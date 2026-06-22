---
sidebar_position: 14
title: Événements in-app
---

# Événements in-app

Créez et gérez des événements in-app — des événements ponctuels (événements en direct, premières, défis, offres spéciales) qui apparaissent sur votre page produit App Store et dans la recherche. Les événements sont désignés par leur **nom de référence** ou leur identifiant.

## Lister et inspecter

```bash
ascelerate events list <bundle-id>
ascelerate events list <bundle-id> --state PUBLISHED
ascelerate events info <bundle-id> <reference-name-or-id>
```

`info` affiche les attributs de l'événement, ses calendriers par territoire et un résumé des localisations.

## Créer, mettre à jour, supprimer

```bash
ascelerate events create <bundle-id> --reference-name "summer-sale" --badge SPECIAL_EVENT --purpose ATTRACT_NEW_USERS --priority HIGH

# Avec un calendrier initial
ascelerate events create <bundle-id> --reference-name "launch" \
  --territories USA,GBR --publish-start 2026-07-01 --event-start 2026-07-05 --event-end 2026-07-12

ascelerate events update <bundle-id> summer-sale --priority NORMAL --badge NONE
ascelerate events delete <bundle-id> summer-sale
```

- **Badges :** `LIVE_EVENT`, `PREMIERE`, `CHALLENGE`, `COMPETITION`, `NEW_SEASON`, `MAJOR_UPDATE`, `SPECIAL_EVENT`. Passez `--badge NONE` à `update` pour le supprimer.
- **Objectifs :** `APPROPRIATE_FOR_ALL_USERS`, `ATTRACT_NEW_USERS`, `KEEP_ACTIVE_USERS_INFORMED`, `BRING_BACK_LAPSED_USERS`.
- **Priorité :** `HIGH` ou `NORMAL`.
- **Dates du calendrier** (`--publish-start`, `--event-start`, `--event-end`) acceptent le format ISO8601 (`2026-07-01T09:00:00Z`) ou `yyyy-MM-dd` (minuit UTC). Omettez `--territories` pour programmer sur tous les territoires.

## Localisations

```bash
ascelerate events localizations view <bundle-id> summer-sale
ascelerate events localizations export <bundle-id> summer-sale
ascelerate events localizations import <bundle-id> summer-sale --file event-locales.json
```

Chaque localisation comporte `name`, `shortDescription` et `longDescription`. Les langues doivent correspondre à celles configurées pour l'app (par ex. `tr`, et non `tr-TR`).

```json
{
  "en-US": {
    "name": "Summer Sale",
    "shortDescription": "Grandes remises d'été",
    "longDescription": "Participez à notre événement d'été pour profiter de remises à durée limitée."
  }
}
```

## Médias

Captures d'écran de la carte d'événement et de la page de détails (`.png`/`.jpg`) ainsi que clips vidéo (`.mp4`/`.mov`), par localisation.

```bash
ascelerate events media list <bundle-id> summer-sale
ascelerate events media upload <bundle-id> summer-sale --locale en-US --asset-type EVENT_CARD card.png
ascelerate events media upload <bundle-id> summer-sale --locale en-US --asset-type EVENT_DETAILS_PAGE clip.mp4 --preview-frame 00:00:03
ascelerate events media delete <bundle-id> summer-sale <media-id>
```

Les types d'asset sont `EVENT_CARD` et `EVENT_DETAILS_PAGE`. Le type de fichier détermine s'il est téléversé comme capture d'écran ou comme clip vidéo ; `--preview-frame` définit le timecode de l'image d'aperçu d'une vidéo.
