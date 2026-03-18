import Foundation

struct ScreenshotRunner: Sendable {
    let config: ScreenshotConfig

    struct Result {
        let language: String
        let device: String
        let success: Bool
        let error: String?
    }

    func run() async throws {
        let simulatorManager = SimulatorManager()
        let testRunner = ScreenshotTestRunner(config: config)
        let collector = ScreenshotCollector(config: config)

        let helperFound = checkHelperVersion()

        let resolvedDevices = try config.devices.map { device -> (ScreenshotConfig.Device, SimulatorManager.SimDevice) in
            let sim = try simulatorManager.findDevice(name: device.simulator)
            print("Found simulator: \(sim.name) (\(sim.udid))")
            return (device, sim)
        }

        let buildResult = try testRunner.build(resolvedDevices: resolvedDevices)

        var results: [Result] = []

        for (langIndex, language) in config.languages.enumerated() {
            let locale = languageToLocale(language)
            print("\n--- [\(langIndex + 1)/\(config.languages.count)] \(language) ---")

            do {
                if config.headless != true {
                    try ScreenshotShell.run("/usr/bin/open", arguments: ["-a", "Simulator"])
                }

                for (device, sim) in resolvedDevices {
                    print("\n  [\(device.simulator)] Preparing...")

                    if config.eraseSimulator {
                        print("  [\(device.simulator)] Erasing...")
                        try simulatorManager.erase(udid: sim.udid)
                    }

                    if config.localizeSimulator {
                        try simulatorManager.boot(udid: sim.udid, waitUntilReady: false)
                        try simulatorManager.localize(udid: sim.udid, language: language, locale: locale)
                        try simulatorManager.shutdown(udid: sim.udid)
                        try simulatorManager.boot(udid: sim.udid)
                    } else {
                        try simulatorManager.boot(udid: sim.udid)
                    }

                    if let wait = config.waitAfterBoot, wait > 0 {
                        print("  [\(device.simulator)] Waiting \(wait)s after boot...")
                        sleep(UInt32(wait))
                    }

                    if config.darkMode == true {
                        try simulatorManager.setAppearance(udid: sim.udid, dark: true)
                    }

                    if config.overrideStatusBar {
                        print("  [\(device.simulator)] Overriding status bar...")
                        try simulatorManager.overrideStatusBar(udid: sim.udid, arguments: config.statusBarArguments)
                    }

                    if let bundleID = config.reinstallApp {
                        print("  [\(device.simulator)] Uninstalling app...")
                        try? simulatorManager.uninstallApp(udid: sim.udid, bundleID: bundleID)
                    }

                    try collector.prepareCacheDirectory(language: language, locale: locale, device: device, udid: sim.udid)
                }
            } catch {
                print("\n  Failed to prepare simulators for \(language): \(error)")
                for (device, _) in resolvedDevices {
                    results.append(Result(language: language, device: device.simulator, success: false, error: "\(error)"))
                }
                for (_, sim) in resolvedDevices {
                    try? simulatorManager.shutdown(udid: sim.udid)
                }
                continue
            }

            print("\n  Running tests concurrently...")
            let deviceResults = await withTaskGroup(of: (ScreenshotConfig.Device, SimulatorManager.SimDevice, Swift.Error?).self) { group in
                for (device, sim) in resolvedDevices {
                    group.addTask {
                        do {
                            try testRunner.test(device: device, udid: sim.udid, language: language, buildResult: buildResult)
                            return (device, sim, nil)
                        } catch {
                            return (device, sim, error)
                        }
                    }
                }

                var collected: [(ScreenshotConfig.Device, SimulatorManager.SimDevice, Swift.Error?)] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            let allSucceeded = deviceResults.allSatisfy { $0.2 == nil }
            if config.clearPreviousScreenshots && allSucceeded {
                try? collector.clearLanguageScreenshots(language: language)
            }

            for (device, sim, error) in deviceResults {
                if let error {
                    print("  [\(device.simulator)] Failed: \(error)")
                    let logFile = ScreenshotCollector.cacheRoot
                        .appendingPathComponent("logs")
                        .appendingPathComponent("\(device.simulator)-\(language).log")
                    let outputDir = URL(fileURLWithPath: config.outputDirectory)
                        .appendingPathComponent(language)
                    try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
                    let errorDest = outputDir.appendingPathComponent("\(device.simulator)-error.log")
                    try? FileManager.default.removeItem(at: errorDest)
                    try? FileManager.default.copyItem(at: logFile, to: errorDest)
                    results.append(Result(language: language, device: device.simulator, success: false, error: "\(error)"))
                } else {
                    let oldErrorLog = URL(fileURLWithPath: config.outputDirectory)
                        .appendingPathComponent(language)
                        .appendingPathComponent("\(device.simulator)-error.log")
                    try? FileManager.default.removeItem(at: oldErrorLog)

                    do {
                        try collector.collectScreenshots(language: language, device: device, udid: sim.udid)
                        results.append(Result(language: language, device: device.simulator, success: true, error: nil))
                    } catch {
                        print("  [\(device.simulator)] Failed to collect: \(error)")
                        results.append(Result(language: language, device: device.simulator, success: false, error: "\(error)"))
                    }
                }
                try? simulatorManager.shutdown(udid: sim.udid)
            }

            if config.stopAfterFirstError == true && results.contains(where: { !$0.success }) {
                print("\nStopping after first error.")
                break
            }
        }

        if !helperFound {
            let message = config.helperPath != nil
                ? "Could not find \(config.helperPath!) to check for updates."
                : "Could not find screenshot helper file to check for updates."
            print("\n" + yellow("Warning:") + " \(message) Set 'helperPath' in screenshot.yml to enable version checking.")
        }

        printSummary(results)
    }

    private func printSummary(_ results: [Result]) {
        print("\n")

        let devices = config.devices.map(\.simulator)
        let languages = config.languages

        let langWidth = max(8, languages.map(\.count).max() ?? 0)
        let deviceWidths = devices.map { max($0.count, 1) }

        var header = "Language".padding(toLength: langWidth + 2, withPad: " ", startingAt: 0)
        for (i, device) in devices.enumerated() {
            header += device.padding(toLength: deviceWidths[i] + 2, withPad: " ", startingAt: 0)
        }
        print(header)
        print(String(repeating: "─", count: header.count))

        for language in languages {
            var row = language.padding(toLength: langWidth + 2, withPad: " ", startingAt: 0)
            for (i, device) in devices.enumerated() {
                let result = results.first { $0.language == language && $0.device == device }
                let mark = result?.success == true ? "✅" : "❌"
                row += mark.padding(toLength: deviceWidths[i] + 2, withPad: " ", startingAt: 0)
            }
            print(row)
        }

        let succeeded = results.filter(\.success).count
        let failed = results.filter { !$0.success }.count
        print("\n\(succeeded) succeeded, \(failed) failed")

        if failed > 0 {
            print("\nFailed:")
            for result in results where !result.success {
                print("  ❌ \(result.language) / \(result.device): \(result.error ?? "unknown")")
            }
        }

        print("\nScreenshots saved to \(config.outputDirectory)")
    }

    private func languageToLocale(_ language: String) -> String {
        if language.contains("-") {
            return language.replacingOccurrences(of: "-", with: "_")
        }

        let mapping: [String: String] = [
            "tr": "tr_TR", "en": "en_US", "de": "de_DE", "fr": "fr_FR",
            "es": "es_ES", "it": "it_IT", "ja": "ja_JP", "ko": "ko_KR",
            "zh": "zh_CN", "pt": "pt_BR", "nl": "nl_NL", "ru": "ru_RU",
            "ar": "ar_SA",
        ]

        return mapping[language] ?? "\(language)_\(language.uppercased())"
    }

    /// Check the helper file version and warn if outdated. Returns whether the helper was found.
    @discardableResult
    private func checkHelperVersion() -> Bool {
        let currentVersion = ScreenshotCommand.CreateHelper.helperVersion

        if let helperPath = config.helperPath {
            let fullPath = helperPath.hasPrefix("/")
                ? helperPath
                : FileManager.default.currentDirectoryPath + "/" + helperPath

            guard FileManager.default.fileExists(atPath: fullPath) else {
                print(yellow("Warning:") + " Helper file not found at '\(helperPath)'. Check helperPath in screenshot.yml.")
                return false
            }

            checkVersionInFile(at: URL(fileURLWithPath: fullPath), currentVersion: currentVersion)
            return true
        } else {
            // Check default location first
            let defaultPath = ScreenshotCommand.defaultHelperPath
            if FileManager.default.fileExists(atPath: defaultPath) {
                checkVersionInFile(at: URL(fileURLWithPath: defaultPath), currentVersion: currentVersion)
                return true
            }

            // Fall back to scanning the project
            let cwd = FileManager.default.currentDirectoryPath
            let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: cwd),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )

            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                guard let content = try? String(contentsOf: url, encoding: .utf8),
                      content.contains("ScreenshotHelperVersion") else { continue }

                checkVersionInFile(at: url, currentVersion: currentVersion)
                return true
            }

            return false
        }
    }

    private func checkVersionInFile(at url: URL, currentVersion: String) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }

        guard let range = content.range(of: #"ScreenshotHelperVersion \[(.+?)\]"#, options: .regularExpression) else {
            print(yellow("Warning:") + " \(url.lastPathComponent) has no version marker. Run 'ascelerate screenshot create-helper' to regenerate.")
            return
        }

        let match = String(content[range])
        let fileVersion = match
            .replacingOccurrences(of: "ScreenshotHelperVersion [", with: "")
            .replacingOccurrences(of: "]", with: "")

        if fileVersion != currentVersion {
            print(yellow("Warning:") + " \(url.lastPathComponent) is version \(fileVersion), latest is \(currentVersion). Run 'ascelerate screenshot create-helper' to update.")
        }
    }
}
