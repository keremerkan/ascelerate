import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

/// One file at a time for a localization outside `apps media`'s folder flow: a custom product page
/// localization (`product-pages media`) or a product page optimization treatment localization
/// (`experiments media`). Screenshots and previews go to classic sets; PRODUCT_PAGE_HEADER,
/// APP_STORE_SEARCH_RESULTS and APP_IPHONE_DUO go through the asset library.
extension LocalizationMedia {
  /// `[locale, kind, type, state, media ID]` rows for every screenshot, preview and library placement.
  static func rows(locale: String, on owner: Owner, client: ASCClient) async throws -> [[String]] {
    var rows: [[String]] = []
    for set in try await classicScreenshotSets(on: owner, client: client) {
      // Raw, as `--display-type` takes it.
      let displayType = set.attributes?.screenshotDisplayType ?? "—"
      let shots = try await LocalizationMedia.screenshots(setID: set.id, client: client)
      for s in shots {
        rows.append([locale, "Screenshot", displayType, s.attributes?.assetDeliveryState?.state.map { formatState($0) } ?? "—", s.id])
      }
    }
    for set in try await classicPreviewSets(on: owner, client: client) {
      let previewType = set.attributes?.previewType ?? "—"
      let previews = try await LocalizationMedia.previews(setID: set.id, client: client)
      for p in previews {
        rows.append([locale, "Preview", previewType, p.attributes?.assetDeliveryState?.state.map { formatState($0) } ?? "—", p.id])
      }
    }
    // Asset library placements: header, search results, iPhone Duo.
    for (kind, placement) in try await AssetLibrary.slotPlacements(on: owner, client: client) {
      rows.append([
        locale, placement.attributes?.mediaType == "VIDEO" ? "Video" : "Image", kind,
        placement.attributes?.state.map { formatState($0) } ?? "—", placement.id,
      ])
    }
    return rows
  }

  static let uploadDiscussion = """
    --display-type or --preview-type can also name an asset library slot:
    PRODUCT_PAGE_HEADER or APP_STORE_SEARCH_RESULTS (one image or video, replacing
    the current one) or APP_IPHONE_DUO (a screenshot or app preview, added after the
    existing ones). Sizes are checked against Apple's specs before uploading.
    """

  /// Uploads one screenshot (`displayType`) or preview (`previewType`), or places a library slot
  /// image/video. `context` is the summary's leading lines (e.g. `("Page", name)`). Without an
  /// `owner`, `createOwner` makes the localization once the user has confirmed.
  static func upload(
    file: String, displayType: String?, previewType: String?, previewFrame: String?,
    appID: String, context: [(String, String)], client: ASCClient,
    owner existing: Owner?, createOwner: () async throws -> Owner = { throw ValidationError("No localization to upload to.") }
  ) async throws {
    let media = try MediaFile(readingFrom: file)
    let ext = (media.fileName as NSString).pathExtension.lowercased()
    let isImage = ["png", "jpg", "jpeg"].contains(ext)
    let isVideo = videoExtensions.contains(ext)
    let slotName = [displayType, previewType].compactMap { $0?.uppercased() }.first { AssetLibrary.slots[$0] != nil }
    let slot = slotName.flatMap { AssetLibrary.slots[$0] }

    if let slot {
      guard !isVideo || slot.videoPlacementType != nil else { throw ValidationError("\(slotName ?? "") takes images only.") }
    } else {
      guard isImage || isVideo else {
        throw ValidationError("Unsupported file type '.\(ext)'. Use png/jpg for screenshots or mp4/mov for previews.")
      }
      if isImage && displayType == nil { throw ValidationError("--display-type is required for screenshots (e.g. APP_IPHONE_67).") }
      if isVideo && previewType == nil { throw ValidationError("--preview-type is required for app previews (e.g. APP_IPHONE_67).") }
    }
    let display: ASCEnum.ScreenshotDisplayType? = try slot == nil && isImage ? parseEnum(displayType ?? "", name: "display-type") : nil
    let preview: ASCEnum.PreviewType? = try slot == nil && isVideo ? parseEnum(previewType ?? "", name: "preview-type") : nil

    let current = if let slot, slot.isSingle, let existing {
      try await AssetLibrary.placements(on: existing, type: slot.placementType, group: slot.group, client: client).map(\.id)
    } else { [String]() }

    let what = slot != nil ? (isVideo ? "video" : "image") : (isImage ? "screenshot" : "app preview")
    print(slot != nil ? "Upload \(what) to the asset library:" : "Upload \(what):")
    let width = (context.map(\.0) + ["Type", "File"]).map(\.count).max() ?? 0
    func line(_ label: String, _ value: String) { print("  \((label + ":").padding(toLength: width + 2, withPad: " ", startingAt: 0))\(value)") }
    for (label, value) in context { line(label, value) }
    line(slot != nil ? "Slot" : "Type", (slotName ?? (display?.rawValue ?? preview?.rawValue ?? "—")) + (current.isEmpty ? "" : " (replaces the current one)"))
    line("File", "\(media.fileName) (\(formatBytes(media.fileSize)))")
    print()
    guard confirm("Upload? [y/N] ") else {
      cancelled()
      return
    }
    var owner = existing
    if owner == nil { owner = try await createOwner() }
    guard let owner else { return }

    if let slot {
      let libraryID = try await AssetLibrary.libraryID(appID: appID, client: client)
      let placementID = try await AssetLibrary.uploadAndPlace(media, slot: slot, on: owner, libraryID: libraryID, replacing: current, client: client)
      print()
      success("Uploaded", "\(what) (placement id: \(placementID)).")
      return
    }

    let mediaID: String
    if let display {
      var setID = try await screenshotSets(on: owner, client: client).first { $0.attributes?.screenshotDisplayType == display.rawValue }?.id
      if setID == nil { setID = try await ClassicMedia.createScreenshotSet(display, owner: owner, client: client) }
      mediaID = try await ClassicMedia.uploadScreenshot(media, setID: setID ?? "", client: client)
    } else if let preview {
      var setID = try await previewSets(on: owner, client: client).first { $0.attributes?.previewType == preview.rawValue }?.id
      if setID == nil { setID = try await ClassicMedia.createPreviewSet(preview, owner: owner, client: client) }
      mediaID = try await ClassicMedia.uploadPreview(media, setID: setID ?? "", previewFrame: previewFrame, client: client)
    } else {
      return
    }
    print()
    success("Uploaded", "\(what) (id: \(mediaID)).")
  }

  /// Deletes a screenshot, preview or library placement found on one of `owners`.
  static func delete(mediaID: String, among owners: [Owner], client: ASCClient) async throws {
    for owner in owners {
      for set in try await classicScreenshotSets(on: owner, client: client) {
        let shots = try await LocalizationMedia.screenshots(setID: set.id, client: client)
        if shots.contains(where: { $0.id == mediaID }) {
          guard confirm("Delete this screenshot? [y/N] ") else { return cancelled() }
          try await ClassicMedia.deleteScreenshot(mediaID, client: client)
          print()
          return success("Deleted", "screenshot \(mediaID).")
        }
      }
      for set in try await classicPreviewSets(on: owner, client: client) {
        let previews = try await LocalizationMedia.previews(setID: set.id, client: client)
        if previews.contains(where: { $0.id == mediaID }) {
          guard confirm("Delete this preview? [y/N] ") else { return cancelled() }
          try await ClassicMedia.deletePreview(mediaID, client: client)
          print()
          return success("Deleted", "preview \(mediaID).")
        }
      }
      // An asset library placement: removing it also deletes its image or video from the
      // library when nothing else uses it.
      if let match = try await AssetLibrary.slotPlacements(on: owner, client: client).first(where: { $0.placement.id == mediaID }) {
        guard confirm("Remove this \(match.kind) placement? [y/N] ") else { return cancelled() }
        let deleted = try await AssetLibrary.removePlacement(id: mediaID, client: client)
        print()
        return success("Removed", "\(match.kind) placement \(mediaID)\(deleted ? " and its unused library file" : "").")
      }
    }
    throw ValidationError("Media '\(mediaID)' not found.")
  }
}
