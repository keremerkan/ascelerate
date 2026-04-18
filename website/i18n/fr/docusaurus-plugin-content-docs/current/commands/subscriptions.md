---
sidebar_position: 7
title: Abonnements
---

# Abonnements

## Lister et inspecter

```bash
ascelerate sub groups <bundle-id>
ascelerate sub list <bundle-id>
ascelerate sub info <bundle-id> <product-id>
```

## Créer, mettre à jour et supprimer des abonnements

```bash
ascelerate sub create <bundle-id> --name "Monthly" --product-id <product-id> --period ONE_MONTH --group-id <group-id>
ascelerate sub update <bundle-id> <product-id> --name "Monthly Plan"
ascelerate sub delete <bundle-id> <product-id>
```

## Groupes d'abonnements

```bash
ascelerate sub create-group <bundle-id> --name "Premium"
ascelerate sub update-group <bundle-id> --name "Premium Plus"
ascelerate sub delete-group <bundle-id>
```

## Soumettre pour examen

```bash
ascelerate sub submit <bundle-id> <product-id>
```

## Localisations d'abonnements

```bash
ascelerate sub localizations view <bundle-id> <product-id>
ascelerate sub localizations export <bundle-id> <product-id>
ascelerate sub localizations import <bundle-id> <product-id> --file sub-de.json
```

## Localisations de groupes

```bash
ascelerate sub group-localizations view <bundle-id>
ascelerate sub group-localizations export <bundle-id>
ascelerate sub group-localizations import <bundle-id> --file group-de.json
```

Les commandes d'import créent automatiquement les langues manquantes avec confirmation, vous permettant d'ajouter de nouvelles langues sans passer par App Store Connect.

## Tarification

La tarification des abonnements est spécifique à chaque région. Il n'existe pas de mécanisme d'alignement automatique comme pour les achats intégrés — chaque région que vous souhaitez tarifer nécessite son propre enregistrement. La CLI permet soit de définir le prix pour une seule région, soit de le diffuser sur toutes les régions en utilisant les paliers tarifaires en monnaie locale d'Apple.

```bash
# Afficher les prix actuels par région (avertit s'il n'y en a pas)
ascelerate sub pricing show <bundle-id> <product-id>

# Lister les paliers tarifaires disponibles pour une région
ascelerate sub pricing tiers <bundle-id> <product-id> --territory USA

# Définir le prix pour une seule région
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --territory USA

# Diffuser le prix sur toutes les régions (un POST par région)
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --equalize-all-territories
```

### Changements de prix et abonnés existants

Apple traite les changements de prix différemment pour les abonnés existants selon le sens du changement. `sub pricing set` récupère le prix actuel pour chaque région concernée, classe le changement et applique le bon comportement :

- **Baisse** : les abonnés existants passent automatiquement au prix inférieur. Les exécutions interactives demandent confirmation avec un avertissement. En mode `--yes`, vous devez ajouter `--confirm-decrease` pour reconnaître l'impact sur les revenus — `--yes` seul ne suffit pas.
- **Hausse** : vous devez choisir explicitement comment gérer les abonnés existants. La commande échoue à moins que l'une des options suivantes ne soit définie :
  - `--preserve-current` — conserve les abonnés existants à leur ancien prix
  - `--no-preserve-current` — applique le nouveau prix aux abonnés existants après la période de notification d'Apple
- **Nouvelle région** (aucun prix existant) : pas d'abonnés existants à considérer ; les drapeaux sont facultatifs.
- **Inchangé** : ignoré silencieusement.

Les mêmes règles s'appliquent de manière agrégée pour `--equalize-all-territories`. Si une région de la diffusion est une hausse, le drapeau de préservation est requis pour toutes. Si l'une est une baisse en mode `--yes`, `--confirm-decrease` est requis.

```bash
# Hausse de prix globale standard : $4.99 → $9.99 dans toutes les régions,
# conserver les abonnés existants à l'ancien prix
ascelerate sub pricing set myapp com.example.monthly \
  --price 9.99 --territory USA --equalize-all-territories \
  --preserve-current
```

## Disponibilité territoriale

Chaque abonnement a sa propre disponibilité territoriale, indépendante de l'application. Par défaut, un abonnement hérite des territoires de son application ; dès que vous appelez `sub availability` avec des modifications, l'abonnement obtient une liste explicite.

```bash
ascelerate sub availability <bundle-id> <product-id>
ascelerate sub availability <bundle-id> <product-id> --add CHN,RUS
ascelerate sub availability <bundle-id> <product-id> --remove ITA
ascelerate sub availability <bundle-id> <product-id> --available-in-new-territories true
```

## Offres d'introduction

Les offres d'introduction ciblent les **nouveaux abonnés** — essais gratuits et remises d'introduction.

```bash
ascelerate sub intro-offer list <bundle-id> <product-id>

# Essai gratuit (pas de prix nécessaire ; --periods + --duration définissent la durée)
ascelerate sub intro-offer create <bundle-id> <product-id> \
  --mode FREE_TRIAL --duration ONE_WEEK --periods 1

# Remise pay-as-you-go (3 mois à 0,99 $/mois, limité aux USA)
ascelerate sub intro-offer create <bundle-id> <product-id> \
  --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --territory USA --price 0.99

# Mettre à jour uniquement la date de fin (les autres champs nécessitent suppression + recréation)
ascelerate sub intro-offer update <bundle-id> <product-id> <offer-id> --end-date 2026-12-31

ascelerate sub intro-offer delete <bundle-id> <product-id> <offer-id>
```

Modes : `FREE_TRIAL`, `PAY_AS_YOU_GO`, `PAY_UP_FRONT`. Sans `--territory`, l'offre s'applique globalement ; avec `--territory`, elle est limitée à cette seule région. `--price` est requis pour les deux modes payants et interdit pour `FREE_TRIAL`.

## Offres promotionnelles

Les offres promotionnelles ciblent les **abonnés existants** — typiquement utilisées pour les flux de montée en gamme dans l'application. Le code de l'offre (la valeur `--code`) doit être intégré dans une charge utile signée que votre serveur génère au moment de l'exécution avant que les clients puissent l'utiliser.

```bash
ascelerate sub promo-offer list <bundle-id> <product-id>
ascelerate sub promo-offer info <bundle-id> <product-id> <offer-id>

# Créer — même motif mono-région ou --equalize-all-territories
ascelerate sub promo-offer create <bundle-id> <product-id> \
  --name "Loyalty 50%" --code LOYALTY50 \
  --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --price 4.99 --territory USA --equalize-all-territories

# Mettre à jour uniquement les prix (les autres champs nécessitent suppression + recréation)
ascelerate sub promo-offer update <bundle-id> <product-id> <offer-id> \
  --price 5.99 --equalize-all-territories

ascelerate sub promo-offer delete <bundle-id> <product-id> <offer-id>
```

## Codes promotionnels

Codes échangeables pour abonnements, en deux variantes :

- **Codes à usage unique** : Apple génère N codes uniques dans un lot (de manière asynchrone).
- **Codes personnalisés** : chaîne fournie par le développeur, utilisable N fois.

```bash
ascelerate sub offer-code list <bundle-id> <product-id>
ascelerate sub offer-code info <bundle-id> <product-id> <offer-code-id>

# Créer un code promotionnel (avec tous les attributs d'offre)
ascelerate sub offer-code create <bundle-id> <product-id> \
  --name "Launch Free Month" \
  --eligibility NEW \
  --offer-eligibility STACK_WITH_INTRO_OFFERS \
  --mode FREE_TRIAL --duration ONE_MONTH --periods 1 \
  --price 0 --territory USA --equalize-all-territories

ascelerate sub offer-code toggle <bundle-id> <product-id> <offer-code-id> --active true

# Générer des codes à usage unique (asynchrone)
ascelerate sub offer-code gen-codes <bundle-id> <product-id> <offer-code-id> \
  --count 500 --expires 2026-12-31

# Récupérer les valeurs réelles des codes une fois la génération terminée
ascelerate sub offer-code view-codes <one-time-use-batch-id> --output codes.txt

# Ajouter un code personnalisé fourni par le développeur
ascelerate sub offer-code add-custom-codes <bundle-id> <product-id> <offer-code-id> \
  --code SUBPROMO --count 1000 --expires 2026-12-31
```

Éligibilités client pour les codes promotionnels d'abonnement : `NEW`, `EXISTING`, `EXPIRED`. Éligibilité de l'offre : `STACK_WITH_INTRO_OFFERS` ou `REPLACE_INTRO_OFFERS`.

## Soumettre un groupe d'abonnements pour examen

Les groupes d'abonnements sont examinés en même temps que la prochaine version de l'application. `sub submit-group` est l'équivalent au niveau du groupe de `sub submit`.

```bash
ascelerate sub submit-group <bundle-id>
```

## Images promotionnelles

Téléchargez les images promotionnelles affichées à côté de l'abonnement dans l'App Store.

```bash
ascelerate sub images list <bundle-id> <product-id>
ascelerate sub images upload <bundle-id> <product-id> ./hero.png
ascelerate sub images delete <bundle-id> <product-id> <image-id>
```

## Capture d'écran d'examen App Review

Chaque abonnement peut avoir au plus une capture d'écran App Review. Un téléchargement remplace toute capture existante.

```bash
ascelerate sub review-screenshot view <bundle-id> <product-id>
ascelerate sub review-screenshot upload <bundle-id> <product-id> ./review.png
ascelerate sub review-screenshot delete <bundle-id> <product-id>
```

Les téléchargements d'images et de captures d'écran utilisent le flux en 3 étapes d'Apple (réserver → envoyer les morceaux par PUT → valider avec MD5). Un seul appel `upload` gère les trois étapes.

## Offres de reconquête (pas encore implémentées)

Les offres de reconquête (offres pour les abonnés perdus) ne sont intentionnellement pas encore implémentées. Le type `WinBackOfferPriceInlineCreate` dans notre dépendance `asc-swift` ne contient pas les relations `territory` et `subscriptionPricePoint` requises par l'API, donc nous ne pouvons pas construire une requête de création valide. À revoir lorsque la dépendance sera mise à jour.
