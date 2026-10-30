---
sidebar_position: 2
title: Build'ler
---

# Build'ler

## Build'leri listeleme

```bash
ascelerate builds list
ascelerate builds list --bundle-id <bundle-id>
ascelerate builds list --bundle-id <bundle-id> --version 2.1.0
ascelerate builds list --bundle-id <bundle-id> --platform macos
```

Çıktı, her build'in uygulama sürümünü, platformunu, build numarasını, işlenme durumunu ve yükleme tarihini gösterir. Makine tarafından okunabilir çıktı için `--json` ekleyin ([kurallar](../guides/automation.md#json-output)).

## Arşivleme

```bash
ascelerate builds archive
ascelerate builds archive --scheme MyApp --output ./archives
```

`archive` komutu geçerli dizindeki `.xcworkspace` veya `.xcodeproj` dosyasını otomatik olarak algılar ve yalnızca bir tane varsa scheme'i çözer.

`--destination` verilmezse scheme'in platformu için arşivler (Mac uygulaması için `generic/platform=macOS`). Birden çok platform için derlenen bir uygulama, `--destination` verilmedikçe iOS için arşivlenir.

`--build-number` ile arşive derlenen her şey (uygulama, uzantıları, Apple Watch uygulaması) bu derleme numarasını alır: seçenek `CURRENT_PROJECT_VERSION` değerini yalnızca bu arşiv için ayarlar, proje olduğu gibi kalır. Projedeki numara zaten yüklendiyse kullanın. Info.plist dosyasında `$(CURRENT_PROJECT_VERSION)` yerine kendi numarasını belirten bir target, o numarayı korur.

```bash
ascelerate builds archive --scheme MyApp --build-number 9
```

## Arşivleri listeleme

```bash
ascelerate builds archives
ascelerate builds archives --bundle-id com.example.MyApp --platform macos --limit 1 --json
```

Xcode'un arşiv konumundaki (`~/Library/Developer/Xcode/Archives`) arşivleri en yeniden başlayarak bundle ID, sürüm, build numarası, platform ve tarihleriyle listeler. `--bundle-id` ve `--platform` listeyi daraltır; `--json` her arşivin yolunu da verir.

## Doğrulama

```bash
ascelerate builds validate MyApp.ipa
```

## Yükleme

```bash
ascelerate builds upload MyApp.ipa
```

`.ipa`, `.pkg` veya `.xcarchive` dosyalarını kabul eder. `.xcarchive` verildiğinde arşivin platformunu algılar ve yüklemeden önce otomatik olarak `.ipa` (iOS ailesi) veya `.pkg` (macOS) biçimine dışa aktarır; eşleşen platform altool'a iletilir.

```bash
ascelerate builds upload --latest --bundle-id com.example.MyApp --platform macos
```

`--latest` ile Xcode'un arşiv konumundaki en yeni arşivi yükler: `--bundle-id` ile bir uygulamanın, `--platform` ile bir platformun en yenisini (iOS ve macOS'ta aynı bundle ID ile satılan bir uygulamanın her ikisi için de arşivleri olur).

App Store dağıtım profilleriyle imzalanmış bir `.xcarchive` (elle imzalanan bir proje), uygulamanın ve uzantılarının yüklü App Store profilleriyle dışa aktarılır; böylece Xcode yeni profil oluşturmaz. Diğer arşivler otomatik imzalamayla dışa aktarılır. Bir dosya verildiğinde `--bundle-id`, başka bir uygulama içeren dosyayı hiçbir şey dışa aktarılmadan veya gönderilmeden önce reddeder.

### App Store Connect API üzerinden yükleme

```bash
ascelerate builds upload MyApp.ipa --api
ascelerate builds upload --latest --bundle-id com.example.MyApp --api
```

`--api` ile build, altool yerine App Store Connect API'nin build yükleme uç noktaları üzerinden, diğer tüm komutlarla aynı API anahtarı kullanılarak gönderilir. Bir `.ipa` veya Mac `.pkg` dosyası (ya da önce dışa aktarılan bir `.xcarchive`) kabul eder, sürümü ve build numarasını içindeki uygulamadan okur, dosyayı parçalar hâlinde tek tek yükler (terminalde bir ilerleme çubuğuyla; bkz. [Parça parça yükleme](../guides/automation.md#upload-chunks)) ve ardından App Store Connect dosyayı kabul edene kadar bekler. Apple dosyayı reddederse komut, Apple'ın hata kodları ve açıklamalarıyla başarısız olur; uyarılar ise başarılı bir yüklemenin ardından yazdırılır. Sonrasında işlenme her zamanki gibi devam eder (bkz. [İşlenmeyi bekleme](#await-processing)).

Şimdilik varsayılan yöntem altool olmaya devam ediyor.

### Diğer araçlar için ilerleme

```bash
ascelerate builds archive --scheme MyApp --json-events
ascelerate builds upload MyApp.ipa --api --json-events
```

`--json-events` ile her iki komut da standart çıktıya her satıra bir JSON nesnesi yazar (`step`, arşivin yolunu içeren `archived`, `uploading`, `progress`, `uploaded` ve Apple'ın uyarılarını içeren `finished`) ve xcodebuild çıktısı dahil okunabilir çıktıyı standart hataya taşır; `screenshot run --json-events` de aynı şekilde çalışır. Arşivlemede xcodebuild bu durumda yalnızca uyarıları ve hataları yazar.

## Yükleme geçmişi

```bash
ascelerate builds uploads <bundle-id>
ascelerate builds uploads <bundle-id> --platform macos --limit 20
ascelerate builds uploads <bundle-id> --delete-stale
```

Uygulamanın son yüklemelerini (altool, Xcode veya `--api` ile yapılmış olmalarından bağımsız olarak) durumları (Awaiting Upload, Processing, Complete, Failed) ve Apple'ın bunlara eklediği hata ve uyarılarla birlikte listeler. Bir yükleme bir türlü build'e dönüşmüyorsa buraya bakın. Makine tarafından okunabilir çıktı için `--json` ekleyin.

Bağlantının yanlış anda kopması, hiç gelmeyecek bir dosyayı bekleyen bir yükleme kaydı bırakabilir. `--api` yüklemeleri, başarıyla tamamlandıktan sonra aynı build'e ait bu tür kayıtları kaldırır; `--delete-stale` ise geriye kalanları kaldırır: aynı build'in başka bir yüklemesi ilerlemişken ya da bir günden uzun süredir hâlâ dosya bekleyen kayıtlar. Devam eden bir yükleme hiçbir zaman kaldırılmaz.

## İşlenmeyi bekleme {#await-processing}

```bash
ascelerate builds await-processing <bundle-id>
ascelerate builds await-processing <bundle-id> --build-version 903
ascelerate builds await-processing <bundle-id> --build-version 903 --platform macos
```

Yakın zamanda yüklenen build'lerin API'da görünmesi birkaç dakika sürebilir -- komut, build bulunana ve işlenmesi tamamlanana kadar ilerleme göstergesiyle yoklar.

## Bir sürüme build ekleme

```bash
# İnteraktif olarak bir build seçin ve ekleyin
ascelerate apps build attach <bundle-id>
ascelerate apps build attach <bundle-id> --version 2.1.0

# En son build'i otomatik olarak ekleyin
ascelerate apps build attach-latest <bundle-id>
ascelerate apps build attach-latest <bundle-id> --platform macos

# Bir sürümden eklenen build'i kaldırın
ascelerate apps build detach <bundle-id>
```

`build attach-latest`, en son build hâlâ işleniyorsa beklemeyi teklif eder. `--yes` ile otomatik olarak bekler.

Build aramaları platforma duyarlıdır: evrensel satın alma kullanan uygulamalarda iOS ve macOS build'leri aynı build numaralarını paylaşabildiğinden, ekleme komutları yalnızca hedef sürümün platformuyla eşleşen build'leri dikkate alır.
