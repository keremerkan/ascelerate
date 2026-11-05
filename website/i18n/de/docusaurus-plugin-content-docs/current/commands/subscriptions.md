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

Alle drei akzeptieren `--json` für maschinenlesbare Ausgabe ([Konventionen](../guides/automation.md#json-output)); `info` meldet die Warnung zu fehlenden Preisen als booleschen `hasPricing`-Wert.

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

Ein Produkt kann eingereicht werden, sobald es eine ausstehende Version hat, also eine Version im Status „Prepare for Submission“, „Ready for Review“ oder einem abgelehnten Status. Das schließt genehmigte Produkte mit Änderungen seit der letzten Genehmigung ein. Ohne ausstehende Version bricht der Befehl ab, bevor eine Anfrage gesendet wird. `sub info` zeigt die ausstehende Version an, falls vorhanden.

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

# Preise als JSON ausgeben (Preis, Währung, Startdatum und Beibehaltungs-Flag pro Region)
ascelerate sub pricing show <bundle-id> <product-id> --json

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

### Preise zwischen Produkten kopieren

```bash
# Aktuellen Preis jeder Region als JSON exportieren
ascelerate sub pricing export <bundle-id> <product-id> --output prices.json

# Auf ein anderes Abonnement anwenden — in derselben oder einer anderen App
ascelerate sub pricing import <other-bundle-id> <other-product-id> --file prices.json
```

Die Datei enthält Kundenpreise, indiziert nach Regionscode (beibehaltene und zukünftig geplante Preise werden nicht exportiert). Beim Import wird jeder Preis anhand des Kundenpreises den Preisstufen des *Zielabonnements* zugeordnet — dieselbe Datei funktioniert daher produkt- und app-übergreifend. Der Import ändert nur die in der Datei aufgeführten Regionen, überspringt Regionen, die bereits den angegebenen Preis haben, und erzwingt dieselben Sicherheitsregeln für Erhöhungen und Senkungen wie `set` — einschließlich `--preserve-current`/`--no-preserve-current` und `--confirm-decrease`.

Ein Preis, der keine Preisstufe des Ziels ist, lässt den Import fehlschlagen; die Meldung nennt die nächstgelegenen Preisstufen. Mit `--snap` erhält jeder solche Preis stattdessen die nächstgelegene Preisstufe (bei gleichem Abstand die günstigere), und die angepassten Preise werden vor der Bestätigung aufgelistet.

Vorübergehende Fehler von App Store Connect (HTTP 429/5xx) bei Schreibvorgängen über mehrere Regionen werden automatisch wiederholt — zunächst direkt mit Wartezeit, dann in einem zweiten Durchlauf am Ende. Regionen, die weiterhin fehlschlagen, werden im Abschlussbericht aufgelistet und der Befehl endet mit einem Fehlercode; ein erneuter Aufruf desselben Befehls wiederholt nur diese, da bereits aktualisierte Regionen als unverändert übersprungen werden.

## Regionale Verfügbarkeit

Jedes Abonnement hat seine eigene regionale Verfügbarkeit, unabhängig von der App. Standardmäßig erbt ein Abonnement die Regionen der App; sobald Sie `sub availability` mit Änderungen aufrufen, hat das Abonnement eine explizite Liste.

```bash
ascelerate sub availability <bundle-id> <product-id>
ascelerate sub availability <bundle-id> <product-id> --add CHN,RUS
ascelerate sub availability <bundle-id> <product-id> --remove ITA
ascelerate sub availability <bundle-id> <product-id> --available-in-new-territories true
ascelerate sub availability <bundle-id> <product-id> --plan monthly --add DEU,FRA
```

Jahresabonnements lassen sich auch **monatlich mit 12 Monaten Mindestlaufzeit** anbieten (monatliche Abrechnung; nicht in den USA und Singapur verfügbar). Dieser Abrechnungsplan hat eine eigene Regionsliste: Mit `--plan monthly` zeigen Sie sie an oder bearbeiten sie. Ohne `--plan` gilt der Befehl für den regulären Plan mit Vorauszahlung.

## Einführungsangebote

Einführungsangebote richten sich an **neue Abonnenten** — kostenlose Testversionen und Einführungsrabatte.

```bash
ascelerate sub intro-offer list <bundle-id> <product-id>

# Kostenlose Testversion (kein Preis nötig; --periods + --duration legen die Dauer fest)
ascelerate sub intro-offer create <bundle-id> <product-id> \
  --mode FREE_TRIAL --duration ONE_WEEK --periods 1 --territories all

# Pay-as-you-go-Rabatt (3 Monate zu $0.99/Monat, auf USA beschränkt)
ascelerate sub intro-offer create <bundle-id> <product-id> \
  --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --territories USA --price 0.99

# Nur das Enddatum aktualisieren (andere Felder erfordern Löschen + neu erstellen)
ascelerate sub intro-offer update <bundle-id> <product-id> <offer-id> --end-date 2026-12-31

ascelerate sub intro-offer delete <bundle-id> <product-id> <offer-id>
```

Modi: `FREE_TRIAL`, `PAY_AS_YOU_GO`, `PAY_UP_FRONT`. `--territories` ist erforderlich: Ländercodes wie `USA,TUR` oder `all`. Apple speichert ein Angebot pro Land oder Region, und ascelerate legt sie in einer einzigen Anfrage an. Länder oder Regionen, in denen sich das Angebot mit einem bestehenden überschneiden würde oder die bereits ein künftiges Angebot haben, werden übersprungen. Der `--price` eines bezahlten Angebots gilt in der Währung des ersten Landes; die übrigen erhalten Apples vergleichbaren Preis. `--price` ist für die beiden bezahlten Modi erforderlich und für `FREE_TRIAL` nicht erlaubt.

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

## Bindungsnachrichten und -angebote

Wenn Abonnenten in ihren App Store-Abonnementeinstellungen kündigen möchten, kann der App Store ihnen eine **Bindungsnachricht** zeigen: eine Überschrift und einen Text in ihrer Sprache, optional ein Bild und Angebote zum Bleiben. Eine Nachricht gehört zur App und durchläuft App Review. Jedes Abonnement zeigt eine Nachricht und darin beliebige seiner **Bindungsangebote**.

```bash
ascelerate sub retention-message list <bundle-id>
ascelerate sub retention-message info <bundle-id> "Stay with us"
ascelerate sub retention-message create <bundle-id> --name "Stay with us" \
  --locale en-US --header "Before you go" --body "Your plan gets new features every month."
ascelerate sub retention-message localizations set <bundle-id> "Stay with us" \
  --locale de-DE --header "Bevor Sie gehen" --body "Ihr Abo erhält jeden Monat neue Funktionen."
ascelerate sub retention-message image upload <bundle-id> "Stay with us" ./retention.png
ascelerate sub retention-message submit <bundle-id> "Stay with us"
ascelerate sub retention-message new-version <bundle-id> "Stay with us"

# Bindungsangebote, dann die Nachricht und Angebote, die ein Abonnement zeigt
ascelerate sub retention-offer create <bundle-id> <product-id> \
  --name "Half off" --offer-id stay.half --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --paid-months 6 --wait-months 12 --price 4.99 --territories all
ascelerate sub retention-offer update <bundle-id> <product-id> stay.half --paid-months 3
ascelerate sub retention-message assign <bundle-id> <product-id> "Stay with us" --offers stay.half
```

- **Text und Bild:** Die Überschrift fasst 66 Zeichen, der Text 144. Das Bild ist 16:9 ohne Transparenz: 3840×2160 (PNG oder JPEG) oder 5244×2950 (PNG), eines pro Version.
- **Versionen:** Eine Nachricht hat jeweils nur eine unveröffentlichte Version. Sobald App Review sie hat, beginnt `new-version` die nächste. `submit` fügt die Nachricht der Entwurfseinreichung hinzu; senden Sie diese mit `apps review submit`.
- **Wer ein Angebot erhält:** Abonnenten, die mindestens `--paid-months` Monate (1–24, 36, 48 oder 60) bezahlt haben und, mit `--wait-months`, deren letztes Angebot 2–24 Monate zurückliegt. Nach dem Anlegen lassen sich nur diese beiden ändern, und eine Wartezeit kann nicht mehr entfernt werden.
- **Preise:** Der `--price` eines bezahlten Angebots gilt im ersten Land oder der ersten Region von `--territories`; die übrigen erhalten Apples vergleichbaren Preis. Ein kostenloser Test hat keinen Preis. `--plan monthly` richtet sich an die monatliche Zahlweise eines Jahresabonnements (standardmäßig Vorauszahlung).

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

Die Gruppe benötigt eine eigene ausstehende Version (zum Beispiel geänderte Gruppen-Lokalisierungen); andernfalls bricht der Befehl ab, bevor eine Anfrage gesendet wird.

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

## Win-Back-Angebote

Win-Back-Angebote richten sich an Personen, deren Abonnement beendet ist: Der App Store bietet ihnen ab einem Startdatum bis zu einem optionalen Enddatum einen Rabatt oder kostenlose Zeit für die Rückkehr an. Nur ein genehmigtes Abonnement kann sie haben.

```bash
ascelerate sub win-back-offer list <bundle-id> <product-id>
ascelerate sub win-back-offer info <bundle-id> <product-id> comeback.half
ascelerate sub win-back-offer create <bundle-id> <product-id> \
  --name "Come back" --offer-id comeback.half --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --since-months 3-12 --paid-months 6 --end-date 2027-01-31 --priority high --promote \
  --price 4.99 --territories all
ascelerate sub win-back-offer update <bundle-id> <product-id> comeback.half --since-months 2-24 --end-date 2027-03-31
ascelerate sub win-back-offer delete <bundle-id> <product-id> comeback.half
```

- **Wer ein Angebot erhält:** Personen, deren Abonnement vor `--since-months` Monaten endete (ein Bereich, von 1–23 bis 2–24 Monate), die mindestens `--paid-months` Monate (1–24, 36, 48 oder 60) bezahlt haben und, mit `--wait-months`, deren letztes Angebot 2–24 Monate zurückliegt.
- **Daten:** Es beginnt am `--start-date` (frühestens und standardmäßig morgen) und endet mit `--end-date` mindestens 3 Tage später.
- **Im App Store:** `--priority high` stellt es vor andere Angebote; mit `--promote` bewirbt der App Store es mit von Apple erstellten Assets.
- **Preise:** Wie bei Bindungsangeboten gilt `--price` im ersten Land oder der ersten Region von `--territories`, die übrigen erhalten Apples vergleichbaren Preis; ein kostenloser Test hat keinen Preis. Ein `PAY_AS_YOU_GO`-Angebot läuft über den Zeitraum des Abonnements selbst (`ONE_YEAR` bei einem Jahresabonnement).
- **Änderungen:** Berechtigung, Daten, Priorität und Bewerbung lassen sich ändern; für alles andere löschen Sie das Angebot und legen es neu an.
