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

## Sortie JSON {#json-output}

Les commandes de lecture prennent en charge `--json` pour une sortie lisible par machine, prête pour `jq`, les scripts et les agents IA :

```bash
ascelerate apps list --json
ascelerate apps info <bundle-id> --json
ascelerate apps versions <bundle-id> --json
ascelerate apps review preflight <bundle-id> --json
ascelerate apps review status <bundle-id> --json
ascelerate builds list --bundle-id <bundle-id> --json
ascelerate testflight builds <bundle-id> --json
ascelerate testflight status <bundle-id> --json
ascelerate reviews list <bundle-id> --json
ascelerate reviews info <review-id> --json
ascelerate iap list <bundle-id> --json
ascelerate iap info <bundle-id> <product-id> --json
ascelerate iap pricing show <bundle-id> <product-id> --json
ascelerate sub groups <bundle-id> --json
ascelerate sub list <bundle-id> --json
ascelerate sub info <bundle-id> <product-id> --json
ascelerate sub pricing show <bundle-id> <product-id> --json
ascelerate rate-limit --json
```

Conventions de sortie :

- Les commandes de liste émettent un **tableau** JSON de premier niveau ; les commandes de détail émettent un **objet** unique.
- Les valeurs d'énumération sont les constantes brutes de l'API (`WAITING_FOR_REVIEW`, `IOS`), les dates sont au format ISO 8601 et chaque ressource porte son `id`.
- Les champs nuls sont omis, et les résultats vides émettent `[]` — jamais de texte.
- Les avertissements deviennent des booléens : `iap info` et `sub info` rapportent `"hasPricing": false` au lieu d'un message d'avertissement.
- `--json` implique le mode non interactif : les commandes qui afficheraient une invite (par exemple pour choisir entre plusieurs plateformes) échouent au lieu de demander — passez `--platform` ou une autre option pour lever l'ambiguïté.
- Les erreurs vont sur stderr, la sortie standard reste donc toujours du JSON valide.

Exemple — compter les avis sans réponse :

```bash
ascelerate reviews list <bundle-id> --json | jq '[.[] | select(.response == null)] | length'
```

## Codes de sortie

Les commandes se terminent avec un code de sortie non nul en cas d'échec, ce qui les rend sûres pour une utilisation dans des scripts avec `set -e` ou un chaînage `&&`. La commande `preflight` se termine spécifiquement avec un code non nul lorsqu'une vérification échoue, vous permettant de conditionner les soumissions :

```bash
ascelerate apps review preflight <bundle-id> && ascelerate apps review submit <bundle-id>
```

Avec `--json`, `preflight` émet un rapport structuré (`{"passed": false, "checks": [{"group", "name", "passed", "detail"}]}`) tout en conservant le même comportement de code de sortie — idéal lorsque votre pipeline CI doit signaler *quelle* vérification a échoué.
