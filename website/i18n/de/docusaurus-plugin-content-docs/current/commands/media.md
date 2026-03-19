---
sidebar_position: 4
title: Screenshots & Vorschauen
---

# Screenshots & App-Vorschauen

## Herunterladen

```bash
ascelerate apps media download <bundle-id>
ascelerate apps media download <bundle-id> --folder my-media/ --version 2.1.0
```

Wird standardmäßig nach `<bundle-id>-media/` heruntergeladen und verwendet die gleiche Ordnerstruktur, die auch für den Upload erwartet wird.

## Hochladen

```bash
# Aus einem Ordner hochladen
ascelerate apps media upload <bundle-id> --folder media/

# Aus einer ZIP-Datei hochladen (z.B. exportiert von app-store-screenshots)
ascelerate apps media upload <bundle-id> --folder screenshots.zip

# In eine bestimmte Version hochladen
ascelerate apps media upload <bundle-id> --folder media/ --version 2.1.0

# Bestehende Medien in passenden Sets vor dem Hochladen ersetzen
ascelerate apps media upload <bundle-id> --folder media/ --replace

# Interaktiver Modus: einen Ordner oder eine ZIP-Datei aus dem aktuellen Verzeichnis auswählen
ascelerate apps media upload <bundle-id>
```

Wenn `--folder` nicht angegeben wird, listet der Befehl alle Unterverzeichnisse und `.zip`-Dateien im aktuellen Verzeichnis als nummerierte Auswahl auf. ZIP-Dateien werden vor dem Upload automatisch entpackt.

## Ordnerstruktur

Organisieren Sie Ihren Medienordner mit Unterordnern für Sprache und Anzeigetyp:

```
media/
├── en-US/
│   ├── APP_IPHONE_67/
│   │   ├── 01_home.png
│   │   ├── 02_settings.png
│   │   └── preview.mp4
│   └── APP_IPAD_PRO_3GEN_129/
│       └── 01_home.png
└── de-DE/
    └── APP_IPHONE_67/
        ├── 01_home.png
        └── 02_settings.png
```

- **Ebene 1:** Sprache (z.B. `en-US`, `de-DE`, `ja`)
- **Ebene 2:** Ordnername des Anzeigetyps (siehe Tabelle unten)
- **Ebene 3:** Mediendateien — Bilder (`.png`, `.jpg`, `.jpeg`) werden zu Screenshots, Videos (`.mp4`, `.mov`) werden zu App-Vorschauen
- Dateien werden in alphabetischer Reihenfolge nach Dateiname hochgeladen
- Nicht unterstützte Dateien werden mit einer Warnung übersprungen

## Anzeigetypen

App Store Connect erfordert **`APP_IPHONE_67`**-Screenshots für iPhone-Apps und **`APP_IPAD_PRO_3GEN_129`**-Screenshots für iPad-Apps. Alle anderen Anzeigetypen sind optional.

| Ordnername | Gerät | Screenshots | Vorschauen |
|---|---|---|---|
| `APP_IPHONE_67` | iPhone 6.7" (iPhone 17 Pro Max, 16 Pro Max, 15 Pro Max) | **Erforderlich** | Ja |
| `APP_IPAD_PRO_3GEN_129` | iPad Pro 12.9" (3. Gen.+) | **Erforderlich** | Ja |

<details>
<summary>Alle optionalen Anzeigetypen</summary>

| Ordnername | Gerät | Screenshots | Vorschauen |
|---|---|---|---|
| `APP_IPHONE_61` | iPhone 6.1" (iPhone 17 Pro, 16 Pro, 15 Pro) | Ja | Ja |
| `APP_IPHONE_65` | iPhone 6.5" (iPhone 11 Pro Max, XS Max) | Ja | Ja |
| `APP_IPHONE_58` | iPhone 5.8" (iPhone 11 Pro, X, XS) | Ja | Ja |
| `APP_IPHONE_55` | iPhone 5.5" (iPhone 8 Plus, 7 Plus, 6s Plus) | Ja | Ja |
| `APP_IPHONE_47` | iPhone 4.7" (iPhone SE 3. Gen., 8, 7, 6s) | Ja | Ja |
| `APP_IPHONE_40` | iPhone 4" (iPhone SE 1. Gen., 5s, 5c) | Ja | Ja |
| `APP_IPHONE_35` | iPhone 3.5" (iPhone 4s und älter) | Ja | Ja |
| `APP_IPAD_PRO_3GEN_11` | iPad Pro 11" | Ja | Ja |
| `APP_IPAD_PRO_129` | iPad Pro 12.9" (1./2. Gen.) | Ja | Ja |
| `APP_IPAD_105` | iPad 10.5" (iPad Air 3. Gen., iPad Pro 10.5") | Ja | Ja |
| `APP_IPAD_97` | iPad 9.7" (iPad 6. Gen. und älter) | Ja | Ja |
| `APP_DESKTOP` | Mac | Ja | Ja |
| `APP_APPLE_TV` | Apple TV | Ja | Ja |
| `APP_APPLE_VISION_PRO` | Apple Vision Pro | Ja | Ja |
| `APP_WATCH_ULTRA` | Apple Watch Ultra | Ja | Nein |
| `APP_WATCH_SERIES_10` | Apple Watch Series 10 | Ja | Nein |
| `APP_WATCH_SERIES_7` | Apple Watch Series 7 | Ja | Nein |
| `APP_WATCH_SERIES_4` | Apple Watch Series 4 | Ja | Nein |
| `APP_WATCH_SERIES_3` | Apple Watch Series 3 | Ja | Nein |
| `IMESSAGE_APP_IPHONE_67` | iMessage iPhone 6.7" | Ja | Nein |
| `IMESSAGE_APP_IPHONE_61` | iMessage iPhone 6.1" | Ja | Nein |
| `IMESSAGE_APP_IPHONE_65` | iMessage iPhone 6.5" | Ja | Nein |
| `IMESSAGE_APP_IPHONE_58` | iMessage iPhone 5.8" | Ja | Nein |
| `IMESSAGE_APP_IPHONE_55` | iMessage iPhone 5.5" | Ja | Nein |
| `IMESSAGE_APP_IPHONE_47` | iMessage iPhone 4.7" | Ja | Nein |
| `IMESSAGE_APP_IPHONE_40` | iMessage iPhone 4" | Ja | Nein |
| `IMESSAGE_APP_IPAD_PRO_3GEN_129` | iMessage iPad Pro 12.9" (3. Gen.+) | Ja | Nein |
| `IMESSAGE_APP_IPAD_PRO_3GEN_11` | iMessage iPad Pro 11" | Ja | Nein |
| `IMESSAGE_APP_IPAD_PRO_129` | iMessage iPad Pro 12.9" (1./2. Gen.) | Ja | Nein |
| `IMESSAGE_APP_IPAD_105` | iMessage iPad 10.5" | Ja | Nein |
| `IMESSAGE_APP_IPAD_97` | iMessage iPad 9.7" | Ja | Nein |

</details>

:::note
Watch- und iMessage-Anzeigetypen unterstützen nur Screenshots — Videodateien in diesen Ordnern werden mit einer Warnung übersprungen. Das `--replace`-Flag löscht alle bestehenden Assets in jedem passenden Set, bevor neue hochgeladen werden.
:::

## Verwendung mit app-store-screenshots

[app-store-screenshots](https://github.com/keremerkan/ascelerate/tree/main/skills/app-store-screenshots) ist ein begleitender Skill für KI-Coding-Agenten, der produktionsreife App Store-Screenshots generiert. Er erstellt eine Next.js-Seite, die werbeähnliche Marketing-Layouts mit gerahmten Geräte-Screenshots aus `ascelerate screenshot frame` rendert und sie als ZIP-Datei zum Hochladen via `ascelerate apps media upload` exportiert:

```
en-US/APP_IPHONE_67/01_hero.png
en-US/APP_IPAD_PRO_3GEN_129/01_hero.png
de-DE/APP_IPHONE_67/01_hero.png
```

Installieren Sie den Skill für Ihren KI-Coding-Agenten:

```bash
npx skills add keremerkan/ascelerate
```

Laden Sie die exportierte ZIP-Datei direkt hoch:

```bash
ascelerate apps media upload <bundle-id> --folder screenshots.zip --replace
```

## Blockierte Medien überprüfen und erneut versuchen

Manchmal bleiben Screenshots oder Vorschauen nach dem Upload im Status "Verarbeitung" hängen. Verwenden Sie `media verify`, um den Status zu prüfen und optional blockierte Elemente erneut zu versuchen:

```bash
# Status aller Screenshots und Vorschauen prüfen
ascelerate apps media verify <bundle-id>

# Eine bestimmte Version prüfen
ascelerate apps media verify <bundle-id> --version 2.1.0

# Blockierte Elemente mit lokalen Dateien aus dem Medienordner erneut versuchen
ascelerate apps media verify <bundle-id> --folder media/
```

Ohne `--folder` zeigt der Befehl einen reinen Statusbericht an. Sets, in denen alle Elemente abgeschlossen sind, werden als kompakte Einzeiler angezeigt; Sets mit blockierten Elementen werden erweitert, um jede Datei und ihren Status anzuzeigen. Mit `--folder` wird angeboten, blockierte Elemente erneut zu versuchen, indem sie gelöscht und aus den passenden lokalen Dateien erneut hochgeladen werden, wobei die ursprüngliche Reihenfolge beibehalten wird.
