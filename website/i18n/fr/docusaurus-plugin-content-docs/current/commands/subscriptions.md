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
