---
sidebar_position: 19
title: Öne Çıkarılma Adaylıkları
---

# Öne Çıkarılma Adaylıkları

Yaklaşan bir lansmanı, büyük bir güncellemeyi veya yeni içeriği Apple'ın editör ekibine bildirin; böylece ekip bunu App Store'da öne çıkarmayı değerlendirebilir.

## Listeleme

```bash
ascelerate nominations
ascelerate nominations --app <bundle-id> --state draft
```

Taslak, gönderilmiş ve arşivlenmiş adaylıkları (ya da `--state` ile yalnızca tek bir durumdakileri) listeler. Makine tarafından okunabilir çıktı için `--json` ekleyin.

## Oluşturma

```bash
ascelerate nominations create --app <bundle-id> --type enhancements --name "Version 5" \
  --description "What's new and why it matters to users" --publish-start 2026-11-01 \
  --devices iphone,ipad --locales en-US,tr-TR
```

| Seçenek | Açıklama |
|---|---|
| `--app` | Uygulama (birden fazla uygulamayı kapsayan bir adaylık için `--app` seçeneğini tekrarlayın) |
| `--type` | `launch`, `enhancements` veya `new-content` |
| `--name`, `--description` | Adaylığın konusu; Apple'ın editörlerine yönelik olarak yazılır |
| `--publish-start` | Yayın tarihi (`yyyy-MM-dd` veya ISO 8601); sınırlı süreli içerik için `--publish-end` |
| `--devices` | Cihaz aileleri: `iphone`, `ipad`, `mac`, `apple-tv`, `apple-watch`, `vision` |
| `--locales` | Sürümün yerelleştirildiği yerel ayarlar |
| `--territories` | İlk olarak yayınlanacağı bölgeler (varsayılan: tümü) |
| `--materials` | Destekleyici materyallerin (basın kiti, video) virgülle ayrılmış bağlantıları |
| `--notes` | Apple için notlar |
| `--pre-order` | Uygulama ön siparişe açıktır |
| `--submit` | Taslak olarak kaydetmek yerine hemen gönderir |

`--submit` verilmezse adaylık, gözden geçirip değiştirebileceğiniz bir taslak olarak kaydedilir.

## Güncelleme, gönderme, arşivleme ve silme

```bash
ascelerate nominations update <id> --publish-start 2026-11-08
ascelerate nominations submit <id>
ascelerate nominations archive <id>
ascelerate nominations delete <id>
```

`update` bir taslağı değiştirir; adaylık kimliklerini `nominations` çıktısında bulabilirsiniz. Öne çıkarma kararı Apple'ın editörlerine aittir; bu yüzden adaylığı yayın tarihinden epey önce oluşturun.
