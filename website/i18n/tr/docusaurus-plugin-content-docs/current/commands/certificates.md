---
sidebar_position: 9
title: Sertifikalar
---

# Sertifikalar

Tüm sertifika komutları interaktif modu destekler -- argümanlar isteğe bağlıdır.

## Listeleme

```bash
ascelerate certs list
ascelerate certs list --type DISTRIBUTION
```

## Detayları görüntüleme

```bash
# İnteraktif seçici
ascelerate certs info

# Seri numarası veya görünen ad ile
ascelerate certs info "Apple Distribution: Example Inc"
```

## Oluşturma

```bash
# İnteraktif tür seçici, RSA anahtar çifti ve CSR'yi otomatik oluşturur
ascelerate certs create

# Tür belirtin
ascelerate certs create --type DISTRIBUTION

# Kendi CSR'nizi kullanın
ascelerate certs create --type DEVELOPMENT --csr my-request.pem
```

Sertifika istenmeden önce özel anahtar (yalnızca sizin okuyabileceğiniz şekilde) yazılır ve çıktı klasörü denetlenir; istek başarısız olursa anahtar yeniden silinir. `--csr` ile oluşturulan sertifika da kaydedilir; `--output` verilmezse `<seri numarası>.cer` adıyla. Anahtar zincirine aktarımdan sonra komut yerel dosyaları silmeyi önerir; `--output` veya `--yes` ile dosyalar korunur, `--delete-local-files` verirseniz silinir.

`--csr` belirtilmediğinde komut otomatik olarak bir RSA anahtar çifti ve CSR oluşturur, ardından her şeyi login keychain'e aktarır.

## İptal etme

```bash
# İnteraktif seçici
ascelerate certs revoke

# Seri numarası ile
ascelerate certs revoke ABC123DEF456
```
