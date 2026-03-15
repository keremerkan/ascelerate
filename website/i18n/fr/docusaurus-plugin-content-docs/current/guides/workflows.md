---
sidebar_position: 1
title: Workflows
---

# Workflows

Enchaînez plusieurs commandes en une seule exécution automatisée avec un fichier de workflow :

```bash
asc run-workflow release.txt
asc run-workflow release.txt --yes   # ignore toutes les invites (CI/CD)
asc run-workflow                     # sélection interactive parmi les fichiers .workflow/.txt
```

Un fichier de workflow est un fichier texte brut avec une commande par ligne (sans le préfixe `asc`). Les lignes commençant par `#` sont des commentaires, les lignes vides sont ignorées. Les extensions `.workflow` et `.txt` sont toutes deux prises en charge.

## Exemple

`release.txt` pour soumettre la version 2.1.0 d'une application exemple :

```
# Workflow de publication pour MyApp v2.1.0

# Créer la nouvelle version sur App Store Connect
apps create-version com.example.MyApp 2.1.0

# Archiver, valider et téléverser
builds archive --scheme MyApp
builds validate --latest --bundle-id com.example.MyApp
builds upload --latest --bundle-id com.example.MyApp

# Attendre la fin du traitement du build
builds await-processing com.example.MyApp

# Mettre à jour les localisations et attacher le build
apps localizations import com.example.MyApp --file localizations.json
apps build attach-latest com.example.MyApp

# Soumettre pour examen
apps review submit com.example.MyApp
```

## Comportement de confirmation

Sans `--yes`, le workflow demande une confirmation avant de démarrer, et les commandes individuelles continuent de poser des questions là où elles le feraient normalement (par ex. avant de soumettre pour examen). Avec `--yes`, toutes les invites sont ignorées pour une exécution entièrement automatisée.

## Imbrication

Les workflows peuvent appeler d'autres workflows (`run-workflow` à l'intérieur d'un fichier de workflow). Les références circulaires sont détectées et empêchées.

## Intégration au pipeline de build

`builds upload` définit une variable interne pour que les commandes `await-processing` et `build attach-latest` suivantes ciblent automatiquement le build qui vient d'être téléversé, évitant ainsi les conditions de concurrence liées au délai de propagation de l'API.
