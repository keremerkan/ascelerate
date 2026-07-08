---
sidebar_position: 2
title: Builds
---

# Builds

## Lister les builds

```bash
ascelerate builds list
ascelerate builds list --bundle-id <bundle-id>
ascelerate builds list --bundle-id <bundle-id> --version 2.1.0
ascelerate builds list --bundle-id <bundle-id> --platform macos
```

La sortie affiche, pour chaque build, la version de l'application, la plateforme, le numéro de build, l'état de traitement et la date de téléversement.

## Archiver

```bash
ascelerate builds archive
ascelerate builds archive --scheme MyApp --output ./archives
```

La commande `archive` détecte automatiquement le `.xcworkspace` ou `.xcodeproj` dans le répertoire courant et résout le scheme s'il n'en existe qu'un seul.

## Valider

```bash
ascelerate builds validate MyApp.ipa
```

## Téléverser

```bash
ascelerate builds upload MyApp.ipa
```

Accepte les fichiers `.ipa`, `.pkg` ou `.xcarchive`. Lorsqu'un `.xcarchive` est fourni, la plateforme de l'archive est détectée et l'export se fait automatiquement en `.ipa` (famille iOS) ou en `.pkg` (macOS) avant le téléversement, avec la plateforme correspondante transmise à altool.

## Attendre le traitement

```bash
ascelerate builds await-processing <bundle-id>
ascelerate builds await-processing <bundle-id> --build-version 903
ascelerate builds await-processing <bundle-id> --build-version 903 --platform macos
```

Les builds récemment téléversés peuvent mettre quelques minutes à apparaître dans l'API -- la commande interroge régulièrement avec un indicateur de progression jusqu'à ce que le build soit trouvé et que le traitement soit terminé.

## Associer un build à une version

```bash
# Sélectionner et associer un build de manière interactive
ascelerate apps build attach <bundle-id>
ascelerate apps build attach <bundle-id> --version 2.1.0

# Associer automatiquement le build le plus récent
ascelerate apps build attach-latest <bundle-id>
ascelerate apps build attach-latest <bundle-id> --platform macos

# Retirer le build associé à une version
ascelerate apps build detach <bundle-id>
```

`build attach-latest` propose d'attendre si le dernier build est encore en cours de traitement. Avec `--yes`, l'attente est automatique.

La recherche de builds tient compte de la plateforme : sur les applications en achat universel, les builds iOS et macOS peuvent partager les mêmes numéros de build ; les commandes d'association ne retiennent donc que les builds correspondant à la plateforme de la version ciblée.
