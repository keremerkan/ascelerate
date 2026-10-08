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

## Exécution à blanc {#dry-run}

Ajoutez `--dry-run` pour essayer une commande ou un workflow complet sans rien modifier dans App Store Connect. L'option fonctionne n'importe où sur la ligne de commande, et `ASCELERATE_DRY_RUN=1` a le même effet. Les requêtes de lecture sont envoyées normalement, de sorte que les recherches et les vérifications portent sur vos données réelles, mais chaque requête d'écriture est bloquée avant son envoi : ascelerate affiche sa méthode, son chemin et son corps JSON sur stderr et indique que la requête n'a pas été envoyée.

```bash
ascelerate apps localizations import <bundle-id> --file localizations.json --yes --dry-run
ascelerate run-workflow release.txt --yes --dry-run
ASCELERATE_DRY_RUN=1 ascelerate run-workflow release.txt --yes   # même effet, par exemple pour toute une tâche de CI
```

- Une commande s'arrête à sa première écriture bloquée ou, si elle traite les éléments un par un, signale chaque requête bloquée comme un échec.
- `media upload` considère les écritures bloquées comme effectuées et continue : les écritures de chaque fichier sont ainsi affichées, et la commande indique à la fin combien de fichiers seraient téléversés.
- Dans `run-workflow`, une étape dont les écritures ont été bloquées n'interrompt pas le workflow : une seule exécution montre ainsi les écritures de toutes les étapes. Une étape qui dépend d'un élément qu'une étape précédente aurait créé, comme une nouvelle version ou un build téléversé, peut tout de même échouer.
- Dans un fichier de workflow, `--dry-run` sur une seule étape ne s'applique qu'à cette étape.
- `builds upload` ignore le téléversement. `builds archive` et `builds validate` s'exécutent normalement, car ils ne modifient rien dans App Store Connect.

## Limite de débit de l'API {#rate-limit}

App Store Connect autorise 3 600 requêtes d'API par heure pour votre clé d'API, comptées sur une heure glissante. Quand une commande longue (un gros téléversement de médias, un nettoyage de la bibliothèque, un import de prix) les épuise, ascelerate attend qu'App Store Connect autorise de nouveau les requêtes, affiche l'heure à laquelle il reprendra, puis continue. Appuyez sur Ctrl-C pour arrêter à la place.

En CI, échouer peut être préférable à attendre : définissez `ASCELERATE_MAX_RATE_LIMIT_WAIT` sur le nombre maximal de secondes qu'une exécution peut attendre au total (`0` échoue dès la première requête limitée).

```bash
ASCELERATE_MAX_RATE_LIMIT_WAIT=600 ascelerate run-workflow release.txt --yes
```

`ascelerate rate-limit` indique combien de requêtes il reste ; cette commande n'attend jamais.

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

Avec `--json`, `preflight` émet un rapport structuré (`{"passed": false, "checks": [{"group", "name", "passed", "detail", "skipped"}]}`, où `skipped` n'apparaît que pour les produits retirés de la vente, qui comptent comme réussis) tout en conservant le même comportement de code de sortie — idéal lorsque votre pipeline CI doit signaler *quelle* vérification a échoué.
