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

## Regionale Verfügbarkeit

Jedes Abonnement hat seine eigene regionale Verfügbarkeit, unabhängig von der App. Standardmäßig erbt ein Abonnement die Regionen der App; sobald Sie `sub availability` mit Änderungen aufrufen, hat das Abonnement eine explizite Liste.

```bash
ascelerate sub availability <bundle-id> <product-id>
ascelerate sub availability <bundle-id> <product-id> --add CHN,RUS
ascelerate sub availability <bundle-id> <product-id> --remove ITA
ascelerate sub availability <bundle-id> <product-id> --available-in-new-territories true
```

## Einführungsangebote

Einführungsangebote richten sich an **neue Abonnenten** — kostenlose Testversionen und Einführungsrabatte.

```bash
ascelerate sub intro-offer list <bundle-id> <product-id>

# Kostenlose Testversion (kein Preis nötig; --periods + --duration legen die Dauer fest)
ascelerate sub intro-offer create <bundle-id> <product-id> \
  --mode FREE_TRIAL --duration ONE_WEEK --periods 1

# Pay-as-you-go-Rabatt (3 Monate zu $0.99/Monat, auf USA beschränkt)
ascelerate sub intro-offer create <bundle-id> <product-id> \
  --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --territory USA --price 0.99

# Nur das Enddatum aktualisieren (andere Felder erfordern Löschen + neu erstellen)
ascelerate sub intro-offer update <bundle-id> <product-id> <offer-id> --end-date 2026-12-31

ascelerate sub intro-offer delete <bundle-id> <product-id> <offer-id>
```

Modi: `FREE_TRIAL`, `PAY_AS_YOU_GO`, `PAY_UP_FRONT`. Ohne `--territory` gilt das Angebot global; mit `--territory` ist es auf diese eine Region beschränkt. `--price` ist für die beiden bezahlten Modi erforderlich und für `FREE_TRIAL` verboten.

## Werbeangebote

Werbeangebote richten sich an **bestehende Abonnenten** — typischerweise für In-App-Upsell-Flüsse. Der Angebotscode (der `--code`-Wert) muss in einer signierten Payload eingebettet sein, die Ihr Server zur Laufzeit generiert, bevor Clients ihn einlösen können.

```bash
ascelerate sub promo-offer list <bundle-id> <product-id>
ascelerate sub promo-offer info <bundle-id> <product-id> <offer-id>

# Erstellen — dasselbe Einzelregion- oder --equalize-all-territories-Muster
ascelerate sub promo-offer create <bundle-id> <product-id> \
  --name "Loyalty 50%" --code LOYALTY50 \
  --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --price 4.99 --territory USA --equalize-all-territories

# Nur Preise aktualisieren (andere Felder erfordern Löschen + neu erstellen)
ascelerate sub promo-offer update <bundle-id> <product-id> <offer-id> \
  --price 5.99 --equalize-all-territories

ascelerate sub promo-offer delete <bundle-id> <product-id> <offer-id>
```

## Angebotscodes

Einlösbare Codes für Abonnements, in zwei Varianten:

- **Einmalnutzungscodes**: Apple generiert N eindeutige Codes in einem Batch (asynchron).
- **Benutzerdefinierte Codes**: vom Entwickler bereitgestellte Zeichenfolge, N-mal einlösbar.

```bash
ascelerate sub offer-code list <bundle-id> <product-id>
ascelerate sub offer-code info <bundle-id> <product-id> <offer-code-id>

# Angebotscode erstellen (mit allen Angebots-Attributen)
ascelerate sub offer-code create <bundle-id> <product-id> \
  --name "Launch Free Month" \
  --eligibility NEW \
  --offer-eligibility STACK_WITH_INTRO_OFFERS \
  --mode FREE_TRIAL --duration ONE_MONTH --periods 1 \
  --price 0 --territory USA --equalize-all-territories

ascelerate sub offer-code toggle <bundle-id> <product-id> <offer-code-id> --active true

# Einmalnutzungscodes generieren (asynchron)
ascelerate sub offer-code gen-codes <bundle-id> <product-id> <offer-code-id> \
  --count 500 --expires 2026-12-31

# Tatsächliche Codewerte nach Abschluss der Generierung abrufen
ascelerate sub offer-code view-codes <one-time-use-batch-id> --output codes.txt

# Vom Entwickler definierten benutzerdefinierten Code hinzufügen
ascelerate sub offer-code add-custom-codes <bundle-id> <product-id> <offer-code-id> \
  --code SUBPROMO --count 1000 --expires 2026-12-31
```

Kundenberechtigungen für Abonnement-Angebotscodes: `NEW`, `EXISTING`, `EXPIRED`. Angebotsberechtigung: `STACK_WITH_INTRO_OFFERS` oder `REPLACE_INTRO_OFFERS`.

## Abonnementgruppe zur Überprüfung einreichen

Abonnementgruppen werden zusammen mit der nächsten App-Version überprüft. `sub submit-group` ist das Gruppen-Äquivalent zu `sub submit`.

```bash
ascelerate sub submit-group <bundle-id>
```

## Werbebilder

Werbebilder hochladen, die im App Store neben dem Abonnement angezeigt werden.

```bash
ascelerate sub images list <bundle-id> <product-id>
ascelerate sub images upload <bundle-id> <product-id> ./hero.png
ascelerate sub images delete <bundle-id> <product-id> <image-id>
```

## App-Review-Screenshot

Jedes Abonnement kann höchstens einen App-Review-Screenshot haben. Ein Upload ersetzt einen vorhandenen.

```bash
ascelerate sub review-screenshot view <bundle-id> <product-id>
ascelerate sub review-screenshot upload <bundle-id> <product-id> ./review.png
ascelerate sub review-screenshot delete <bundle-id> <product-id>
```

Bild- und Screenshot-Uploads verwenden Apples 3-Schritt-Flow (reservieren → Chunks per PUT → mit MD5 festschreiben). Ein einziger `upload`-Aufruf erledigt alle drei Schritte.

## Win-Back-Angebote (noch nicht implementiert)

Win-Back-Angebote (Angebote für abgewanderte Abonnenten) sind absichtlich noch nicht implementiert. Der Typ `WinBackOfferPriceInlineCreate` in unserer `asc-swift`-Abhängigkeit enthält nicht die `territory`- und `subscriptionPricePoint`-Beziehungen, die die API benötigt, sodass wir keine gültige Erstellungsanfrage konstruieren können. Wird erneut geprüft, sobald die Abhängigkeit aktualisiert wird.
