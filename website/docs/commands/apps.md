---
sidebar_position: 1
title: Apps
---

# Apps

## List apps

```bash
ascelerate apps list
```

## App details

```bash
ascelerate apps info <bundle-id>
```

## List versions

```bash
ascelerate apps versions <bundle-id>
```

`apps list`, `apps info`, and `apps versions` all accept `--json` for machine-readable output ([conventions](../guides/automation.md#json-output)).

## Create a version

```bash
ascelerate apps create-version <bundle-id> <version-string>
ascelerate apps create-version <bundle-id> 2.1.0 --platform ios --release-type manual
```

The `--release-type` is optional — omitting it uses the previous version's setting.

:::note Universal purchase
For universal-purchase apps (one App Store record spanning iOS, macOS, tvOS, and/or visionOS), the same version string can exist once per platform. `create-version` and `review submit` default to iOS — pass `--platform macos` (or `tvos`, `visionos`) to target another platform. All other version-scoped commands (localizations, media, build attach, review preflight/info/attachments/resolve-issues/cancel-submission, phased release) accept an optional `--platform` as well; without it they prompt whenever a version (or active review submission) matches more than one platform — and refuse with a hint instead of prompting under `--yes`.
:::

## Copyright

```bash
ascelerate apps copyright <bundle-id>
ascelerate apps copyright <bundle-id> --set "2026 Your Name" --version 2.1.0 --platform macos
```

Without `--set`, prints the current copyright notice. Updating requires the version to be in an editable state.

## Review

### Check review status

```bash
ascelerate apps review status <bundle-id>
ascelerate apps review status <bundle-id> --version 2.1.0
```

Add `--json` to get the submissions — including per-item states — as machine-readable JSON.

### Submit for review

```bash
ascelerate apps review submit <bundle-id>
ascelerate apps review submit <bundle-id> --version 2.1.0
ascelerate apps review submit <bundle-id> --platform macos
```

When submitting, the command automatically detects IAPs and subscriptions with pending changes and offers to submit them alongside the app version.

### Resolve rejected items

After fixing issues and replying in Resolution Center:

```bash
ascelerate apps review resolve-issues <bundle-id>
```

### Cancel submission

```bash
ascelerate apps review cancel-submission <bundle-id>
```

### App Review Information

View or update the contact, demo account, and notes provided to App Review. With no flags it prints the current values; pass any field flag to update it (omitted fields are left unchanged).

```bash
ascelerate apps review info <bundle-id>
ascelerate apps review info <bundle-id> --contact-email you@example.com --demo-account-name reviewer --demo-account-password "hunter2" --demo-account-required true --notes "Steps to test…"

# Attachments (demo videos, documents, etc.)
ascelerate apps review attachment list <bundle-id>
ascelerate apps review attachment upload <bundle-id> demo.mp4
ascelerate apps review attachment delete <attachment-id>
```

## Preflight checks

Before submitting for review, run `preflight` to verify that all required fields are filled in across every locale:

```bash
# Check the latest editable version
ascelerate apps review preflight <bundle-id>

# Check a specific version
ascelerate apps review preflight <bundle-id> --version 2.1.0
```

The command checks version state, build attachment, and then goes through each locale to verify localization fields (description, what's new, keywords, support URL), app info fields (name, subtitle, privacy policy URL), and screenshots:

```
Preflight checks for MyApp v2.1.0 (Prepare for Submission)

Check                                Status
──────────────────────────────────────────────────────────────────
Version state                        ✓ Prepare for Submission
Build attached                       ✓ Build 42

en-US (English (United States))
  App info                           ✓ All fields filled
  Localizations                      ✓ All fields filled
  Screenshots                        ✓ 2 sets, 10 screenshots

de-DE (German (Germany))
  App info                           ✗ Missing: Privacy Policy URL
  Localizations                      ✗ Missing: What's New
  Screenshots                        ✗ No screenshots
──────────────────────────────────────────────────────────────────
Result: 5 passed, 3 failed
```

The What's New check is skipped when the app has no previously released version — that field only exists for updates, not for a first release.

Exits with a non-zero status when any check fails, making it suitable for CI pipelines and workflow files. With `--json`, the command emits a structured report instead of the table — a `passed` boolean plus one entry per check (`group`, `name`, `passed`, `detail`) — while keeping the same exit-code behavior, so CI gates can report exactly which check failed.

## Phased release

```bash
# View phased release status
ascelerate apps phased-release <bundle-id>

# Enable phased release (starts inactive, activates when version goes live)
ascelerate apps phased-release <bundle-id> --enable

# Pause, resume, or complete a phased release
ascelerate apps phased-release <bundle-id> --pause
ascelerate apps phased-release <bundle-id> --resume
ascelerate apps phased-release <bundle-id> --complete

# Remove phased release entirely
ascelerate apps phased-release <bundle-id> --disable
```

## Territory availability

```bash
# View which territories the app is available in
ascelerate apps availability <bundle-id>

# Show full country names
ascelerate apps availability <bundle-id> --verbose

# Make territories available or unavailable
ascelerate apps availability <bundle-id> --add CHN,RUS
ascelerate apps availability <bundle-id> --remove CHN
```

## Encryption declarations

```bash
# View existing encryption declarations
ascelerate apps encryption <bundle-id>

# Create a new encryption declaration
ascelerate apps encryption <bundle-id> --create --description "Uses HTTPS for API communication"
ascelerate apps encryption <bundle-id> --create --description "Uses AES encryption" --proprietary-crypto --third-party-crypto
```

## EULA

```bash
# View the current EULA (or see that the standard Apple EULA applies)
ascelerate apps eula <bundle-id>

# Set a custom EULA from a text file
ascelerate apps eula <bundle-id> --file eula.txt

# Remove the custom EULA (reverts to standard Apple EULA)
ascelerate apps eula <bundle-id> --delete
```

## Subscription grace period

The grace period lets subscribers keep access for a short window after a failed renewal payment while Apple retries billing. The setting applies app-wide.

```bash
# View current configuration
ascelerate apps subscription-grace-period <bundle-id>

# Enable for production with a 16-day window, applies to all renewals
ascelerate apps subscription-grace-period <bundle-id> \
  --opt-in true --duration SIXTEEN_DAYS --renewal-type ALL_RENEWALS

# Enable for sandbox testing too
ascelerate apps subscription-grace-period <bundle-id> --sandbox-opt-in true
```

Valid `--duration` values: `THREE_DAYS`, `SIXTEEN_DAYS`, `TWENTY_EIGHT_DAYS`. Valid `--renewal-type` values: `ALL_RENEWALS`, `PAID_TO_PAID_ONLY`.
