---
sidebar_position: 7
title: Abonnements
---

# Abonnements

## Lister et inspecter

```bash
asc sub groups <bundle-id>
asc sub list <bundle-id>
asc sub info <bundle-id> <product-id>
```

## Créer, mettre à jour et supprimer des abonnements

```bash
asc sub create <bundle-id> --name "Monthly" --product-id <product-id> --period ONE_MONTH --group-id <group-id>
asc sub update <bundle-id> <product-id> --name "Monthly Plan"
asc sub delete <bundle-id> <product-id>
```

## Groupes d'abonnements

```bash
asc sub create-group <bundle-id> --name "Premium"
asc sub update-group <bundle-id> --name "Premium Plus"
asc sub delete-group <bundle-id>
```

## Soumettre pour examen

```bash
asc sub submit <bundle-id> <product-id>
```

## Localisations d'abonnements

```bash
asc sub localizations view <bundle-id> <product-id>
asc sub localizations export <bundle-id> <product-id>
asc sub localizations import <bundle-id> <product-id> --file sub-de.json
```

## Localisations de groupes

```bash
asc sub group-localizations view <bundle-id>
asc sub group-localizations export <bundle-id>
asc sub group-localizations import <bundle-id> --file group-de.json
```

Les commandes d'import créent automatiquement les langues manquantes avec confirmation, vous permettant d'ajouter de nouvelles langues sans passer par App Store Connect.
