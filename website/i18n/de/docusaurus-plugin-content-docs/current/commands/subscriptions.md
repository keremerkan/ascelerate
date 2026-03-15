---
sidebar_position: 7
title: Abonnements
---

# Abonnements

## Auflisten und anzeigen

```bash
asc sub groups <bundle-id>
asc sub list <bundle-id>
asc sub info <bundle-id> <product-id>
```

## Abonnements erstellen, aktualisieren und löschen

```bash
asc sub create <bundle-id> --name "Monthly" --product-id <product-id> --period ONE_MONTH --group-id <group-id>
asc sub update <bundle-id> <product-id> --name "Monthly Plan"
asc sub delete <bundle-id> <product-id>
```

## Abonnementgruppen

```bash
asc sub create-group <bundle-id> --name "Premium"
asc sub update-group <bundle-id> --name "Premium Plus"
asc sub delete-group <bundle-id>
```

## Zur Überprüfung einreichen

```bash
asc sub submit <bundle-id> <product-id>
```

## Abonnement-Lokalisierungen

```bash
asc sub localizations view <bundle-id> <product-id>
asc sub localizations export <bundle-id> <product-id>
asc sub localizations import <bundle-id> <product-id> --file sub-de.json
```

## Gruppen-Lokalisierungen

```bash
asc sub group-localizations view <bundle-id>
asc sub group-localizations export <bundle-id>
asc sub group-localizations import <bundle-id> --file group-de.json
```

Die Import-Befehle erstellen fehlende Sprachen automatisch mit Bestätigung, sodass Sie neue Sprachen hinzufügen können, ohne App Store Connect besuchen zu müssen.
