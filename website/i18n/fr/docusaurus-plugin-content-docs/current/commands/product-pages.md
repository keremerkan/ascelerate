---
sidebar_position: 15
title: Pages de produit personnalisées
---

# Pages de produit personnalisées

Créez et gérez des pages de produit personnalisées — des variantes de votre page produit App Store avec leur propre texte promotionnel et leurs propres captures d'écran, chacune accessible via une URL unique. Les pages sont désignées par leur **nom** ou leur identifiant.

## Lister et inspecter

```bash
ascelerate product-pages list <bundle-id>
ascelerate product-pages info <bundle-id> <name-or-id>
```

`list` affiche le nom, la visibilité, l'URL App Store partageable (avec son `ppid`) et l'identifiant de chaque page. `info` ajoute les versions de la page et leurs localisations.

## Créer

```bash
ascelerate product-pages create <bundle-id> --name "Summer Campaign" --locale en-US --promotional-text "Offre à durée limitée"
```

L'API App Store Connect exige qu'une page soit créée avec une première version et au moins une localisation, c'est pourquoi `--locale` est requis. Ajoutez d'autres langues ensuite avec `product-pages localizations import`.

## Mettre à jour et supprimer

```bash
ascelerate product-pages update <bundle-id> "Summer Campaign" --name "Summer 2026" --visible false
ascelerate product-pages delete <bundle-id> "Summer Campaign"
```

`--visible` détermine si la page est active sur l'App Store.

## Localisations

```bash
ascelerate product-pages localizations view <bundle-id> "Summer 2026"
ascelerate product-pages localizations export <bundle-id> "Summer 2026"
ascelerate product-pages localizations import <bundle-id> "Summer 2026" --file page-locales.json
```

Chaque localisation comporte `promotionalText`, appliqué à la version modifiable de la page.

```json
{
  "en-US": { "promotionalText": "Offre à durée limitée" },
  "fr-FR": { "promotionalText": "Offre à durée limitée" }
}
```

## Captures d'écran et aperçus de l'app

Captures d'écran par langue (`.png`/`.jpg`, par type d'affichage) et aperçus de l'app (`.mp4`/`.mov`, par type d'aperçu). Le jeu est créé automatiquement lors du premier téléversement.

```bash
ascelerate product-pages media list <bundle-id> "Summer 2026"
ascelerate product-pages media upload <bundle-id> "Summer 2026" --locale en-US --display-type APP_IPHONE_67 screenshot.png
ascelerate product-pages media upload <bundle-id> "Summer 2026" --locale en-US --preview-type APP_IPHONE_67 preview.mp4 --preview-frame 00:00:03
ascelerate product-pages media delete <bundle-id> "Summer 2026" <media-id>
```

Le type de fichier détermine s'il est téléversé comme capture d'écran ou comme aperçu de l'app. Les types d'affichage et d'aperçu utilisent les identifiants d'appareil App Store standard (par ex. `APP_IPHONE_67`, `APP_IPAD_PRO_3GEN_129`).
