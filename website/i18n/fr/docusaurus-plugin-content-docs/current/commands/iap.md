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

`iap list` et `iap info` acceptent `--json` pour une sortie lisible par machine ([conventions](../guides/automation.md#json-output)) ; `info` rapporte l'avertissement de tarification manquante sous la forme d'un booléen `hasPricing`.

## Achats promus

Mettez en avant des achats intégrés ou des abonnements sur votre page produit App Store. Ils apparaissent dans l'ordre d'affichage.

```bash
ascelerate iap promoted list <bundle-id>
ascelerate iap promoted add <bundle-id> <product-id> --visible-for-all true --enabled true
ascelerate iap promoted reorder <bundle-id> com.example.a,com.example.b
ascelerate iap promoted toggle <bundle-id> <product-id> --enabled false
ascelerate iap promoted remove <bundle-id> <product-id>
```

`reorder` attend les identifiants de produit dans l'ordre souhaité ; ceux que vous omettez sont conservés et ajoutés après ceux que vous indiquez.

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

Un produit peut être soumis dès qu'il possède une version en attente, c'est-à-dire une version à l'état « Prepare for Submission », « Ready for Review » ou dans un état rejeté. Cela inclut les produits approuvés modifiés depuis leur dernière approbation. Sans version en attente, la commande s'arrête avant d'envoyer la moindre requête. `iap info` affiche la version en attente lorsqu'il y en a une.

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

`pricing show` accepte `--json` — la commande émet la région de base ainsi que chaque prix avec sa région et sa devise.

### Définir le prix de la région de base

```bash
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99 --base-territory GBR
ascelerate iap pricing set <bundle-id> <product-id> --price 5.99 --start-date 2027-03-01
```

Avec `--start-date` (AAAA-MM-JJ, après aujourd'hui), le nouveau prix de base s'applique à partir de ce jour et le prix actuel jusque-là ; le premier prix d'un produit et une nouvelle région de base s'appliquent tout de suite. Les prix définis à la main dans d'autres régions, ainsi que les prix planifiés ou temporaires, restent tels quels ; `pricing show` liste les changements planifiés, et la confirmation indique tout prix planifié ou temporaire auquel le changement met fin.

`--base-territory` prend par défaut la région de base existante (ou USA pour un nouveau calendrier). Si le calendrier comporte des prix manuels spécifiques à une région, `set` affiche un menu interactif proposant de réinitialiser certains d'entre eux à l'alignement automatique depuis la nouvelle région de base. Pour effacer tous les prix manuels sans confirmation, utilisez `--remove-all-overrides`.

### Prix manuels par région

```bash
# Ajouter ou mettre à jour un prix manuel
ascelerate iap pricing override <bundle-id> <product-id> --price 5.99 --territory FRA

# Supprimer le prix manuel (la région revient à l'alignement automatique depuis la base)
ascelerate iap pricing remove <bundle-id> <product-id> --territory FRA
```

`override` et `remove` acceptent aussi `--start-date` : le prix actuel de la région s'applique jusqu'à ce jour.

`override` et `remove` ne fonctionnent qu'avec des régions non-base. Pour modifier le prix de la région de base, utilisez `set`.

Lorsqu'un achat intégré n'a pas de calendrier de tarification, `iap info` et `iap pricing show` affichent tous deux un avertissement ; la même condition est signalée comme bloquante dans `apps review preflight`.

### Copier les prix entre produits

```bash
# Exporter le calendrier (région de base + tous les prix manuels) en JSON
ascelerate iap pricing export <bundle-id> <product-id> --output prices.json

# L'appliquer à un autre achat intégré — dans la même app ou une autre
ascelerate iap pricing import <other-bundle-id> <other-product-id> --file prices.json
```

L'import remplace aussi les prix planifiés (ils sont listés avant la confirmation). Avec `--start-date`, les prix du fichier s'appliquent à partir de ce jour et ceux d'aujourd'hui jusque-là.

Le fichier contient les prix client indexés par code de région. À l'import, chaque prix est mis en correspondance avec les paliers tarifaires du produit *cible* d'après le prix client ; le même fichier fonctionne donc d'un produit ou d'une app à l'autre. L'import remplace intégralement le calendrier : les régions absentes du fichier reviennent à l'alignement automatique, et si le calendrier actuel correspond déjà au fichier, la commande ne fait rien. Les erreurs transitoires d'App Store Connect (HTTP 429/5xx) sont automatiquement réessayées.

Tous les prix qui ne sont pas un palier de la cible sont listés en une fois, avec leurs paliers les plus proches, et rien n'est envoyé ; avec `--snap`, chacun de ces prix prend à la place le palier le plus proche (le moins cher si deux sont aussi proches), et les prix ajustés sont listés avant la confirmation. Les prix doivent être des nombres simples, comme `4.99` (ou `4,99` avec une virgule décimale) ; tout le reste (`1,300`, `1e2`, `-1`) est refusé à la lecture du fichier, chacun de ces prix étant nommé, avant toute requête.

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

`--add` et `--remove` sur un produit sans liste propre partent des pays ou régions de l'app, que le produit conserve donc.

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
