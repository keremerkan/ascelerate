---
name: ascelerate
description: Use when working with App Store Connect tasks — app submissions, localizations, screenshots, builds, provisioning, in-app purchases, subscriptions, or release workflows. Triggers on App Store, App Store Connect, asc, ascelerate, app review, provisioning profiles, screenshots, localizations, IAP, subscriptions.
---

# ascelerate

A command-line tool for the App Store Connect API. Use `ascelerate` for all App Store Connect operations instead of the web interface.

## Quick Reference

### App aliases

Use aliases instead of full bundle IDs:

```bash
ascelerate alias add myapp    # Interactive app picker
ascelerate apps info myapp    # Use alias anywhere
```

Any argument without a dot is treated as an alias. Real bundle IDs work unchanged.

### Version management

```bash
ascelerate apps create-version <app> <version>
ascelerate apps build attach-latest <app>
ascelerate apps build attach <app>        # Interactive build picker
ascelerate apps build detach <app>
```

`--version` targets a specific version. Without it, commands prefer the latest editable version (Prepare for Submission or Waiting for Review).

### Localizations

Two layers: **version-level** (description, what's new, keywords) and **app-level** (name, subtitle, privacy URL).

```bash
# Version localizations
ascelerate apps localizations export <app>
ascelerate apps localizations import <app> --file localizations.json

# App info localizations
ascelerate apps app-info export <app>
ascelerate apps app-info import <app> --file app-infos.json
```

#### Version localization JSON format

```json
{
  "en-US": {
    "description": "App description.",
    "whatsNew": "- Bug fixes",
    "keywords": "keyword1,keyword2",
    "promotionalText": "Promo text",
    "marketingURL": "https://example.com",
    "supportURL": "https://example.com/support"
  }
}
```

#### App info localization JSON format

```json
{
  "en-US": {
    "name": "My App",
    "subtitle": "Best app ever",
    "privacyPolicyURL": "https://example.com/privacy",
    "privacyChoicesURL": "https://example.com/choices"
  }
}
```

Only fields present in the JSON get updated — omitted fields are left unchanged. Import commands create missing locales automatically with confirmation.

### Screenshots & App Previews

```bash
ascelerate apps media download <app>
ascelerate apps media upload <app> media/
ascelerate apps media upload <app> screenshots.zip            # Zip/tar/tar.gz support
ascelerate apps media upload <app>                            # Interactive picker
ascelerate apps media upload <app> media/ --replace           # Replace existing
ascelerate apps media verify <app>                            # Check processing status
ascelerate apps media verify <app> media/                     # Retry stuck items
```

#### Folder structure

```
media/
├── en-US/
│   ├── APP_IPHONE_67/
│   │   ├── 01_home.png
│   │   └── 02_settings.png
│   └── APP_IPAD_PRO_3GEN_129/
│       └── 01_home.png
└── de-DE/
    └── APP_IPHONE_67/
        └── 01_home.png
```

Required display types: `APP_IPHONE_67` (iPhone) and `APP_IPAD_PRO_3GEN_129` (iPad). Files sorted alphabetically = upload order. Images become screenshots, videos become previews.

### Review submission

```bash
ascelerate apps review preflight <app>           # Pre-submission checks
ascelerate apps review submit <app>              # Submit (offers to include IAPs/subs)
ascelerate apps review status <app>              # Check status
ascelerate apps review resolve-issues <app>      # After fixing rejection
ascelerate apps review cancel-submission <app>   # Cancel active review
```

`preflight` checks build attachment, localizations, app info, screenshots across all locales, plus IAP/subscription state and pricing (warns when an IAP has no price schedule or a sub has no prices). Exits non-zero on failures.

When submitting, the tool detects IAPs and subscriptions and offers to submit them alongside the app version.

### In-app purchases

```bash
ascelerate iap list <app>
ascelerate iap info <app> <product-id>                   # warns if no price schedule set
ascelerate iap create <app> --name "Name" --product-id <id> --type CONSUMABLE
ascelerate iap update <app> <product-id> --name "New Name"
ascelerate iap delete <app> <product-id>
ascelerate iap submit <app> <product-id>

# Localizations
ascelerate iap localizations view <app> <product-id>
ascelerate iap localizations export <app> <product-id>
ascelerate iap localizations import <app> <product-id> --file iap-de.json

# Pricing — wholesale schedule POST is read-modify-write, preserves overrides
ascelerate iap pricing show <app> <product-id>
ascelerate iap pricing tiers <app> <product-id> --territory USA
ascelerate iap pricing set <app> <product-id> --price 4.99 [--base-territory USA] [--remove-all-overrides]
ascelerate iap pricing override <app> <product-id> --price 5.99 --territory FRA
ascelerate iap pricing remove <app> <product-id> --territory FRA   # revert to auto-equalize

# Per-IAP territory availability (independent of app's)
ascelerate iap availability <app> <product-id> [--add CHN,RUS] [--remove ITA] [--available-in-new-territories true]

# Offer codes (one-time-use batches + custom codes)
ascelerate iap offer-code list <app> <product-id>
ascelerate iap offer-code info <app> <product-id> <offer-code-id>
ascelerate iap offer-code create <app> <product-id> --name X --eligibility NON_SPENDER,ACTIVE_SPENDER --price 0.99 [--territory USA] [--equalize-all-territories]
ascelerate iap offer-code toggle <app> <product-id> <offer-code-id> --active true
ascelerate iap offer-code gen-codes <app> <product-id> <offer-code-id> --count 100 --expires 2026-12-31
ascelerate iap offer-code add-custom-codes <app> <product-id> <offer-code-id> --code PROMO2026 --count 1000 --expires 2026-12-31
ascelerate iap offer-code view-codes <one-time-use-batch-id> [--output codes.txt]   # async; may need retry

# Promotional images + App Review screenshot (Apple's 3-step file upload flow)
ascelerate iap images list/upload/delete <app> <product-id> [<file>|<image-id>]
ascelerate iap review-screenshot view/upload/delete <app> <product-id> [<file>]   # one screenshot per IAP
```

IAP types: `CONSUMABLE`, `NON_CONSUMABLE`, `NON_RENEWING_SUBSCRIPTION`. Offer code eligibilities: `NON_SPENDER`, `ACTIVE_SPENDER`, `CHURNED_SPENDER`.

Pricing notes:
- `set` preserves per-territory overrides by default; interactive menu offers to drop them, or `--remove-all-overrides` for non-interactive wipe.
- `override` and `remove` only operate on non-base territories.
- One-time-use offer codes generate asynchronously — `gen-codes` returns a batch ID; use `view-codes <batch-id>` to fetch values once ready.

### Subscriptions

```bash
ascelerate sub list <app>
ascelerate sub groups <app>
ascelerate sub info <app> <product-id>                         # warns if no prices set
ascelerate sub create <app> --name "Monthly" --product-id <id> --period ONE_MONTH --group-id <gid>
ascelerate sub update <app> <product-id> --name "New Name"
ascelerate sub delete <app> <product-id>
ascelerate sub submit <app> <product-id>
ascelerate sub submit-group <app>                              # submit whole group for review

# Subscription localizations
ascelerate sub localizations export <app> <product-id>
ascelerate sub localizations import <app> <product-id> --file sub-de.json

# Group management
ascelerate sub create-group <app> --name "Premium"
ascelerate sub update-group <app> --name "Premium Plus"
ascelerate sub delete-group <app>

# Group localizations
ascelerate sub group-localizations export <app>
ascelerate sub group-localizations import <app> --file group-de.json

# Pricing — per-territory; --equalize-all-territories fans out via Apple's equalizations
ascelerate sub pricing show <app> <product-id>
ascelerate sub pricing tiers <app> <product-id> --territory USA
ascelerate sub pricing set <app> <product-id> --price 4.99 [--territory USA] [--equalize-all-territories]
  [--preserve-current | --no-preserve-current]   # required on price increases
  [--confirm-decrease]                           # required on decreases in --yes mode

# Per-subscription territory availability (independent of app's)
ascelerate sub availability <app> <product-id> [--add CHN,RUS] [--remove ITA] [--available-in-new-territories true]

# Introductory offers (free trials + intro discounts for NEW subscribers)
ascelerate sub intro-offer list <app> <product-id>
ascelerate sub intro-offer create <app> <product-id> --mode FREE_TRIAL --duration ONE_WEEK --periods 1
ascelerate sub intro-offer create <app> <product-id> --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 --territory USA --price 0.99
ascelerate sub intro-offer update <app> <product-id> <offer-id> --end-date 2026-12-31
ascelerate sub intro-offer delete <app> <product-id> <offer-id>

# Promotional offers (server-signed offers for EXISTING subscribers)
ascelerate sub promo-offer list/info/delete <app> <product-id> [<offer-id>]
ascelerate sub promo-offer create <app> <product-id> --name X --code LOYALTY50 --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 --price 4.99 --territory USA --equalize-all-territories
ascelerate sub promo-offer update <app> <product-id> <offer-id> --price 5.99 --equalize-all-territories   # only prices can change

# Offer codes (one-time-use batches + custom codes)
ascelerate sub offer-code list/info <app> <product-id> [<offer-code-id>]
ascelerate sub offer-code create <app> <product-id> --name X --eligibility NEW --offer-eligibility STACK_WITH_INTRO_OFFERS --mode FREE_TRIAL --duration ONE_MONTH --periods 1 --price 0 --territory USA --equalize-all-territories
ascelerate sub offer-code toggle <app> <product-id> <offer-code-id> --active true
ascelerate sub offer-code gen-codes <app> <product-id> <offer-code-id> --count 500 --expires 2026-12-31
ascelerate sub offer-code add-custom-codes <app> <product-id> <offer-code-id> --code SUBPROMO --count 1000 --expires 2026-12-31
ascelerate sub offer-code view-codes <one-time-use-batch-id> [--output codes.txt]

# Promotional images + App Review screenshot (Apple's 3-step file upload flow)
ascelerate sub images list/upload/delete <app> <product-id> [<file>|<image-id>]
ascelerate sub review-screenshot view/upload/delete <app> <product-id> [<file>]   # one screenshot per sub
```

Subscription pricing safety:
- **Price increase** in any territory requires `--preserve-current` (grandfather existing subs at old price) OR `--no-preserve-current` (push new price after Apple's notification period). Errors if neither set.
- **Price decrease** prompts interactively; under `--yes`, requires `--confirm-decrease` to acknowledge revenue impact.
- **`--equalize-all-territories`** aggregates the analysis: if any territory in the fan-out is an increase, the preserve flag is required for all.

Offer code eligibilities for subs: `NEW`, `EXISTING`, `EXPIRED`. Offer eligibility: `STACK_WITH_INTRO_OFFERS` or `REPLACE_INTRO_OFFERS`. Modes: `FREE_TRIAL`, `PAY_AS_YOU_GO`, `PAY_UP_FRONT`.

NOT YET IMPLEMENTED: `sub win-back-offer` is blocked on asc-swift codegen (the inline price create type is missing required relationships). `iap hosted-content` is intentionally skipped.

### Screenshots (Simulator Capture)

Capture App Store screenshots from simulators using UI tests. Replaces fastlane snapshot.

```bash
ascelerate screenshot init                          # Generate config and helper in ascelerate/ directory
ascelerate screenshot create-helper                 # Generate ScreenshotHelper.swift for UITest target
ascelerate screenshot run                           # Capture screenshots
ascelerate screenshot run -l en-US,tr-TR            # Override languages (subset of configured), comma-separated
ascelerate screenshot frame                         # Frame captured screenshots with device bezels
ascelerate screenshot doctor                        # Check config and environment for problems
```

#### Config (`ascelerate/screenshot.yml`)

```yaml
project: MyApp.xcodeproj
scheme: AppUITests
devices:
  - simulator: iPhone 17 Pro Max
    # frameDevice: true
    # deviceBezel: ./bezels/iPhone 17 Pro Max.png
  - simulator: iPad Pro 13-inch (M5)
    # frameDevice: true
    # deviceBezel: ./bezels/iPad Pro 13-inch (M5).png
languages: [en-US, de-DE]
outputDirectory: ./screenshots
clearPreviousScreenshots: true
localizeSimulator: true
overrideStatusBar: true
# helperPath: AppUITests/ScreenshotHelper.swift
# testWithoutBuilding: true
# headless: true
# darkMode: false
# disableAnimations: true
# waitAfterBoot: 5
# waitAfterEraseAndReboot: 30   # extra wait for first-run system alerts (Apple Intelligence etc.); fires on first language and on retries
# configuration: Debug
# testplan: MyTestPlan
# numberOfRetries: 1
# stopAfterFirstError: false
# reinstallApp: false
# xcargs: SWIFT_ACTIVE_COMPILATION_CONDITIONS=SCREENSHOTS
# framedOutputDirectory: ./screenshots/framed
```

Supports dark mode capture, animation disabling, automatic retries (erases simulator, re-localizes, reboots), custom test plans, Xcode build configurations, and arbitrary xcodebuild arguments.

#### Device framing

Frame screenshots with Apple device bezels (from [Apple Design Resources](https://developer.apple.com/design/resources/)). Per-device: set `frameDevice: true` and `deviceBezel` path to the bezel PNG. Framing runs automatically after capture, or standalone via `screenshot frame`. Output goes to `framedOutputDirectory` (defaults to `{outputDirectory}/framed`). Use `screenshot doctor` to validate config, simulators, bezels, and environment.

#### UITest usage

```swift
override func setUp() {
    setupScreenshots(app)
    app.launch()
}

func testScreenshots() {
    screenshot("01-home")
    app.buttons["Settings"].tap()
    screenshot("02-settings")
}
```

Builds once, runs tests concurrently across devices per language. Output: `screenshots/{language}/{device}-{name}.png`. Errors skip and continue with summary table.

### Builds

```bash
ascelerate builds archive                           # Auto-detects workspace/scheme
ascelerate builds upload MyApp.ipa
ascelerate builds await-processing <app>             # Wait for processing
ascelerate builds list --bundle-id <app>
```

### Provisioning

All provisioning commands support interactive mode (run without arguments for guided prompts):

```bash
# Devices
ascelerate devices list
ascelerate devices register

# Certificates (auto-generates CSR)
ascelerate certs create --type DISTRIBUTION
ascelerate certs revoke

# Bundle IDs & capabilities
ascelerate bundle-ids register --name "My App" --identifier com.example.MyApp --platform IOS
ascelerate bundle-ids enable-capability com.example.MyApp --type PUSH_NOTIFICATIONS

# Profiles
ascelerate profiles create --name "My Profile" --type IOS_APP_STORE --bundle-id com.example.MyApp --certificates all
ascelerate profiles reissue --all-invalid
```

Note: provisioning commands (devices, certs, bundle-ids, profiles) do NOT support aliases.

### App configuration

```bash
ascelerate apps app-info view <app>
ascelerate apps app-info update <app> --primary-category UTILITIES
ascelerate apps app-info age-rating <app>
ascelerate apps app-info age-rating export <app>
ascelerate apps app-info age-rating import <app> --file age-rating.json
ascelerate apps availability <app> --add CHN,RUS
ascelerate apps encryption <app> --create --description "Uses HTTPS"
ascelerate apps eula <app> --file eula.txt
ascelerate apps phased-release <app> --enable

# App-level subscription grace period (after failed renewal payments)
ascelerate apps subscription-grace-period <app>                         # view
ascelerate apps subscription-grace-period <app> --opt-in true --duration SIXTEEN_DAYS --renewal-type ALL_RENEWALS
ascelerate apps subscription-grace-period <app> --sandbox-opt-in true
```

Grace period durations: `THREE_DAYS`, `SIXTEEN_DAYS`, `TWENTY_EIGHT_DAYS`. Renewal types: `ALL_RENEWALS`, `PAID_TO_PAID_ONLY`.

### Workflow files

Automate multi-step releases with a plain text file:

```
# release.workflow
apps create-version com.example.MyApp 2.1.0
builds archive --scheme MyApp
builds upload --latest --bundle-id com.example.MyApp
builds await-processing com.example.MyApp
apps localizations import com.example.MyApp --file localizations.json
apps build attach-latest com.example.MyApp
apps review preflight com.example.MyApp
apps review submit com.example.MyApp
```

```bash
ascelerate run-workflow release.workflow
ascelerate run-workflow release.workflow --yes   # Skip all prompts (CI/CD)
```

Commands are one per line, without the `ascelerate` prefix. Lines starting with `#` are comments. `builds upload` automatically passes the build version to subsequent commands.

## Adding a new language to an app

When the user asks to add a new language/locale to an app, translate **all** of these:

1. **App info localizations** (name, subtitle, privacy URLs) — always
2. **Version localizations** (description, what's new, keywords, promo text) — always
3. **In-app purchases** — ask the user: translate all IAPs, or specific ones?
4. **Subscription groups** — ask the user: translate all groups, or specific ones?
5. **Subscriptions** — ask the user: translate all subscriptions, or specific ones?

### Workflow

1. Export existing localizations to see the source text:
   ```bash
   ascelerate apps app-info export <app>
   ascelerate apps localizations export <app>
   ascelerate iap localizations view <app> <product-id>       # for each IAP
   ascelerate sub group-localizations export <app>
   ascelerate sub localizations export <app> <product-id>     # for each subscription
   ```
2. Ask the user which IAPs, subscription groups, and subscriptions to translate (or all).
3. Translate the source text into the new locale.
4. Import the translations (use `-y` to skip confirmation prompts):
   ```bash
   ascelerate apps app-info import <app> --file app-infos.json -y
   ascelerate apps localizations import <app> --file localizations.json -y
   ascelerate iap localizations import <app> <product-id> --file iap.json -y
   ascelerate sub group-localizations import <app> --file group.json -y
   ascelerate sub localizations import <app> <product-id> --file sub.json -y
   ```

## Tips

- Add `--yes` / `-y` to skip confirmation prompts (for scripting/CI)
- Use `ascelerate rate-limit` to check API quota (3600 requests/hour)
- Run `ascelerate install-completions` after updates for tab completion
- Only editable versions (Prepare for Submission / Waiting for Review) accept updates
- `promotionalText` can be updated on any version state
- Export JSON → edit → import is the fastest way to update localizations across locales
