import ArgumentParser
import ASCKit
import CryptoKit
import Foundation

// MARK: - Media Types

struct MediaFile {
  let path: String
  let fileName: String
  let fileSize: Int
}

struct DisplayTypeMedia {
  let folderName: String
  let screenshotDisplayType: ASCEnum.ScreenshotDisplayType?
  let previewType: ASCEnum.PreviewType?
  let screenshots: [MediaFile]
  let previews: [MediaFile]
}

struct LocaleMedia {
  let locale: String
  let displayTypes: [DisplayTypeMedia]
}

struct MediaUploadPlan {
  let locales: [LocaleMedia]
  let warnings: [String]
  var totalScreenshots: Int
  var totalPreviews: Int
}

// MARK: - Folder Scanning

private let imageExtensions: Set<String> = ["png", "jpg", "jpeg"]
private let videoExtensions: Set<String> = ["mp4", "mov"]

func scanMediaFolder(at path: String) throws -> MediaUploadPlan {
  let fm = FileManager.default
  let expandedPath = expandPath(path)

  var isDir: ObjCBool = false
  guard fm.fileExists(atPath: expandedPath, isDirectory: &isDir), isDir.boolValue else {
    throw ValidationError("Folder not found at '\(expandedPath)'.")
  }

  var locales: [LocaleMedia] = []
  var warnings: [String] = []
  var totalScreenshots = 0
  var totalPreviews = 0

  let localeContents = try fm.contentsOfDirectory(atPath: expandedPath).sorted()

  for localeName in localeContents {
    let localePath = (expandedPath as NSString).appendingPathComponent(localeName)
    var isLocalDir: ObjCBool = false
    guard fm.fileExists(atPath: localePath, isDirectory: &isLocalDir), isLocalDir.boolValue else {
      continue
    }

    var displayTypes: [DisplayTypeMedia] = []
    let displayTypeContents = try fm.contentsOfDirectory(atPath: localePath).sorted()

    for displayTypeName in displayTypeContents {
      let displayTypePath = (localePath as NSString).appendingPathComponent(displayTypeName)
      var isDTDir: ObjCBool = false
      guard fm.fileExists(atPath: displayTypePath, isDirectory: &isDTDir), isDTDir.boolValue else {
        continue
      }

      let screenshotType = ASCEnum.ScreenshotDisplayType(rawValue: displayTypeName)
      let pvType = previewTypeForDisplayType(displayTypeName)

      let slot = AssetLibrary.slots[displayTypeName]
      if screenshotType == nil && slot == nil {
        warnings.append("[\(localeName)] Skipping unknown display type '\(displayTypeName)'.")
        continue
      }

      var screenshots: [MediaFile] = []
      var previews: [MediaFile] = []

      let files = try fm.contentsOfDirectory(atPath: displayTypePath).sorted()
      for fileName in files {
        guard !fileName.hasPrefix(".") else { continue }

        let filePath = (displayTypePath as NSString).appendingPathComponent(fileName)
        let ext = (fileName as NSString).pathExtension.lowercased()

        let attrs = try fm.attributesOfItem(atPath: filePath)
        let fileSize = (attrs[.size] as? Int) ?? 0

        if imageExtensions.contains(ext) {
          screenshots.append(
            MediaFile(path: filePath, fileName: fileName, fileSize: fileSize))
        } else if videoExtensions.contains(ext) {
          if pvType != nil {
            previews.append(
              MediaFile(path: filePath, fileName: fileName, fileSize: fileSize))
          } else {
            warnings.append(
              "[\(localeName)/\(displayTypeName)] Skipping '\(fileName)' — no preview support for this display type."
            )
          }
        } else {
          warnings.append(
            "[\(localeName)/\(displayTypeName)] Skipping '\(fileName)' — unsupported file type.")
        }
      }

      if slot?.isSingle == true && screenshots.count > 1 {
        throw ValidationError(
          "\(localeName)/\(displayTypeName) holds one image per locale, but the folder has \(screenshots.count).")
      }
      if !screenshots.isEmpty || !previews.isEmpty {
        totalScreenshots += screenshots.count
        totalPreviews += previews.count
        displayTypes.append(
          DisplayTypeMedia(
            folderName: displayTypeName,
            screenshotDisplayType: screenshotType,
            previewType: pvType,
            screenshots: screenshots,
            previews: previews
          ))
      }
    }

    if !displayTypes.isEmpty {
      locales.append(LocaleMedia(locale: localeName, displayTypes: displayTypes))
    }
  }

  return MediaUploadPlan(
    locales: locales,
    warnings: warnings,
    totalScreenshots: totalScreenshots,
    totalPreviews: totalPreviews
  )
}

func previewTypeForDisplayType(_ rawValue: String) -> ASCEnum.PreviewType? {
  if rawValue.hasPrefix("APP_WATCH_") || rawValue.hasPrefix("IMESSAGE_") {
    return nil
  }
  guard rawValue.hasPrefix("APP_") else { return nil }
  let previewRaw = String(rawValue.dropFirst(4))
  return ASCEnum.PreviewType(rawValue: previewRaw)
}

/// The App Store version platform a screenshot display type belongs to.
/// Watch and iMessage display types ride along iOS app versions.
func platformForDisplayType(_ rawValue: String) -> Platform {
  if rawValue == "APP_DESKTOP" { return .macOs }
  if rawValue.hasPrefix("APP_APPLE_TV") { return .tvOs }
  if rawValue.hasPrefix("APP_APPLE_VISION") { return .visionOs }
  return .ios
}

/// Filters an upload plan to the display types that belong to the target version's
/// platform — ASC rejects foreign sets with HTTP 409 (e.g. APP_DESKTOP on an iOS
/// version), so mixed exports must route cleanly per platform.
/// Returns the filtered plan and the skipped display-type names.
func filterPlan(_ plan: MediaUploadPlan, platform: Platform?) -> (plan: MediaUploadPlan, skippedTypes: [String]) {
  guard let platform else { return (plan, []) }
  var skipped = Set<String>()
  var locales: [LocaleMedia] = []
  var totalScreenshots = 0
  var totalPreviews = 0
  for localeMedia in plan.locales {
    let kept = localeMedia.displayTypes.filter { dt in
      guard AssetLibrary.slots[dt.folderName]?.isPlatformIndependent == true
        || platformForDisplayType(dt.folderName) == platform
      else {
        skipped.insert(dt.folderName)
        return false
      }
      return true
    }
    guard !kept.isEmpty else { continue }
    totalScreenshots += kept.reduce(0) { $0 + $1.screenshots.count }
    totalPreviews += kept.reduce(0) { $0 + $1.previews.count }
    locales.append(LocaleMedia(locale: localeMedia.locale, displayTypes: kept))
  }
  return (
    MediaUploadPlan(
      locales: locales, warnings: plan.warnings,
      totalScreenshots: totalScreenshots, totalPreviews: totalPreviews),
    skipped.sorted()
  )
}

// MARK: - Upload Helpers

/// An upload operation's fields as `uploadChunks` reads them.
protocol UploadOperationDescribing {
  var url: String? { get }
  var method: String? { get }
  var offset: Int? { get }
  var length: Int? { get }
  var headers: [(name: String, value: String)] { get }
}

extension Components.Schemas.UploadOperation: UploadOperationDescribing {
  var headers: [(name: String, value: String)] {
    (requestHeaders ?? []).compactMap { header in header.name.flatMap { name in header.value.map { (name, $0) } } }
  }
}

/// Live byte progress for an upload, drawn in place after whatever the current line shows and
/// erased when the upload ends, so the caller's "Done." lands where it would have. Bytes come
/// from URLSession's task delegate, which reports them as they go out.
final class UploadProgressLine: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private let total: Int64
  /// Bytes of the chunks already uploaded.
  private var base: Int64 = 0
  private var shownPercent = -1
  private var isActive = true

  init(totalBytes: Int64) {
    total = totalBytes
    super.init()
    write("\u{1B}7")  // save the cursor position
  }

  /// Counts a finished chunk; a retried chunk starts again from its own beginning.
  func chunkFinished(length: Int64) {
    lock.withLock { base += length }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64, totalBytesExpectedToSend: Int64
  ) {
    lock.withLock {
      guard isActive, total > 0 else { return }
      let sent = min(base + totalBytesSent, total)
      let percent = Int(sent * 100 / total)
      guard percent != shownPercent else { return }
      shownPercent = percent
      // Restore the cursor, clear to the end of the line, draw.
      write("\u{1B}8\u{1B}[K\(percent)% (\(formatBytes(Int(sent))) of \(formatBytes(Int(total))))")
    }
  }

  /// Erases the progress, leaving the cursor where the line's text ended.
  func finish() {
    lock.withLock {
      isActive = false
      write("\u{1B}8\u{1B}[K")
    }
  }

  private func write(_ text: String) {
    fputs(text, stdout)
    fflush(stdout)
  }
}

func uploadChunks<Operation: UploadOperationDescribing>(filePath: String, operations: [Operation]) async throws {
  guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
    throw MediaUploadError.cannotReadFile(filePath)
  }
  defer { try? fileHandle.close() }

  fflush(stdout)
  let progress = isTerminal
    ? UploadProgressLine(totalBytes: operations.reduce(0) { $0 + Int64($1.length ?? 0) })
    : nil
  defer { progress?.finish() }

  for operation in operations {
    guard let urlString = operation.url,
      let url = URL(string: urlString),
      let method = operation.method,
      let offset = operation.offset,
      let length = operation.length
    else {
      throw MediaUploadError.invalidUploadOperation
    }

    try fileHandle.seek(toOffset: UInt64(offset))
    let chunkData = fileHandle.readData(ofLength: length)

    var request = URLRequest(url: url)
    request.httpMethod = method
    for header in operation.headers {
      request.setValue(header.value, forHTTPHeaderField: header.name)
    }

    // The storage host rate-limits bursts (HTTP 429 seen live after ~180 sequential uploads);
    // retry 429/5xx with backoff, honoring Retry-After, and dropped or timed-out connections.
    // A chunk PUT to its presigned URL is safe to repeat.
    var delays: [Double] = [2, 5, 15, 30]
    while true {
      let response: URLResponse
      do {
        (_, response) = try await URLSession.shared.upload(for: request, from: chunkData, delegate: progress)
      } catch where isTransientError(error) && !delays.isEmpty {
        try await Task.sleep(for: .seconds(delays.removeFirst()))
        continue
      }
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
      if (200...299).contains(statusCode) {
        progress?.chunkFinished(length: Int64(length))
        break
      }
      guard statusCode == 429 || (500...599).contains(statusCode), !delays.isEmpty else {
        throw MediaUploadError.chunkUploadFailed(statusCode)
      }
      let delay = delays.removeFirst()
      let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
      try await Task.sleep(for: .seconds(min(retryAfter ?? delay, 60)))
    }
  }
}

func md5Hex(filePath: String) throws -> String {
  guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
    throw MediaUploadError.cannotReadFile(filePath)
  }
  defer { try? fileHandle.close() }

  var md5 = Insecure.MD5()
  let bufferSize = 1024 * 1024

  while true {
    let data = fileHandle.readData(ofLength: bufferSize)
    if data.isEmpty { break }
    md5.update(data: data)
  }

  let digest = md5.finalize()
  return digest.map { String(format: "%02x", $0) }.joined()
}

extension MediaFile {
  /// Reads a file's name and size from disk, expanding `~` in the path.
  init(readingFrom file: String) throws {
    let path = expandPath(file)
    let attrs = try FileManager.default.attributesOfItem(atPath: path)
    self.path = path
    self.fileName = (path as NSString).lastPathComponent
    self.fileSize = (attrs[.size] as? Int) ?? 0
  }
}

/// Runs the App Store Connect 3-step asset upload protocol shared by app screenshots/previews,
/// IAP/subscription promotional images, and App Review screenshots:
/// reserve → upload chunks → commit with checksum.
///
/// - Parameters:
///   - reserve: performs the create POST; returns the new asset's ID and its upload operations.
///   - commit: performs the PATCH marking the asset uploaded, given the ID and computed MD5 checksum.
/// - Returns: the new asset's ID.
func uploadAsset<Operation: UploadOperationDescribing>(
  filePath: String,
  reserve: () async throws -> (id: String, operations: [Operation]),
  commit: (_ id: String, _ md5: String) async throws -> Void
) async throws -> String {
  let (id, operations) = try await reserve()
  guard !operations.isEmpty else {
    throw MediaUploadError.noUploadOperations
  }
  try await uploadChunks(filePath: filePath, operations: operations)
  let md5 = try md5Hex(filePath: filePath)
  // The commit PATCH only marks the asset uploaded, so it is safe to repeat.
  try await withTransientRetry { try await commit(id, md5) }
  return id
}

func mediaMimeType(for fileName: String) -> String {
  let ext = (fileName as NSString).pathExtension.lowercased()
  switch ext {
  case "mp4": return "video/mp4"
  case "mov": return "video/quicktime"
  default: return "application/octet-stream"
  }
}

/// Per-set file counts for `media upload`.
struct UploadTally {
  var succeeded = 0
  var failed = 0
  /// Files whose first write dry run stopped.
  var notSent = 0

  var total: Int { succeeded + failed + notSent }

  /// Runs one file's upload and counts it: done, failed, or not sent under dry run.
  mutating func record(_ upload: () async throws -> Void) async {
    do {
      try await upload()
      print("Done.")
      succeeded += 1
    } catch where ASCDryRunStop.from(error) != nil {
      print("Not sent (dry run).")
      notSent += 1
    } catch {
      print("Failed: \(describeError(error))")
      failed += 1
    }
  }

  mutating func add(_ other: UploadTally) {
    succeeded += other.succeeded
    failed += other.failed
    notSent += other.notSent
  }

  var summary: String {
    var parts: [String] = []
    if succeeded > 0 || total == 0 { parts.append(green("\(succeeded) succeeded")) }
    if notSent > 0 { parts.append("\(notSent) not sent") }
    if failed > 0 { parts.append(red("\(failed) failed")) }
    return parts.joined(separator: ", ")
  }
}

/// Prints how many existing items a `--replace` removed (or, under dry run, would remove).
func printDeleted(_ count: Int, _ noun: String) {
  guard count > 0 else { return }
  print("    \(ClientFactory.isDryRun ? "Would delete" : "Deleted") \(count) existing \(noun)\(count == 1 ? "" : "s").")
}

/// Numbers the files of a whole `media upload` run: each file's line starts with `[n/total]`.
struct UploadCounter {
  let total: Int
  private var current = 0

  init(total: Int) { self.total = total }

  /// Prints the start of the next file's line, e.g. `    [ 57/203] Screenshot 1/7: 01_hero.png... `.
  mutating func printLine(_ kind: String, _ index: Int, of count: Int, _ fileName: String) {
    current += 1
    let width = String(total).count
    let position = String(repeating: " ", count: max(0, width - String(current).count)) + String(current)
    print("    [\(position)/\(total)] \(kind) \(index + 1)/\(count): \(fileName)... ", terminator: "")
    fflush(stdout)
  }
}

/// Uploads images through the asset library and places them in `slot`, in file order
/// (placements keep their creation order). A single-image slot's current placements are removed
/// once the new image is uploaded, so a failed upload leaves the slot as it was. Returns the
/// counts and the IDs of the placements created.
func placeAssetLibraryImages(
  _ files: [MediaFile], slot: AssetLibrary.Slot, localizationID: String, libraryID: String,
  replacing current: [String] = [], counter: inout UploadCounter, client: ASCClient
) async -> (tally: UploadTally, placementIDs: [String]) {
  var tally = UploadTally()
  var placementIDs: [String] = []
  for (i, file) in files.enumerated() {
    counter.printLine(slot.fileLabel, i, of: files.count, file.fileName)
    await tally.record {
      try AssetLibrary.validateSize(of: file, slot: slot)
      // Under dry run the image is never reserved; a placeholder lets the placement be previewed.
      let imageID = try await unlessDryRunStopped {
        try await AssetLibrary.uploadImage(file, category: slot.category, libraryID: libraryID, client: client)
      } ?? "DRY-RUN-IMAGE"
      for placementID in current {
        try await AssetLibrary.removePlacement(id: placementID, client: client)
      }
      placementIDs.append(try await AssetLibrary.placeImage(
        imageID: imageID, localizationID: localizationID, slot: slot, client: client))
    }
  }
  return (tally, placementIDs)
}

// MARK: - Screenshot and Preview Writes

/// Writes to classic screenshot and preview sets, shared by `apps media` (version
/// localizations) and `product-pages media` (custom product page localizations).
enum ClassicMedia {
  /// The localization a new set is created under.
  enum Owner {
    case versionLocalization(String)
    case productPageLocalization(String)
  }

  static func createScreenshotSet(
    _ displayType: ASCEnum.ScreenshotDisplayType, owner: Owner, client: ASCClient
  ) async throws -> String {
    typealias Relationships = Components.Schemas.AppScreenshotSetCreateRequest.DataPayload.RelationshipsPayload
    let relationships: Relationships
    switch owner {
    case .versionLocalization(let id):
      relationships = .init(appStoreVersionLocalization: .init(data: .init(id: id, _type: "appStoreVersionLocalizations")))
    case .productPageLocalization(let id):
      relationships = .init(appCustomProductPageLocalization: .init(data: .init(id: id, _type: "appCustomProductPageLocalizations")))
    }
    return try await client.appScreenshotSetsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(screenshotDisplayType: displayType.rawValue),
      relationships: relationships,
      _type: "appScreenshotSets"
    )))).created.body.json.data.id
  }

  static func createPreviewSet(
    _ previewType: ASCEnum.PreviewType, owner: Owner, client: ASCClient
  ) async throws -> String {
    typealias Relationships = Components.Schemas.AppPreviewSetCreateRequest.DataPayload.RelationshipsPayload
    let relationships: Relationships
    switch owner {
    case .versionLocalization(let id):
      relationships = .init(appStoreVersionLocalization: .init(data: .init(id: id, _type: "appStoreVersionLocalizations")))
    case .productPageLocalization(let id):
      relationships = .init(appCustomProductPageLocalization: .init(data: .init(id: id, _type: "appCustomProductPageLocalizations")))
    }
    return try await client.appPreviewSetsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(previewType: previewType.rawValue),
      relationships: relationships,
      _type: "appPreviewSets"
    )))).created.body.json.data.id
  }

  /// Reserves, uploads and commits a screenshot in `setID`; returns its ID.
  static func uploadScreenshot(_ file: MediaFile, setID: String, client: ASCClient) async throws -> String {
    try await uploadAsset(
      filePath: file.path,
      reserve: {
        let response = try await client.appScreenshotsCreateInstance(body: .json(.init(data: .init(
          attributes: .init(fileName: file.fileName, fileSize: file.fileSize),
          relationships: .init(appScreenshotSet: .init(data: .init(id: setID, _type: "appScreenshotSets"))),
          _type: "appScreenshots"
        )))).created.body.json
        return (response.data.id, response.data.attributes?.uploadOperations ?? [])
      },
      commit: { id, md5 in
        _ = try await client.appScreenshotsUpdateInstance(
          path: .init(id: id),
          body: .json(.init(data: .init(
            attributes: .init(sourceFileChecksum: md5, uploaded: true), id: id, _type: "appScreenshots")))
        ).ok
      })
  }

  /// Reserves, uploads and commits an app preview in `setID`; returns its ID.
  static func uploadPreview(
    _ file: MediaFile, setID: String, previewFrame: String? = nil, client: ASCClient
  ) async throws -> String {
    try await uploadAsset(
      filePath: file.path,
      reserve: {
        let response = try await client.appPreviewsCreateInstance(body: .json(.init(data: .init(
          attributes: .init(
            fileName: file.fileName, fileSize: file.fileSize, mimeType: mediaMimeType(for: file.fileName),
            previewFrameTimeCode: previewFrame),
          relationships: .init(appPreviewSet: .init(data: .init(id: setID, _type: "appPreviewSets"))),
          _type: "appPreviews"
        )))).created.body.json
        return (response.data.id, response.data.attributes?.uploadOperations ?? [])
      },
      commit: { id, md5 in
        _ = try await client.appPreviewsUpdateInstance(
          path: .init(id: id),
          body: .json(.init(data: .init(
            attributes: .init(previewFrameTimeCode: previewFrame, sourceFileChecksum: md5, uploaded: true),
            id: id, _type: "appPreviews")))
        ).ok
      })
  }

  static func deleteScreenshot(_ id: String, client: ASCClient) async throws {
    _ = try await client.appScreenshotsDeleteInstance(path: .init(id: id)).noContent
  }

  static func deletePreview(_ id: String, client: ASCClient) async throws {
    _ = try await client.appPreviewsDeleteInstance(path: .init(id: id)).noContent
  }

  static func deleteScreenshotSet(_ id: String, client: ASCClient) async throws {
    _ = try await client.appScreenshotSetsDeleteInstance(path: .init(id: id)).noContent
  }

  static func deletePreviewSet(_ id: String, client: ASCClient) async throws {
    _ = try await client.appPreviewSetsDeleteInstance(path: .init(id: id)).noContent
  }

  /// Deletes every screenshot in a set; returns how many there were. Under dry run the
  /// stopped deletes count as done.
  static func deleteAllScreenshots(inSet setID: String, client: ASCClient) async throws -> Int {
    let screenshots = try await client.appScreenshotSetsAppScreenshotsGetToManyRelated(path: .init(id: setID)).ok.body.json.data
    for screenshot in screenshots { _ = try await unlessDryRunStopped { try await deleteScreenshot(screenshot.id, client: client) } }
    return screenshots.count
  }

  /// Deletes every preview in a set; returns how many there were. Under dry run the
  /// stopped deletes count as done.
  static func deleteAllPreviews(inSet setID: String, client: ASCClient) async throws -> Int {
    let previews = try await client.appPreviewSetsAppPreviewsGetToManyRelated(path: .init(id: setID)).ok.body.json.data
    for preview in previews { _ = try await unlessDryRunStopped { try await deletePreview(preview.id, client: client) } }
    return previews.count
  }

  /// Sets the order of a screenshot set's screenshots.
  static func reorderScreenshots(setID: String, ids: [String], client: ASCClient) async throws {
    _ = try await client.appScreenshotSetsAppScreenshotsReplaceToManyRelationship(
      path: .init(id: setID),
      body: .json(.init(data: ids.map { .init(id: $0, _type: "appScreenshots") }))
    ).noContent
  }

  /// Sets the order of a preview set's previews.
  static func reorderPreviews(setID: String, ids: [String], client: ASCClient) async throws {
    _ = try await client.appPreviewSetsAppPreviewsReplaceToManyRelationship(
      path: .init(id: setID),
      body: .json(.init(data: ids.map { .init(id: $0, _type: "appPreviews") }))
    ).noContent
  }
}

enum MediaUploadError: LocalizedError {
  case cannotReadFile(String)
  case invalidUploadOperation
  case chunkUploadFailed(Int)
  case noUploadOperations
  case unsupportedImage(String, accepted: [String])

  var errorDescription: String? {
    switch self {
    case .unsupportedImage(let image, let accepted):
      return "A \(image) image is not accepted here; use \(accepted.joined(separator: ", "))."
    case .cannotReadFile(let path):
      return "Cannot read file at '\(path)'."
    case .invalidUploadOperation:
      return "Upload operation missing required fields."
    case .chunkUploadFailed(let statusCode):
      return "Chunk upload failed with status \(statusCode)."
    case .noUploadOperations:
      return "No upload operations returned by the API."
    }
  }
}

enum MediaDownloadError: LocalizedError {
  case invalidURL(String)
  case noURL(String)

  var errorDescription: String? {
    switch self {
    case .invalidURL(let url):
      return "Invalid download URL: \(url)"
    case .noURL(let fileName):
      return "No download URL available for '\(fileName)'."
    }
  }
}

func resolveImageURL(templateURL: String, width: Int, height: Int, fileName: String) -> String {
  let ext = (fileName as NSString).pathExtension.lowercased()
  let format = (ext == "jpg" || ext == "jpeg") ? "jpg" : "png"
  return templateURL
    .replacingOccurrences(of: "{w}", with: "\(width)")
    .replacingOccurrences(of: "{h}", with: "\(height)")
    .replacingOccurrences(of: "{f}", with: format)
}

// MARK: - UploadMedia Command

extension AppsCommand {
  struct MediaCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "media",
      abstract: "Manage screenshots and app preview videos.",
      subcommands: [Upload.self, Download.self, Verify.self, Prune.self, Remove.self, Library.self]
    )

    // MARK: - Upload

    struct Upload: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Upload screenshots and app preview videos from a folder.",
        discussion: """
          The folder holds one folder per locale (en-US, tr, ...), each with one folder
          per display type named after App Store Connect's display types (APP_IPHONE_67,
          APP_IPAD_PRO_3GEN_129, ...). Images become screenshots and videos app
          previews, uploaded in file name order.

          These folders go through the app's asset library instead:
            APP_IPHONE_DUO            iPhone Duo screenshots
            PRODUCT_PAGE_HEADER       one product page header image per locale
            APP_STORE_SEARCH_RESULTS  one App Store search results image per locale
          A header or search results image replaces the current one, with or without
          --replace.
          """
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "Path to the media folder or zip file.",
                completion: .file(extensions: ["zip", "tar", "tgz", "tar.gz"]))
      var folder: String?

      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
      var version: String?

      @OptionGroup var platformOption: PlatformOption

      @Flag(name: .long, help: "Delete existing media in matching sets before uploading.")
      var replace = false

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let folderPath = try resolveFolder(folder, prompt: "Select media folder")
        let rawPlan = try scanMediaFolder(at: folderPath)

        if rawPlan.locales.isEmpty {
          print("No media files found in '\(expandPath(folderPath))'.")
          return
        }

        // Print warnings
        for warning in rawPlan.warnings {
          print("Warning: \(warning)")
        }
        if !rawPlan.warnings.isEmpty { print() }

        let ascClient = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: ascClient)
        let appVersion = try await findVersion(appID: app.id, versionString: version, platform: try platformOption.parsed(), client: ascClient)

        let versionString = appVersion.attributes?.versionString ?? "unknown"
        let versionState = appVersion.attributes?.appVersionState.map { formatState($0) } ?? "unknown"
        let versionPlatform = appVersion.attributes?.platform.flatMap(Platform.init(rawValue:))

        // Drop display types that belong to another platform (mixed exports)
        let (plan, skippedTypes) = filterPlan(rawPlan, platform: versionPlatform)
        for skippedType in skippedTypes {
          let owner = formatState(platformForDisplayType(skippedType).rawValue)
          print(yellow("⚠ Skipping \(skippedType) — \(owner) display type, not applicable to this \(versionPlatform.map { formatState($0.rawValue) } ?? "?") version."))
        }
        if !skippedTypes.isEmpty { print() }

        guard !plan.locales.isEmpty else {
          throw ValidationError(
            "No media in '\(expandPath(folderPath))' matches this \(versionPlatform.map { formatState($0.rawValue) } ?? "?") version's platform.")
        }

        // Print confirmation summary
        print("App:     \(app.attributes?.name ?? bundleID)")
        print("Version: \(versionString)")
        print("State:   \(versionState)")
        if replace { print("Mode:    Replace existing media") }
        print()

        for localeMedia in plan.locales {
          print()
          print("[\(localeName(localeMedia.locale))]")
          for dt in localeMedia.displayTypes {
            var parts: [String] = []
            if !dt.screenshots.isEmpty {
              let noun = AssetLibrary.slots[dt.folderName]?.isSingle == true ? "image" : "screenshot"
              parts.append("\(dt.screenshots.count) \(noun)\(dt.screenshots.count == 1 ? "" : "s")")
            }
            if !dt.previews.isEmpty {
              parts.append("\(dt.previews.count) preview\(dt.previews.count == 1 ? "" : "s")")
            }
            print("  \(dt.folderName): \(parts.joined(separator: ", "))")
          }
        }
        print()

        let localeCount = plan.locales.count
        guard confirm(
          "Upload \(plan.totalScreenshots) screenshot\(plan.totalScreenshots == 1 ? "" : "s") and \(plan.totalPreviews) preview\(plan.totalPreviews == 1 ? "" : "s") for \(localeCount) locale\(localeCount == 1 ? "" : "s")? [y/N] ")
        else {
          cancelled()
          return
        }
        print()

        // Fetch all localizations for this version
        let locsResponse = try await ascClient.appStoreVersionsAppStoreVersionLocalizationsGetToManyRelated(
          path: .init(id: appVersion.id)
        ).ok.body.json
        // Keyed lowercased so a local `pt-br/` folder still matches ASC's `pt-BR`.
        let locByLocale = Dictionary(
          locsResponse.data.compactMap { loc in
            loc.attributes?.locale.map { ($0.lowercased(), loc) }
          },
          uniquingKeysWith: { first, _ in first }
        )

        struct UploadResult {
          let locale: String
          let displayType: String
          var tally: UploadTally
        }
        // iPhone Duo sets that ended with failed files, to place again in order after the run.
        struct DuoRedo {
          let resultIndex: Int
          let locale: String
          let files: [MediaFile]
          let localizationID: String
          let slot: AssetLibrary.Slot
          let placementIDs: [String]
        }

        var results: [UploadResult] = []
        var duoRedos: [DuoRedo] = []
        var assetLibraryID: String?
        var counter = UploadCounter(total: plan.totalScreenshots + plan.totalPreviews)

        for localeMedia in plan.locales {
          guard let localization = locByLocale[localeMedia.locale.lowercased()] else {
            print("[\(localeName(localeMedia.locale))] Skipped — locale not found on this version.")
            continue
          }

          print()
          print("[\(localeName(localeMedia.locale))]")

          // Fetch existing screenshot and preview sets for this localization.
          // A failure here must not abort the run — mark this locale failed and continue.
          // Set IDs by raw display/preview type.
          var screenshotSetsByType: [String: String] = [:]
          var previewSetsByType: [String: String] = [:]
          do {
            let screenshotSetsResponse = try await ascClient.appStoreVersionLocalizationsAppScreenshotSetsGetToManyRelated(
              path: .init(id: localization.id), query: .init(limit: 50)
            ).ok.body.json
            for set in screenshotSetsResponse.data {
              if let rawType = set.attributes?.screenshotDisplayType {
                screenshotSetsByType[rawType] = set.id
              }
            }

            let previewSetsResponse = try await ascClient.appStoreVersionLocalizationsAppPreviewSetsGetToManyRelated(
              path: .init(id: localization.id), query: .init(limit: 50)
            ).ok.body.json
            for set in previewSetsResponse.data {
              if let rawType = set.attributes?.previewType {
                previewSetsByType[rawType] = set.id
              }
            }
          } catch {
            print("  Failed to fetch existing media sets: \(describeError(error))")
            for dt in localeMedia.displayTypes {
              results.append(UploadResult(
                locale: localeMedia.locale, displayType: dt.folderName,
                tally: UploadTally(failed: dt.screenshots.count + dt.previews.count)))
            }
            continue
          }

          for dt in localeMedia.displayTypes {
            print("  \(dt.folderName):")
            var tally = UploadTally()

            // Set-level failures (create/replace rejected, e.g. HTTP 409) must not
            // abort the run — the catch below records them and moves to the next set.
            // Under dry run, stopped writes count as done so the later ones are previewed too.
            do {

              // Folders without a screenshot set (iPhone Duo, product page header, search results)
              // go through the asset library: upload each image, then place it on the localization.
              if !dt.screenshots.isEmpty, dt.screenshotDisplayType == nil, let slot = AssetLibrary.slots[dt.folderName] {
                if assetLibraryID == nil {
                  assetLibraryID = try await AssetLibrary.libraryID(appID: app.id, client: ascClient)
                }
                // A single-image slot is always replaced; a set only with --replace.
                var current: [String] = []
                if slot.isSingle || replace {
                  current = try await AssetLibrary.placements(
                    localizationID: localization.id, slot: slot, client: ascClient
                  ).map(\.id)
                }
                if !slot.isSingle {
                  for placementID in current {
                    try await AssetLibrary.removePlacement(id: placementID, client: ascClient)
                  }
                  printDeleted(current.count, "screenshot")
                } else if !current.isEmpty {
                  print("    \(ClientFactory.isDryRun ? "Would replace" : "Replacing") the current image.")
                }

                let placed = await placeAssetLibraryImages(
                  dt.screenshots, slot: slot, localizationID: localization.id, libraryID: assetLibraryID!,
                  replacing: slot.isSingle ? current : [], counter: &counter, client: ascClient)
                tally = placed.tally
                if !slot.isSingle && placed.tally.failed > 0 && !ClientFactory.isDryRun {
                  duoRedos.append(DuoRedo(
                    resultIndex: results.count, locale: localeMedia.locale, files: dt.screenshots,
                    localizationID: localization.id, slot: slot, placementIDs: placed.placementIDs))
                }
              }

              // Handle screenshots
              if !dt.screenshots.isEmpty, let displayType = dt.screenshotDisplayType {
                let screenshotSetID: String
                if let existingSetID = screenshotSetsByType[displayType.rawValue] {
                  screenshotSetID = existingSetID

                  if replace {
                    printDeleted(try await ClassicMedia.deleteAllScreenshots(inSet: screenshotSetID, client: ascClient), "screenshot")
                  }
                } else {
                  screenshotSetID = try await unlessDryRunStopped {
                    try await ClassicMedia.createScreenshotSet(
                      displayType, owner: .versionLocalization(localization.id), client: ascClient)
                  } ?? "DRY-RUN-SET"
                }

                for (i, file) in dt.screenshots.enumerated() {
                  counter.printLine("Screenshot", i, of: dt.screenshots.count, file.fileName)
                  await tally.record {
                    _ = try await ClassicMedia.uploadScreenshot(file, setID: screenshotSetID, client: ascClient)
                  }
                }
              }

              // Handle previews
              if !dt.previews.isEmpty, let pvType = dt.previewType {
                let previewSetID: String
                if let existingSetID = previewSetsByType[pvType.rawValue] {
                  previewSetID = existingSetID

                  if replace {
                    printDeleted(try await ClassicMedia.deleteAllPreviews(inSet: previewSetID, client: ascClient), "preview")
                  }
                } else {
                  previewSetID = try await unlessDryRunStopped {
                    try await ClassicMedia.createPreviewSet(
                      pvType, owner: .versionLocalization(localization.id), client: ascClient)
                  } ?? "DRY-RUN-SET"
                }

                for (i, file) in dt.previews.enumerated() {
                  counter.printLine("Preview  ", i, of: dt.previews.count, file.fileName)
                  await tally.record {
                    _ = try await ClassicMedia.uploadPreview(file, setID: previewSetID, client: ascClient)
                  }
                }
              }

            } catch {
              // One rejected set must not sink the rest — count this set's
              // unattempted files as failed and continue with the next set.
              print("    Failed: \(describeError(error))")
              tally.failed = (dt.screenshots.count + dt.previews.count) - tally.succeeded - tally.notSent
            }

            if tally.total > 0 {
              results.append(UploadResult(locale: localeMedia.locale, displayType: dt.folderName, tally: tally))
            }
          }
        }

        // A Duo file that failed even after retries leaves a gap, and placements keep their
        // creation order, so the rest of the set sits out of order. Place such sets again once:
        // remove this run's placements (earlier ones stay) and place every file in order.
        if !duoRedos.isEmpty {
          print()
          print("Placing \(duoRedos.count) iPhone Duo set\(duoRedos.count == 1 ? "" : "s") with failed files again, in file order.")
          var redoCounter = UploadCounter(total: duoRedos.reduce(0) { $0 + $1.files.count })
          for redo in duoRedos {
            print()
            print("[\(localeName(redo.locale))]")
            print("  \(results[redo.resultIndex].displayType):")
            do {
              for id in redo.placementIDs {
                try await AssetLibrary.removePlacement(id: id, client: ascClient)
              }
            } catch {
              print("    Failed to remove this run's placements: \(describeError(error))")
              continue
            }
            printDeleted(redo.placementIDs.count, "screenshot")
            results[redo.resultIndex].tally = await placeAssetLibraryImages(
              redo.files, slot: redo.slot, localizationID: redo.localizationID,
              libraryID: assetLibraryID!, counter: &redoCounter, client: ascClient
            ).tally
          }
        }

        // Results table
        let total = results.reduce(into: UploadTally()) { $0.add($1.tally) }

        print()
        if total.failed == 0 {
          if total.notSent > 0 {
            print("Dry run complete. \(total.notSent) file\(total.notSent == 1 ? "" : "s") would be uploaded; no writes were sent.")
          } else {
            print("Done. \(total.succeeded) file\(total.succeeded == 1 ? "" : "s") uploaded successfully.")
          }
        } else {
          var rows: [[String]] = []
          var lastLocale = ""
          for r in results {
            let localeLabel = r.locale == lastLocale ? "" : localeName(r.locale)
            lastLocale = r.locale
            rows.append([localeLabel, r.displayType, r.tally.summary])
          }
          // Totals row
          rows.append(["", "", ""])
          rows.append([bold("Total"), "", total.summary])

          Table.print(headers: ["Locale", "Display Type", "Result"], rows: rows)

          // A partial upload must not look like success to scripts/workflows.
          throw ExitCode.failure
        }
      }
    }

    // MARK: - Download

    struct Download: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Download screenshots and app preview videos to a folder."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Output folder path. Defaults to <bundle-id>-media.")
      var folder: String?

      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
      var version: String?

      @OptionGroup var platformOption: PlatformOption

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appVersion = try await findVersion(
          appID: app.id, versionString: version, platform: try platformOption.parsed(), client: client)

        let versionString = appVersion.attributes?.versionString ?? "unknown"
        let versionState = appVersion.attributes?.appVersionState.map { formatState($0) } ?? "unknown"
        print("App:     \(app.attributes?.name ?? bundleID)")
        print("Version: \(versionString)")
        print("State:   \(versionState)")
        print()

        // Fetch all localizations
        let locsResponse = try await client.appStoreVersionsAppStoreVersionLocalizationsGetToManyRelated(
          path: .init(id: appVersion.id)
        ).ok.body.json

        let outputFolder = expandPath(
          confirmOutputPath(folder ?? "\(bundleID)-media", isDirectory: true))
        let fm = FileManager.default

        var screenshotCount = 0
        var previewCount = 0
        var failureCount = 0

        for loc in locsResponse.data {
          guard let locale = loc.attributes?.locale else { continue }

          // Fetch screenshot sets for this localization
          let setsResponse = try await client.appStoreVersionLocalizationsAppScreenshotSetsGetToManyRelated(
            path: .init(id: loc.id), query: .init(limit: 50)
          ).ok.body.json

          for set in setsResponse.data {
            guard let displayType = set.attributes?.screenshotDisplayType else { continue }

            let screenshotsResponse = try await client.appScreenshotSetsAppScreenshotsGetToManyRelated(
              path: .init(id: set.id)
            ).ok.body.json

            if screenshotsResponse.data.isEmpty { continue }

            let setFolder = "\(outputFolder)/\(locale)/\(displayType)"
            try fm.createDirectory(atPath: setFolder, withIntermediateDirectories: true)

            print("[\(localeName(locale))] \(displayType):")

            for (i, screenshot) in screenshotsResponse.data.enumerated() {
              // Server-supplied name — strip path separators before building a local path.
              let originalName = (screenshot.attributes?.fileName ?? "\(screenshot.id).png")
                .replacingOccurrences(of: "/", with: "_")
              let fileName = String(format: "%02d_%@", i + 1, originalName)

              print(
                "  Screenshot \(i + 1)/\(screenshotsResponse.data.count): \(fileName)... ",
                terminator: "")
              fflush(stdout)

              do {
                guard let templateURL = screenshot.attributes?.imageAsset?.templateUrl else {
                  throw MediaDownloadError.noURL(originalName)
                }

                let width = screenshot.attributes?.imageAsset?.width ?? 0
                let height = screenshot.attributes?.imageAsset?.height ?? 0
                let downloadURL = resolveImageURL(
                  templateURL: templateURL, width: width, height: height, fileName: originalName)

                guard let url = URL(string: downloadURL) else {
                  throw MediaDownloadError.invalidURL(downloadURL)
                }

                let (tempURL, _) = try await URLSession.shared.download(from: url)
                let destPath = "\(setFolder)/\(fileName)"
                let destURL = URL(fileURLWithPath: destPath)
                if fm.fileExists(atPath: destPath) {
                  try fm.removeItem(at: destURL)
                }
                try fm.moveItem(at: tempURL, to: destURL)

                print("Done.")
                screenshotCount += 1
              } catch {
                print("Failed: \(describeError(error))")
                failureCount += 1
              }
            }
          }

          // Fetch preview sets for this localization
          let previewSetsResponse = try await client.appStoreVersionLocalizationsAppPreviewSetsGetToManyRelated(
            path: .init(id: loc.id), query: .init(limit: 50)
          ).ok.body.json

          for set in previewSetsResponse.data {
            guard let pvType = set.attributes?.previewType else { continue }

            let previewsResponse = try await client.appPreviewSetsAppPreviewsGetToManyRelated(
              path: .init(id: set.id)
            ).ok.body.json

            if previewsResponse.data.isEmpty { continue }

            // Map preview type back to screenshot display type folder name
            let folderName = "APP_\(pvType)"
            let setFolder = "\(outputFolder)/\(locale)/\(folderName)"
            try fm.createDirectory(atPath: setFolder, withIntermediateDirectories: true)

            print("[\(localeName(locale))] \(folderName):")

            for (i, preview) in previewsResponse.data.enumerated() {
              // Server-supplied name — strip path separators before building a local path.
              let originalName = (preview.attributes?.fileName ?? "\(preview.id).mp4")
                .replacingOccurrences(of: "/", with: "_")
              let fileName = String(format: "%02d_%@", i + 1, originalName)

              print(
                "  Preview   \(i + 1)/\(previewsResponse.data.count): \(fileName)... ",
                terminator: "")
              fflush(stdout)

              do {
                guard let videoURLString = preview.attributes?.videoUrl else {
                  throw MediaDownloadError.noURL(originalName)
                }

                guard let url = URL(string: videoURLString) else {
                  throw MediaDownloadError.invalidURL(videoURLString)
                }

                let (tempURL, _) = try await URLSession.shared.download(from: url)
                let destPath = "\(setFolder)/\(fileName)"
                let destURL = URL(fileURLWithPath: destPath)
                if fm.fileExists(atPath: destPath) {
                  try fm.removeItem(at: destURL)
                }
                try fm.moveItem(at: tempURL, to: destURL)

                print("Done.")
                previewCount += 1
              } catch {
                print("Failed: \(describeError(error))")
                failureCount += 1
              }
            }
          }
        }

        // Final summary
        print()
        let total = screenshotCount + previewCount
        if total == 0 {
          print("No media found for this version.")
        } else if failureCount == 0 {
          print(
            "Downloaded \(screenshotCount) screenshot\(screenshotCount == 1 ? "" : "s") and \(previewCount) preview\(previewCount == 1 ? "" : "s") to \(outputFolder)"
          )
        } else {
          print(
            "Done. \(total) succeeded, \(failureCount) failed. Output: \(outputFolder)")
        }
      }
    }

    // MARK: - Verify

    struct Verify: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Check processing status of all screenshots and previews, optionally retry stuck items."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
      var version: String?

      @OptionGroup var platformOption: PlatformOption

      @Argument(help: "Path to the media folder or zip file for retrying stuck uploads.",
                completion: .file(extensions: ["zip", "tar", "tgz", "tar.gz"]))
      var folder: String?

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let ascClient = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: ascClient)
        let appVersion = try await findVersion(
          appID: app.id, versionString: version, platform: try platformOption.parsed(), client: ascClient)

        let versionString = appVersion.attributes?.versionString ?? "unknown"
        print("App:     \(app.attributes?.name ?? bundleID)")
        print("Version: \(versionString)")
        print()

        // Fetch all media status
        let items = try await fetchAllMediaStatus(versionID: appVersion.id, client: ascClient)

        if items.isEmpty {
          print("No media found for this version.")
          return
        }

        // Print status and get counts
        let (total, stuck) = printMediaStatus(items)
        let plan = try folder.map { try scanMediaFolder(at: $0) }

        // Placements keep their creation order and can't be reordered or retried one by one,
        // so check them against the folder: a set that differs needs `media upload --replace`.
        if let plan {
          let mismatched = placementSetsDifferingFromFolder(items, plan: plan)
          if !mismatched.isEmpty {
            print()
            for label in mismatched {
              print(yellow("⚠ \(label): files or order differ from the folder."))
            }
            print("Run `media upload` with --replace to place them again in file order.")
          }
        }

        if stuck == 0 {
          print()
          print("All \(total) media item\(total == 1 ? "" : "s") complete.")
          return
        }

        print()
        print("\(total - stuck) of \(total) complete, \(stuck) stuck.")
        let stuckPlacements = items.filter { !$0.isComplete && $0.isPlacement }.count
        if stuckPlacements > 0 {
          print("\(stuckPlacements) stuck iPhone Duo screenshot\(stuckPlacements == 1 ? "" : "s") can't be retried here; run `media upload` with --replace for them.")
        }

        // Without --folder, just show status
        guard let plan else {
          print("Use --folder to provide the media folder and retry stuck uploads.")
          return
        }

        // Build local file index from the folder
        let fileIndex = buildLocalFileIndex(from: plan)

        // Match stuck items to local files
        let stuckItems = items.filter { !$0.isComplete && !$0.isPlacement }
        var matchedRetries: [(MediaItemStatus, String)] = []  // (item, localFilePath)
        var unmatchedCount = 0

        for item in stuckItems {
          let prefix = item.isScreenshot ? "screenshot" : "preview"
          let key = "\(item.locale.lowercased())/\(item.displayTypeName)/\(prefix)/\(item.position)"
          if let localPath = fileIndex[key] {
            matchedRetries.append((item, localPath))
          } else {
            unmatchedCount += 1
          }
        }

        if matchedRetries.isEmpty {
          print("No matching local files found for stuck items.")
          return
        }

        if unmatchedCount > 0 {
          print("\(unmatchedCount) stuck item\(unmatchedCount == 1 ? "" : "s") have no matching local file and will be skipped.")
        }

        print()
        guard confirm("Retry \(matchedRetries.count) stuck item\(matchedRetries.count == 1 ? "" : "s")? [y/N] ") else {
          cancelled()
          return
        }
        print()

        var successCount = 0
        var failureCount = 0

        // Track each set's current ID order across retries — when a set has more
        // than one stuck item, later reorders must reference the replacement IDs
        // from earlier retries, not the deleted originals in the initial snapshot.
        var orderBySet: [String: [String]] = [:]
        func reorderedIDs(for item: MediaItemStatus, replacingWith newID: String) -> [String] {
          var order = orderBySet[item.setID] ?? item.allIDsInSet
          if let idx = order.firstIndex(of: item.mediaID) {
            order[idx] = newID
          } else {
            order.append(newID)
          }
          orderBySet[item.setID] = order
          return order
        }

        for (item, localPath) in matchedRetries {
          print("[\(localeName(item.locale))] \(item.displayTypeName) #\(item.position): ", terminator: "")
          fflush(stdout)

          do {
            // Delete the stuck item
            print("Deleting... ", terminator: "")
            fflush(stdout)
            if item.isScreenshot {
              try await ClassicMedia.deleteScreenshot(item.mediaID, client: ascClient)
            } else {
              try await ClassicMedia.deletePreview(item.mediaID, client: ascClient)
            }

            // Upload replacement
            print("Uploading... ", terminator: "")
            fflush(stdout)

            let file = try MediaFile(readingFrom: localPath)
            if item.isScreenshot {
              let newID = try await ClassicMedia.uploadScreenshot(file, setID: item.setID, client: ascClient)

              // Reorder to restore original position
              print("Reordering... ", terminator: "")
              fflush(stdout)
              try await ClassicMedia.reorderScreenshots(
                setID: item.setID, ids: reorderedIDs(for: item, replacingWith: newID), client: ascClient)
            } else {
              let newID = try await ClassicMedia.uploadPreview(file, setID: item.setID, client: ascClient)

              // Reorder to restore original position
              print("Reordering... ", terminator: "")
              fflush(stdout)
              try await ClassicMedia.reorderPreviews(
                setID: item.setID, ids: reorderedIDs(for: item, replacingWith: newID), client: ascClient)
            }

            print("Done.")
            successCount += 1
          } catch {
            print("Failed: \(describeError(error))")
            failureCount += 1
          }
        }

        // Re-verify
        print()
        print("Re-verifying...")
        print()

        let updatedItems = try await fetchAllMediaStatus(versionID: appVersion.id, client: ascClient)
        let (newTotal, newStuck) = printMediaStatus(updatedItems)

        print()
        if newStuck == 0 {
          print("All \(newTotal) media item\(newTotal == 1 ? "" : "s") complete.")
        } else {
          print("\(newTotal - newStuck) of \(newTotal) complete, \(newStuck) still stuck.")
        }

        if failureCount > 0 {
          print("\(successCount) retried successfully, \(failureCount) failed.")
        }
      }
    }

    // MARK: - Remove

    struct Remove: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Remove asset library images (header, search results, iPhone Duo) from a version.",
        discussion: """
          Removes one kind of asset library image from the version's localizations:
          PRODUCT_PAGE_HEADER, APP_STORE_SEARCH_RESULTS or APP_IPHONE_DUO. A removed
          image is also deleted from the app's asset library when nothing uses it any
          more: no placement on any version (old ones included), custom product page or
          event, and never reviewed.
          """
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "What to remove: PRODUCT_PAGE_HEADER, APP_STORE_SEARCH_RESULTS or APP_IPHONE_DUO.",
                completion: .list(AssetLibrary.slots.keys.sorted()))
      var kind: String

      @Option(name: .long, help: "Comma-separated locales (e.g. en-US,tr). Defaults to all of the version's locales.")
      var locale: String?

      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
      var version: String?

      @OptionGroup var platformOption: PlatformOption

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        guard let slot = AssetLibrary.slots[kind.uppercased()] else {
          throw ValidationError("Unknown kind '\(kind)'. Valid values: \(AssetLibrary.slots.keys.sorted().joined(separator: ", "))")
        }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appVersion = try await findVersion(
          appID: app.id, versionString: version, platform: try platformOption.parsed(), client: client)

        let wanted = locale.map { Set($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }) }
        let localizations = try await client.appStoreVersionsAppStoreVersionLocalizationsGetToManyRelated(
          path: .init(id: appVersion.id)
        ).ok.body.json.data
          .compactMap { loc in loc.attributes?.locale.map { (locale: $0, id: loc.id) } }
          .sorted { $0.locale < $1.locale }
        if let wanted {
          let missing = wanted.subtracting(localizations.map { $0.locale.lowercased() })
          if !missing.isEmpty {
            throw ValidationError("Locale not on this version: \(missing.sorted().joined(separator: ", ")).")
          }
        }

        print("App:     \(app.attributes?.name ?? bundleID)")
        print("Version: \(appVersion.attributes?.versionString ?? "unknown")")
        print()

        var targets: [(locale: String, placementIDs: [String])] = []
        for loc in localizations where wanted?.contains(loc.locale.lowercased()) ?? true {
          let ids = try await AssetLibrary.placements(localizationID: loc.id, slot: slot, client: client).map(\.id)
          if !ids.isEmpty { targets.append((loc.locale, ids)) }
        }
        guard !targets.isEmpty else {
          print("No \(kind.uppercased()) images on this version\(wanted == nil ? "" : " for those locales").")
          return
        }
        for target in targets {
          print("[\(localeName(target.locale))] \(target.placementIDs.count) image\(target.placementIDs.count == 1 ? "" : "s")")
        }
        let total = targets.reduce(0) { $0 + $1.placementIDs.count }
        print()
        guard confirm("Remove \(total) \(kind.uppercased()) image\(total == 1 ? "" : "s") from \(targets.count) locale\(targets.count == 1 ? "" : "s")? [y/N] ") else {
          cancelled()
          return
        }
        print()

        var removed = 0
        var deletedImages = 0
        var failures = 0
        for target in targets {
          print("[\(localeName(target.locale))] ", terminator: "")
          fflush(stdout)
          var localeRemoved = 0
          do {
            for placementID in target.placementIDs {
              if try await AssetLibrary.removePlacement(id: placementID, client: client) { deletedImages += 1 }
              localeRemoved += 1
            }
            print(ClientFactory.isDryRun ? "Not sent (dry run)." : "Removed \(localeRemoved).")
          } catch {
            print("Failed: \(describeError(error))")
            failures += target.placementIDs.count - localeRemoved
          }
          removed += localeRemoved
        }

        print()
        if ClientFactory.isDryRun {
          print("Dry run complete. \(removed) image\(removed == 1 ? "" : "s") would be removed; no writes were sent.")
        } else {
          success("Removed", "\(removed) image\(removed == 1 ? "" : "s"); deleted \(deletedImages) unused from the asset library.")
        }
        if failures > 0 {
          throw ExitCode.failure
        }
      }
    }

    // MARK: - Library

    struct Library: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Show the app's asset library images and delete the ones nothing uses.",
        discussion: """
          Versions share asset library images, and old versions keep theirs, so most
          images stay placed somewhere. An image is unused when it has no placement on
          any version (old ones included), custom product page or event, which happens
          when a placement is removed (e.g. by replacing classic screenshot sets). With
          --delete-unused, the unused images that never went through App Review are
          listed and, after confirmation, deleted. Images that were ever reviewed are
          never deleted.

          --only narrows the list to images that fit PRODUCT_PAGE_HEADER,
          APP_STORE_SEARCH_RESULTS and/or APP_IPHONE_DUO, by asset category and pixel
          size, leaving e.g. 6.9-inch iPhone screenshots alone.
          """
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Only images that fit these kinds (comma-separated): PRODUCT_PAGE_HEADER, APP_STORE_SEARCH_RESULTS, APP_IPHONE_DUO.")
      var only: String?

      @Flag(name: .long, help: "Delete the unused, never-reviewed images after listing them.")
      var deleteUnused = false

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let onlySlots = try only.map { list in
          try list.split(separator: ",").map { name in
            let kind = name.trimmingCharacters(in: .whitespaces).uppercased()
            guard let slot = AssetLibrary.slots[kind] else {
              throw ValidationError("Unknown kind '\(kind)'. Valid values: \(AssetLibrary.slots.keys.sorted().joined(separator: ", "))")
            }
            return slot
          }
        }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let libraryID = try await AssetLibrary.libraryID(appID: app.id, client: client)
        let images = try await ASCPaging.allPages(next: { $0.links.next }) {
          try await withTransientRetry {
            try await client.appAssetLibrariesImagesGetToManyRelated(
              path: .init(id: libraryID), query: .init(limit: 200, include: [.placements], limitPlacements: 1)
            ).ok.body.json
          }
        }.flatMap(\.data)

        // An image whose placements didn't come back counts as placed.
        let placed = images.filter { $0.relationships?.placements?.data?.isEmpty != true }
        let unplaced = images.filter { $0.relationships?.placements?.data?.isEmpty == true }
        let allUnused = unplaced.filter(AssetLibrary.isUnused)
        let unused = allUnused
          .filter { image in onlySlots.map { $0.contains { AssetLibrary.image(image, fits: $0) } } ?? true }
          .sorted { ($0.attributes?.common.createdDate ?? .distantPast) < ($1.attributes?.common.createdDate ?? .distantPast) }

        print("App:     \(app.attributes?.name ?? bundleID)")
        print("Images:  \(images.count) (\(placed.count) placed, \(unplaced.count) unplaced)")
        let reviewed = unplaced.count - allUnused.count
        if reviewed > 0 {
          print("         \(reviewed) unplaced image\(reviewed == 1 ? " was" : "s were") reviewed and \(reviewed == 1 ? "is" : "are") kept.")
        }
        if let only, allUnused.count > unused.count {
          print("         \(allUnused.count - unused.count) unused image\(allUnused.count - unused.count == 1 ? "" : "s") left out by --only \(only.uppercased()).")
        }
        guard !unused.isEmpty else {
          print()
          print("No unused images\(only == nil ? "" : " of those kinds").")
          return
        }
        print()
        print("Unused (no placement, never reviewed):")
        Table.print(
          headers: ["File", "Size", "State", "Category", "Created"],
          rows: unused.map { image in
            let common = image.attributes?.common
            let size = common?.imageAsset.flatMap { asset in asset.width.flatMap { w in asset.height.map { "\(w)×\($0)" } } }
            return [
              common?.fileName ?? "—", size ?? "—", formatState(image.attributes?.stateName ?? ""),
              common?.category.map { formatState($0) } ?? "—", common?.createdDate.map(formatDate) ?? "—",
            ]
          })

        guard deleteUnused else {
          print()
          print("Run with --delete-unused to delete them.")
          return
        }
        print()
        guard confirm("Delete \(unused.count) unused image\(unused.count == 1 ? "" : "s")? [y/N] ") else {
          cancelled()
          return
        }

        // Each image is checked again right before its delete, eight at a time. On a terminal a
        // counter shows progress (not under dry run, whose stopped requests show it and would
        // interleave with it); failures are listed as they happen.
        let showsCounter = isTerminal && !ClientFactory.isDryRun
        var deleted = 0
        var failures = 0
        var finished = 0
        var remaining = unused.makeIterator()
        await withTaskGroup(of: (name: String, outcome: Result<Bool?, any Error>).self) { group in
          func addNext() {
            guard let image = remaining.next() else { return }
            group.addTask {
              let name = image.attributes?.common.fileName ?? image.id
              do {
                return (name, .success(try await unlessDryRunStopped {
                  try await AssetLibrary.deleteImageIfUnused(id: image.id, client: client)
                }))
              } catch {
                return (name, .failure(error))
              }
            }
          }
          for _ in 0..<8 { addNext() }
          for await (name, outcome) in group {
            finished += 1
            switch outcome {
              case .success(let wasDeleted): if wasDeleted == true { deleted += 1 }
              case .failure(let error):
                failures += 1
                if showsCounter { print("\r\u{1B}[K", terminator: "") }
                print("\(name): \(describeError(error))")
            }
            if showsCounter {
              print("\r\u{1B}[KDeleting... \(finished)/\(unused.count)", terminator: "")
              fflush(stdout)
            }
            addNext()
          }
        }
        if showsCounter { print("\r\u{1B}[K", terminator: "") }
        print()
        if ClientFactory.isDryRun {
          print("Dry run complete. \(unused.count) image\(unused.count == 1 ? "" : "s") would be deleted; no writes were sent.")
        } else {
          success("Deleted", "\(deleted) unused image\(deleted == 1 ? "" : "s") from the asset library.")
        }
        if failures > 0 {
          throw ExitCode.failure
        }
      }
    }

    // MARK: - Prune

    struct Prune: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Delete server screenshot/preview sets that have no matching local folder.",
        discussion: """
          Compares the version's screenshot and app preview sets against a local media
          folder and deletes the sets with no corresponding locale/display-type folder —
          e.g. stale sets for screen sizes you no longer ship (`--replace` on upload
          never touches those). Locales without a local folder are left untouched.
          """
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "Path to the media folder (same structure as upload).")
      var folder: String?

      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
      var version: String?

      @OptionGroup var platformOption: PlatformOption

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let folderPath = try resolveFolder(folder, prompt: "Select media folder")
        let rawPlan = try scanMediaFolder(at: folderPath)

        guard !rawPlan.locales.isEmpty else {
          throw ValidationError(
            "No media files found in '\(expandPath(folderPath))' — refusing to prune against an empty folder.")
        }

        let ascClient = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: ascClient)
        let appVersion = try await findVersion(
          appID: app.id, versionString: version, platform: try platformOption.parsed(), client: ascClient)
        let versionString = appVersion.attributes?.versionString ?? "unknown"
        let versionPlatform = appVersion.attributes?.platform.flatMap(Platform.init(rawValue:))

        let (plan, _) = filterPlan(rawPlan, platform: versionPlatform)
        guard !plan.locales.isEmpty else {
          throw ValidationError(
            "No media in '\(expandPath(folderPath))' matches this \(versionPlatform.map { formatState($0.rawValue) } ?? "?") version's platform.")
        }

        // Which display types exist locally, per locale (lowercased for matching)
        var localScreenshotTypes: [String: Set<String>] = [:]
        var localPreviewTypes: [String: Set<String>] = [:]
        for localeMedia in plan.locales {
          let key = localeMedia.locale.lowercased()
          for dt in localeMedia.displayTypes {
            if !dt.screenshots.isEmpty {
              localScreenshotTypes[key, default: []].insert(dt.folderName)
            }
            if !dt.previews.isEmpty, let pv = dt.previewType {
              localPreviewTypes[key, default: []].insert(pv.rawValue)
            }
          }
        }

        struct OrphanSet {
          let locale: String
          let typeName: String
          let kind: String
          let setID: String
          let isScreenshot: Bool
          let assetCount: Int
        }
        var orphans: [OrphanSet] = []
        var skippedLocales: [String] = []

        let locsResponse = try await ascClient.appStoreVersionsAppStoreVersionLocalizationsGetToManyRelated(
          path: .init(id: appVersion.id)
        ).ok.body.json
        for loc in locsResponse.data {
          guard let locale = loc.attributes?.locale else { continue }
          let key = locale.lowercased()
          // A locale with no local folder is not managed by this folder — leave it alone.
          guard localScreenshotTypes[key] != nil || localPreviewTypes[key] != nil else {
            skippedLocales.append(locale)
            continue
          }

          let screenshotSets = try await ascClient.appStoreVersionLocalizationsAppScreenshotSetsGetToManyRelated(
            path: .init(id: loc.id), query: .init(limit: 50)
          ).ok.body.json
          for set in screenshotSets.data {
            // Display types the classic API can't create (APP_IPHONE_DUO, placed through the asset
            // library) are not managed by a media folder — never offer to delete them.
            guard let raw = set.attributes?.screenshotDisplayType,
                  ASCEnum.ScreenshotDisplayType(rawValue: raw) != nil else { continue }
            if localScreenshotTypes[key]?.contains(raw) != true {
              let assets = try await ascClient.appScreenshotSetsAppScreenshotsGetToManyRelated(
                path: .init(id: set.id)
              ).ok.body.json
              orphans.append(OrphanSet(
                locale: locale, typeName: raw, kind: "Screenshots",
                setID: set.id, isScreenshot: true, assetCount: assets.data.count))
            }
          }

          let previewSets = try await ascClient.appStoreVersionLocalizationsAppPreviewSetsGetToManyRelated(
            path: .init(id: loc.id), query: .init(limit: 50)
          ).ok.body.json
          for set in previewSets.data {
            guard let raw = set.attributes?.previewType, ASCEnum.PreviewType(rawValue: raw) != nil else { continue }
            if localPreviewTypes[key]?.contains(raw) != true {
              let assets = try await ascClient.appPreviewSetsAppPreviewsGetToManyRelated(
                path: .init(id: set.id)
              ).ok.body.json
              orphans.append(OrphanSet(
                locale: locale, typeName: raw, kind: "Previews",
                setID: set.id, isScreenshot: false, assetCount: assets.data.count))
            }
          }
        }

        if !skippedLocales.isEmpty {
          print("Skipping locale\(skippedLocales.count == 1 ? "" : "s") with no local folder: \(skippedLocales.sorted().joined(separator: ", "))")
          print()
        }

        guard !orphans.isEmpty else {
          print("Nothing to prune — every server set has a matching local folder.")
          return
        }

        let totalAssets = orphans.reduce(0) { $0 + $1.assetCount }
        print("App:     \(app.attributes?.name ?? bundleID)")
        print("Version: \(versionString) (\(versionPlatform.map { formatState($0.rawValue) } ?? "—"))")
        print()
        print("Server sets with no matching local folder:")
        print()
        Table.print(
          headers: ["Locale", "Display Type", "Kind", "Assets"],
          rows: orphans.map { [localeName($0.locale), $0.typeName, $0.kind, "\($0.assetCount)"] })
        print()
        print(yellow("⚠ Deleting a set permanently removes it and its assets from this version."))
        print()
        guard confirm(
          "Delete \(orphans.count) set\(orphans.count == 1 ? "" : "s") (\(totalAssets) asset\(totalAssets == 1 ? "" : "s"))? [y/N] ")
        else {
          cancelled()
          return
        }
        print()

        var deleted = 0
        var failed = 0
        for orphan in orphans {
          do {
            if orphan.isScreenshot {
              try await ClassicMedia.deleteScreenshotSet(orphan.setID, client: ascClient)
            } else {
              try await ClassicMedia.deletePreviewSet(orphan.setID, client: ascClient)
            }
            print("  OK   [\(orphan.locale)] \(orphan.typeName) (\(orphan.kind.lowercased()))")
            deleted += 1
          } catch {
            print("  FAIL [\(orphan.locale)] \(orphan.typeName) — \(describeError(error))")
            failed += 1
          }
        }

        print()
        success("Pruned", "\(deleted) set\(deleted == 1 ? "" : "s").")
        if failed > 0 {
          print("\(failed) set\(failed == 1 ? "" : "s") failed to delete.")
          throw ExitCode.failure
        }
      }
    }
  }
}

// MARK: - VerifyMedia Helpers

private struct MediaItemStatus {
  let locale: String
  let displayTypeName: String
  let position: Int        // 1-based
  let fileName: String
  let state: String
  let isComplete: Bool
  let isScreenshot: Bool
  /// An asset library placement (iPhone Duo, header, search results), which the classic retry
  /// can't redo.
  var isPlacement = false
  let setID: String
  let mediaID: String
  let allIDsInSet: [String]
}

private func fetchAllMediaStatus(versionID: String, client: ASCClient) async throws -> [MediaItemStatus] {
  let locsResponse = try await client.appStoreVersionsAppStoreVersionLocalizationsGetToManyRelated(
    path: .init(id: versionID)
  ).ok.body.json

  var items: [MediaItemStatus] = []

  func item(locale: String, displayTypeName: String, position: Int, fileName: String?, state: String?,
            isScreenshot: Bool, setID: String, mediaID: String, allIDs: [String]) -> MediaItemStatus {
    MediaItemStatus(
      locale: locale,
      displayTypeName: displayTypeName,
      position: position,
      fileName: fileName ?? "unknown",
      state: state.map { formatState($0) } ?? "unknown",
      isComplete: state == "COMPLETE",
      isScreenshot: isScreenshot,
      setID: setID,
      mediaID: mediaID,
      allIDsInSet: allIDs
    )
  }

  for loc in locsResponse.data {
    guard let locale = loc.attributes?.locale else { continue }

    // Asset library placements. A placement still processing reads ASSET_PROCESSING, a
    // finished one ACTIVE (seen live), and the spec also lists FAILED and PARENT_* states.
    for (displayTypeName, slot) in AssetLibrary.slots.sorted(by: { $0.key < $1.key }) {
      let placements = try await AssetLibrary.placements(localizationID: loc.id, slot: slot, client: client)
      let fileNames = try await withThrowingTaskGroup(of: (Int, String?).self) { tasks in
        for (i, placement) in placements.enumerated() {
          tasks.addTask { (i, try await AssetLibrary.placementFileName(id: placement.id, client: client)) }
        }
        var names = [String?](repeating: nil, count: placements.count)
        for try await (i, name) in tasks { names[i] = name }
        return names
      }
      for (i, placement) in placements.enumerated() {
        let state = placement.attributes?.state
        items.append(MediaItemStatus(
          locale: locale, displayTypeName: displayTypeName, position: i + 1,
          fileName: fileNames[i] ?? "unknown", state: state.map { formatState($0) } ?? "unknown",
          isComplete: state.map { $0 != "ASSET_PROCESSING" && $0 != "FAILED" } ?? false,
          isScreenshot: true, isPlacement: true,
          setID: "placements/\(loc.id)", mediaID: placement.id, allIDsInSet: placements.map(\.id)))
      }
    }

    // Screenshot sets
    let setsResponse = try await client.appStoreVersionLocalizationsAppScreenshotSetsGetToManyRelated(
      path: .init(id: loc.id), query: .init(limit: 50)
    ).ok.body.json

    for set in setsResponse.data {
      // Placement groups are listed from their placements above; once those are active, the
      // classic API lists the same screenshots in a set of its own (seen live 2026-10-07).
      guard let displayType = set.attributes?.screenshotDisplayType,
        AssetLibrary.slots[displayType] == nil
      else { continue }
      let screenshots = try await client.appScreenshotSetsAppScreenshotsGetToManyRelated(
        path: .init(id: set.id)
      ).ok.body.json.data
      let allIDs = screenshots.map(\.id)
      for (i, screenshot) in screenshots.enumerated() {
        items.append(item(
          locale: locale, displayTypeName: displayType, position: i + 1,
          fileName: screenshot.attributes?.fileName, state: screenshot.attributes?.assetDeliveryState?.state,
          isScreenshot: true, setID: set.id, mediaID: screenshot.id, allIDs: allIDs))
      }
    }

    // Preview sets
    let previewSetsResponse = try await client.appStoreVersionLocalizationsAppPreviewSetsGetToManyRelated(
      path: .init(id: loc.id), query: .init(limit: 50)
    ).ok.body.json

    for set in previewSetsResponse.data {
      guard let pvType = set.attributes?.previewType else { continue }
      let previews = try await client.appPreviewSetsAppPreviewsGetToManyRelated(
        path: .init(id: set.id)
      ).ok.body.json.data
      let allIDs = previews.map(\.id)
      for (i, preview) in previews.enumerated() {
        items.append(item(
          locale: locale, displayTypeName: "APP_\(pvType)", position: i + 1,
          fileName: preview.attributes?.fileName, state: preview.attributes?.assetDeliveryState?.state,
          isScreenshot: false, setID: set.id, mediaID: preview.id, allIDs: allIDs))
      }
    }
  }

  return items
}

/// Prints media status grouped by locale and display type.
/// Returns (total, stuck) counts.
@discardableResult
private func printMediaStatus(_ items: [MediaItemStatus]) -> (total: Int, stuck: Int) {
  // Group by locale, then by displayType+setID
  struct SetKey: Hashable {
    let locale: String
    let displayTypeName: String
    let setID: String
  }

  var grouped: [SetKey: [MediaItemStatus]] = [:]
  for item in items {
    let key = SetKey(locale: item.locale, displayTypeName: item.displayTypeName, setID: item.setID)
    grouped[key, default: []].append(item)
  }

  // Sort by locale, then display type
  let sortedKeys = grouped.keys.sorted {
    if $0.locale != $1.locale { return $0.locale < $1.locale }
    return $0.displayTypeName < $1.displayTypeName
  }

  var total = 0
  var stuck = 0

  for key in sortedKeys {
    let setItems = grouped[key]!
    total += setItems.count
    let setStuck = setItems.filter { !$0.isComplete }.count
    stuck += setStuck

    if setStuck == 0 {
      print("[\(localeName(key.locale))] \(key.displayTypeName): \(setItems.count)/\(setItems.count) complete")
    } else {
      print("[\(localeName(key.locale))] \(key.displayTypeName):")
      for item in setItems {
        let marker = item.isComplete ? "complete" : item.state
        print("  #\(item.position)  \(item.fileName)    \(marker)")
      }
    }
  }

  return (total, stuck)
}

/// The "[locale] displayType" labels of placement sets (iPhone Duo) whose file names, in
/// display order, differ from the folder's files for that locale and display type.
private func placementSetsDifferingFromFolder(_ items: [MediaItemStatus], plan: MediaUploadPlan) -> [String] {
  var labels: [String] = []
  for localeMedia in plan.locales {
    for dt in localeMedia.displayTypes where AssetLibrary.slots[dt.folderName] != nil {
      let placed = items.filter {
        $0.isPlacement && $0.locale.lowercased() == localeMedia.locale.lowercased() && $0.displayTypeName == dt.folderName
      }.sorted { $0.position < $1.position }.map(\.fileName)
      if placed != dt.screenshots.map(\.fileName) {
        labels.append("[\(localeName(localeMedia.locale))] \(dt.folderName)")
      }
    }
  }
  return labels
}

/// Builds a lookup from "locale/displayType/screenshot|preview/position" to local file path.
private func buildLocalFileIndex(from plan: MediaUploadPlan) -> [String: String] {
  var index: [String: String] = [:]

  for localeMedia in plan.locales {
    for dt in localeMedia.displayTypes {
      // Locale lowercased so a local `pt-br/` folder still matches ASC's `pt-BR`.
      for (i, file) in dt.screenshots.enumerated() {
        index["\(localeMedia.locale.lowercased())/\(dt.folderName)/screenshot/\(i + 1)"] = file.path
      }
      for (i, file) in dt.previews.enumerated() {
        index["\(localeMedia.locale.lowercased())/\(dt.folderName)/preview/\(i + 1)"] = file.path
      }
    }
  }

  return index
}
