---
sidebar_position: 5
title: App-Info & Kategorien
---

# App-Info & Kategorien

## Anzeigen

```bash
# App-Info, Kategorien und sprachspezifische Metadaten anzeigen
asc apps app-info view <bundle-id>

# Alle verfügbaren Kategorie-IDs auflisten (keine Bundle ID erforderlich)
asc apps app-info view --list-categories
```

## Aktualisieren

```bash
# Lokalisierungsfelder für eine einzelne Sprache aktualisieren
asc apps app-info update <bundle-id> --name "My App" --subtitle "Best app ever"
asc apps app-info update <bundle-id> --locale de-DE --name "Meine App"

# Kategorien aktualisieren (kann mit Lokalisierungs-Flags kombiniert werden)
asc apps app-info update <bundle-id> --primary-category UTILITIES
asc apps app-info update <bundle-id> --primary-category GAMES_ACTION --secondary-category ENTERTAINMENT
```

## Exportieren

```bash
asc apps app-info export <bundle-id>
asc apps app-info export <bundle-id> --output app-infos.json
```

## Importieren

```bash
asc apps app-info import <bundle-id> --file app-infos.json
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
# Altersfreigabe-Erklärung für die neueste Version anzeigen
asc apps app-info age-rating <bundle-id>
asc apps app-info age-rating <bundle-id> --version 2.1.0

# Altersfreigabe aus einer JSON-Datei aktualisieren
asc apps app-info age-rating <bundle-id> --file age-rating.json
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
asc apps routing-coverage <bundle-id>

# Eine .geojson-Datei hochladen
asc apps routing-coverage <bundle-id> --file coverage.geojson
```
