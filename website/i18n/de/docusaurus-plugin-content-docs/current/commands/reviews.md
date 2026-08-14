---
sidebar_position: 13
title: Kundenrezensionen
---

# Kundenrezensionen

Kundenrezensionen anzeigen und Entwicklerantworten verwalten. Die Rezensionen selbst sind schreibgeschützt — Sie können nur die **Entwicklerantwort** veröffentlichen, ersetzen oder löschen.

## Auflisten

```bash
ascelerate reviews list <bundle-id>
ascelerate reviews list <bundle-id> --rating 1 --sort critical --unanswered --limit 20
ascelerate reviews list <bundle-id> --territory USA
```

Die Tabelle zeigt die Rezensions-ID, die Sternebewertung, das Datum, die Region, ob eine Antwort vorliegt, und den Titel.

- `--rating` — nach Sternebewertung filtern (1–5).
- `--territory` — nach Rezensionsregion filtern (z. B. `USA`).
- `--sort` — `recent` (Standard), `oldest`, `critical` (niedrigste Bewertung zuerst) oder `best` (höchste zuerst).
- `--unanswered` — nur Rezensionen ohne veröffentlichte Antwort.
- `--limit` — maximale Anzahl anzuzeigender Rezensionen (Standard 50, maximal 200).
- `--json` — maschinenlesbare Ausgabe einschließlich der **vollständigen Rezensionstexte und Entwicklerantworten**, sodass keine `info`-Aufrufe pro Rezension nötig sind ([Konventionen](../guides/automation.md#json-output)).

## Details

```bash
ascelerate reviews info <review-id>
```

Zeigt den vollständigen Rezensionstext und ggf. die Entwicklerantwort. Rezensions-IDs stammen aus `reviews list`. Auch hier wird `--json` akzeptiert; die Ausgabe hat dieselbe Form wie ein einzelnes Element von `reviews list --json`.

## Antworten

```bash
ascelerate reviews respond <review-id> --body "Danke für Ihr Feedback! Wir haben das im neuesten Update behoben."
```

Veröffentlicht eine Entwicklerantwort. Hat die Rezension bereits eine Antwort, wird diese nach einer Bestätigung ersetzt.

## Eine Antwort löschen

```bash
ascelerate reviews delete-response <review-id>
```
