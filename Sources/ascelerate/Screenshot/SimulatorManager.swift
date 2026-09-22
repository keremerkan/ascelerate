import Foundation

struct SimulatorManager: Sendable {
    struct SimDevice: Decodable {
        let udid: String
        let name: String
        let state: String
        let isAvailable: Bool
    }

    struct SimDeviceList: Decodable {
        let devices: [String: [SimDevice]]
    }

    /// The simulator window host inside the Xcode that `xcode-select` (or `DEVELOPER_DIR`) points
    /// at: DeviceHub.app on Xcode 27+ (`Contents/Applications`, bundle ID `com.apple.dt.Devices`),
    /// Simulator.app on Xcode 26 and earlier (`Contents/Developer/Applications`). Nil when the
    /// developer directory isn't a full Xcode.
    private func uiHostPath() throws -> String? {
        let developerDir = try ScreenshotShell.run("/usr/bin/xcode-select", arguments: ["-p"])
        let xcodeRoot = developerDir.replacingOccurrences(of: "/Contents/Developer", with: "")
        return [
            "\(xcodeRoot)/Contents/Applications/DeviceHub.app",
            "\(xcodeRoot)/Contents/Developer/Applications/Simulator.app",
        ].first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Launches the simulator window host. `open -a Simulator` resolves by name through
    /// LaunchServices and fails outright once no Simulator.app is registered anywhere on the
    /// machine, so resolve the host by path and fall back to bundle IDs.
    func launchUIHost() throws {
        if let path = try uiHostPath() {
            try ScreenshotShell.run("/usr/bin/open", arguments: ["-a", path])
            return
        }
        for bundleID in ["com.apple.dt.Devices", "com.apple.iphonesimulator"] {
            if (try? ScreenshotShell.run("/usr/bin/open", arguments: ["-b", bundleID])) != nil { return }
        }
        throw ScreenshotShellError.nonZeroExit(1, "No simulator UI host (DeviceHub.app or Simulator.app) found for the selected Xcode")
    }

    /// Shows the on-screen window of a booted device. Simulator.app opens a window for every
    /// booted device on its own; DeviceHub only shows devices opened through its URL scheme
    /// (`devices://device/open?id=<udid>`, verified on Xcode 27.1), so call this after each boot.
    func showDeviceWindow(udid: String) throws {
        guard let path = try uiHostPath(), path.hasSuffix("DeviceHub.app") else { return }
        try ScreenshotShell.run("/usr/bin/open", arguments: ["-a", path, "devices://device/open?id=\(udid)"])
    }

    func findDevice(name: String) throws -> SimDevice {
        let output = try ScreenshotShell.run("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j", "available"])
        let data = Data(output.utf8)
        let list = try JSONDecoder().decode(SimDeviceList.self, from: data)

        for (_, devices) in list.devices {
            if let device = devices.first(where: { $0.name == name && $0.isAvailable }) {
                return device
            }
        }

        throw ScreenshotError.simulatorNotFound(name)
    }

    func boot(udid: String, waitUntilReady: Bool = true) throws {
        do {
            try ScreenshotShell.run("/usr/bin/xcrun", arguments: ["simctl", "boot", udid])
        } catch {
            // Already booted is fine
        }
        if waitUntilReady {
            try ScreenshotShell.run("/usr/bin/xcrun", arguments: ["simctl", "bootstatus", udid, "-b"])
        }
    }

    func shutdown(udid: String) throws {
        do {
            try ScreenshotShell.run("/usr/bin/xcrun", arguments: ["simctl", "shutdown", udid])
        } catch {
            // Already shut down is fine
        }
    }

    func erase(udid: String) throws {
        try shutdown(udid: udid)
        try ScreenshotShell.run("/usr/bin/xcrun", arguments: ["simctl", "erase", udid])
    }

    static let defaultStatusBarArguments = "--time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --operatorName '' --cellularBars 4 --batteryState charged --batteryLevel 100"

    func overrideStatusBar(udid: String, arguments: String?) throws {
        var args = ["simctl", "status_bar", udid, "override"]

        let parts = try splitArguments(arguments ?? Self.defaultStatusBarArguments)
        args.append(contentsOf: parts)

        try ScreenshotShell.run("/usr/bin/xcrun", arguments: args)
    }

    func clearStatusBarOverride(udid: String) throws {
        try ScreenshotShell.run("/usr/bin/xcrun", arguments: ["simctl", "status_bar", udid, "clear"])
    }

    func setAppearance(udid: String, dark: Bool) throws {
        try ScreenshotShell.run("/usr/bin/xcrun", arguments: [
            "simctl", "ui", udid, "appearance", dark ? "dark" : "light",
        ])
    }

    /// iOS 26 posts a "Ready for Apple Intelligence" follow-up banner (followupd, delivered through
    /// the Settings notification section) the moment generativeexperiencesd sees the models ready.
    /// On the simulator that can be seconds after boot or minutes later, mid-capture. The daemon
    /// records when it last posted the follow-up and never re-posts, so stamping "now" before the
    /// first real boot suppresses it. iOS 27 no longer posts it; the write is harmless there.
    func suppressAppleIntelligenceBanner(udid: String) throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss +0000"
        try ScreenshotShell.run("/usr/bin/xcrun", arguments: [
            "simctl", "spawn", udid, "defaults", "write",
            "com.apple.generativeexperiences.corefollowup",
            "DateOfLastAppleIntelligenceReadinessCFU", "-date", formatter.string(from: Date()),
        ])
    }

    /// mobileassetd pulls gigabytes of Siri, keyboard, and ML assets into every freshly erased
    /// simulator. Disabling it in the simulator's own launchd persists across reboots (an erase
    /// resets it, which is why this runs during every prep). The service is usually already
    /// running when this is called, so it is also booted out.
    func disableAssetDownloads(udid: String) throws {
        let service = "user/\(getuid())/com.apple.mobileassetd"
        try ScreenshotShell.run("/usr/bin/xcrun", arguments: ["simctl", "spawn", udid, "launchctl", "disable", service])
        do {
            try ScreenshotShell.run("/usr/bin/xcrun", arguments: ["simctl", "spawn", udid, "launchctl", "bootout", service])
        } catch {
            // Not running yet: the disable alone keeps it from launching.
        }
    }

    func uninstallApp(udid: String, bundleID: String) throws {
        try ScreenshotShell.run("/usr/bin/xcrun", arguments: [
            "simctl", "uninstall", udid, bundleID,
        ])
    }

    func localize(udid: String, language: String, locale: String) throws {
        try ScreenshotShell.run("/usr/bin/xcrun", arguments: [
            "simctl", "spawn", udid, "defaults", "write",
            "Apple Global Domain", "AppleLanguages", "-array", language,
        ])
        try ScreenshotShell.run("/usr/bin/xcrun", arguments: [
            "simctl", "spawn", udid, "defaults", "write",
            "Apple Global Domain", "AppleLocale", "-string", locale,
        ])

        let keyboard = "\(locale)@sw=\(language)"
        try ScreenshotShell.run("/usr/bin/xcrun", arguments: [
            "simctl", "spawn", udid, "defaults", "write",
            "Apple Global Domain", "AppleKeyboards", "-array", keyboard,
        ])
    }

}
