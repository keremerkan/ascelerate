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
        return BuildResult(xctestrunFile: xctestrunFile)
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
