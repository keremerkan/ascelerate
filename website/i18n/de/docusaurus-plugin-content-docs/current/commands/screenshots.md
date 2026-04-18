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

### Rahmen

```bash
ascelerate screenshot frame                    # Frame screenshots with device bezels
```

Rahmt aufgenommene Screenshots mit Geräterahmen-Bildern. Verwendet die `frameDevice`- und `deviceBezel`-Einstellungen aus der Konfiguration. Kann nach der Aufnahme unabhängig ausgeführt werden.

### Diagnose

```bash
ascelerate screenshot doctor                   # Check config and environment
```

Überprüft die Screenshot-Konfiguration und Umgebung: Konfigurationsdatei, Projekt-/Workspace-Existenz, xcodebuild- und simctl-Verfügbarkeit, Simulatorgeräte, Helper-Dateiversion, Geräterahmen-Dateien und Ausgabeverzeichnisse. Zeigt eine Checkliste mit Bestanden/Fehlgeschlagen/Warnung-Indikatoren.

## Konfiguration (`ascelerate/screenshot.yml`)

```yaml
workspace: MyApp.xcworkspace
# project: MyApp.xcodeproj               # Use project instead of workspace
scheme: AppUITests
devices:
  - simulator: iPhone 17 Pro Max
    # frameDevice: true
    # deviceBezel: ./bezels/iPhone 17 Pro Max.png
  - simulator: iPad Pro 13-inch (M5)
    # frameDevice: true
    # deviceBezel: ./bezels/iPad Pro 13-inch (M5).png
languages:
  - en-US
  - de-DE
outputDirectory: ./screenshots
# framedOutputDirectory: ./screenshots/framed
clearPreviousScreenshots: true
eraseSimulator: false
localizeSimulator: true
overrideStatusBar: true
darkMode: false
disableAnimations: true
waitAfterBoot: 0
# waitAfterEraseAndReboot: 30           # Zusätzliches Warten auf Erstausführungs-Systemwarnungen (z. B. Apple Intelligence)
# statusBarArguments: "--time '9:41' --dataNetwork wifi"
# testWithoutBuilding: true               # Skip build, use existing xctestrun
# cleanBuild: false
# headless: false                         # Don't open Simulator.app
# helperPath: AppUITests/ScreenshotHelper.swift
# launchArguments:
#   - -ui_testing
# configuration: Debug                    # Build configuration
# testplan: MyTestPlan                    # Xcode test plan name
# numberOfRetries: 0                     # Retry failed languages (erase + reboot simulator)
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
4. Wenn `numberOfRetries` gesetzt ist und ein Gerät fehlschlägt: setzt fehlgeschlagene Simulatoren zurück, lokalisiert neu, startet neu und wiederholt die Tests
5. Sammelt Screenshots aus dem gerätespezifischen Cache ins Ausgabeverzeichnis
6. Rahmt Screenshots mit Geräterahmen (wenn `frameDevice` aktiviert ist)
7. Fehler werden übersprungen — Fehlerprotokolle werden in der Ausgabe gespeichert

## Ausgabe

```
screenshots/
├── en-US/
│   ├── iPhone 17 Pro Max-01-home.png
│   ├── iPhone 17 Pro Max-02-settings.png
│   └── iPad Pro 13-inch (M5)-01-home.png
└── de-DE/
    └── ...
```

## Geräterahmen

Rahmen Sie aufgenommene Screenshots mit Apple-Geräterahmen.

:::info
Geräterahmen sind nicht in ascelerate enthalten — laden Sie sie von [Apple Product Bezels](https://developer.apple.com/design/resources/#product-bezels) herunter (Apple Developer Account erforderlich). Der Download ist eine DMG-Datei mit PNG-Rahmen für alle aktuellen Geräte.
:::

### Einrichtung

1. Laden Sie die Product Bezels DMG von [Apple Design Resources](https://developer.apple.com/design/resources/#product-bezels) herunter
2. Extrahieren Sie die Rahmen-PNG-Dateien in einen Ordner in Ihrem Projekt (z.B. `./bezels/`)
3. Aktivieren Sie das Rahmen pro Gerät in der Konfiguration:

```yaml
devices:
  - simulator: iPhone 17 Pro Max
    frameDevice: true
    deviceBezel: ./bezels/iPhone 17 Pro Max.png
  - simulator: iPad Pro 13-inch (M5)
    frameDevice: false
```

### Ausgabe

Gerahmte Screenshots werden im `framedOutputDirectory` gespeichert (Standard: `{outputDirectory}/framed`):

```
screenshots/framed/
├── en-US/
│   └── iPhone 17 Pro Max-01-home.png
└── de-DE/
    └── ...
```

Nur Geräte mit `frameDevice: true` werden gerahmt. Das Rahmen erfolgt automatisch nach jeder Sprache während `screenshot run` oder eigenständig über `screenshot frame`.

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
| `waitAfterEraseAndReboot` | Zusätzliche Sekunden, wenn der Simulator in einem frischen Zustand ist — bei der ersten Sprache des Laufs oder wann immer der Simulator gelöscht wurde (über `eraseSimulator: true` oder einen Wiederholungsversuch). Gibt Erstausführungs-Systemwarnungen (z. B. "Apple Intelligence ist bereit") Zeit zu erscheinen, bevor Screenshots erstellt werden. |
| `testWithoutBuilding` | Build überspringen, vorhandene xctestrun-Datei verwenden |
| `cleanBuild` | `clean` vor dem Bauen ausführen |
| `headless` | Simulator.app nicht öffnen |
| `helperPath` | Pfad zu ScreenshotHelper.swift für Versionsprüfung |
| `launchArguments` | Zusätzliche Startargumente für die App |
| `configuration` | Build-Konfiguration (z.B. Debug, Release) |
| `testplan` | Name des Xcode-Testplans |
| `numberOfRetries` | Anzahl der Wiederholungsversuche bei fehlgeschlagenen Sprachen — setzt den Simulator zurück, lokalisiert neu, startet neu und führt Tests erneut aus. Nur fehlgeschlagene Geräte werden wiederholt. Wiederholte Ergebnisse werden in der Übersichtstabelle markiert. |
| `stopAfterFirstError` | Alle Geräte nach dem ersten Fehler stoppen |
| `reinstallApp` | App vor den Tests löschen und neu installieren |
| `xcargs` | Zusätzliche Argumente für `xcodebuild` |
| `frameDevice` | Geräterahmen für dieses Gerät aktivieren (pro Gerät) |
| `deviceBezel` | Pfad zur Geräterahmen-PNG-Datei (pro Gerät) |
| `framedOutputDirectory` | Ausgabeverzeichnis für gerahmte Screenshots (Standard: `{outputDirectory}/framed`) |
