import AscelerateCore
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

  /// A runtime identifier's version ("com.apple.CoreSimulator.SimRuntime.iOS-26-5" → [26, 5]).
  static func runtimeVersion(_ key: String) -> [Int] {
    let tail = key.split(separator: ".").last.map(String.init) ?? key
    return tail.split(separator: "-").compactMap { Int($0) }
  }

  /// "iOS 26.5" for "com.apple.CoreSimulator.SimRuntime.iOS-26-5".
  static func runtimeLabel(_ key: String) -> String {
    let tail = key.split(separator: ".").last.map(String.init) ?? key
    let parts = tail.split(separator: "-")
    guard let platform = parts.first else { return key }
    return "\(platform) \(parts.dropFirst().joined(separator: "."))"
  }

  /// Whether a pinned runtime ("26.5", "iOS 26.5" or the identifier) names this runtime.
  static func runtime(_ key: String, matches pin: String) -> Bool {
    if key == pin { return true }
    let wanted = pin.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    return !wanted.isEmpty && runtimeVersion(key) == wanted
  }

  /// Every available device of the name, newest runtime first.
  func candidates(name: String) throws -> [(runtime: String, device: SimDevice)] {
    let output = try ScreenshotShell.run("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j", "available"])
    let list = try JSONDecoder().decode(SimDeviceList.self, from: Data(output.utf8))
    return list.devices.flatMap { runtime, devices in
      devices.filter { $0.name == name && $0.isAvailable }.map { (runtime, $0) }
    }.sorted { Self.runtimeVersion($1.runtime).lexicographicallyPrecedes(Self.runtimeVersion($0.runtime)) }
  }

  /// The device a config entry means: its `udid`, else the named device on its `runtime`, else
  /// the named device on the newest runtime that has one (a dictionary's order used to pick at
  /// random among runtimes).
  func findDevice(name: String, runtime: String? = nil, udid: String? = nil) throws -> SimDevice {
    let found = try candidates(name: name)
    if let udid {
      let output = try ScreenshotShell.run("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j", "available"])
      let list = try JSONDecoder().decode(SimDeviceList.self, from: Data(output.utf8))
      if let device = list.devices.values.joined().first(where: { $0.udid.caseInsensitiveCompare(udid) == .orderedSame }) { return device }
      throw ScreenshotError.simulatorNotFound("\(name) (UDID \(udid))")
    }
    if let runtime {
      guard let match = found.first(where: { Self.runtime($0.runtime, matches: runtime) }) else {
        throw ScreenshotError.simulatorNotFound("\(name) on runtime \(runtime)")
      }
      return match.device
    }
    guard let newest = found.first else { throw ScreenshotError.simulatorNotFound(name) }
    return newest.device
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
