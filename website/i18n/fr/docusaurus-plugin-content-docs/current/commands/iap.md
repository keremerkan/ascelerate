---
sidebar_position: 6
title: Achats intégrés
---

# Achats intégrés

## Lister

```bash
asc iap list <bundle-id>
asc iap list <bundle-id> --type consumable --state approved
```

Les valeurs de filtre sont insensibles à la casse. Types : `CONSUMABLE`, `NON_CONSUMABLE`, `NON_RENEWING_SUBSCRIPTION`. États : `APPROVED`, `MISSING_METADATA`, `READY_TO_SUBMIT`, `WAITING_FOR_REVIEW`, `IN_REVIEW`, etc.

## Détails

```bash
asc iap info <bundle-id> <product-id>
```

## Achats promus

```bash
asc iap promoted <bundle-id>
```

## Créer, mettre à jour et supprimer

```bash
asc iap create <bundle-id> --name "100 Coins" --product-id <product-id> --type CONSUMABLE
asc iap update <bundle-id> <product-id> --name "100 Gold Coins"
asc iap delete <bundle-id> <product-id>
```

## Soumettre pour examen

```bash
asc iap submit <bundle-id> <product-id>
```

## Localisations

```bash
asc iap localizations view <bundle-id> <product-id>
asc iap localizations export <bundle-id> <product-id>
asc iap localizations import <bundle-id> <product-id> --file iap-de.json
```

La commande d'import crée automatiquement les langues manquantes avec confirmation, vous permettant d'ajouter de nouvelles langues sans passer par App Store Connect.
