import ArgumentParser
import Foundation

struct ScreenshotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Capture App Store screenshots from simulators.",
        subcommands: [Run.self, Init.self, CreateHelper.self],
        defaultSubcommand: Run.self
    )

    static let configPath = "ascelerate/screenshot.yml"
    static let defaultHelperPath = "ascelerate/ScreenshotHelper.swift"

    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Capture screenshots for all configured devices and languages."
        )

        func run() async throws {
            let configPath = ScreenshotCommand.configPath

            guard FileManager.default.fileExists(atPath: configPath) else {
                throw ScreenshotError.configNotFound(configPath)
            }

            let screenshotConfig = try ScreenshotConfig.load(from: configPath)

            print("ascelerate screenshot")
            print("  Scheme: \(screenshotConfig.scheme)")
            print("  Devices: \(screenshotConfig.devices.map(\.simulator).joined(separator: ", "))")
            print("  Languages: \(screenshotConfig.languages.joined(separator: ", "))")
            print("  Output: \(screenshotConfig.outputDirectory)")

            let runner = ScreenshotRunner(config: screenshotConfig)
            try await runner.run()
        }
    }

    struct Init: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Initialize screenshot configuration and helper."
        )

        func run() throws {
            let fm = FileManager.default
            let cwd = fm.currentDirectoryPath
            let dir = "ascelerate"
            let configPath = ScreenshotCommand.configPath
            let helperPath = ScreenshotCommand.defaultHelperPath

            print("This will create files in \(cwd)/\(dir)/")
            guard confirm("Continue? [y/N] ") else {
                print("Cancelled.")
                return
            }

            // Create ascelerate/ directory
            if !fm.fileExists(atPath: dir) {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }

            // Create screenshot.yml
            if fm.fileExists(atPath: configPath) {
                print("Config already exists at \(configPath)")
            } else {
                try ScreenshotConfig.exampleYAML.write(toFile: configPath, atomically: true, encoding: .utf8)
                print(green("Created") + " \(configPath)")
            }

            // Create ScreenshotHelper.swift
            if fm.fileExists(atPath: helperPath) {
                print("Helper already exists at \(helperPath)")
            } else {
                try CreateHelper.helperSource.write(toFile: helperPath, atomically: true, encoding: .utf8)
                print(green("Created") + " \(helperPath)")
            }

            print()
            print("Next steps:")
            print("  1. Edit \(configPath) to match your project")
            print("  2. Add \(helperPath) to your UITest target")
            print("  3. Run: ascelerate screenshot")
        }
    }

    struct CreateHelper: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create-helper",
            abstract: "Generate ScreenshotHelper.swift to add to your UITest target."
        )

        @Option(name: .shortAndLong, help: "Output file path.")
        var output: String?

        func run() throws {
            let filename: String
            if let output {
                filename = output
            } else {
                let defaultPath = ScreenshotCommand.defaultHelperPath
                print("Enter filename [\(defaultPath)]: ", terminator: "")
                let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                filename = input.isEmpty ? defaultPath : input
            }

            let outputPath = expandPath(filename)

            if FileManager.default.fileExists(atPath: outputPath) {
                guard confirm("File already exists at \(filename). Overwrite? [y/N] ") else {
                    print("Cancelled.")
                    return
                }
            }

            // Ensure parent directory exists
            let parentDir = (outputPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

            try Self.helperSource.write(toFile: outputPath, atomically: true, encoding: .utf8)
            print(green("Created") + " \(filename)")
            print("Add this file to your UITest target.")
        }

        static let helperVersion = "1.0"

        static let helperSource = """
        //
        //  ScreenshotHelper.swift
        //  Add this file to your UITest target.
        //
        //  Generated by ascelerate screenshot
        //  ScreenshotHelperVersion [\(helperVersion)]
        //

        import Foundation
        import XCTest

        // MARK: - Public API

        /// Call this in your test's setUp() before launching the app.
        /// Set `waitForAnimations: false` if you disable animations via config.
        @MainActor
        func setupScreenshots(_ app: XCUIApplication, waitForAnimations: Bool = true) {
            Screenshot.setup(app, waitForAnimations: waitForAnimations)
        }

        /// Copy this function to your AppDelegate or SceneDelegate and call it on launch
        /// to disable animations when running in screenshot mode.
        /// Pair with `disableAnimations: true` in screenshot.yml.
        func disableAnimationsIfNeeded() {
            if ProcessInfo.processInfo.arguments.contains("-ASC_DISABLE_ANIMATIONS") {
                UIView.setAnimationsEnabled(false)
            }
        }

        /// Call this to capture a screenshot with the given name.
        @MainActor
        func screenshot(_ name: String) {
            Screenshot.capture(name)
        }

        // MARK: - Implementation

        @MainActor
        enum Screenshot {
            static var app: XCUIApplication?
            static var waitForAnimations = true
            static var cacheDirectory: URL?
            static var deviceName: String = ""

            static var screenshotsDirectory: URL? {
                cacheDirectory?.appendingPathComponent("screenshots", isDirectory: true)
            }

            static func setup(_ app: XCUIApplication, waitForAnimations: Bool = true) {
                Self.app = app
                Self.waitForAnimations = waitForAnimations

                do {
                    let cacheDir = try getCacheDirectory()
                    Self.cacheDirectory = cacheDir
                    readDeviceName()
                    setLanguage(app)
                    setLocale(app)
                    setLaunchArguments(app)
                } catch {
                    NSLog("ScreenshotHelper setup error: \\(error.localizedDescription)")
                }
            }

            static func capture(_ name: String) {
                guard app != nil else {
                    NSLog("ScreenshotHelper: Call setupScreenshots() before screenshot()")
                    return
                }

                NSLog("screenshot: \\(name)")

                if waitForAnimations {
                    sleep(1)
                }

                let screenshotImage = XCUIScreen.main.screenshot()

                #if os(iOS) && !targetEnvironment(macCatalyst)
                let image = XCUIDevice.shared.orientation.isLandscape
                    ? fixLandscapeOrientation(image: screenshotImage.image)
                    : screenshotImage.image
                #else
                let image = screenshotImage.image
                #endif

                guard let screenshotsDir = screenshotsDirectory else {
                    NSLog("ScreenshotHelper: Screenshots directory not set. Call setupScreenshots() first.")
                    return
                }

                do {
                    let filename = deviceName.isEmpty ? "\\(name).png" : "\\(deviceName)-\\(name).png"
                    let path = screenshotsDir.appendingPathComponent(filename)
                    try image.pngData()?.write(to: path, options: .atomic)
                } catch {
                    NSLog("ScreenshotHelper: Failed to write screenshot '\\(name)': \\(error.localizedDescription)")
                }
            }

            // MARK: - Private

            private static func readDeviceName() {
                guard let cacheDirectory else { return }
                let path = cacheDirectory.appendingPathComponent("device_name.txt")
                guard let name = try? String(contentsOf: path, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty else { return }
                deviceName = name
            }

            private static func getCacheDirectory() throws -> URL {
                guard let simulatorHome = ProcessInfo().environment["SIMULATOR_HOST_HOME"] else {
                    throw ScreenshotHelperError.noSimulatorHome
                }
                guard let udid = ProcessInfo().environment["SIMULATOR_UDID"] else {
                    throw ScreenshotHelperError.noSimulatorUDID
                }
                return URL(fileURLWithPath: simulatorHome)
                    .appendingPathComponent("Library/Caches/tools.ascelerate")
                    .appendingPathComponent(udid)
            }

            private static func setLanguage(_ app: XCUIApplication) {
                guard let cacheDirectory else { return }
                let path = cacheDirectory.appendingPathComponent("language.txt")
                guard let language = try? String(contentsOf: path, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !language.isEmpty else { return }
                app.launchArguments += ["-AppleLanguages", "(\\(language))"]
            }

            private static func setLocale(_ app: XCUIApplication) {
                guard let cacheDirectory else { return }
                let path = cacheDirectory.appendingPathComponent("locale.txt")
                guard let locale = try? String(contentsOf: path, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !locale.isEmpty else { return }
                app.launchArguments += ["-AppleLocale", "\\"\\(locale)\\""]
            }

            private static func setLaunchArguments(_ app: XCUIApplication) {
                guard let cacheDirectory else { return }
                let path = cacheDirectory.appendingPathComponent("screenshot-launch_arguments.txt")
                app.launchArguments += ["-ASC_SCREENSHOT", "YES", "-ui_testing"]

                guard let args = try? String(contentsOf: path, encoding: .utf8),
                      !args.isEmpty else { return }

                // Split respecting quoted strings
                let regex = try! NSRegularExpression(pattern: #"(".+?"|\\S+)"#)
                let matches = regex.matches(in: args, range: NSRange(location: 0, length: args.count))
                let parts = matches.map { (args as NSString).substring(with: $0.range) }
                app.launchArguments += parts
            }

            #if os(iOS) && !targetEnvironment(macCatalyst)
            private static func fixLandscapeOrientation(image: UIImage) -> UIImage {
                let format = UIGraphicsImageRendererFormat()
                format.scale = image.scale
                let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
                return renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: image.size))
                }
            }
            #endif
        }

        enum ScreenshotHelperError: Error, CustomDebugStringConvertible {
            case noSimulatorHome
            case noSimulatorUDID

            var debugDescription: String {
                switch self {
                case .noSimulatorHome:
                    "Could not find SIMULATOR_HOST_HOME. Are you running on a simulator?"
                case .noSimulatorUDID:
                    "Could not find SIMULATOR_UDID. Are you running on a simulator?"
                }
            }
        }
        """
    }
}
