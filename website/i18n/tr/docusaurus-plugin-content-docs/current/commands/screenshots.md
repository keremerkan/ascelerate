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

### Çerçeveleme

```bash
ascelerate screenshot frame                    # Frame screenshots with device bezels
```

Yakalanan ekran görüntülerini cihaz çerçeve görüntüleri ile çerçeveler. Yapılandırmadaki `frameDevice` ve `deviceBezel` ayarlarını kullanır. Ekran görüntüleri yakalandıktan sonra bağımsız olarak çalıştırılabilir.

### Doktor

```bash
ascelerate screenshot doctor                   # Check config and environment
```

Ekran görüntüsü yapılandırmasını ve ortamı doğrular: yapılandırma dosyası, proje/workspace varlığı, xcodebuild ve simctl erişilebilirliği, simülatör cihazları, helper dosya sürümü, cihaz çerçeve dosyaları ve çıktı dizinlerini kontrol eder. Başarılı/başarısız/uyarı göstergeleri ile bir kontrol listesi gösterir.

## Yapılandırma (`ascelerate/screenshot.yml`)

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
# numberOfRetries: 0                     # Retry failed languages (erase + reboot simulator)
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
4. `numberOfRetries` ayarlıysa ve herhangi bir cihaz başarısız olursa: başarısız simülatörleri sıfırlar, yeniden yerelleştirir, yeniden başlatır ve tekrar dener
5. Cihaz bazlı önbellekten çıktı dizinine ekran görüntülerini toplar
6. Ekran görüntülerini cihaz çerçeveleri ile çerçeveler (`frameDevice` etkinse)
7. Hatalar atlanır ve devam edilir — hata günlükleri çıktıya kaydedilir

## Çıktı

```
screenshots/
├── en-US/
│   ├── iPhone 17 Pro Max-01-home.png
│   ├── iPhone 17 Pro Max-02-settings.png
│   └── iPad Pro 13-inch (M5)-01-home.png
└── de-DE/
    └── ...
```

## Cihaz çerçeveleme

Apple cihaz çerçeveleri ile yakalanan ekran görüntülerini çerçeveleyin.

:::info
Cihaz çerçeveleri ascelerate ile birlikte gelmez — [Apple Product Bezels](https://developer.apple.com/design/resources/#product-bezels) sayfasından indirin (Apple Developer hesabı gereklidir). İndirme, tüm güncel cihazlar için PNG çerçeveler içeren bir DMG dosyasıdır.
:::

### Kurulum

1. [Apple Design Resources](https://developer.apple.com/design/resources/#product-bezels) sayfasından Product Bezels DMG dosyasını indirin
2. Çerçeve PNG dosyalarını projenizde bir klasöre çıkarın (örn. `./bezels/`)
3. Yapılandırmada her cihaz için çerçevelemeyi etkinleştirin:

```yaml
devices:
  - simulator: iPhone 17 Pro Max
    frameDevice: true
    deviceBezel: ./bezels/iPhone 17 Pro Max.png
  - simulator: iPad Pro 13-inch (M5)
    frameDevice: false
```

### Çıktı

Çerçevelenmiş ekran görüntüleri `framedOutputDirectory` dizinine kaydedilir (varsayılan: `{outputDirectory}/framed`):

```
screenshots/framed/
├── en-US/
│   └── iPhone 17 Pro Max-01-home.png
└── de-DE/
    └── ...
```

Yalnızca `frameDevice: true` olan cihazlar çerçevelenir. Çerçeveleme, `screenshot run` sırasında her dilden sonra otomatik olarak çalışır veya `screenshot frame` ile bağımsız olarak çalıştırılabilir.

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
| `numberOfRetries` | Başarısız diller için tekrar deneme sayısı — simülatörü sıfırlar, yeniden yerelleştirir, yeniden başlatır ve testleri tekrar çalıştırır. Yalnızca başarısız cihazları tekrar dener. Tekrar denenen sonuçlar özet tablosunda işaretlenir. |
| `stopAfterFirstError` | İlk hatadan sonra tüm cihazları durdur |
| `reinstallApp` | Testlerden önce uygulamayı silip yeniden yükle |
| `xcargs` | `xcodebuild`'e aktarılan ek argümanlar |
| `frameDevice` | Bu cihaz için çerçevelemeyi etkinleştir (cihaz başına) |
| `deviceBezel` | Cihaz çerçeve PNG dosyasının yolu (cihaz başına) |
| `framedOutputDirectory` | Çerçevelenmiş ekran görüntüleri için çıktı dizini (varsayılan: `{outputDirectory}/framed`) |
