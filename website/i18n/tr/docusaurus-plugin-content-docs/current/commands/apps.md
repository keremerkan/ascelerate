---
sidebar_position: 1
title: Uygulamalar
---

# Uygulamalar

## Uygulamaları listeleme

```bash
ascelerate apps list
```

## Uygulama detayları

```bash
ascelerate apps info <bundle-id>
```

## Sürümleri listeleme

```bash
ascelerate apps versions <bundle-id>
```

`apps list`, `apps info` ve `apps versions` komutlarının tümü, makine tarafından okunabilir çıktı için `--json` seçeneğini kabul eder ([kurallar](../guides/automation.md#json-output)).

## Sürüm oluşturma

```bash
ascelerate apps create-version <bundle-id> <version-string>
ascelerate apps create-version <bundle-id> 2.1.0 --platform ios --release-type manual
```

`--release-type` isteğe bağlıdır -- belirtilmezse önceki sürümün ayarı kullanılır.

:::note Evrensel Satın Alma
Evrensel satın alma kullanan uygulamalarda (iOS, macOS, tvOS ve/veya visionOS'i kapsayan tek bir App Store kaydı) aynı sürüm numarası her platformda birer kez bulunabilir. `create-version` ve `review submit` varsayılan olarak iOS'i hedefler; başka bir platformu hedeflemek için `--platform macos` (veya `tvos`, `visionos`) verin. Sürüm kapsamındaki diğer tüm komutlar (yerelleştirmeler, medya, build ekleme, review preflight/info/attachments/resolve-issues/cancel-submission, aşamalı yayınlama, manuel yayınlama) da isteğe bağlı bir `--platform` seçeneği kabul eder; seçenek verilmediğinde, bir sürüm (veya etkin bir inceleme gönderimi) birden fazla platformla eşleşiyorsa sizden platform seçmeniz istenir. `--yes` ile bu komutlar seçim istemek yerine yönlendirici bir hatayla durur.
:::

## Telif Hakkı

```bash
ascelerate apps copyright <bundle-id>
ascelerate apps copyright <bundle-id> --set "2026 Your Name" --version 2.1.0 --platform macos
```

`--set` verilmediğinde mevcut telif hakkı bildirimi gösterilir. Güncelleme için sürümün düzenlenebilir durumda olması gerekir.

## İnceleme

### İnceleme durumunu kontrol etme

```bash
ascelerate apps review status <bundle-id>
ascelerate apps review status <bundle-id> --version 2.1.0
```

Gönderimleri (öğe başına durumlar dahil) makine tarafından okunabilir JSON olarak almak için `--json` ekleyin.

### İncelemeye gönderme {#submit-for-review}

```bash
ascelerate apps review submit <bundle-id>
ascelerate apps review submit <bundle-id> --version 2.1.0
ascelerate apps review submit <bundle-id> --platform macos
```

Gönderim sırasında komut, bekleyen değişiklikleri olan IAP'leri ve abonelikleri otomatik olarak algılar ve bunları uygulama sürümüyle birlikte göndermeyi teklif eder. Bekleyen değişiklikler her ürünün sürüm geçmişinden okunur (Prepare for Submission, Ready for Review veya reddedilmiş durumdaki bir sürüm); böylece yalnızca ekran görüntüsü değişen ürünler de algılanır. `apps review status`, etkin gönderimlerdeki öğeleri ilgili uygulama sürümüne veya ürüne çözümleyerek gösterir.

### Reddedilen öğeleri çözme

Sorunları düzeltip Resolution Center'da yanıtladıktan sonra:

```bash
ascelerate apps review resolve-issues <bundle-id>
```

### Gönderimi iptal etme

```bash
ascelerate apps review cancel-submission <bundle-id>
```

### Uygulama İnceleme Bilgileri

App Review'a sunulan iletişim bilgilerini, demo hesabını ve notları görüntüleyin veya güncelleyin. Bayrak verilmediğinde mevcut değerler yazdırılır; herhangi bir alan bayrağı vererek o alanı güncelleyin (belirtilmeyen alanlar değiştirilmez).

```bash
ascelerate apps review info <bundle-id>
ascelerate apps review info <bundle-id> --contact-email siz@example.com --demo-account-name reviewer --demo-account-password "hunter2" --demo-account-required true --notes "Test adımları…"

# Ekler (demo videoları, belgeler vb.)
ascelerate apps review attachment list <bundle-id>
ascelerate apps review attachment upload <bundle-id> demo.mp4
ascelerate apps review attachment delete <attachment-id>
```

## Ön kontroller

İncelemeye göndermeden önce, her locale'de tüm gerekli alanların doldurulduğunu doğrulamak için `preflight` çalıştırın:

```bash
# En son düzenlenebilir sürümü kontrol edin
ascelerate apps review preflight <bundle-id>

# Belirli bir sürümü kontrol edin
ascelerate apps review preflight <bundle-id> --version 2.1.0
```

Komut; sürüm durumunu, build eklentisini kontrol eder ve ardından her locale'i inceleyerek yerelleştirme alanlarını (açıklama, yenilikler, anahtar kelimeler, destek URL'si), uygulama bilgi alanlarını (ad, alt başlık, gizlilik politikası URL'si) ve ekran görüntülerini doğrular:

```
Preflight checks for MyApp v2.1.0 (Prepare for Submission)

Check                                Status
──────────────────────────────────────────────────────────────────
Version state                        ✓ Prepare for Submission
Build attached                       ✓ Build 42

en-US (English (United States))
  App info                           ✓ All fields filled
  Localizations                      ✓ All fields filled
  Screenshots                        ✓ 2 sets, 10 screenshots

de-DE (German (Germany))
  App info                           ✗ Missing: Privacy Policy URL
  Localizations                      ✗ Missing: What's New
  Screenshots                        ✗ No screenshots
──────────────────────────────────────────────────────────────────
Result: 5 passed, 3 failed
```

Uygulama içi satın almalar ve abonelikler, fiyat ve gönderimle birlikte gidebilecek bir durum açısından denetlenir. Satıştan kaldırdığınız bir ürün (Developer Removed from Sale) atlandı (–) olarak listelenir ve kontrolün başarısız olmasına yol açmaz; sonuç satırı onu ayrıca sayar.

Uygulamanın daha önce yayınlanmış bir sürümü yoksa yenilikler denetimi atlanır; bu alan yalnızca güncellemelerde bulunur, ilk sürümde yer almaz.

Herhangi bir kontrol başarısız olduğunda sıfır olmayan çıkış kodu döndürür, bu da CI pipeline'larında ve workflow dosyalarında rahatlıkla kullanılmasını sağlar. `--json` ile komut, tablo yerine yapılandırılmış bir rapor üretir: bir `passed` boolean'ı ve her kontrol için bir kayıt (`group`, `name`, `passed`, `detail`). Çıkış kodu davranışı aynı kaldığından, CI kapıları tam olarak hangi kontrolün başarısız olduğunu raporlayabilir.

## Aşamalı yayınlama

```bash
# Aşamalı yayınlama durumunu görüntüleyin
ascelerate apps phased-release <bundle-id>

# Aşamalı yayınlamayı etkinleştirin (pasif başlar, sürüm yayınlandığında aktifleşir)
ascelerate apps phased-release <bundle-id> --enable

# Aşamalı yayınlamayı duraklatın, devam ettirin veya tamamlayın
ascelerate apps phased-release <bundle-id> --pause
ascelerate apps phased-release <bundle-id> --resume
ascelerate apps phased-release <bundle-id> --complete

# Aşamalı yayınlamayı tamamen kaldırın
ascelerate apps phased-release <bundle-id> --disable
```

## Manuel yayınlama

Bir sürümün yayınlama seçeneği manuel olarak ayarlandığında, onaylanan sürüm siz yayınlayana kadar Pending Developer Release (geliştirici yayınlaması bekleniyor) durumunda bekler:

```bash
# Geliştirici yayınlaması bekleyen sürümü yayınlayın
ascelerate apps release <bundle-id>

# Belirli bir sürümü veya platformu hedefleyin
ascelerate apps release <bundle-id> --version 2.1.0 --platform macos
```

## Erişilebilirlik beyanları

App Store, bir uygulamanın desteklediği erişilebilirlik özelliklerini gösterir. Bu özellikler cihaz ailesi başına beyan edilir: VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion, Captions ve Audio Descriptions.

```bash
# Beyanları (taslak veya yayınlanmış) cihaz ailesi başına görüntüleyin
ascelerate apps accessibility <bundle-id>

# Uygulamanın iPhone'da neleri desteklediğini beyan edin ve yayınlayın
ascelerate apps accessibility set <bundle-id> --device iphone --supports voiceover,larger-text,dark-interface --publish

# Taslak beyanları olduğu gibi yayınlayın
ascelerate apps accessibility publish <bundle-id>
```

`set` listenin tamamını beyan eder: Dışarıda bıraktığınız özellikler desteklenmiyor olarak beyan edilir (`--supports none` hiçbir özelliğin desteklenmediğini beyan eder). Cihaz aileleri: `iphone`, `ipad`, `mac`, `apple-tv`, `apple-watch`, `vision`. `--publish` verilmezse beyan taslak olarak kalır. Değiştirilmiş bir beyan yayınlandığında yayındaki beyanın yerini alır; `--all` yerini almış beyanları da listeler. Yalnızca kullanıcıların uygulamanın yaygın görevlerinde güvenebileceği özellikleri beyan edin.

## Bölge erişilebilirliği

```bash
# Uygulamanın hangi bölgelerde erişilebilir olduğunu görüntüleyin
ascelerate apps availability <bundle-id>

# Tam ülke adlarını gösterin
ascelerate apps availability <bundle-id> --verbose

# Bölgeleri erişilebilir veya erişilemez yapın
ascelerate apps availability <bundle-id> --add CHN,RUS
ascelerate apps availability <bundle-id> --remove CHN
```

## Uygulama fiyatlandırması

```bash
# Temel fiyat, elle belirlenen fiyatlar ve planlanan değişiklikler (--all: tüm bölgeler; --json)
ascelerate apps pricing <bundle-id>
ascelerate apps pricing tiers <bundle-id> --territory USA

# Temel fiyat, hemen veya belirli bir tarihten itibaren (temel bölgenin para biriminde; ücretsiz için 0)
ascelerate apps pricing set <bundle-id> --price 0.99
ascelerate apps pricing set <bundle-id> --price 1.99 --start-date 2026-12-01

# Elle belirlenen fiyatlar: tek bir bölge, Apple'ın güncel fiyatlarını koruma veya fiyatları Apple'a geri bırakma
ascelerate apps pricing override <bundle-id> --territory FRA --price 0.99
ascelerate apps pricing keep <bundle-id> --territories all
ascelerate apps pricing remove <bundle-id> --territories FRA,DEU

# Geçici fiyat değişikliği (indirim) ve planlanan bir değişikliği kaldırma
ascelerate apps pricing sale <bundle-id> --territories all --price 0.49 --start-date 2026-12-20 --end-date 2026-12-27
ascelerate apps pricing cancel <bundle-id> --territory USA --start-date 2026-12-01

# Fiyat planını başka bir uygulamaya kopyalama (iap pricing export biçimi)
ascelerate apps pricing export <bundle-id> --output prices.json
ascelerate apps pricing import <other-bundle-id> --file prices.json
```

Apple diğer bölgelerin fiyatlarını temel fiyattan belirler ve vergi veya döviz kuru değişikliklerine göre ayarlayabilir; elle belirlenen bir fiyat olduğu gibi kalır. Birden çok bölgede `sale`, fiyatı temel bölgenin para biriminde alır ve diğer bölgelere Apple'ın karşılaştırılabilir fiyatlarını verir; sonrasında her bölgede önceki fiyat yeniden geçerli olur. `import` fiyat planını bütünüyle değiştirir.

## Şifreleme beyanları

```bash
# Mevcut şifreleme beyanlarını görüntüleyin
ascelerate apps encryption <bundle-id>

# Yeni bir şifreleme beyanı oluşturun
ascelerate apps encryption <bundle-id> --create --description "Uses HTTPS for API communication"
ascelerate apps encryption <bundle-id> --create --description "Uses AES encryption" --proprietary-crypto --third-party-crypto
```

## EULA

```bash
# Mevcut EULA'yı görüntüleyin (veya standart Apple EULA'nın geçerli olduğunu görün)
ascelerate apps eula <bundle-id>

# Bir metin dosyasından özel EULA ayarlayın
ascelerate apps eula <bundle-id> --file eula.txt

# Özel EULA'yı kaldırın (standart Apple EULA'ya geri döner)
ascelerate apps eula <bundle-id> --delete
```

## Abonelik ödemesiz dönem (grace period)

Ödemesiz dönem, başarısız bir yenileme ödemesinden sonra Apple yeniden faturalandırmayı denerken abonelerin kısa bir süre erişimi koruyabilmesini sağlar. Ayar uygulama genelinde uygulanır.

```bash
# Mevcut yapılandırmayı görüntüle
ascelerate apps subscription-grace-period <bundle-id>

# Tüm yenilemeler için 16 günlük üretim ödemesiz dönemini etkinleştir
ascelerate apps subscription-grace-period <bundle-id> \
  --opt-in true --duration SIXTEEN_DAYS --renewal-type ALL_RENEWALS

# Yalnızca sandbox testi (üretim kapalı kalır)
ascelerate apps subscription-grace-period <bundle-id> \
  --sandbox-opt-in true --duration THREE_DAYS --renewal-type ALL_RENEWALS
```

Geçerli `--duration` değerleri: `THREE_DAYS`, `SIXTEEN_DAYS`, `TWENTY_EIGHT_DAYS`. Geçerli `--renewal-type` değerleri: `ALL_RENEWALS`, `PAID_TO_PAID_ONLY`.

Üretim, sandbox kapalıyken açık olamaz: `--opt-in` sandbox'ı da açar ve başka değer verilmezse süre 16 gün, kapsam tüm yenilemeler olur. İkisi de kapatılınca süre ve yenileme türü silinir.

## Kolaylaştırılmış satın alma (Streamlined Purchasing)

Kolaylaştırılmış satın alma, müşterilerin uygulamanın aboneliklerini uygulama dışında, örneğin App Store ürün sayfasında satın almasını sağlar. Varsayılan olarak açıktır ve uygulamanın tüm aboneliklerine uygulanır. Apple bunu yalnızca son onaylanan yapısı StoreKit `PurchaseIntent` API'sini kullanan bir uygulamada kapattırır; müşteriler o zaman uygulama içinden abone olur.

```bash
# Görüntüle
ascelerate apps streamlined-purchasing <bundle-id>

# Kapat
ascelerate apps streamlined-purchasing <bundle-id> --enabled false
```
