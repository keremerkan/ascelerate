---
sidebar_position: 5
title: App-Info & Kategorien
---

# App-Info & Kategorien

## Anzeigen

```bash
# App-Info, Kategorien und sprachspezifische Metadaten anzeigen
ascelerate apps app-info view <bundle-id>

# Alle verfügbaren Kategorie-IDs auflisten (keine Bundle ID erforderlich)
ascelerate apps app-info view --list-categories
```

## Aktualisieren

```bash
# Lokalisierungsfelder für eine einzelne Sprache aktualisieren
ascelerate apps app-info update <bundle-id> --name "My App" --subtitle "Best app ever"
ascelerate apps app-info update <bundle-id> --locale de-DE --name "Meine App"

# Kategorien aktualisieren (kann mit Lokalisierungs-Flags kombiniert werden)
ascelerate apps app-info update <bundle-id> --primary-category UTILITIES
ascelerate apps app-info update <bundle-id> --primary-category GAMES_ACTION --secondary-category ENTERTAINMENT
```

## Exportieren

```bash
ascelerate apps app-info export <bundle-id>
ascelerate apps app-info export <bundle-id> --output app-infos.json
```

## Importieren

```bash
ascelerate apps app-info import <bundle-id> --file app-infos.json
```

## JSON-Format

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

Nur die vorhandenen Felder werden aktualisiert — fehlende Felder bleiben unverändert.

:::note
Die Befehle `app-info update` und `app-info import` erfordern, dass die AppInfo in einem bearbeitbaren Zustand ist (`PREPARE_FOR_SUBMISSION` oder `WAITING_FOR_REVIEW`).
:::

## Altersfreigabe

```bash
# Altersfreigabe-Erklärung anzeigen
ascelerate apps app-info age-rating <bundle-id>

# Altersfreigabe als JSON exportieren
ascelerate apps app-info age-rating export <bundle-id>

# Altersfreigabe aus einer JSON-Datei aktualisieren
ascelerate apps app-info age-rating import <bundle-id> --file age-rating.json
```

Die JSON-Datei verwendet die gleichen Feldnamen wie die API. Nur die in der Datei vorhandenen Felder werden aktualisiert:

```json
{
  "isAdvertising": false,
  "isUserGeneratedContent": true,
  "violenceCartoonOrFantasy": "INFREQUENT_OR_MILD",
  "alcoholTobaccoOrDrugUseOrReferences": "NONE"
}
```

Intensitätsfelder akzeptieren: `NONE`, `INFREQUENT_OR_MILD`, `FREQUENT_OR_INTENSE`. Boolesche Felder akzeptieren `true`/`false`.

## Routing App Coverage

```bash
# Aktuellen Routing-Coverage-Status anzeigen
ascelerate apps routing-coverage <bundle-id>

# Eine .geojson-Datei hochladen
ascelerate apps routing-coverage <bundle-id> --file coverage.geojson
```
