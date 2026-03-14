# asc — **A** **S**wift **C**LI for App Store Connect

A command-line tool for building, archiving, and publishing apps to the App Store — from Xcode archive to App Review submission. Built with Swift on the [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi).

> **Note:** Covers the core app release workflow: archiving, uploading builds, managing versions and localizations, screenshots, review submission, provisioning (devices, certificates, bundle IDs, profiles), and full management of in-app purchases and subscriptions. Most provisioning commands support interactive mode — run without arguments to get guided prompts.

## Requirements

- macOS 13+
- Swift 6.0+ (only for building from source)

## Installation

### Homebrew

```bash
brew tap keremerkan/tap
brew install asc-cli
```

The tap provides a pre-built binary for Apple Silicon Macs, so installation is instant.

### Download the binary

Download the latest release from [GitHub Releases](https://github.com/keremerkan/asc-cli/releases):

```bash
curl -L https://github.com/keremerkan/asc-cli/releases/latest/download/asc-macos-arm64.tar.gz -o asc.tar.gz
tar xzf asc.tar.gz
mv asc /usr/local/bin/
```

Since the binary is not signed or notarized, macOS will quarantine it on first download. Remove the quarantine attribute:

```bash
xattr -d com.apple.quarantine /usr/local/bin/asc
```

> **Note:** Pre-built binaries are provided for Apple Silicon (arm64) only. Intel Mac users should build from source.

### Build from source

```bash
git clone https://github.com/keremerkan/asc-cli.git
cd asc-cli
swift build -c release
strip .build/release/asc
cp .build/release/asc /usr/local/bin/
```

> **Note:** The release build takes a few minutes because the [asc-swift](https://github.com/aaronsky/asc-swift) dependency includes ~2500 generated source files covering the entire App Store Connect API surface. `strip` removes debug symbols, reducing the binary from ~175 MB to ~59 MB.

### Shell completions

Set up tab completion for subcommands, options, and flags (supports zsh and bash):

```bash
asc install-completions
```

This detects your shell and configures everything automatically. Restart your shell or open a new tab to activate.

### AI coding skill

asc ships with a skill file that gives AI coding agents (Claude Code, Cursor, Windsurf, GitHub Copilot) full knowledge of all commands, JSON formats, and workflows.

**Via the binary** (Claude Code only):

```bash
asc install-skill
```

The tool checks for outdated skills on each run and prompts you to update after upgrades.

**Via npx** (any AI coding agent):

```bash
npx asc-skill
```

This presents an interactive menu to select your agent and installs the skill to the appropriate directory. The skill file is fetched from GitHub, so it's always up to date. Use `npx asc-skill --uninstall` to remove it.

## Setup

### 1. Create an API Key

Go to [App Store Connect > Users and Access > Integrations > App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) and generate a new key. Download the `.p8` private key file.

### 2. Configure

```bash
asc configure
```

This will prompt for your **Key ID**, **Issuer ID**, and the path to your `.p8` file. The private key is copied into `~/.asc/` with strict file permissions (owner-only access).

## Usage

### Aliases

Instead of typing full bundle IDs every time, you can create short aliases:

```bash
# Add an alias (interactive app picker)
asc alias add myapp

# Now use the alias anywhere you'd use a bundle ID
asc apps info myapp
asc apps versions myapp
asc apps localizations view myapp

# List all aliases
asc alias list

# Remove an alias
asc alias remove myapp
```

Aliases are stored in `~/.asc/aliases.json`. Any argument that doesn't contain a dot is looked up as an alias — real bundle IDs (which always contain dots) work unchanged.

### Apps

```bash
# List all apps
asc apps list

# Show app details
asc apps info <bundle-id>

# List App Store versions
asc apps versions <bundle-id>

# Create a new version
asc apps create-version <bundle-id> <version-string>
asc apps create-version <bundle-id> 2.1.0 --platform ios --release-type manual

# Check review submission status
asc apps review status <bundle-id>
asc apps review status <bundle-id> --version 2.1.0

# Submit for review
asc apps review submit <bundle-id>
asc apps review submit <bundle-id> --version 2.1.0

# Resolve rejected review items (after fixing issues and replying in Resolution Center)
asc apps review resolve-issues <bundle-id>

# Cancel an active review submission
asc apps review cancel-submission <bundle-id>
```

#### Pre-submission preflight checks

Before submitting for review, run `preflight` to verify that all required fields are filled in across every locale:

```bash
# Check the latest editable version
asc apps review preflight <bundle-id>

# Check a specific version
asc apps review preflight <bundle-id> --version 2.1.0
```

The command checks version state, build attachment, and then goes through each locale to verify localization fields (description, what's new, keywords), app info fields (name, subtitle, privacy policy URL), and screenshots. Results are grouped by locale with colored pass/fail indicators:

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

Exits with a non-zero status when any check fails, making it suitable for CI pipelines and workflow files.

### Build Management

```bash
# Interactively select and attach a build to a version
asc apps build attach <bundle-id>
asc apps build attach <bundle-id> --version 2.1.0

# Attach the most recent build automatically
asc apps build attach-latest <bundle-id>

# Remove the attached build from a version
asc apps build detach <bundle-id>
```

### Phased Release

```bash
# View phased release status
asc apps phased-release <bundle-id>

# Enable phased release (starts inactive, activates when version goes live)
asc apps phased-release <bundle-id> --enable

# Pause, resume, or complete a phased release
asc apps phased-release <bundle-id> --pause
asc apps phased-release <bundle-id> --resume
asc apps phased-release <bundle-id> --complete

# Remove phased release entirely
asc apps phased-release <bundle-id> --disable
```

### Age Rating

```bash
# View age rating declaration for the latest version
asc apps app-info age-rating <bundle-id>
asc apps app-info age-rating <bundle-id> --version 2.1.0

# Update age ratings from a JSON file
asc apps app-info age-rating <bundle-id> --file age-rating.json
```

The JSON file uses the same field names as the API. Only fields present in the file are updated:

```json
{
  "isAdvertising": false,
  "isUserGeneratedContent": true,
  "violenceCartoonOrFantasy": "INFREQUENT_OR_MILD",
  "alcoholTobaccoOrDrugUseOrReferences": "NONE"
}
```

Intensity fields accept: `NONE`, `INFREQUENT_OR_MILD`, `FREQUENT_OR_INTENSE`. Boolean fields accept `true`/`false`.

### Routing App Coverage

```bash
# View current routing coverage status
asc apps routing-coverage <bundle-id>

# Upload a .geojson file
asc apps routing-coverage <bundle-id> --file coverage.geojson
```

### Localizations

```bash
# View localizations (latest version by default)
asc apps localizations view <bundle-id>
asc apps localizations view <bundle-id> --version 2.1.0 --locale en-US

# Export localizations to JSON
asc apps localizations export <bundle-id>
asc apps localizations export <bundle-id> --version 2.1.0 --output my-localizations.json

# Update a single locale
asc apps localizations update <bundle-id> --whats-new "Bug fixes" --locale en-US

# Bulk update from JSON file
asc apps localizations import <bundle-id> --file localizations.json
```

The JSON format for export and bulk update:

```json
{
  "en-US": {
    "description": "My app description.\n\nSecond paragraph.",
    "whatsNew": "- Bug fixes\n- New dark mode",
    "keywords": "productivity,tools,utility",
    "promotionalText": "Try our new features!",
    "marketingURL": "https://example.com",
    "supportURL": "https://example.com/support"
  },
  "de-DE": {
    "whatsNew": "- Fehlerbehebungen\n- Neuer Dunkelmodus"
  }
}
```

Only fields present in the JSON are updated -- omitted fields are left unchanged.

### Screenshots & App Previews

```bash
# Download all screenshots and preview videos
asc apps media download <bundle-id>
asc apps media download <bundle-id> --folder my-media/ --version 2.1.0

# Upload screenshots and preview videos from a folder
asc apps media upload <bundle-id> --folder media/

# Upload from a zip file (e.g. exported from asc-screenshots)
asc apps media upload <bundle-id> --folder screenshots.zip

# Upload to a specific version
asc apps media upload <bundle-id> --folder media/ --version 2.1.0

# Replace existing media in matching sets before uploading
asc apps media upload <bundle-id> --folder media/ --replace

# Interactive mode: pick a folder or zip from the current directory
asc apps media upload <bundle-id>
```

When `--folder` is omitted, the command lists all subdirectories and `.zip` files in the current directory as a numbered picker. Zip files are extracted automatically before upload.

Organize your media folder with locale and display type subfolders:

```
media/
├── en-US/
│   ├── APP_IPHONE_67/
│   │   ├── 01_home.png
│   │   ├── 02_settings.png
│   │   └── preview.mp4
│   └── APP_IPAD_PRO_3GEN_129/
│       └── 01_home.png
└── de-DE/
    └── APP_IPHONE_67/
        ├── 01_home.png
        └── 02_settings.png
```

- **Level 1:** Locale (e.g. `en-US`, `de-DE`, `ja`)
- **Level 2:** Display type folder name (see table below)
- **Level 3:** Media files -- images (`.png`, `.jpg`, `.jpeg`) become screenshots, videos (`.mp4`, `.mov`) become app previews
- Files are uploaded in alphabetical order by filename
- Unsupported files are skipped with a warning

#### Display types

App Store Connect requires **`APP_IPHONE_67`** screenshots for iPhone apps and **`APP_IPAD_PRO_3GEN_129`** screenshots for iPad apps. All other display types are optional.

| Folder name | Device | Screenshots | Previews |
|---|---|---|---|
| `APP_IPHONE_67` | iPhone 6.7" (iPhone 16 Pro Max, 15 Pro Max, 14 Pro Max) | **Required** | Yes |
| `APP_IPAD_PRO_3GEN_129` | iPad Pro 12.9" (3rd gen+) | **Required** | Yes |

<details>
<summary>All optional display types</summary>

| Folder name | Device | Screenshots | Previews |
|---|---|---|---|
| `APP_IPHONE_61` | iPhone 6.1" (iPhone 16 Pro, 15 Pro, 14 Pro) | Yes | Yes |
| `APP_IPHONE_65` | iPhone 6.5" (iPhone 11 Pro Max, XS Max) | Yes | Yes |
| `APP_IPHONE_58` | iPhone 5.8" (iPhone 11 Pro, X, XS) | Yes | Yes |
| `APP_IPHONE_55` | iPhone 5.5" (iPhone 8 Plus, 7 Plus, 6s Plus) | Yes | Yes |
| `APP_IPHONE_47` | iPhone 4.7" (iPhone SE 3rd gen, 8, 7, 6s) | Yes | Yes |
| `APP_IPHONE_40` | iPhone 4" (iPhone SE 1st gen, 5s, 5c) | Yes | Yes |
| `APP_IPHONE_35` | iPhone 3.5" (iPhone 4s and earlier) | Yes | Yes |
| `APP_IPAD_PRO_3GEN_11` | iPad Pro 11" | Yes | Yes |
| `APP_IPAD_PRO_129` | iPad Pro 12.9" (1st/2nd gen) | Yes | Yes |
| `APP_IPAD_105` | iPad 10.5" (iPad Air 3rd gen, iPad Pro 10.5") | Yes | Yes |
| `APP_IPAD_97` | iPad 9.7" (iPad 6th gen and earlier) | Yes | Yes |
| `APP_DESKTOP` | Mac | Yes | Yes |
| `APP_APPLE_TV` | Apple TV | Yes | Yes |
| `APP_APPLE_VISION_PRO` | Apple Vision Pro | Yes | Yes |
| `APP_WATCH_ULTRA` | Apple Watch Ultra | Yes | No |
| `APP_WATCH_SERIES_10` | Apple Watch Series 10 | Yes | No |
| `APP_WATCH_SERIES_7` | Apple Watch Series 7 | Yes | No |
| `APP_WATCH_SERIES_4` | Apple Watch Series 4 | Yes | No |
| `APP_WATCH_SERIES_3` | Apple Watch Series 3 | Yes | No |
| `IMESSAGE_APP_IPHONE_67` | iMessage iPhone 6.7" | Yes | No |
| `IMESSAGE_APP_IPHONE_61` | iMessage iPhone 6.1" | Yes | No |
| `IMESSAGE_APP_IPHONE_65` | iMessage iPhone 6.5" | Yes | No |
| `IMESSAGE_APP_IPHONE_58` | iMessage iPhone 5.8" | Yes | No |
| `IMESSAGE_APP_IPHONE_55` | iMessage iPhone 5.5" | Yes | No |
| `IMESSAGE_APP_IPHONE_47` | iMessage iPhone 4.7" | Yes | No |
| `IMESSAGE_APP_IPHONE_40` | iMessage iPhone 4" | Yes | No |
| `IMESSAGE_APP_IPAD_PRO_3GEN_129` | iMessage iPad Pro 12.9" (3rd gen+) | Yes | No |
| `IMESSAGE_APP_IPAD_PRO_3GEN_11` | iMessage iPad Pro 11" | Yes | No |
| `IMESSAGE_APP_IPAD_PRO_129` | iMessage iPad Pro 12.9" (1st/2nd gen) | Yes | No |
| `IMESSAGE_APP_IPAD_105` | iMessage iPad 10.5" | Yes | No |
| `IMESSAGE_APP_IPAD_97` | iMessage iPad 9.7" | Yes | No |

</details>

> **Note:** Watch and iMessage display types support screenshots only -- video files in those folders are skipped with a warning. The `--replace` flag deletes all existing assets in each matching set before uploading new ones.
>
> `media download` saves files in this same folder structure (defaults to `<bundle-id>-media/`), so you can download, edit, and re-upload.

#### Using with asc-screenshots

[asc-screenshots](https://github.com/keremerkan/asc-screenshots) is a companion skill for AI coding agents that generates production-ready App Store screenshots. It creates a Next.js page that renders ad-style screenshot layouts with device bezels and exports them as a zip file in the exact folder structure asc expects:

```
en-US/APP_IPHONE_67/01_hero.png
en-US/APP_IPAD_PRO_3GEN_129/01_hero.png
de-DE/APP_IPHONE_67/01_hero.png
```

Upload the exported zip directly:

```bash
asc apps media upload <bundle-id> --folder screenshots.zip --replace
```

#### Verify and retry stuck media

Sometimes screenshots or previews get stuck in "processing" after upload. Use `media verify` to check the status of all media at once and optionally retry stuck items:

```bash
# Check status of all screenshots and previews
asc apps media verify <bundle-id>

# Check a specific version
asc apps media verify <bundle-id> --version 2.1.0

# Retry stuck items using local files from the media folder
asc apps media verify <bundle-id> --folder media/
```

Without `--folder`, the command shows a read-only status report. Sets where all items are complete show a compact one-liner; sets with stuck items expand to show each file and its state. With `--folder`, it prompts to retry stuck items by deleting them and re-uploading from the matching local files, preserving the original position order.

### App Info & Categories

```bash
# View app info, categories, and per-locale metadata
asc apps app-info view <bundle-id>

# List all available category IDs (no bundle ID needed)
asc apps app-info view --list-categories

# Update localization fields for a single locale
asc apps app-info update <bundle-id> --name "My App" --subtitle "Best app ever"
asc apps app-info update <bundle-id> --locale de-DE --name "Meine App"

# Update categories (can combine with localization flags)
asc apps app-info update <bundle-id> --primary-category UTILITIES
asc apps app-info update <bundle-id> --primary-category GAMES_ACTION --secondary-category ENTERTAINMENT

# Export all app info localizations to JSON
asc apps app-info export <bundle-id>
asc apps app-info export <bundle-id> --output app-infos.json

# Bulk update localizations from a JSON file
asc apps app-info import <bundle-id> --file app-infos.json
```

### Territory Availability

```bash
# View which territories the app is available in
asc apps availability <bundle-id>

# Show full country names
asc apps availability <bundle-id> --verbose

# Make territories available or unavailable
asc apps availability <bundle-id> --add CHN,RUS
asc apps availability <bundle-id> --remove CHN
```

### Encryption Declarations

```bash
# View existing encryption declarations
asc apps encryption <bundle-id>

# Create a new encryption declaration
asc apps encryption <bundle-id> --create --description "Uses HTTPS for API communication"
asc apps encryption <bundle-id> --create --description "Uses AES encryption" --proprietary-crypto --third-party-crypto
```

### EULA

```bash
# View the current EULA (or see that the standard Apple EULA applies)
asc apps eula <bundle-id>

# Set a custom EULA from a text file
asc apps eula <bundle-id> --file eula.txt

# Remove the custom EULA (reverts to standard Apple EULA)
asc apps eula <bundle-id> --delete
```

### Devices

```bash
# List registered devices
asc devices list
asc devices list --platform IOS --status ENABLED

# Show device details (interactive picker if name/UDID omitted)
asc devices info
asc devices info "My iPhone"

# Register a new device (interactive prompts if options omitted)
asc devices register
asc devices register --name "My iPhone" --udid 00008101-XXXXXXXXXXXX --platform IOS

# Update a device (interactive picker and update prompts if omitted)
asc devices update
asc devices update "My iPhone" --name "Work iPhone"
asc devices update "My iPhone" --status DISABLED
```

### Certificates

```bash
# List signing certificates
asc certs list
asc certs list --type DISTRIBUTION

# Show certificate details (interactive picker if omitted)
asc certs info
asc certs info "Apple Distribution: Example Inc"

# Create a certificate (interactive type picker if --type omitted)
# Auto-generates RSA key pair and CSR, imports into login keychain
asc certs create
asc certs create --type DISTRIBUTION
asc certs create --type DEVELOPMENT --csr my-request.pem

# Revoke a certificate (interactive picker if omitted)
asc certs revoke
asc certs revoke ABC123DEF456
```

### Bundle Identifiers

```bash
# List bundle identifiers
asc bundle-ids list
asc bundle-ids list --platform IOS

# Show details and capabilities (interactive picker if omitted)
asc bundle-ids info
asc bundle-ids info com.example.MyApp

# Register a new bundle ID (interactive prompts if options omitted)
asc bundle-ids register
asc bundle-ids register --name "My App" --identifier com.example.MyApp --platform IOS

# Rename a bundle ID (identifier itself is immutable)
asc bundle-ids update
asc bundle-ids update com.example.MyApp --name "My Renamed App"

# Delete a bundle ID (interactive picker if omitted)
asc bundle-ids delete
asc bundle-ids delete com.example.MyApp

# Enable a capability (interactive pickers if omitted)
# Shows only capabilities not already enabled
asc bundle-ids enable-capability
asc bundle-ids enable-capability com.example.MyApp --type PUSH_NOTIFICATIONS

# Disable a capability (picks from currently enabled capabilities)
asc bundle-ids disable-capability
asc bundle-ids disable-capability com.example.MyApp
```

After enabling or disabling a capability, if provisioning profiles exist for that bundle ID, the command offers to regenerate them (required for changes to take effect).

> **Note:** Some capabilities (e.g. App Groups, iCloud, Associated Domains) require additional configuration in the [Apple Developer portal](https://developer.apple.com/account/resources) after enabling.

### Provisioning Profiles

```bash
# List provisioning profiles
asc profiles list
asc profiles list --type IOS_APP_STORE --state ACTIVE

# Show profile details (interactive picker if omitted)
asc profiles info
asc profiles info "My App Store Profile"

# Download a profile (interactive picker if omitted)
asc profiles download
asc profiles download "My App Store Profile" --output ./profiles/

# Create a profile (fully interactive if options omitted)
# Prompts for name, type, bundle ID, certificates, and devices
asc profiles create
asc profiles create --name "My Profile" --type IOS_APP_STORE --bundle-id com.example.MyApp --certificates all

# --certificates all uses all certs of the matching family (distribution, development, or Developer ID)
# You can also specify serial numbers: --certificates ABC123,DEF456

# Delete a profile (interactive picker if omitted)
asc profiles delete
asc profiles delete "My App Store Profile"

# Reissue profiles (delete + recreate with latest certs of matching family)
asc profiles reissue                         # Interactive: pick from all profiles (shows status)
asc profiles reissue "My Profile"            # Reissue a specific profile by name
asc profiles reissue --all-invalid           # Reissue all invalid profiles
asc profiles reissue --all                   # Reissue all profiles regardless of state
asc profiles reissue --all --all-devices     # Reissue all, using all enabled devices for dev/adhoc
asc profiles reissue --all --to-certs ABC123,DEF456  # Use specific certificates instead of auto-detect
```

### Builds

```bash
# List all builds (shows app version and build number)
asc builds list
asc builds list --bundle-id <bundle-id>
asc builds list --bundle-id <bundle-id> --version 2.1.0

# Archive an Xcode project
asc builds archive
asc builds archive --scheme MyApp --output ./archives

# Validate a build before uploading
asc builds validate MyApp.ipa

# Upload a build to App Store Connect
asc builds upload MyApp.ipa

# Wait for a build to finish processing
asc builds await-processing <bundle-id>
asc builds await-processing <bundle-id> --build-version 903
```

The `archive` command auto-detects the `.xcworkspace` or `.xcodeproj` in the current directory and resolves the scheme if only one exists. It accepts `.ipa`, `.pkg`, or `.xcarchive` files for `upload` and `validate`. When given an `.xcarchive`, it automatically exports to `.ipa` before uploading.

### In-App Purchases

```bash
# List and inspect
asc iap list <bundle-id>
asc iap list <bundle-id> --type consumable --state approved
asc iap info <bundle-id> <product-id>
asc iap promoted <bundle-id>

# Create, update, and delete
asc iap create <bundle-id> --name "100 Coins" --product-id <product-id> --type CONSUMABLE
asc iap update <bundle-id> <product-id> --name "100 Gold Coins"
asc iap delete <bundle-id> <product-id>

# Submit for review
asc iap submit <bundle-id> <product-id>

# Manage localizations
asc iap localizations view <bundle-id> <product-id>
asc iap localizations export <bundle-id> <product-id>
asc iap localizations import <bundle-id> <product-id> --file iap-de.json
```

Filter values are case-insensitive. Types: `CONSUMABLE`, `NON_CONSUMABLE`, `NON_RENEWING_SUBSCRIPTION`. States: `APPROVED`, `MISSING_METADATA`, `READY_TO_SUBMIT`, `WAITING_FOR_REVIEW`, `IN_REVIEW`, etc.

### Subscriptions

```bash
# List and inspect
asc sub groups <bundle-id>
asc sub list <bundle-id>
asc sub info <bundle-id> <product-id>

# Create, update, and delete subscriptions
asc sub create <bundle-id> --name "Monthly" --product-id <product-id> --period ONE_MONTH --group-id <group-id>
asc sub update <bundle-id> <product-id> --name "Monthly Plan"
asc sub delete <bundle-id> <product-id>

# Manage subscription groups
asc sub create-group <bundle-id> --name "Premium"
asc sub update-group <bundle-id> --name "Premium Plus"
asc sub delete-group <bundle-id>

# Submit for review
asc sub submit <bundle-id> <product-id>

# Subscription localizations
asc sub localizations view <bundle-id> <product-id>
asc sub localizations export <bundle-id> <product-id>
asc sub localizations import <bundle-id> <product-id> --file sub-de.json

# Subscription group localizations
asc sub group-localizations view <bundle-id>
asc sub group-localizations export <bundle-id>
asc sub group-localizations import <bundle-id> --file group-de.json
```

When submitting an app version for review, `apps review submit` automatically detects IAPs and subscriptions that may have pending changes and offers to submit them alongside the app version.

The localization import commands create missing locales automatically with confirmation, so you can add new languages without visiting App Store Connect.

### Rate Limit

Check your current API usage against the rolling hourly quota:

```bash
asc rate-limit
```

```
Hourly limit: 3600 requests (rolling window)
Used:         57
Remaining:    3543 (98%)
```

### Workflows

Chain multiple commands into a single automated run with a workflow file:

```bash
asc run-workflow release.txt
asc run-workflow release.txt --yes   # skip all prompts (CI/CD)
asc run-workflow                     # interactively select from .workflow/.txt files
```

A workflow file is a plain text file with one command per line (without the `asc` prefix). Lines starting with `#` are comments, blank lines are ignored. Both `.workflow` and `.txt` extensions are supported.

**Example** -- `release.txt` for submitting version 2.1.0 of a sample app:

```
# Release workflow for MyApp v2.1.0

# Create the new version on App Store Connect
apps create-version com.example.MyApp 2.1.0

# Build, validate, and upload
builds archive --scheme MyApp
builds validate --latest --bundle-id com.example.MyApp
builds upload --latest --bundle-id com.example.MyApp

# Wait for the build to finish processing
builds await-processing com.example.MyApp

# Update localizations and attach the build
apps localizations import com.example.MyApp --file localizations.json
apps build attach-latest com.example.MyApp

# Submit for review
apps review submit com.example.MyApp
```

Without `--yes`, the workflow asks for confirmation before starting, and individual commands still prompt where they normally would (e.g., before submitting for review). With `--yes`, all prompts are skipped for fully unattended execution.

### Automation

Most commands that prompt for confirmation support `--yes` / `-y` to skip prompts, making them suitable for CI/CD pipelines and scripts. When using `--yes` with provisioning commands, all required arguments must be provided explicitly (interactive mode is disabled):

```bash
asc apps build attach-latest <bundle-id> --yes
asc apps review submit <bundle-id> --yes
```

### Version

```bash
asc version     # Prints version number
asc --version   # Same as above
asc -v          # Same as above
```

## Acknowledgments

Built on top of [asc-swift](https://github.com/aaronsky/asc-swift) by Aaron Sky.

*"A Swift Client, App Store Connect"* — [@validatedev](https://x.com/validatedev/status/2026613415012118674)

Developed with [Claude Code](https://claude.ai/code).

## License

MIT
