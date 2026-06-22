---
sidebar_position: 15
title: Individuelle Produktseiten
---

# Individuelle Produktseiten

Individuelle Produktseiten erstellen und verwalten — alternative Varianten deiner App-Store-Produktseite mit eigenem Werbetext und eigenen Screenshots, jeweils über eine eindeutige URL erreichbar. Seiten werden über ihren **Namen** oder ihre ID angesprochen.

## Auflisten und ansehen

```bash
ascelerate product-pages list <bundle-id>
ascelerate product-pages info <bundle-id> <name-or-id>
```

`list` zeigt Name, Sichtbarkeit, die teilbare App-Store-URL (samt `ppid`) und die ID jeder Seite. `info` ergänzt die Versionen der Seite und deren Lokalisierungen.

## Erstellen

```bash
ascelerate product-pages create <bundle-id> --name "Summer Campaign" --locale en-US --promotional-text "Zeitlich begrenztes Angebot"
```

Die App-Store-Connect-API verlangt, dass eine Seite zusammen mit einer ersten Version und mindestens einer Lokalisierung erstellt wird, daher ist `--locale` erforderlich. Füge weitere Sprachen anschließend mit `product-pages localizations import` hinzu.

## Aktualisieren und löschen

```bash
ascelerate product-pages update <bundle-id> "Summer Campaign" --name "Summer 2026" --visible false
ascelerate product-pages delete <bundle-id> "Summer Campaign"
```

`--visible` legt fest, ob die Seite im App Store aktiv ist.

## Lokalisierungen

```bash
ascelerate product-pages localizations view <bundle-id> "Summer 2026"
ascelerate product-pages localizations export <bundle-id> "Summer 2026"
ascelerate product-pages localizations import <bundle-id> "Summer 2026" --file page-locales.json
```

Jede Lokalisierung enthält `promotionalText`, der auf die bearbeitbare Version der Seite angewendet wird.

```json
{
  "en-US": { "promotionalText": "Zeitlich begrenztes Angebot" },
  "fr-FR": { "promotionalText": "Offre à durée limitée" }
}
```
