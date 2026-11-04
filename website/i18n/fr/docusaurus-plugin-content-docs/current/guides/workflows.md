---
sidebar_position: 1
title: Workflows
---

# Workflows

Enchaînez plusieurs commandes en une seule exécution automatisée avec un fichier de workflow :

```bash
ascelerate run-workflow release.txt
ascelerate run-workflow release.txt --yes   # ignore toutes les invites (CI/CD)
ascelerate run-workflow                     # sélection interactive parmi les fichiers .workflow/.txt
```

Un fichier de workflow est un fichier texte brut avec une commande par ligne (sans le préfixe `ascelerate`). Les lignes commençant par `#` sont des commentaires, les lignes vides sont ignorées. Les extensions `.workflow` et `.txt` sont toutes deux prises en charge.

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

## Vérifier un workflow

```bash
ascelerate run-workflow release.txt --check          # every step parses; nothing runs
ascelerate run-workflow release.txt --check --json   # each step's line, command and error
```

`--check` analyse les arguments et options de chaque étape sans rien exécuter, et liste les étapes qui ne s’analysent pas, avec leur ligne dans le fichier.

## Suivre une exécution depuis un autre programme

```bash
ascelerate run-workflow release.txt --json-events
```

Avec `--json-events`, stdout transporte un événement JSON par ligne et tout ce qui est lisible, y compris la sortie des étapes elles-mêmes, va sur stderr. Les événements sont `workflow` (les étapes et leurs lignes), `step` (`running`, puis `succeeded`, `failed` avec l’erreur, ou `dry-run`), `finished`, et `prompt` pour chaque question posée par une étape : son `kind` (`confirm`, `choice`, `choices` ou `text`), son `message` et ses `options`. L’étape lit ensuite la réponse sur stdin, une ligne (`y` ou `n`, le numéro d’une option à partir de 1, ou le texte). Le workflow n’est pas confirmé au départ, puisque le programme qui l’exécute l’a fait. Les événements d’un workflow imbriqué portent sa `depth`. Les étapes qui signalent leurs propres événements quand elles s’exécutent seules (`builds archive`, `builds upload`, `screenshot`) ne les ajoutent pas ici ; leur progression va sur stderr, sauf celle d’un chargement avec `--api`, qui arrive sous forme d’événements `progress` de son étape (`index`, `sent` sur `bytes`). La sortie xcodebuild des étapes est réduite (avertissements et erreurs), sauf si `ascelerate settings --xcodebuild-output full` en décide autrement.

## Imbrication

Les workflows peuvent appeler d'autres workflows (`run-workflow` à l'intérieur d'un fichier de workflow). Les références circulaires sont détectées et empêchées.

## Intégration au pipeline de build

`builds upload` définit une variable interne pour que les commandes `await-processing` et `build attach-latest` suivantes ciblent automatiquement le build qui vient d'être téléversé, évitant ainsi les conditions de concurrence liées au délai de propagation de l'API.
