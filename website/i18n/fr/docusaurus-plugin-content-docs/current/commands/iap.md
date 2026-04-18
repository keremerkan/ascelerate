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
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99 --base-territory GBR
```

`--base-territory` prend par défaut la région de base existante (ou USA pour un nouveau calendrier). Si le calendrier comporte des prix manuels spécifiques à une région, `set` affiche un menu interactif proposant de réinitialiser certains d'entre eux à l'alignement automatique depuis la nouvelle région de base. Pour effacer tous les prix manuels sans confirmation, utilisez `--remove-all-overrides`.

### Prix manuels par région

```bash
# Ajouter ou mettre à jour un prix manuel
ascelerate iap pricing override <bundle-id> <product-id> --price 5.99 --territory FRA

# Supprimer le prix manuel (la région revient à l'alignement automatique depuis la base)
ascelerate iap pricing remove <bundle-id> <product-id> --territory FRA
```

`override` et `remove` ne fonctionnent qu'avec des régions non-base. Pour modifier le prix de la région de base, utilisez `set`.

Lorsqu'un achat intégré n'a pas de calendrier de tarification, `iap info` et `iap pricing show` affichent tous deux un avertissement ; la même condition est signalée comme bloquante dans `apps review preflight`.

## Disponibilité territoriale

Chaque achat intégré a sa propre disponibilité territoriale, indépendante de l'application. Par défaut, un IAP hérite des territoires de son application ; dès que vous appelez `iap availability` avec des modifications, l'IAP obtient une liste explicite.

```bash
# Voir les territoires actuels spécifiques à l'IAP
ascelerate iap availability <bundle-id> <product-id>

# Modifier la liste des territoires (le POST remplace la liste complète)
ascelerate iap availability <bundle-id> <product-id> --add CHN,RUS
ascelerate iap availability <bundle-id> <product-id> --remove ITA
ascelerate iap availability <bundle-id> <product-id> --available-in-new-territories true
```

## Codes promotionnels

Les codes promotionnels sont des codes échangeables qui débloquent une réduction unique sur un IAP. Ils existent en deux variantes, gérées sous la même ressource de code promotionnel :

- **Codes à usage unique** : Apple génère N codes uniques dans un lot (de manière asynchrone). Chacun ne peut être utilisé qu'une seule fois.
- **Codes personnalisés** : chaîne fournie par le développeur (par exemple `PROMO2026`), utilisable N fois.

```bash
# Lister tous les codes promotionnels d'un IAP
ascelerate iap offer-code list <bundle-id> <product-id>

# Afficher les détails + les compteurs de codes pour un code promotionnel
ascelerate iap offer-code info <bundle-id> <product-id> <offer-code-id>

# Créer un code promotionnel avec un prix réduit (auto-équilibré sur tous les territoires)
ascelerate iap offer-code create <bundle-id> <product-id> \
  --name "Launch Promo" \
  --eligibility NON_SPENDER,ACTIVE_SPENDER \
  --price 0.99 --territory USA --equalize-all-territories

# Activer ou désactiver
ascelerate iap offer-code toggle <bundle-id> <product-id> <offer-code-id> --active true

# Générer un lot de codes à usage unique (les codes sont générés de manière asynchrone)
ascelerate iap offer-code gen-codes <bundle-id> <product-id> <offer-code-id> \
  --count 100 --expires 2026-12-31

# Récupérer les valeurs réelles des codes une fois la génération terminée
ascelerate iap offer-code view-codes <one-time-use-batch-id> --output codes.txt

# Ajouter un code personnalisé fourni par le développeur
ascelerate iap offer-code add-custom-codes <bundle-id> <product-id> <offer-code-id> \
  --code PROMO2026 --count 1000 --expires 2026-12-31
```

Éligibilités client pour les codes promotionnels IAP : `NON_SPENDER`, `ACTIVE_SPENDER`, `CHURNED_SPENDER`.

## Images promotionnelles

Téléchargez les images promotionnelles affichées à côté de l'IAP dans l'App Store.

```bash
ascelerate iap images list <bundle-id> <product-id>
ascelerate iap images upload <bundle-id> <product-id> ./hero.png
ascelerate iap images delete <bundle-id> <product-id> <image-id>
```

Les téléchargements utilisent le flux en 3 étapes d'Apple : réserver avec `fileSize` + `fileName`, envoyer les morceaux du fichier via PUT vers des URL présignées, puis valider avec le MD5 du fichier via PATCH. La CLI gère les trois étapes dans un seul appel `upload`.

## Capture d'écran d'examen App Review

Chaque IAP peut avoir au plus une capture d'écran App Review (montrée aux examinateurs d'Apple). Un téléchargement remplace toute capture existante.

```bash
ascelerate iap review-screenshot view <bundle-id> <product-id>
ascelerate iap review-screenshot upload <bundle-id> <product-id> ./review.png
ascelerate iap review-screenshot delete <bundle-id> <product-id>
```
