import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

/// Uploads an .ipa or a Mac .pkg through the App Store Connect API's build upload resources instead
/// of altool: create a build upload, reserve its file, PUT the chunks to the presigned URLs, commit the
/// file with its MD5, then wait until Apple has taken the upload in (state COMPLETE) or rejected it (FAILED).
enum BuildUploader {
  /// What the upload needs to know about the app.
  struct AppInfo {
    let bundleID: String
    let version: String
    let buildNumber: String
    /// App Store Connect platform: IOS, MAC_OS, TV_OS or VISION_OS.
    let platform: String
  }

  static func info(path: String) throws -> AppInfo {
    let name = (path as NSString).lastPathComponent
    if path.hasSuffix(".pkg") {
      // A product archive's Distribution file lists the bundles with their versions; the app is
      // the one at the payload root (the others are its extensions).
      let xml = try XMLDocument(data: try output("/usr/bin/tar", ["-xOf", path, "Distribution"]))
      let bundles = try xml.nodes(forXPath: "//bundle").compactMap { $0 as? XMLElement }
      guard let app = bundles.first(where: { !($0.attribute(forName: "path")?.stringValue ?? "/").contains("/") }) ?? bundles.first,
        let bundleID = app.attribute(forName: "id")?.stringValue,
        let version = app.attribute(forName: "CFBundleShortVersionString")?.stringValue,
        let build = app.attribute(forName: "CFBundleVersion")?.stringValue
      else { throw ValidationError("Couldn't read the app's bundle version from \(name)'s Distribution file.") }
      return AppInfo(bundleID: bundleID, version: version, buildNumber: build, platform: "MAC_OS")
    }
    // The Info.plist at the app bundle's root, by its exact name: unzip's `*` crosses folders, so
    // `Payload/*.app/Info.plist` also matched an embedded watch app's (Payload/X.app/Watch/Y.app/
    // Info.plist) and printed two plists that read as none.
    let entries = String(decoding: try output("/usr/bin/unzip", ["-Z1", path]), as: UTF8.self).split(separator: "\n")
    let infoPlist = entries.first { entry in
      let parts = entry.split(separator: "/")
      return parts.count == 3 && parts[0] == "Payload" && parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
    }
    guard let infoPlist,
      let plist = try? PropertyListSerialization.propertyList(
        from: try output("/usr/bin/unzip", ["-p", path, String(infoPlist)]), format: nil) as? [String: Any],
      let bundleID = plist["CFBundleIdentifier"] as? String,
      let version = plist["CFBundleShortVersionString"] as? String,
      let build = plist["CFBundleVersion"] as? String
    else { throw ValidationError("Couldn't read the app's Info.plist from \(name).") }
    let platforms = plist["CFBundleSupportedPlatforms"] as? [String] ?? []
    let platform = platforms.contains("AppleTVOS") ? "TV_OS" : platforms.contains("XROS") ? "VISION_OS" : "IOS"
    return AppInfo(bundleID: bundleID, version: version, buildNumber: build, platform: platform)
  }

  /// The standard output of a tool that must succeed.
  private static func output(_ tool: String, _ arguments: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw ValidationError("\((tool as NSString).lastPathComponent) failed reading \((arguments.dropFirst().first ?? "") as String).")
    }
    return data
  }

  /// Uploads the .ipa or .pkg and waits for Apple's verdict on it. Returns the uploaded build number.
  @discardableResult
  static func upload(path: String) async throws -> String {
    let info = try info(path: path)
    let client = try ClientFactory.makeClient()
    let app = try await findApp(bundleID: info.bundleID, client: client)
    let fileName = (path as NSString).lastPathComponent
    let size = try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int ?? 0
    EventOutput.log("Uploading \(fileName): \(info.bundleID) \(info.version) (\(info.buildNumber)), \(formatState(info.platform))")
    EventOutput.emit(BuildEvent(
      event: "uploading", path: path, bundleID: info.bundleID, version: info.version, build: info.buildNumber,
      platform: info.platform, bytes: Int64(size)))

    let upload = try await client.buildUploadsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(cfBundleShortVersionString: info.version, cfBundleVersion: info.buildNumber, platform: info.platform),
      relationships: .init(app: .init(data: .init(id: app.id, _type: "apps"))),
      _type: "buildUploads"
    )))).created.body.json.data

    let file = try await client.buildUploadFilesCreateInstance(body: .json(.init(data: .init(
      attributes: .init(
        assetType: "ASSET", fileName: fileName, fileSize: Int64(size),
        uti: path.hasSuffix(".pkg") ? "com.apple.pkg" : "com.apple.ipa"),
      relationships: .init(buildUpload: .init(data: .init(id: upload.id, _type: "buildUploads"))),
      _type: "buildUploadFiles"
    )))).created.body.json.data

    try await uploadChunks(filePath: path, operations: (file.attributes?.uploadOperations ?? []).map(DeliveryOperation.init))
    let checksum = try md5Hex(filePath: path)
    _ = try await withTransientRetry {
      try await client.buildUploadFilesUpdateInstance(
        path: .init(id: file.id),
        body: .json(.init(data: .init(
          attributes: .init(sourceFileChecksums: .init(file: .init(algorithm: "MD5", hash: checksum)), uploaded: true),
          id: file.id, _type: "buildUploadFiles"
        )))
      ).ok
    }
    if EventOutput.emitsEvents {
      EventOutput.log("Uploaded. Waiting for App Store Connect to take it in...")
      EventOutput.emit(BuildEvent(event: "processing"))
    } else {
      print("Uploaded. Waiting for App Store Connect to take it in", terminator: "")
      fflush(stdout)
    }
    let warnings = try await waitForUpload(id: upload.id, client: client)

    // Records of this build still waiting for a file can't complete any more: an earlier run's that
    // failed, or a second one made when a flaky connection sent the create request again (seen live).
    do {
      let stray = try await strayUploads(
        appID: app.id, version: info.version, build: info.buildNumber, platform: info.platform, client: client)
      if try await delete(stray, client: client) > 0 {
        EventOutput.log("Removed \(stray.count) unused upload record\(stray.count == 1 ? "" : "s") of this build.")
      }
    } catch {
      EventOutput.log(yellow("Warning:") + " couldn't remove unused upload records of this build: \(describeError(error))")
    }
    EventOutput.emit(BuildEvent(
      event: "finished", bundleID: info.bundleID, version: info.version, build: info.buildNumber, platform: info.platform,
      warnings: warnings))
    return info.buildNumber
  }

  /// The app's upload records that will never complete (`BuildUploadRecords.stale`).
  static func strayUploads(
    appID: String, version: String? = nil, build: String? = nil, platform: String? = nil, client: ASCClient
  ) async throws -> [BuildUploadRecords.Upload] {
    try await BuildUploadRecords.stale(appID: appID, version: version, build: build, platform: platform, client: client)
  }

  /// Deletes upload records; returns how many went (none under dry run).
  @discardableResult
  static func delete(_ uploads: [BuildUploadRecords.Upload], client: ASCClient) async throws -> Int {
    var deleted = 0
    for upload in uploads {
      let done = try await unlessDryRunStopped {
        try await BuildUploadRecords.delete(id: upload.id, client: client)
      }
      if done != nil { deleted += 1 }
    }
    return deleted
  }

  /// Polls the build upload until COMPLETE (returns Apple's warnings) or FAILED (throws with Apple's
  /// messages).
  private static func waitForUpload(id: String, client: ASCClient) async throws -> [String] {
    let deadline = Date().addingTimeInterval(45 * 60)
    while Date() < deadline {
      let upload = try await withTransientRetry {
        try await client.buildUploadsGetInstance(path: .init(id: id)).ok.body.json.data
      }
      let state = upload.attributes?.state
      switch state?.state {
      case "COMPLETE":
        if !EventOutput.emitsEvents { print(" done.") }
        printDetails(state?.warnings, label: "Warning")
        printDetails(state?.infos, label: "Note")
        EventOutput.log(green("Upload complete.") + " Processing continues in App Store Connect ('ascelerate builds await-processing').")
        return (state?.warnings ?? []).map(describe)
      case "FAILED":
        if !EventOutput.emitsEvents { print() }
        let errors = (state?.errors ?? []).map(describe)
        throw ValidationError("App Store Connect rejected the upload:\n" + (errors.isEmpty ? "  (no details)" : errors.map { "  - \($0)" }.joined(separator: "\n")))
      default:
        if !EventOutput.emitsEvents {
          print(".", terminator: "")
          fflush(stdout)
        }
        // Each poll counts against the hourly API quota; Apple takes minutes, not seconds.
        try await Task.sleep(for: .seconds(30))
      }
    }
    if !EventOutput.emitsEvents { print() }
    throw ValidationError("The upload didn't finish within 45 minutes; check it in App Store Connect.")
  }

  private static func printDetails(_ details: [Components.Schemas.StateDetail]?, label: String) {
    for detail in details ?? [] { EventOutput.log("  \(label): \(describe(detail))") }
  }

  private static func describe(_ detail: Components.Schemas.StateDetail) -> String {
    [detail.code, detail.description].compactMap { $0 }.joined(separator: ": ")
  }
}

/// A build upload chunk (`DeliveryFileUploadOperation` has 64-bit offsets and part numbers) in the shape
/// `uploadChunks` takes.
private struct DeliveryOperation: UploadOperationDescribing {
  let url: String?
  let method: String?
  let offset: Int?
  let length: Int?
  let headers: [(name: String, value: String)]

  init(_ operation: Components.Schemas.DeliveryFileUploadOperation) {
    url = operation.url
    method = operation.method
    offset = operation.offset.map(Int.init)
    length = operation.length.map(Int.init)
    headers = (operation.requestHeaders ?? []).compactMap { header in
      header.name.flatMap { name in header.value.map { (name, $0) } }
    }
  }
}
