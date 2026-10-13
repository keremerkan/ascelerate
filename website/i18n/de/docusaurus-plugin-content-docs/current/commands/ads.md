---
sidebar_position: 21
title: Apple Ads
---

# Apple Ads

Verwalten Sie Apple-Ads-Kampagnen (früher Search Ads) über die Befehlszeile mit der Apple Ads Platform API: Leistungsberichte, Kampagnen, Anzeigengruppen, Keywords und ausschließende Keywords, Gebote und Budgets, Apples Empfehlungen sowie die Keyword-Recherchedaten. Apps werden mit App Store Connect abgeglichen, daher nimmt `--app` dieselben Bundle IDs und [Aliase](../getting-started/aliases.md) an wie alle anderen Befehle. Kampagnen und Anzeigengruppen werden über ihren **Namen** (ohne Beachtung der Groß-/Kleinschreibung) oder ihre ID angesprochen; bei einem falschen Namen werden die gültigen aufgelistet.

Jeder Befehl, der etwas ändert, fragt zuerst nach einer Bestätigung (`-y` überspringt sie), und `--dry-run` gibt die genauen Anfragen aus, ohne sie zu senden ([Probelauf](../guides/automation.md#dry-run)). Änderungen kosten echtes Geld, probieren Sie sie daher zuerst mit `--dry-run` aus. Beträge gelten in der Währung des Werbekontos.

## Einrichtung

Apple Ads verwendet eigene Zugangsdaten, getrennt von Ihrem App-Store-Connect-API-Schlüssel:

1. Gehen Sie in Apple Ads zu **Account-Einstellungen → Benutzerverwaltung**, laden Sie einen Benutzer mit einer **API**-Rolle ein (zum Beispiel API Account Manager) und nehmen Sie die Einladung mit dem Apple Account dieses Benutzers an.
2. Starten Sie die Einrichtung:

```bash
ascelerate ads configure
```

ascelerate erstellt das Schlüsselpaar und gibt den öffentlichen Schlüssel aus. Melden Sie sich als API-Benutzer bei Apple Ads an, fügen Sie den Schlüssel unter **Account-Einstellungen → API** ein und geben Sie die dort angezeigte Client-ID, Team-ID und Schlüssel-ID ein. ascelerate listet dann die Werbekonten auf, auf die der Benutzer zugreifen kann, und speichert das gewählte in einem Abschnitt `ads` von `~/.ascelerate/config.json`. `--new-key` erstellt ein neues Schlüsselpaar.

```bash
ascelerate ads accounts          # Werbekonten und Rollen des API-Benutzers
```

## Berichte

```bash
ascelerate ads reports campaigns --days 30
ascelerate ads reports campaigns --from 2026-09-01 --to 2026-09-30 --app myapp
ascelerate ads reports campaigns --campaign "MyApp US" --by device
ascelerate ads reports adgroups --campaign "MyApp US"
ascelerate ads reports ads --campaign "MyApp US"
ascelerate ads reports keywords --campaign "MyApp US"
ascelerate ads reports search-terms --app myapp --days 14
```

| Bericht | Zeilen |
|---|---|
| `campaigns` | Kampagnen; `--by age gender device country region city` schlüsselt sie auf |
| `adgroups` | Anzeigengruppen (zum Beispiel um Testgruppen zu vergleichen) |
| `ads` | Anzeigen, also die Produktseite, an die jede Anzeigengruppe Taps weiterleitet |
| `keywords` | Keywords mit Apples vorgeschlagenem Gebot |
| `search-terms` | Wonach tatsächlich gesucht wurde, das passende Keyword und ob der Treffer aus Ihren Keywords oder aus Search Match stammt |

Alle Berichte nehmen `--days N` (einschließlich heute) oder `--from`/`--to`, `--app`, `--campaign`, `--all` (auch Zeilen ohne Aktivität) und `--json` an. Datumsangaben gelten in der Zeitzone des Werbekontos. Vergleichen Sie für Entscheidungen vollständige Tage: Die Zahlen von heute kommen noch herein.

Jede Zeile zeigt Ausgaben, Impressionen, Taps, Installationen, die Tap-Through-Rate (TTR), die durchschnittlichen Kosten pro Tap (CPT) und pro Installation (CPI) sowie zwei Konversionsraten:

- **CR (Tap)**: Installationen nach einem Tap, geteilt durch die Taps. Zeigt, wie gut Ihre Produktseite Personen überzeugt, die getippt haben.
- **CR (Total)**: alle Installationen einschließlich View-Through-Installationen (Personen, die die Anzeige gesehen und später ohne Tap installiert haben), geteilt durch die Taps. Sie kann über 100 % liegen.

:::note
Alter, Geschlecht und Standort unterhalb der Länderebene kennt Apple nur bei Nutzern, die personalisierte Werbung erlaubt haben; diese Aufschlüsselungen bestehen daher fast vollständig aus „Unknown“. Aufschlüsselungen nach Gerät sind vollständig. Suchbegriffe, die Apple aus Datenschutzgründen zurückhält, erscheinen als „(low volume)“.
:::

## Kampagnen

```bash
ascelerate ads campaigns list --app myapp
ascelerate ads campaigns pause "MyApp US"
ascelerate ads campaigns resume "MyApp US"
ascelerate ads campaigns budget "MyApp US" --daily 120
ascelerate ads campaigns bid "MyApp US Max Conv" --amount 2.50
```

`list` zeigt für jede Kampagne Status, Länder, Tagesbudget und Gebotsstrategie (Manual CPT oder Max Conversions). Bei einer Max-Conversions-Kampagne legt `bid` fest, wie viel sie in einer einzelnen Auktion höchstens zahlen darf. Richten Sie diesen Wert danach aus, was Ihnen eine Installation wert ist: Eine Obergrenze unter den üblichen Kosten pro Tap der Storefront bremst die Kampagne aus.

### Kampagne erstellen

```bash
ascelerate ads campaigns create --like "MyApp US" --name "MyApp US Max Conv" --max-conversions --bid 2.50 --daily 25
ascelerate ads campaigns create --app myapp --name "MyApp DE" --country DE --daily 20 --default-bid 1.00 --search-match off
```

Die Kampagne wird **pausiert** erstellt, zusammen mit ihrer Anzeigengruppe: einer automatisierten bei Max Conversions oder einer manuellen mit `--default-bid`. `--like` übernimmt App, Länder und Einstellungen einer bestehenden Kampagne. `--enabled` startet sie sofort.

```bash
ascelerate ads campaigns target-cpa --app myapp --country US
```

Zeigt Apples vorgeschlagene Zielkosten pro Installation für eine neue Max-Conversions-Kampagne.

:::tip
Die Kampagnen einer App in derselben Storefront konkurrieren nicht miteinander: Apple lässt pro Auktion nur eine von ihnen zu. Eine neue Kampagne neben einer laufenden erhält daher nur den restlichen Traffic. Um eine neue Kampagne zu testen, verlagern Sie den Traffic zu ihr, zum Beispiel indem Sie die alte auf Ihren Markennamen beschränken.
:::

## Anzeigengruppen

```bash
ascelerate ads adgroups --campaign "MyApp US"
ascelerate ads adgroups create --campaign "MyApp US" --name "Exact" --search-match off
ascelerate ads adgroups create --campaign "MyApp US" --name "Adults" --like "US Ad Group" --min-age 25
ascelerate ads adgroups update "Exact" --campaign "MyApp US" --default-bid 1.20
ascelerate ads adgroups pause "Exact" --campaign "MyApp US"
ascelerate ads adgroups resume "Exact" --campaign "MyApp US"
```

`create` übernimmt Preismodell, Gebotsstrategie und Targeting einer bestehenden Anzeigengruppe (`--like` oder die einzige Gruppe der Kampagne) und erstellt die Gruppe **pausiert**, sofern nicht `--enabled` angegeben ist. `--min-age`/`--max-age` richten sich an Altersgruppen von 18 bis 64 (ohne `--max-age` gilt 65 und älter). Alters-Targeting erreicht nur Nutzer, die personalisierte Werbung erlaubt haben, und Apple ordnet Installationen aus Anzeigengruppen mit Alters-Targeting in anderen Tools nicht der Kampagne zu. Beurteilen Sie solche Gruppen daher anhand ihrer Zahlen in Apple Ads.

## Keywords und ausschließende Keywords

```bash
ascelerate ads keywords list --campaign "MyApp US"
ascelerate ads keywords add --campaign "MyApp US" --match exact --bid 1.50 "qr scanner" "barcode reader"
ascelerate ads keywords bid --campaign "MyApp US" --bid 1.25 "qr scanner"
ascelerate ads keywords pause --campaign "MyApp US" "barcode reader"
ascelerate ads keywords copy --campaign "MyApp US" --from "US Ad Group" --to "Exact"

ascelerate ads negatives list --campaign "MyApp US"
ascelerate ads negatives add --campaign "MyApp US" "free wifi"
ascelerate ads negatives add --campaign "MyApp US" --ad-group "Discovery" --match broad "wifi"
ascelerate ads negatives remove --campaign "MyApp US" "free wifi"
```

`--ad-group` wählt die Anzeigengruppe aus, wenn eine Kampagne mehrere hat. Ausschließende Keywords gelten auf Kampagnenebene, sofern nicht `--ad-group` angegeben ist, und als genaue Übereinstimmung, sofern nicht `--match broad` angegeben ist. `keywords add` überspringt bereits vorhandene Keywords. Max-Conversions-Kampagnen wählen ihre Gebote selbst, daher gelten Keyword-Gebote für sie nicht.

## Was sich ändern lässt

```bash
ascelerate ads opportunities --app myapp
ascelerate ads opportunities --campaign "MyApp US" --days 60 --min-taps 20 --brand "my app"
```

`opportunities` vergleicht die Suchbegriffe einer Kampagne (standardmäßig die letzten 30 vollständigen Tage) mit ihren Keywords und ihren eigenen Durchschnittswerten und schlägt vor:

- **Als genaues Keyword hinzufügen**: ein konvertierender Suchbegriff ohne eigenes genaues Keyword, zu guten Kosten pro Installation.
- **Eigenes Gebot vergeben**: ein konvertierender Suchbegriff, der zu höheren Kosten über das Gebot eines anderen Keywords läuft.
- **Ausschließen**: ein Suchbegriff mit nennenswerten Ausgaben und ohne Installationen oder mit deutlich schlechteren Kosten oder einer deutlich schlechteren Konversionsrate.

Suchen nach dem Namen Ihrer App fließen nicht in die Durchschnittswerte ein und werden nie zum Ausschließen vorgeschlagen; weitere Schreibweisen Ihrer Marke fügen Sie mit `--brand` hinzu. Betrachten Sie die Ergebnisse als Kandidaten und prüfen Sie vor jeder Änderung, ob der Suchbegriff zu Ihrer App passt.

```bash
ascelerate ads recommendations
ascelerate ads recommendations apply <id>
ascelerate ads recommendations dismiss <id>
```

Apples offene Empfehlungen (Änderungen an Tagesbudget und Ziel-CPA) mit dem erwarteten Ergebnis.

```bash
ascelerate ads history --app myapp --days 7
```

Jede Änderung an Kampagnen, Anzeigengruppen, Keywords und ausschließenden Keywords in den letzten sechs Monaten mit alten und neuen Werten, auch solche, die auf der Apple-Ads-Website oder von Apple vorgenommen wurden. Hilfreich, bevor Sie eine Veränderung der Leistung deuten.

## Keyword-Recherche

```bash
ascelerate ads keywords suggest --app myapp --seed "qr code" "barcode" --country US GB
ascelerate ads keywords popularity --app myapp --country US --term "qr code" "qr scanner"
ascelerate ads keywords popularity --genre PRODUCTIVITY_UTILITIES --country US --contains scanner
ascelerate ads insights impression-share --app myapp --country US --weeks 4
```

- `suggest` liefert Apples Keyword-Vorschläge zu Ihren Ausgangsbegriffen, mit ihrer Beliebtheit und den Stellen, an denen Sie sie bereits verwenden.
- `popularity` zeigt, wie beliebt Suchbegriffe in einer Storefront (1 bis 100) und im Genre der App sind. Begriffe außerhalb der Rangliste des Genres werden gesondert aufgeführt.
- `impression-share` zeigt Ihren Anteil an den Anzeigenimpressionen und Ihren Rang für die Suchbegriffe, bei denen Ihre Anzeigen erschienen sind: Ein geringer Anteil bei einem beliebten, konvertierenden Begriff bietet Raum für Wachstum, und ein Anteil unter 100 % bei Ihrem eigenen Markennamen bedeutet, dass Wettbewerber darauf bieten.

Die Beliebtheitsdaten helfen auch bei der Wahl der App-Store-Keywords (ASO).

## Anzeigen und individuelle Produktseiten

```bash
ascelerate ads product-pages --app myapp
ascelerate ads ads --campaign "MyApp US"
ascelerate ads ads create --campaign "MyApp US" --ad-group "Scanner" --product-page "Scanner Page" --enabled
ascelerate ads ads pause "Scanner Page ad" --campaign "MyApp US"
```

Eine Anzeige leitet die Taps einer Anzeigengruppe an eine Produktseite weiter. Anzeigengruppen ohne eigene Anzeige verwenden die Standardproduktseite. Um Suchen nach einem bestimmten Bedarf auf eine [individuelle Produktseite](product-pages.md) zu leiten, geben Sie ihnen eine eigene Anzeigengruppe (`adgroups create`, `keywords add`) und erstellen eine Anzeige dafür. Pro Anzeigengruppe wird nur eine Anzeige ausgeliefert, daher pausiert `--enabled` die bisher ausgelieferte. Apple prüft neue Anzeigen; `ads ads` zeigt ihren Prüfstatus.

## Zusammen mit einem KI-Agenten

Der [ascelerate-Skill](../guides/ai-skill.md) bringt KI-Coding-Agenten bei, diese Berichte zu lesen und wann sie Änderungen vorschlagen sollten. So können Sie einen Agenten bitten, Ihre Kampagnen über alle Apps hinweg zu prüfen, Keywords zum Hinzufügen oder Ausschließen zu finden oder eine Veränderung der Leistung zu erklären. Jeder Befehl nimmt `--json` an, und Agenten werden angewiesen, Ihnen die geplanten Änderungen zu zeigen und `--dry-run` zu verwenden, bevor etwas gesendet wird.
