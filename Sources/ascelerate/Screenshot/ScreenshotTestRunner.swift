import Foundation

struct ScreenshotTestRunner: Sendable {
    let config: ScreenshotConfig

    struct BuildResult: Sendable {
        let xctestrunFile: String
    }

    func build(resolvedDevices: [(ScreenshotConfig.Device, SimulatorManager.SimDevice)]) throws -> BuildResult {
        if config.testWithoutBuilding != true {
            print("\nBuilding for testing...")

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
                args += xcargs.split(separator: " ").map(String.init)
            }

            if config.cleanBuild == true {
                args += ["clean"]
            }

            args += ["build-for-testing"]

            let status = try ScreenshotShell.stream("/usr/bin/xcodebuild", arguments: Array(args.dropFirst()))

            guard status == 0 else {
                throw ScreenshotError.xcodebuildFailed(status)
            }
        }

        let derivedDataPath = try config.derivedDataPath ?? resolveDerivedDataPath()
        let xctestrunFile = try findXctestrunFile(derivedDataPath: derivedDataPath)
        return BuildResult(xctestrunFile: try repairXctestrunIfNeeded(xctestrunFile))
    }

    /// Xcode 27 resolves a UI test target's `TEST_TARGET_NAME` by name across the whole
    /// workspace. When another project in the workspace has a same-named target with a
    /// different PRODUCT_NAME, the generated xctestrun's `UITargetAppPath` points at an app
    /// that was never built (e.g. a macOS target's "My App.app" instead of the iOS
    /// "MyApp.app"). xcodebuild then fails the runner instantly, blocks on
    /// `simctl diagnose --timeout=600` for ten minutes per run, and only afterwards runs
    /// the tests with the correct app it already mapped from `DependentProductPaths`.
    /// Detect the dangling path, point it at the one real app among the dependent
    /// products, and write the repaired copy (with `__TESTROOT__` made absolute, since the
    /// copy lives outside the Products dir) into the cache directory.
    private func repairXctestrunIfNeeded(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        let testRoot = url.deletingLastPathComponent().path
        guard var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any],
              var configurations = plist["TestConfigurations"] as? [[String: Any]] else {
            return path
        }

        func exists(_ product: String) -> Bool {
            FileManager.default.fileExists(atPath: product.replacingOccurrences(of: "__TESTROOT__", with: testRoot))
        }

        var repaired = false
        for c in configurations.indices {
            guard var targets = configurations[c]["TestTargets"] as? [[String: Any]] else { continue }
            for t in targets.indices {
                guard let appPath = targets[t]["UITargetAppPath"] as? String, !exists(appPath) else { continue }
                let host = targets[t]["TestHostPath"] as? String
                let candidates = (targets[t]["DependentProductPaths"] as? [String] ?? [])
                    .filter { $0.hasSuffix(".app") && $0 != host && exists($0) }
                guard candidates.count == 1 else {
                    throw ScreenshotError.uiTargetAppNotFound(appPath.replacingOccurrences(of: "__TESTROOT__", with: testRoot))
                }
                let wrong = URL(fileURLWithPath: appPath).lastPathComponent
                let right = URL(fileURLWithPath: candidates[0]).lastPathComponent
                print("  " + yellow("Warning:") + " xctestrun points to a target app that was not built ('\(wrong)'); using '\(right)' from the scheme's build products instead.")
                print("  Xcode 27 resolves TEST_TARGET_NAME across the whole workspace: a same-named target in another project probably has a different PRODUCT_NAME.")
                targets[t]["UITargetAppPath"] = candidates[0]
                repaired = true
            }
            configurations[c]["TestTargets"] = targets
        }
        guard repaired else { return path }

        plist["TestConfigurations"] = configurations
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

        if let testplan = config.testplan {
            args += ["-testPlan", testplan]
        }

        if let xcargs = config.xcargs {
            args += xcargs.split(separator: " ").map(String.init)
        }

        args += ["test-without-building"]

        let logDir = ScreenshotCollector.cacheRoot.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logFile = logDir.appendingPathComponent("\(device.simulator)-\(language).log")

        print("  [\(device.simulator)] Running tests...")

        let status = try ScreenshotShell.runToLog("/usr/bin/xcodebuild", arguments: Array(args.dropFirst()), logFile: logFile)

        guard status == 0 else {
            let tail = ScreenshotShell.tail(logFile, lines: 15)
            print("  [\(device.simulator)] Test failed. Last lines from log:")
            print(tail)
            print("  Full log: \(logFile.path)")
            throw ScreenshotError.xcodebuildFailed(status)
        }

        print("  [\(device.simulator)] " + green("Tests passed ✓"))
    }

    private func findXctestrunFile(derivedDataPath: String) throws -> String {
        let baseURL = URL(fileURLWithPath: derivedDataPath)

        let productsDir = baseURL.appendingPathComponent("Build/Products")
        if let file = xctestrunFileIn(directory: productsDir) {
            print("  Using xctestrun: \(file.lastPathComponent)")
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
            print("  Using xctestrun: \(newest.path)")
            return newest.path
        }

        throw ScreenshotError.xctestrunNotFound(derivedDataPath)
    }

    private func xctestrunFileIn(directory: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        return contents
            .filter { $0.pathExtension == "xctestrun" }
            .max { modificationDate($0) < modificationDate($1) }
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
            print("  Using derived data: \(exactPath.path)")
            return exactPath.path
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: derivedDataRoot,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )

        // Multiple ProjectName-<hash> dirs exist after the project path moves or is
        // renamed — pick the most recently modified one, not directory order.
        let matches = contents.filter { $0.lastPathComponent.hasPrefix("\(projectName)-") }

        guard let match = matches.max(by: { modificationDate($0) < modificationDate($1) }) else {
            throw ScreenshotError.derivedDataNotFound(projectName)
        }

        print("  Using derived data: \(match.path)")
        return match.path
    }
}
