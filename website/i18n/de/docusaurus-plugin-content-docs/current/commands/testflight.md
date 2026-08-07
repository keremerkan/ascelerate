---
sidebar_position: 17
title: TestFlight
---

# TestFlight

Verwalten Sie TestFlight-Betatests von Anfang bis Ende: Beta-Gruppen, Tester, Build-Verteilung, What-to-Test-Notizen, Beta-Review und Tester-Feedback.

Build-bezogene Befehle verwenden standardmäßig den neuesten, nicht abgelaufenen Build. Mit `--build <number>` wählen Sie einen bestimmten Build aus; wenn eine App mit Universalkauf dieselbe Build-Nummer auf mehreren Plattformen verwendet, sorgt `--platform` für Eindeutigkeit.

## Beta-Gruppen

```bash
ascelerate testflight groups list <bundle-id>
ascelerate testflight groups info <bundle-id> "External Testers"
ascelerate testflight groups create <bundle-id> --name "Friends" --public-link --public-link-limit 100
ascelerate testflight groups update <bundle-id> "Friends" --public-link false
ascelerate testflight groups delete <bundle-id> "Friends"
```

`groups list` zeigt für jede Gruppe den Typ, den öffentlichen Link, das Tester-Limit und die Feedback-Einstellung. `groups info` ergänzt die Tester und die zugewiesenen Builds der Gruppe. `create` akzeptiert `--internal` für eine interne Gruppe (Teammitglieder) und `--all-builds`, um ihr automatischen Zugriff auf alle Builds zu geben; externe Gruppen können einen öffentlichen Einladungslink mit optionalem Tester-Limit aktivieren.

Gruppennamen werden ohne Beachtung der Groß-/Kleinschreibung abgeglichen. Lassen Sie den Namen weg, um aus einer interaktiven Liste zu wählen.

### Builds zuweisen

```bash
# Standardmäßig wird der neueste, nicht abgelaufene Build verwendet
ascelerate testflight groups add-build <bundle-id> "Friends"
ascelerate testflight groups add-build <bundle-id> "Friends" --build 123
ascelerate testflight groups remove-build <bundle-id> "Friends" --build 123
```

### Aufnahmekriterien

Gruppen mit öffentlichem Link können den Beitritt nach Gerätefamilie und Betriebssystemversion einschränken:

```bash
# Aktuelle Kriterien anzeigen, samt der von Apple akzeptierten Geräte-/OS-Optionen
ascelerate testflight groups criteria view <bundle-id> "Friends" --options

# Kriterien ersetzen: FAMILY[:MIN[:MAX]] mit einschließenden Grenzen
ascelerate testflight groups criteria set <bundle-id> "Friends" --filter IPHONE:18.0 --filter IPAD:17.0:26

# Alle Kriterien entfernen
ascelerate testflight groups criteria clear <bundle-id> "Friends"
```

Gültige Gerätefamilien: `IPHONE`, `IPAD`, `MAC`, `APPLE_TV`, `APPLE_WATCH`, `VISION`.

## Tester

```bash
ascelerate testflight testers list <bundle-id>
ascelerate testflight testers list <bundle-id> --group "Friends"

# Das Hinzufügen versendet bei externen Gruppen die TestFlight-Einladung
ascelerate testflight testers add <bundle-id> --email tester@example.com --first-name Jane --group "Friends"

# Aus einer Gruppe oder aus der gesamten App entfernen
ascelerate testflight testers remove <bundle-id> tester@example.com --group "Friends"
ascelerate testflight testers remove <bundle-id> tester@example.com

# Einladungs-E-Mail erneut senden
ascelerate testflight testers invite <bundle-id> tester@example.com
```

`--group` akzeptiert bei `add` und `import` mehrere durch Kommas getrennte Gruppennamen.

### Massenimport

```bash
ascelerate testflight testers import <bundle-id> --file testers.csv --group "Friends"
```

Die Datei enthält einen Tester pro Zeile: `email[,Vorname[,Nachname]]`. Leere Zeilen, Zeilen mit `#` am Anfang und eine führende Kopfzeile werden übersprungen — das CSV-Format, das die Weboberfläche von App Store Connect exportiert, funktioniert unverändert. Fehlgeschlagene Zeilen werden am Ende gemeldet, ohne den Rest des Imports abzubrechen.

## Builds und Verteilung

```bash
# Alle Builds mit ihren TestFlight-Status
ascelerate testflight builds <bundle-id>
ascelerate testflight builds <bundle-id> --platform ios --limit 50

# Pre-Release-Versionen
ascelerate testflight versions <bundle-id>

# Vollständiger Status eines Builds
ascelerate testflight status <bundle-id> --build 123
```

`builds` listet für jeden Build den Verarbeitungsstatus, die internen und externen Teststatus sowie das Ablaufdatum auf. `status` ergänzt für einen einzelnen Build die Auto-Notify-Einstellung und den Beta-Review-Status.

```bash
# Einen Build ablaufen lassen; Tester können ihn nicht mehr installieren
ascelerate testflight expire <bundle-id> --build 123

# Tester benachrichtigen, dass ein Build verfügbar ist
ascelerate testflight notify <bundle-id>

# Automatische Benachrichtigung für einen Build ein- oder ausschalten
ascelerate testflight auto-notify <bundle-id> --enabled false
```

## What to Test

Testnotizen werden pro Build und pro Sprache gespeichert:

```bash
ascelerate testflight whats-new view <bundle-id>

# Eine Sprache oder alle vorhandenen Sprachen, wenn --locale weggelassen wird
ascelerate testflight whats-new set <bundle-id> --text "Testen Sie die neuen Kartenfilter" --locale de-DE
ascelerate testflight whats-new set <bundle-id> --text "Testen Sie die neuen Kartenfilter"

# Export und Import über JSON
ascelerate testflight whats-new export <bundle-id> --output notes.json
ascelerate testflight whats-new import <bundle-id> --file notes.json
```

Das JSON-Format entspricht den übrigen Lokalisierungsbefehlen:

```json
{
  "en-US": { "whatsNew": "Try the new map filters" },
  "de-DE": { "whatsNew": "Testen Sie die neuen Kartenfilter" }
}
```

## Beta-Review

Externe Tests erfordern für jeden Build ein Beta-Review:

```bash
ascelerate testflight submit <bundle-id> --build 123
ascelerate testflight status <bundle-id> --build 123
```

Beta-App-Informationen und Review-Details gelten auf App-Ebene:

```bash
# Beta-App-Beschreibung und Feedback-E-Mail, pro Sprache
ascelerate testflight app-info view <bundle-id>
ascelerate testflight app-info update <bundle-id> --locale de-DE --feedback-email ich@example.com
ascelerate testflight app-info export <bundle-id> --output beta-app-info.json
ascelerate testflight app-info import <bundle-id> --file beta-app-info.json

# Kontakt und Demo-Konto für das Beta-Review-Team
ascelerate testflight review-info <bundle-id>
ascelerate testflight review-info <bundle-id> --demo-account-name demo@example.com --demo-account-required true

# Eigene Beta-Lizenzvereinbarung (--text "" stellt Apples Standardvereinbarung wieder her)
ascelerate testflight eula <bundle-id>
ascelerate testflight eula <bundle-id> --file eula.txt
```

## Tester-Feedback

Absturz- und Screenshot-Feedback, das Tester über TestFlight einreichen:

```bash
ascelerate testflight feedback crashes list <bundle-id>
ascelerate testflight feedback crashes info <submission-id>
ascelerate testflight feedback crashes log <submission-id> --output crash.log
ascelerate testflight feedback crashes delete <submission-id>

ascelerate testflight feedback screenshots list <bundle-id>
ascelerate testflight feedback screenshots info <submission-id>
ascelerate testflight feedback screenshots download <bundle-id> [submission-id] --output feedback.zip
ascelerate testflight feedback screenshots delete <submission-id>
```

`list` akzeptiert die Filter `--build` und `--platform`. `info` zeigt den vollständigen Gerätekontext — Modell, Betriebssystemversion, Sprache, Verbindungstyp, Akkustand, freien Speicherplatz und den Kommentar des Testers. `log` gibt das Absturzprotokoll aus oder speichert es mit `--output`. `download` verpackt die Screenshots und den Kommentar einer Einreichung in ein Zip-Archiv; ohne Einreichungs-ID wählen Sie aus einer seitenweisen Liste der Einreichungen der App. Screenshot-URLs laufen nach wenigen Tagen ab — laden Sie Feedback, das Sie behalten möchten, rechtzeitig herunter.
