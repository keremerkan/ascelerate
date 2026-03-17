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

## Sürüm oluşturma

```bash
ascelerate apps create-version <bundle-id> <version-string>
ascelerate apps create-version <bundle-id> 2.1.0 --platform ios --release-type manual
```

`--release-type` isteğe bağlıdır -- belirtilmezse önceki sürümün ayarı kullanılır.

## İnceleme

### İnceleme durumunu kontrol etme

```bash
ascelerate apps review status <bundle-id>
ascelerate apps review status <bundle-id> --version 2.1.0
```

### İncelemeye gönderme

```bash
ascelerate apps review submit <bundle-id>
ascelerate apps review submit <bundle-id> --version 2.1.0
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

## Ön kontroller

İncelemeye göndermeden önce, her locale'de tüm gerekli alanların doldurulduğunu doğrulamak için `preflight` çalıştırın:

```bash
# En son düzenlenebilir sürümü kontrol edin
ascelerate apps review preflight <bundle-id>

# Belirli bir sürümü kontrol edin
ascelerate apps review preflight <bundle-id> --version 2.1.0
```

Komut; sürüm durumunu, build eklentisini kontrol eder ve ardından her locale'i inceleyerek yerelleştirme alanlarını (açıklama, yenilikler, anahtar kelimeler), uygulama bilgi alanlarını (ad, alt başlık, gizlilik politikası URL'si) ve ekran görüntülerini doğrular:

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

Herhangi bir kontrol başarısız olduğunda sıfır olmayan çıkış kodu döndürür, bu da CI pipeline'larında ve workflow dosyalarında rahatlıkla kullanılmasını sağlar.

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
