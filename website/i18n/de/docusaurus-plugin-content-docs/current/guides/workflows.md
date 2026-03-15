---
sidebar_position: 1
title: Workflows
---

# Workflows

Verketten Sie mehrere Befehle zu einem einzigen automatisierten Durchlauf mit einer Workflow-Datei:

```bash
asc run-workflow release.txt
asc run-workflow release.txt --yes   # alle Abfragen überspringen (CI/CD)
asc run-workflow                     # interaktiv aus .workflow/.txt-Dateien auswählen
```

Eine Workflow-Datei ist eine einfache Textdatei mit einem Befehl pro Zeile (ohne das `asc`-Präfix). Zeilen, die mit `#` beginnen, sind Kommentare, leere Zeilen werden ignoriert. Sowohl `.workflow`- als auch `.txt`-Erweiterungen werden unterstützt.

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

## Verschachtelung

Workflows können andere Workflows aufrufen (`run-workflow` innerhalb einer Workflow-Datei). Zirkuläre Referenzen werden erkannt und verhindert.

## Build-Pipeline-Integration

`builds upload` setzt eine interne Variable, sodass nachfolgende `await-processing`- und `build attach-latest`-Befehle automatisch den gerade hochgeladenen Build verwenden und Race Conditions mit der API-Verzögerung vermieden werden.
