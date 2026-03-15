---
sidebar_position: 2
title: Builds
---

# Builds

## Builds auflisten

```bash
asc builds list
asc builds list --bundle-id <bundle-id>
asc builds list --bundle-id <bundle-id> --version 2.1.0
```

## Archivieren

```bash
asc builds archive
asc builds archive --scheme MyApp --output ./archives
```

Der `archive`-Befehl erkennt automatisch den `.xcworkspace` oder `.xcodeproj` im aktuellen Verzeichnis und bestimmt das Scheme, wenn nur eines vorhanden ist.

## Validieren

```bash
asc builds validate MyApp.ipa
```

## Hochladen

```bash
asc builds upload MyApp.ipa
```

Akzeptiert `.ipa`-, `.pkg`- oder `.xcarchive`-Dateien. Bei einem `.xcarchive` wird vor dem Hochladen automatisch nach `.ipa` exportiert.

## Auf Verarbeitung warten

```bash
asc builds await-processing <bundle-id>
asc builds await-processing <bundle-id> --build-version 903
```

Kürzlich hochgeladene Builds können einige Minuten brauchen, bis sie in der API erscheinen — der Befehl fragt regelmäßig mit einer Fortschrittsanzeige ab, bis der Build gefunden wurde und die Verarbeitung abgeschlossen ist.

## Einen Build einer Version zuordnen

```bash
# Interaktiv einen Build auswählen und zuordnen
asc apps build attach <bundle-id>
asc apps build attach <bundle-id> --version 2.1.0

# Den neuesten Build automatisch zuordnen
asc apps build attach-latest <bundle-id>

# Den zugeordneten Build von einer Version entfernen
asc apps build detach <bundle-id>
```

`build attach-latest` bietet an zu warten, wenn der neueste Build noch verarbeitet wird. Mit `--yes` wird automatisch gewartet.
