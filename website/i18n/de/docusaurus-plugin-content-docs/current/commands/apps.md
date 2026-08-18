---
sidebar_position: 1
title: Apps
---

# Apps

## Apps auflisten

```bash
ascelerate apps list
```

## App-Details

```bash
ascelerate apps info <bundle-id>
```

## Versionen auflisten

```bash
ascelerate apps versions <bundle-id>
```

`apps list`, `apps info` und `apps versions` akzeptieren alle `--json` für maschinenlesbare Ausgabe ([Konventionen](../guides/automation.md#json-output)).

## Version erstellen

```bash
ascelerate apps create-version <bundle-id> <version-string>
ascelerate apps create-version <bundle-id> 2.1.0 --platform ios --release-type manual
```

Der `--release-type` ist optional — wird er weggelassen, wird die Einstellung der vorherigen Version verwendet.

:::note Universalkauf
Bei Apps mit Universalkauf (ein App Store-Eintrag, der iOS, macOS, tvOS und/oder visionOS umfasst) kann dieselbe Versionsnummer einmal pro Plattform existieren. `create-version` und `review submit` verwenden standardmäßig iOS — übergeben Sie `--platform macos` (oder `tvos`, `visionos`), um eine andere Plattform anzusprechen. Alle anderen versionsbezogenen Befehle (Lokalisierungen, Medien, Build-Zuordnung, Review-Preflight/-Informationen/-Anhänge, `resolve-issues`/`cancel-submission`, stufenweise Veröffentlichung, manuelle Veröffentlichung) akzeptieren ebenfalls ein optionales `--platform`; ohne diese Option fragen sie nach, wenn eine Version (oder eine aktive Review-Einreichung) für mehr als eine Plattform existiert — mit `--yes` brechen sie stattdessen mit einem Hinweis ab.
:::

## Copyright

```bash
ascelerate apps copyright <bundle-id>
ascelerate apps copyright <bundle-id> --set "2026 Your Name" --version 2.1.0 --platform macos
```

Ohne `--set` wird der aktuelle Copyright-Hinweis angezeigt. Für die Aktualisierung muss sich die Version in einem bearbeitbaren Zustand befinden.

## Review

### Review-Status prüfen

```bash
ascelerate apps review status <bundle-id>
ascelerate apps review status <bundle-id> --version 2.1.0
```

Mit `--json` erhalten Sie die Einreichungen — einschließlich der Status der einzelnen Elemente — als maschinenlesbares JSON.

### Zur Überprüfung einreichen

```bash
ascelerate apps review submit <bundle-id>
ascelerate apps review submit <bundle-id> --version 2.1.0
ascelerate apps review submit <bundle-id> --platform macos
```

Beim Einreichen erkennt der Befehl automatisch IAPs und Abonnements mit ausstehenden Änderungen und bietet an, diese zusammen mit der App-Version einzureichen.

### Abgelehnte Elemente lösen

Nach der Behebung von Problemen und der Antwort im Resolution Center:

```bash
ascelerate apps review resolve-issues <bundle-id>
```

### Einreichung abbrechen

```bash
ascelerate apps review cancel-submission <bundle-id>
```

### App-Review-Informationen

Zeigen oder aktualisieren Sie die Kontaktdaten, das Demo-Konto und die Hinweise für die App-Prüfung. Ohne Flags werden die aktuellen Werte ausgegeben; geben Sie ein Feld-Flag an, um es zu aktualisieren (nicht angegebene Felder bleiben unverändert).

```bash
ascelerate apps review info <bundle-id>
ascelerate apps review info <bundle-id> --contact-email du@example.com --demo-account-name reviewer --demo-account-password "hunter2" --demo-account-required true --notes "Testschritte…"

# Anhänge (Demo-Videos, Dokumente usw.)
ascelerate apps review attachment list <bundle-id>
ascelerate apps review attachment upload <bundle-id> demo.mp4
ascelerate apps review attachment delete <attachment-id>
```

## Preflight-Prüfungen

Führen Sie vor dem Einreichen zur Überprüfung `preflight` aus, um sicherzustellen, dass alle erforderlichen Felder in jeder Sprache ausgefüllt sind:

```bash
# Die neueste bearbeitbare Version prüfen
ascelerate apps review preflight <bundle-id>

# Eine bestimmte Version prüfen
ascelerate apps review preflight <bundle-id> --version 2.1.0
```

Der Befehl prüft den Versionsstatus, die Build-Zuordnung und geht dann jede Sprache durch, um Lokalisierungsfelder (Beschreibung, Neuigkeiten, Schlüsselwörter, Support-URL), App-Info-Felder (Name, Untertitel, Datenschutzrichtlinien-URL) und Screenshots zu überprüfen:

```
Preflight checks for MyApp v2.1.0 (Prepare for Submission)

Check                                Status
──────────────────────────────────────────────────────────────────
Version state                        ✓ Prepare for Submission
Build attached                       ✓ Build 42

en-US (English (United States))
  App info                           ✓ All fields filled
  Localizations                      ✓ All fields filled
  Screenshots                        ✓ 2 sets, 10 screenshots

de-DE (German (Germany))
  App info                           ✗ Missing: Privacy Policy URL
  Localizations                      ✗ Missing: What's New
  Screenshots                        ✗ No screenshots
──────────────────────────────────────────────────────────────────
Result: 5 passed, 3 failed
```

Die Prüfung der Neuigkeiten wird übersprungen, wenn die App noch keine veröffentlichte Version hat — dieses Feld gibt es nur bei Updates, nicht bei einer Erstveröffentlichung.

Der Befehl gibt einen Exit-Code ungleich Null zurück, wenn eine Prüfung fehlschlägt — und ist damit geeignet für CI-Pipelines und Workflow-Dateien. Mit `--json` gibt der Befehl statt der Tabelle einen strukturierten Bericht aus — einen booleschen `passed`-Wert plus einen Eintrag pro Prüfung (`group`, `name`, `passed`, `detail`) — und behält dabei das gleiche Exit-Code-Verhalten bei, sodass CI-Gates genau melden können, welche Prüfung fehlgeschlagen ist.

## Stufenweise Veröffentlichung

```bash
# Status der stufenweisen Veröffentlichung anzeigen
ascelerate apps phased-release <bundle-id>

# Stufenweise Veröffentlichung aktivieren (startet inaktiv, wird aktiv wenn die Version live geht)
ascelerate apps phased-release <bundle-id> --enable

# Eine stufenweise Veröffentlichung pausieren, fortsetzen oder abschließen
ascelerate apps phased-release <bundle-id> --pause
ascelerate apps phased-release <bundle-id> --resume
ascelerate apps phased-release <bundle-id> --complete

# Stufenweise Veröffentlichung vollständig entfernen
ascelerate apps phased-release <bundle-id> --disable
```

## Manuelle Veröffentlichung

Wenn die Veröffentlichungsoption einer Version auf manuell gesetzt ist, verbleibt die genehmigte Version im Status „Pending Developer Release", bis Sie sie veröffentlichen:

```bash
# Die Version veröffentlichen, die auf die Freigabe durch den Entwickler wartet
ascelerate apps release <bundle-id>

# Eine bestimmte Version oder Plattform ansteuern
ascelerate apps release <bundle-id> --version 2.1.0 --platform macos
```

## Länderverfügbarkeit

```bash
# Anzeigen, in welchen Ländern die App verfügbar ist
ascelerate apps availability <bundle-id>

# Vollständige Ländernamen anzeigen
ascelerate apps availability <bundle-id> --verbose

# Verfügbarkeit in Ländern aktivieren oder deaktivieren
ascelerate apps availability <bundle-id> --add CHN,RUS
ascelerate apps availability <bundle-id> --remove CHN
```

## Verschlüsselungserklärungen

```bash
# Bestehende Verschlüsselungserklärungen anzeigen
ascelerate apps encryption <bundle-id>

# Neue Verschlüsselungserklärung erstellen
ascelerate apps encryption <bundle-id> --create --description "Uses HTTPS for API communication"
ascelerate apps encryption <bundle-id> --create --description "Uses AES encryption" --proprietary-crypto --third-party-crypto
```

## EULA

```bash
# Aktuelle EULA anzeigen (oder sehen, dass die Standard-Apple-EULA gilt)
ascelerate apps eula <bundle-id>

# Benutzerdefinierte EULA aus einer Textdatei setzen
ascelerate apps eula <bundle-id> --file eula.txt

# Benutzerdefinierte EULA entfernen (kehrt zur Standard-Apple-EULA zurück)
ascelerate apps eula <bundle-id> --delete
```

## Abonnement-Kulanzzeitraum

Der Kulanzzeitraum ermöglicht es Abonnenten, nach einer fehlgeschlagenen Verlängerungszahlung für eine kurze Zeit Zugriff zu behalten, während Apple die Abrechnung erneut versucht. Die Einstellung gilt für die gesamte App.

```bash
# Aktuelle Konfiguration anzeigen
ascelerate apps subscription-grace-period <bundle-id>

# Für die Produktion mit 16 Tagen aktivieren, gilt für alle Verlängerungen
ascelerate apps subscription-grace-period <bundle-id> \
  --opt-in true --duration SIXTEEN_DAYS --renewal-type ALL_RENEWALS

# Auch für Sandbox-Tests aktivieren
ascelerate apps subscription-grace-period <bundle-id> --sandbox-opt-in true
```

Gültige `--duration`-Werte: `THREE_DAYS`, `SIXTEEN_DAYS`, `TWENTY_EIGHT_DAYS`. Gültige `--renewal-type`-Werte: `ALL_RENEWALS`, `PAID_TO_PAID_ONLY`.
