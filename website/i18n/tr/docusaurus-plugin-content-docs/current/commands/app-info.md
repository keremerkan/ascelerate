---
sidebar_position: 5
title: Uygulama Bilgileri ve Kategoriler
---

# Uygulama Bilgileri ve Kategoriler

## Görüntüleme

```bash
# Uygulama bilgilerini, kategorileri ve locale bazlı meta verileri görüntüleyin
ascelerate apps app-info view <bundle-id>

# Tüm kullanılabilir kategori ID'lerini listeleyin (bundle ID gerekmez)
ascelerate apps app-info view --list-categories
```

## Güncelleme

```bash
# Tek bir locale için yerelleştirme alanlarını güncelleyin
ascelerate apps app-info update <bundle-id> --name "My App" --subtitle "Best app ever"
ascelerate apps app-info update <bundle-id> --locale de-DE --name "Meine App"

# Kategorileri güncelleyin (yerelleştirme flag'leriyle birleştirilebilir)
ascelerate apps app-info update <bundle-id> --primary-category UTILITIES
ascelerate apps app-info update <bundle-id> --primary-category GAMES_ACTION --secondary-category ENTERTAINMENT
```

## Dışa aktarma

```bash
ascelerate apps app-info export <bundle-id>
ascelerate apps app-info export <bundle-id> --output app-infos.json
```

## İçe aktarma

```bash
ascelerate apps app-info import <bundle-id> --file app-infos.json
```

## JSON formatı

```json
{
  "en-US": {
    "name": "My App",
    "subtitle": "Best app ever",
    "privacyPolicyURL": "https://example.com/privacy",
    "privacyChoicesURL": "https://example.com/choices"
  }
}
```

Yalnızca mevcut alanlar güncellenir -- belirtilmeyen alanlar değiştirilmez.

:::note
`app-info update` ve `app-info import` komutları, AppInfo'nun düzenlenebilir durumda olmasını gerektirir (`PREPARE_FOR_SUBMISSION` veya `WAITING_FOR_REVIEW`).
:::

## Yaş derecelendirmesi

```bash
# Yaş derecelendirme beyanını görüntüleyin
ascelerate apps app-info age-rating <bundle-id>

# Yaş derecelendirmesini JSON olarak dışa aktarın
ascelerate apps app-info age-rating export <bundle-id>

# Yaş derecelendirmelerini bir JSON dosyasından güncelleyin
ascelerate apps app-info age-rating import <bundle-id> --file age-rating.json
```

JSON dosyası API ile aynı alan adlarını kullanır. Yalnızca dosyada bulunan alanlar güncellenir:

```json
{
  "isAdvertising": false,
  "isUserGeneratedContent": true,
  "violenceCartoonOrFantasy": "INFREQUENT_OR_MILD",
  "alcoholTobaccoOrDrugUseOrReferences": "NONE"
}
```

Yoğunluk alanları şu değerleri kabul eder: `NONE`, `INFREQUENT_OR_MILD`, `FREQUENT_OR_INTENSE`. Boolean alanlar `true`/`false` kabul eder.

## Routing app coverage

```bash
# Mevcut routing coverage durumunu görüntüleyin
ascelerate apps routing-coverage <bundle-id>

# Bir .geojson dosyası yükleyin
ascelerate apps routing-coverage <bundle-id> --file coverage.geojson
```
