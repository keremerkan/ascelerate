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
