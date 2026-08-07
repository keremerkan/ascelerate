---
sidebar_position: 14
title: Uygulama İçi Etkinlikler
---

# Uygulama İçi Etkinlikler

Uygulama içi etkinlikler oluşturun ve yönetin: App Store ürün sayfanızda ve aramada görünen, zamana duyarlı etkinlikler (canlı etkinlikler, galalar, yarışmalar, özel teklifler). Etkinliklere **referans adı** veya kimlikleriyle başvurulur.

## Listeleme ve inceleme

```bash
ascelerate events list <bundle-id>
ascelerate events list <bundle-id> --state PUBLISHED
ascelerate events info <bundle-id> <reference-name-or-id>
```

`info`; etkinliğin özniteliklerini, bölgeye özel programlarını ve yerelleştirme özetini gösterir.

## Oluşturma, güncelleme, silme

```bash
ascelerate events create <bundle-id> --reference-name "summer-sale" --badge SPECIAL_EVENT --purpose ATTRACT_NEW_USERS --priority HIGH

# Başlangıç programıyla birlikte
ascelerate events create <bundle-id> --reference-name "launch" \
  --territories USA,GBR --publish-start 2026-07-01 --event-start 2026-07-05 --event-end 2026-07-12

ascelerate events update <bundle-id> summer-sale --priority NORMAL --badge NONE
ascelerate events delete <bundle-id> summer-sale
```

- **Rozetler:** `LIVE_EVENT`, `PREMIERE`, `CHALLENGE`, `COMPETITION`, `NEW_SEASON`, `MAJOR_UPDATE`, `SPECIAL_EVENT`. Rozeti kaldırmak için `update` komutuna `--badge NONE` verin.
- **Amaçlar:** `APPROPRIATE_FOR_ALL_USERS`, `ATTRACT_NEW_USERS`, `KEEP_ACTIVE_USERS_INFORMED`, `BRING_BACK_LAPSED_USERS`.
- **Öncelik:** `HIGH` veya `NORMAL`.
- **Program tarihleri** (`--publish-start`, `--event-start`, `--event-end`) ISO8601 (`2026-07-01T09:00:00Z`) veya `yyyy-MM-dd` (UTC gece yarısı) biçimini kabul eder. Tüm bölgeler için programlamak istiyorsanız `--territories` seçeneğini atlayın.

## Yerelleştirmeler

```bash
ascelerate events localizations view <bundle-id> summer-sale
ascelerate events localizations export <bundle-id> summer-sale
ascelerate events localizations import <bundle-id> summer-sale --file event-locales.json
```

Her yerelleştirme `name`, `shortDescription` ve `longDescription` alanlarını taşır. Yerel ayarlar, uygulamanın yapılandırılmış yerel ayarlarıyla eşleşmelidir (örn. `tr-TR` değil `tr`).

```json
{
  "en-US": {
    "name": "Yaz İndirimi",
    "shortDescription": "Büyük yaz indirimleri",
    "longDescription": "Sınırlı süreli indirimler için yaz etkinliğimize katılın."
  }
}
```

## Medya

Yerelleştirme başına etkinlik kartı ve etkinlik ayrıntıları sayfası ekran görüntüleri (`.png`/`.jpg`) ve video klipleri (`.mp4`/`.mov`).

```bash
ascelerate events media list <bundle-id> summer-sale
ascelerate events media upload <bundle-id> summer-sale --locale en-US --asset-type EVENT_CARD card.png
ascelerate events media upload <bundle-id> summer-sale --locale en-US --asset-type EVENT_DETAILS_PAGE clip.mp4 --preview-frame 00:00:03
ascelerate events media delete <bundle-id> summer-sale <media-id>
```

Varlık türleri `EVENT_CARD` ve `EVENT_DETAILS_PAGE`'dir. Dosya türü, içeriğin ekran görüntüsü mü yoksa video klip olarak mı yükleneceğini belirler; `--preview-frame` bir videonun önizleme karesi zaman kodunu ayarlar.
