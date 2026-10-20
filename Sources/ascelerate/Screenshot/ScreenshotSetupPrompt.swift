import Foundation

/// What a project folder already has for screenshot capture: the facts the setup prompts start
/// from, so an agent begins with what's done instead of rediscovering it.
struct ScreenshotProjectSurvey {
  /// Workspaces and projects, relative to the project root.
  var containers: [String] = []
  var schemes: [String] = []
  var uiTestTargets: [String] = []
  /// The localizations the Xcode projects declare (`knownRegions`, without Base).
  var localizations: [String] = []
  var config: ScreenshotConfig?
  var configError: String?
  var helperPath = ScreenshotCommand.defaultHelperPath
  /// Nil when the helper file is missing; empty when it has no version marker.
  var helperVersion: String?
  /// The installed simulators of the newest iOS version's runtimes.
  var simulators: [String] = []
  var hasCaptures = false
  /// Whether the design generator the `--design` prompt builds exists (`app-store-screenshots/`
  /// with a `package.json`), and whether it has exported images.
  var hasDesignGenerator = false
  var hasDesignExport = false

  static let designFolder = "app-store-screenshots"

  static func survey() -> ScreenshotProjectSurvey {
    var survey = ScreenshotProjectSurvey()
    let fm = FileManager.default
    survey.containers = findContainers()

    // Schemes from their files, shared and per user (`xcodebuild -list` takes seconds on a
    // workspace with packages).
    let projects = projectFiles(survey.containers)
    for container in survey.containers + projects.map { ($0 as NSString).deletingLastPathComponent } {
      for folder in ["\(container)/xcshareddata/xcschemes"] + userSchemeFolders(container) {
        let files = (try? fm.contentsOfDirectory(atPath: folder)) ?? []
        survey.schemes += files.filter { $0.hasSuffix(".xcscheme") }.map { ($0 as NSString).deletingPathExtension }.sorted()
      }
    }
    survey.schemes = unique(survey.schemes)

    // UI test targets and localizations, from every project file (a workspace's projects included).
    for pbxproj in projects {
      guard let text = try? String(contentsOfFile: pbxproj, encoding: .utf8) else { continue }
      survey.uiTestTargets += uiTestTargets(in: text)
      survey.localizations += knownRegions(in: text)
    }
    survey.uiTestTargets = unique(survey.uiTestTargets)
    survey.localizations = unique(survey.localizations)

    if fm.fileExists(atPath: ScreenshotCommand.configPath) {
      do {
        let config = try ScreenshotConfig.load(from: ScreenshotCommand.configPath)
        survey.config = config
        survey.helperPath = config.helperPath ?? ScreenshotCommand.defaultHelperPath
        survey.hasCaptures = containsPNG(config.outputDirectory)
      } catch {
        survey.configError = "\(error)"
      }
    }
    survey.helperVersion = ScreenshotCommand.CreateHelper.installedVersion(at: survey.helperPath)
    survey.hasDesignGenerator = fm.fileExists(atPath: "\(designFolder)/package.json")
    survey.hasDesignExport = containsPNG("\(designFolder)/export")
    survey.simulators = newestIOSSimulators()
    return survey
  }

  /// `.xcworkspace` and `.xcodeproj` folders in the project root and one level down, leaving out
  /// dependency and build folders and the workspace inside every project.
  private static func findContainers() -> [String] {
    let fm = FileManager.default
    let skipped: Set<String> = [".build", ".git", "Pods", "Carthage", "node_modules", "DerivedData", "build"]
    var found: [String] = []
    func scan(_ folder: String, depth: Int) {
      guard let entries = try? fm.contentsOfDirectory(atPath: folder.isEmpty ? "." : folder) else { return }
      for entry in entries.sorted() where !skipped.contains(entry) && !entry.hasPrefix(".") {
        let path = folder.isEmpty ? entry : "\(folder)/\(entry)"
        if entry.hasSuffix(".xcworkspace") || entry.hasSuffix(".xcodeproj") {
          found.append(path)
        } else if depth < 1 {
          var isDirectory: ObjCBool = false
          if fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            scan(path, depth: depth + 1)
          }
        }
      }
    }
    scan("", depth: 0)
    return found
  }

  private static func userSchemeFolders(_ container: String) -> [String] {
    let users = (try? FileManager.default.contentsOfDirectory(atPath: "\(container)/xcuserdata")) ?? []
    return users.map { "\(container)/xcuserdata/\($0)/xcschemes" }
  }

  /// The project files of the projects, and of the projects a workspace lists.
  private static func projectFiles(_ containers: [String]) -> [String] {
    var projects = containers.filter { $0.hasSuffix(".xcodeproj") }
    for workspace in containers where workspace.hasSuffix(".xcworkspace") {
      guard let data = try? String(contentsOfFile: "\(workspace)/contents.xcworkspacedata", encoding: .utf8) else { continue }
      let base = (workspace as NSString).deletingLastPathComponent
      for match in data.matches(of: /location\s*=\s*"group:([^"]+\.xcodeproj)"/) {
        let path = base.isEmpty ? String(match.1) : "\(base)/\(match.1)"
        projects.append((path as NSString).standardizingPath)
      }
    }
    return unique(projects).map { "\($0)/project.pbxproj" }
  }

  private static func uiTestTargets(in pbxproj: String) -> [String] {
    pbxproj.components(separatedBy: "isa = PBXNativeTarget;").dropFirst().compactMap { block in
      // A target's block ends at the next object; its name and product type come before that.
      let body = block.components(separatedBy: "};").first ?? block
      guard body.contains("com.apple.product-type.bundle.ui-testing"),
        let match = body.firstMatch(of: /\bname = "?([^";]+)"?;/)
      else { return nil }
      return String(match.1)
    }
  }

  private static func knownRegions(in pbxproj: String) -> [String] {
    guard let match = pbxproj.firstMatch(of: /knownRegions = \(([^)]*)\);/) else { return [] }
    return match.1.split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
      .filter { !$0.isEmpty && $0 != "Base" }
  }

  private static func newestIOSSimulators() -> [String] {
    guard let output = try? ScreenshotShell.run("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "available", "-j"]),
      let devices = jsonObject(in: output)?["devices"] as? [String: [[String: Any]]]
    else { return [] }
    // Runtime IDs end in the version (…SimRuntime.iOS-27-1); a new device can come with a point
    // release, so every runtime of the newest major version counts.
    func major(_ runtime: String) -> Int? {
      runtime.components(separatedBy: ".iOS-").last?.split(separator: "-").first.flatMap { Int($0) }
    }
    let runtimes = devices.keys.filter { $0.contains(".iOS-") }
    guard let newest = runtimes.compactMap(major).max() else { return [] }
    return unique(runtimes.filter { major($0) == newest }.sorted().flatMap { devices[$0] ?? [] }.compactMap { $0["name"] as? String })
  }

  private static func containsPNG(_ folder: String) -> Bool {
    guard let enumerator = FileManager.default.enumerator(atPath: folder) else { return false }
    while let path = enumerator.nextObject() as? String {
      if path.lowercased().hasSuffix(".png") { return true }
    }
    return false
  }

  /// The JSON object in tool output that may have warnings around it.
  private static func jsonObject(in output: String) -> [String: Any]? {
    guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}") else { return nil }
    return try? JSONSerialization.jsonObject(with: Data(output[start...end].utf8)) as? [String: Any]
  }

  private static func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }
}

/// The prompts `screenshot setup-prompt` prints for an AI coding agent: setting up capture in a
/// project, and building a screenshot design generator on top of it. They ship with the binary so
/// they always describe the helper and commands of this version.
enum ScreenshotSetupPrompt {
  static func capture(_ survey: ScreenshotProjectSurvey, root: String) -> String {
    let helperCurrent = ScreenshotCommand.CreateHelper.helperVersion
    let helperState: String
    switch survey.helperVersion {
      case nil: helperState = "missing (\(survey.helperPath))"
      case ""?: helperState = "\(survey.helperPath), no version marker: regenerate it"
      case let version? where version == helperCurrent: helperState = "\(survey.helperPath), current (v\(version))"
      case let version?: helperState = "\(survey.helperPath), v\(version): update it to v\(helperCurrent) with `ascelerate screenshot create-helper -o \(survey.helperPath) --yes`"
    }
    let configState: String
    if let config = survey.config {
      configState = "ascelerate/screenshot.yml (scheme \(config.scheme); devices \(config.devices.map(\.simulator).joined(separator: ", ")); languages \(config.languages.joined(separator: ", ")))"
    } else if let error = survey.configError {
      configState = "ascelerate/screenshot.yml doesn't parse: \(error)"
    } else {
      configState = "missing"
    }

    return """
      # Set up App Store screenshot capture

      You're setting up automated App Store screenshot capture for the iOS app in this folder. The ascelerate command-line tool (version \(Ascelerate.appVersion)) does the capturing: it boots the simulators, switches them to each language, runs the app's UI tests on every device and collects the screenshots the tests take. Your part is the project side: a UI test target, the screenshot helper, a screenshot mode in the app with demo content, the UI tests that walk to each screen, and the configuration.

      Work through the steps in order. Each step ends with a check: don't move on while it fails. Ask the user when a decision is theirs (which screens, what demo content) or when a step needs Xcode's interface.

      ## What's here already

      Detected in \(root) by `ascelerate screenshot setup-prompt`. Run it again later to see what's left.

      - Xcode workspaces and projects: \(list(survey.containers))
      - Schemes: \(list(survey.schemes))
      - UI test targets: \(list(survey.uiTestTargets))
      - Localizations: \(list(survey.localizations))
      - Screenshot configuration: \(configState)
      - Screenshot helper: \(helperState)
      - Simulators for the newest iOS version: \(list(survey.simulators))
      - Captured screenshots: \(survey.hasCaptures ? "yes, in the output folder" : "none yet")
      - Screenshot design generator: \(survey.hasDesignGenerator ? "\(ScreenshotProjectSurvey.designFolder)/" : "none")

      Steps already done: check them quickly and move on.

      ## Ground rules

      - Don't change how the app behaves for its users. Everything for screenshots runs only when the app was launched with the `-ASC_SCREENSHOT` argument, which the helper adds.
      - Screenshots must not depend on the network, the current date, an account or anything else on the simulator: in screenshot mode the app shows built-in demo content.
      - Follow the project's code style. Commit nothing unless the user asks.
      - Use the ascelerate commands named here instead of writing their files by hand. `ascelerate screenshot --help` and `ascelerate screenshot <subcommand> --help` describe them.

      ## 1. UI test target

      The screenshots are taken by UI tests, which need a UI Testing Bundle target. If the project has none, ask the user to add it in Xcode, which edits the project file reliably: File → New → Target…, iOS, UI Testing Bundle, named after the app with a `UITests` suffix, with the app as the target to be tested. Edit `project.pbxproj` yourself only if the user asks you to.

      A scheme must build the app and run that target in its Test action: the app's own scheme, or one of its own for screenshots. That scheme goes in the configuration.

      Check: `xcodebuild -list -project <project>` lists the target, and the scheme's Test action includes it.

      ## 2. Configuration

      In the project root, run `ascelerate screenshot init --yes`. It creates `ascelerate/screenshot.yml` and `ascelerate/ScreenshotHelper.swift`, and leaves either alone if it already exists. Then edit `ascelerate/screenshot.yml`:

      - `workspace` or `project` (relative to the project root), and `scheme` from step 1.
      - `devices`: one simulator per screenshot size the App Store needs, named exactly as `xcrun simctl list devices available` shows them: the largest iPhone (6.9" display, such as an iPhone Pro Max) and, if the app runs on iPad, a 13" iPad. Use installed simulators (above); if one is missing, ask the user to add it in Xcode (Window → Devices and Simulators).
      - `languages`: the App Store languages to capture, as language codes the simulator understands (`en-US`, `de-DE`, `tr`, `ja`…), usually one per App Store localization. If the app's localizations (above) and its App Store languages may differ, ask the user.
      - `helperPath`: where the helper goes in step 3, so `ascelerate screenshot doctor` can check its version.

      Leave the other settings as they are unless a later step needs them; the comments in the file explain each one.

      Check: `ascelerate screenshot doctor` reports no errors (✗).

      ## 3. Screenshot helper

      Move `ascelerate/ScreenshotHelper.swift` into the UI test target's folder and make it part of that target. With Xcode's folder-synchronized groups (the default since Xcode 16) placing it in the target's folder is enough; with classic groups, add it to the target, or ask the user to. Set `helperPath` to the new path. Don't edit the helper: `ascelerate screenshot create-helper` regenerates it when ascelerate updates it.

      The helper gives the tests:

      - `setupScreenshots(app)`: call it before `app.launch()`. It passes the simulator's language and region to the app, plus `-ASC_SCREENSHOT YES`, `-ui_testing` and the configuration's `launchArguments`.
      - `screenshot("01_Home")`: saves a screenshot of the app's window under that name. Number the names: screenshots are uploaded in name order.
      - `setHinge(.open)` / `setHinge(.closed)`: unfolds or folds the iPhone Duo simulator; does nothing on other devices.

      Check: the UI test target builds, e.g. `xcodebuild build-for-testing -scheme <scheme> -destination 'generic/platform=iOS Simulator'` with `-workspace` or `-project`.

      ## 4. Screenshot mode in the app

      When the app was launched with `-ASC_SCREENSHOT` (`ProcessInfo.processInfo.arguments.contains("-ASC_SCREENSHOT")`), it should:

      - Show demo content that shows the app at its best: realistic, varied, and in the simulator's language (localize the demo text like the rest of the app). Reuse existing preview or sample data if the project has some. If the right content isn't obvious, ask the user.
      - Skip onboarding, sign-in, what's-new screens, rating prompts, tips and permission requests, and anything that waits for the network.
      - Keep dates and numbers stable: a fixed "now" if the interface shows relative dates.

      Keep this in as few places as possible: one check at launch and one source of demo data.

      If animations make the screenshots flaky, set `disableAnimations: true` in the configuration: the app is then launched with `-ASC_DISABLE_ANIMATIONS`, and the helper's file shows a `disableAnimationsIfNeeded()` for the app to call at launch.

      ## 5. UI tests

      Ask the user which screens to show and in which order: usually 5 to 10, the most important first. Then write a test class (for example `ScreenshotTests`) with one test that calls `setupScreenshots(app)`, launches the app once, goes to each screen and calls `screenshot("NN_name")`:

      - Find elements by accessibility identifiers you add to the app (`.accessibilityIdentifier("…")`), never by their visible text: the text changes with the language.
      - Before each screenshot, wait for the content with `waitForExistence(timeout:)`, not with fixed sleeps.
      - For the iPad, landscape screens or the iPhone Duo, branch on the device (`UIDevice.current.userInterfaceIdiom`, or `ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]`, which is `iPhone19,4` for the iPhone Duo) and set `XCUIDevice.shared.orientation` or the hinge before the screens that need it.
      - The capture runs the scheme's tests: leave other tests out of it (a scheme or a test plan of its own, `testplan` in the configuration).

      Check: run the test once on one simulator and fix what fails: `xcodebuild test` with the scheme, `-destination 'platform=iOS Simulator,name=<simulator>'` and `-only-testing:<UI test target>/ScreenshotTests`.

      ## 6. First capture

      Run `ascelerate screenshot --languages <one language>`. It builds the tests once, then runs them on every configured simulator. Look at the PNG files in the output folder (`outputDirectory`, one folder per language, each file named after its simulator and screenshot): every screen there, the right content, nothing cut off, no system alerts, keyboard or loading indicators. Fix and run it again. A simulator that failed leaves `<simulator>-error.log` in the language's folder.

      When one language looks right, run them all with `ascelerate screenshot`. It takes a while: each language boots the simulators again. Check that longer translations still fit.

      ## 7. Device frames (optional)

      Ask the user whether they want the screenshots in real device frames too, for marketing images or the design generator below. If they do:

      - Point them to Apple's device frames, the "Product Bezels" on developer.apple.com/design/resources. They download them there themselves, accepting Apple's terms; don't download them for them. Suggest keeping them in one folder outside the project that all their apps can share (paths may start with `~`).
      - For each simulator, pick the frame of the same model, in the orientation its screenshots are taken in (a landscape iPad frame for landscape iPad screenshots). Any color the user likes.
      - In `ascelerate/screenshot.yml`, set `frameDevice: true` and `deviceBezel` for each device. A device whose screenshots come in more than one shape takes a list of frames, and each screenshot gets the one that fits it: the iPhone Duo's folded and unfolded frames, for example.

      Check: `ascelerate screenshot frame` frames every screenshot (framed copies go to `framedOutputDirectory`, by default `framed/` in the output folder), and the framed images show each screenshot exactly inside the frame's screen.

      ## Afterwards

      Tell the user what you set up, which screens the tests capture, how to capture again (`ascelerate screenshot`, or the Screenshots page of the ascelerate app), and anything left for them.

      \(survey.hasDesignGenerator
        ? "The project has a design generator in `\(ScreenshotProjectSurvey.designFolder)/`: remind the user to frame (`ascelerate screenshot frame`), refresh its copies of the framed screenshots and export again after each capture."
        : "Optional next step to mention: `ascelerate screenshot setup-prompt --design` prints the prompt for a small web app that turns the framed screenshots into App Store images with headlines in every language, and exports them in the folder layout `ascelerate apps media upload` takes.")

      """
  }

  static func design(_ survey: ScreenshotProjectSurvey, root: String) -> String {
    let captureState: String
    if let config = survey.config {
      let framed = config.devices.filter { $0.frameDevice == true }.map(\.simulator)
      captureState = """
        - Screenshot configuration: ascelerate/screenshot.yml (devices \(config.devices.map(\.simulator).joined(separator: ", ")); languages \(config.languages.joined(separator: ", ")); output \(config.outputDirectory))
        - Framing: \(framed.isEmpty ? "not set up" : "set up for \(framed.joined(separator: ", "))"), framed copies in \(config.framedOutputDirectory ?? "\(config.outputDirectory)/framed")
        - Captured screenshots: \(survey.hasCaptures ? "yes" : "none yet")
        """
    } else {
      captureState = "- Screenshot capture isn't set up yet (no ascelerate/screenshot.yml). Set it up first with the prompt `ascelerate screenshot setup-prompt` prints."
    }
    let designState =
      survey.hasDesignGenerator
      ? "- Design generator: `\(ScreenshotProjectSurvey.designFolder)/` exists\(survey.hasDesignExport ? ", with exported images" : ", nothing exported yet"). Work on it rather than starting a new one: read it first, then go through the steps below and do what's missing or different."
      : "- Design generator: none yet."

    return """
      # Build App Store screenshot designs

      You're building a small web app that turns this app's captured screenshots into its App Store images: each screenshot in its device frame on a designed background with a headline, in every language, at the exact sizes App Store Connect takes, exported into the folder layout the ascelerate command-line tool (version \(Ascelerate.appVersion)) uploads.

      ## What's here already

      Detected in \(root) by `ascelerate screenshot setup-prompt --design`. Run it again after changing the capture setup (framing, for example) to see the current state.

      \(captureState)
      \(designState)

      ## Ground rules

      - Put the web app in its own folder in the project, `\(ScreenshotProjectSurvey.designFolder)/` (that name lets ascelerate and the ascelerate app find it), apart from the app's code.
      - Screenshots are advertisements, not documentation. Each slide sells one idea: a feeling, an outcome, or a problem gone. Showing the interface for its own sake is the most common mistake.
      - Get the copy approved before building the layouts, and show the user the first finished slide before doing the rest.
      - Commit nothing unless the user asks.

      ## Questions first

      Before writing code, ask the user these one at a time, waiting for each answer (skip what they've already told you):

      1. The app icon (a PNG).
      2. Brand colors: accent, text, light or dark backgrounds.
      3. The font, the app's own or another.
      4. The app's features in priority order: what's the most important thing it does?
      5. How many slides (up to 10; the first one or two are all most people see).
      6. The style: warm, dark, minimal, bold, gradient-heavy…, and App Store screenshots they like.
      7. Optionally: images of interface pieces (cards, widgets) to float around the devices, and anything else they want.

      Decide the rest yourself from the answers: backgrounds, decorations, which slides are dark, the typography and the secondary colors.

      ## Plan and copy

      A proven order (adapt it to the slide count): the main benefit with the app icon first; then what sets the app apart; widgets or other extensions if it has them; then one core feature per slide, most important first; something about who the app is made for near the end; and a last slide listing more features as short pills.

      Write the headlines before the layouts:

      - One idea per headline: never two things joined with "and".
      - Short, common words, 3 to 5 per line, readable at thumbnail size; place the line breaks deliberately.
      - Write each one as a moment ("Check your coffee without opening the app"), an outcome ("A home for every coffee you buy") or a pain removed ("Never waste a great bag of coffee").
      - Never a feature list, a vague slogan ("Every item, tracked") or a buzzword the app doesn't earn.
      - Offer three options per slide with your reasoning, and let the user choose. Then write each language as a native speaker would, not word for word, in that language's usual tone; longer languages (German, French) may need other line breaks.

      ## Layout

      - Vary the layout from slide to slide: a centered device, two overlapping devices, a device off to one side, a slide with no device. Mix light and dark slides; prefer gradients to flat backgrounds.
      - Keep space between the device and the canvas edges: a device touching the edge looks cramped.
      - Size text from the canvas width (labels about 3% of it, headlines 9–10%, bold, tight line height).
      - On the iPad's wider canvas, make the device narrower (about 70–78% of the width, not 82–86%) and put the headline above it.
      - Shadow the device images with `filter: drop-shadow()`, which follows the frame's shape, not `box-shadow`, which draws a rectangle.

      ## 1. Framed screenshots

      The designs show the screenshots in real device frames. If framing isn't set up yet, point the user to Apple's device frames, the "Product Bezels" on developer.apple.com/design/resources: they download them there themselves, accepting Apple's terms; don't download them for them. Suggest one folder outside the project that all their apps can share. Then, in `ascelerate/screenshot.yml`, set `frameDevice: true` and `deviceBezel` for each device: the frame of the same model, in the orientation of its screenshots (a list of frames picks the one that fits each screenshot, such as an iPhone Duo's folded and unfolded frames). Run `ascelerate screenshot frame` after each capture. The framed files land in `framedOutputDirectory` (by default `framed/` in the output folder), one folder per language. The web app reads them from its `public/` folder: add a small script that copies them there, run after each capture.

      Check: framed PNGs exist for every language and device.

      ## 2. The web app

      Use Next.js with React and TypeScript, and the package manager the user has (npm, pnpm or bun). Next.js changes its APIs between major versions: read the documentation of the installed version before writing code.

      - One page shows every slide of a device and language at its real pixel size, scaled down into a preview grid, with pickers for the device and language.
      - Each slide is a React component that receives the canvas width and height. Size and place everything as fractions of the canvas, never in fixed pixels, so one design serves every device.
      - The copy lives in JSON, by language and slide.
      - A query string mode (`?slide=<device>-<name>&locale=<code>`) renders one slide alone at full size in the top left corner, with nothing else on the page, for the export.

      Canvas sizes App Store Connect takes (portrait; swap them for landscape), with the folder each goes in:

      - iPhone 6.9": 1320×2868, `APP_IPHONE_67`
      - iPad 13": 2064×2752, `APP_IPAD_PRO_3GEN_129`
      - iPhone Duo: unfolded 2007×2853, folded 1398×2034, `APP_IPHONE_DUO`
      - Mac: 2880×1800, `APP_DESKTOP`

      Check: the preview shows every slide of every language without overflowing text; look at the longest translations.

      ## 3. Export

      Write a script that renders every slide through the single-slide mode while the development server runs, with headless Chrome (`--headless=new --screenshot=<file> --window-size=<width>,<height> --force-device-scale-factor=1 --hide-scrollbars`, plus a `--virtual-time-budget` so fonts and images finish loading). It writes

      `export/<locale>/<folder>/NN_name.png`, for example `export/en-US/APP_IPHONE_67/01_home.png`

      which is the layout `ascelerate apps media upload <bundle ID> export --platform ios --replace` uploads. The locale folders use App Store Connect's codes (`en-US`, `de-DE`, `tr`, `ja`…). For an app on more than one platform, export each platform to its own folder (`export/ios`, `export/macos`) and upload each with its `--platform`: without it, ascelerate asks which platform's version to use. Delete a slide's previous file before rendering it and retry a failed render once, so a failure never leaves an old image behind.

      Check: every exported image has its canvas's exact size, and `ascelerate apps media upload <bundle ID> export --platform ios --dry-run --yes` lists every file without errors (`--dry-run` sends nothing; `--yes` makes ascelerate stop with an error instead of waiting for an answer).

      ## Afterwards

      Tell the user how to change the copy and the design, how to export again, and how to upload: `ascelerate apps media upload <bundle ID> export --platform ios --replace`, or the ascelerate app.

      """
  }

  private static func list(_ values: [String]) -> String {
    values.isEmpty ? "none found" : values.joined(separator: ", ")
  }
}
