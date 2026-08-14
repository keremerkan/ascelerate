import AppStoreAPI
import AppStoreConnect
import ArgumentParser
import Foundation

struct BuildsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "builds",
    abstract: "Manage builds.",
    subcommands: [List.self, AwaitProcessing.self, Archive.self, Upload.self, Validate.self]
  )

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List builds."
    )

    @Option(name: .long, help: "Filter by bundle identifier.",
            completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String?

    @Option(name: .long, help: "Filter by app version (e.g. 14.3).")
    var version: String?

    @OptionGroup var platformOption: PlatformOption

    @OptionGroup var jsonOption: JSONOption

    private struct Entry: Encodable {
      let id: String
      let buildNumber: String?
      let version: String?
      let platform: String?
      let processingState: String?
      let uploadedDate: Date?
    }

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()

      var filterApp: [String]?
      if let bundleID {
        let app = try await findApp(bundleID: bundleID, client: client)
        filterApp = [app.id]
      }

      var entries: [Entry] = []

      let request = Resources.v1.builds.get(
        filterPreReleaseVersionVersion: version.map { [$0] },
        filterPreReleaseVersionPlatform: platformFilter(try platformOption.parsed()),
        filterApp: filterApp,
        sort: [.minusUploadedDate],
        include: [.preReleaseVersion]
      )

      for try await page in client.pages(request) {
        // Index included pre-release versions
        var prereleaseVersions: [String: PrereleaseVersion] = [:]
        for item in page.included ?? [] {
          if case .prereleaseVersion(let v) = item {
            prereleaseVersions[v.id] = v
          }
        }

        for build in page.data {
          let train = build.relationships?.preReleaseVersion?.data
            .flatMap { prereleaseVersions[$0.id] }
          entries.append(Entry(
            id: build.id,
            buildNumber: build.attributes?.version,
            version: train?.attributes?.version,
            platform: train?.attributes?.platform?.rawValue,
            processingState: build.attributes?.processingState?.rawValue,
            uploadedDate: build.attributes?.uploadedDate
          ))
        }
      }

      if jsonOption.json {
        try printJSON(entries)
        return
      }

      Table.print(
        headers: ["Version", "Platform", "Build", "State", "Uploaded"],
        rows: entries.map { e in
          [
            e.version ?? "—",
            e.platform.map { formatState($0) } ?? "—",
            e.buildNumber ?? "—",
            e.processingState.map { formatState($0) } ?? "—",
            e.uploadedDate.map { formatDate($0) } ?? "—",
          ]
        }
      )

      print()
      print("Note: Recently uploaded builds may take a few minutes to appear.")
    }
  }

  struct AwaitProcessing: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "await-processing",
      abstract: "Wait for a build to finish processing."
    )

    @Argument(help: "The app's bundle identifier.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .long, help: "Build version number to wait for (e.g. 903). If omitted, waits for the latest build.")
    var buildVersion: String?

    @OptionGroup var platformOption: PlatformOption

    @Option(name: .long, help: "Polling interval in seconds (default: 30).")
    var interval: Int = 30

    @Option(name: .long, help: "Timeout in minutes (default: 30).")
    var timeout: Int = 30

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let platform = try platformOption.parsed()

      // Per-platform lookup: with two uploads in one workflow (iOS + macOS), each
      // await must inherit its own platform's build number, not the last upload's.
      let effectiveVersion = buildVersion ?? lastUploadedBuild(for: platform)
      let label: String
      if let v = effectiveVersion {
        label = "build \(v)"
        if buildVersion == nil {
          print("Using build version \(v) from previous upload step.")
        }
      } else {
        label = "latest build"
      }
      print("Waiting for \(label) to finish processing...")
      print("  Polling every \(interval)s, timeout \(timeout)m")
      print()

      _ = try await awaitBuildProcessing(
        appID: app.id,
        buildVersion: effectiveVersion,
        platform: platform,
        client: client,
        interval: interval,
        timeout: timeout
      )
    }
  }

  struct Archive: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Archive an Xcode project via xcodebuild."
    )

    @Option(name: .long, help: "Path to .xcodeproj (auto-detected if omitted).")
    var project: String?

    @Option(name: .long, help: "Path to .xcworkspace (auto-detected if omitted).")
    var workspace: String?

    @Option(name: .long, help: "Build scheme (auto-detected if only one exists).")
    var scheme: String?

    @Option(name: .long, help: "Output directory for the .xcarchive.")
    var output: String?

    @Option(name: .long, help: "Build configuration (default: Release).")
    var configuration: String?

    @Option(name: .long, help: "Destination (default: generic/platform=iOS).")
    var destination: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() throws {
      if yes { autoConfirm = true }

      try ensureXcodebuild()

      // 1. Detect project or workspace
      let (buildFlag, buildPath) = try detectProject()

      // 2. Detect scheme
      let schemeName = try detectScheme(buildFlag: buildFlag, buildPath: buildPath)

      // 3. Clean before archiving
      print("Cleaning build...")
      fflush(stdout)

      let cleanProcess = Process()
      cleanProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
      cleanProcess.arguments = [
        "clean",
        buildFlag, buildPath,
        "-scheme", schemeName,
        "-configuration", configuration ?? "Release",
      ]
      cleanProcess.standardOutput = FileHandle.standardOutput
      cleanProcess.standardError = FileHandle.standardError

      try cleanProcess.run()
      trackProcess(cleanProcess)
      setupSignalHandler()
      cleanProcess.waitUntilExit()
      untrackProcess(cleanProcess)

      if cleanProcess.terminationStatus != 0 {
        throw ExitCode(cleanProcess.terminationStatus)
      }

      // 4. Build archive arguments
      var args = [
        "archive",
        buildFlag, buildPath,
        "-scheme", schemeName,
        "-configuration", configuration ?? "Release",
        "-destination", destination ?? "generic/platform=iOS",
        "-allowProvisioningUpdates",
      ]

      var archivePath: String?
      if let output {
        let dir = expandPath(output)
        let path = (dir as NSString).appendingPathComponent("\(schemeName).xcarchive")
        let confirmed = confirmOutputPath(path, isDirectory: true)
        let confirmedDir = (confirmed as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: confirmedDir, withIntermediateDirectories: true)
        args += ["-archivePath", confirmed]
        archivePath = confirmed
      }

      // 5. Run xcodebuild archive
      print("Archiving scheme '\(schemeName)'...")
      print()
      fflush(stdout)

      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
      process.arguments = args
      process.standardOutput = FileHandle.standardOutput
      process.standardError = FileHandle.standardError

      try process.run()
      trackProcess(process)
      setupSignalHandler()
      process.waitUntilExit()
      untrackProcess(process)

      if process.terminationStatus != 0 {
        throw ExitCode(process.terminationStatus)
      }

      // 6. Print result
      print()
      if let archivePath {
        print("Archive created at: \(archivePath)")
      } else {
        print("Archive complete. The .xcarchive is in Xcode's default archive location:")
        print("  ~/Library/Developer/Xcode/Archives/")
      }
    }

    /// Finds a .xcworkspace or .xcodeproj in the current directory, or uses the explicit flag.
    private func detectProject() throws -> (String, String) {
      if let workspace {
        return ("-workspace", expandPath(workspace))
      }
      if let project {
        return ("-project", expandPath(project))
      }

      let fm = FileManager.default
      let cwd = fm.currentDirectoryPath
      let contents = try fm.contentsOfDirectory(atPath: cwd)

      // Prefer workspace over project
      if let ws = contents.first(where: { $0.hasSuffix(".xcworkspace") && !$0.hasPrefix(".") }) {
        let path = (cwd as NSString).appendingPathComponent(ws)
        print("Using workspace: \(ws)")
        return ("-workspace", path)
      }
      if let proj = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
        let path = (cwd as NSString).appendingPathComponent(proj)
        print("Using project: \(proj)")
        return ("-project", path)
      }

      throw ValidationError(
        "No .xcworkspace or .xcodeproj found in the current directory. Use --workspace or --project to specify one."
      )
    }

    /// Runs `xcodebuild -list -json` to discover schemes. Uses --scheme if provided.
    private func detectScheme(buildFlag: String, buildPath: String) throws -> String {
      if let scheme { return scheme }

      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
      process.arguments = ["-list", "-json", buildFlag, buildPath]

      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice

      try process.run()
      process.waitUntilExit()

      guard process.terminationStatus == 0 else {
        throw ValidationError("Failed to list schemes. Check that the project/workspace is valid.")
      }

      let data = pipe.fileHandleForReading.readDataToEndOfFile()

      struct XcodeList: Decodable {
        struct Project: Decodable { var schemes: [String]? }
        struct Workspace: Decodable { var schemes: [String]? }
        var project: Project?
        var workspace: Workspace?
      }

      let list = try JSONDecoder().decode(XcodeList.self, from: data)
      let schemes = list.project?.schemes ?? list.workspace?.schemes ?? []

      if schemes.isEmpty {
        throw ValidationError("No schemes found in the project/workspace.")
      }
      if schemes.count == 1 {
        let name = schemes[0]
        print("Using scheme: \(name)")
        return name
      }

      let schemeList = schemes.map { "  - \($0)" }.joined(separator: "\n")
      throw ValidationError(
        """
        Multiple schemes found. Use --scheme to specify one:
        \(schemeList)
        """)
    }
  }

  struct Upload: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Upload a build to App Store Connect via xcrun altool."
    )

    @Argument(help: "Path to the .ipa, .pkg, or .xcarchive file.",
              completion: .file(extensions: ["ipa", "pkg", "xcarchive"]))
    var file: String?

    @Flag(name: .long, help: "Use the latest .xcarchive from Xcode's archive location.")
    var latest = false

    @Option(name: .long, help: "Filter archives by exact bundle identifier (use with --latest).")
    var bundleID: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() throws {
      if yes { autoConfirm = true }
      try ensureAltool()

      if file != nil && latest {
        throw ValidationError("Cannot specify both a file path and --latest.")
      }
      if bundleID != nil && !latest {
        throw ValidationError("--bundle-id requires --latest.")
      }

      let expandedPath: String
      var uploadedBuildNumber: String?
      if latest {
        let archive = try findLatestArchive(bundleID: bundleID)
        expandedPath = archive.path
        uploadedBuildNumber = archive.buildNumber
        print("Found archive: \((archive.path as NSString).lastPathComponent)")
        print("  Bundle ID:  \(archive.bundleID)")
        print("  Version:    \(archive.version) (\(archive.buildNumber))")
        print("  Created:    \(formatDate(archive.creationDate))")
        print()
        guard confirm("Upload this archive? [y/N] ") else { return }
      } else {
        expandedPath = try resolveFilePath(file, prompt: "Path to .ipa, .pkg, or .xcarchive file: ")
        // Try to extract build number from .xcarchive
        if expandedPath.hasSuffix(".xcarchive") {
          uploadedBuildNumber = buildNumberFromArchive(expandedPath)
        }
      }

      let config = try Config.load()

      // Export .xcarchive to .ipa/.pkg if needed
      let (uploadPath, tempDir, archivePlatform) = try resolveUploadable(expandedPath)
      defer { if let dir = tempDir { try? FileManager.default.removeItem(atPath: dir) } }

      print("Uploading \((uploadPath as NSString).lastPathComponent)...")
      print()
      fflush(stdout)

      var altoolArgs = [
        "altool", "--upload-app",
        "-f", uploadPath,
        "--apiKey", config.keyId,
        "--apiIssuer", config.issuerId,
        "--p8-file-path", config.privateKeyPath,
        "--show-progress",
      ]
      if let archivePlatform {
        altoolArgs += ["--type", archivePlatform.altoolType]
      }

      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
      process.arguments = altoolArgs
      process.standardOutput = FileHandle.standardOutput
      process.standardError = FileHandle.standardError

      try process.run()
      trackProcess(process)
      setupSignalHandler()
      process.waitUntilExit()
      untrackProcess(process)

      if process.terminationStatus != 0 {
        throw ExitCode(process.terminationStatus)
      }

      if let buildNumber = uploadedBuildNumber {
        recordUploadedBuild(buildNumber, platform: archivePlatform?.ascPlatform)
      }
    }
  }

  struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Validate a build before uploading via xcrun altool."
    )

    @Argument(help: "Path to the .ipa, .pkg, or .xcarchive file.",
              completion: .file(extensions: ["ipa", "pkg", "xcarchive"]))
    var file: String?

    @Flag(name: .long, help: "Use the latest .xcarchive from Xcode's archive location.")
    var latest = false

    @Option(name: .long, help: "Filter archives by exact bundle identifier (use with --latest).")
    var bundleID: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() throws {
      if yes { autoConfirm = true }
      try ensureAltool()

      if file != nil && latest {
        throw ValidationError("Cannot specify both a file path and --latest.")
      }
      if bundleID != nil && !latest {
        throw ValidationError("--bundle-id requires --latest.")
      }

      let expandedPath: String
      if latest {
        let archive = try findLatestArchive(bundleID: bundleID)
        expandedPath = archive.path
        print("Found archive: \((archive.path as NSString).lastPathComponent)")
        print("  Bundle ID:  \(archive.bundleID)")
        print("  Version:    \(archive.version) (\(archive.buildNumber))")
        print("  Created:    \(formatDate(archive.creationDate))")
        print()
        guard confirm("Validate this archive? [y/N] ") else { return }
      } else {
        expandedPath = try resolveFilePath(file, prompt: "Path to .ipa, .pkg, or .xcarchive file: ")
      }

      let config = try Config.load()

      // Export .xcarchive to .ipa/.pkg if needed
      let (uploadPath, tempDir, archivePlatform) = try resolveUploadable(expandedPath)
      defer { if let dir = tempDir { try? FileManager.default.removeItem(atPath: dir) } }

      print("Validating \((uploadPath as NSString).lastPathComponent)...")
      print()
      fflush(stdout)

      var altoolArgs = [
        "altool", "--validate-app",
        "-f", uploadPath,
        "--apiKey", config.keyId,
        "--apiIssuer", config.issuerId,
        "--p8-file-path", config.privateKeyPath,
      ]
      if let archivePlatform {
        altoolArgs += ["--type", archivePlatform.altoolType]
      }

      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
      process.arguments = altoolArgs
      process.standardOutput = FileHandle.standardOutput
      process.standardError = FileHandle.standardError

      try process.run()
      trackProcess(process)
      setupSignalHandler()
      process.waitUntilExit()
      untrackProcess(process)

      if process.terminationStatus != 0 {
        throw ExitCode(process.terminationStatus)
      }
    }
  }
}

// MARK: - Helpers

private func ensureXcodebuild() throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
  process.arguments = ["-version"]
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice

  try process.run()
  process.waitUntilExit()

  if process.terminationStatus != 0 {
    throw ValidationError(
      """
      'xcodebuild' is not available. This command requires Xcode to be installed.
        1. Install Xcode from the Mac App Store
        2. Run: sudo xcode-select --switch /Applications/Xcode.app
        3. Accept the license: sudo xcodebuild -license accept
      """)
  }
}

private func ensureAltool() throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
  process.arguments = ["--find", "altool"]
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice

  try process.run()
  process.waitUntilExit()

  if process.terminationStatus != 0 {
    throw ValidationError(
      """
      'xcrun altool' is not available. This command requires Xcode to be installed.
        1. Install Xcode from the Mac App Store
        2. Run: sudo xcode-select --switch /Applications/Xcode.app
        3. Accept the license: sudo xcodebuild -license accept
      """)
  }
}

private struct ArchiveInfo {
  let path: String
  let bundleID: String
  let version: String
  let buildNumber: String
  let creationDate: Date
}

/// Finds the most recent .xcarchive in Xcode's default archive location.
/// Reads each archive's Info.plist to extract bundle ID and creation date.
private func findLatestArchive(bundleID: String?) throws -> ArchiveInfo {
  let archivesDir = expandPath("~/Library/Developer/Xcode/Archives")
  let fm = FileManager.default

  guard fm.fileExists(atPath: archivesDir) else {
    throw ValidationError("No Xcode archives found at ~/Library/Developer/Xcode/Archives/")
  }

  let dateDirs = try fm.contentsOfDirectory(atPath: archivesDir)
  var archives: [ArchiveInfo] = []

  for dateDir in dateDirs {
    let datePath = (archivesDir as NSString).appendingPathComponent(dateDir)
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: datePath, isDirectory: &isDir), isDir.boolValue else { continue }

    let items = (try? fm.contentsOfDirectory(atPath: datePath)) ?? []
    for item in items where item.hasSuffix(".xcarchive") {
      let archivePath = (datePath as NSString).appendingPathComponent(item)
      let infoPlistPath = (archivePath as NSString).appendingPathComponent("Info.plist")

      guard let data = fm.contents(atPath: infoPlistPath),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let appProps = plist["ApplicationProperties"] as? [String: Any],
            let archiveBundleID = appProps["CFBundleIdentifier"] as? String,
            let creationDate = plist["CreationDate"] as? Date
      else { continue }

      // Exact bundle ID match if filter is provided
      if let bundleID, archiveBundleID != bundleID { continue }

      let version = appProps["CFBundleShortVersionString"] as? String ?? "—"
      let build = appProps["CFBundleVersion"] as? String ?? "—"

      archives.append(ArchiveInfo(
        path: archivePath,
        bundleID: archiveBundleID,
        version: version,
        buildNumber: build,
        creationDate: creationDate
      ))
    }
  }

  archives.sort { $0.creationDate > $1.creationDate }

  guard let latest = archives.first else {
    if let bundleID {
      throw ValidationError("No archives found matching bundle ID '\(bundleID)'.")
    }
    throw ValidationError("No archives found in ~/Library/Developer/Xcode/Archives/")
  }

  return latest
}

private func resolveFilePath(_ file: String?, prompt: String) throws -> String {
  let filePath: String
  if let f = file {
    filePath = f
  } else {
    print(prompt, terminator: "")
    guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
      !line.isEmpty
    else {
      throw ValidationError("No file path provided.")
    }
    filePath = line
  }

  let expandedPath = expandPath(filePath)
  guard FileManager.default.fileExists(atPath: expandedPath) else {
    throw ValidationError("File not found at '\(expandedPath)'.")
  }

  return expandedPath
}

/// The platform of an .xcarchive, detected from the archived app's Info.plist.
private enum ArchivePlatform {
  case iOS, macOS, tvOS, visionOS

  /// The value for altool's `--type` flag.
  var altoolType: String {
    switch self {
    case .iOS: return "ios"
    case .macOS: return "macos"
    case .tvOS: return "appletvos"
    case .visionOS: return "visionos"
    }
  }

  /// The file extension an App Store export produces for this platform.
  var exportExtension: String {
    self == .macOS ? "pkg" : "ipa"
  }

  /// The corresponding App Store Connect API platform.
  var ascPlatform: Platform {
    switch self {
    case .iOS: return .iOS
    case .macOS: return .macOS
    case .tvOS: return .tvOS
    case .visionOS: return .visionOS
    }
  }

  var label: String {
    switch self {
    case .iOS: return "iOS"
    case .macOS: return "macOS"
    case .tvOS: return "tvOS"
    case .visionOS: return "visionOS"
    }
  }
}

/// Detects the archive's platform: reads DTPlatformName from the app's Info.plist,
/// falling back to bundle layout (macOS apps keep Info.plist under Contents/).
private func detectArchivePlatform(_ archivePath: String) -> ArchivePlatform {
  let fm = FileManager.default
  let archivePlistPath = (archivePath as NSString).appendingPathComponent("Info.plist")

  var appPath: String?
  if let data = fm.contents(atPath: archivePlistPath),
     let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
     let appProps = plist["ApplicationProperties"] as? [String: Any],
     let relativePath = appProps["ApplicationPath"] as? String {
    appPath = (archivePath as NSString).appendingPathComponent("Products/\(relativePath)")
  }
  guard let appPath else { return .iOS }

  let macPlist = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
  let iosPlist = (appPath as NSString).appendingPathComponent("Info.plist")
  let isMacLayout = fm.fileExists(atPath: macPlist)

  guard let data = fm.contents(atPath: isMacLayout ? macPlist : iosPlist),
        let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
  else {
    return isMacLayout ? .macOS : .iOS
  }

  switch (info["DTPlatformName"] as? String)?.lowercased() {
  case "macosx": return .macOS
  case "appletvos": return .tvOS
  case "xros", "visionos": return .visionOS
  case "iphoneos": return .iOS
  default: return isMacLayout ? .macOS : .iOS
  }
}

/// If the path is an .xcarchive, exports it to a temporary .ipa (iOS-family) or
/// .pkg (macOS) and returns that path.
/// Returns (uploadablePath, tempDirToCleanUp, platform).
/// tempDir is nil if no export was needed; platform is nil when it cannot be
/// detected (bare .ipa input — altool infers it from the package).
private func resolveUploadable(_ path: String) throws -> (String, String?, ArchivePlatform?) {
  let ext = (path as NSString).pathExtension.lowercased()

  guard ext == "xcarchive" else {
    // Only macOS App Store packages ship as .pkg.
    return (path, nil, ext == "pkg" ? .macOS : nil)
  }

  let platform = detectArchivePlatform(path)
  print("Exporting .xcarchive to .\(platform.exportExtension) (\(platform.label))...")
  fflush(stdout)

  // UUID, not PID: a predictable path could pick up a stale export from a prior crashed run.
  let tempDir = NSTemporaryDirectory() + "ascelerate-export-\(UUID().uuidString)"
  let exportDir = tempDir + "/output"
  let plistPath = tempDir + "/ExportOptions.plist"

  try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

  // Write ExportOptions.plist for App Store export with automatic signing
  let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>method</key>
        <string>app-store-connect</string>
        <key>destination</key>
        <string>export</string>
        <key>signingStyle</key>
        <string>automatic</string>
    </dict>
    </plist>
    """
  try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
  process.arguments = [
    "-exportArchive",
    "-archivePath", path,
    "-exportPath", exportDir,
    "-exportOptionsPlist", plistPath,
    "-allowProvisioningUpdates",
  ]
  // Capture stdout (it carries the *.xcdistributionlogs path) and surface it only on failure.
  let stdoutPipe = Pipe()
  process.standardOutput = stdoutPipe
  process.standardError = FileHandle.standardError

  try process.run()
  let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()

  if process.terminationStatus != 0 {
    try? FileManager.default.removeItem(atPath: tempDir)
    if let output = String(data: stdoutData, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
      print(output)
    }
    throw ValidationError(
      """
      Failed to export .xcarchive for \(platform.label) App Store distribution.
      Check the signing certificates\(platform == .macOS ? " (macOS needs a Mac Installer Distribution certificate for the .pkg installer signature)" : "") \
      and Xcode's export log in the *.xcdistributionlogs bundle above.
      """)
  }

  // Find the exported package
  let contents = try FileManager.default.contentsOfDirectory(atPath: exportDir)
  guard let exportName = contents.first(where: { $0.hasSuffix(".\(platform.exportExtension)") }) else {
    try? FileManager.default.removeItem(atPath: tempDir)
    throw ValidationError("No .\(platform.exportExtension) found after exporting the \(platform.label) .xcarchive.")
  }

  let exportPath = exportDir + "/" + exportName
  print("Exported \(exportName)")
  print()
  fflush(stdout)

  return (exportPath, tempDir, platform)
}

/// Extracts CFBundleVersion from an .xcarchive's Info.plist, or nil if unavailable.
private func buildNumberFromArchive(_ archivePath: String) -> String? {
  let plistPath = (archivePath as NSString).appendingPathComponent("Info.plist")
  guard let data = FileManager.default.contents(atPath: plistPath),
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
        let appProps = plist["ApplicationProperties"] as? [String: Any],
        let buildNumber = appProps["CFBundleVersion"] as? String
  else { return nil }
  return buildNumber
}
