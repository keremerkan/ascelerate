---
sidebar_position: 12
title: Screenshots aufnehmen
---

# Screenshots aufnehmen

Erfassen Sie App Store Screenshots direkt von iOS/iPadOS-Simulatoren mithilfe von UI-Tests. Ersetzt [fastlane snapshot](https://docs.fastlane.tools/actions/snapshot/).

## Schnellstart

```bash
ascelerate screenshot init                  # Create config and helper in ascelerate/
ascelerate screenshot                       # Capture screenshots
```

## Befehle

### Ausführen

```bash
ascelerate screenshot                       # Capture screenshots
ascelerate screenshot run                   # Same as above
```

Verwendet immer `ascelerate/screenshot.yml` im aktuellen Verzeichnis.

### Initialisieren

```bash
ascelerate screenshot init
```

Erstellt sowohl `ascelerate/screenshot.yml` als auch `ascelerate/ScreenshotHelper.swift` im Verzeichnis `ascelerate/`. Fragt vor dem Schreiben um Bestätigung. Überschreibt keine bestehenden Dateien.

### Helper erstellen

```bash
ascelerate screenshot create-helper         # Generates ScreenshotHelper.swift
ascelerate screenshot create-helper -o CustomHelper.swift
```

## Konfiguration (`ascelerate/screenshot.yml`)

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

## Verwendung in UITests

Fügen Sie `ScreenshotHelper.swift` zu Ihrem UITest-Target hinzu:

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

Ihre App kann den Screenshot-Modus erkennen:

```swift
if ProcessInfo.processInfo.arguments.contains("-ASC_SCREENSHOT") {
    // Show demo data, hide debug UI, etc.
}
```

Der Helper bietet auch `disableAnimationsIfNeeded()`, um Animationen zu deaktivieren, wenn `disableAnimations` in der Konfiguration aktiviert ist:

```swift
override func setUp() {
    setupScreenshots(app)
    disableAnimationsIfNeeded()
    app.launch()
}
```

## Funktionsweise

1. Baut einmal mit `build-for-testing` (oder überspringt, wenn `testWithoutBuilding: true`)
2. Für jede Sprache: startet alle Simulatoren, lokalisiert, überschreibt die Statusleiste
3. Führt Tests parallel auf allen Geräten aus
4. Sammelt Screenshots aus dem gerätespezifischen Cache ins Ausgabeverzeichnis
5. Fehler werden übersprungen — Fehlerprotokolle werden in der Ausgabe gespeichert

## Ausgabe

```
screenshots/
├── en-US/
│   ├── iPhone 16 Pro Max-01-home.png
│   ├── iPhone 16 Pro Max-02-settings.png
│   └── iPad Pro 13-inch (M4)-01-home.png
└── de-DE/
    └── ...
```

## Optionen

| Option | Beschreibung |
|---|---|
| `clearPreviousScreenshots` | Sprachordner vor dem Sammeln leeren (nur wenn alle Geräte erfolgreich sind) |
| `eraseSimulator` | Simulator vor jeder Sprache zurücksetzen |
| `localizeSimulator` | Simulator-Sprache/-Locale pro Sprache setzen |
| `overrideStatusBar` | Statusleiste überschreiben (9:41, volle Balken, WLAN) |
| `statusBarArguments` | Benutzerdefinierte `xcrun simctl status_bar`-Argumente |
| `darkMode` | Dunkelmodus auf Simulatoren aktivieren |
| `disableAnimations` | Animationen während Tests deaktivieren |
| `waitAfterBoot` | Sekunden nach dem Simulatorstart warten (Standard: 0) |
| `testWithoutBuilding` | Build überspringen, vorhandene xctestrun-Datei verwenden |
| `cleanBuild` | `clean` vor dem Bauen ausführen |
| `headless` | Simulator.app nicht öffnen |
| `helperPath` | Pfad zu ScreenshotHelper.swift für Versionsprüfung |
| `launchArguments` | Zusätzliche Startargumente für die App |
| `configuration` | Build-Konfiguration (z.B. Debug, Release) |
| `testplan` | Name des Xcode-Testplans |
| `numberOfRetries` | Anzahl der Wiederholungsversuche bei fehlgeschlagenen Tests |
| `stopAfterFirstError` | Alle Geräte nach dem ersten Fehler stoppen |
| `reinstallApp` | App vor den Tests löschen und neu installieren |
| `xcargs` | Zusätzliche Argumente für `xcodebuild` |
