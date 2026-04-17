---
sidebar_position: 7
title: Abonelikler
---

# Abonelikler

## Listeleme ve inceleme

```bash
ascelerate sub groups <bundle-id>
ascelerate sub list <bundle-id>
ascelerate sub info <bundle-id> <product-id>
```

## Abonelik oluşturma, güncelleme ve silme

```bash
ascelerate sub create <bundle-id> --name "Monthly" --product-id <product-id> --period ONE_MONTH --group-id <group-id>
ascelerate sub update <bundle-id> <product-id> --name "Monthly Plan"
ascelerate sub delete <bundle-id> <product-id>
```

## Abonelik grupları

```bash
ascelerate sub create-group <bundle-id> --name "Premium"
ascelerate sub update-group <bundle-id> --name "Premium Plus"
ascelerate sub delete-group <bundle-id>
```

## İncelemeye gönderme

```bash
ascelerate sub submit <bundle-id> <product-id>
```

## Abonelik yerelleştirmeleri

```bash
ascelerate sub localizations view <bundle-id> <product-id>
ascelerate sub localizations export <bundle-id> <product-id>
ascelerate sub localizations import <bundle-id> <product-id> --file sub-de.json
```

## Grup yerelleştirmeleri

```bash
ascelerate sub group-localizations view <bundle-id>
ascelerate sub group-localizations export <bundle-id>
ascelerate sub group-localizations import <bundle-id> --file group-de.json
```

İçe aktarma komutları eksik locale'leri onay ile otomatik olarak oluşturur, böylece App Store Connect'i ziyaret etmeden yeni diller ekleyebilirsiniz.

## Fiyatlandırma

Abonelik fiyatlandırması bölgeye özeldir. IAP'lerde olduğu gibi otomatik eşitleme kavramı yoktur — fiyatlamak istediğiniz her bölgenin kendi kaydı olmalıdır. CLI ya tek bir bölgeyi ayarlar ya da Apple'ın yerel para birimi kademe karşılıklarını kullanarak fiyatı tüm bölgelere yayar.

```bash
# Mevcut bölgeye özel fiyatları göster (yoksa uyarır)
ascelerate sub pricing show <bundle-id> <product-id>

# Bir bölgedeki mevcut fiyat kademelerini listele
ascelerate sub pricing tiers <bundle-id> <product-id> --territory USA

# Tek bir bölge için fiyat ayarla
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --territory USA

# Tüm bölgelere fiyatı yay (her bölge için bir POST)
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --equalize-all-territories
```

### Fiyat değişiklikleri ve mevcut aboneler

Apple, fiyat değişikliklerini değişikliğin yönüne göre mevcut aboneler için farklı şekilde uygular. `sub pricing set` komutu her etkilenen bölgenin mevcut fiyatını alır, değişikliği sınıflandırır ve doğru davranışı uygular:

- **Düşürme**: mevcut aboneler otomatik olarak düşük fiyata geçer. Etkileşimli çalıştırmalarda uyarı ile birlikte sorulur. `--yes` modunda, gelir etkisini onaylamak için `--confirm-decrease` eklemeniz gerekir — sadece `--yes` yeterli değildir.
- **Artış**: mevcut abonelerle nasıl başa çıkılacağını açıkça seçmeniz gerekir. Aşağıdakilerden biri ayarlanmadığı sürece komut hata verir:
  - `--preserve-current` — mevcut aboneleri eski fiyatlarında tutar
  - `--no-preserve-current` — Apple'ın bildirim süresinden sonra yeni fiyatı mevcut abonelere uygular
- **Yeni bölge** (mevcut fiyat yok): değerlendirilecek mevcut abone yok; bayraklar isteğe bağlıdır.
- **Değişiklik yok**: sessizce atlanır.

`--equalize-all-territories` için aynı kurallar toplu olarak uygulanır. Yayılan bölgelerden herhangi biri artış ise, korunma bayrağı hepsi için gereklidir. Herhangi biri `--yes` modunda düşüş ise, `--confirm-decrease` gereklidir.

```bash
# Standart küresel fiyat artışı: tüm bölgelerde $4.99 → $9.99,
# mevcut aboneleri eski fiyatta tut
ascelerate sub pricing set myapp com.example.monthly \
  --price 9.99 --territory USA --equalize-all-territories \
  --preserve-current
```
