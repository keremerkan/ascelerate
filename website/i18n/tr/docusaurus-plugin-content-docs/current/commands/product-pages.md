---
sidebar_position: 15
title: Özel Ürün Sayfaları
---

# Özel Ürün Sayfaları

Özel ürün sayfaları oluşturun ve yönetin: App Store ürün sayfanızın, her biri benzersiz bir URL üzerinden erişilebilen, kendi tanıtım metnine ve ekran görüntülerine sahip alternatif sürümleri. Sayfalara **ad** veya kimlikleriyle başvurulur.

## Listeleme ve inceleme

```bash
ascelerate product-pages list <bundle-id>
ascelerate product-pages info <bundle-id> <name-or-id>
```

`list`; her sayfanın adını, görünürlüğünü, paylaşılabilir App Store URL'sini (`ppid` dahil) ve kimliğini gösterir. `info` ise sayfanın sürümlerini ve bunların yerelleştirmelerini ekler.

## Oluşturma

```bash
ascelerate product-pages create <bundle-id> --name "Summer Campaign" --locale en-US --promotional-text "Sınırlı süreli teklif"
```

App Store Connect API'si, bir sayfanın ilk sürümü ve en az bir yerelleştirmesiyle birlikte oluşturulmasını gerektirir; bu yüzden `--locale` zorunludur. Daha fazla yerel ayarı sonradan `product-pages localizations import` ile ekleyin.

## Güncelleme ve silme

```bash
ascelerate product-pages update <bundle-id> "Summer Campaign" --name "Summer 2026" --visible false
ascelerate product-pages delete <bundle-id> "Summer Campaign"
```

`--visible`, sayfanın App Store'da yayında olup olmadığını değiştirir.

## Yerelleştirmeler

```bash
ascelerate product-pages localizations view <bundle-id> "Summer 2026"
ascelerate product-pages localizations export <bundle-id> "Summer 2026"
ascelerate product-pages localizations import <bundle-id> "Summer 2026" --file page-locales.json
```

Her yerelleştirme, sayfanın düzenlenebilir sürümüne uygulanan `promotionalText` alanını taşır.

```json
{
  "en-US": { "promotionalText": "Sınırlı süreli teklif" },
  "fr-FR": { "promotionalText": "Offre à durée limitée" }
}
```

## Ekran görüntüleri ve uygulama önizlemeleri

Yerel ayar başına ekran görüntüleri (`.png`/`.jpg`, görüntü türüne göre) ve uygulama önizlemeleri (`.mp4`/`.mov`, önizleme türüne göre). Set, ilk yüklemede otomatik olarak oluşturulur.

```bash
ascelerate product-pages media list <bundle-id> "Summer 2026"
ascelerate product-pages media upload <bundle-id> "Summer 2026" --locale en-US --display-type APP_IPHONE_67 screenshot.png
ascelerate product-pages media upload <bundle-id> "Summer 2026" --locale en-US --preview-type APP_IPHONE_67 preview.mp4 --preview-frame 00:00:03
ascelerate product-pages media delete <bundle-id> "Summer 2026" <media-id>
```

Dosya türü, içeriğin ekran görüntüsü mü yoksa uygulama önizlemesi olarak mı yükleneceğini belirler. Görüntü ve önizleme türleri standart App Store cihaz tanımlayıcılarını kullanır (örn. `APP_IPHONE_67`, `APP_IPAD_PRO_3GEN_129`).
