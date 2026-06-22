---
sidebar_position: 15
title: Custom Product Pages
---

# Custom Product Pages

Create and manage custom product pages — alternate versions of your App Store product page with their own promotional text and screenshots, each reachable via a unique URL. Pages are referenced by **name** or ID.

## List & inspect

```bash
ascelerate product-pages list <bundle-id>
ascelerate product-pages info <bundle-id> <name-or-id>
```

`list` shows each page's name, visibility, shareable App Store URL (including its `ppid`), and ID. `info` adds the page's versions and their localizations.

## Create

```bash
ascelerate product-pages create <bundle-id> --name "Summer Campaign" --locale en-US --promotional-text "Limited-time offer"
```

The App Store Connect API requires a page to be created together with a first version and at least one localization, so `--locale` is required. Add more locales afterward with `product-pages localizations import`.

## Update & delete

```bash
ascelerate product-pages update <bundle-id> "Summer Campaign" --name "Summer 2026" --visible false
ascelerate product-pages delete <bundle-id> "Summer Campaign"
```

`--visible` toggles whether the page is live on the App Store.

## Localizations

```bash
ascelerate product-pages localizations view <bundle-id> "Summer 2026"
ascelerate product-pages localizations export <bundle-id> "Summer 2026"
ascelerate product-pages localizations import <bundle-id> "Summer 2026" --file page-locales.json
```

Each localization carries `promotionalText`, applied to the page's editable version.

```json
{
  "en-US": { "promotionalText": "Limited-time offer" },
  "fr-FR": { "promotionalText": "Offre à durée limitée" }
}
```
