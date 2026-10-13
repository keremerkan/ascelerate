---
sidebar_position: 19
title: Featuring-Nominierungen
---

# Featuring-Nominierungen

Informieren Sie Apples Redaktionsteam über einen bevorstehenden Launch, ein größeres Update oder neue Inhalte, damit es diese für ein Featuring im App Store in Betracht ziehen kann.

## Auflisten

```bash
ascelerate nominations
ascelerate nominations --app <bundle-id> --state draft
```

Listet Entwürfe sowie eingereichte und archivierte Nominierungen auf (oder mit `--state` nur einen Status). Mit `--json` erhalten Sie eine maschinenlesbare Ausgabe.

## Erstellen

```bash
ascelerate nominations create --app <bundle-id> --type enhancements --name "Version 5" \
  --description "What's new and why it matters to users" --publish-start 2026-11-01 \
  --devices iphone,ipad --locales en-US,tr-TR
```

| Option | Beschreibung |
|---|---|
| `--app` | Die App (wiederholen Sie `--app` für eine Nominierung, die mehrere Apps umfasst) |
| `--type` | `launch`, `enhancements` oder `new-content` |
| `--name`, `--description` | Worum es bei der Nominierung geht, formuliert für Apples Redaktion |
| `--publish-start` | Veröffentlichungsdatum (`yyyy-MM-dd` oder ISO 8601); `--publish-end` für zeitlich begrenzte Inhalte |
| `--devices` | Gerätefamilien: `iphone`, `ipad`, `mac`, `apple-tv`, `apple-watch`, `vision` |
| `--locales` | Locales, in die das Release lokalisiert ist |
| `--territories` | Länder, in denen es zuerst erscheint (Standard: alle) |
| `--materials` | Links zu ergänzendem Material (Pressemappe, Video), durch Kommas getrennt |
| `--notes` | Hinweise für Apple |
| `--pre-order` | Die App ist vorbestellbar |
| `--submit` | Sofort einreichen, statt einen Entwurf zu speichern |

Ohne `--submit` wird die Nominierung als Entwurf gespeichert, den Sie prüfen und ändern können.

## Aktualisieren, einreichen, archivieren und löschen

```bash
ascelerate nominations update <id> --publish-start 2026-11-08
ascelerate nominations submit <id>
ascelerate nominations archive <id>
ascelerate nominations delete <id>
```

`update` ändert einen Entwurf; die IDs der Nominierungen liefert `nominations`. Über ein Featuring entscheidet Apples Redaktion; nominieren Sie daher rechtzeitig vor dem Veröffentlichungsdatum.
