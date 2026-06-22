---
sidebar_position: 14
title: In-App-Events
---

# In-App-Events

In-App-Events erstellen und verwalten — zeitnahe Events (Live-Events, Premieren, Challenges, Sonderangebote), die auf deiner App-Store-Produktseite und in der Suche erscheinen. Events werden über ihren **Referenznamen** oder ihre ID angesprochen.

## Auflisten und ansehen

```bash
ascelerate events list <bundle-id>
ascelerate events list <bundle-id> --state PUBLISHED
ascelerate events info <bundle-id> <reference-name-or-id>
```

`info` zeigt die Attribute des Events, seine regionsspezifischen Zeitpläne und eine Übersicht der Lokalisierungen.

## Erstellen, aktualisieren, löschen

```bash
ascelerate events create <bundle-id> --reference-name "summer-sale" --badge SPECIAL_EVENT --purpose ATTRACT_NEW_USERS --priority HIGH

# Mit einem ersten Zeitplan
ascelerate events create <bundle-id> --reference-name "launch" \
  --territories USA,GBR --publish-start 2026-07-01 --event-start 2026-07-05 --event-end 2026-07-12

ascelerate events update <bundle-id> summer-sale --priority NORMAL --badge NONE
ascelerate events delete <bundle-id> summer-sale
```

- **Badges:** `LIVE_EVENT`, `PREMIERE`, `CHALLENGE`, `COMPETITION`, `NEW_SEASON`, `MAJOR_UPDATE`, `SPECIAL_EVENT`. Gib `update` ein `--badge NONE` mit, um das Badge zu entfernen.
- **Zwecke:** `APPROPRIATE_FOR_ALL_USERS`, `ATTRACT_NEW_USERS`, `KEEP_ACTIVE_USERS_INFORMED`, `BRING_BACK_LAPSED_USERS`.
- **Priorität:** `HIGH` oder `NORMAL`.
- **Zeitplandaten** (`--publish-start`, `--event-start`, `--event-end`) akzeptieren ISO8601 (`2026-07-01T09:00:00Z`) oder `yyyy-MM-dd` (UTC-Mitternacht). Lass `--territories` weg, um für alle Regionen zu planen.

## Lokalisierungen

```bash
ascelerate events localizations view <bundle-id> summer-sale
ascelerate events localizations export <bundle-id> summer-sale
ascelerate events localizations import <bundle-id> summer-sale --file event-locales.json
```

Jede Lokalisierung enthält `name`, `shortDescription` und `longDescription`. Die Sprachen müssen mit den konfigurierten Sprachen der App übereinstimmen (z. B. `tr`, nicht `tr-TR`).

```json
{
  "en-US": {
    "name": "Summer Sale",
    "shortDescription": "Große Sommerrabatte",
    "longDescription": "Nimm an unserem Sommer-Event teil und sichere dir zeitlich begrenzte Rabatte."
  }
}
```

## Medien

Screenshots der Event-Karte und der Event-Detailseite (`.png`/`.jpg`) sowie Videoclips (`.mp4`/`.mov`), pro Lokalisierung.

```bash
ascelerate events media list <bundle-id> summer-sale
ascelerate events media upload <bundle-id> summer-sale --locale en-US --asset-type EVENT_CARD card.png
ascelerate events media upload <bundle-id> summer-sale --locale en-US --asset-type EVENT_DETAILS_PAGE clip.mp4 --preview-frame 00:00:03
ascelerate events media delete <bundle-id> summer-sale <media-id>
```

Die Asset-Typen sind `EVENT_CARD` und `EVENT_DETAILS_PAGE`. Der Dateityp bestimmt, ob die Datei als Screenshot oder als Videoclip hochgeladen wird; `--preview-frame` legt den Timecode des Vorschaubilds eines Videos fest.
