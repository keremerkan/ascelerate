---
sidebar_position: 2
title: Builds
---

# Builds

## Builds auflisten

```bash
ascelerate builds list
ascelerate builds list --bundle-id <bundle-id>
ascelerate builds list --bundle-id <bundle-id> --version 2.1.0
ascelerate builds list --bundle-id <bundle-id> --platform macos
```

Die Ausgabe zeigt für jeden Build die App-Version, die Plattform, die Build-Nummer, den Verarbeitungsstatus und das Upload-Datum. Mit `--json` erhalten Sie eine maschinenlesbare Ausgabe ([Konventionen](../guides/automation.md#json-output)).

## Archivieren

```bash
ascelerate builds archive
ascelerate builds archive --scheme MyApp --output ./archives
```

Der `archive`-Befehl erkennt automatisch den `.xcworkspace` oder `.xcodeproj` im aktuellen Verzeichnis und bestimmt das Scheme, wenn nur eines vorhanden ist.

## Validieren

```bash
ascelerate builds validate MyApp.ipa
```

## Hochladen

```bash
ascelerate builds upload MyApp.ipa
```

Akzeptiert `.ipa`-, `.pkg`- oder `.xcarchive`-Dateien. Bei einem `.xcarchive` wird die Plattform des Archivs erkannt und vor dem Hochladen automatisch nach `.ipa` (iOS-Familie) bzw. `.pkg` (macOS) exportiert; die passende Plattform wird an altool übergeben.

## Auf Verarbeitung warten

```bash
ascelerate builds await-processing <bundle-id>
ascelerate builds await-processing <bundle-id> --build-version 903
ascelerate builds await-processing <bundle-id> --build-version 903 --platform macos
```

Kürzlich hochgeladene Builds können einige Minuten brauchen, bis sie in der API erscheinen — der Befehl fragt regelmäßig mit einer Fortschrittsanzeige ab, bis der Build gefunden wurde und die Verarbeitung abgeschlossen ist.

## Einen Build einer Version zuordnen

```bash
# Interaktiv einen Build auswählen und zuordnen
ascelerate apps build attach <bundle-id>
ascelerate apps build attach <bundle-id> --version 2.1.0

# Den neuesten Build automatisch zuordnen
ascelerate apps build attach-latest <bundle-id>
ascelerate apps build attach-latest <bundle-id> --platform macos

# Den zugeordneten Build von einer Version entfernen
ascelerate apps build detach <bundle-id>
```

`build attach-latest` bietet an zu warten, wenn der neueste Build noch verarbeitet wird. Mit `--yes` wird automatisch gewartet.

Die Build-Suche erfolgt plattformspezifisch: Bei Apps mit Universalkauf können iOS- und macOS-Builds dieselben Build-Nummern verwenden, daher ziehen die attach-Befehle nur Builds heran, die zur Plattform der Zielversion passen.
