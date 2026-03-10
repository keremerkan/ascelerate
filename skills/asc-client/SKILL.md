---
name: asc-client
description: Use when working with App Store Connect tasks — app submissions, localizations, screenshots, builds, provisioning, in-app purchases, subscriptions, or release workflows. Triggers on App Store, App Store Connect, asc-client, app review, provisioning profiles, screenshots, localizations, IAP, subscriptions.
---

# asc-client

A command-line tool for the App Store Connect API. Use `asc-client` for all App Store Connect operations instead of the web interface.

## Quick Reference

### App aliases

Use aliases instead of full bundle IDs:

```bash
asc-client alias add myapp    # Interactive app picker
asc-client apps info myapp    # Use alias anywhere
```

Any argument without a dot is treated as an alias. Real bundle IDs work unchanged.

### Version management

```bash
asc-client apps create-version <app> <version>
asc-client apps build attach-latest <app>
asc-client apps build attach <app>        # Interactive build picker
asc-client apps build detach <app>
```

`--version` targets a specific version. Without it, commands prefer the latest editable version (Prepare for Submission or Waiting for Review).

### Localizations

Two layers: **version-level** (description, what's new, keywords) and **app-level** (name, subtitle, privacy URL).

```bash
# Version localizations
asc-client apps localizations export <app>
asc-client apps localizations import <app> --file localizations.json

# App info localizations
asc-client apps app-info export <app>
asc-client apps app-info import <app> --file app-infos.json
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
asc-client apps media download <app>
asc-client apps media upload <app> --folder media/
asc-client apps media upload <app> --folder screenshots.zip   # Zip support
asc-client apps media upload <app>                            # Interactive folder/zip picker
asc-client apps media upload <app> --folder media/ --replace  # Replace existing
asc-client apps media verify <app>                            # Check processing status
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
asc-client apps review preflight <app>           # Pre-submission checks
asc-client apps review submit <app>              # Submit (offers to include IAPs/subs)
asc-client apps review status <app>              # Check status
asc-client apps review resolve-issues <app>      # After fixing rejection
asc-client apps review cancel-submission <app>   # Cancel active review
```

`preflight` checks build attachment, localizations, app info, and screenshots across all locales. Exits non-zero on failures.

When submitting, the tool detects IAPs and subscriptions and offers to submit them alongside the app version.

### In-app purchases

```bash
asc-client iap list <app>
asc-client iap info <app> <product-id>
asc-client iap create <app> --name "Name" --product-id <id> --type CONSUMABLE
asc-client iap update <app> <product-id> --name "New Name"
asc-client iap delete <app> <product-id>
asc-client iap submit <app> <product-id>

# Localizations
asc-client iap localizations view <app> <product-id>
asc-client iap localizations export <app> <product-id>
asc-client iap localizations import <app> <product-id> --file iap-de.json
```

IAP types: `CONSUMABLE`, `NON_CONSUMABLE`, `NON_RENEWING_SUBSCRIPTION`.

### Subscriptions

```bash
asc-client sub list <app>
asc-client sub groups <app>
asc-client sub info <app> <product-id>
asc-client sub create <app> --name "Monthly" --product-id <id> --period ONE_MONTH --group-id <gid>
asc-client sub update <app> <product-id> --name "New Name"
asc-client sub delete <app> <product-id>
asc-client sub submit <app> <product-id>

# Subscription localizations
asc-client sub localizations export <app> <product-id>
asc-client sub localizations import <app> <product-id> --file sub-de.json

# Group management
asc-client sub create-group <app> --name "Premium"
asc-client sub update-group <app> --name "Premium Plus"
asc-client sub delete-group <app>

# Group localizations
asc-client sub group-localizations export <app>
asc-client sub group-localizations import <app> --file group-de.json
```

### Builds

```bash
asc-client builds archive                           # Auto-detects workspace/scheme
asc-client builds upload MyApp.ipa
asc-client builds await-processing <app>             # Wait for processing
asc-client builds list --bundle-id <app>
```

### Provisioning

All provisioning commands support interactive mode (run without arguments for guided prompts):

```bash
# Devices
asc-client devices list
asc-client devices register

# Certificates (auto-generates CSR)
asc-client certs create --type DISTRIBUTION
asc-client certs revoke

# Bundle IDs & capabilities
asc-client bundle-ids register --name "My App" --identifier com.example.MyApp --platform IOS
asc-client bundle-ids enable-capability com.example.MyApp --type PUSH_NOTIFICATIONS

# Profiles
asc-client profiles create --name "My Profile" --type IOS_APP_STORE --bundle-id com.example.MyApp --certificates all
asc-client profiles reissue --all-invalid
```

Note: provisioning commands (devices, certs, bundle-ids, profiles) do NOT support aliases.

### App configuration

```bash
asc-client apps app-info view <app>
asc-client apps app-info update <app> --primary-category UTILITIES
asc-client apps app-info age-rating <app>
asc-client apps app-info age-rating <app> --file age-rating.json
asc-client apps availability <app> --add CHN,RUS
asc-client apps encryption <app> --create --description "Uses HTTPS"
asc-client apps eula <app> --file eula.txt
asc-client apps phased-release <app> --enable
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
asc-client run-workflow release.workflow
asc-client run-workflow release.workflow --yes   # Skip all prompts (CI/CD)
```

Commands are one per line, without the `asc-client` prefix. Lines starting with `#` are comments. `builds upload` automatically passes the build version to subsequent commands.

## Tips

- Add `--yes` / `-y` to skip confirmation prompts (for scripting/CI)
- Use `asc-client rate-limit` to check API quota (3600 requests/hour)
- Run `asc-client install-completions` after updates for tab completion
- Only editable versions (Prepare for Submission / Waiting for Review) accept updates
- `promotionalText` can be updated on any version state
- Export JSON → edit → import is the fastest way to update localizations across locales
