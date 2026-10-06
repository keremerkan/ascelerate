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

        enum CodingKeys: String, CodingKey {
            case simulator, frameDevice
            case deviceBezels = "deviceBezel"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            simulator = try container.decode(String.self, forKey: .simulator)
            frameDevice = try container.decodeIfPresent(Bool.self, forKey: .frameDevice)
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
        let config = try decoder.decode(ScreenshotConfig.self, from: raw)

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
    # darkMode: false
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
    # xcargs: -resultBundlePath ./results
    """
}
