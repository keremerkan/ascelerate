---
sidebar_position: 3
title: Lokalisierungen
---

# Lokalisierungen

Verwalten Sie App Store-Versionslokalisierungen (Beschreibung, Neuigkeiten, Schlüsselwörter usw.).

## Anzeigen

```bash
ascelerate apps localizations view <bundle-id>
ascelerate apps localizations view <bundle-id> --version 2.1.0 --locale en-US
```

## Exportieren

```bash
ascelerate apps localizations export <bundle-id>
ascelerate apps localizations export <bundle-id> --version 2.1.0 --output my-localizations.json
```

## Einzelne Sprache aktualisieren

```bash
ascelerate apps localizations update <bundle-id> --whats-new "Bug fixes" --locale en-US
```

## Massenaktualisierung aus JSON

```bash
ascelerate apps localizations import <bundle-id> --file localizations.json
```

## JSON-Format

Das gleiche Format wird sowohl für den Export als auch für den Import verwendet:

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

Nur die im JSON vorhandenen Felder werden aktualisiert — fehlende Felder bleiben unverändert.

:::note
Nur Versionen in bearbeitbaren Zuständen (`PREPARE_FOR_SUBMISSION` oder `WAITING_FOR_REVIEW`) akzeptieren Lokalisierungsaktualisierungen — mit Ausnahme von `promotionalText`, das in jedem Zustand aktualisiert werden kann.
:::
