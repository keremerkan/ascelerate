---
sidebar_position: 2
title: Builds
---

# Builds

## Lister les builds

```bash
asc builds list
asc builds list --bundle-id <bundle-id>
asc builds list --bundle-id <bundle-id> --version 2.1.0
```

## Archiver

```bash
asc builds archive
asc builds archive --scheme MyApp --output ./archives
```

La commande `archive` détecte automatiquement le `.xcworkspace` ou `.xcodeproj` dans le répertoire courant et résout le scheme s'il n'en existe qu'un seul.

## Valider

```bash
asc builds validate MyApp.ipa
```

## Téléverser

```bash
asc builds upload MyApp.ipa
```

Accepte les fichiers `.ipa`, `.pkg` ou `.xcarchive`. Lorsqu'un `.xcarchive` est fourni, il est automatiquement exporté en `.ipa` avant le téléversement.

## Attendre le traitement

```bash
asc builds await-processing <bundle-id>
asc builds await-processing <bundle-id> --build-version 903
```

Les builds récemment téléversés peuvent mettre quelques minutes à apparaître dans l'API -- la commande interroge régulièrement avec un indicateur de progression jusqu'à ce que le build soit trouvé et que le traitement soit terminé.

## Associer un build à une version

```bash
# Sélectionner et associer un build de manière interactive
asc apps build attach <bundle-id>
asc apps build attach <bundle-id> --version 2.1.0

# Associer automatiquement le build le plus récent
asc apps build attach-latest <bundle-id>

# Retirer le build associé à une version
asc apps build detach <bundle-id>
```

`build attach-latest` propose d'attendre si le dernier build est encore en cours de traitement. Avec `--yes`, l'attente est automatique.
