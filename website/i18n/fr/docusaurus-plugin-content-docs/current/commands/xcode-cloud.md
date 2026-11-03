---
sidebar_position: 21
title: Xcode Cloud
---

# Xcode Cloud

Suivez et lancez des builds Xcode Cloud : vos produits, leurs workflows et chaque exécution de build avec ses actions, ses problèmes, ses résultats de tests et ses artefacts.

Un **produit** est créé dans Xcode la première fois que vous connectez un dépôt (**Integrate > Create Workflow**) ; l'API ne peut pas en créer. Ensuite, tout ce qui est décrit ici fonctionne en ligne de commande. Un produit est désigné par le **bundle ID** de son application (ou un alias), son nom ou son identifiant ; un workflow par son **nom** ou son identifiant ; une exécution de build par son **numéro** ou son identifiant.

## Produits

```bash
ascelerate xcode-cloud products
```

Liste les produits de l'équipe (applications et frameworks) avec leur bundle ID et leur dépôt.

## Workflows

```bash
ascelerate xcode-cloud workflows <bundle-id>
ascelerate xcode-cloud workflows info <bundle-id> "Release"
ascelerate xcode-cloud workflows update <bundle-id> "Default" --manual-only
ascelerate xcode-cloud workflows update <bundle-id> "Release" --branch-changes "main,release/*" --xcode "Xcode 27.2" --clean false
ascelerate xcode-cloud workflows create <bundle-id> --like "Default" --name "TestFlight" --action archive:MyApp:ios --manual-branches main
ascelerate xcode-cloud workflows disable <bundle-id> "Nightly"
ascelerate xcode-cloud workflows enable <bundle-id> "Nightly"
ascelerate xcode-cloud workflows delete <bundle-id> "Old workflow"
```

`info` affiche les conditions de démarrage d'un workflow (modifications de branches et de tags, pull requests, planifications et ce qui peut être lancé manuellement), ses actions (build, test, analyse, archivage, avec scheme, plateforme et distribution), ainsi que le dépôt, le projet et les versions d'Xcode et de macOS qu'il utilise. `update --manual-only` empêche un workflow de démarrer de lui-même (modifications de branches et de tags, pull requests, planification) et conserve ce qui peut être lancé manuellement. `update` modifie aussi le nom, la description, les builds propres, « Restrict Editing », les versions d’Xcode et de macOS et chaque condition de démarrage : `--branch-changes`, `--tag-changes`, `--pull-requests` (avec `--pull-request-source`), `--manual-branches`, `--manual-tags` et `--manual-pull-requests` acceptent des noms (`release/*` pour ceux qui commencent ainsi), `any` ou `off` ; s’y ajoutent `--auto-cancel` et `--remove-schedule`. Avant d’enregistrer, il liste les modifications et demande confirmation. `--action TYPE:SCHÉMA[:PLATEFORME]` (répétable) remplace les actions, et `--distribution internal|app-store|none` définit la distribution d’une archive. `create` crée un workflow en copiant un autre (`--like`, inutile si le produit n’en a qu’un) et accepte les mêmes options. L’API n’a ni variables d’environnement ni post-actions : ajoutez-les (des groupes TestFlight, par exemple) dans App Store Connect. Un workflow désactivé ne lance aucun build. La suppression d'un workflow conserve ses exécutions de build.

## Exécutions de build

```bash
ascelerate xcode-cloud runs <bundle-id>                         # les plus récentes d'abord
ascelerate xcode-cloud runs <bundle-id> --workflow "Release" --limit 50
ascelerate xcode-cloud runs info <bundle-id> 42                 # détails et actions
ascelerate xcode-cloud runs issues <bundle-id> 42 [--errors]
ascelerate xcode-cloud runs tests <bundle-id> 42 [--failed]
ascelerate xcode-cloud runs logs <bundle-id> 42 [--action "Build - iOS"] [--show ci_post_clone.log]
ascelerate xcode-cloud runs artifacts <bundle-id> 42
ascelerate xcode-cloud runs artifacts <bundle-id> 42 --type LOG_BUNDLE --download ./logs
```

Chaque exécution affiche son état, la branche, le tag ou la pull request compilés, le commit et sa durée ; `runs info` y ajoute ses actions avec leur nombre d'erreurs, d'avertissements et de tests en échec (Apple n'en envoie pas : ils sont comptés à partir des problèmes de chaque action). Pour une archive chargée dans App Store Connect, il affiche aussi le build chargé avec son état de traitement et ses états TestFlight. `issues` liste les erreurs et avertissements de chaque action avec le fichier et la ligne ; `tests` liste les résultats de tests par destination (appareil et OS), avec le message d'échec de chaque test échoué. `logs` lit le paquet de journaux de chaque action : ceux du script post-clone, de la résolution des paquets et de xcodebuild, listés avec leur nombre de lignes ou affichés avec `--show`. `artifacts` liste les journaux, archives, result bundles et produits ; `--download` les enregistre (`--type` restreint la sélection).

## Lancer un build

```bash
ascelerate xcode-cloud start <bundle-id> "Release" --branch main
ascelerate xcode-cloud start <bundle-id> "Release" --tag v2.1
ascelerate xcode-cloud start <bundle-id> "PR checks" --pull-request 128
ascelerate xcode-cloud rerun <bundle-id> 42 [--clean]
```

`start` compile la branche, le tag ou la pull request que vous indiquez ; sans indication, Xcode Cloud compile ce que la condition de démarrage du workflow permet de lancer manuellement. `rerun` recompile le commit d'une exécution précédente avec son workflow. `--clean` compile sans le cache. L'API ne permet pas d'annuler un build.

## Dépôts et versions d'Xcode

```bash
ascelerate xcode-cloud repositories
ascelerate xcode-cloud xcode-versions
```

`xcode-versions` liste les versions d'Xcode proposées par Xcode Cloud, avec les versions de macOS sur lesquelles chacune s'exécute.

Toutes les commandes de liste et d'information acceptent `--json`.
