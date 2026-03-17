---
sidebar_position: 10
title: Bundle IDs
---

# Bundle IDs

Toutes les commandes de bundle IDs prennent en charge le mode interactif -- les arguments sont facultatifs.

## Lister

```bash
ascelerate bundle-ids list
ascelerate bundle-ids list --platform IOS
```

## Détails

```bash
# Sélecteur interactif
ascelerate bundle-ids info

# Par identifiant
ascelerate bundle-ids info com.example.MyApp
```

## Enregistrer

```bash
# Invites interactives
ascelerate bundle-ids register

# Non interactif
ascelerate bundle-ids register --name "My App" --identifier com.example.MyApp --platform IOS
```

## Renommer

```bash
ascelerate bundle-ids update
ascelerate bundle-ids update com.example.MyApp --name "My Renamed App"
```

L'identifiant lui-même est immuable -- seul le nom peut être modifié.

## Supprimer

```bash
ascelerate bundle-ids delete
ascelerate bundle-ids delete com.example.MyApp
```

## Capacités

### Activer

```bash
# Sélecteurs interactifs (affiche uniquement les capacités non encore activées)
ascelerate bundle-ids enable-capability

# Non interactif
ascelerate bundle-ids enable-capability com.example.MyApp --type PUSH_NOTIFICATIONS
```

### Désactiver

```bash
# Sélectionne parmi les capacités actuellement activées
ascelerate bundle-ids disable-capability
ascelerate bundle-ids disable-capability com.example.MyApp
```

Après avoir activé ou désactivé une capacité, si des profils de provisionnement existent pour ce bundle ID, la commande propose de les régénérer (nécessaire pour que les modifications prennent effet).

:::note
Certaines capacités (par ex. App Groups, iCloud, Associated Domains) nécessitent une configuration supplémentaire dans le [portail Apple Developer](https://developer.apple.com/account/resources) après activation.
:::
