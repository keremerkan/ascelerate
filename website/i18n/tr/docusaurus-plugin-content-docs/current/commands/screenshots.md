---
sidebar_position: 12
title: Ekran Görüntüsü Yakalama
---

# Ekran Görüntüsü Yakalama

UI testleri kullanarak iOS/iPadOS simülatörlerinden doğrudan App Store ekran görüntüleri yakalayın. [fastlane snapshot](https://docs.fastlane.tools/actions/snapshot/) yerine kullanılır.

## Hızlı başlangıç

```bash
ascelerate screenshot init                  # Create config and helper in ascelerate/
ascelerate screenshot                       # Capture screenshots
```

## Komutlar

### Çalıştırma

```bash
ascelerate screenshot                       # Capture screenshots
ascelerate screenshot run                   # Same as above
```

Her zaman mevcut dizindeki `ascelerate/screenshot.yml` dosyasını kullanır.

### Başlatma

```bash
ascelerate screenshot init
```

`ascelerate/` dizininde hem `ascelerate/screenshot.yml` hem de `ascelerate/ScreenshotHelper.swift` dosyalarını oluşturur. Yazmadan önce onay ister. Mevcut dosyaların üzerine yazmaz.

### Helper oluşturma

```bash
ascelerate screenshot create-helper         # Generates ScreenshotHelper.swift
ascelerate screenshot create-helper -o CustomHelper.swift
```

## Yapılandırma (`ascelerate/screenshot.yml`)

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

## UITest'lerde kullanım

`ScreenshotHelper.swift` dosyasını UITest target'ınıza ekleyin:

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

Uygulamanız ekran görüntüsü modunu algılayabilir:

```swift
if ProcessInfo.processInfo.arguments.contains("-ASC_SCREENSHOT") {
    // Show demo data, hide debug UI, etc.
}
```

Helper ayrıca `disableAnimationsIfNeeded()` fonksiyonunu da sunar; yapılandırmada `disableAnimations` etkinleştirildiğinde animasyonları devre dışı bırakır:

```swift
override func setUp() {
    setupScreenshots(app)
    disableAnimationsIfNeeded()
    app.launch()
}
```

## Nasıl çalışır

1. `build-for-testing` ile bir kez derler (`testWithoutBuilding: true` ise atlar)
2. Her dil için: tüm simülatörleri başlatır, yerelleştirir, durum çubuğunu değiştirir
3. Tüm cihazlarda testleri eş zamanlı çalıştırır
4. Cihaz bazlı önbellekten çıktı dizinine ekran görüntülerini toplar
5. Hatalar atlanır ve devam edilir — hata günlükleri çıktıya kaydedilir

## Çıktı

```
screenshots/
├── en-US/
│   ├── iPhone 16 Pro Max-01-home.png
│   ├── iPhone 16 Pro Max-02-settings.png
│   └── iPad Pro 13-inch (M4)-01-home.png
└── de-DE/
    └── ...
```

## Seçenekler

| Seçenek | Açıklama |
|---|---|
| `clearPreviousScreenshots` | Toplamadan önce dil klasörünü temizle (yalnızca tüm cihazlar başarılı olursa) |
| `eraseSimulator` | Her dilden önce simülatörü sıfırla |
| `localizeSimulator` | Her dil için simülatör dilini/locale'ini ayarla |
| `overrideStatusBar` | Durum çubuğunu değiştir (9:41, tam çubuklar, Wi-Fi) |
| `statusBarArguments` | Özel `xcrun simctl status_bar` argümanları |
| `darkMode` | Simülatörlerde karanlık modu etkinleştir |
| `disableAnimations` | Testler sırasında animasyonları devre dışı bırak |
| `waitAfterBoot` | Simülatör başlatıldıktan sonra beklenecek saniye (varsayılan: 0) |
| `testWithoutBuilding` | Derlemeyi atla, mevcut xctestrun dosyasını kullan |
| `cleanBuild` | Derlemeden önce `clean` çalıştır |
| `headless` | Simulator.app'i açma |
| `helperPath` | Versiyon kontrolü için ScreenshotHelper.swift yolu |
| `launchArguments` | Uygulamaya aktarılan ek başlatma argümanları |
| `configuration` | Derleme yapılandırması (örn. Debug, Release) |
| `testplan` | Xcode test planı adı |
| `numberOfRetries` | Başarısız testler için tekrar deneme sayısı |
| `stopAfterFirstError` | İlk hatadan sonra tüm cihazları durdur |
| `reinstallApp` | Testlerden önce uygulamayı silip yeniden yükle |
| `xcargs` | `xcodebuild`'e aktarılan ek argümanlar |
