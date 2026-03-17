---
sidebar_position: 6
title: Achats intégrés
---

# Achats intégrés

## Lister

```bash
ascelerate iap list <bundle-id>
ascelerate iap list <bundle-id> --type consumable --state approved
```

Les valeurs de filtre sont insensibles à la casse. Types : `CONSUMABLE`, `NON_CONSUMABLE`, `NON_RENEWING_SUBSCRIPTION`. États : `APPROVED`, `MISSING_METADATA`, `READY_TO_SUBMIT`, `WAITING_FOR_REVIEW`, `IN_REVIEW`, etc.

## Détails

```bash
ascelerate iap info <bundle-id> <product-id>
```

## Achats promus

```bash
ascelerate iap promoted <bundle-id>
```

## Créer, mettre à jour et supprimer

```bash
ascelerate iap create <bundle-id> --name "100 Coins" --product-id <product-id> --type CONSUMABLE
ascelerate iap update <bundle-id> <product-id> --name "100 Gold Coins"
ascelerate iap delete <bundle-id> <product-id>
```

## Soumettre pour examen

```bash
ascelerate iap submit <bundle-id> <product-id>
```

## Localisations

```bash
ascelerate iap localizations view <bundle-id> <product-id>
ascelerate iap localizations export <bundle-id> <product-id>
ascelerate iap localizations import <bundle-id> <product-id> --file iap-de.json
```

La commande d'import crée automatiquement les langues manquantes avec confirmation, vous permettant d'ajouter de nouvelles langues sans passer par App Store Connect.
