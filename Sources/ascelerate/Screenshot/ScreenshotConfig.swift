import ArgumentParser
import Foundation
import Yams

struct AscelerateConfig: Codable, Sendable {
    var screenshot: ScreenshotConfig?

    static func load(from path: String) throws -> AscelerateConfig {
        let url = URL(fileURLWithPath: path)
        let raw = try String(contentsOf: url, encoding: .utf8)
        let decoder = YAMLDecoder()
        let config = try decoder.decode(AscelerateConfig.self, from: raw)

        if let screenshot = config.screenshot {
            // Validate language codes contain only safe characters
            for lang in screenshot.languages {
                guard lang.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil else {
                    throw ValidationError("Invalid language code '\(lang)' in config.")
                }
            }
            // Validate outputDirectory is not a system path
            let resolved = URL(fileURLWithPath: screenshot.outputDirectory).standardized.path
            let dangerous = ["/", "/System", "/Library", "/usr", "/bin", "/sbin", "/etc", "/var", "/tmp", "/private"]
            guard !dangerous.contains(resolved) else {
                throw ValidationError("Refusing to use '\(screenshot.outputDirectory)' as output directory.")
            }
        }

        return config
    }
}

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
    var overrideStatusBar: Bool
    var statusBarArguments: String?
    var derivedDataPath: String?
    var testWithoutBuilding: Bool?
    var cleanBuild: Bool?
    var headless: Bool?
    var helperPath: String?
    var launchArguments: [String]?

    struct Device: Codable, Sendable {
        var simulator: String
    }

    static let exampleYAML = """
    screenshot:
      # Project configuration
      # project: App.xcodeproj
      workspace: App.xcworkspace
      scheme: AppUITests

      # Devices to capture screenshots from
      devices:
        - simulator: iPhone 16 Pro Max
        - simulator: iPad Pro 13-inch (M4)

      # Languages to capture
      languages:
        - en-US
        - tr-TR
        - de-DE

      # Output directory (relative to current directory)
      outputDirectory: ./screenshots

      # Simulator settings
      clearPreviousScreenshots: true
      eraseSimulator: false
      localizeSimulator: true

      # Status bar override (9:41, full bars, no carrier)
      overrideStatusBar: true
      # statusBarArguments: "--time '9:41' --dataNetwork wifi"

      # Build settings
      # derivedDataPath: /path/to/DerivedData
      # testWithoutBuilding: true
      # cleanBuild: false
      # headless: false

      # Path to ScreenshotHelper.swift (used for version checking)
      # Update this if you rename or move the file
      # helperPath: AppUITests/ScreenshotHelper.swift

      # Extra launch arguments passed to the app
      # launchArguments:
      #   - -ui_testing
    """
}
