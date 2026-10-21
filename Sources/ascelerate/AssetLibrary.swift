import ASCKit
import AscelerateCore
import Foundation
import AVFoundation
import ImageIO

/// Checking files for, uploading to and placing in the App Asset Library, and removing placements
/// (the rest of it, deleting unused assets included, is in AscelerateCore).
extension AssetLibrary {
  /// Throws if the image's pixel size or file type is not one the slot accepts.
  static func validateSize(of file: MediaFile, slot: Slot) throws {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: file.path) as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else {
      throw MediaUploadError.cannotReadFile(file.path)
    }
    let fileExtension = (file.fileName as NSString).pathExtension.lowercased()
    guard slot.imageSpecs.contains(where: { $0.accepts(width: width, height: height, fileExtension: fileExtension) }) else {
      throw MediaUploadError.unsupportedImage(
        "\(width)×\(height) \(fileExtension.uppercased())", accepted: slot.imageSpecs.map(\.description))
    }
  }

  /// Throws if the video's size, length, frame rate, audio or file type is not one the slot
  /// accepts.
  static func validateVideo(_ file: MediaFile, slot: Slot) async throws {
    let asset = AVURLAsset(url: URL(fileURLWithPath: file.path))
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
      throw MediaUploadError.cannotReadFile(file.path)
    }
    let (naturalSize, transform, fps) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
    let size = naturalSize.applying(transform)
    let width = Int(abs(size.width).rounded()), height = Int(abs(size.height).rounded())
    let seconds = try await asset.load(.duration).seconds
    let hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
    let fileExtension = (file.fileName as NSString).pathExtension.lowercased()
    guard slot.videoSpecs.contains(where: {
      $0.accepts(width: width, height: height, seconds: seconds, fps: Double(fps), hasAudio: hasAudio, fileExtension: fileExtension)
    }) else {
      let found = "\(width)×\(height), \(String(format: "%.1f", seconds)) s at \(String(format: "%g", (fps * 100).rounded() / 100)) fps\(hasAudio ? " with audio" : " without audio")"
      throw MediaUploadError.unsupportedVideo(found, accepted: slot.videoSpecs.map(\.description))
    }
  }

  /// Validates, uploads and places one file in `slot` on `owner`: images under the slot's
  /// placement type, videos under its video placement type. The `current` placements (a single
  /// slot's existing one) are removed once the file is uploaded, so a failed upload leaves the
  /// slot as it was. Under dry run nothing is reserved, and a placeholder ID lets the placement be
  /// previewed. Returns the new placement's ID.
  static func uploadAndPlace(
    _ file: MediaFile, slot: Slot, on owner: Owner, libraryID: String, replacing current: [String] = [],
    client: ASCClient
  ) async throws -> String {
    let asset: Asset
    let type: PlacementType
    if videoExtensions.contains((file.fileName as NSString).pathExtension.lowercased()), let videoType = slot.videoPlacementType {
      try await validateVideo(file, slot: slot)
      asset = .video(try await unlessDryRunStopped {
        try await uploadVideo(file, category: slot.category, libraryID: libraryID, client: client)
      } ?? "DRY-RUN-VIDEO")
      type = videoType
    } else {
      try validateSize(of: file, slot: slot)
      asset = .image(try await unlessDryRunStopped {
        try await uploadImage(file, category: slot.category, libraryID: libraryID, client: client)
      } ?? "DRY-RUN-IMAGE")
      type = slot.placementType
    }
    for placementID in current {
      try await removePlacement(id: placementID, client: client)
    }
    return try await place(asset, on: owner, type: type, group: slot.group, client: client)
  }

  /// The library assets behind a localization's classic screenshot or preview set: its items are
  /// the placements of `type` (screenshot or preview) in the display type's group
  /// (`displayTypeGroups`). Read them before the set is cleared; deleting a classic item leaves
  /// its library asset behind, and the classic API has no link from item to asset.
  static func classicSetAssets(
    localizationID: String, displayType: String, type: PlacementType, client: ASCClient
  ) async throws -> [Asset] {
    guard let group = displayTypeGroups[displayType] else { return [] }
    return try await placementsWithMedia(on: .versionLocalization(localizationID), type: type, group: group, client: client)
      .compactMap { placed in placed.image.map { .image($0.id) } ?? placed.video.map { .video($0.id) } }
  }

  /// Removes a placement, then deletes its library asset when nothing uses it any more: a removed
  /// placement leaves its asset in the library otherwise (seen live). Returns whether the asset
  /// was deleted. Under dry run the delete is shown and not sent, and the asset is kept.
  @discardableResult
  static func removePlacement(id: String, client: ASCClient) async throws -> Bool {
    let asset = try await placedAsset(placementID: id, client: client).asset
    guard try await unlessDryRunStopped({ try await deletePlacement(id: id, client: client) }) != nil,
      let asset
    else { return false }
    return try await deleteIfUnused(asset, client: client)
  }
}
