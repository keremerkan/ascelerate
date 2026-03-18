---
sidebar_position: 12
title: Capturing Screenshots
---

# Capturing Screenshots

Capture App Store screenshots directly from iOS/iPadOS simulators using UI tests. Replaces [fastlane snapshot](https://docs.fastlane.tools/actions/snapshot/).

## Quick start

```bash
ascelerate screenshot init                  # Create config and helper in ascelerate/
ascelerate screenshot                       # Capture screenshots
```

## Commands

### Run

```bash
ascelerate screenshot                       # Capture screenshots
ascelerate screenshot run                   # Same as above
```

Always uses `ascelerate/screenshot.yml` in the current directory.

### Init

```bash
ascelerate screenshot init
```

Creates both `ascelerate/screenshot.yml` and `ascelerate/ScreenshotHelper.swift` in the `ascelerate/` directory. Prompts for confirmation before writing. Won't overwrite existing files.

### Create helper

```bash
ascelerate screenshot create-helper         # Generates ScreenshotHelper.swift
ascelerate screenshot create-helper -o CustomHelper.swift
```

## Config (`ascelerate/screenshot.yml`)

```yaml
workspace: MyApp.xcworkspace
# project: MyApp.xcodeproj               # Use project instead of workspace
scheme: AppUITests
devices:
  - simulator: iPhone 16 Pro Max
  - simulator: iPad Pro 13-inch (M4)
languages:
  - en-US
  - de-DE
outputDirectory: ./screenshots
clearPreviousScreenshots: true
eraseSimulator: false
localizeSimulator: true
overrideStatusBar: true
darkMode: false
disableAnimations: true
waitAfterBoot: 0
# statusBarArguments: "--time '9:41' --dataNetwork wifi"
# testWithoutBuilding: true               # Skip build, use existing xctestrun
# cleanBuild: false
# headless: false                         # Don't open Simulator.app
# helperPath: AppUITests/ScreenshotHelper.swift
# launchArguments:
#   - -ui_testing
# configuration: Debug                    # Build configuration
# testplan: MyTestPlan                    # Xcode test plan name
# numberOfRetries: 0                     # Retry failed tests
# stopAfterFirstError: false             # Stop all devices on first failure
# reinstallApp: false                    # Delete and reinstall app before tests
# xcargs: SWIFT_ACTIVE_COMPILATION_CONDITIONS=SCREENSHOTS
```

## UITest usage

Add `ScreenshotHelper.swift` to your UITest target:

```swift
override func setUp() {
    setupScreenshots(app)
    app.launch()
}

func testScreenshots() {
    screenshot("01-home")
    app.buttons["Settings"].tap()
    screenshot("02-settings")
}
```

Your app can detect screenshot mode via:

```swift
if ProcessInfo.processInfo.arguments.contains("-ASC_SCREENSHOT") {
    // Show demo data, hide debug UI, etc.
}
```

The helper also provides `disableAnimationsIfNeeded()` to turn off animations when `disableAnimations` is enabled in the config:

```swift
override func setUp() {
    setupScreenshots(app)
    disableAnimationsIfNeeded()
    app.launch()
}
```

## How it works

1. Builds once with `build-for-testing` (or skips if `testWithoutBuilding: true`)
2. For each language: boots all simulators, localizes, overrides status bar
3. Runs tests concurrently across devices
4. Collects screenshots from per-device cache to output directory
5. Errors skip and continue — error logs saved to output

## Output

```
screenshots/
├── en-US/
│   ├── iPhone 16 Pro Max-01-home.png
│   ├── iPhone 16 Pro Max-02-settings.png
│   └── iPad Pro 13-inch (M4)-01-home.png
└── de-DE/
    └── ...
```

## Options

| Option | Description |
|---|---|
| `clearPreviousScreenshots` | Clear language folder before collecting (only if all devices succeed) |
| `eraseSimulator` | Erase simulator before each language |
| `localizeSimulator` | Set simulator language/locale per language |
| `overrideStatusBar` | Override status bar (9:41, full bars, Wi-Fi) |
| `statusBarArguments` | Custom `xcrun simctl status_bar` arguments |
| `darkMode` | Enable dark mode on simulators |
| `disableAnimations` | Disable animations during tests |
| `waitAfterBoot` | Seconds to wait after simulator boot (default: 0) |
| `testWithoutBuilding` | Skip build, use existing xctestrun file |
| `cleanBuild` | Run `clean` before building |
| `headless` | Don't open Simulator.app |
| `helperPath` | Path to ScreenshotHelper.swift for version checking |
| `launchArguments` | Extra launch arguments passed to the app |
| `configuration` | Build configuration (e.g. Debug, Release) |
| `testplan` | Xcode test plan name |
| `numberOfRetries` | Number of times to retry failed tests |
| `stopAfterFirstError` | Stop all devices after the first failure |
| `reinstallApp` | Delete and reinstall the app before running tests |
| `xcargs` | Extra arguments passed to `xcodebuild` |
