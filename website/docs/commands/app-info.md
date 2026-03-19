---
sidebar_position: 5
title: App Info & Categories
---

# App Info & Categories

## View

```bash
# View app info, categories, and per-locale metadata
ascelerate apps app-info view <bundle-id>

# List all available category IDs (no bundle ID needed)
ascelerate apps app-info view --list-categories
```

## Update

```bash
# Update localization fields for a single locale
ascelerate apps app-info update <bundle-id> --name "My App" --subtitle "Best app ever"
ascelerate apps app-info update <bundle-id> --locale de-DE --name "Meine App"

# Update categories (can combine with localization flags)
ascelerate apps app-info update <bundle-id> --primary-category UTILITIES
ascelerate apps app-info update <bundle-id> --primary-category GAMES_ACTION --secondary-category ENTERTAINMENT
```

## Export

```bash
ascelerate apps app-info export <bundle-id>
ascelerate apps app-info export <bundle-id> --output app-infos.json
```

## Import

```bash
ascelerate apps app-info import <bundle-id> --file app-infos.json
```

## JSON format

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

Only fields present get updated — omitted fields are left unchanged.

:::note
The `app-info update` and `app-info import` commands require the AppInfo to be in an editable state (`PREPARE_FOR_SUBMISSION` or `WAITING_FOR_REVIEW`).
:::

## Age rating

```bash
# View age rating declaration
ascelerate apps app-info age-rating <bundle-id>

# Export age rating to JSON
ascelerate apps app-info age-rating export <bundle-id>

# Update age ratings from a JSON file
ascelerate apps app-info age-rating import <bundle-id> --file age-rating.json
```

The JSON file uses the same field names as the API. Only fields present in the file are updated:

```json
{
  "isAdvertising": false,
  "isUserGeneratedContent": true,
  "violenceCartoonOrFantasy": "INFREQUENT_OR_MILD",
  "alcoholTobaccoOrDrugUseOrReferences": "NONE"
}
```

Intensity fields accept: `NONE`, `INFREQUENT_OR_MILD`, `FREQUENT_OR_INTENSE`. Boolean fields accept `true`/`false`.

## Routing app coverage

```bash
# View current routing coverage status
ascelerate apps routing-coverage <bundle-id>

# Upload a .geojson file
ascelerate apps routing-coverage <bundle-id> --file coverage.geojson
```
