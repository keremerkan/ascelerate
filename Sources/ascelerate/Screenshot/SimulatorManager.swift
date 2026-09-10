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
