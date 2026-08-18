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

### İncelemeye gönderme

```bash
ascelerate apps review submit <bundle-id>
ascelerate apps review submit <bundle-id> --version 2.1.0
ascelerate apps review submit <bundle-id> --platform macos
```

Gönderim sırasında komut, bekleyen değişiklikleri olan IAP'leri ve abonelikleri otomatik olarak algılar ve bunları uygulama sürümüyle birlikte göndermeyi teklif eder.

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

# Sandbox testi için de etkinleştir
ascelerate apps subscription-grace-period <bundle-id> --sandbox-opt-in true
```

Geçerli `--duration` değerleri: `THREE_DAYS`, `SIXTEEN_DAYS`, `TWENTY_EIGHT_DAYS`. Geçerli `--renewal-type` değerleri: `ALL_RENEWALS`, `PAID_TO_PAID_ONLY`.
