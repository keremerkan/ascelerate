---
sidebar_position: 3
title: Localisations
---

# Localisations

Gérez les localisations des versions App Store (description, nouveautés, mots-clés, etc.).

## Afficher

```bash
asc apps localizations view <bundle-id>
asc apps localizations view <bundle-id> --version 2.1.0 --locale en-US
```

## Exporter

```bash
asc apps localizations export <bundle-id>
asc apps localizations export <bundle-id> --version 2.1.0 --output my-localizations.json
```

## Mettre à jour une seule langue

```bash
asc apps localizations update <bundle-id> --whats-new "Bug fixes" --locale en-US
```

## Mise à jour en masse depuis un JSON

```bash
asc apps localizations import <bundle-id> --file localizations.json
```

## Format JSON

Le même format est utilisé pour l'export et l'import :

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

Seuls les champs présents dans le JSON sont mis à jour -- les champs omis restent inchangés.

:::note
Seules les versions dans un état modifiable (`PREPARE_FOR_SUBMISSION` ou `WAITING_FOR_REVIEW`) acceptent les mises à jour de localisation -- à l'exception de `promotionalText`, qui peut être mis à jour quel que soit l'état.
:::
