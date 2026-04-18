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

        let parts = splitArguments(arguments ?? Self.defaultStatusBarArguments)
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
