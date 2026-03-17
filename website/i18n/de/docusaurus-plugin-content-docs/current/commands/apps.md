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

## Version erstellen

```bash
ascelerate apps create-version <bundle-id> <version-string>
ascelerate apps create-version <bundle-id> 2.1.0 --platform ios --release-type manual
```

Der `--release-type` ist optional — wird er weggelassen, wird die Einstellung der vorherigen Version verwendet.

## Review

### Review-Status prüfen

```bash
ascelerate apps review status <bundle-id>
ascelerate apps review status <bundle-id> --version 2.1.0
```

### Zur Überprüfung einreichen

```bash
ascelerate apps review submit <bundle-id>
ascelerate apps review submit <bundle-id> --version 2.1.0
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

## Preflight-Prüfungen

Führen Sie vor dem Einreichen zur Überprüfung `preflight` aus, um sicherzustellen, dass alle erforderlichen Felder in jeder Sprache ausgefüllt sind:

```bash
# Die neueste bearbeitbare Version prüfen
ascelerate apps review preflight <bundle-id>

# Eine bestimmte Version prüfen
ascelerate apps review preflight <bundle-id> --version 2.1.0
```

Der Befehl prüft den Versionsstatus, die Build-Zuordnung und geht dann jede Sprache durch, um Lokalisierungsfelder (Beschreibung, Neuigkeiten, Schlüsselwörter), App-Info-Felder (Name, Untertitel, Datenschutzrichtlinien-URL) und Screenshots zu überprüfen:

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

Der Befehl gibt einen Exit-Code ungleich Null zurück, wenn eine Prüfung fehlschlägt — und ist damit geeignet für CI-Pipelines und Workflow-Dateien.

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
