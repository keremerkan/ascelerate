---
sidebar_position: 18
title: Optimisation de la page de produit
---

# Optimisation de la page de produit

Testez d'autres captures d'écran, aperçus de l'app et icônes d'application face à votre page produit App Store d'origine. Un test présente jusqu'à trois **traitements** (des variantes de la page) à une partie des visiteurs de l'App Store et compare leurs taux de conversion à celui de la page d'origine. Les tests et les traitements sont désignés par leur **nom** ou leur identifiant.

## Lister et inspecter

```bash
ascelerate experiments <bundle-id>
ascelerate experiments info <bundle-id> "Screenshot order"
```

`info` affiche l'état du test, sa part de trafic et ses dates, ainsi que chaque traitement avec ses langues et ses médias par langue. Les deux commandes acceptent `--json`.

## Créer un test

```bash
ascelerate experiments create <bundle-id> --name "Screenshot order" --traffic 50 --treatment "Map first" --treatment "Alerts first"
```

`--traffic` est le pourcentage de visiteurs de l'App Store qui voient l'un des traitements ; il est réparti à parts égales entre eux, et tous les autres visiteurs voient la page d'origine. `--platform` vaut `ios` par défaut.

## Traitements

```bash
ascelerate experiments treatments add <bundle-id> "Screenshot order" --name "Icon B" --app-icon AppIconB
ascelerate experiments treatments update <bundle-id> "Screenshot order" "Icon B" --name "Blue icon"
ascelerate experiments treatments delete <bundle-id> "Screenshot order" "Blue icon"
ascelerate experiments treatments remove-locale <bundle-id> "Screenshot order" "Map first" --locale de-DE
```

`--app-icon` teste une autre icône d'application ; celle-ci doit figurer comme icône alternative dans le build publié. Dans une langue que le traitement ne couvre pas, la page d'origine s'affiche, même pour les visiteurs inclus dans le test.

## Médias

```bash
ascelerate experiments media list <bundle-id> "Screenshot order"
ascelerate experiments media upload <bundle-id> "Screenshot order" "Map first" --locale en-US --display-type APP_IPHONE_67 01.png
ascelerate experiments media upload <bundle-id> "Screenshot order" "Map first" --locale en-US --preview-type APP_IPHONE_67 preview.mp4
ascelerate experiments media delete <bundle-id> "Screenshot order" <media-id>
```

Les téléversements fonctionnent comme pour les [médias des pages de produit personnalisées](product-pages.md) : les images vont dans les jeux de captures d'écran selon `--display-type`, les vidéos dans les jeux d'aperçus de l'app selon `--preview-type`, et `PRODUCT_PAGE_HEADER`, `APP_STORE_SEARCH_RESULTS` et `APP_IPHONE_DUO` passent par la bibliothèque de ressources. La langue du traitement est créée lors du premier téléversement.

:::note
Une nouvelle langue de traitement commence par une **copie des médias de la page d'origine** : App Store Connect la remplit avec les captures d'écran et les aperçus de la version actuelle. Les fichiers téléversés s'ajoutent après cette copie ; supprimez donc les captures copiées que vous remplacez (`media list` affiche leurs identifiants).
:::

## Examen, démarrage et arrêt

```bash
ascelerate experiments submit <bundle-id> "Screenshot order"
ascelerate experiments start <bundle-id> "Screenshot order"
ascelerate experiments stop <bundle-id> "Screenshot order"
```

Un test comportant de nouveaux médias doit passer l'examen App Review avant de pouvoir démarrer (`info` l'indique). `submit` crée une soumission d'examen contenant uniquement le test et la soumet. S'il existe déjà, pour la plateforme, une soumission en brouillon contenant d'autres éléments (par exemple une version de l'application), le test y est ajouté et part en examen avec eux via [`apps review submit`](apps.md#submit-for-review). Une fois le test approuvé, `start` le lance et `stop` y met fin. Les résultats s'affichent dans App Store Connect.

## Mettre à jour et supprimer

```bash
ascelerate experiments update <bundle-id> "Screenshot order" --traffic 30
ascelerate experiments delete <bundle-id> "Screenshot order"
```

Ne modifiez qu'un seul élément par traitement (par exemple la première capture d'écran, ou l'icône) : le résultat vous dira alors quelle modification a fait la différence.
