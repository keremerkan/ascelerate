import ASCKit
import Foundation

/// What a version's screenshots and app previews download as, in the folder layout uploads read
/// (`<locale>/<display type or slot>/<file>`): for each language its classic screenshot sets,
/// its asset library images (iPhone Duo, header, search results) and its app preview sets.
public enum MediaDownload {
  public enum Kind: Sendable {
    case screenshots, previews
  }

  /// One set's files, in display order.
  public struct MediaSet: Sendable {
    public let locale: String
    /// The set's folder: a display type (APP_IPHONE_67), a library slot (APP_IPHONE_DUO), or a
    /// preview set's display type (APP_ + its preview type).
    public let folder: String
    public let kind: Kind
    public let files: [File]
    /// Library videos left out: App Store Connect gives no download URL for them (header and
    /// search results videos; Duo previews come with the preview sets).
    public let skippedVideos: Int
  }

  public struct File: Sendable {
    /// The name to save it as.
    public let fileName: String
    /// The name App Store Connect has, for messages.
    public let originalName: String
    /// Where to download it from, or why it can't be.
    public let source: Result<URL, DownloadError>
  }

  public enum DownloadError: LocalizedError, Sendable {
    case invalidURL(String)
    case noURL(String)

    public var errorDescription: String? {
      switch self {
        case .invalidURL(let url): "Invalid download URL: \(url)"
        case .noURL(let fileName): "No download URL available for '\(fileName)'."
      }
    }
  }

  /// The version's languages (only `locales`, lowercase codes, when given), each with its sets, in
  /// the order above; only the sets of `folders` when given. Empty sets are left out.
  public static func plan(
    versionID: String, locales: Set<String>? = nil, folders: Set<String>? = nil, client: ASCClient
  ) async throws -> [(locale: String, sets: [MediaSet])] {
    let localizations = try await client.appStoreVersionsAppStoreVersionLocalizationsGetToManyRelated(
      path: .init(id: versionID)
    ).ok.body.json.data
    var result: [(locale: String, sets: [MediaSet])] = []
    for localization in localizations {
      guard let locale = localization.attributes?.locale, locales?.contains(locale.lowercased()) ?? true else { continue }
      result.append((locale, try await sets(localizationID: localization.id, locale: locale, folders: folders, client: client)))
    }
    return result
  }

  /// A language's sets: classic screenshots, library images, previews (only those of `folders`
  /// when given).
  public static func sets(
    localizationID: String, locale: String, folders: Set<String>? = nil, client: ASCClient
  ) async throws -> [MediaSet] {
    func wanted(_ folder: String) -> Bool { folders?.contains(folder) ?? true }
    var sets: [MediaSet] = []
    let screenshotSets = try await client.appStoreVersionLocalizationsAppScreenshotSetsGetToManyRelated(
      path: .init(id: localizationID), query: .init(limit: 50)
    ).ok.body.json.data
    for set in screenshotSets {
      // Library folders (iPhone Duo) come from their placements below; the classic API mirrors
      // Duo screenshots only once they're active.
      guard let displayType = set.attributes?.screenshotDisplayType, AssetLibrary.slots[displayType] == nil, wanted(displayType) else { continue }
      let screenshots = try await client.appScreenshotSetsAppScreenshotsGetToManyRelated(path: .init(id: set.id)).ok.body.json.data
      guard !screenshots.isEmpty else { continue }
      let files = screenshots.enumerated().map { i, screenshot in
        // Server-supplied name: path separators go before it makes a local path.
        let originalName = (screenshot.attributes?.fileName ?? "\(screenshot.id).png").replacingOccurrences(of: "/", with: "_")
        let asset = screenshot.attributes?.imageAsset
        return File(
          fileName: String(format: "%02d_%@", i + 1, originalName), originalName: originalName,
          source: imageSource(asset?.templateUrl, width: asset?.width, height: asset?.height, fileName: originalName))
      }
      sets.append(MediaSet(locale: locale, folder: displayType, kind: .screenshots, files: files, skippedVideos: 0))
    }

    // Library images, from their placements (one request per slot). Library videos have no
    // download URL (videoAsset stays empty, seen live).
    for (kind, slot) in AssetLibrary.slots.sorted(by: { $0.key < $1.key }) where wanted(kind) {
      let placements = try await AssetLibrary.placementsWithMedia(
        on: .versionLocalization(localizationID), type: slot.placementType, group: slot.group, client: client)
      let images = placements.compactMap(\.image)
      let skipped = slot.isSingle ? placements.count - images.count : 0
      // Names that are unique and already sort into display order are kept, so the folder
      // round-trips through upload and verify; otherwise each gets its position as a prefix.
      let names = images.map { ($0.attributes?.common.fileName ?? "\($0.id).png").replacingOccurrences(of: "/", with: "_") }
      let keepNames = Set(names).count == names.count && names == names.sorted()
      let files = images.enumerated().map { i, image in
        let asset = image.attributes?.common.imageAsset
        return File(
          fileName: keepNames ? names[i] : String(format: "%02d_%@", i + 1, names[i]), originalName: names[i],
          source: imageSource(asset?.templateUrl, width: asset?.width, height: asset?.height, fileName: names[i]))
      }
      if !files.isEmpty || skipped > 0 {
        sets.append(MediaSet(locale: locale, folder: kind, kind: .screenshots, files: files, skippedVideos: skipped))
      }
    }

    let previewSets = try await client.appStoreVersionLocalizationsAppPreviewSetsGetToManyRelated(
      path: .init(id: localizationID), query: .init(limit: 50)
    ).ok.body.json.data
    for set in previewSets {
      guard let previewType = set.attributes?.previewType, wanted("APP_\(previewType)") else { continue }
      let previews = try await client.appPreviewSetsAppPreviewsGetToManyRelated(path: .init(id: set.id)).ok.body.json.data
      guard !previews.isEmpty else { continue }
      let files = previews.enumerated().map { i, preview in
        let originalName = (preview.attributes?.fileName ?? "\(preview.id).mp4").replacingOccurrences(of: "/", with: "_")
        let source: Result<URL, DownloadError> =
          if let string = preview.attributes?.videoUrl {
            URL(string: string).map { .success($0) } ?? .failure(.invalidURL(string))
          } else {
            .failure(.noURL(originalName))
          }
        return File(fileName: String(format: "%02d_%@", i + 1, originalName), originalName: originalName, source: source)
      }
      // Preview sets are named after their preview type; their folder is the display type's.
      sets.append(MediaSet(locale: locale, folder: "APP_\(previewType)", kind: .previews, files: files, skippedVideos: 0))
    }
    return sets
  }

  /// Downloads a file to `destination`, replacing a file already there.
  public static func download(_ file: File, to destination: URL) async throws {
    let url = try file.source.get()
    let (temporary, _) = try await URLSession.shared.download(from: url)
    let manager = FileManager.default
    if manager.fileExists(atPath: destination.path(percentEncoded: false)) {
      try manager.removeItem(at: destination)
    }
    try manager.moveItem(at: temporary, to: destination)
  }

  /// An image's URL from its template (`{w}x{h}bb.{f}`), as JPEG for a .jpg/.jpeg file and PNG
  /// otherwise.
  public static func imageURL(templateURL: String, width: Int, height: Int, fileName: String) -> String {
    let ext = (fileName as NSString).pathExtension.lowercased()
    let format = (ext == "jpg" || ext == "jpeg") ? "jpg" : "png"
    return templateURL
      .replacingOccurrences(of: "{w}", with: "\(width)")
      .replacingOccurrences(of: "{h}", with: "\(height)")
      .replacingOccurrences(of: "{f}", with: format)
  }

  private static func imageSource(_ template: String?, width: Int?, height: Int?, fileName: String) -> Result<URL, DownloadError> {
    guard let template else { return .failure(.noURL(fileName)) }
    let string = imageURL(templateURL: template, width: width ?? 0, height: height ?? 0, fileName: fileName)
    return URL(string: string).map { .success($0) } ?? .failure(.invalidURL(string))
  }
}
