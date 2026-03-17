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
```

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

Akzeptiert `.ipa`-, `.pkg`- oder `.xcarchive`-Dateien. Bei einem `.xcarchive` wird vor dem Hochladen automatisch nach `.ipa` exportiert.

## Auf Verarbeitung warten

```bash
ascelerate builds await-processing <bundle-id>
ascelerate builds await-processing <bundle-id> --build-version 903
```

Kürzlich hochgeladene Builds können einige Minuten brauchen, bis sie in der API erscheinen — der Befehl fragt regelmäßig mit einer Fortschrittsanzeige ab, bis der Build gefunden wurde und die Verarbeitung abgeschlossen ist.

## Einen Build einer Version zuordnen

```bash
# Interaktiv einen Build auswählen und zuordnen
ascelerate apps build attach <bundle-id>
ascelerate apps build attach <bundle-id> --version 2.1.0

# Den neuesten Build automatisch zuordnen
ascelerate apps build attach-latest <bundle-id>

# Den zugeordneten Build von einer Version entfernen
ascelerate apps build detach <bundle-id>
```

`build attach-latest` bietet an zu warten, wenn der neueste Build noch verarbeitet wird. Mit `--yes` wird automatisch gewartet.
