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
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99 --base-territory GBR
```

`--base-territory` verwendet standardmäßig die bestehende Basisregion (oder USA bei einem neuen Plan). Wenn der Plan regionsspezifische manuelle Preise enthält, zeigt `set` ein interaktives Menü an, in dem Sie diese optional zur automatischen Anpassung von der neuen Basisregion zurücksetzen können. Mit `--remove-all-overrides` werden alle manuellen Preise ohne Rückfrage entfernt.

### Regionsspezifische manuelle Preise

```bash
# Manuellen Preis hinzufügen oder aktualisieren
ascelerate iap pricing override <bundle-id> <product-id> --price 5.99 --territory FRA

# Manuellen Preis entfernen (Region wird wieder automatisch von der Basisregion angepasst)
ascelerate iap pricing remove <bundle-id> <product-id> --territory FRA
```

`override` und `remove` arbeiten nur mit Nicht-Basisregionen. Um den Preis der Basisregion zu ändern, verwenden Sie `set`.

Wenn ein In-App-Kauf keinen Preisplan hat, geben sowohl `iap info` als auch `iap pricing show` eine Warnung aus; derselbe Zustand wird in `apps review preflight` als blockierender Fehler für die Einreichung markiert.

## Regionale Verfügbarkeit

Jeder In-App-Kauf hat seine eigene regionale Verfügbarkeit, unabhängig von der App. Standardmäßig erbt ein IAP die Regionen der App; sobald Sie `iap availability` mit Änderungen aufrufen, hat der IAP eine explizite Liste.

```bash
# Aktuelle IAP-spezifische Regionen anzeigen
ascelerate iap availability <bundle-id> <product-id>

# Regionsliste bearbeiten (POST ersetzt die gesamte Liste)
ascelerate iap availability <bundle-id> <product-id> --add CHN,RUS
ascelerate iap availability <bundle-id> <product-id> --remove ITA
ascelerate iap availability <bundle-id> <product-id> --available-in-new-territories true
```

## Angebotscodes

Angebotscodes sind einlösbare Codes, die einen einmaligen Rabatt auf einen IAP gewähren. Sie werden in zwei Varianten unter derselben Angebotscode-Ressource verwaltet:

- **Einmalnutzungscodes**: Apple generiert N eindeutige Codes in einem Batch (asynchron). Jeder kann nur einmal eingelöst werden.
- **Benutzerdefinierte Codes**: vom Entwickler bereitgestellte Zeichenfolge (z. B. `PROMO2026`), N-mal einlösbar.

```bash
# Alle Angebotscodes eines IAP auflisten
ascelerate iap offer-code list <bundle-id> <product-id>

# Details + Code-Zähler für einen Angebotscode anzeigen
ascelerate iap offer-code info <bundle-id> <product-id> <offer-code-id>

# Angebotscode mit rabattiertem Preis erstellen (auto-equalisiert über alle Regionen)
ascelerate iap offer-code create <bundle-id> <product-id> \
  --name "Launch Promo" \
  --eligibility NON_SPENDER,ACTIVE_SPENDER \
  --price 0.99 --territory USA --equalize-all-territories

# Aktivieren oder deaktivieren
ascelerate iap offer-code toggle <bundle-id> <product-id> <offer-code-id> --active true

# Batch von Einmalnutzungscodes generieren (Codes werden asynchron erstellt)
ascelerate iap offer-code gen-codes <bundle-id> <product-id> <offer-code-id> \
  --count 100 --expires 2026-12-31

# Tatsächliche Codewerte nach Abschluss der Generierung abrufen
ascelerate iap offer-code view-codes <one-time-use-batch-id> --output codes.txt

# Vom Entwickler definierten benutzerdefinierten Code hinzufügen
ascelerate iap offer-code add-custom-codes <bundle-id> <product-id> <offer-code-id> \
  --code PROMO2026 --count 1000 --expires 2026-12-31
```

Kundenberechtigungen für IAP-Angebotscodes: `NON_SPENDER`, `ACTIVE_SPENDER`, `CHURNED_SPENDER`.

## Werbebilder

Werbebilder hochladen, die im App Store neben dem IAP angezeigt werden.

```bash
ascelerate iap images list <bundle-id> <product-id>
ascelerate iap images upload <bundle-id> <product-id> ./hero.png
ascelerate iap images delete <bundle-id> <product-id> <image-id>
```

Uploads verwenden Apples 3-Schritt-Flow: mit `fileSize` + `fileName` reservieren, Dateichunks an vorsignierte URLs per PUT senden, dann mit dem MD5 der Datei per PATCH festschreiben. Die CLI erledigt alle drei Schritte in einem einzigen `upload`-Aufruf.

## App-Review-Screenshot

Jeder IAP kann höchstens einen App-Review-Screenshot haben (für Apples Prüfer sichtbar). Ein Upload ersetzt einen vorhandenen.

```bash
ascelerate iap review-screenshot view <bundle-id> <product-id>
ascelerate iap review-screenshot upload <bundle-id> <product-id> ./review.png
ascelerate iap review-screenshot delete <bundle-id> <product-id>
```
