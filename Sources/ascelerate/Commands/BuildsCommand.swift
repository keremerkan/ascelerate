import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

struct BuildsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "builds",
    abstract: "Manage builds.",
    subcommands: [List.self, Uploads.self, AwaitProcessing.self, Archive.self, Upload.self, Validate.self]
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

      let platform = try platformOption.parsed()
      let pages = try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.buildsGetCollection(query: .init(
          filterPreReleaseVersionVersion: version.map { [$0] },
          filterPreReleaseVersionPlatform: platformFilter(platform),
          filterApp: filterApp,
          sort: [.minusUploadedDate],
          include: [.preReleaseVersion]
        )).ok.body.json
      }

      var entries: [Entry] = []
      for page in pages {
        // Index included pre-release versions
        var prereleaseVersions: [String: Components.Schemas.PrereleaseVersion] = [:]
        for item in page.included ?? [] {
          if case .preReleaseVersions(let v) = item {
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
            platform: train?.attributes?.platform,
            processingState: build.attributes?.processingState,
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

  /// Uploads Apple has received, through the API or altool, with Apple's verdict on each: the place
  /// to look when an upload never turns into a build.
  struct Uploads: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List recent build uploads with their state and Apple's errors and warnings."
    )

    @Argument(help: "Bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @OptionGroup var platformOption: PlatformOption

    @Option(name: .long, help: "Number of uploads to show (default 10).")
    var limit = 10

    @Flag(name: .long, help: "Delete upload records that will never complete: waiting for a file while another upload of the same build moved on, or for over a day.")
    var deleteStale = false

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt (with --delete-stale).")
    var yes = false

    @OptionGroup var jsonOption: JSONOption

    struct Detail: Encodable {
      let code: String?
      let description: String?
    }

    struct Entry: Encodable {
      let id: String
      let version: String?
      let build: String?
      let platform: String?
      let state: String?
      let createdDate: Date?
      let uploadedDate: Date?
      let errors: [Detail]?
      let warnings: [Detail]?
    }

    func run() async throws {
      jsonOption.activate()
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      if deleteStale {
        let stale = try await BuildUploader.strayUploads(appID: app.id, platform: try platformOption.parsed()?.rawValue, client: client)
        guard !stale.isEmpty else {
          print("No stale upload records.")
          return
        }
        for u in stale {
          let a = u.attributes
          print("  \(a?.cfBundleShortVersionString ?? "-") (\(a?.cfBundleVersion ?? "-")) \(formatState(a?.platform ?? "-")), created \(a?.createdDate.map { formatDate($0) } ?? "-")  \(u.id)")
        }
        guard confirm("Delete \(stale.count == 1 ? "this record" : "these \(stale.count) records")? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        let deleted = try await BuildUploader.delete(stale, client: client)
        print(green("Deleted") + " \(deleted) stale upload record\(deleted == 1 ? "" : "s").")
        return
      }
      // Apple sorts records without an uploadedDate (never finished) first whatever the order, so
      // take them all and order by creation here.
      let uploads = try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.appsBuildUploadsGetToManyRelated(
          path: .init(id: app.id), query: .init(filterPlatform: platformFilter(try platformOption.parsed()), limit: 200)
        ).ok.body.json
      }.flatMap(\.data)
      let details = { (list: [Components.Schemas.StateDetail]?) in list.map { $0.map { Detail(code: $0.code, description: $0.description) } } }
      let entries = uploads.map { u in
        let a = u.attributes
        return Entry(
          id: u.id, version: a?.cfBundleShortVersionString, build: a?.cfBundleVersion, platform: a?.platform,
          state: a?.state?.state, createdDate: a?.createdDate, uploadedDate: a?.uploadedDate,
          errors: details(a?.state?.errors), warnings: details(a?.state?.warnings)
        )
      }.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }.prefix(limit).map { $0 }
      if jsonOption.json { try printJSON(entries); return }
      guard !entries.isEmpty else {
        print("No build uploads.")
        return
      }
      Table.print(
        headers: ["Version", "Build", "Platform", "State", "Created", "Uploaded"],
        rows: entries.map { e in
          let state = e.state.map { $0 == "FAILED" ? red(formatState($0)) : formatState($0) } ?? "-"
          return [e.version ?? "-", e.build ?? "-", formatState(e.platform ?? "-"), state,
                  e.createdDate.map { formatDate($0) } ?? "-", e.uploadedDate.map { formatDate($0) } ?? "-"]
        }
      )
      for e in entries where !(e.errors ?? []).isEmpty || !(e.warnings ?? []).isEmpty {
        print()
        print(bold("\(e.version ?? "-") (\(e.build ?? "-")) \(formatState(e.platform ?? "-"))"))
        for d in e.errors ?? [] { print("  " + red("Error: ") + [d.code, d.description].compactMap { $0 }.joined(separator: ": ")) }
        for d in e.warnings ?? [] { print("  " + yellow("Warning: ") + [d.code, d.description].compactMap { $0 }.joined(separator: ": ")) }
      }
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

    @Flag(
      name: .customLong("json-events"),
      help: "Report progress as JSON events on stdout, one per line (step, archived), for other tools. The readable progress and xcodebuild's output go to stderr.")
    var jsonEvents = false

    func run() throws {
      try EventOutput.$emitsEvents.withValue(jsonEvents) { try archive() }
    }

    private func archive() throws {
      if yes { autoConfirm = true }

      try ensureXcodebuild()

      // 1. Detect project or workspace
      let (buildFlag, buildPath) = try detectProject()

      // 2. Detect scheme
      let schemeName = try detectScheme(buildFlag: buildFlag, buildPath: buildPath)

      // 3. Clean before archiving
      EventOutput.log("Cleaning build...")
      EventOutput.emit(BuildEvent(event: "step", step: "cleaning"))
      fflush(stdout)

      let cleanProcess = Process()
      cleanProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
      cleanProcess.arguments = [
        "clean",
        buildFlag, buildPath,
        "-scheme", schemeName,
        "-configuration", configuration ?? "Release",
      ] + quietFlag
      cleanProcess.standardOutput = toolOutput
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
      ] + quietFlag + (try APICredentials.fromEnvironment()?.xcodebuildArguments ?? [])

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
      EventOutput.log("Archiving scheme '\(schemeName)'...")
      EventOutput.log()
      EventOutput.emit(BuildEvent(event: "step", step: "archiving"))
      fflush(stdout)

      let started = Date()
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
      process.arguments = args
      process.standardOutput = toolOutput
      process.standardError = FileHandle.standardError

      try process.run()
      trackProcess(process)
      setupSignalHandler()
      process.waitUntilExit()
      untrackProcess(process)

      if process.terminationStatus != 0 {
        throw ExitCode(process.terminationStatus)
      }

      // 6. Print result: without --output, xcodebuild names the archive in Xcode's archive
      // location, where it's the newest one made since the run started.
      EventOutput.log()
      if let archivePath {
        EventOutput.log("Archive created at: \(archivePath)")
        EventOutput.emit(BuildEvent(event: "archived", path: archivePath))
      } else {
        EventOutput.log("Archive complete. The .xcarchive is in Xcode's default archive location:")
        EventOutput.log("  ~/Library/Developer/Xcode/Archives/")
        if let latest = try? findLatestArchive(bundleID: nil), latest.creationDate > started.addingTimeInterval(-60) {
          EventOutput.emit(BuildEvent(event: "archived", path: latest.path))
        }
      }
    }

    /// For another tool following the events, xcodebuild prints only warnings and errors: its full
    /// output (every compile command, kilobytes a line) is more than a log view can follow.
    private var quietFlag: [String] {
      jsonEvents ? ["-quiet"] : []
    }

    /// Where xcodebuild's output goes: the terminal, or stderr when stdout carries events.
    private var toolOutput: FileHandle {
      jsonEvents ? .standardError : .standardOutput
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
        EventOutput.log("Using workspace: \(ws)")
        return ("-workspace", path)
      }
      if let proj = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
        let path = (cwd as NSString).appendingPathComponent(proj)
        EventOutput.log("Using project: \(proj)")
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
        EventOutput.log("Using scheme: \(name)")
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

  struct Upload: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Upload a build to App Store Connect (xcrun altool, or the App Store Connect API with --api)."
    )

    @Argument(help: "Path to the .ipa, .pkg, or .xcarchive file.",
              completion: .file(extensions: ["ipa", "pkg", "xcarchive"]))
    var file: String?

    @Flag(name: .long, help: "Use the latest .xcarchive from Xcode's archive location.")
    var latest = false

    @Option(name: .long, help: "With --latest, the latest archive of this exact bundle identifier; with a file, refuse it unless the app in it has this bundle identifier.")
    var bundleID: String?

    @Flag(name: .long, help: "Upload through the App Store Connect API's build uploads (.ipa or Mac .pkg) instead of altool.")
    var api = false

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    @Flag(
      name: .customLong("json-events"),
      help: "Report progress as JSON events on stdout, one per line (step, exported, uploading, progress, finished), for other tools. The readable progress goes to stderr.")
    var jsonEvents = false

    func run() async throws {
      guard jsonEvents else { return try await upload() }
      try await EventOutput.$emitsEvents.withValue(true) {
        try await UploadProgress.$observe.withValue({ total in UploadProgressEvents(total: total) }) {
          try await upload()
        }
      }
    }

    private func upload() async throws {
      if yes { autoConfirm = true }
      if !api { try ensureAltool() }

      if file != nil && latest {
        throw ValidationError("Cannot specify both a file path and --latest.")
      }
      let expandedPath: String
      var uploadedBuildNumber: String?
      if latest {
        let archive = try findLatestArchive(bundleID: bundleID)
        expandedPath = archive.path
        uploadedBuildNumber = archive.buildNumber
        EventOutput.log("Found archive: \((archive.path as NSString).lastPathComponent)")
        EventOutput.log("  Bundle ID:  \(archive.bundleID)")
        EventOutput.log("  Version:    \(archive.version) (\(archive.buildNumber))")
        EventOutput.log("  Created:    \(formatDate(archive.creationDate))")
        EventOutput.log()
        guard confirm("Upload this archive? [y/N] ") else { return }
      } else {
        expandedPath = try resolveFilePath(file, prompt: "Path to .ipa, .pkg, or .xcarchive file: ")
        // Try to extract build number from .xcarchive
        if expandedPath.hasSuffix(".xcarchive") {
          uploadedBuildNumber = buildNumberFromArchive(expandedPath)
        }
        // Before exporting or sending anything: the file must hold that app.
        if let bundleID {
          let found = expandedPath.hasSuffix(".xcarchive")
            ? bundleIDFromArchive(expandedPath) : try BuildUploader.info(path: expandedPath).bundleID
          guard found == bundleID else {
            throw ValidationError("\((expandedPath as NSString).lastPathComponent) holds \(found ?? "an app of unknown bundle ID"), not \(bundleID).")
          }
        }
      }

      let key = try APICredentials.current()

      // Export .xcarchive to .ipa/.pkg if needed
      let (uploadPath, tempDir, archivePlatform) = try resolveUploadable(expandedPath)
      defer { if let dir = tempDir { try? FileManager.default.removeItem(atPath: dir) } }

      if api {
        // Through ASCKit, so dry run shows the requests and stops at the first write.
        guard uploadPath.hasSuffix(".ipa") || uploadPath.hasSuffix(".pkg") else {
          throw ValidationError("--api uploads an .ipa or a .pkg.")
        }
        let buildNumber = try await BuildUploader.upload(path: uploadPath)
        recordUploadedBuild(uploadedBuildNumber ?? buildNumber, platform: archivePlatform?.ascPlatform)
        return
      }

      // altool talks to Apple itself, outside the dry-run gate: skip the upload, and don't record
      // a build number a later await-processing or attach-latest would wait for in vain.
      if ClientFactory.isDryRun {
        EventOutput.log(yellow("Dry run: \((uploadPath as NSString).lastPathComponent) was not uploaded."))
        return
      }

      EventOutput.log("Uploading \((uploadPath as NSString).lastPathComponent)...")
      EventOutput.log()
      EventOutput.emit(BuildEvent(event: "uploading", path: uploadPath, platform: archivePlatform?.ascPlatform.rawValue))
      fflush(stdout)

      var altoolArgs = [
        "altool", "--upload-app",
        "-f", uploadPath,
        "--apiKey", key.keyID,
        "--apiIssuer", key.issuerID,
        "--p8-file-path", key.privateKeyPath,
        "--show-progress",
      ]
      if let archivePlatform {
        altoolArgs += ["--type", archivePlatform.altoolType]
      }

      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
      process.arguments = altoolArgs
      process.standardOutput = jsonEvents ? FileHandle.standardError : FileHandle.standardOutput
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
      EventOutput.emit(BuildEvent(event: "finished", build: uploadedBuildNumber))
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

      let key = try APICredentials.current()

      // Export .xcarchive to .ipa/.pkg if needed
      let (uploadPath, tempDir, archivePlatform) = try resolveUploadable(expandedPath)
      defer { if let dir = tempDir { try? FileManager.default.removeItem(atPath: dir) } }

      print("Validating \((uploadPath as NSString).lastPathComponent)...")
      print()
      fflush(stdout)

      var altoolArgs = [
        "altool", "--validate-app",
        "-f", uploadPath,
        "--apiKey", key.keyID,
        "--apiIssuer", key.issuerID,
        "--p8-file-path", key.privateKeyPath,
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
  // Xcode's folder, in the account's home whatever $HOME says (like DerivedData).
  let archivesDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Developer/Xcode/Archives").path
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

  // Without a trailing slash: an .xcarchive is a folder, which tab completion and apps passing a
  // folder's URL end in one, and the type is told by the path's extension.
  let expandedPath = (expandPath(filePath) as NSString).standardizingPath
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
    case .iOS: return .ios
    case .macOS: return .macOs
    case .tvOS: return .tvOs
    case .visionOS: return .visionOs
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
  EventOutput.log("Exporting .xcarchive to .\(platform.exportExtension) (\(platform.label))...")
  EventOutput.emit(BuildEvent(event: "step", step: "exporting", platform: platform.ascPlatform.rawValue))
  fflush(stdout)

  // UUID, not PID: a predictable path could pick up a stale export from a prior crashed run.
  let tempDir = NSTemporaryDirectory() + "ascelerate-export-\(UUID().uuidString)"
  let exportDir = tempDir + "/output"
  let plistPath = tempDir + "/ExportOptions.plist"

  try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

  // App Store export options: an archive signed with App Store distribution profiles (a project
  // signed manually) exports with those same profiles, so Xcode creates none; any other archive
  // (signed for development, as automatic signing does) exports with automatic signing.
  var options: [String: Any] = ["method": "app-store-connect", "destination": "export", "signingStyle": "automatic"]
  if let signing = distributionSigning(archivePath: path) {
    EventOutput.log("Signing with the archive's App Store profiles (manual signing).")
    options["signingStyle"] = "manual"
    options["teamID"] = signing.teamID
    options["provisioningProfiles"] = signing.profiles
    // Xcode's selectors for the newest certificate of each kind; left out, it picked the installer
    // certificate to sign the app (seen 2026-10-23: "profile doesn't include signing certificate
    // 3rd Party Mac Developer Installer").
    options["signingCertificate"] = "Apple Distribution"
    if platform == .macOS { options["installerSigningCertificate"] = installerCertificateName() }
  }
  try PropertyListSerialization.data(fromPropertyList: options, format: .xml, options: 0)
    .write(to: URL(fileURLWithPath: plistPath))

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
  process.arguments = [
    "-exportArchive",
    "-archivePath", path,
    "-exportPath", exportDir,
    "-exportOptionsPlist", plistPath,
    "-allowProvisioningUpdates",
  ] + ((try? APICredentials.fromEnvironment())??.xcodebuildArguments ?? [])
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
      EventOutput.log(output)
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
  EventOutput.log("Exported \(exportName)")
  EventOutput.log()
  fflush(stdout)

  return (exportPath, tempDir, platform)
}

/// The keychain's name for the Mac App Store installer certificate: "Mac Installer Distribution"
/// for one made since Xcode 11, "3rd Party Mac Developer Installer" for an older one (Xcode's
/// selector for the first doesn't match the second).
private func installerCertificateName() -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
  process.arguments = ["find-identity", "-v"]
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = FileHandle.nullDevice
  guard (try? process.run()) != nil else { return "Mac Installer Distribution" }
  let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  process.waitUntilExit()
  let current = "Mac Installer Distribution"
  return output.contains("\"\(current):") || !output.contains("\"3rd Party Mac Developer Installer:")
    ? current : "3rd Party Mac Developer Installer"
}

/// A provisioning profile's contents, from its CMS envelope (`security cms -D`).
private func decodeProfile(_ path: String) -> [String: Any]? {
  let decode = Process()
  decode.executableURL = URL(fileURLWithPath: "/usr/bin/security")
  decode.arguments = ["cms", "-D", "-i", path]
  let pipe = Pipe()
  decode.standardOutput = pipe
  decode.standardError = FileHandle.nullDevice
  guard (try? decode.run()) != nil else { return nil }
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  decode.waitUntilExit()
  guard decode.terminationStatus == 0 else { return nil }
  return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
}

/// Whether a profile is for distribution (a development or ad hoc one lists devices; an
/// enterprise one provisions all).
private func isDistribution(_ profile: [String: Any]) -> Bool {
  profile["ProvisionedDevices"] == nil && profile["ProvisionsAllDevices"] == nil
}

/// The profiles Xcode has installed (where it keeps them since Xcode 16), decoded.
private func installedProfiles() -> [[String: Any]] {
  let folder = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Developer/Xcode/UserData/Provisioning Profiles").path
  return ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
    .compactMap { decodeProfile((folder as NSString).appendingPathComponent($0)) }
}

/// The App Store profiles to export an archive with, by bundle identifier (the app's and each
/// embedded bundle's), with their team; nil when the archive wasn't signed for distribution (a
/// development profile lists devices) or a bundle has no installed profile to use. Each bundle
/// gets the archive's own profile if it's still installed (by UUID, then by name: reissuing gives
/// a profile a new UUID, and a rename a new name), else the newest installed App Store profile of
/// its App ID and platform.
private func distributionSigning(archivePath: String) -> (teamID: String, profiles: [String: String])? {
  let fm = FileManager.default
  let products = (archivePath as NSString).appendingPathComponent("Products/Applications")
  guard let app = (try? fm.contentsOfDirectory(atPath: products))?.first(where: { $0.hasSuffix(".app") }) else { return nil }
  let appPath = (products as NSString).appendingPathComponent(app)
  // Every signed bundle: the app, its extensions, watch apps and helper apps.
  let bundles = [appPath] + ((fm.enumerator(atPath: appPath)?.allObjects as? [String]) ?? [])
    .filter { [".app", ".appex"].contains(where: $0.hasSuffix) }
    .map { (appPath as NSString).appendingPathComponent($0) }
  var installed: [[String: Any]]?
  var profiles: [String: String] = [:]
  var teamID: String?
  for bundle in bundles {
    let isMac = fm.fileExists(atPath: (bundle as NSString).appendingPathComponent("Contents/Info.plist"))
    let root = isMac ? (bundle as NSString).appendingPathComponent("Contents") : bundle
    let profilePath = (root as NSString).appendingPathComponent(isMac ? "embedded.provisionprofile" : "embedded.mobileprovision")
    // A bundle without a profile (a helper signed without one) doesn't need one.
    guard fm.fileExists(atPath: profilePath) else { continue }
    guard let infoData = fm.contents(atPath: (root as NSString).appendingPathComponent("Info.plist")),
      let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
      let bundleID = info["CFBundleIdentifier"] as? String,
      let embedded = decodeProfile(profilePath), isDistribution(embedded),
      let team = (embedded["TeamIdentifier"] as? [String])?.first
    else { return nil }
    let platforms = Set(embedded["Platform"] as? [String] ?? [])
    func appID(_ profile: [String: Any]) -> String? {
      let entitlements = profile["Entitlements"] as? [String: Any]
      return (entitlements?["application-identifier"] ?? entitlements?["com.apple.application-identifier"]) as? String
    }
    if installed == nil { installed = installedProfiles() }
    let candidates = (installed ?? []).filter { profile in
      isDistribution(profile) && appID(profile) == "\(team).\(bundleID)"
        && !platforms.isDisjoint(with: profile["Platform"] as? [String] ?? [])
        && (profile["ExpirationDate"] as? Date ?? .distantPast) > Date()
    }
    guard let chosen = candidates.first(where: { $0["UUID"] as? String == embedded["UUID"] as? String })
      ?? candidates.first(where: { $0["Name"] as? String == embedded["Name"] as? String })
      ?? candidates.max(by: { ($0["CreationDate"] as? Date ?? .distantPast) < ($1["CreationDate"] as? Date ?? .distantPast) }),
      let uuid = chosen["UUID"] as? String
    else { return nil }
    profiles[bundleID] = uuid
    teamID = teamID ?? team
  }
  guard let teamID, !profiles.isEmpty else { return nil }
  return (teamID, profiles)
}

/// The archived app's bundle identifier, from an .xcarchive's Info.plist, or nil if unavailable.
private func bundleIDFromArchive(_ archivePath: String) -> String? {
  let plistPath = (archivePath as NSString).appendingPathComponent("Info.plist")
  guard let data = FileManager.default.contents(atPath: plistPath),
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
        let appProps = plist["ApplicationProperties"] as? [String: Any]
  else { return nil }
  return appProps["CFBundleIdentifier"] as? String
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

// MARK: - Events

/// A step of `builds archive` or `builds upload` as `--json-events` reports it. `event` is one of:
/// - `step`: `step` is `cleaning` or `archiving` (archive), or `exporting` (upload of an
///   .xcarchive, with its `platform`)
/// - `archived`: the new .xcarchive's `path`
/// - `uploading`: the file's `path`; through the API also `bundleID`, `version`, `build`,
///   `platform` and `bytes`
/// - `progress`: `sent` of `bytes` (API uploads, at most once per percent)
/// - `processing`: the file is in; App Store Connect is taking it in (API uploads)
/// - `finished`: the upload is complete, with its `build` and Apple's `warnings` (API uploads)
struct BuildEvent: Encodable {
  let event: String
  var step: String?
  var path: String?
  var bundleID: String?
  var version: String?
  var build: String?
  var platform: String?
  var bytes: Int64?
  var sent: Int64?
  var warnings: [String]?
}

/// Reports an upload's acknowledged bytes as `progress` events, at most once per percent.
private final class UploadProgressEvents: UploadProgressObserver, @unchecked Sendable {
  private let lock = NSLock()
  private var shownPercent = -1

  init(total: Int64) {}

  func progress(sent: Int64, total: Int64) {
    lock.withLock {
      guard total > 0 else { return }
      let percent = Int(sent * 100 / total)
      guard percent > shownPercent else { return }
      shownPercent = percent
      EventOutput.emit(BuildEvent(event: "progress", bytes: total, sent: sent))
    }
  }

  func finish() {}
}
