---
sidebar_position: 1
title: Workflows
---

# Workflows

Verketten Sie mehrere Befehle zu einem einzigen automatisierten Durchlauf mit einer Workflow-Datei:

```bash
ascelerate run-workflow release.txt
ascelerate run-workflow release.txt --yes   # alle Abfragen überspringen (CI/CD)
ascelerate run-workflow                     # interaktiv aus .workflow/.txt-Dateien auswählen
```

Eine Workflow-Datei ist eine einfache Textdatei mit einem Befehl pro Zeile (ohne das `ascelerate`-Präfix). Zeilen, die mit `#` beginnen, sind Kommentare, leere Zeilen werden ignoriert. Sowohl `.workflow`- als auch `.txt`-Erweiterungen werden unterstützt.

## Beispiel

`release.txt` zum Einreichen von Version 2.1.0 einer Beispiel-App:

```
# Release-Workflow für MyApp v2.1.0

# Neue Version auf App Store Connect erstellen
apps create-version com.example.MyApp 2.1.0

# Archivieren, validieren und hochladen
builds archive --scheme MyApp
builds validate --latest --bundle-id com.example.MyApp
builds upload --latest --bundle-id com.example.MyApp

# Auf Abschluss der Build-Verarbeitung warten
builds await-processing com.example.MyApp

# Lokalisierungen aktualisieren und Build anhängen
apps localizations import com.example.MyApp --file localizations.json
apps build attach-latest com.example.MyApp

# Zur App Review einreichen
apps review submit com.example.MyApp
```

## Bestätigungsverhalten

Ohne `--yes` fragt der Workflow vor dem Start nach Bestätigung, und einzelne Befehle fragen weiterhin dort nach, wo sie es normalerweise tun würden (z.B. vor dem Einreichen zur Überprüfung). Mit `--yes` werden alle Abfragen für eine vollständig unbeaufsichtigte Ausführung übersprungen.

## Einen Workflow prüfen

```bash
ascelerate run-workflow release.txt --check          # every step parses; nothing runs
ascelerate run-workflow release.txt --check --json   # each step's line, command and error
```

`--check` parst die Argumente und Optionen jedes Schritts, ohne etwas auszuführen, und listet die Schritte, die sich nicht parsen lassen, mit ihrer Zeile in der Datei auf.

## Einen Lauf aus einem anderen Programm verfolgen

```bash
ascelerate run-workflow release.txt --json-events
```

Mit `--json-events` trägt stdout ein JSON-Ereignis pro Zeile, und alles Lesbare, auch die Ausgabe der Schritte selbst, geht an stderr. Die Ereignisse sind `workflow` (die Schritte und ihre Zeilen), `step` (`running`, dann `succeeded`, `failed` mit dem Fehler oder `dry-run`), `finished` und `prompt` für jede Frage, die ein Schritt stellt: ihr `kind` (`confirm`, `choice`, `choices` oder `text`), ihre `message` und ihre `options`. Der Schritt liest die Antwort dann als eine Zeile von stdin (`y` oder `n`, die Nummer einer Option ab 1 oder den Text). Der Workflow wird nicht vorab bestätigt, denn das hat das ausführende Programm getan. Die Ereignisse eines verschachtelten Workflows tragen seine `depth`. Schritte, die allein ausgeführt eigene Ereignisse melden (`builds archive`, `builds upload`, `screenshot`), fügen sie hier nicht hinzu; ihr Fortschritt geht an stderr, außer dem eines Uploads mit `--api`, der als `progress`-Ereignisse seines Schritts kommt (`index`, `sent` von `bytes`). Die xcodebuild-Ausgabe der Schritte ist knapp (Warnungen und Fehler), sofern `ascelerate settings --xcodebuild-output full` nichts anderes festlegt.

## Verschachtelung

Workflows können andere Workflows aufrufen (`run-workflow` innerhalb einer Workflow-Datei). Zirkuläre Referenzen werden erkannt und verhindert.

## Build-Pipeline-Integration

`builds upload` setzt eine interne Variable, sodass nachfolgende `await-processing`- und `build attach-latest`-Befehle automatisch den gerade hochgeladenen Build verwenden und Race Conditions mit der API-Verzögerung vermieden werden.
