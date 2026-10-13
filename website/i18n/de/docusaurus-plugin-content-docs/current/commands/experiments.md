---
sidebar_position: 18
title: Produktseitenoptimierung
---

# Produktseitenoptimierung

Testen Sie alternative Screenshots, App-Vorschauen und App-Symbole gegen Ihre ursprüngliche App-Store-Produktseite. Ein Test zeigt einem Teil der App-Store-Besucher bis zu drei **Varianten** (Treatments) der Seite und vergleicht deren Konversionsraten mit denen des Originals. Tests und Varianten werden über ihren **Namen** oder ihre ID angesprochen.

## Auflisten und ansehen

```bash
ascelerate experiments <bundle-id>
ascelerate experiments info <bundle-id> "Screenshot order"
```

`info` zeigt Status, Traffic-Anteil und Zeitraum des Tests sowie jede Variante mit ihren Locales und den Medien pro Locale. Beide Befehle akzeptieren `--json`.

## Test erstellen

```bash
ascelerate experiments create <bundle-id> --name "Screenshot order" --traffic 50 --treatment "Map first" --treatment "Alerts first"
```

`--traffic` ist der Prozentsatz der App-Store-Besucher, die eine der Varianten sehen; er wird gleichmäßig auf die Varianten verteilt, und alle anderen sehen die ursprüngliche Seite. `--platform` ist standardmäßig `ios`.

## Varianten

```bash
ascelerate experiments treatments add <bundle-id> "Screenshot order" --name "Icon B" --app-icon AppIconB
ascelerate experiments treatments update <bundle-id> "Screenshot order" "Icon B" --name "Blue icon"
ascelerate experiments treatments delete <bundle-id> "Screenshot order" "Blue icon"
ascelerate experiments treatments remove-locale <bundle-id> "Screenshot order" "Map first" --locale de-DE
```

`--app-icon` testet ein alternatives App-Symbol; es muss im aktuell veröffentlichten Build als alternatives Symbol enthalten sein. In einer Locale, die eine Variante nicht abdeckt, erscheint die ursprüngliche Seite, auch für Besucher, die am Test teilnehmen.

## Medien

```bash
ascelerate experiments media list <bundle-id> "Screenshot order"
ascelerate experiments media upload <bundle-id> "Screenshot order" "Map first" --locale en-US --display-type APP_IPHONE_67 01.png
ascelerate experiments media upload <bundle-id> "Screenshot order" "Map first" --locale en-US --preview-type APP_IPHONE_67 preview.mp4
ascelerate experiments media delete <bundle-id> "Screenshot order" <media-id>
```

Uploads funktionieren wie bei den [Medien individueller Produktseiten](product-pages.md): Bilder kommen nach `--display-type` in Screenshot-Sets, Videos nach `--preview-type` in App-Vorschau-Sets, und `PRODUCT_PAGE_HEADER`, `APP_STORE_SEARCH_RESULTS` sowie `APP_IPHONE_DUO` laufen über die Asset-Bibliothek. Die Locale der Variante wird beim ersten Upload erstellt.

:::note
Eine neue Locale einer Variante beginnt als **Kopie der Medien der ursprünglichen Seite**: App Store Connect füllt sie mit den Screenshots und Vorschauen der aktuellen Version. Uploads werden nach dieser Kopie angefügt. Löschen Sie daher die kopierten Screenshots, die Sie ersetzen (`media list` zeigt ihre IDs).
:::

## Review, Start und Ende

```bash
ascelerate experiments submit <bundle-id> "Screenshot order"
ascelerate experiments start <bundle-id> "Screenshot order"
ascelerate experiments stop <bundle-id> "Screenshot order"
```

Ein Test mit neuen Medien muss den App Review durchlaufen, bevor er starten kann (`info` weist darauf hin). `submit` erstellt eine Einreichung, die nur den Test enthält, und reicht sie ein. Gibt es für die Plattform bereits einen Einreichungsentwurf mit anderen Elementen (zum Beispiel einer App-Version), wird der Test diesem hinzugefügt und geht zusammen mit ihnen über [`apps review submit`](apps.md#submit-for-review) in den Review. Sobald der Test genehmigt ist, startet `start` ihn; `stop` beendet ihn. Die Ergebnisse sehen Sie in App Store Connect.

## Aktualisieren und löschen

```bash
ascelerate experiments update <bundle-id> "Screenshot order" --traffic 30
ascelerate experiments delete <bundle-id> "Screenshot order"
```

Ändern Sie pro Variante nur eine Sache (zum Beispiel den ersten Screenshot oder das Symbol), damit das Ergebnis zeigt, welche Änderung den Unterschied ausgemacht hat.
