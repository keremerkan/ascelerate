---
sidebar_position: 19
title: Featuring Nominations
---

# Featuring Nominations

Tell Apple's editorial team about an upcoming launch, a major update, or new content, so they can consider it for featuring on the App Store.

## List

```bash
ascelerate nominations
ascelerate nominations --app <bundle-id> --state draft
```

Lists drafts, submitted, and archived nominations (or one state with `--state`). Add `--json` for machine-readable output.

## Create

```bash
ascelerate nominations create --app <bundle-id> --type enhancements --name "Version 5" \
  --description "What's new and why it matters to users" --publish-start 2026-11-01 \
  --devices iphone,ipad --locales en-US,tr-TR
```

| Option | Description |
|---|---|
| `--app` | The app (repeat `--app` for a nomination that covers several apps) |
| `--type` | `launch`, `enhancements`, or `new-content` |
| `--name`, `--description` | What the nomination is about, written for Apple's editors |
| `--publish-start` | Release date (`yyyy-MM-dd` or ISO 8601); `--publish-end` for limited-time content |
| `--devices` | Device families: `iphone`, `ipad`, `mac`, `apple-tv`, `apple-watch`, `vision` |
| `--locales` | Locales the release is localized in |
| `--territories` | Territories it launches in first (default: all) |
| `--materials` | Links to supporting material (press kit, video), comma-separated |
| `--notes` | Notes for Apple |
| `--pre-order` | The app is available for pre-order |
| `--submit` | Submit right away instead of saving a draft |

Without `--submit`, the nomination is saved as a draft you can review and change.

## Update, submit, archive & delete

```bash
ascelerate nominations update <id> --publish-start 2026-11-08
ascelerate nominations submit <id>
ascelerate nominations archive <id>
ascelerate nominations delete <id>
```

`update` changes a draft; nomination IDs come from `nominations`. Featuring is up to Apple's editors, so nominate well ahead of the release date.
