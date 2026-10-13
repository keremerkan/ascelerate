---
sidebar_position: 19
title: Candidatures pour une mise en avant
---

# Candidatures pour une mise en avant

Informez l'équipe éditoriale d'Apple d'un lancement à venir, d'une mise à jour majeure ou d'un nouveau contenu, afin qu'elle puisse envisager de le mettre en avant sur l'App Store.

## Lister

```bash
ascelerate nominations
ascelerate nominations --app <bundle-id> --state draft
```

Liste les candidatures en brouillon, soumises et archivées (ou un seul état avec `--state`). Ajoutez `--json` pour une sortie lisible par machine.

## Créer

```bash
ascelerate nominations create --app <bundle-id> --type enhancements --name "Version 5" \
  --description "What's new and why it matters to users" --publish-start 2026-11-01 \
  --devices iphone,ipad --locales en-US,tr-TR
```

| Option | Description |
|---|---|
| `--app` | L'application (répétez `--app` pour une candidature qui couvre plusieurs applications) |
| `--type` | `launch`, `enhancements` ou `new-content` |
| `--name`, `--description` | L'objet de la candidature, rédigé à l'intention des éditeurs d'Apple |
| `--publish-start` | Date de sortie (`yyyy-MM-dd` ou ISO 8601) ; `--publish-end` pour un contenu disponible pendant une durée limitée |
| `--devices` | Familles d'appareils : `iphone`, `ipad`, `mac`, `apple-tv`, `apple-watch`, `vision` |
| `--locales` | Langues dans lesquelles la sortie est localisée |
| `--territories` | Territoires dans lesquels elle sort en premier (par défaut : tous) |
| `--materials` | Liens vers des documents d'accompagnement (dossier de presse, vidéo), séparés par des virgules |
| `--notes` | Remarques à l'intention d'Apple |
| `--pre-order` | L'application est disponible en précommande |
| `--submit` | Soumettre immédiatement au lieu d'enregistrer un brouillon |

Sans `--submit`, la candidature est enregistrée comme brouillon, que vous pouvez relire et modifier.

## Mettre à jour, soumettre, archiver et supprimer

```bash
ascelerate nominations update <id> --publish-start 2026-11-08
ascelerate nominations submit <id>
ascelerate nominations archive <id>
ascelerate nominations delete <id>
```

`update` modifie un brouillon ; les identifiants des candidatures s'obtiennent avec `nominations`. La décision de mettre en avant une application revient aux éditeurs d'Apple : soumettez votre candidature bien avant la date de sortie.
