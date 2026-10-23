---
sidebar_position: 2
title: Configuration
---

# Configuration

## 1. Créer une clé API

Rendez-vous sur [App Store Connect > Utilisateurs et accès > Intégrations > API App Store Connect](https://appstoreconnect.apple.com/access/integrations/api) et générez une nouvelle clé. Téléchargez le fichier de clé privée `.p8`.

## 2. Configurer

```bash
ascelerate configure
```

Cette commande vous demandera votre **Key ID**, **Issuer ID** et le chemin vers votre fichier `.p8`. La clé privée est copiée dans `~/.ascelerate/` avec des permissions de fichier strictes (accès propriétaire uniquement).

La configuration est stockée dans `~/.ascelerate/config.json` :

```json
{
    "keyId": "KEY_ID",
    "issuerId": "ISSUER_ID",
    "privateKeyPath": "/Users/.../.ascelerate/AuthKey_XXXXXXXXXX.p8"
}
```

`configure` demande également un **numéro de vendeur** facultatif (App Store Connect → Paiements et rapports financiers). Il n'est nécessaire que pour les [rapports Ventes et financiers](../commands/reports.md) et est stocké dans un champ `vendorNumber` ; vous pouvez l'ignorer et l'ajouter plus tard, ou le passer par commande avec `--vendor-number`.

Pour [Apple Ads](../commands/ads.md), ascelerate a besoin d'identifiants distincts, que `ascelerate ads configure` configure et enregistre dans une section `ads` du même fichier. Une nouvelle exécution de `configure` les conserve.

### Une clé pour une seule exécution

Pour exécuter une commande avec une autre clé (pour une autre équipe ou en CI), définissez les trois variables d'environnement. Elles priment sur `config.json` pour cette exécution, et le fichier reste inchangé :

```bash
export ASCELERATE_KEY_ID=KEY_ID
export ASCELERATE_ISSUER_ID=ISSUER_ID
export ASCELERATE_PRIVATE_KEY_PATH=~/keys/AuthKey_KEY_ID.p8
ascelerate apps list
```

`builds archive` et `builds upload` transmettent aussi cette clé à `xcodebuild` (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`), afin que les profils soient récupérés avec la clé plutôt qu'avec l'identifiant Apple connecté dans Xcode. La clé doit alors pouvoir gérer les certificats, identifiants et profils. `ascelerate configure --show` indique quelle clé une exécution utilise.

## 3. Vérifier

Exécutez une commande rapide pour vérifier que tout fonctionne :

```bash
ascelerate apps list
```

Si vos identifiants sont corrects, vous verrez la liste de toutes vos applications.

## Limite de requêtes

L'API App Store Connect dispose d'un quota horaire glissant de 3600 requêtes. Vous pouvez vérifier votre utilisation actuelle à tout moment :

```bash
ascelerate rate-limit
```

```
Hourly limit: 3600 requests (rolling window)
Used:         57
Remaining:    3543 (98%)
```
