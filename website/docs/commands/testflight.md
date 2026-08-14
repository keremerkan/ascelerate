---
sidebar_position: 17
title: TestFlight
---

# TestFlight

Manage TestFlight beta testing end to end: beta groups, testers, build distribution, What to Test notes, beta review, and tester feedback.

Build-scoped commands default to the latest non-expired build. Pass `--build <number>` to target a specific build, and `--platform` to disambiguate when a universal-purchase app shares build numbers across platforms.

## Beta groups

```bash
ascelerate testflight groups list <bundle-id>
ascelerate testflight groups info <bundle-id> "External Testers"
ascelerate testflight groups create <bundle-id> --name "Friends" --public-link --public-link-limit 100
ascelerate testflight groups update <bundle-id> "Friends" --public-link false
ascelerate testflight groups delete <bundle-id> "Friends"
```

`groups list` shows each group's type, public link, tester limit, and feedback setting. `groups info` adds the group's testers and assigned builds. `create` accepts `--internal` for an internal group (team members) and `--all-builds` to give it automatic access to every build; external groups can enable a public invite link with an optional tester limit.

Group names are matched case-insensitively. Omit the name to pick from an interactive list.

### Assigning builds

```bash
# Defaults to the latest non-expired build
ascelerate testflight groups add-build <bundle-id> "Friends"
ascelerate testflight groups add-build <bundle-id> "Friends" --build 123
ascelerate testflight groups remove-build <bundle-id> "Friends" --build 123
```

### Recruitment criteria

Public-link groups can restrict who joins by device family and OS version:

```bash
# View current criteria, plus the device/OS options Apple accepts
ascelerate testflight groups criteria view <bundle-id> "Friends" --options

# Replace criteria: FAMILY[:MIN[:MAX]] with inclusive bounds
ascelerate testflight groups criteria set <bundle-id> "Friends" --filter IPHONE:18.0 --filter IPAD:17.0:26

# Remove all criteria
ascelerate testflight groups criteria clear <bundle-id> "Friends"
```

Valid families: `IPHONE`, `IPAD`, `MAC`, `APPLE_TV`, `APPLE_WATCH`, `VISION`.

## Testers

```bash
ascelerate testflight testers list <bundle-id>
ascelerate testflight testers list <bundle-id> --group "Friends"

# Adding sends the TestFlight invitation for external groups
ascelerate testflight testers add <bundle-id> --email tester@example.com --first-name Jane --group "Friends"

# Remove from one group, or from the whole app
ascelerate testflight testers remove <bundle-id> tester@example.com --group "Friends"
ascelerate testflight testers remove <bundle-id> tester@example.com

# Re-send the invitation email
ascelerate testflight testers invite <bundle-id> tester@example.com
```

`--group` accepts multiple comma-separated group names on `add` and `import`.

### Bulk import

```bash
ascelerate testflight testers import <bundle-id> --file testers.csv --group "Friends"
```

The file has one tester per line: `email[,first name[,last name]]`. Blank lines, lines starting with `#`, and a leading header row are skipped — the CSV format App Store Connect's web UI exports works as-is. Failed rows are reported at the end without aborting the rest of the batch.

## Builds and distribution

```bash
# Every build with its TestFlight states
ascelerate testflight builds <bundle-id>
ascelerate testflight builds <bundle-id> --platform ios --limit 50

# Pre-release version trains
ascelerate testflight versions <bundle-id>

# Full status for one build
ascelerate testflight status <bundle-id> --build 123
```

`builds` lists each build's processing state, internal and external testing states, and expiry date. `status` adds the auto-notify setting and the beta review state for a single build. Both accept `--json` for machine-readable output ([conventions](../guides/automation.md#json-output)).

```bash
# Expire a build so testers can no longer install it
ascelerate testflight expire <bundle-id> --build 123

# Notify testers that a build is available
ascelerate testflight notify <bundle-id>

# Toggle automatic notification for a build
ascelerate testflight auto-notify <bundle-id> --enabled false
```

## What to Test

Test notes are stored per build and per locale:

```bash
ascelerate testflight whats-new view <bundle-id>

# One locale, or all existing locales when --locale is omitted
ascelerate testflight whats-new set <bundle-id> --text "Try the new map filters" --locale en-US
ascelerate testflight whats-new set <bundle-id> --text "Try the new map filters"

# Round-trip through JSON
ascelerate testflight whats-new export <bundle-id> --output notes.json
ascelerate testflight whats-new import <bundle-id> --file notes.json
```

The JSON format follows the other localization commands:

```json
{
  "en-US": { "whatsNew": "Try the new map filters" },
  "de-DE": { "whatsNew": "Testen Sie die neuen Kartenfilter" }
}
```

## Beta review

External testing requires a beta review for each build:

```bash
ascelerate testflight submit <bundle-id> --build 123
ascelerate testflight status <bundle-id> --build 123
```

Beta app information and review details are app-level:

```bash
# Beta app description and feedback email, per locale
ascelerate testflight app-info view <bundle-id>
ascelerate testflight app-info update <bundle-id> --locale en-US --feedback-email me@example.com
ascelerate testflight app-info export <bundle-id> --output beta-app-info.json
ascelerate testflight app-info import <bundle-id> --file beta-app-info.json

# Contact and demo account for the beta review team
ascelerate testflight review-info <bundle-id>
ascelerate testflight review-info <bundle-id> --demo-account-name demo@example.com --demo-account-required true

# Custom beta license agreement (--text "" reverts to Apple's standard agreement)
ascelerate testflight eula <bundle-id>
ascelerate testflight eula <bundle-id> --file eula.txt
```

## Tester feedback

Crash and screenshot feedback submitted by testers through TestFlight:

```bash
ascelerate testflight feedback crashes list <bundle-id>
ascelerate testflight feedback crashes info <submission-id>
ascelerate testflight feedback crashes log <submission-id> --output crash.log
ascelerate testflight feedback crashes delete <submission-id>

ascelerate testflight feedback screenshots list <bundle-id>
ascelerate testflight feedback screenshots info <submission-id>
ascelerate testflight feedback screenshots download <bundle-id> [submission-id] --output feedback.zip
ascelerate testflight feedback screenshots delete <submission-id>
```

`list` accepts `--build` and `--platform` filters. `info` shows the full device context — model, OS version, locale, connection type, battery, free disk space, and the tester's comment. `log` prints the crash log or saves it with `--output`. `download` packs a submission's screenshots and comment into a zip archive; omit the submission ID to pick from a paged list of the app's submissions. Screenshot URLs expire after a few days, so download feedback you want to keep.
