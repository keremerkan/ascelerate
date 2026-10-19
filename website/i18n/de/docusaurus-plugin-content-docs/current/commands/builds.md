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

### Über die App-Store-Connect-API hochladen

```bash
ascelerate builds upload MyApp.ipa --api
ascelerate builds upload --latest --bundle-id com.example.MyApp --api
```

Mit `--api` läuft der Build nicht über altool, sondern über die Build-Uploads der App-Store-Connect-API, mit demselben API-Schlüssel wie alle anderen Befehle. Der Befehl nimmt eine `.ipa` oder ein Mac-`.pkg` an (oder ein `.xcarchive`, das zuerst exportiert wird), liest Version und Build-Nummer aus der enthaltenen App, lädt die Datei in Teilen hoch (im Terminal mit Fortschrittsbalken; nacheinander, siehe [Upload in Teilen](../guides/automation.md#upload-chunks)) und wartet dann, bis App Store Connect die Datei angenommen hat. Lehnt Apple sie ab, schlägt der Befehl mit Apples Fehlercodes und -beschreibungen fehl; Warnungen werden nach einem erfolgreichen Upload ausgegeben. Danach läuft die Verarbeitung wie gewohnt weiter (siehe [Auf Verarbeitung warten](#await-processing)).

Vorerst bleibt altool die Standardmethode.

## Upload-Verlauf

```bash
ascelerate builds uploads <bundle-id>
ascelerate builds uploads <bundle-id> --platform macos --limit 20
ascelerate builds uploads <bundle-id> --delete-stale
```

Listet die letzten Uploads der App auf, unabhängig davon, ob sie mit altool, Xcode oder `--api` erfolgt sind, jeweils mit ihrem Status (Awaiting Upload, Processing, Complete, Failed) sowie den Fehlern und Warnungen, die Apple ihnen zugeordnet hat. Hier sollten Sie nachsehen, wenn aus einem Upload nie ein Build wird. Mit `--json` erhalten Sie eine maschinenlesbare Ausgabe.

Bricht die Verbindung im falschen Moment ab, kann ein Upload-Eintrag zurückbleiben, der auf eine Datei wartet, die nie ankommt. `--api`-Uploads entfernen solche Einträge desselben Builds, sobald sie erfolgreich waren, und `--delete-stale` entfernt alle übrigen: Einträge, die noch auf eine Datei warten, während ein anderer Upload desselben Builds bereits weiter ist, oder die schon länger als einen Tag warten. Ein laufender Upload wird nie entfernt.

## Auf Verarbeitung warten {#await-processing}

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
