---
name: asc
description: Use when working with App Store Connect tasks — app submissions, localizations, screenshots, builds, provisioning, in-app purchases, subscriptions, or release workflows. Triggers on App Store, App Store Connect, asc, app review, provisioning profiles, screenshots, localizations, IAP, subscriptions.
---

# asc

A command-line tool for the App Store Connect API. Use `asc` for all App Store Connect operations instead of the web interface.

## Quick Reference

### App aliases

Use aliases instead of full bundle IDs:

```bash
asc alias add myapp    # Interactive app picker
asc apps info myapp    # Use alias anywhere
```

Any argument without a dot is treated as an alias. Real bundle IDs work unchanged.

### Version management

```bash
asc apps create-version <app> <version>
asc apps build attach-latest <app>
asc apps build attach <app>        # Interactive build picker
asc apps build detach <app>
```

`--version` targets a specific version. Without it, commands prefer the latest editable version (Prepare for Submission or Waiting for Review).

### Localizations

Two layers: **version-level** (description, what's new, keywords) and **app-level** (name, subtitle, privacy URL).

```bash
# Version localizations
asc apps localizations export <app>
asc apps localizations import <app> --file localizations.json

# App info localizations
asc apps app-info export <app>
asc apps app-info import <app> --file app-infos.json
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
asc apps media download <app>
asc apps media upload <app> --folder media/
asc apps media upload <app> --folder screenshots.zip   # Zip support
asc apps media upload <app>                            # Interactive folder/zip picker
asc apps media upload <app> --folder media/ --replace  # Replace existing
asc apps media verify <app>                            # Check processing status
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
asc apps review preflight <app>           # Pre-submission checks
asc apps review submit <app>              # Submit (offers to include IAPs/subs)
asc apps review status <app>              # Check status
asc apps review resolve-issues <app>      # After fixing rejection
asc apps review cancel-submission <app>   # Cancel active review
```

`preflight` checks build attachment, localizations, app info, and screenshots across all locales. Exits non-zero on failures.

When submitting, the tool detects IAPs and subscriptions and offers to submit them alongside the app version.

### In-app purchases

```bash
asc iap list <app>
asc iap info <app> <product-id>
asc iap create <app> --name "Name" --product-id <id> --type CONSUMABLE
asc iap update <app> <product-id> --name "New Name"
asc iap delete <app> <product-id>
asc iap submit <app> <product-id>

# Localizations
asc iap localizations view <app> <product-id>
asc iap localizations export <app> <product-id>
asc iap localizations import <app> <product-id> --file iap-de.json
```

IAP types: `CONSUMABLE`, `NON_CONSUMABLE`, `NON_RENEWING_SUBSCRIPTION`.

### Subscriptions

```bash
asc sub list <app>
asc sub groups <app>
asc sub info <app> <product-id>
asc sub create <app> --name "Monthly" --product-id <id> --period ONE_MONTH --group-id <gid>
asc sub update <app> <product-id> --name "New Name"
asc sub delete <app> <product-id>
asc sub submit <app> <product-id>

# Subscription localizations
asc sub localizations export <app> <product-id>
asc sub localizations import <app> <product-id> --file sub-de.json

# Group management
asc sub create-group <app> --name "Premium"
asc sub update-group <app> --name "Premium Plus"
asc sub delete-group <app>

# Group localizations
asc sub group-localizations export <app>
asc sub group-localizations import <app> --file group-de.json
```

### Builds

```bash
asc builds archive                           # Auto-detects workspace/scheme
asc builds upload MyApp.ipa
asc builds await-processing <app>             # Wait for processing
asc builds list --bundle-id <app>
```

### Provisioning

All provisioning commands support interactive mode (run without arguments for guided prompts):

```bash
# Devices
asc devices list
asc devices register

# Certificates (auto-generates CSR)
asc certs create --type DISTRIBUTION
asc certs revoke

# Bundle IDs & capabilities
asc bundle-ids register --name "My App" --identifier com.example.MyApp --platform IOS
asc bundle-ids enable-capability com.example.MyApp --type PUSH_NOTIFICATIONS

# Profiles
asc profiles create --name "My Profile" --type IOS_APP_STORE --bundle-id com.example.MyApp --certificates all
asc profiles reissue --all-invalid
```

Note: provisioning commands (devices, certs, bundle-ids, profiles) do NOT support aliases.

### App configuration

```bash
asc apps app-info view <app>
asc apps app-info update <app> --primary-category UTILITIES
asc apps app-info age-rating <app>
asc apps app-info age-rating <app> --file age-rating.json
asc apps availability <app> --add CHN,RUS
asc apps encryption <app> --create --description "Uses HTTPS"
asc apps eula <app> --file eula.txt
asc apps phased-release <app> --enable
```

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
asc run-workflow release.workflow
asc run-workflow release.workflow --yes   # Skip all prompts (CI/CD)
```

Commands are one per line, without the `asc` prefix. Lines starting with `#` are comments. `builds upload` automatically passes the build version to subsequent commands.

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
   asc apps app-info export <app>
   asc apps localizations export <app>
   asc iap localizations view <app> <product-id>       # for each IAP
   asc sub group-localizations export <app>
   asc sub localizations export <app> <product-id>     # for each subscription
   ```
2. Ask the user which IAPs, subscription groups, and subscriptions to translate (or all).
3. Translate the source text into the new locale.
4. Import the translations (use `-y` to skip confirmation prompts):
   ```bash
   asc apps app-info import <app> --file app-infos.json -y
   asc apps localizations import <app> --file localizations.json -y
   asc iap localizations import <app> <product-id> --file iap.json -y
   asc sub group-localizations import <app> --file group.json -y
   asc sub localizations import <app> <product-id> --file sub.json -y
   ```

## Tips

- Add `--yes` / `-y` to skip confirmation prompts (for scripting/CI)
- Use `asc rate-limit` to check API quota (3600 requests/hour)
- Run `asc install-completions` after updates for tab completion
- Only editable versions (Prepare for Submission / Waiting for Review) accept updates
- `promotionalText` can be updated on any version state
- Export JSON → edit → import is the fastest way to update localizations across locales
