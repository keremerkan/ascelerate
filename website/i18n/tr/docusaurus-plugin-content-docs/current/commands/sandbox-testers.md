---
sidebar_position: 7
title: Sandbox Test Kullanıcıları
---

# Sandbox Test Kullanıcıları

Sandbox'ta uygulama içi satın almaları ve abonelikleri satın alan Apple Hesapları. Bir test kullanıcısı **Apple Hesabı** (e-posta adresi) veya kimliğiyle belirtilir. Test kullanıcısı oluşturma ve silme App Store Connect'te (Kullanıcılar ve Erişim > Sandbox) yapılır; API bunu sunmaz.

## Listeleme

```bash
ascelerate sandbox-testers
ascelerate sandbox-testers --json
```

Her test kullanıcısının Apple Hesabı, adı, mağazası, aboneliklerinin ne sıklıkla yenilendiği, satın almalarının kesintiye uğratılıp uğratılmadığı ve Apple Pay kullanıp kullanamadığı.

## Değiştirme

```bash
ascelerate sandbox-testers update tester@example.com --renewal-rate 3m
ascelerate sandbox-testers update tester@example.com --territory DEU --interrupt-purchases true
```

`--territory` mağazayı belirler (üç harfli bölge kodu). `--interrupt-purchases`, koşulları kabul etme veya ödeme bilgilerini güncelleme gibi ek bir adım için satın almaları durdurur. `--renewal-rate`, test kullanıcısı için aylık bir aboneliğin ne sıklıkla yenileneceğini belirler: `1h`, `30m`, `15m`, `5m` veya `3m` (diğer süreler orantılı olarak yenilenir). Komut değişiklikleri listeler ve önce onay ister.

## Satın Alma Geçmişini Temizleme

```bash
ascelerate sandbox-testers clear-history tester@example.com other@example.com
ascelerate sandbox-testers clear-history --all
```

Test kullanıcılarının uygulama içi satın almalarını ve aboneliklerini unutturur; böylece baştan yeniden satın alınabilirler. Önce onay ister.
