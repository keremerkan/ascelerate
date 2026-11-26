import AscelerateCore
import Foundation

struct ScreenshotTestRunner: Sendable {
  let config: ScreenshotConfig

  struct BuildResult: Sendable {
    let xctestrunFile: String
  }

  func build(resolvedDevices: [(ScreenshotConfig.Device, SimulatorManager.SimDevice)]) throws -> BuildResult {
    if config.testWithoutBuilding != true {
      EventOutput.log("\nBuilding for testing...")

      var args = ["xcodebuild"]

      if let workspace = config.workspace {
        args += ["-workspace", workspace]
      } else if let project = config.project {
        args += ["-project", project]
      }

      args += ["-scheme", config.scheme]
      args += ["-configuration", config.configuration ?? "Release"]
      args += ["-destination", "generic/platform=iOS Simulator"]

      if let testplan = config.testplan {
        args += ["-testPlan", testplan]
      }

      if let xcargs = config.xcargs {
        args += try splitArguments(xcargs)
      }

      if config.cleanBuild == true {
        args += ["clean"]
      }

      // The xcodebuild output setting, as builds archive takes it (quiet when a program follows).
      if XcodebuildOutput.resolve(nil, followed: EventOutput.emitsEvents) == .quiet { args += ["-quiet"] }
      args += ["build-for-testing"]

      let status = try ScreenshotShell.stream("/usr/bin/xcodebuild", arguments: Array(args.dropFirst()))

      guard status == 0 else {
        throw ScreenshotError.xcodebuildFailed(status)
      }
    }

    let derivedDataPath = try config.derivedDataPath ?? resolveDerivedDataPath()
    let xctestrunFile = try findXctestrunFile(derivedDataPath: derivedDataPath)
    return BuildResult(xctestrunFile: try prepareXctestrun(xctestrunFile))
  }

  /// Xcode 27 resolves a UI test target's `TEST_TARGET_NAME` by name across the whole
  /// workspace. When another project in the workspace has a same-named target with a
  /// different PRODUCT_NAME, the generated xctestrun's `UITargetAppPath` points at an app
  /// that was never built (e.g. a macOS target's "My App.app" instead of the iOS
  /// "MyApp.app"). xcodebuild then fails the runner instantly, blocks on
  /// `simctl diagnose --timeout=600` for ten minutes per run, and only afterwards runs
  /// the tests with the correct app it already mapped from `DependentProductPaths`.
  /// Detect the dangling path and point it at the one real app among the dependent
  /// products.
  ///
  /// Also switch off the unified log output of the app under test (`OS_ACTIVITY_MODE=disable`
  /// in `UITargetAppEnvironmentVariables`, unless the project set it): XCTest's automation
  /// logs every element query inside the app, which Xcode captures into the result bundle.
  /// A query-heavy screenshot test wrote 3.1 MB per device run (14 MB on a longer one), and
  /// Xcode 27.1's result bundle importer crashed copying the still-growing file; with the
  /// logs off the same run wrote 2.7 KB (measured 2026-10-09).
  ///
  /// The prepared copy (with `__TESTROOT__` made absolute, since it lives outside the
  /// Products dir) is written into the cache directory.
  private func prepareXctestrun(_ path: String) throws -> String {
    let url = URL(fileURLWithPath: path)
    let testRoot = url.deletingLastPathComponent().path
    guard var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any] else {
      return path
    }

    func exists(_ product: String) -> Bool {
      FileManager.default.fileExists(atPath: product.replacingOccurrences(of: "__TESTROOT__", with: testRoot))
    }

    /// One test target: the app's logging off, and a target app path that wasn't built repaired.
    func fix(_ target: inout [String: Any]) throws -> Bool {
      var changed = false
      if target["UITargetAppPath"] != nil {
        var environment = target["UITargetAppEnvironmentVariables"] as? [String: String] ?? [:]
        if environment["OS_ACTIVITY_MODE"] == nil {
          environment["OS_ACTIVITY_MODE"] = "disable"
          target["UITargetAppEnvironmentVariables"] = environment
          changed = true
        }
      }
      guard let appPath = target["UITargetAppPath"] as? String, !exists(appPath) else { return changed }
      let host = target["TestHostPath"] as? String
      let candidates = (target["DependentProductPaths"] as? [String] ?? [])
        .filter { $0.hasSuffix(".app") && $0 != host && exists($0) }
      guard candidates.count == 1 else {
        throw ScreenshotError.uiTargetAppNotFound(appPath.replacingOccurrences(of: "__TESTROOT__", with: testRoot))
      }
      let wrong = URL(fileURLWithPath: appPath).lastPathComponent
      let right = URL(fileURLWithPath: candidates[0]).lastPathComponent
      EventOutput.log("  " + yellow("Warning:") + " xctestrun points to a target app that was not built ('\(wrong)'); using '\(right)' from the scheme's build products instead.")
      EventOutput.log("  Xcode 27 resolves TEST_TARGET_NAME across the whole workspace: a same-named target in another project probably has a different PRODUCT_NAME.")
      target["UITargetAppPath"] = candidates[0]
      return true
    }

    var changed = false
    if var configurations = plist["TestConfigurations"] as? [[String: Any]] {
      // Format 2: test plans' configurations, each with its targets.
      for c in configurations.indices {
        guard var targets = configurations[c]["TestTargets"] as? [[String: Any]] else { continue }
        for t in targets.indices where try fix(&targets[t]) { changed = true }
        configurations[c]["TestTargets"] = targets
      }
      plist["TestConfigurations"] = configurations
    } else {
      // Format 1: each target is a top-level entry (beside the metadata).
      for key in plist.keys where key != "__xctestrun_metadata__" {
        guard var target = plist[key] as? [String: Any], target["TestBundlePath"] != nil else { continue }
        if try fix(&target) {
          plist[key] = target
          changed = true
        }
      }
    }
    guard changed else { return path }

    let absolute = replacingTestRoot(plist, with: testRoot)
    let data = try PropertyListSerialization.data(fromPropertyList: absolute, format: .xml, options: 0)
    let dir = ScreenshotCollector.cacheRoot.appendingPathComponent("xctestrun")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let repairedURL = dir.appendingPathComponent(url.lastPathComponent)
    try data.write(to: repairedURL)
    return repairedURL.path
  }

  private func replacingTestRoot(_ value: Any, with root: String) -> Any {
    switch value {
    case let string as String: string.replacingOccurrences(of: "__TESTROOT__", with: root)
    case let array as [Any]: array.map { replacingTestRoot($0, with: root) }
    case let dict as [String: Any]: dict.mapValues { replacingTestRoot($0, with: root) }
    default: value
    }
  }

  func test(device: ScreenshotConfig.Device, udid: String, language: String, buildResult: BuildResult) throws {
    var args = ["xcodebuild"]
    args += ["-xctestrun", buildResult.xctestrunFile]
    args += ["-destination", "platform=iOS Simulator,id=\(udid)"]
    args += ["-parallel-testing-enabled", "NO"]
    // No sysdiagnose-style collection on failure: after a failure xcodebuild otherwise runs
    // `simctl diagnose --timeout=600`, a silent 10-minute stall per device (seen live with
    // Xcode 27.1, 2026-10-09).
    args += ["-collect-test-diagnostics", "never"]

    if let testplan = config.testplan {
      args += ["-testPlan", testplan]
    }

    if let xcargs = config.xcargs {
      args += try splitArguments(xcargs)
    }

    args += ["test-without-building"]

    let logDir = ScreenshotCollector.cacheRoot.appendingPathComponent("logs")
    try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    let logFile = logDir.appendingPathComponent("\(device.simulator)-\(language).log")

    EventOutput.log("  [\(device.simulator)] Running tests...")

    let status = try ScreenshotShell.runToLog("/usr/bin/xcodebuild", arguments: Array(args.dropFirst()), logFile: logFile)

    // The screenshots are written while the tests run, so a run whose tests all passed keeps
    // them even if xcodebuild fails afterwards. Seen live with Xcode 27.1: its result bundle
    // importer crashes ("CASTreeDataStructure/Importer.swift: Fatal error … file has been
    // modified") when the app is still writing to its captured console output.
    if status != 0, Self.testsPassed(logFile: logFile) {
      EventOutput.log("  [\(device.simulator)] " + green("Tests passed ✓") + yellow(" (xcodebuild then exited with status \(status); screenshots kept)"))
      EventOutput.log("  Full log: \(logFile.path)")
      return
    }

    guard status == 0 else {
      let tail = ScreenshotShell.tail(logFile, lines: 15)
      EventOutput.log("  [\(device.simulator)] Test failed. Last lines from log:")
      EventOutput.log(tail)
      EventOutput.log("  Full log: \(logFile.path)")
      throw ScreenshotError.xcodebuildFailed(status)
    }

    EventOutput.log("  [\(device.simulator)] " + green("Tests passed ✓"))
  }

  /// Whether the log's final test summary reports every test passed.
  private static func testsPassed(logFile: URL) -> Bool {
    // The whole log: with several bundles, the first one's verdict is far from the end.
    guard let log = try? String(contentsOf: logFile, encoding: .utf8) else { return false }
    return XcodebuildLog.testsPassed(log)
  }

  private func findXctestrunFile(derivedDataPath: String) throws -> String {
    let baseURL = URL(fileURLWithPath: derivedDataPath)

    let productsDir = baseURL.appendingPathComponent("Build/Products")
    if let file = xctestrunFileIn(directory: productsDir) {
      EventOutput.log("  Using xctestrun: \(file.lastPathComponent)")
      return file.path
    }

    // Fallback: search recursively, but pick the most recently modified file —
    // enumeration order is arbitrary and could return a stale build's xctestrun.
    let enumerator = FileManager.default.enumerator(
      at: baseURL,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )

    var candidates: [URL] = []
    while let url = enumerator?.nextObject() as? URL {
      if url.pathExtension == "xctestrun" {
        candidates.append(url)
      }
    }
    if let newest = candidates.max(by: { modificationDate($0) < modificationDate($1) }) {
      EventOutput.log("  Using xctestrun: \(newest.path)")
      return newest.path
    }

    throw ScreenshotError.xctestrunNotFound(derivedDataPath)
  }

  private func xctestrunFileIn(directory: URL) -> URL? {
    guard let contents = try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey]
    ) else { return nil }

    // The scheme's own (Xcode names it `<scheme>_…`) before any other's, newest first.
    let all = contents.filter { $0.pathExtension == "xctestrun" }
    let scheme = all.filter { $0.lastPathComponent.hasPrefix("\(config.scheme)_") }
    return (scheme.isEmpty ? all : scheme).max { modificationDate($0) < modificationDate($1) }
  }

  private func modificationDate(_ url: URL) -> Date {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
  }

  private func resolveDerivedDataPath() throws -> String {
    let projectName: String
    if let workspace = config.workspace {
      projectName = URL(fileURLWithPath: workspace).deletingPathExtension().lastPathComponent
    } else if let project = config.project {
      projectName = URL(fileURLWithPath: project).deletingPathExtension().lastPathComponent
    } else {
      throw ScreenshotError.noProjectSpecified
    }

    let derivedDataRoot = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Developer/Xcode/DerivedData")

    let exactPath = derivedDataRoot.appendingPathComponent(projectName)
    if FileManager.default.fileExists(atPath: exactPath.path) {
      EventOutput.log("  Using derived data: \(exactPath.path)")
      return exactPath.path
    }

    let contents = try FileManager.default.contentsOfDirectory(
      at: derivedDataRoot,
      includingPropertiesForKeys: [.contentModificationDateKey]
    )

    // Multiple ProjectName-<hash> dirs exist after the project path moves or is
    // renamed — pick the most recently modified one, not directory order.
    let matches = contents.filter { $0.lastPathComponent.hasPrefix("\(projectName)-") }
    // The folder Xcode keeps for this project's path (its info.plist names it), so a second
    // checkout or `MyApp-Lite` beside `MyApp` isn't taken; without one, the newest as before.
    let projectPath = URL(fileURLWithPath: expandPath(config.workspace ?? config.project ?? "")).standardizedFileURL
      .resolvingSymlinksInPath().path
    let ours = matches.filter { folder in
      guard let info = NSDictionary(contentsOf: folder.appendingPathComponent("info.plist")),
        let path = info["WorkspacePath"] as? String
      else { return false }
      return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path == projectPath
    }
    if ours.isEmpty && !matches.isEmpty {
      EventOutput.log("  No derived data names \(projectPath); using the newest \(projectName)-… folder.")
    }

    guard let match = (ours.isEmpty ? matches : ours).max(by: { modificationDate($0) < modificationDate($1) }) else {
      throw ScreenshotError.derivedDataNotFound(projectName)
    }

    EventOutput.log("  Using derived data: \(match.path)")
    return match.path
  }
}
