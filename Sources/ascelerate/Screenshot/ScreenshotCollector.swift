import Foundation

struct ScreenshotCollector: Sendable {
    let config: ScreenshotConfig

    static var cacheRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/tools.ascelerate")
    }

    func cacheDirectory(for udid: String) -> URL {
        Self.cacheRoot.appendingPathComponent(udid)
    }

    func screenshotsCache(for udid: String) -> URL {
        cacheDirectory(for: udid).appendingPathComponent("screenshots")
    }

    func prepareCacheDirectory(language: String, locale: String, device: ScreenshotConfig.Device, udid: String) throws {
        let fm = FileManager.default
        let cacheDir = cacheDirectory(for: udid)
        let screenshotsDir = screenshotsCache(for: udid)

        try fm.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)

        if let files = try? fm.contentsOfDirectory(at: screenshotsDir, includingPropertiesForKeys: nil) {
            for file in files {
                try fm.removeItem(at: file)
            }
        }

        try language.write(to: cacheDir.appendingPathComponent("language.txt"), atomically: true, encoding: .utf8)
        try locale.write(to: cacheDir.appendingPathComponent("locale.txt"), atomically: true, encoding: .utf8)
        try device.simulator.write(to: cacheDir.appendingPathComponent("device_name.txt"), atomically: true, encoding: .utf8)

        var launchArgs = config.launchArguments ?? []
        if config.disableAnimations == true {
            launchArgs += ["-ASC_DISABLE_ANIMATIONS", "YES"]
        }
        try launchArgs.joined(separator: " ").write(to: cacheDir.appendingPathComponent("screenshot-launch_arguments.txt"), atomically: true, encoding: .utf8)
    }

    /// Copies a device's screenshots into the language's output folder; returns how many.
    @discardableResult
    func collectScreenshots(language: String, device: ScreenshotConfig.Device, udid: String) throws -> Int {
        let fm = FileManager.default
        let outputDir = URL(fileURLWithPath: config.outputDirectory)
            .appendingPathComponent(language)

        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let screenshotsDir = screenshotsCache(for: udid)

        guard let files = try? fm.contentsOfDirectory(at: screenshotsDir, includingPropertiesForKeys: nil) else {
            ScreenshotOutput.log("  [\(device.simulator)] Warning: No screenshots found in cache directory")
            return 0
        }

        let screenshots = files.filter { $0.pathExtension.lowercased() == "png" }

        guard !screenshots.isEmpty else {
            ScreenshotOutput.log("  [\(device.simulator)] Warning: No PNG screenshots found")
            return 0
        }

        for file in screenshots {
            let destination = outputDir.appendingPathComponent(file.lastPathComponent)
            try? fm.removeItem(at: destination)
            try fm.copyItem(at: file, to: destination)
        }

        ScreenshotOutput.log("  [\(device.simulator)] Collected \(screenshots.count) screenshot(s) → \(language)/")
        return screenshots.count
    }

    func clearLanguageScreenshots(language: String) throws {
        let fm = FileManager.default
        let langDir = URL(fileURLWithPath: config.outputDirectory)
            .appendingPathComponent(language)

        if fm.fileExists(atPath: langDir.path) {
            try fm.removeItem(at: langDir)
        }
    }
}
