---
sidebar_position: 10
title: Bundle ID'ler
---

# Bundle ID'ler

Tüm bundle ID komutları interaktif modu destekler -- argümanlar isteğe bağlıdır.

## Listeleme

```bash
asc bundle-ids list
asc bundle-ids list --platform IOS
```

## Detayları görüntüleme

```bash
# İnteraktif seçici
asc bundle-ids info

# Tanımlayıcı ile
asc bundle-ids info com.example.MyApp
```

## Kayıt etme

```bash
# İnteraktif sorular
asc bundle-ids register

# İnteraktif olmayan
asc bundle-ids register --name "My App" --identifier com.example.MyApp --platform IOS
```

## Yeniden adlandırma

```bash
asc bundle-ids update
asc bundle-ids update com.example.MyApp --name "My Renamed App"
```

Tanımlayıcının kendisi değiştirilemez -- yalnızca ad değiştirilebilir.

## Silme

```bash
asc bundle-ids delete
asc bundle-ids delete com.example.MyApp
```

## Yetenekler

### Etkinleştirme

```bash
# İnteraktif seçiciler (yalnızca henüz etkinleştirilmemiş yetenekleri gösterir)
asc bundle-ids enable-capability

# İnteraktif olmayan
asc bundle-ids enable-capability com.example.MyApp --type PUSH_NOTIFICATIONS
```

### Devre dışı bırakma

```bash
# Şu anda etkinleştirilmiş yeteneklerden seçer
asc bundle-ids disable-capability
asc bundle-ids disable-capability com.example.MyApp
```

Bir yeteneği etkinleştirdikten veya devre dışı bıraktıktan sonra, o bundle ID için provisioning profilleri varsa, komut bunları yeniden oluşturmayı teklif eder (değişikliklerin etkili olması için gereklidir).

:::note
Bazı yetenekler (ör. App Groups, iCloud, Associated Domains) etkinleştirildikten sonra [Apple Developer portalında](https://developer.apple.com/account/resources) ek yapılandırma gerektirir.
:::
