---
sidebar_position: 6
title: In-App-Käufe
---

# In-App-Käufe

## Auflisten

```bash
ascelerate iap list <bundle-id>
ascelerate iap list <bundle-id> --type consumable --state approved
```

Bei Filterwerten wird nicht zwischen Groß- und Kleinschreibung unterschieden. Typen: `CONSUMABLE`, `NON_CONSUMABLE`, `NON_RENEWING_SUBSCRIPTION`. Zustände: `APPROVED`, `MISSING_METADATA`, `READY_TO_SUBMIT`, `WAITING_FOR_REVIEW`, `IN_REVIEW` usw.

## Details

```bash
ascelerate iap info <bundle-id> <product-id>
```

## Beworbene Käufe

```bash
ascelerate iap promoted <bundle-id>
```

## Erstellen, Aktualisieren und Löschen

```bash
ascelerate iap create <bundle-id> --name "100 Coins" --product-id <product-id> --type CONSUMABLE
ascelerate iap update <bundle-id> <product-id> --name "100 Gold Coins"
ascelerate iap delete <bundle-id> <product-id>
```

## Zur Überprüfung einreichen

```bash
ascelerate iap submit <bundle-id> <product-id>
```

## Lokalisierungen

```bash
ascelerate iap localizations view <bundle-id> <product-id>
ascelerate iap localizations export <bundle-id> <product-id>
ascelerate iap localizations import <bundle-id> <product-id> --file iap-de.json
```

Der Import-Befehl erstellt fehlende Sprachen automatisch mit Bestätigung, sodass Sie neue Sprachen hinzufügen können, ohne App Store Connect besuchen zu müssen.

## Preisgestaltung

`iap pricing` liest und schreibt den Preisplan. Der Plan hat eine einzige Basisregion — die Region, die Apple verwendet, um die Preise in allen anderen Regionen automatisch anzupassen — sowie optional regionsspezifische manuelle Preise.

```bash
# Aktuellen Preisplan anzeigen (warnt, wenn keiner gesetzt ist)
ascelerate iap pricing show <bundle-id> <product-id>

# Verfügbare Preisstufen für eine Region auflisten
ascelerate iap pricing tiers <bundle-id> <product-id> --territory USA
```

### Preis der Basisregion festlegen

```bash
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99 --base-region GBR
```

`--base-region` verwendet standardmäßig die bestehende Basisregion (oder USA bei einem neuen Plan). Wenn der Plan regionsspezifische manuelle Preise enthält, zeigt `set` ein interaktives Menü an, in dem Sie diese optional zur automatischen Anpassung von der neuen Basisregion zurücksetzen können. Mit `--remove-all-overrides` werden alle manuellen Preise ohne Rückfrage entfernt.

### Regionsspezifische manuelle Preise

```bash
# Manuellen Preis hinzufügen oder aktualisieren
ascelerate iap pricing override <bundle-id> <product-id> --price 5.99 --territory FRA

# Manuellen Preis entfernen (Region wird wieder automatisch von der Basisregion angepasst)
ascelerate iap pricing remove <bundle-id> <product-id> --territory FRA
```

`override` und `remove` arbeiten nur mit Nicht-Basisregionen. Um den Preis der Basisregion zu ändern, verwenden Sie `set`.

Wenn ein In-App-Kauf keinen Preisplan hat, geben sowohl `iap info` als auch `iap pricing show` eine Warnung aus; derselbe Zustand wird in `apps review preflight` als blockierender Fehler für die Einreichung markiert.
