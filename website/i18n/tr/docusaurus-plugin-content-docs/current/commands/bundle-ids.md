---
sidebar_position: 10
title: Bundle ID'ler
---

# Bundle ID'ler

Tüm bundle ID komutları interaktif modu destekler -- argümanlar isteğe bağlıdır.

## Listeleme

```bash
ascelerate bundle-ids list
ascelerate bundle-ids list --platform IOS
```

## Detayları görüntüleme

```bash
# İnteraktif seçici
ascelerate bundle-ids info

# Tanımlayıcı ile
ascelerate bundle-ids info com.example.MyApp
```

## Kayıt etme

```bash
# İnteraktif sorular
ascelerate bundle-ids register

# İnteraktif olmayan
ascelerate bundle-ids register --name "My App" --identifier com.example.MyApp --platform IOS
```

## Yeniden adlandırma

```bash
ascelerate bundle-ids update
ascelerate bundle-ids update com.example.MyApp --name "My Renamed App"
```

Tanımlayıcının kendisi değiştirilemez -- yalnızca ad değiştirilebilir.

## Silme

```bash
ascelerate bundle-ids delete
ascelerate bundle-ids delete com.example.MyApp
```

## Yetenekler

### Etkinleştirme

```bash
# İnteraktif seçiciler (yalnızca henüz etkinleştirilmemiş yetenekleri gösterir)
ascelerate bundle-ids enable-capability

# İnteraktif olmayan
ascelerate bundle-ids enable-capability com.example.MyApp --type PUSH_NOTIFICATIONS
```

### Devre dışı bırakma

```bash
# Şu anda etkinleştirilmiş yeteneklerden seçer
ascelerate bundle-ids disable-capability
ascelerate bundle-ids disable-capability com.example.MyApp
```

Bir yeteneği etkinleştirdikten veya devre dışı bıraktıktan sonra, o bundle ID için provisioning profilleri varsa, komut bunları yeniden oluşturmayı teklif eder (değişikliklerin etkili olması için gereklidir).

:::note
Bazı yetenekler (ör. App Groups, iCloud, Associated Domains) etkinleştirildikten sonra [Apple Developer portalında](https://developer.apple.com/account/resources) ek yapılandırma gerektirir.
:::
