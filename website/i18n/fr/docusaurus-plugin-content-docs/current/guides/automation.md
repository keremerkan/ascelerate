---
sidebar_position: 2
title: Automatisation et CI/CD
---

# Automatisation et CI/CD

La plupart des commandes qui demandent une confirmation prennent en charge `--yes` / `-y` pour ignorer les invites, ce qui les rend adaptées aux pipelines CI/CD et aux scripts.

```bash
ascelerate apps build attach-latest <bundle-id> --yes
ascelerate apps review submit <bundle-id> --yes
```

:::warning
Lorsque vous utilisez `--yes` avec les commandes de provisionnement, tous les arguments requis doivent être fournis explicitement -- le mode interactif est désactivé.
:::

## Signature Xcode en CI

Les commandes `builds archive` et l'export d'archive vers IPA passent `-allowProvisioningUpdates` à `xcodebuild`. Sans cela, `xcodebuild` utilise uniquement les profils de provisionnement mis en cache localement et ne récupère pas les profils mis à jour depuis le portail développeur.

Pour les environnements CI sans connexion via l'interface Xcode, fournissez les options d'authentification :

```bash
ascelerate builds archive \
  --authentication-key-path /path/to/AuthKey.p8 \
  --authentication-key-id YOUR_KEY_ID \
  --authentication-key-issuer-id YOUR_ISSUER_ID
```

## Codes de sortie

Les commandes se terminent avec un code de sortie non nul en cas d'échec, ce qui les rend sûres pour une utilisation dans des scripts avec `set -e` ou un chaînage `&&`. La commande `preflight` se termine spécifiquement avec un code non nul lorsqu'une vérification échoue, vous permettant de conditionner les soumissions :

```bash
ascelerate apps review preflight <bundle-id> && asc apps review submit <bundle-id>
```
