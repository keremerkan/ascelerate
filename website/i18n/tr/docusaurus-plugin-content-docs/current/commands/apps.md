---
sidebar_position: 1
title: Uygulamalar
---

# Uygulamalar

## Uygulamaları listeleme

```bash
asc apps list
```

## Uygulama detayları

```bash
asc apps info <bundle-id>
```

## Sürümleri listeleme

```bash
asc apps versions <bundle-id>
```

## Sürüm oluşturma

```bash
asc apps create-version <bundle-id> <version-string>
asc apps create-version <bundle-id> 2.1.0 --platform ios --release-type manual
```

`--release-type` isteğe bağlıdır -- belirtilmezse önceki sürümün ayarı kullanılır.

## İnceleme

### İnceleme durumunu kontrol etme

```bash
asc apps review status <bundle-id>
asc apps review status <bundle-id> --version 2.1.0
```

### İncelemeye gönderme

```bash
asc apps review submit <bundle-id>
asc apps review submit <bundle-id> --version 2.1.0
```

Gönderim sırasında komut, bekleyen değişiklikleri olan IAP'leri ve abonelikleri otomatik olarak algılar ve bunları uygulama sürümüyle birlikte göndermeyi teklif eder.

### Reddedilen öğeleri çözme

Sorunları düzeltip Resolution Center'da yanıtladıktan sonra:

```bash
asc apps review resolve-issues <bundle-id>
```

### Gönderimi iptal etme

```bash
asc apps review cancel-submission <bundle-id>
```

## Ön kontroller

İncelemeye göndermeden önce, her locale'de tüm gerekli alanların doldurulduğunu doğrulamak için `preflight` çalıştırın:

```bash
# En son düzenlenebilir sürümü kontrol edin
asc apps review preflight <bundle-id>

# Belirli bir sürümü kontrol edin
asc apps review preflight <bundle-id> --version 2.1.0
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
asc apps phased-release <bundle-id>

# Aşamalı yayınlamayı etkinleştirin (pasif başlar, sürüm yayınlandığında aktifleşir)
asc apps phased-release <bundle-id> --enable

# Aşamalı yayınlamayı duraklatın, devam ettirin veya tamamlayın
asc apps phased-release <bundle-id> --pause
asc apps phased-release <bundle-id> --resume
asc apps phased-release <bundle-id> --complete

# Aşamalı yayınlamayı tamamen kaldırın
asc apps phased-release <bundle-id> --disable
```

## Bölge erişilebilirliği

```bash
# Uygulamanın hangi bölgelerde erişilebilir olduğunu görüntüleyin
asc apps availability <bundle-id>

# Tam ülke adlarını gösterin
asc apps availability <bundle-id> --verbose

# Bölgeleri erişilebilir veya erişilemez yapın
asc apps availability <bundle-id> --add CHN,RUS
asc apps availability <bundle-id> --remove CHN
```

## Şifreleme beyanları

```bash
# Mevcut şifreleme beyanlarını görüntüleyin
asc apps encryption <bundle-id>

# Yeni bir şifreleme beyanı oluşturun
asc apps encryption <bundle-id> --create --description "Uses HTTPS for API communication"
asc apps encryption <bundle-id> --create --description "Uses AES encryption" --proprietary-crypto --third-party-crypto
```

## EULA

```bash
# Mevcut EULA'yı görüntüleyin (veya standart Apple EULA'nın geçerli olduğunu görün)
asc apps eula <bundle-id>

# Bir metin dosyasından özel EULA ayarlayın
asc apps eula <bundle-id> --file eula.txt

# Özel EULA'yı kaldırın (standart Apple EULA'ya geri döner)
asc apps eula <bundle-id> --delete
```
