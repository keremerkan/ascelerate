import AppStoreAPI
import AppStoreConnect
import ArgumentParser
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
  let screenshotDisplayType: ScreenshotDisplayType?
  let previewType: PreviewType?
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

      let screenshotType = ScreenshotDisplayType(rawValue: displayTypeName)
      let pvType = previewTypeForDisplayType(displayTypeName)

      if screenshotType == nil {
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

func previewTypeForDisplayType(_ rawValue: String) -> PreviewType? {
  if rawValue.hasPrefix("APP_WATCH_") || rawValue.hasPrefix("IMESSAGE_") {
    return nil
  }
  guard rawValue.hasPrefix("APP_") else { return nil }
  let previewRaw = String(rawValue.dropFirst(4))
  return PreviewType(rawValue: previewRaw)
}

// MARK: - Upload Helpers

func uploadChunks(filePath: String, operations: [UploadOperation]) async throws {
  guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
    throw MediaUploadError.cannotReadFile(filePath)
  }
  defer { try? fileHandle.close() }

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
    if let headers = operation.requestHeaders {
      for header in headers {
        if let name = header.name, let value = header.value {
          request.setValue(value, forHTTPHeaderField: name)
        }
      }
    }

    let (_, response) = try await URLSession.shared.upload(for: request, from: chunkData)
    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode)
    else {
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
      throw MediaUploadError.chunkUploadFailed(statusCode)
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

func mediaMimeType(for fileName: String) -> String {
  let ext = (fileName as NSString).pathExtension.lowercased()
  switch ext {
  case "mp4": return "video/mp4"
  case "mov": return "video/quicktime"
  default: return "application/octet-stream"
  }
}

enum MediaUploadError: LocalizedError {
  case cannotReadFile(String)
  case invalidUploadOperation
  case chunkUploadFailed(Int)
  case noUploadOperations

  var errorDescription: String? {
    switch self {
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
      subcommands: [Upload.self, Download.self, Verify.self]
    )

    // MARK: - Upload

    struct Upload: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Upload screenshots and app preview videos from a folder."
      )

      @Argument(help: "The bundle identifier of the app.")
      var bundleID: String

      @Option(name: .long, help: "Path to the media folder.")
      var folder: String?

      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
      var version: String?

      @Flag(name: .long, help: "Delete existing media in matching sets before uploading.")
      var replace = false

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        // Get folder path
        let folderPath: String
        if let f = folder {
          folderPath = f
        } else {
          print("Path to media folder: ", terminator: "")
          guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
            !line.isEmpty
          else {
            throw ValidationError("No folder path provided.")
          }
          folderPath = line
        }

        // Scan folder
        let plan = try scanMediaFolder(at: folderPath)

        if plan.locales.isEmpty {
          print("No media files found in '\(expandPath(folderPath))'.")
          return
        }

        // Print warnings
        for warning in plan.warnings {
          print("Warning: \(warning)")
        }
        if !plan.warnings.isEmpty { print() }

        // Resolve app and version
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appVersion = try await findVersion(appID: app.id, versionString: version, client: client)

        let versionString = appVersion.attributes?.versionString ?? "unknown"
        let versionState = appVersion.attributes?.appVersionState.map { "\($0)" } ?? "unknown"

        // Print confirmation summary
        print("App:     \(app.attributes?.name ?? bundleID)")
        print("Version: \(versionString)")
        print("State:   \(versionState)")
        if replace { print("Mode:    Replace existing media") }
        print()

        for localeMedia in plan.locales {
          print("[\(localeMedia.locale)]")
          for dt in localeMedia.displayTypes {
            var parts: [String] = []
            if !dt.screenshots.isEmpty {
              parts.append(
                "\(dt.screenshots.count) screenshot\(dt.screenshots.count == 1 ? "" : "s")")
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
          print("Cancelled.")
          return
        }
        print()

        // Fetch all localizations for this version
        let locsResponse = try await client.send(
          Resources.v1.appStoreVersions.id(appVersion.id)
            .appStoreVersionLocalizations.get()
        )
        let locByLocale = Dictionary(
          locsResponse.data.compactMap { loc in
            loc.attributes?.locale.map { ($0, loc) }
          },
          uniquingKeysWith: { first, _ in first }
        )

        var successCount = 0
        var failureCount = 0

        for localeMedia in plan.locales {
          guard let localization = locByLocale[localeMedia.locale] else {
            print("[\(localeMedia.locale)] Skipped — locale not found on this version.")
            continue
          }

          print("[\(localeMedia.locale)]")

          // Fetch existing screenshot sets for this localization
          let screenshotSetsResponse = try await client.send(
            Resources.v1.appStoreVersionLocalizations.id(localization.id)
              .appScreenshotSets.get(limit: 50)
          )
          var screenshotSetsByType: [String: AppScreenshotSet] = [:]
          for set in screenshotSetsResponse.data {
            if let rawType = set.attributes?.screenshotDisplayType?.rawValue {
              screenshotSetsByType[rawType] = set
            }
          }

          // Fetch existing preview sets for this localization
          let previewSetsResponse = try await client.send(
            Resources.v1.appStoreVersionLocalizations.id(localization.id)
              .appPreviewSets.get(limit: 50)
          )
          var previewSetsByType: [String: AppPreviewSet] = [:]
          for set in previewSetsResponse.data {
            if let rawType = set.attributes?.previewType?.rawValue {
              previewSetsByType[rawType] = set
            }
          }

          for dt in localeMedia.displayTypes {
            print("  \(dt.folderName):")

            // Handle screenshots
            if !dt.screenshots.isEmpty, let displayType = dt.screenshotDisplayType {
              let screenshotSetID: String
              if let existingSet = screenshotSetsByType[displayType.rawValue] {
                screenshotSetID = existingSet.id

                if replace {
                  let existing = try await client.send(
                    Resources.v1.appScreenshotSets.id(screenshotSetID)
                      .appScreenshots.get()
                  )
                  for screenshot in existing.data {
                    try await client.send(
                      Resources.v1.appScreenshots.id(screenshot.id).delete
                    )
                  }
                  if !existing.data.isEmpty {
                    print(
                      "    Deleted \(existing.data.count) existing screenshot\(existing.data.count == 1 ? "" : "s")."
                    )
                  }
                }
              } else {
                let createResponse = try await client.send(
                  Resources.v1.appScreenshotSets.post(
                    AppScreenshotSetCreateRequest(
                      data: .init(
                        attributes: .init(screenshotDisplayType: displayType),
                        relationships: .init(
                          appStoreVersionLocalization: .init(
                            data: .init(id: localization.id)
                          )
                        )
                      )
                    )
                  )
                )
                screenshotSetID = createResponse.data.id
              }

              for (i, file) in dt.screenshots.enumerated() {
                print(
                  "    Screenshot \(i + 1)/\(dt.screenshots.count): \(file.fileName)... ",
                  terminator: "")
                fflush(stdout)

                do {
                  // Reserve
                  let reserveResponse = try await client.send(
                    Resources.v1.appScreenshots.post(
                      AppScreenshotCreateRequest(
                        data: .init(
                          attributes: .init(fileSize: file.fileSize, fileName: file.fileName),
                          relationships: .init(
                            appScreenshotSet: .init(data: .init(id: screenshotSetID))
                          )
                        )
                      )
                    )
                  )

                  let screenshotID = reserveResponse.data.id
                  guard let operations = reserveResponse.data.attributes?.uploadOperations,
                    !operations.isEmpty
                  else {
                    throw MediaUploadError.noUploadOperations
                  }

                  // Upload chunks
                  try await uploadChunks(filePath: file.path, operations: operations)

                  // Commit
                  let checksum = try md5Hex(filePath: file.path)
                  _ = try await client.send(
                    Resources.v1.appScreenshots.id(screenshotID).patch(
                      AppScreenshotUpdateRequest(
                        data: .init(
                          id: screenshotID,
                          attributes: .init(
                            sourceFileChecksum: checksum,
                            isUploaded: true
                          )
                        )
                      )
                    )
                  )

                  print("Done.")
                  successCount += 1
                } catch {
                  print("Failed: \(error.localizedDescription)")
                  failureCount += 1
                }
              }
            }

            // Handle previews
            if !dt.previews.isEmpty, let pvType = dt.previewType {
              let previewSetID: String
              if let existingSet = previewSetsByType[pvType.rawValue] {
                previewSetID = existingSet.id

                if replace {
                  let existing = try await client.send(
                    Resources.v1.appPreviewSets.id(previewSetID)
                      .appPreviews.get()
                  )
                  for preview in existing.data {
                    try await client.send(
                      Resources.v1.appPreviews.id(preview.id).delete
                    )
                  }
                  if !existing.data.isEmpty {
                    print(
                      "    Deleted \(existing.data.count) existing preview\(existing.data.count == 1 ? "" : "s")."
                    )
                  }
                }
              } else {
                let createResponse = try await client.send(
                  Resources.v1.appPreviewSets.post(
                    AppPreviewSetCreateRequest(
                      data: .init(
                        attributes: .init(previewType: pvType),
                        relationships: .init(
                          appStoreVersionLocalization: .init(
                            data: .init(id: localization.id)
                          )
                        )
                      )
                    )
                  )
                )
                previewSetID = createResponse.data.id
              }

              for (i, file) in dt.previews.enumerated() {
                print(
                  "    Preview   \(i + 1)/\(dt.previews.count): \(file.fileName)... ",
                  terminator: "")
                fflush(stdout)

                do {
                  let mime = mediaMimeType(for: file.fileName)

                  // Reserve
                  let reserveResponse = try await client.send(
                    Resources.v1.appPreviews.post(
                      AppPreviewCreateRequest(
                        data: .init(
                          attributes: .init(
                            fileSize: file.fileSize,
                            fileName: file.fileName,
                            mimeType: mime
                          ),
                          relationships: .init(
                            appPreviewSet: .init(data: .init(id: previewSetID))
                          )
                        )
                      )
                    )
                  )

                  let previewID = reserveResponse.data.id
                  guard let operations = reserveResponse.data.attributes?.uploadOperations,
                    !operations.isEmpty
                  else {
                    throw MediaUploadError.noUploadOperations
                  }

                  // Upload chunks
                  try await uploadChunks(filePath: file.path, operations: operations)

                  // Commit
                  let checksum = try md5Hex(filePath: file.path)
                  _ = try await client.send(
                    Resources.v1.appPreviews.id(previewID).patch(
                      AppPreviewUpdateRequest(
                        data: .init(
                          id: previewID,
                          attributes: .init(
                            sourceFileChecksum: checksum,
                            isUploaded: true
                          )
                        )
                      )
                    )
                  )

                  print("Done.")
                  successCount += 1
                } catch {
                  print("Failed: \(error.localizedDescription)")
                  failureCount += 1
                }
              }
            }
          }
        }

        // Final summary
        print()
        if failureCount == 0 {
          print("Done. \(successCount) file\(successCount == 1 ? "" : "s") uploaded successfully.")
        } else {
          print("Done. \(successCount) succeeded, \(failureCount) failed.")
        }
      }
    }

    // MARK: - Download

    struct Download: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Download screenshots and app preview videos to a folder."
      )

      @Argument(help: "The bundle identifier of the app.")
      var bundleID: String

      @Option(name: .long, help: "Output folder path. Defaults to <bundle-id>-media.")
      var folder: String?

      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
      var version: String?

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appVersion = try await findVersion(
          appID: app.id, versionString: version, client: client)

        let versionString = appVersion.attributes?.versionString ?? "unknown"
        let versionState = appVersion.attributes?.appVersionState.map { "\($0)" } ?? "unknown"
        print("App:     \(app.attributes?.name ?? bundleID)")
        print("Version: \(versionString)")
        print("State:   \(versionState)")
        print()

        // Fetch all localizations
        let locsResponse = try await client.send(
          Resources.v1.appStoreVersions.id(appVersion.id)
            .appStoreVersionLocalizations.get()
        )

        let outputFolder = expandPath(
          confirmOutputPath(folder ?? "\(bundleID)-media", isDirectory: true))
        let fm = FileManager.default

        var screenshotCount = 0
        var previewCount = 0
        var failureCount = 0

        for loc in locsResponse.data {
          guard let locale = loc.attributes?.locale else { continue }

          // Fetch screenshot sets for this localization
          let setsResponse = try await client.send(
            Resources.v1.appStoreVersionLocalizations.id(loc.id)
              .appScreenshotSets.get(limit: 50)
          )

          for set in setsResponse.data {
            guard let displayType = set.attributes?.screenshotDisplayType else { continue }

            let screenshotsResponse = try await client.send(
              Resources.v1.appScreenshotSets.id(set.id).appScreenshots.get()
            )

            if screenshotsResponse.data.isEmpty { continue }

            let setFolder = "\(outputFolder)/\(locale)/\(displayType.rawValue)"
            try fm.createDirectory(atPath: setFolder, withIntermediateDirectories: true)

            print("[\(locale)] \(displayType.rawValue):")

            for (i, screenshot) in screenshotsResponse.data.enumerated() {
              let originalName = screenshot.attributes?.fileName ?? "\(screenshot.id).png"
              let fileName = String(format: "%02d_%@", i + 1, originalName)

              print(
                "  Screenshot \(i + 1)/\(screenshotsResponse.data.count): \(fileName)... ",
                terminator: "")
              fflush(stdout)

              do {
                guard let templateURL = screenshot.attributes?.imageAsset?.templateURL else {
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
                print("Failed: \(error.localizedDescription)")
                failureCount += 1
              }
            }
          }

          // Fetch preview sets for this localization
          let previewSetsResponse = try await client.send(
            Resources.v1.appStoreVersionLocalizations.id(loc.id)
              .appPreviewSets.get(limit: 50)
          )

          for set in previewSetsResponse.data {
            guard let pvType = set.attributes?.previewType else { continue }

            let previewsResponse = try await client.send(
              Resources.v1.appPreviewSets.id(set.id).appPreviews.get()
            )

            if previewsResponse.data.isEmpty { continue }

            // Map preview type back to screenshot display type folder name
            let folderName = "APP_\(pvType.rawValue)"
            let setFolder = "\(outputFolder)/\(locale)/\(folderName)"
            try fm.createDirectory(atPath: setFolder, withIntermediateDirectories: true)

            print("[\(locale)] \(folderName):")

            for (i, preview) in previewsResponse.data.enumerated() {
              let originalName = preview.attributes?.fileName ?? "\(preview.id).mp4"
              let fileName = String(format: "%02d_%@", i + 1, originalName)

              print(
                "  Preview   \(i + 1)/\(previewsResponse.data.count): \(fileName)... ",
                terminator: "")
              fflush(stdout)

              do {
                guard let videoURLString = preview.attributes?.videoURL else {
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
                print("Failed: \(error.localizedDescription)")
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

      @Argument(help: "The bundle identifier of the app.")
      var bundleID: String

      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
      var version: String?

      @Option(name: .long, help: "Path to the media folder for retrying stuck uploads.")
      var folder: String?

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appVersion = try await findVersion(
          appID: app.id, versionString: version, client: client)

        let versionString = appVersion.attributes?.versionString ?? "unknown"
        print("App:     \(app.attributes?.name ?? bundleID)")
        print("Version: \(versionString)")
        print()

        // Fetch all media status
        let items = try await fetchAllMediaStatus(versionID: appVersion.id, client: client)

        if items.isEmpty {
          print("No media found for this version.")
          return
        }

        // Print status and get counts
        let (total, stuck) = printMediaStatus(items)

        if stuck == 0 {
          print()
          print("All \(total) media item\(total == 1 ? "" : "s") complete.")
          return
        }

        print()
        print("\(total - stuck) of \(total) complete, \(stuck) stuck.")

        // Without --folder, just show status
        guard let folderPath = folder else {
          print("Use --folder to provide the media folder and retry stuck uploads.")
          return
        }

        // Build local file index from the folder
        let plan = try scanMediaFolder(at: folderPath)
        let fileIndex = buildLocalFileIndex(from: plan)

        // Match stuck items to local files
        let stuckItems = items.filter { !$0.isComplete }
        var matchedRetries: [(MediaItemStatus, String)] = []  // (item, localFilePath)
        var unmatchedCount = 0

        for item in stuckItems {
          let prefix = item.isScreenshot ? "screenshot" : "preview"
          let key = "\(item.locale)/\(item.displayTypeName)/\(prefix)/\(item.position)"
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
          print("Cancelled.")
          return
        }
        print()

        var successCount = 0
        var failureCount = 0

        for (item, localPath) in matchedRetries {
          print("[\(item.locale)] \(item.displayTypeName) #\(item.position): ", terminator: "")
          fflush(stdout)

          do {
            // Delete the stuck item
            print("Deleting... ", terminator: "")
            fflush(stdout)
            if item.isScreenshot {
              try await client.send(Resources.v1.appScreenshots.id(item.mediaID).delete)
            } else {
              try await client.send(Resources.v1.appPreviews.id(item.mediaID).delete)
            }

            // Upload replacement
            print("Uploading... ", terminator: "")
            fflush(stdout)

            let fm = FileManager.default
            let attrs = try fm.attributesOfItem(atPath: localPath)
            let fileSize = (attrs[.size] as? Int) ?? 0
            let fileName = (localPath as NSString).lastPathComponent

            if item.isScreenshot {
              let reserveResponse = try await client.send(
                Resources.v1.appScreenshots.post(
                  AppScreenshotCreateRequest(
                    data: .init(
                      attributes: .init(fileSize: fileSize, fileName: fileName),
                      relationships: .init(
                        appScreenshotSet: .init(data: .init(id: item.setID))
                      )
                    )
                  )
                )
              )

              let newID = reserveResponse.data.id
              guard let operations = reserveResponse.data.attributes?.uploadOperations,
                !operations.isEmpty
              else {
                throw MediaUploadError.noUploadOperations
              }

              try await uploadChunks(filePath: localPath, operations: operations)

              let checksum = try md5Hex(filePath: localPath)
              _ = try await client.send(
                Resources.v1.appScreenshots.id(newID).patch(
                  AppScreenshotUpdateRequest(
                    data: .init(
                      id: newID,
                      attributes: .init(
                        sourceFileChecksum: checksum,
                        isUploaded: true
                      )
                    )
                  )
                )
              )

              // Reorder to restore original position
              print("Reordering... ", terminator: "")
              fflush(stdout)
              var newOrder = item.allIDsInSet
              if let idx = newOrder.firstIndex(of: item.mediaID) {
                newOrder.remove(at: idx)
                newOrder.insert(newID, at: idx)
              }
              try await client.send(
                Resources.v1.appScreenshotSets.id(item.setID).relationships.appScreenshots.patch(
                  AppScreenshotSetAppScreenshotsLinkagesRequest(
                    data: newOrder.map { .init(id: $0) }
                  )
                )
              )
            } else {
              let mime = mediaMimeType(for: fileName)
              let reserveResponse = try await client.send(
                Resources.v1.appPreviews.post(
                  AppPreviewCreateRequest(
                    data: .init(
                      attributes: .init(
                        fileSize: fileSize,
                        fileName: fileName,
                        mimeType: mime
                      ),
                      relationships: .init(
                        appPreviewSet: .init(data: .init(id: item.setID))
                      )
                    )
                  )
                )
              )

              let newID = reserveResponse.data.id
              guard let operations = reserveResponse.data.attributes?.uploadOperations,
                !operations.isEmpty
              else {
                throw MediaUploadError.noUploadOperations
              }

              try await uploadChunks(filePath: localPath, operations: operations)

              let checksum = try md5Hex(filePath: localPath)
              _ = try await client.send(
                Resources.v1.appPreviews.id(newID).patch(
                  AppPreviewUpdateRequest(
                    data: .init(
                      id: newID,
                      attributes: .init(
                        sourceFileChecksum: checksum,
                        isUploaded: true
                      )
                    )
                  )
                )
              )

              // Reorder to restore original position
              print("Reordering... ", terminator: "")
              fflush(stdout)
              var newOrder = item.allIDsInSet
              if let idx = newOrder.firstIndex(of: item.mediaID) {
                newOrder.remove(at: idx)
                newOrder.insert(newID, at: idx)
              }
              try await client.send(
                Resources.v1.appPreviewSets.id(item.setID).relationships.appPreviews.patch(
                  AppPreviewSetAppPreviewsLinkagesRequest(
                    data: newOrder.map { .init(id: $0) }
                  )
                )
              )
            }

            print("Done.")
            successCount += 1
          } catch {
            print("Failed: \(error.localizedDescription)")
            failureCount += 1
          }
        }

        // Re-verify
        print()
        print("Re-verifying...")
        print()

        let updatedItems = try await fetchAllMediaStatus(versionID: appVersion.id, client: client)
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
  let setID: String
  let mediaID: String
  let allIDsInSet: [String]
}

private func fetchAllMediaStatus(
  versionID: String, client: AppStoreConnectClient
) async throws -> [MediaItemStatus] {
  let locsResponse = try await client.send(
    Resources.v1.appStoreVersions.id(versionID)
      .appStoreVersionLocalizations.get()
  )

  var items: [MediaItemStatus] = []

  for loc in locsResponse.data {
    guard let locale = loc.attributes?.locale else { continue }

    // Screenshot sets
    let setsResponse = try await client.send(
      Resources.v1.appStoreVersionLocalizations.id(loc.id)
        .appScreenshotSets.get(limit: 50)
    )

    for set in setsResponse.data {
      guard let displayType = set.attributes?.screenshotDisplayType else { continue }

      let screenshotsResponse = try await client.send(
        Resources.v1.appScreenshotSets.id(set.id).appScreenshots.get()
      )

      let allIDs = screenshotsResponse.data.map(\.id)

      for (i, screenshot) in screenshotsResponse.data.enumerated() {
        let name = screenshot.attributes?.fileName ?? "unknown"
        let assetState = screenshot.attributes?.assetDeliveryState?.state
        let stateStr = assetState.map { "\($0)" } ?? "unknown"
        let complete = assetState == .complete

        items.append(MediaItemStatus(
          locale: locale,
          displayTypeName: displayType.rawValue,
          position: i + 1,
          fileName: name,
          state: stateStr,
          isComplete: complete,
          isScreenshot: true,
          setID: set.id,
          mediaID: screenshot.id,
          allIDsInSet: allIDs
        ))
      }
    }

    // Preview sets
    let previewSetsResponse = try await client.send(
      Resources.v1.appStoreVersionLocalizations.id(loc.id)
        .appPreviewSets.get(limit: 50)
    )

    for set in previewSetsResponse.data {
      guard let pvType = set.attributes?.previewType else { continue }
      let displayTypeName = "APP_\(pvType.rawValue)"

      let previewsResponse = try await client.send(
        Resources.v1.appPreviewSets.id(set.id).appPreviews.get()
      )

      let allIDs = previewsResponse.data.map(\.id)

      for (i, preview) in previewsResponse.data.enumerated() {
        let name = preview.attributes?.fileName ?? "unknown"
        let assetState = preview.attributes?.assetDeliveryState?.state
        let stateStr = assetState.map { "\($0)" } ?? "unknown"
        let complete = assetState == .complete

        items.append(MediaItemStatus(
          locale: locale,
          displayTypeName: displayTypeName,
          position: i + 1,
          fileName: name,
          state: stateStr,
          isComplete: complete,
          isScreenshot: false,
          setID: set.id,
          mediaID: preview.id,
          allIDsInSet: allIDs
        ))
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
      print("[\(key.locale)] \(key.displayTypeName): \(setItems.count)/\(setItems.count) complete")
    } else {
      print("[\(key.locale)] \(key.displayTypeName):")
      for item in setItems {
        let marker = item.isComplete ? "complete" : item.state
        print("  #\(item.position)  \(item.fileName)    \(marker)")
      }
    }
  }

  return (total, stuck)
}

/// Builds a lookup from "locale/displayType/screenshot|preview/position" to local file path.
private func buildLocalFileIndex(from plan: MediaUploadPlan) -> [String: String] {
  var index: [String: String] = [:]

  for localeMedia in plan.locales {
    for dt in localeMedia.displayTypes {
      for (i, file) in dt.screenshots.enumerated() {
        index["\(localeMedia.locale)/\(dt.folderName)/screenshot/\(i + 1)"] = file.path
      }
      for (i, file) in dt.previews.enumerated() {
        index["\(localeMedia.locale)/\(dt.folderName)/preview/\(i + 1)"] = file.path
      }
    }
  }

  return index
}
