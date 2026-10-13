---
sidebar_position: 20
title: Webhooks
---

# Webhooks

Lassen Sie App Store Connect die Ereignisse einer App sofort an Ihren Server senden: Statusänderungen im Review, Build-Uploads, externe TestFlight-Status von Builds und Tester-Feedback. Webhooks werden über ihren **Namen** oder ihre ID angesprochen.

## Auflisten

```bash
ascelerate webhooks <bundle-id>
```

## Erstellen

```bash
ascelerate webhooks create <bundle-id> --name "Release bot" --url https://example.com/hook \
  --events app-store-version-app-version-state-updated,build-upload-state-updated
```

`--events` nimmt eine durch Kommas getrennte Liste oder `all` an. Zu den Ereignistypen gehören:

| Ereignis | Gesendet, wenn |
|---|---|
| `app-store-version-app-version-state-updated` | sich der App-Review- oder Veröffentlichungsstatus einer Version ändert |
| `build-upload-state-updated` | sich der Status eines Build-Uploads ändert |
| `build-beta-detail-external-build-state-updated` | sich der externe TestFlight-Status eines Builds ändert |
| `beta-feedback-crash-submission-created` | ein Tester Absturz-Feedback sendet |
| `beta-feedback-screenshot-submission-created` | ein Tester Screenshot-Feedback sendet |

`ascelerate webhooks create --help` listet alle Typen auf, einschließlich der Ereignisse für Background Assets und alternative Vertriebswege.

Apple signiert jede Anfrage mit dem Secret des Webhooks. Ohne `--secret` erzeugt `create` ein zufälliges Secret und gibt es einmalig aus: Speichern Sie es auf Ihrem Server, denn App Store Connect zeigt es nie wieder an. `--disabled` erstellt den Webhook, ohne ihn zu aktivieren.

## Testen und Fehler suchen

```bash
ascelerate webhooks ping <bundle-id> "Release bot"
ascelerate webhooks deliveries <bundle-id> "Release bot"
ascelerate webhooks deliveries <bundle-id> "Release bot" --state failed
ascelerate webhooks redeliver <delivery-id>
```

`ping` sendet ein Testereignis. `deliveries` listet die letzten Zustellungen mit dem Ereignistyp, dem HTTP-Status, mit dem Ihr Server geantwortet hat, und gegebenenfalls dem Fehler auf (`--state succeeded|failed|pending`, `--limit`, `--json`). Wenn Sie Ihren Server korrigiert haben, sendet `redeliver` das Ereignis einer Zustellung erneut.

## Aktualisieren und löschen

```bash
ascelerate webhooks update <bundle-id> "Release bot" --enabled false
ascelerate webhooks update <bundle-id> "Release bot" --events all --url https://example.com/new-hook
ascelerate webhooks delete <bundle-id> "Release bot"
```

`--events` ersetzt die gesamte Liste; `--secret` legt ein neues Signatur-Secret fest.
