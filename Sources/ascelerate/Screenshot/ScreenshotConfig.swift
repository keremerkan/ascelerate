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
    var xcargs: String?

    var framedOutputDirectory: String?

    struct Device: Codable, Sendable {
        var simulator: String
        var frameDevice: Bool?
        var deviceBezel: String?
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

    # Status bar override (9:41, full bars, no carrier)
    overrideStatusBar: true
    # statusBarArguments: "--time '9:41' --dataNetwork wifi"

    # Build settings
    # configuration: Release
    # derivedDataPath: /path/to/DerivedData
    # testWithoutBuilding: true
    # cleanBuild: false
    # headless: false
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
    # xcargs: -resultBundlePath ./results
    """
}
