---
sidebar_position: 8
title: Appareils
---

# Appareils

Toutes les commandes d'appareils prennent en charge le mode interactif -- les arguments sont facultatifs. Lorsqu'ils sont omis, la commande propose des listes numérotées.

## Lister

```bash
asc devices list
asc devices list --platform IOS --status ENABLED
```

## Détails

```bash
# Sélecteur interactif
asc devices info

# Par nom ou UDID
asc devices info "My iPhone"
```

## Enregistrer

```bash
# Invites interactives
asc devices register

# Non interactif
asc devices register --name "My iPhone" --udid 00008101-XXXXXXXXXXXX --platform IOS
```

## Mettre à jour

```bash
# Sélecteur interactif et invites de mise à jour
asc devices update

# Renommer un appareil
asc devices update "My iPhone" --name "Work iPhone"

# Désactiver un appareil
asc devices update "My iPhone" --status DISABLED
```
