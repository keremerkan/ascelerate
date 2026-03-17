---
sidebar_position: 6
title: Uygulama İçi Satın Almalar
---

# Uygulama İçi Satın Almalar

## Listeleme

```bash
ascelerate iap list <bundle-id>
ascelerate iap list <bundle-id> --type consumable --state approved
```

Filtre değerleri büyük/küçük harf duyarsızdır. Türler: `CONSUMABLE`, `NON_CONSUMABLE`, `NON_RENEWING_SUBSCRIPTION`. Durumlar: `APPROVED`, `MISSING_METADATA`, `READY_TO_SUBMIT`, `WAITING_FOR_REVIEW`, `IN_REVIEW` vb.

## Detayları görüntüleme

```bash
ascelerate iap info <bundle-id> <product-id>
```

## Tanıtılan satın almalar

```bash
ascelerate iap promoted <bundle-id>
```

## Oluşturma, güncelleme ve silme

```bash
ascelerate iap create <bundle-id> --name "100 Coins" --product-id <product-id> --type CONSUMABLE
ascelerate iap update <bundle-id> <product-id> --name "100 Gold Coins"
ascelerate iap delete <bundle-id> <product-id>
```

## İncelemeye gönderme

```bash
ascelerate iap submit <bundle-id> <product-id>
```

## Yerelleştirmeler

```bash
ascelerate iap localizations view <bundle-id> <product-id>
ascelerate iap localizations export <bundle-id> <product-id>
ascelerate iap localizations import <bundle-id> <product-id> --file iap-de.json
```

İçe aktarma komutu eksik locale'leri onay ile otomatik olarak oluşturur, böylece App Store Connect'i ziyaret etmeden yeni diller ekleyebilirsiniz.
