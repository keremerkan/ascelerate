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
ascelerate apps media upload <bundle-id> media/

# Aus einem Archiv hochladen (zip, tar, tar.gz unterstützt)
ascelerate apps media upload <bundle-id> screenshots.zip

# In eine bestimmte Version hochladen (bei Apps mit Universalkauf --platform ergänzen)
ascelerate apps media upload <bundle-id> media/ --version 2.1.0
ascelerate apps media upload <bundle-id> media/ --version 2.1.0 --platform macos

# Bestehende Medien in passenden Sets vor dem Hochladen ersetzen
ascelerate apps media upload <bundle-id> media/ --replace

# Interaktiver Modus: einen Ordner oder ein Archiv aus dem aktuellen Verzeichnis auswählen
ascelerate apps media upload <bundle-id>
```

Wenn das Ordner-Argument nicht angegeben wird, listet der Befehl alle Unterverzeichnisse und Archivdateien im aktuellen Verzeichnis als nummerierte Auswahl auf. Archive (zip, tar, tar.gz) werden vor dem Upload automatisch entpackt.

Jede Dateizeile beginnt mit ihrer Position im Durchlauf (`[57/203]`). Im Terminal zeigt die Zeile außerdem an, wie viel der Datei bereits hochgeladen ist, während sie gesendet wird.

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
| `APP_IPHONE_DUO` | iPhone Duo (siehe [unten](#iphone-duo)) | Ja | Nein |
| `PRODUCT_PAGE_HEADER` | Produktseiten-Header (siehe [unten](#header-and-search-results)) | Ja | Nein |
| `APP_STORE_SEARCH_RESULTS` | App Store-Suchergebnisse (siehe [unten](#header-and-search-results)) | Ja | Nein |
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

### iPhone Duo

App Store Connect bietet für das iPhone Duo kein Screenshot-Set. ascelerate lädt die Dateien eines `APP_IPHONE_DUO`-Ordners in die Asset-Bibliothek der App hoch und ordnet sie in der Reihenfolge der Dateinamen der Versionslokalisierung zu. Zulässig sind 2853×2007 oder 2007×2853 (inneres Display, aufgeklappt) sowie 2034×1398 oder 1398×2034 (äußeres Display); andere Größen werden abgelehnt, bevor etwas hochgeladen wird. Mit `--replace` werden die vorhandenen iPhone-Duo-Screenshots jeder Locale zuerst entfernt.

Scheitert eine Datei auch nach erneuten Versuchen, ordnet `media upload` die iPhone-Duo-Screenshots dieser Locale am Ende des Durchlaufs erneut zu, damit die Reihenfolge der Dateien erhalten bleibt. `media verify` listet iPhone-Duo-Screenshots mit Dateinamen und Verarbeitungsstatus auf; mit dem Medienordner meldet es außerdem Locales, deren iPhone-Duo-Screenshots in Dateien oder Reihenfolge vom Ordner abweichen (beheben Sie das mit `media upload` und `--replace`). App-Vorschauen für das iPhone Duo werden noch nicht unterstützt, `media download` berücksichtigt iPhone-Duo-Screenshots nicht, und `media prune` löscht sie nie.

### Produktseiten-Header und Suchergebnisse {#header-and-search-results}

Zwei weitere Ordner werden über die Asset-Bibliothek hochgeladen. Jeder enthält ein Bild pro Locale, das an keine Geräteklasse gebunden ist: Die Version zeigt es auf jedem Gerät (iPhone, iPad, iPhone Duo), und beide funktionieren für Versionen aller Plattformen.

- `PRODUCT_PAGE_HEADER`: das Bild oben auf der Produktseite. PNG mit 3840×1646 oder 5244×2950.
- `APP_STORE_SEARCH_RESULTS`: das Bild, das in den App Store-Suchergebnissen mit der App erscheint. JPG oder PNG im Format 3:2, von 1920×1280 bis 3840×2560, oder ein PNG mit 5244×2950.

Ein Upload ersetzt das aktuelle Bild der Locale, mit oder ohne `--replace`; das alte wird erst entfernt, nachdem das neue hochgeladen ist. Videos für diese Plätze werden noch nicht unterstützt. `media verify` prüft sie wie iPhone-Duo-Screenshots.

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
ascelerate apps media upload <bundle-id> screenshots.zip --replace
```

## Blockierte Medien überprüfen und erneut versuchen

Manchmal bleiben Screenshots oder Vorschauen nach dem Upload im Status "Verarbeitung" hängen. Verwenden Sie `media verify`, um den Status zu prüfen und optional blockierte Elemente erneut zu versuchen:

```bash
# Status aller Screenshots und Vorschauen prüfen
ascelerate apps media verify <bundle-id>

# Eine bestimmte Version prüfen
ascelerate apps media verify <bundle-id> --version 2.1.0

# Blockierte Elemente mit lokalen Dateien aus dem Medienordner erneut versuchen
ascelerate apps media verify <bundle-id> media/
```

Ohne Ordner-Argument zeigt der Befehl einen reinen Statusbericht an. Sets, in denen alle Elemente abgeschlossen sind, werden als kompakte Einzeiler angezeigt; Sets mit blockierten Elementen werden erweitert, um jede Datei und ihren Status anzuzeigen. Mit einem Ordner-Argument wird angeboten, blockierte Elemente erneut zu versuchen, indem sie gelöscht und aus den passenden lokalen Dateien erneut hochgeladen werden, wobei die ursprüngliche Reihenfolge beibehalten wird.

## Veraltete Sets entfernen

`--replace` beim Hochladen leert nur Sets, die einem lokalen Ordner entsprechen — Server-Sets für Bildschirmgrößen, die Sie nicht mehr ausliefern, behalten ihre veralteten Screenshots. `media prune` löscht die Sets ohne passenden lokalen Locale-/Display-Type-Ordner, nachdem sie mit Asset-Anzahl aufgelistet und bestätigt wurden:

```bash
ascelerate apps media prune <bundle-id> media/
ascelerate apps media prune <bundle-id> media/ --version 2.1.0 --platform ios
```

Locales ohne lokalen Ordner werden vollständig übersprungen — der Befehl bereinigt nur innerhalb der Locales, die der Ordner tatsächlich verwaltet.

## Bilder aus der Asset-Bibliothek entfernen

`media remove` entfernt eine Art von Asset-Bibliotheksbild aus der Version: `PRODUCT_PAGE_HEADER`, `APP_STORE_SEARCH_RESULTS` oder `APP_IPHONE_DUO`. Der Befehl wirkt auf die mit `--locale` angegebenen Locales oder auf alle und listet vor der Rückfrage auf, was er gefunden hat:

```bash
ascelerate apps media remove <bundle-id> PRODUCT_PAGE_HEADER --locale en-US
ascelerate apps media remove <bundle-id> APP_STORE_SEARCH_RESULTS
ascelerate apps media remove <bundle-id> APP_IPHONE_DUO --locale en-US,tr --version 2.1.0
```

## Asset-Bibliothek aufräumen

Jede App hat eine Asset-Bibliothek mit ihren hochgeladenen Bildern, und Versionen teilen sie: Die Screenshots einer neuen Version sind die Bilder der vorherigen Version, und alte Versionen behalten ihre. Ein Bild bleibt daher in Gebrauch, solange eine Version (auch eine alte), eine eigene Produktseite oder ein Event es verwendet. Wenn ascelerate eine Platzierung entfernt (`media remove`, `media upload --replace` oder beim Ersetzen eines Header- oder Suchergebnisbilds), löscht es auch das Bild, sofern es nichts mehr verwendet und es nie den App Review durchlaufen hat.

Frühere Uploads können dennoch ungenutzte Bilder in der Bibliothek hinterlassen haben. `media library` zählt die Bilder und listet die ungenutzten auf; mit `--delete-unused` löscht es sie nach einer Rückfrage:

```bash
ascelerate apps media library <bundle-id>
ascelerate apps media library <bundle-id> --delete-unused
ascelerate apps media library <bundle-id> --only APP_IPHONE_DUO --delete-unused
```

`--only` beschränkt die Liste auf Bilder, die zu den angegebenen Arten passen, beurteilt nach Asset-Kategorie und Pixelgröße: `PRODUCT_PAGE_HEADER`, `APP_STORE_SEARCH_RESULTS`, `APP_IPHONE_DUO`, ein Screenshot-Anzeigetyp wie `APP_IPHONE_67` (die Größen kommen von App Store Connect) oder `UNFINISHED_UPLOADS` für Uploads, deren Datei nie angekommen ist. So lässt sich die Bibliothek Gerätetyp für Gerätetyp aufräumen. Bilder, die jünger als eine Stunde sind, bleiben immer erhalten, da ein gleichzeitig laufender Upload sie gerade platzieren könnte, und ein Durchlauf, der das stündliche API-Limit von App Store Connect erreicht, hält an und bittet Sie, ihn später erneut auszuführen.

Bilder, die den App Review durchlaufen haben, werden nie gelöscht, ob platziert oder nicht, und jedes Bild wird unmittelbar vor dem Löschen erneut geprüft.
