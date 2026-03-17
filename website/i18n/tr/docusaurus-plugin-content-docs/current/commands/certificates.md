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

`--csr` belirtilmediğinde komut otomatik olarak bir RSA anahtar çifti ve CSR oluşturur, ardından her şeyi login keychain'e aktarır.

## İptal etme

```bash
# İnteraktif seçici
ascelerate certs revoke

# Seri numarası ile
ascelerate certs revoke ABC123DEF456
```
