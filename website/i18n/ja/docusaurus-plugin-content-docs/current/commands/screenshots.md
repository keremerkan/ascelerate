---
sidebar_position: 12
title: スクリーンショット撮影
---

# スクリーンショット撮影

UIテストを使用してiOS/iPadOSシミュレーターからApp Storeのスクリーンショットを直接キャプチャします。[fastlane snapshot](https://docs.fastlane.tools/actions/snapshot/)の代替です。

## クイックスタート

```bash
ascelerate screenshot init                  # Create config and helper in ascelerate/
ascelerate screenshot                       # Capture screenshots
```

## コマンド

### 実行

```bash
ascelerate screenshot                       # Capture screenshots
ascelerate screenshot run                   # Same as above
```

常にカレントディレクトリの `ascelerate/screenshot.yml` を使用します。

### 初期化

```bash
ascelerate screenshot init
```

`ascelerate/` ディレクトリに `ascelerate/screenshot.yml` と `ascelerate/ScreenshotHelper.swift` の両方を作成します。書き込み前に確認を求めます。既存のファイルは上書きしません。

### ヘルパー作成

```bash
ascelerate screenshot create-helper         # Generates ScreenshotHelper.swift
ascelerate screenshot create-helper -o CustomHelper.swift
```

### フレーミング

```bash
ascelerate screenshot frame                    # Frame screenshots with device bezels
```

キャプチャしたスクリーンショットをデバイスベゼル画像でフレーミングします。設定の `frameDevice` と `deviceBezel` を使用します。スクリーンショットのキャプチャ後に独立して実行できます。

### ドクター

```bash
ascelerate screenshot doctor                   # Check config and environment
```

スクリーンショットの設定と環境を検証します：設定ファイル、プロジェクト/ワークスペースの存在、xcodebuildとsimctlの利用可能性、シミュレーターデバイス、ヘルパーファイルのバージョン、デバイスベゼルファイル、出力ディレクトリをチェックします。合格/不合格/警告のインジケーター付きチェックリストを表示します。

## 設定（`ascelerate/screenshot.yml`）

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

## UIテストでの使用方法

`ScreenshotHelper.swift` をUITestターゲットに追加します：

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

アプリ側でスクリーンショットモードを検出できます：

```swift
if ProcessInfo.processInfo.arguments.contains("-ASC_SCREENSHOT") {
    // Show demo data, hide debug UI, etc.
}
```

ヘルパーは `disableAnimationsIfNeeded()` 関数も提供しており、設定で `disableAnimations` が有効な場合にアニメーションを無効化できます：

```swift
override func setUp() {
    setupScreenshots(app)
    disableAnimationsIfNeeded()
    app.launch()
}
```

## 動作の仕組み

1. `build-for-testing` で一度ビルド（`testWithoutBuilding: true` の場合はスキップ）
2. 各言語ごとに：すべてのシミュレーターを起動、ローカライズ、ステータスバーをオーバーライド
3. 全デバイスで並行してテストを実行
4. デバイスごとのキャッシュから出力ディレクトリにスクリーンショットを収集
5. デバイスベゼルでスクリーンショットをフレーミング（`frameDevice` が有効な場合）
6. エラーはスキップして続行 — エラーログは出力に保存

## 出力

```
screenshots/
├── en-US/
│   ├── iPhone 17 Pro Max-01-home.png
│   ├── iPhone 17 Pro Max-02-settings.png
│   └── iPad Pro 13-inch (M5)-01-home.png
└── de-DE/
    └── ...
```

## デバイスフレーミング

[Apple Design Resources](https://developer.apple.com/design/resources/)のAppleデバイスベゼルを使用して、キャプチャしたスクリーンショットをフレーミングします。

### セットアップ

1. Apple Design Resourcesからデバイスベゼルをダウンロード（DMGファイル）
2. ベゼルPNGファイルをプロジェクト内のフォルダに展開（例：`./bezels/`）
3. 設定でデバイスごとにフレーミングを有効化：

```yaml
devices:
  - simulator: iPhone 17 Pro Max
    frameDevice: true
    deviceBezel: ./bezels/iPhone 17 Pro Max.png
  - simulator: iPad Pro 13-inch (M5)
    frameDevice: false
```

### 出力

フレーミングされたスクリーンショットは `framedOutputDirectory` に保存されます（デフォルト：`{outputDirectory}/framed`）：

```
screenshots/framed/
├── en-US/
│   └── iPhone 17 Pro Max-01-home.png
└── de-DE/
    └── ...
```

`frameDevice: true` のデバイスのみがフレーミングされます。フレーミングは `screenshot run` 中に各言語の後で自動的に実行されるか、`screenshot frame` で独立して実行できます。

## オプション

| オプション | 説明 |
|---|---|
| `clearPreviousScreenshots` | 収集前に言語フォルダをクリア（すべてのデバイスが成功した場合のみ） |
| `eraseSimulator` | 各言語の前にシミュレーターをリセット |
| `localizeSimulator` | 言語ごとにシミュレーターの言語/ロケールを設定 |
| `overrideStatusBar` | ステータスバーをオーバーライド（9:41、フルバー、Wi-Fi） |
| `statusBarArguments` | `xcrun simctl status_bar` のカスタム引数 |
| `darkMode` | シミュレーターでダークモードを有効化 |
| `disableAnimations` | テスト中のアニメーションを無効化 |
| `waitAfterBoot` | シミュレーター起動後の待機秒数（デフォルト: 0） |
| `testWithoutBuilding` | ビルドをスキップし、既存のxctestrunファイルを使用 |
| `cleanBuild` | ビルド前に `clean` を実行 |
| `headless` | Simulator.appを開かない |
| `helperPath` | バージョンチェック用のScreenshotHelper.swiftへのパス |
| `launchArguments` | アプリに渡す追加の起動引数 |
| `configuration` | ビルド構成（例: Debug、Release） |
| `testplan` | Xcodeテストプラン名 |
| `numberOfRetries` | 失敗したテストの再試行回数 |
| `stopAfterFirstError` | 最初のエラー後にすべてのデバイスを停止 |
| `reinstallApp` | テスト前にアプリを削除して再インストール |
| `xcargs` | `xcodebuild` に渡す追加の引数 |
| `frameDevice` | このデバイスのベゼルフレーミングを有効化（デバイスごと） |
| `deviceBezel` | デバイスベゼルPNGファイルへのパス（デバイスごと） |
| `framedOutputDirectory` | フレーミングされたスクリーンショットの出力ディレクトリ（デフォルト：`{outputDirectory}/framed`） |
