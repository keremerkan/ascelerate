---
sidebar_position: 2
title: Yapılandırma
---

# Yapılandırma

## 1. API Anahtarı Oluşturma

[App Store Connect > Users and Access > Integrations > App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) sayfasına gidin ve yeni bir anahtar oluşturun. `.p8` özel anahtar dosyasını indirin.

## 2. Yapılandırma

```bash
ascelerate configure
```

Bu komut **Key ID**, **Issuer ID** ve `.p8` dosyanızın yolunu soracaktır. Özel anahtar, sıkı dosya izinleriyle (yalnızca sahip erişimi) `~/.ascelerate/` dizinine kopyalanır.

Yapılandırma `~/.ascelerate/config.json` dosyasında saklanır:

```json
{
    "keyId": "KEY_ID",
    "issuerId": "ISSUER_ID",
    "privateKeyPath": "/Users/.../.ascelerate/AuthKey_XXXXXXXXXX.p8"
}
```

## 3. Doğrulama

Her şeyin çalıştığını doğrulamak için hızlıca bir komut çalıştırın:

```bash
ascelerate apps list
```

Kimlik bilgileriniz doğruysa, tüm uygulamalarınızın listesini göreceksiniz.

## İstek kotası

App Store Connect API'nin saatlik 3600 istek kotası vardır (kayan pencere). Mevcut kullanımınızı istediğiniz zaman kontrol edebilirsiniz:

```bash
ascelerate rate-limit
```

```
Hourly limit: 3600 requests (rolling window)
Used:         57
Remaining:    3543 (98%)
```
