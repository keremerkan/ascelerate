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

## Tarification

`iap pricing` lit et écrit le calendrier de tarification. Le calendrier comporte une seule région de base — la région qu'Apple utilise pour aligner automatiquement les prix dans toutes les autres régions — ainsi que zéro ou plusieurs prix manuels spécifiques à une région.

```bash
# Afficher le calendrier de tarification actuel (avertit s'il n'est pas défini)
ascelerate iap pricing show <bundle-id> <product-id>

# Lister tous les paliers tarifaires disponibles dans une région
ascelerate iap pricing tiers <bundle-id> <product-id> --territory USA
```

### Définir le prix de la région de base

```bash
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99 --base-region GBR
```

`--base-region` prend par défaut la région de base existante (ou USA pour un nouveau calendrier). Si le calendrier comporte des prix manuels spécifiques à une région, `set` affiche un menu interactif proposant de réinitialiser certains d'entre eux à l'alignement automatique depuis la nouvelle région de base. Pour effacer tous les prix manuels sans confirmation, utilisez `--remove-all-overrides`.

### Prix manuels par région

```bash
# Ajouter ou mettre à jour un prix manuel
ascelerate iap pricing override <bundle-id> <product-id> --price 5.99 --territory FRA

# Supprimer le prix manuel (la région revient à l'alignement automatique depuis la base)
ascelerate iap pricing remove <bundle-id> <product-id> --territory FRA
```

`override` et `remove` ne fonctionnent qu'avec des régions non-base. Pour modifier le prix de la région de base, utilisez `set`.

Lorsqu'un achat intégré n'a pas de calendrier de tarification, `iap info` et `iap pricing show` affichent tous deux un avertissement ; la même condition est signalée comme bloquante dans `apps review preflight`.
