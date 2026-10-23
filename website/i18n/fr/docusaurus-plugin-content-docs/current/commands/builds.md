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

La sortie affiche, pour chaque build, la version de l'application, la plateforme, le numéro de build, l'état de traitement et la date de téléversement. Ajoutez `--json` pour une sortie lisible par machine ([conventions](../guides/automation.md#json-output)).

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

Un `.xcarchive` signé avec des profils de distribution App Store (un projet à signature manuelle) est exporté avec les profils App Store installés de son application et de ses extensions, si bien qu'Xcode n'en crée aucun ; les autres archives sont exportées avec la signature automatique. Avec un fichier, `--bundle-id` refuse un fichier qui contient une autre application, avant tout export ou envoi.

### Téléverser via l'API App Store Connect

```bash
ascelerate builds upload MyApp.ipa --api
ascelerate builds upload --latest --bundle-id com.example.MyApp --api
```

Avec `--api`, le build passe par les téléversements de builds de l'API App Store Connect au lieu d'altool, avec la même clé d'API que toutes les autres commandes. La commande accepte un `.ipa` ou un `.pkg` Mac (ou un `.xcarchive`, exporté au préalable), lit la version et le numéro de build dans l'application qu'il contient, téléverse le fichier par morceaux, un par un (voir [Téléversement par morceaux](../guides/automation.md#upload-chunks)), avec une barre de progression dans un terminal, puis attend qu'App Store Connect ait accepté le fichier. Si Apple le refuse, la commande échoue en affichant les codes et les descriptions d'erreur d'Apple ; les avertissements sont affichés après un téléversement réussi. Le traitement se poursuit ensuite comme d'habitude (voir [Attendre le traitement](#attendre-le-traitement)).

altool reste pour l'instant l'outil par défaut.

### Progression pour d'autres outils

```bash
ascelerate builds archive --scheme MyApp --json-events
ascelerate builds upload MyApp.ipa --api --json-events
```

Avec `--json-events`, les deux commandes écrivent un objet JSON par ligne sur stdout (`step`, `archived` avec le chemin de l'archive, `uploading`, `progress`, `processing` et `finished` avec les avertissements d'Apple) et déplacent leur sortie lisible, celle de xcodebuild comprise, vers stderr, comme le fait `screenshot run --json-events`. Lors de l'archivage, xcodebuild n'affiche alors que les avertissements et les erreurs.

## Historique des téléversements

```bash
ascelerate builds uploads <bundle-id>
ascelerate builds uploads <bundle-id> --platform macos --limit 20
ascelerate builds uploads <bundle-id> --delete-stale
```

Liste les téléversements récents de l'application, qu'ils aient été faits avec altool, Xcode ou `--api`, avec leur état (Awaiting Upload, Processing, Complete, Failed) et les erreurs et avertissements qu'Apple y a associés. Consultez cette liste lorsqu'un téléversement ne devient jamais un build. Ajoutez `--json` pour une sortie lisible par machine.

Une connexion qui se coupe au mauvais moment peut laisser un enregistrement de téléversement en attente d'un fichier qui n'arrivera jamais. Les téléversements `--api` suppriment, une fois réussis, ces enregistrements du même build, et `--delete-stale` supprime ceux qui restent : les enregistrements toujours en attente d'un fichier alors qu'un autre téléversement du même build a avancé, ou depuis plus d'un jour. Un téléversement encore en cours n'est jamais supprimé.

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
