---
sidebar_position: 3
title: Yerelleştirmeler
---

# Yerelleştirmeler

App Store sürüm yerelleştirmelerini (açıklama, yenilikler, anahtar kelimeler vb.) yönet.

## Görüntüleme

```bash
asc apps localizations view <bundle-id>
asc apps localizations view <bundle-id> --version 2.1.0 --locale en-US
```

## Dışa aktarma

```bash
asc apps localizations export <bundle-id>
asc apps localizations export <bundle-id> --version 2.1.0 --output my-localizations.json
```

## Tek bir locale'i güncelleme

```bash
asc apps localizations update <bundle-id> --whats-new "Bug fixes" --locale en-US
```

## JSON'dan toplu güncelleme

```bash
asc apps localizations import <bundle-id> --file localizations.json
```

## JSON formatı

Hem dışa aktarma hem de içe aktarma için aynı format kullanılır:

```json
{
  "en-US": {
    "description": "My app description.\n\nSecond paragraph.",
    "whatsNew": "- Bug fixes\n- New dark mode",
    "keywords": "productivity,tools,utility",
    "promotionalText": "Try our new features!",
    "marketingURL": "https://example.com",
    "supportURL": "https://example.com/support"
  },
  "de-DE": {
    "whatsNew": "- Fehlerbehebungen\n- Neuer Dunkelmodus"
  }
}
```

Yalnızca JSON'da bulunan alanlar güncellenir -- belirtilmeyen alanlar değiştirilmez.

:::note
Yalnızca düzenlenebilir durumdaki sürümler (`PREPARE_FOR_SUBMISSION` veya `WAITING_FOR_REVIEW`) yerelleştirme güncellemelerini kabul eder -- `promotionalText` hariç, bu her durumda güncellenebilir.
:::
