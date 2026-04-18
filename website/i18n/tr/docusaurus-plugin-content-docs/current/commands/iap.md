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
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99 --base-territory GBR
```

`--base-territory` mevcut temel bölgeye varsayılan olarak ayarlanır (yeni bir çizelgede ise USA). Çizelgede bölgeye özel manuel geçersiz kılmalar varsa, `set` komutu bunlardan herhangi birini yeni temel bölgeden otomatik eşitlemeye geri çevirme seçeneği sunan etkileşimli bir menü gösterir. Tüm geçersiz kılmaları onay almadan silmek için `--remove-all-overrides` bayrağını kullanın.

### Bölgeye özel geçersiz kılmalar

```bash
# Manuel bir geçersiz kılma ekle veya güncelle
ascelerate iap pricing override <bundle-id> <product-id> --price 5.99 --territory FRA

# Geçersiz kılmayı kaldır (bölge, temel bölgeden otomatik eşitlemeye geri döner)
ascelerate iap pricing remove <bundle-id> <product-id> --territory FRA
```

`override` ve `remove` yalnızca temel olmayan bölgelerde çalışır. Temel bölgenin fiyatını değiştirmek için `set` komutunu kullanın.

Bir IAP'nin fiyat çizelgesi olmadığında, `iap info` ve `iap pricing show` komutları uyarı verir; aynı durum `apps review preflight` komutunda da gönderim için engelleyici olarak işaretlenir.

## Bölge erişilebilirliği

Her IAP'nin uygulamadan bağımsız kendi bölge erişilebilirliği vardır. Varsayılan olarak bir IAP, uygulamasının bölgelerini devralır; `iap availability` ile değişiklik yaptığınızda IAP'ye özel bir liste oluşur.

```bash
# Mevcut IAP bölgelerini görüntüle
ascelerate iap availability <bundle-id> <product-id>

# Bölge listesini düzenle (toplu POST listenin tamamını değiştirir)
ascelerate iap availability <bundle-id> <product-id> --add CHN,RUS
ascelerate iap availability <bundle-id> <product-id> --remove ITA
ascelerate iap availability <bundle-id> <product-id> --available-in-new-territories true
```

## Teklif kodları

Teklif kodları IAP üzerinde tek seferlik indirim sağlayan kodlardır. Aynı teklif kodu kaynağı altında iki türde gelir:

- **Tek kullanımlık kodlar**: Apple, asenkron olarak N adet benzersiz kod üretir. Her biri yalnızca bir kez kullanılabilir.
- **Özel kodlar**: geliştirici tarafından sağlanan dize (örn. `PROMO2026`), N kez kullanılabilir.

```bash
# Bir IAP'deki tüm teklif kodlarını listele
ascelerate iap offer-code list <bundle-id> <product-id>

# Bir teklif kodunun detaylarını ve kod toplamlarını görüntüle
ascelerate iap offer-code info <bundle-id> <product-id> <offer-code-id>

# İndirimli fiyatlı bir teklif kodu oluştur (tüm bölgeler için otomatik eşitlenmiş)
ascelerate iap offer-code create <bundle-id> <product-id> \
  --name "Launch Promo" \
  --eligibility NON_SPENDER,ACTIVE_SPENDER \
  --price 0.99 --territory USA --equalize-all-territories

# Etkinleştir veya devre dışı bırak
ascelerate iap offer-code toggle <bundle-id> <product-id> <offer-code-id> --active true

# Tek kullanımlık kod yığını oluştur (kodlar asenkron olarak üretilir)
ascelerate iap offer-code gen-codes <bundle-id> <product-id> <offer-code-id> \
  --count 100 --expires 2026-12-31

# Üretim tamamlandıktan sonra gerçek kod değerlerini al
ascelerate iap offer-code view-codes <one-time-use-batch-id> --output codes.txt

# Geliştirici tanımlı özel kod ekle
ascelerate iap offer-code add-custom-codes <bundle-id> <product-id> <offer-code-id> \
  --code PROMO2026 --count 1000 --expires 2026-12-31
```

IAP teklif kodları için müşteri uygunluk değerleri: `NON_SPENDER`, `ACTIVE_SPENDER`, `CHURNED_SPENDER`.

## Tanıtım görselleri

App Store'da IAP'nin yanında gösterilen tanıtım görsellerini yükleyin.

```bash
ascelerate iap images list <bundle-id> <product-id>
ascelerate iap images upload <bundle-id> <product-id> ./hero.png
ascelerate iap images delete <bundle-id> <product-id> <image-id>
```

Yüklemeler Apple'ın 3 adımlı akışını kullanır: `fileSize` + `fileName` ile rezerve et, dosya parçalarını imzalı URL'lere PUT et, ardından dosyanın MD5'i ile PATCH ederek tamamla. CLI tek bir `upload` çağrısında üç adımı da yönetir.

## App Review ekran görüntüsü

Her IAP en fazla bir App Review ekran görüntüsüne sahip olabilir (Apple'ın inceleme ekibine gösterilir). Yükleme mevcut olanı değiştirir.

```bash
ascelerate iap review-screenshot view <bundle-id> <product-id>
ascelerate iap review-screenshot upload <bundle-id> <product-id> ./review.png
ascelerate iap review-screenshot delete <bundle-id> <product-id>
```
