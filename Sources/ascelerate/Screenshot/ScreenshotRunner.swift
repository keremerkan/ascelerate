import Foundation

struct ScreenshotRunner: Sendable {
    let config: ScreenshotConfig

    struct Result {
        let language: String
        let device: String
        let success: Bool
        let error: String?
        var retried: Bool = false
    }

    func run() async throws {
        let startTime = Date()
        let outputPath = URL(fileURLWithPath: config.outputDirectory).standardizedFileURL.path
        EventOutput.emit(ScreenshotEvent(
            event: "start", scheme: config.scheme, devices: config.devices.map(\.simulator),
            languages: config.languages, outputDirectory: outputPath))
        let simulatorManager = SimulatorManager()
        let testRunner = ScreenshotTestRunner(config: config)
        let collector = ScreenshotCollector(config: config)

        let helperFound = checkHelperVersion()

        let resolvedDevices = try config.devices.map { device -> (ScreenshotConfig.Device, SimulatorManager.SimDevice) in
            let sim = try simulatorManager.findDevice(name: device.simulator)
            EventOutput.log("Found simulator: \(sim.name) (\(sim.udid))")
            return (device, sim)
        }

        EventOutput.emit(ScreenshotEvent(event: "build", step: "started"))
        let buildResult = try testRunner.build(resolvedDevices: resolvedDevices)
        EventOutput.emit(ScreenshotEvent(event: "build", step: "finished"))

        var results: [Result] = []

        // Pre-load bezels for framing (empty if no device has frameDevice enabled)
        let framer = ScreenshotFramer(config: config)
        let bezels = config.devices.contains(where: { $0.frameDevice == true })
            ? framer.loadBezels()
            : []

        for (langIndex, language) in config.languages.enumerated() {
            let locale = languageToLocale(language)
            EventOutput.log("\n--- [\(langIndex + 1)/\(config.languages.count)] \(language) ---")
            EventOutput.emit(ScreenshotEvent(
                event: "language", language: language, index: langIndex + 1, count: config.languages.count))

            do {
                if config.headless != true {
                    do {
                        try simulatorManager.launchUIHost()
                    } catch {
                        // Screenshots render off the framebuffer either way; windows are a nicety.
                        EventOutput.log("  " + yellow("Warning:") + " Could not open the simulator UI, continuing headless: \(error)")
                    }
                }

                try await prepareDevicesConcurrently(
                    resolvedDevices: resolvedDevices,
                    language: language,
                    locale: locale,
                    simulatorManager: simulatorManager,
                    collector: collector,
                    isFirstRun: langIndex == 0
                )
            } catch {
                EventOutput.log("\n  " + red("Failed to prepare simulators for \(language): \(error)"))
                for (device, _) in resolvedDevices {
                    EventOutput.emit(.device("failed", device.simulator, language: language, message: "\(error)"))
                    results.append(Result(language: language, device: device.simulator, success: false, error: "\(error)"))
                }
                for (_, sim) in resolvedDevices {
                    try? simulatorManager.shutdown(udid: sim.udid)
                }
                continue
            }

            EventOutput.log("\n  Running tests concurrently...")
            let deviceResults = await withTaskGroup(of: (ScreenshotConfig.Device, SimulatorManager.SimDevice, Swift.Error?).self) { group in
                for (device, sim) in resolvedDevices {
                    EventOutput.emit(.device("testing", device.simulator, language: language))
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

            var languageResults = evaluateTestResults(
                deviceResults, language: language, simulatorManager: simulatorManager
            )
            // Track which device results to collect from (updated if retries succeed)
            var pendingCollection = deviceResults

            // Retry failed devices with fresh simulator state (erase + reboot + re-localize)
            let maxRetries = config.numberOfRetries ?? 0
            if maxRetries > 0 {
            for attempt in 1...maxRetries where languageResults.contains(where: { !$0.success }) {

                let failedDevices = resolvedDevices.filter { device, _ in
                    languageResults.contains { !$0.success && $0.device == device.simulator }
                }
                guard !failedDevices.isEmpty else { break }

                EventOutput.log("\n  " + yellow("Retry \(attempt)/\(maxRetries) for \(language) — erasing failed simulators..."))

                for (device, _) in failedDevices {
                    EventOutput.emit(ScreenshotEvent(
                        event: "device", step: "retrying", language: language, device: device.simulator, index: attempt))
                }

                // Remove failed results — they'll be replaced by retry results
                let failedDeviceNames = Set(failedDevices.map { $0.0.simulator })
                languageResults.removeAll { failedDeviceNames.contains($0.device) }
                pendingCollection.removeAll { failedDeviceNames.contains($0.0.simulator) }

                do {
                    try await prepareDevicesConcurrently(
                        resolvedDevices: failedDevices,
                        language: language,
                        locale: locale,
                        simulatorManager: simulatorManager,
                        collector: collector,
                        forceErase: true
                    )

                    EventOutput.log("\n  Running retry tests...")
                    let retryResults = await withTaskGroup(of: (ScreenshotConfig.Device, SimulatorManager.SimDevice, Swift.Error?).self) { group in
                        for (device, sim) in failedDevices {
                            EventOutput.emit(.device("testing", device.simulator, language: language))
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

                    var retryLanguageResults = evaluateTestResults(
                        retryResults, language: language, simulatorManager: simulatorManager
                    )
                    for i in retryLanguageResults.indices {
                        retryLanguageResults[i].retried = true
                    }
                    languageResults += retryLanguageResults
                    pendingCollection += retryResults
                } catch {
                    EventOutput.log("\n  " + red("Retry preparation failed: \(error)"))
                    for (device, _) in failedDevices {
                        EventOutput.emit(.device("failed", device.simulator, language: language, message: "\(error)"))
                        languageResults.append(Result(language: language, device: device.simulator, success: false, error: "\(error)"))
                    }
                    for (_, sim) in failedDevices {
                        try? simulatorManager.shutdown(udid: sim.udid)
                    }
                    break
                }
            }
            }

            // Clear previous screenshots only if all devices succeeded (including after retries)
            let allSucceeded = languageResults.allSatisfy(\.success)
            if config.clearPreviousScreenshots && allSucceeded {
                try? collector.clearLanguageScreenshots(language: language)
            }

            // Collect screenshots from cache to output directory
            collectScreenshots(results: &languageResults, deviceResults: pendingCollection, language: language, collector: collector)

            results += languageResults

            // Frame screenshots for this language
            if !bezels.isEmpty {
                framer.frameLanguage(language, bezels: bezels)
            }

            if config.stopAfterFirstError == true && results.contains(where: { !$0.success }) {
                EventOutput.log("\nStopping after first error.")
                break
            }
        }

        if !bezels.isEmpty {
            framer.printFramingSummary()
        }

        if !helperFound {
            let message = config.helperPath != nil
                ? "Could not find \(config.helperPath!) to check for updates."
                : "Could not find screenshot helper file to check for updates."
            EventOutput.log("\n" + yellow("Warning:") + " \(message) Set 'helperPath' in screenshot.yml to enable version checking.")
        }

        let elapsed = Date().timeIntervalSince(startTime)
        EventOutput.emit(ScreenshotEvent(
            event: "finished", outputDirectory: outputPath,
            results: results.map {
                ScreenshotEvent.Result(language: $0.language, device: $0.device, success: $0.success, retried: $0.retried, error: $0.error)
            },
            elapsed: Int(elapsed)))
        printSummary(results, elapsed: elapsed)
    }

    /// Runs the full per-device prep flow for every device concurrently: optional erase,
    /// boot (with localization dance if enabled), the single waitAfterBoot sleep, appearance,
    /// status bar override, app uninstall, and cache dir prep. Boot commands run in parallel
    /// so the `waitAfterBoot` isn't multiplied by device count.
    private func prepareDevicesConcurrently(
        resolvedDevices: [(ScreenshotConfig.Device, SimulatorManager.SimDevice)],
        language: String,
        locale: String,
        simulatorManager: SimulatorManager,
        collector: ScreenshotCollector,
        forceErase: Bool = false,
        isFirstRun: Bool = false
    ) async throws {
        let config = self.config
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (device, sim) in resolvedDevices {
                group.addTask {
                    let tag = "[\(device.simulator)]"
                    EventOutput.log("\n  \(tag) Preparing...")
                    EventOutput.emit(.device("preparing", device.simulator, language: language))

                    let didErase = forceErase || config.eraseSimulator
                    if didErase {
                        EventOutput.log("  \(tag) Erasing...")
                        try simulatorManager.erase(udid: sim.udid)
                    }

                    if config.localizeSimulator {
                        try simulatorManager.boot(udid: sim.udid, waitUntilReady: false)
                        silenceSystemNoise(udid: sim.udid, tag: tag, simulatorManager: simulatorManager)
                        try simulatorManager.localize(udid: sim.udid, language: language, locale: locale)
                        EventOutput.log("  \(tag) Localized to \(language) (\(locale))")
                        try simulatorManager.shutdown(udid: sim.udid)
                        EventOutput.log("  \(tag) Booting and waiting for ready state...")
                        try simulatorManager.boot(udid: sim.udid)
                    } else {
                        EventOutput.log("  \(tag) Booting and waiting for ready state...")
                        try simulatorManager.boot(udid: sim.udid)
                        silenceSystemNoise(udid: sim.udid, tag: tag, simulatorManager: simulatorManager)
                    }

                    if config.headless != true {
                        do {
                            try simulatorManager.showDeviceWindow(udid: sim.udid)
                        } catch {
                            EventOutput.log("  \(tag) " + yellow("Warning:") + " Could not open the device window: \(error)")
                        }
                    }

                    if let wait = config.waitAfterBoot, wait > 0 {
                        EventOutput.log("  \(tag) Waiting \(wait)s after boot...")
                        try await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
                    }

                    if (didErase || isFirstRun), let extraWait = config.waitAfterEraseAndReboot, extraWait > 0 {
                        let reason = didErase ? "erased simulator" : "first run of this session"
                        EventOutput.log("  \(tag) Waiting \(extraWait)s for first-run system alerts (\(reason))...")
                        try await Task.sleep(nanoseconds: UInt64(extraWait) * 1_000_000_000)
                    }

                    if config.darkMode == true {
                        try simulatorManager.setAppearance(udid: sim.udid, dark: true)
                    }

                    if config.overrideStatusBar {
                        EventOutput.log("  \(tag) Overriding status bar...")
                        try simulatorManager.overrideStatusBar(udid: sim.udid, arguments: config.statusBarArguments)
                    }

                    if let bundleID = config.reinstallApp {
                        EventOutput.log("  \(tag) Uninstalling app...")
                        try? simulatorManager.uninstallApp(udid: sim.udid, bundleID: bundleID)
                    }

                    try collector.prepareCacheDirectory(language: language, locale: locale, device: device, udid: sim.udid)
                    EventOutput.emit(.device("ready", device.simulator, language: language))
                }
            }
            try await group.waitForAll()
        }
    }

    /// Best-effort suppression of system chatter that leaks into screenshots: the iOS 26
    /// "Ready for Apple Intelligence" banner always, background asset downloads when configured.
    /// Failures only warn; neither is worth failing a run over.
    private func silenceSystemNoise(udid: String, tag: String, simulatorManager: SimulatorManager) {
        do {
            try simulatorManager.suppressAppleIntelligenceBanner(udid: udid)
        } catch {
            EventOutput.log("  \(tag) " + yellow("Warning:") + " Could not suppress the Apple Intelligence banner: \(error)")
        }
        guard config.disableAssetDownloads == true else { return }
        EventOutput.log("  \(tag) Disabling asset downloads...")
        do {
            try simulatorManager.disableAssetDownloads(udid: udid)
        } catch {
            EventOutput.log("  \(tag) " + yellow("Warning:") + " Could not disable asset downloads: \(error)")
        }
    }

    private func evaluateTestResults(
        _ deviceResults: [(ScreenshotConfig.Device, SimulatorManager.SimDevice, Swift.Error?)],
        language: String,
        simulatorManager: SimulatorManager
    ) -> [Result] {
        var results: [Result] = []

        for (device, sim, error) in deviceResults {
            if let error {
                EventOutput.log("  [\(device.simulator)] " + red("Failed: \(error)"))
                EventOutput.emit(.device("failed", device.simulator, language: language, message: "\(error)"))
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
                EventOutput.emit(.device("passed", device.simulator, language: language))
                results.append(Result(language: language, device: device.simulator, success: true, error: nil))
            }
            try? simulatorManager.shutdown(udid: sim.udid)
        }

        return results
    }

    /// Collects screenshots from cache for successful results. Updates results in place on collection failure.
    private func collectScreenshots(
        results: inout [Result],
        deviceResults: [(ScreenshotConfig.Device, SimulatorManager.SimDevice, Swift.Error?)],
        language: String,
        collector: ScreenshotCollector
    ) {
        for (device, sim, _) in deviceResults {
            guard let idx = results.firstIndex(where: { $0.language == language && $0.device == device.simulator && $0.success }) else {
                continue
            }

            let oldErrorLog = URL(fileURLWithPath: config.outputDirectory)
                .appendingPathComponent(language)
                .appendingPathComponent("\(device.simulator)-error.log")
            try? FileManager.default.removeItem(at: oldErrorLog)

            do {
                let count = try collector.collectScreenshots(language: language, device: device, udid: sim.udid)
                EventOutput.emit(.device("collected", device.simulator, language: language, count: count))
            } catch {
                EventOutput.log("  [\(device.simulator)] " + red("Failed to collect: \(error)"))
                EventOutput.emit(.device("failed", device.simulator, language: language, message: "\(error)"))
                results[idx] = Result(language: language, device: device.simulator, success: false, error: "\(error)", retried: results[idx].retried)
            }
        }
    }

    private func printSummary(_ results: [Result], elapsed: TimeInterval) {
        EventOutput.log("\n")

        let devices = config.devices.map(\.simulator)
        let languages = config.languages

        let langWidth = max(8, languages.map(\.count).max() ?? 0)

        let deviceWidths = devices.map { max($0.count, 10) }

        var header = "Language".padding(toLength: langWidth + 2, withPad: " ", startingAt: 0)
        for (i, device) in devices.enumerated() {
            header += device.padding(toLength: deviceWidths[i] + 2, withPad: " ", startingAt: 0)
        }
        EventOutput.log(header)
        EventOutput.log(String(repeating: "─", count: header.count))

        for language in languages {
            var row = language.padding(toLength: langWidth + 2, withPad: " ", startingAt: 0)
            for (i, device) in devices.enumerated() {
                let result = results.first { $0.language == language && $0.device == device }
                let mark: String
                if result?.success == true {
                    mark = result?.retried == true ? "✅ 🔄" : "✅"
                } else {
                    mark = "❌"
                }
                row += mark.padding(toLength: deviceWidths[i] + 2, withPad: " ", startingAt: 0)
            }
            EventOutput.log(row)
        }

        let succeeded = results.filter(\.success).count
        let failed = results.filter { !$0.success }.count
        let retried = results.filter { $0.success && $0.retried }.count
        let succeededStr = succeeded > 0 ? green("\(succeeded) succeeded") : "\(succeeded) succeeded"
        let failedStr = failed > 0 ? red("\(failed) failed") : "\(failed) failed"
        var summary = "\(succeededStr), \(failedStr)"
        if retried > 0 {
            summary += " " + yellow("(\(retried) succeeded after retry — verify those screenshots)")
        }
        EventOutput.log("\n\(summary)")

        if failed > 0 {
            EventOutput.log("\n" + red("Failed:"))
            for result in results where !result.success {
                EventOutput.log("  " + red("❌ \(result.language) / \(result.device): \(result.error ?? "unknown")"))
            }
        }

        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        let timeStr = minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
        EventOutput.log("\nScreenshots saved to \(config.outputDirectory) (\(timeStr))")
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
                EventOutput.log(yellow("Warning:") + " Helper file not found at '\(helperPath)'. Check helperPath in screenshot.yml.")
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
            EventOutput.log(yellow("Warning:") + " \(url.lastPathComponent) has no version marker. Run 'ascelerate screenshot create-helper' to regenerate.")
            return
        }

        let match = String(content[range])
        let fileVersion = match
            .replacingOccurrences(of: "ScreenshotHelperVersion [", with: "")
            .replacingOccurrences(of: "]", with: "")

        if fileVersion != currentVersion {
            EventOutput.log(yellow("Warning:") + " \(url.lastPathComponent) is version \(fileVersion), latest is \(currentVersion). Run 'ascelerate screenshot create-helper' to update.")
        }
    }
}
