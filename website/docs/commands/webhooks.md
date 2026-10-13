---
sidebar_position: 20
title: Webhooks
---

# Webhooks

Have App Store Connect send an app's events to your server as they happen: review state changes, build uploads, TestFlight external build states, and tester feedback. Webhooks are referenced by **name** or ID.

## List

```bash
ascelerate webhooks <bundle-id>
```

## Create

```bash
ascelerate webhooks create <bundle-id> --name "Release bot" --url https://example.com/hook \
  --events app-store-version-app-version-state-updated,build-upload-state-updated
```

`--events` takes a comma-separated list or `all`. The event types include:

| Event | Sent when |
|---|---|
| `app-store-version-app-version-state-updated` | A version's App Review or release state changes |
| `build-upload-state-updated` | A build upload changes state |
| `build-beta-detail-external-build-state-updated` | A build's external TestFlight state changes |
| `beta-feedback-crash-submission-created` | A tester sends crash feedback |
| `beta-feedback-screenshot-submission-created` | A tester sends screenshot feedback |

`ascelerate webhooks create --help` lists every type, including background asset and alternative distribution events.

Apple signs each request with the webhook's secret. Without `--secret`, `create` generates a random one and prints it once: store it on your server, since App Store Connect never shows it again. `--disabled` creates the webhook without turning it on.

## Test & debug

```bash
ascelerate webhooks ping <bundle-id> "Release bot"
ascelerate webhooks deliveries <bundle-id> "Release bot"
ascelerate webhooks deliveries <bundle-id> "Release bot" --state failed
ascelerate webhooks redeliver <delivery-id>
```

`ping` sends a test event. `deliveries` lists recent deliveries with the event type, the HTTP status your server answered, and any error (`--state succeeded|failed|pending`, `--limit`, `--json`). After fixing your server, `redeliver` sends a delivery's event again.

## Update & delete

```bash
ascelerate webhooks update <bundle-id> "Release bot" --enabled false
ascelerate webhooks update <bundle-id> "Release bot" --events all --url https://example.com/new-hook
ascelerate webhooks delete <bundle-id> "Release bot"
```

`--events` replaces the whole list; `--secret` sets a new signing secret.
