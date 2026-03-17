---
sidebar_position: 3
title: Localizations
---

# Localizations

Manage App Store version localizations (description, what's new, keywords, etc.).

## View

```bash
ascelerate apps localizations view <bundle-id>
ascelerate apps localizations view <bundle-id> --version 2.1.0 --locale en-US
```

## Export

```bash
ascelerate apps localizations export <bundle-id>
ascelerate apps localizations export <bundle-id> --version 2.1.0 --output my-localizations.json
```

## Update a single locale

```bash
ascelerate apps localizations update <bundle-id> --whats-new "Bug fixes" --locale en-US
```

## Bulk update from JSON

```bash
ascelerate apps localizations import <bundle-id> --file localizations.json
```

## JSON format

The same format is used for both export and import:

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

Only fields present in the JSON are updated — omitted fields are left unchanged.

:::note
Only versions in editable states (`PREPARE_FOR_SUBMISSION` or `WAITING_FOR_REVIEW`) accept localization updates — except `promotionalText`, which can be updated in any state.
:::
