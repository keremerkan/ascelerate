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
```

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

Accepte les fichiers `.ipa`, `.pkg` ou `.xcarchive`. Lorsqu'un `.xcarchive` est fourni, il est automatiquement exporté en `.ipa` avant le téléversement.

## Attendre le traitement

```bash
ascelerate builds await-processing <bundle-id>
ascelerate builds await-processing <bundle-id> --build-version 903
```

Les builds récemment téléversés peuvent mettre quelques minutes à apparaître dans l'API -- la commande interroge régulièrement avec un indicateur de progression jusqu'à ce que le build soit trouvé et que le traitement soit terminé.

## Associer un build à une version

```bash
# Sélectionner et associer un build de manière interactive
ascelerate apps build attach <bundle-id>
ascelerate apps build attach <bundle-id> --version 2.1.0

# Associer automatiquement le build le plus récent
ascelerate apps build attach-latest <bundle-id>

# Retirer le build associé à une version
ascelerate apps build detach <bundle-id>
```

`build attach-latest` propose d'attendre si le dernier build est encore en cours de traitement. Avec `--yes`, l'attente est automatique.
