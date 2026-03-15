---
sidebar_position: 6
title: In-App-Käufe
---

# In-App-Käufe

## Auflisten

```bash
asc iap list <bundle-id>
asc iap list <bundle-id> --type consumable --state approved
```

Bei Filterwerten wird nicht zwischen Groß- und Kleinschreibung unterschieden. Typen: `CONSUMABLE`, `NON_CONSUMABLE`, `NON_RENEWING_SUBSCRIPTION`. Zustände: `APPROVED`, `MISSING_METADATA`, `READY_TO_SUBMIT`, `WAITING_FOR_REVIEW`, `IN_REVIEW` usw.

## Details

```bash
asc iap info <bundle-id> <product-id>
```

## Beworbene Käufe

```bash
asc iap promoted <bundle-id>
```

## Erstellen, Aktualisieren und Löschen

```bash
asc iap create <bundle-id> --name "100 Coins" --product-id <product-id> --type CONSUMABLE
asc iap update <bundle-id> <product-id> --name "100 Gold Coins"
asc iap delete <bundle-id> <product-id>
```

## Zur Überprüfung einreichen

```bash
asc iap submit <bundle-id> <product-id>
```

## Lokalisierungen

```bash
asc iap localizations view <bundle-id> <product-id>
asc iap localizations export <bundle-id> <product-id>
asc iap localizations import <bundle-id> <product-id> --file iap-de.json
```

Der Import-Befehl erstellt fehlende Sprachen automatisch mit Bestätigung, sodass Sie neue Sprachen hinzufügen können, ohne App Store Connect besuchen zu müssen.
