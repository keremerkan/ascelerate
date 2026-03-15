---
sidebar_position: 9
title: Sertifikalar
---

# Sertifikalar

Tüm sertifika komutları interaktif modu destekler -- argümanlar isteğe bağlıdır.

## Listeleme

```bash
asc certs list
asc certs list --type DISTRIBUTION
```

## Detayları görüntüleme

```bash
# İnteraktif seçici
asc certs info

# Seri numarası veya görünen ad ile
asc certs info "Apple Distribution: Example Inc"
```

## Oluşturma

```bash
# İnteraktif tür seçici, RSA anahtar çifti ve CSR'yi otomatik oluşturur
asc certs create

# Tür belirtin
asc certs create --type DISTRIBUTION

# Kendi CSR'nizi kullanın
asc certs create --type DEVELOPMENT --csr my-request.pem
```

`--csr` belirtilmediğinde komut otomatik olarak bir RSA anahtar çifti ve CSR oluşturur, ardından her şeyi login keychain'e aktarır.

## İptal etme

```bash
# İnteraktif seçici
asc certs revoke

# Seri numarası ile
asc certs revoke ABC123DEF456
```
