---
sidebar_position: 7
title: Abonelikler
---

# Abonelikler

## Listeleme ve inceleme

```bash
asc sub groups <bundle-id>
asc sub list <bundle-id>
asc sub info <bundle-id> <product-id>
```

## Abonelik oluşturma, güncelleme ve silme

```bash
asc sub create <bundle-id> --name "Monthly" --product-id <product-id> --period ONE_MONTH --group-id <group-id>
asc sub update <bundle-id> <product-id> --name "Monthly Plan"
asc sub delete <bundle-id> <product-id>
```

## Abonelik grupları

```bash
asc sub create-group <bundle-id> --name "Premium"
asc sub update-group <bundle-id> --name "Premium Plus"
asc sub delete-group <bundle-id>
```

## İncelemeye gönderme

```bash
asc sub submit <bundle-id> <product-id>
```

## Abonelik yerelleştirmeleri

```bash
asc sub localizations view <bundle-id> <product-id>
asc sub localizations export <bundle-id> <product-id>
asc sub localizations import <bundle-id> <product-id> --file sub-de.json
```

## Grup yerelleştirmeleri

```bash
asc sub group-localizations view <bundle-id>
asc sub group-localizations export <bundle-id>
asc sub group-localizations import <bundle-id> --file group-de.json
```

İçe aktarma komutları eksik locale'leri onay ile otomatik olarak oluşturur, böylece App Store Connect'i ziyaret etmeden yeni diller ekleyebilirsiniz.
