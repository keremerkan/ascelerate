import ArgumentParser
import Foundation
import Yams

struct ScreenshotConfig: Codable, Sendable {
  var project: String?
  var workspace: String?
  var scheme: String
  var devices: [Device]
  var languages: [String]
  var outputDirectory: String
  var clearPreviousScreenshots: Bool
  var eraseSimulator: Bool
  var localizeSimulator: Bool
  var darkMode: Bool?
  var disableAnimations: Bool?
  var waitAfterBoot: Int?
  var waitAfterEraseAndReboot: Int?
  var overrideStatusBar: Bool
  var statusBarArguments: String?
  var configuration: String?
  var derivedDataPath: String?
  var testWithoutBuilding: Bool?
  var cleanBuild: Bool?
  var headless: Bool?
  var helperPath: String?
  var launchArguments: [String]?
  var testplan: String?
  var numberOfRetries: Int?
  var stopAfterFirstError: Bool?
  var reinstallApp: String?
  var disableAssetDownloads: Bool?
  var xcargs: String?

  var framedOutputDirectory: String?

  struct Device: Codable, Sendable {
    var simulator: String
    var frameDevice: Bool?
    /// `deviceBezel` in YAML: one path, or a list (e.g. an iPhone Duo's folded and unfolded
    /// frames). Each screenshot is framed with the bezel whose screen area fits it best.
    var deviceBezels: [String]
    /// Pins the simulator when a device of that name exists on several runtimes: a runtime's
    /// version ("26.5") or identifier, or the device's UDID. Without one, the newest runtime's.
    var runtime: String?
    var udid: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
      case simulator, frameDevice, runtime, udid
      case deviceBezels = "deviceBezel"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      simulator = try container.decode(String.self, forKey: .simulator)
      frameDevice = try container.decodeIfPresent(Bool.self, forKey: .frameDevice)
      runtime = try container.decodeIfPresent(String.self, forKey: .runtime)
      udid = try container.decodeIfPresent(String.self, forKey: .udid)
      if let single = try? container.decodeIfPresent(String.self, forKey: .deviceBezels) {
        deviceBezels = [single]
      } else {
        deviceBezels = try container.decodeIfPresent([String].self, forKey: .deviceBezels) ?? []
      }
    }
  }

  static func load(from path: String) throws -> ScreenshotConfig {
    let url = URL(fileURLWithPath: path)
    let raw = try String(contentsOf: url, encoding: .utf8)
    let decoder = YAMLDecoder()
    var config = try decoder.decode(ScreenshotConfig.self, from: raw)
    try checkKeys(raw, known: Mirror(reflecting: config).children.compactMap(\.label))
    // `~` in a path works everywhere the path is used (doctor's checks, xcodebuild's arguments).
    config.project = config.project.map(expandPath)
    config.workspace = config.workspace.map(expandPath)
    config.outputDirectory = expandPath(config.outputDirectory)
    config.framedOutputDirectory = config.framedOutputDirectory.map(expandPath)
    config.helperPath = config.helperPath.map(expandPath)
    config.derivedDataPath = config.derivedDataPath.map(expandPath)
    // One simulator per entry: two entries of the same name ran two tests on one simulator.
    let names = config.devices.map(\.simulator)
    if let repeated = names.first(where: { name in names.filter { $0 == name }.count > 1 }) {
      throw ValidationError("'\(repeated)' is listed more than once under 'devices'.")
    }
    // Framed output in the output folder would frame the frames on the next run.
    if let framed = config.framedOutputDirectory,
      URL(fileURLWithPath: framed).standardized.path == URL(fileURLWithPath: config.outputDirectory).standardized.path
    {
      throw ValidationError("'framedOutputDirectory' is the output directory; frame into a folder of its own.")
    }

    // A run needs at least one device and one language: with none, every device "passed".
    guard !config.devices.isEmpty else {
      throw ValidationError("The config lists no devices; add at least one under 'devices'.")
    }
    guard !config.languages.isEmpty else {
      throw ValidationError("The config lists no languages; add at least one under 'languages'.")
    }

    // Validate language codes contain only safe characters
    for lang in config.languages {
      guard lang.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil else {
        throw ValidationError("Invalid language code '\(lang)' in config.")
      }
    }
    // Validate outputDirectory is not a system path
    let resolved = URL(fileURLWithPath: config.outputDirectory).standardized.path
    let dangerous = ["/", "/System", "/Library", "/usr", "/bin", "/sbin", "/etc", "/var", "/tmp", "/private"]
    guard !dangerous.contains(resolved) else {
      throw ValidationError("Refusing to use '\(config.outputDirectory)' as output directory.")
    }

    return config
  }

  static let exampleYAML = """
  # Project configuration
  # project: App.xcodeproj
  workspace: App.xcworkspace
  scheme: AppUITests

  # Devices to capture screenshots from
  devices:
    - simulator: iPhone 17 Pro Max
      # frameDevice: true
      # deviceBezel: ./bezels/iPhone 17 Pro Max.png
    - simulator: iPad Pro 13-inch (M5)
      # frameDevice: true
      # deviceBezel: ./bezels/iPad Pro 13-inch (M5).png
    # A list of bezels frames each screenshot with the one that fits its size,
    # e.g. iPhone Duo folded and unfolded (setHinge in the UI test):
    # - simulator: iPhone Duo
    #   frameDevice: true
    #   deviceBezel:
    #     - ./bezels/iPhone Duo - Outer Closed Portrait.png
    #     - ./bezels/iPhone Duo - Inner Open Landscape.png

  # Languages to capture
  languages:
    - en-US
    - tr-TR
    - de-DE

  # Output directory (relative to project root)
  outputDirectory: ./screenshots

  # Screenshot framing (device bezels)
  # framedOutputDirectory: ./screenshots/framed

  # Simulator settings
  clearPreviousScreenshots: true
  eraseSimulator: false
  localizeSimulator: true
  # darkMode: false            # true: dark; false or left out: light
  # disableAnimations: false
  # waitAfterBoot: 0
  # Extra wait (in seconds) for first-run system alerts to appear and settle.
  # A simulator may show system alerts the first time it boots or after an
  # erase, and these can leak into screenshots. This wait gives those alerts
  # time to appear so they can be dismissed (manually or by the test) before
  # screenshots are captured. (The iOS 26 "Ready for Apple Intelligence"
  # banner is suppressed automatically and needs no wait.)
  # Triggers when:
  #   - It's the first language being processed in this run (regardless of
  #     other settings — the simulator state from prior runs is unknown)
  #   - The simulator was erased in this prep cycle (either via
  #     eraseSimulator: true or a retry forcing an erase after a failure)
  # Subsequent languages with no erase reuse the warm simulator and skip
  # this wait, since first-run alerts won't reappear.
  # waitAfterEraseAndReboot: 30

  # Status bar override (9:41, full bars, no carrier)
  overrideStatusBar: true
  # statusBarArguments: "--time '9:41' --dataNetwork wifi"

  # Build settings
  # configuration: Release
  # derivedDataPath: /path/to/DerivedData
  # testWithoutBuilding: true
  # cleanBuild: false
  # headless: false                    # Don't open simulator windows (DeviceHub / Simulator.app)
  # numberOfRetries: 0

  # Path to ScreenshotHelper.swift (used for version checking)
  # Update this if you move the file out of ascelerate/
  # helperPath: AppUITests/ScreenshotHelper.swift

  # Extra launch arguments passed to the app
  # launchArguments:
  #   - -ui_testing

  # Advanced options (rarely needed)
  # testplan: MyTestPlan
  # stopAfterFirstError: false
  # reinstallApp: com.example.MyApp
  # Keep mobileassetd from downloading gigabytes of Siri/keyboard/ML assets into
  # freshly erased simulators. Also blocks on-device ML assets some apps need
  # (e.g. text recognition), so leave it off if your screenshots depend on those.
  # disableAssetDownloads: true
  # xcargs: -skipPackagePluginValidation   # quoted arguments work ("a b")
  """
}

extension ScreenshotConfig {
  static let deviceKeys = Device.CodingKeys.allCases.map(\.rawValue)

  /// Refuses a key the config doesn't know (a typo such as `numberOfRetrys` did nothing),
  /// naming the nearest known one (Kerem, 2026-11-26).
  static func checkKeys(_ raw: String, known: [String]) throws {
    guard let root = try Yams.compose(yaml: raw), let mapping = root.mapping else { return }
    var problems: [String] = []
    func check(_ keys: [String], against known: [String], in place: String) {
      for key in keys where !known.contains(key) {
        let hint = nearest(key, among: known).map { " (did you mean '\($0)'?)" } ?? ""
        problems.append("'\(key)'\(place)\(hint)")
      }
    }
    check(mapping.keys.compactMap(\.string), against: known, in: "")
    if let devices = mapping["devices"]?.sequence {
      for (i, device) in devices.enumerated() {
        check(device.mapping?.keys.compactMap(\.string) ?? [], against: deviceKeys, in: " in device \(i + 1)")
      }
    }
    guard problems.isEmpty else {
      throw ValidationError("Unknown key\(problems.count == 1 ? "" : "s") in the config: \(problems.joined(separator: ", ")).")
    }
  }

  /// The known key closest to `key` (same letters in another case, or a few edits away).
  static func nearest(_ key: String, among known: [String]) -> String? {
    func distance(_ a: String, _ b: String) -> Int {
      let a = Array(a.lowercased()), b = Array(b.lowercased())
      var row = Array(0...b.count)
      for i in 1...max(a.count, 1) where i <= a.count {
        var previous = row[0]
        row[0] = i
        for j in 1...max(b.count, 1) where j <= b.count {
          let current = row[j]
          row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
          previous = current
        }
      }
      return row[b.count]
    }
    let best = known.map { ($0, distance(key, $0)) }.min { $0.1 < $1.1 }
    guard let best, best.1 <= max(2, key.count / 4) else { return nil }
    return best.0
  }
}
