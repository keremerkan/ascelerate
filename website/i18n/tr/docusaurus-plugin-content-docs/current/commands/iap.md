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

## Fiyatlandırma

`iap pricing` fiyat çizelgesini okur ve yazar. Çizelgenin tek bir temel bölgesi vardır — Apple'ın diğer tüm bölgelerdeki fiyatları otomatik eşitlemek için kullandığı bölge — ve isteğe bağlı olarak bölgeye özel manuel geçersiz kılmalar içerebilir.

```bash
# Mevcut fiyat çizelgesini göster (henüz ayarlanmamışsa uyarır)
ascelerate iap pricing show <bundle-id> <product-id>

# Bir bölgedeki tüm fiyat kademelerini listele
ascelerate iap pricing tiers <bundle-id> <product-id> --territory USA
```

### Temel bölge fiyatını ayarlama

```bash
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99 --base-region GBR
```

`--base-region` mevcut temel bölgeye varsayılan olarak ayarlanır (yeni bir çizelgede ise USA). Çizelgede bölgeye özel manuel geçersiz kılmalar varsa, `set` komutu bunlardan herhangi birini yeni temel bölgeden otomatik eşitlemeye geri çevirme seçeneği sunan etkileşimli bir menü gösterir. Tüm geçersiz kılmaları onay almadan silmek için `--remove-all-overrides` bayrağını kullanın.

### Bölgeye özel geçersiz kılmalar

```bash
# Manuel bir geçersiz kılma ekle veya güncelle
ascelerate iap pricing override <bundle-id> <product-id> --price 5.99 --territory FRA

# Geçersiz kılmayı kaldır (bölge, temel bölgeden otomatik eşitlemeye geri döner)
ascelerate iap pricing remove <bundle-id> <product-id> --territory FRA
```

`override` ve `remove` yalnızca temel olmayan bölgelerde çalışır. Temel bölgenin fiyatını değiştirmek için `set` komutunu kullanın.

Bir IAP'nin fiyat çizelgesi olmadığında, `iap info` ve `iap pricing show` komutları uyarı verir; aynı durum `apps review preflight` komutunda da gönderim için engelleyici olarak işaretlenir.
