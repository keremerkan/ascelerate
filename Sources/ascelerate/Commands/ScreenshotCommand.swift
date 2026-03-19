import ArgumentParser
import Foundation

struct ScreenshotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Capture App Store screenshots from simulators.",
        subcommands: [Run.self, Init.self, CreateHelper.self, Frame.self, Doctor.self],
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

    struct Frame: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Frame captured screenshots with device bezels."
        )

        func run() throws {
            let configPath = ScreenshotCommand.configPath
            guard FileManager.default.fileExists(atPath: configPath) else {
                throw ScreenshotError.configNotFound(configPath)
            }

            let config = try ScreenshotConfig.load(from: configPath)
            let devices = config.devices.filter { $0.frameDevice == true }
            guard !devices.isEmpty else {
                print("No devices have frameDevice enabled in \(configPath)")
                return
            }

            let framer = ScreenshotFramer(config: config)
            try framer.frameAll()
        }
    }

    struct Doctor: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check screenshot configuration for problems."
        )

        private struct Check {
            let name: String
            let status: String
            let detail: String
        }

        func run() throws {
            let configPath = ScreenshotCommand.configPath
            let fm = FileManager.default

            print("ascelerate screenshot doctor\n")

            var checks: [Check] = []

            func pass(_ name: String, _ detail: String = "") {
                checks.append(Check(name: name, status: green("✓"), detail: detail))
            }

            func fail(_ name: String, _ detail: String) {
                checks.append(Check(name: name, status: red("✗"), detail: detail))
            }

            func warn(_ name: String, _ detail: String) {
                checks.append(Check(name: name, status: yellow("!"), detail: detail))
            }

            // 1. Config file
            guard fm.fileExists(atPath: configPath) else {
                if fm.fileExists(atPath: URL(fileURLWithPath: configPath).lastPathComponent) {
                    fail("Config", "Not found at \(configPath). It looks like you're inside the ascelerate/ folder. Run the command from the project root (cd ..).")
                } else {
                    fail("Config", "Not found at \(configPath). Run 'ascelerate screenshot init'.")
                }
                printChecks(checks)
                return
            }
            pass("Config", configPath)

            // 2. Parse config
            let config: ScreenshotConfig
            do {
                config = try ScreenshotConfig.load(from: configPath)
            } catch {
                fail("Config", "Failed to parse: \(error)")
                printChecks(checks)
                return
            }
            pass("Config parsing", "Valid YAML")

            // 3. Project or workspace
            if let workspace = config.workspace {
                if fm.fileExists(atPath: workspace) {
                    pass("Workspace", workspace)
                } else {
                    fail("Workspace", "Not found: \(workspace)")
                }
            } else if let project = config.project {
                if fm.fileExists(atPath: project) {
                    pass("Project", project)
                } else {
                    fail("Project", "Not found: \(project)")
                }
            } else {
                fail("Project", "No 'project' or 'workspace' specified in config")
            }

            // 4. xcodebuild
            if let version = try? ScreenshotShell.run("/usr/bin/xcodebuild", arguments: ["-version"]) {
                let firstLine = version.components(separatedBy: .newlines).first ?? version
                pass("xcodebuild", firstLine)
            } else {
                fail("xcodebuild", "Not found or not working. Install Xcode Command Line Tools.")
            }

            // 5. xcrun simctl
            if (try? ScreenshotShell.run("/usr/bin/xcrun", arguments: ["simctl", "help"])) != nil {
                pass("simctl", "Available")
            } else {
                fail("simctl", "xcrun simctl not working")
            }

            // 6. Simulators
            let simulatorManager = SimulatorManager()
            for device in config.devices {
                do {
                    let sim = try simulatorManager.findDevice(name: device.simulator)
                    pass("Simulator", "\(device.simulator) (\(sim.udid))")
                } catch {
                    fail("Simulator", "'\(device.simulator)' not found. Check available devices with 'xcrun simctl list devices available'.")
                }
            }

            // 7. Helper file
            let helperPath = config.helperPath ?? ScreenshotCommand.defaultHelperPath
            if fm.fileExists(atPath: helperPath) {
                if let content = try? String(contentsOfFile: helperPath, encoding: .utf8),
                   let range = content.range(of: #"ScreenshotHelperVersion \[(.+?)\]"#, options: .regularExpression) {
                    let match = String(content[range])
                    let version = match
                        .replacingOccurrences(of: "ScreenshotHelperVersion [", with: "")
                        .replacingOccurrences(of: "]", with: "")
                    let current = CreateHelper.helperVersion
                    if version == current {
                        pass("Helper", "\(helperPath) (v\(version))")
                    } else {
                        warn("Helper", "\(helperPath) is v\(version), latest is v\(current). Run 'ascelerate screenshot create-helper'.")
                    }
                } else {
                    warn("Helper", "\(helperPath) has no version marker")
                }
            } else {
                warn("Helper", "Not found at \(helperPath). Run 'ascelerate screenshot create-helper'.")
            }

            // 8. Languages
            if config.languages.isEmpty {
                fail("Languages", "No languages configured")
            } else {
                pass("Languages", config.languages.joined(separator: ", "))
            }

            // 9. Output directory
            let outputDir = config.outputDirectory
            let outputURL = URL(fileURLWithPath: outputDir)
            if fm.fileExists(atPath: outputURL.path) {
                if fm.isWritableFile(atPath: outputURL.path) {
                    pass("Output directory", outputDir)
                } else {
                    fail("Output directory", "\(outputDir) is not writable")
                }
            } else {
                // Will be created at runtime
                pass("Output directory", "\(outputDir) (will be created)")
            }

            // 10. Device bezels
            let framingDevices = config.devices.filter { $0.frameDevice == true }
            if !framingDevices.isEmpty {
                for device in framingDevices {
                    if let bezelPath = device.deviceBezel, !bezelPath.isEmpty {
                        let resolved = URL(fileURLWithPath: bezelPath).path
                        if fm.fileExists(atPath: resolved) {
                            pass("Bezel", "\(device.simulator) → \(bezelPath)")
                        } else {
                            fail("Bezel", "\(device.simulator) → file not found: \(bezelPath)")
                        }
                    } else {
                        fail("Bezel", "\(device.simulator) has frameDevice enabled but no deviceBezel path")
                    }
                }

                // 11. Framed output directory
                if let framedDir = config.framedOutputDirectory {
                    let framedURL = URL(fileURLWithPath: framedDir)
                    if fm.fileExists(atPath: framedURL.path) {
                        if fm.isWritableFile(atPath: framedURL.path) {
                            pass("Framed output", framedDir)
                        } else {
                            fail("Framed output", "\(framedDir) is not writable")
                        }
                    } else {
                        pass("Framed output", "\(framedDir) (will be created)")
                    }
                } else {
                    pass("Framed output", "\(outputDir)/framed (default)")
                }
            }

            printChecks(checks)
        }

        private func printChecks(_ checks: [Check]) {
            let nameWidth = max(checks.map { $0.name.count }.max() ?? 0, 6)

            for check in checks {
                let paddedName = check.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
                print("  \(check.status) \(bold(paddedName))  \(check.detail)")
            }

            let failures = checks.filter { $0.status.contains("✗") }.count
            let warnings = checks.filter { $0.status.contains("!") }.count

            print()
            if failures == 0 && warnings == 0 {
                print(green("All checks passed."))
            } else {
                var parts: [String] = []
                if failures > 0 { parts.append(red("\(failures) error(s)")) }
                if warnings > 0 { parts.append(yellow("\(warnings) warning(s)")) }
                print(parts.joined(separator: ", "))
            }
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
