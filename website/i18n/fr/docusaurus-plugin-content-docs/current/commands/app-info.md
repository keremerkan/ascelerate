---
sidebar_position: 5
title: Informations et catégories
---

# Informations et catégories de l'application

## Afficher

```bash
# Afficher les informations de l'application, les catégories et les métadonnées par langue
ascelerate apps app-info view <bundle-id>

# Lister tous les identifiants de catégorie disponibles (aucun bundle ID requis)
ascelerate apps app-info view --list-categories
```

## Mettre à jour

```bash
# Mettre à jour les champs de localisation pour une seule langue
ascelerate apps app-info update <bundle-id> --name "My App" --subtitle "Best app ever"
ascelerate apps app-info update <bundle-id> --locale de-DE --name "Meine App"

# Mettre à jour les catégories (peut être combiné avec les options de localisation)
ascelerate apps app-info update <bundle-id> --primary-category UTILITIES
ascelerate apps app-info update <bundle-id> --primary-category GAMES_ACTION --secondary-category ENTERTAINMENT
```

## Exporter

```bash
ascelerate apps app-info export <bundle-id>
ascelerate apps app-info export <bundle-id> --output app-infos.json
```

## Importer

```bash
ascelerate apps app-info import <bundle-id> --file app-infos.json
```

## Format JSON

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

Seuls les champs présents sont mis à jour -- les champs omis restent inchangés.

:::note
Les commandes `app-info update` et `app-info import` nécessitent que l'AppInfo soit dans un état modifiable (`PREPARE_FOR_SUBMISSION` ou `WAITING_FOR_REVIEW`).
:::

## Classification d'âge

```bash
# Afficher la déclaration de classification d'âge pour la dernière version
ascelerate apps app-info age-rating <bundle-id>
ascelerate apps app-info age-rating <bundle-id> --version 2.1.0

# Mettre à jour les classifications d'âge depuis un fichier JSON
ascelerate apps app-info age-rating <bundle-id> --file age-rating.json
```

Le fichier JSON utilise les mêmes noms de champs que l'API. Seuls les champs présents dans le fichier sont mis à jour :

```json
{
  "isAdvertising": false,
  "isUserGeneratedContent": true,
  "violenceCartoonOrFantasy": "INFREQUENT_OR_MILD",
  "alcoholTobaccoOrDrugUseOrReferences": "NONE"
}
```

Les champs d'intensité acceptent : `NONE`, `INFREQUENT_OR_MILD`, `FREQUENT_OR_INTENSE`. Les champs booléens acceptent `true`/`false`.

## Couverture de routage

```bash
# Voir le statut actuel de la couverture de routage
ascelerate apps routing-coverage <bundle-id>

# Téléverser un fichier .geojson
ascelerate apps routing-coverage <bundle-id> --file coverage.geojson
```
