---
sidebar_position: 14
title: In-App Events
---

# In-App Events

Create and manage in-app events — timely events (live events, premieres, challenges, special offers) that appear on your App Store product page and in search. Events are referenced by their **reference name** or ID.

## List & inspect

```bash
ascelerate events list <bundle-id>
ascelerate events list <bundle-id> --state PUBLISHED
ascelerate events info <bundle-id> <reference-name-or-id>
```

`info` shows the event's attributes, its per-territory schedules, and a localization summary.

## Create, update, delete

```bash
ascelerate events create <bundle-id> --reference-name "summer-sale" --badge SPECIAL_EVENT --purpose ATTRACT_NEW_USERS --priority HIGH

# With an initial schedule
ascelerate events create <bundle-id> --reference-name "launch" \
  --territories USA,GBR --publish-start 2026-07-01 --event-start 2026-07-05 --event-end 2026-07-12

ascelerate events update <bundle-id> summer-sale --priority NORMAL --badge NONE
ascelerate events delete <bundle-id> summer-sale
```

- **Badges:** `LIVE_EVENT`, `PREMIERE`, `CHALLENGE`, `COMPETITION`, `NEW_SEASON`, `MAJOR_UPDATE`, `SPECIAL_EVENT`. Pass `--badge NONE` to `update` to clear it.
- **Purposes:** `APPROPRIATE_FOR_ALL_USERS`, `ATTRACT_NEW_USERS`, `KEEP_ACTIVE_USERS_INFORMED`, `BRING_BACK_LAPSED_USERS`.
- **Priority:** `HIGH` or `NORMAL`.
- **Schedule dates** (`--publish-start`, `--event-start`, `--event-end`) accept ISO8601 (`2026-07-01T09:00:00Z`) or `yyyy-MM-dd` (UTC midnight). Omit `--territories` to schedule for all territories.

## Localizations

```bash
ascelerate events localizations view <bundle-id> summer-sale
ascelerate events localizations export <bundle-id> summer-sale
ascelerate events localizations import <bundle-id> summer-sale --file event-locales.json
```

Each localization carries `name`, `shortDescription`, and `longDescription`. Locales must match the app's configured locales (e.g. `tr`, not `tr-TR`).

```json
{
  "en-US": {
    "name": "Summer Sale",
    "shortDescription": "Big summer discounts",
    "longDescription": "Join our summer event for limited-time discounts."
  }
}
```

## Media

Event card and event details page screenshots (`.png`/`.jpg`) and video clips (`.mp4`/`.mov`), per localization.

```bash
ascelerate events media list <bundle-id> summer-sale
ascelerate events media upload <bundle-id> summer-sale --locale en-US --asset-type EVENT_CARD card.png
ascelerate events media upload <bundle-id> summer-sale --locale en-US --asset-type EVENT_DETAILS_PAGE clip.mp4 --preview-frame 00:00:03
ascelerate events media delete <bundle-id> summer-sale <media-id>
```

Asset types are `EVENT_CARD` and `EVENT_DETAILS_PAGE`. The file type determines whether it's uploaded as a screenshot or a video clip; `--preview-frame` sets a video's preview frame timecode.
