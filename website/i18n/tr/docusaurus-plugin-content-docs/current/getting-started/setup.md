---
sidebar_position: 2
title: Yapılandırma
---

# Yapılandırma

## 1. API Anahtarı Oluşturma

[App Store Connect > Users and Access > Integrations > App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) sayfasına gidin ve yeni bir anahtar oluşturun. `.p8` özel anahtar dosyasını indirin.

## 2. Yapılandırma

```bash
asc configure
```

Bu komut **Key ID**, **Issuer ID** ve `.p8` dosyanızın yolunu soracaktır. Özel anahtar, sıkı dosya izinleriyle (yalnızca sahip erişimi) `~/.asc/` dizinine kopyalanır.

Yapılandırma `~/.asc/config.json` dosyasında saklanır:

```json
{
    "keyId": "KEY_ID",
    "issuerId": "ISSUER_ID",
    "privateKeyPath": "/Users/.../.asc/AuthKey_XXXXXXXXXX.p8"
}
```

## 3. Doğrulama

Her şeyin çalıştığını doğrulamak için hızlıca bir komut çalıştırın:

```bash
asc apps list
```

Kimlik bilgileriniz doğruysa, tüm uygulamalarınızın listesini göreceksiniz.

## İstek kotası

App Store Connect API'nin saatlik 3600 istek kotası vardır (kayan pencere). Mevcut kullanımınızı istediğiniz zaman kontrol edebilirsiniz:

```bash
asc rate-limit
```

```
Hourly limit: 3600 requests (rolling window)
Used:         57
Remaining:    3543 (98%)
```
