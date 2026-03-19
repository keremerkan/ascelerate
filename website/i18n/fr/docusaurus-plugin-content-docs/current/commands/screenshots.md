---
sidebar_position: 12
title: Capture d'écran
---

# Capture d'écran

Capturez des screenshots App Store directement depuis les simulateurs iOS/iPadOS via des tests UI. Remplace [fastlane snapshot](https://docs.fastlane.tools/actions/snapshot/).

## Démarrage rapide

```bash
ascelerate screenshot init                  # Create config and helper in ascelerate/
ascelerate screenshot                       # Capture screenshots
```

## Commandes

### Exécuter

```bash
ascelerate screenshot                       # Capture screenshots
ascelerate screenshot run                   # Same as above
```

Utilise toujours `ascelerate/screenshot.yml` dans le répertoire courant.

### Initialiser

```bash
ascelerate screenshot init
```

Crée `ascelerate/screenshot.yml` et `ascelerate/ScreenshotHelper.swift` dans le répertoire `ascelerate/`. Demande confirmation avant l'écriture. Ne remplace pas les fichiers existants.

### Créer le helper

```bash
ascelerate screenshot create-helper         # Generates ScreenshotHelper.swift
ascelerate screenshot create-helper -o CustomHelper.swift
```

### Encadrement

```bash
ascelerate screenshot frame                    # Frame screenshots with device bezels
```

Encadre les captures d'écran avec des contours d'appareil. Utilise les paramètres `frameDevice` et `deviceBezel` de la configuration. Peut être exécuté indépendamment après la capture.

### Diagnostic

```bash
ascelerate screenshot doctor                   # Check config and environment
```

Vérifie la configuration et l'environnement : fichier de configuration, existence du projet/workspace, disponibilité de xcodebuild et simctl, simulateurs, version du fichier helper, fichiers de contour d'appareil et répertoires de sortie. Affiche une liste de contrôle avec des indicateurs de réussite/échec/avertissement.

## Configuration (`ascelerate/screenshot.yml`)

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

## Utilisation dans les UITests

Ajoutez `ScreenshotHelper.swift` à votre cible UITest :

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

Votre application peut détecter le mode screenshot :

```swift
if ProcessInfo.processInfo.arguments.contains("-ASC_SCREENSHOT") {
    // Show demo data, hide debug UI, etc.
}
```

Le helper fournit également `disableAnimationsIfNeeded()` pour désactiver les animations lorsque `disableAnimations` est activé dans la configuration :

```swift
override func setUp() {
    setupScreenshots(app)
    disableAnimationsIfNeeded()
    app.launch()
}
```

## Fonctionnement

1. Build unique avec `build-for-testing` (ou ignoré si `testWithoutBuilding: true`)
2. Pour chaque langue : démarre tous les simulateurs, localise, remplace la barre d'état
3. Exécute les tests en parallèle sur tous les appareils
4. Collecte les screenshots du cache par appareil vers le répertoire de sortie
5. Encadre les captures d'écran avec des contours d'appareil (si `frameDevice` est activé)
6. Les erreurs sont ignorées et le processus continue — les logs d'erreur sont enregistrés dans la sortie

## Sortie

```
screenshots/
├── en-US/
│   ├── iPhone 17 Pro Max-01-home.png
│   ├── iPhone 17 Pro Max-02-settings.png
│   └── iPad Pro 13-inch (M5)-01-home.png
└── de-DE/
    └── ...
```

## Encadrement d'appareil

Encadrez les captures d'écran avec les contours d'appareils Apple depuis [Apple Design Resources](https://developer.apple.com/design/resources/).

### Configuration

1. Téléchargez les contours d'appareils depuis Apple Design Resources (fichier DMG)
2. Extrayez les fichiers PNG de contour dans un dossier de votre projet (ex. `./bezels/`)
3. Activez l'encadrement par appareil dans la configuration :

```yaml
devices:
  - simulator: iPhone 17 Pro Max
    frameDevice: true
    deviceBezel: ./bezels/iPhone 17 Pro Max.png
  - simulator: iPad Pro 13-inch (M5)
    frameDevice: false
```

### Sortie

Les captures d'écran encadrées sont enregistrées dans `framedOutputDirectory` (par défaut : `{outputDirectory}/framed`) :

```
screenshots/framed/
├── en-US/
│   └── iPhone 17 Pro Max-01-home.png
└── de-DE/
    └── ...
```

Seuls les appareils avec `frameDevice: true` sont encadrés. L'encadrement s'exécute automatiquement après chaque langue pendant `screenshot run`, ou de manière autonome via `screenshot frame`.

## Options

| Option | Description |
|---|---|
| `clearPreviousScreenshots` | Vider le dossier de langue avant la collecte (uniquement si tous les appareils réussissent) |
| `eraseSimulator` | Réinitialiser le simulateur avant chaque langue |
| `localizeSimulator` | Définir la langue/locale du simulateur par langue |
| `overrideStatusBar` | Remplacer la barre d'état (9:41, barres pleines, Wi-Fi) |
| `statusBarArguments` | Arguments personnalisés pour `xcrun simctl status_bar` |
| `darkMode` | Activer le mode sombre sur les simulateurs |
| `disableAnimations` | Désactiver les animations pendant les tests |
| `waitAfterBoot` | Secondes d'attente après le démarrage du simulateur (défaut : 0) |
| `testWithoutBuilding` | Ignorer le build, utiliser le fichier xctestrun existant |
| `cleanBuild` | Exécuter `clean` avant le build |
| `headless` | Ne pas ouvrir Simulator.app |
| `helperPath` | Chemin vers ScreenshotHelper.swift pour la vérification de version |
| `launchArguments` | Arguments de lancement supplémentaires passés à l'application |
| `configuration` | Configuration de build (ex. Debug, Release) |
| `testplan` | Nom du plan de test Xcode |
| `numberOfRetries` | Nombre de tentatives pour les tests échoués |
| `stopAfterFirstError` | Arrêter tous les appareils après le premier échec |
| `reinstallApp` | Supprimer et réinstaller l'application avant les tests |
| `xcargs` | Arguments supplémentaires passés à `xcodebuild` |
| `frameDevice` | Activer l'encadrement pour cet appareil (par appareil) |
| `deviceBezel` | Chemin vers le fichier PNG de contour d'appareil (par appareil) |
| `framedOutputDirectory` | Répertoire de sortie pour les captures encadrées (défaut : `{outputDirectory}/framed`) |
