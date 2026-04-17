---
sidebar_position: 7
title: Abonnements
---

# Abonnements

## Auflisten und anzeigen

```bash
ascelerate sub groups <bundle-id>
ascelerate sub list <bundle-id>
ascelerate sub info <bundle-id> <product-id>
```

## Abonnements erstellen, aktualisieren und löschen

```bash
ascelerate sub create <bundle-id> --name "Monthly" --product-id <product-id> --period ONE_MONTH --group-id <group-id>
ascelerate sub update <bundle-id> <product-id> --name "Monthly Plan"
ascelerate sub delete <bundle-id> <product-id>
```

## Abonnementgruppen

```bash
ascelerate sub create-group <bundle-id> --name "Premium"
ascelerate sub update-group <bundle-id> --name "Premium Plus"
ascelerate sub delete-group <bundle-id>
```

## Zur Überprüfung einreichen

```bash
ascelerate sub submit <bundle-id> <product-id>
```

## Abonnement-Lokalisierungen

```bash
ascelerate sub localizations view <bundle-id> <product-id>
ascelerate sub localizations export <bundle-id> <product-id>
ascelerate sub localizations import <bundle-id> <product-id> --file sub-de.json
```

## Gruppen-Lokalisierungen

```bash
ascelerate sub group-localizations view <bundle-id>
ascelerate sub group-localizations export <bundle-id>
ascelerate sub group-localizations import <bundle-id> --file group-de.json
```

Die Import-Befehle erstellen fehlende Sprachen automatisch mit Bestätigung, sodass Sie neue Sprachen hinzufügen können, ohne App Store Connect besuchen zu müssen.

## Preisgestaltung

Die Preisgestaltung von Abonnements ist regionsspezifisch. Es gibt kein automatisches Anpassungs-Konzept wie bei In-App-Käufen — jede Region, in der Sie einen Preis festlegen möchten, benötigt einen eigenen Eintrag. Die CLI legt entweder einen Preis für eine einzelne Region fest oder verteilt den Preis mithilfe der lokalen Apple-Preisstufen-Äquivalente auf alle Regionen.

```bash
# Aktuelle regionsspezifische Preise anzeigen (warnt, wenn keine vorhanden sind)
ascelerate sub pricing show <bundle-id> <product-id>

# Verfügbare Preisstufen für eine Region auflisten
ascelerate sub pricing tiers <bundle-id> <product-id> --territory USA

# Preis für eine einzelne Region festlegen
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --territory USA

# Preis auf alle Regionen verteilen (ein POST pro Region)
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --equalize-all-territories
```

### Preisänderungen und bestehende Abonnenten

Apple behandelt Preisänderungen je nach Richtung unterschiedlich für bestehende Abonnenten. `sub pricing set` ruft den aktuellen Preis für jede betroffene Region ab, klassifiziert die Änderung und erzwingt das richtige Verhalten:

- **Senkung**: bestehende Abonnenten erhalten automatisch den niedrigeren Preis. Interaktive Ausführungen geben eine Warnung aus und fragen nach. Im `--yes`-Modus müssen Sie `--confirm-decrease` hinzufügen, um die Auswirkung auf den Umsatz zu bestätigen — `--yes` allein reicht nicht aus.
- **Erhöhung**: Sie müssen ausdrücklich entscheiden, wie mit bestehenden Abonnenten umgegangen werden soll. Der Befehl gibt einen Fehler aus, sofern keine der folgenden Optionen gesetzt ist:
  - `--preserve-current` — bestehende Abonnenten behalten ihren alten Preis
  - `--no-preserve-current` — bestehende Abonnenten werden nach Apples Benachrichtigungsfrist auf den neuen Preis umgestellt
- **Neue Region** (kein bestehender Preis): keine bestehenden Abonnenten zu berücksichtigen; Flags optional.
- **Unverändert**: wird stillschweigend übersprungen.

Die gleichen Regeln gelten zusammengefasst für `--equalize-all-territories`. Wenn eine Region in der Verteilung eine Erhöhung darstellt, ist das Beibehaltungs-Flag für alle erforderlich. Wenn eine im `--yes`-Modus eine Senkung ist, ist `--confirm-decrease` erforderlich.

```bash
# Standardmäßige globale Preiserhöhung: $4.99 → $9.99 in allen Regionen,
# bestehende Abonnenten beim alten Preis belassen
ascelerate sub pricing set myapp com.example.monthly \
  --price 9.99 --territory USA --equalize-all-territories \
  --preserve-current
```
