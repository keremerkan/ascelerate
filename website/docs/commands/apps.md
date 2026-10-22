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
For universal-purchase apps (one App Store record spanning iOS, macOS, tvOS, and/or visionOS), the same version string can exist once per platform. `create-version` and `review submit` default to iOS — pass `--platform macos` (or `tvos`, `visionos`) to target another platform. All other version-scoped commands (localizations, media, build attach, review preflight/info/attachments/resolve-issues/cancel-submission, phased release, manual release) accept an optional `--platform` as well; without it they prompt whenever a version (or active review submission) matches more than one platform — and refuse with a hint instead of prompting under `--yes`.
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

When submitting, the command automatically detects IAPs and subscriptions with pending changes and offers to submit them alongside the app version. Pending changes are read from each product's version history (a version in Prepare for Submission, Ready for Review, or a rejected state), so screenshot-only edits are detected too. `apps review status` resolves the items of active submissions to the app version or product they refer to.

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

In-app purchases and subscriptions are checked for prices and a state that can go with a submission. A product you removed from sale (Developer Removed from Sale) is listed as skipped (–) and doesn't fail the check; the result line counts it separately.

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

## Manual release

When a version's release option is set to manual, the approved version sits in Pending Developer Release until you release it:

```bash
# Release the version that is pending developer release
ascelerate apps release <bundle-id>

# Target a specific version or platform
ascelerate apps release <bundle-id> --version 2.1.0 --platform macos
```

## Accessibility declarations

The App Store shows which accessibility features an app supports, declared per device family: VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion, Captions, and Audio Descriptions.

```bash
# View the declarations (draft or published) per device family
ascelerate apps accessibility <bundle-id>

# Declare what the app supports on iPhone, and publish it
ascelerate apps accessibility set <bundle-id> --device iphone --supports voiceover,larger-text,dark-interface --publish

# Publish draft declarations as they are
ascelerate apps accessibility publish <bundle-id>
```

`set` declares the full list: features you leave out are declared as not supported (`--supports none` declares none). Device families: `iphone`, `ipad`, `mac`, `apple-tv`, `apple-watch`, `vision`. Without `--publish` the declaration stays a draft. Publishing a changed declaration replaces the published one; `--all` also lists replaced declarations. Declare only what users can rely on across the app's common tasks.

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

## App pricing

```bash
# Base price, prices set by hand and planned changes (--all: every territory; --json)
ascelerate apps pricing <bundle-id>
ascelerate apps pricing tiers <bundle-id> --territory USA

# Base price, now or from a date (in the base territory's currency; 0 for free)
ascelerate apps pricing set <bundle-id> --price 0.99
ascelerate apps pricing set <bundle-id> --price 1.99 --start-date 2026-12-01

# Prices set by hand: one territory, keep Apple's current prices, or give them back to Apple
ascelerate apps pricing override <bundle-id> --territory FRA --price 0.99
ascelerate apps pricing keep <bundle-id> --territories all
ascelerate apps pricing remove <bundle-id> --territories FRA,DEU

# Temporary price change (a sale), and removing a planned change
ascelerate apps pricing sale <bundle-id> --territories all --price 0.49 --start-date 2026-12-20 --end-date 2026-12-27
ascelerate apps pricing cancel <bundle-id> --territory USA --start-date 2026-12-01

# Copy a schedule to another app (the iap pricing export format)
ascelerate apps pricing export <bundle-id> --output prices.json
ascelerate apps pricing import <other-bundle-id> --file prices.json
```

Apple derives the other territories' prices from the base price and may adjust them for tax and exchange rate changes; a price set by hand stays as it is. For several territories, `sale` takes the price in the base territory's currency and gives the others Apple's comparable prices; afterwards each territory's earlier price applies again. `import` replaces the whole schedule.

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

# Sandbox testing only (production stays off)
ascelerate apps subscription-grace-period <bundle-id> \
  --sandbox-opt-in true --duration THREE_DAYS --renewal-type ALL_RENEWALS
```

Valid `--duration` values: `THREE_DAYS`, `SIXTEEN_DAYS`, `TWENTY_EIGHT_DAYS`. Valid `--renewal-type` values: `ALL_RENEWALS`, `PAID_TO_PAID_ONLY`.

Production can't be on without sandbox: turning on `--opt-in` turns sandbox on too, with a 16-day window for all renewals unless you pass others. Turning both off clears the duration and renewal type.

## Streamlined purchasing

Streamlined purchasing lets customers buy the app's subscriptions outside the app, such as on its App Store product page. It's on by default and applies to all the app's subscriptions. Apple turns it off only for an app whose latest approved build uses the StoreKit `PurchaseIntent` API; customers then subscribe from within the app.

```bash
# View
ascelerate apps streamlined-purchasing <bundle-id>

# Turn off
ascelerate apps streamlined-purchasing <bundle-id> --enabled false
```
