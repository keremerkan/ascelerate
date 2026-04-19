# ascelerate — A Swift CLI for App Store Connect

A command-line tool for building, archiving, and publishing apps to the App Store — from Xcode archive to App Review submission. Built with Swift on the [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi).

> **Note:** Covers the core app release workflow: archiving, uploading builds, managing versions and localizations, screenshots, review submission, provisioning (devices, certificates, bundle IDs, profiles), and full management of in-app purchases and subscriptions. Most provisioning commands support interactive mode — run without arguments to get guided prompts.

> **Full documentation:** [ascelerate.dev](https://ascelerate.dev)

## Requirements

- macOS 13+
- Swift 6.0+ (only for building from source)

## Installation

### Homebrew

```bash
brew tap keremerkan/tap
brew install ascelerate
```

The tap provides a pre-built binary for Apple Silicon Macs, so installation is instant.

### Install script

```bash
curl -sSL https://raw.githubusercontent.com/keremerkan/ascelerate/main/install.sh | bash
```

Downloads the latest release, installs to `/usr/local/bin`, and removes the quarantine attribute automatically. Apple Silicon only.

### Download manually

Download the latest release from [GitHub Releases](https://github.com/keremerkan/ascelerate/releases):

```bash
curl -L https://github.com/keremerkan/ascelerate/releases/latest/download/ascelerate-macos-arm64.tar.gz -o ascelerate.tar.gz
tar xzf ascelerate.tar.gz
mv ascelerate /usr/local/bin/
```

Since the binary is not signed or notarized, macOS will quarantine it on first download. Remove the quarantine attribute:

```bash
xattr -d com.apple.quarantine /usr/local/bin/ascelerate
```

> **Note:** Pre-built binaries are provided for Apple Silicon (arm64) only. Intel Mac users should build from source.

### Build from source

```bash
git clone https://github.com/keremerkan/ascelerate.git
cd ascelerate
swift build -c release
strip .build/release/ascelerate
cp .build/release/ascelerate /usr/local/bin/
```

> **Note:** The release build takes a few minutes because the [asc-swift](https://github.com/aaronsky/asc-swift) dependency includes ~2500 generated source files covering the entire App Store Connect API surface. `strip` removes debug symbols, reducing the binary from ~175 MB to ~59 MB.

### Shell completions

Set up tab completion for subcommands, options, and flags (supports zsh and bash):

```bash
ascelerate install-completions
```

This detects your shell and configures everything automatically. Restart your shell or open a new tab to activate.

### AI coding skill

ascelerate ships with a skill file that gives AI coding agents (Claude Code, Cursor, Windsurf, GitHub Copilot) full knowledge of all commands, JSON formats, and workflows.

**Via the binary** (Claude Code only):

```bash
ascelerate install-skill
```

The tool checks for outdated skills on each run and prompts you to update after upgrades.

**Via npx** (any AI coding agent):

```bash
npx ascelerate-skill
```

This presents an interactive menu to select your agent and installs the skill to the appropriate directory. The skill file is fetched from GitHub, so it's always up to date. Use `npx ascelerate-skill --uninstall` to remove it.

## Setup

### 1. Create an API Key

Go to [App Store Connect > Users and Access > Integrations > App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) and generate a new key. Download the `.p8` private key file.

### 2. Configure

```bash
ascelerate configure
```

This will prompt for your **Key ID**, **Issuer ID**, and the path to your `.p8` file. The private key is copied into `~/.ascelerate/` with strict file permissions (owner-only access).

## Usage

### Aliases

Instead of typing full bundle IDs every time, you can create short aliases:

```bash
# Add an alias (interactive app picker)
ascelerate alias add myapp

# Now use the alias anywhere you'd use a bundle ID
ascelerate apps info myapp
ascelerate apps versions myapp
ascelerate apps localizations view myapp

# List all aliases
ascelerate alias list

# Remove an alias
ascelerate alias remove myapp
```

Aliases are stored in `~/.ascelerate/aliases.json`. Any argument that doesn't contain a dot is looked up as an alias — real bundle IDs (which always contain dots) work unchanged.

### Apps

```bash
# List all apps
ascelerate apps list

# Show app details
ascelerate apps info <bundle-id>

# List App Store versions
ascelerate apps versions <bundle-id>

# Create a new version
ascelerate apps create-version <bundle-id> <version-string>
ascelerate apps create-version <bundle-id> 2.1.0 --platform ios --release-type manual

# Check review submission status
ascelerate apps review status <bundle-id>
ascelerate apps review status <bundle-id> --version 2.1.0

# Submit for review
ascelerate apps review submit <bundle-id>
ascelerate apps review submit <bundle-id> --version 2.1.0

# Resolve rejected review items (after fixing issues and replying in Resolution Center)
ascelerate apps review resolve-issues <bundle-id>

# Cancel an active review submission
ascelerate apps review cancel-submission <bundle-id>
```

#### Pre-submission preflight checks

Before submitting for review, run `preflight` to verify that all required fields are filled in across every locale:

```bash
# Check the latest editable version
ascelerate apps review preflight <bundle-id>

# Check a specific version
ascelerate apps review preflight <bundle-id> --version 2.1.0
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
ascelerate apps build attach <bundle-id>
ascelerate apps build attach <bundle-id> --version 2.1.0

# Attach the most recent build automatically
ascelerate apps build attach-latest <bundle-id>

# Remove the attached build from a version
ascelerate apps build detach <bundle-id>
```

### Phased Release

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

### Age Rating

```bash
# View age rating declaration
ascelerate apps app-info age-rating <bundle-id>

# Export age rating to JSON
ascelerate apps app-info age-rating export <bundle-id>

# Update age ratings from a JSON file
ascelerate apps app-info age-rating import <bundle-id> --file age-rating.json
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
ascelerate apps routing-coverage <bundle-id>

# Upload a .geojson file
ascelerate apps routing-coverage <bundle-id> --file coverage.geojson
```

### Localizations

```bash
# View localizations (latest version by default)
ascelerate apps localizations view <bundle-id>
ascelerate apps localizations view <bundle-id> --version 2.1.0 --locale en-US

# Export localizations to JSON
ascelerate apps localizations export <bundle-id>
ascelerate apps localizations export <bundle-id> --version 2.1.0 --output my-localizations.json

# Update a single locale
ascelerate apps localizations update <bundle-id> --whats-new "Bug fixes" --locale en-US

# Bulk update from JSON file
ascelerate apps localizations import <bundle-id> --file localizations.json
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
ascelerate apps media download <bundle-id>
ascelerate apps media download <bundle-id> --folder my-media/ --version 2.1.0

# Upload screenshots and preview videos from a folder
ascelerate apps media upload <bundle-id> media/

# Upload from an archive (zip, tar, tar.gz supported)
ascelerate apps media upload <bundle-id> screenshots.zip

# Upload to a specific version
ascelerate apps media upload <bundle-id> media/ --version 2.1.0

# Replace existing media in matching sets before uploading
ascelerate apps media upload <bundle-id> media/ --replace

# Interactive mode: pick a folder or archive from the current directory
ascelerate apps media upload <bundle-id>
```

When the folder argument is omitted, the command lists all subdirectories and archive files in the current directory as a numbered picker. Archives (zip, tar, tar.gz) are extracted automatically before upload.

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
| `APP_IPHONE_67` | iPhone 6.7" (iPhone 17 Pro Max, 16 Pro Max, 15 Pro Max) | **Required** | Yes |
| `APP_IPAD_PRO_3GEN_129` | iPad Pro 12.9" (3rd gen+) | **Required** | Yes |

<details>
<summary>All optional display types</summary>

| Folder name | Device | Screenshots | Previews |
|---|---|---|---|
| `APP_IPHONE_61` | iPhone 6.1" (iPhone 17 Pro, 16 Pro, 15 Pro) | Yes | Yes |
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

#### Using with app-store-screenshots

[app-store-screenshots](https://github.com/keremerkan/ascelerate/tree/main/skills/app-store-screenshots) is a companion skill for AI coding agents that generates production-ready App Store screenshots. It creates a Next.js page that renders ad-style marketing layouts using framed device screenshots from `ascelerate screenshot frame` and exports them as a zip file ready for upload via `ascelerate apps media upload`:

```
en-US/APP_IPHONE_67/01_hero.png
en-US/APP_IPAD_PRO_3GEN_129/01_hero.png
de-DE/APP_IPHONE_67/01_hero.png
```

Install the skill for your AI coding agent:

```bash
npx skills add keremerkan/ascelerate
```

Upload the exported zip directly:

```bash
ascelerate apps media upload <bundle-id> screenshots.zip --replace
```

#### Verify and retry stuck media

Sometimes screenshots or previews get stuck in "processing" after upload. Use `media verify` to check the status of all media at once and optionally retry stuck items:

```bash
# Check status of all screenshots and previews
ascelerate apps media verify <bundle-id>

# Check a specific version
ascelerate apps media verify <bundle-id> --version 2.1.0

# Retry stuck items using local files from the media folder
ascelerate apps media verify <bundle-id> media/
```

Without `--folder`, the command shows a read-only status report. Sets where all items are complete show a compact one-liner; sets with stuck items expand to show each file and its state. With `--folder`, it prompts to retry stuck items by deleting them and re-uploading from the matching local files, preserving the original position order.

### Capturing Screenshots

Capture App Store screenshots directly from iOS/iPadOS simulators using UI tests. Replaces [fastlane snapshot](https://docs.fastlane.tools/actions/snapshot/).

```bash
# Generate config and helper files
ascelerate screenshot init                        # Creates ascelerate/screenshot.yml and ascelerate/ScreenshotHelper.swift

# Capture screenshots
ascelerate screenshot run
ascelerate screenshot run -l en-US,tr-TR          # Only capture a subset of configured languages
ascelerate screenshot frame                       # Frame screenshots with device bezels
ascelerate screenshot doctor                      # Check config and environment for problems
```

Add `ScreenshotHelper.swift` to your UITest target, then call `setupScreenshots(app)` in `setUp()` and `screenshot("name")` to capture:

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

Configure via `ascelerate/screenshot.yml`:

```yaml
# workspace: MyApp.xcworkspace
project: MyApp.xcodeproj
scheme: AppUITests
devices:
  - simulator: iPhone 17 Pro Max
    # frameDevice: true
    # deviceBezel: ./bezels/iPhone 17 Pro Max.png
  - simulator: iPad Pro 13-inch (M5)
    # frameDevice: true
    # deviceBezel: ./bezels/iPad Pro 13-inch (M5).png
languages:
  - en-US
  - de-DE
outputDirectory: ./screenshots
# framedOutputDirectory: ./screenshots/framed
clearPreviousScreenshots: true
localizeSimulator: true
overrideStatusBar: true
# darkMode: false
# disableAnimations: false
# waitAfterBoot: 0
# configuration: Debug
# testplan: MyTestPlan
# numberOfRetries: 0                    # Retry failed languages (erase + reboot simulator)
# stopAfterFirstError: false
# reinstallApp: false
# xcargs: -maximum-parallel-testing-workers 2
```

Features:
- Builds once, then runs tests across all languages
- iPhone and iPad run concurrently per language
- Status bar override (9:41, full bars, no carrier)
- Simulator localization per language
- Dark mode support
- Animation disabling for reliable captures
- Automatic retries for failed languages (erases simulator, re-localizes, reboots, and reruns)
- Errors skip and continue, with summary table and error logs saved to output
- Helper version tracking with update warnings
- Device bezel framing with [Apple Product Bezels](https://developer.apple.com/design/resources/#product-bezels) (download required)
- Config validation via `doctor` subcommand
- `create-helper` available separately but also run automatically by `init`

Output structure:
```
screenshots/
├── en-US/
│   ├── iPhone-01-home.png
│   └── iPad-01-home.png
└── de-DE/
    └── ...
```

With `frameDevice` enabled, framed screenshots are saved to `{outputDirectory}/framed/` (or `framedOutputDirectory` if set).

### App Info & Categories

```bash
# View app info, categories, and per-locale metadata
ascelerate apps app-info view <bundle-id>

# List all available category IDs (no bundle ID needed)
ascelerate apps app-info view --list-categories

# Update localization fields for a single locale
ascelerate apps app-info update <bundle-id> --name "My App" --subtitle "Best app ever"
ascelerate apps app-info update <bundle-id> --locale de-DE --name "Meine App"

# Update categories (can combine with localization flags)
ascelerate apps app-info update <bundle-id> --primary-category UTILITIES
ascelerate apps app-info update <bundle-id> --primary-category GAMES_ACTION --secondary-category ENTERTAINMENT

# Export all app info localizations to JSON
ascelerate apps app-info export <bundle-id>
ascelerate apps app-info export <bundle-id> --output app-infos.json

# Bulk update localizations from a JSON file
ascelerate apps app-info import <bundle-id> --file app-infos.json
```

### Territory Availability

```bash
# View which territories the app is available in
ascelerate apps availability <bundle-id>

# Show full country names
ascelerate apps availability <bundle-id> --verbose

# Make territories available or unavailable
ascelerate apps availability <bundle-id> --add CHN,RUS
ascelerate apps availability <bundle-id> --remove CHN
```

### Encryption Declarations

```bash
# View existing encryption declarations
ascelerate apps encryption <bundle-id>

# Create a new encryption declaration
ascelerate apps encryption <bundle-id> --create --description "Uses HTTPS for API communication"
ascelerate apps encryption <bundle-id> --create --description "Uses AES encryption" --proprietary-crypto --third-party-crypto
```

### EULA

```bash
# View the current EULA (or see that the standard Apple EULA applies)
ascelerate apps eula <bundle-id>

# Set a custom EULA from a text file
ascelerate apps eula <bundle-id> --file eula.txt

# Remove the custom EULA (reverts to standard Apple EULA)
ascelerate apps eula <bundle-id> --delete
```

### Subscription Grace Period

The grace period lets subscribers keep access for a short window after a failed renewal payment while Apple retries billing. Settings apply to the whole app.

```bash
# View current grace period configuration
ascelerate apps subscription-grace-period <bundle-id>

# Enable for production with a 16-day window, applies to all renewals
ascelerate apps subscription-grace-period <bundle-id> --opt-in true --duration SIXTEEN_DAYS --renewal-type ALL_RENEWALS

# Enable for sandbox testing too
ascelerate apps subscription-grace-period <bundle-id> --sandbox-opt-in true
```

Valid `--duration` values: `THREE_DAYS`, `SIXTEEN_DAYS`, `TWENTY_EIGHT_DAYS`. Valid `--renewal-type` values: `ALL_RENEWALS`, `PAID_TO_PAID_ONLY`.

### Devices

```bash
# List registered devices
ascelerate devices list
ascelerate devices list --platform IOS --status ENABLED

# Show device details (interactive picker if name/UDID omitted)
ascelerate devices info
ascelerate devices info "My iPhone"

# Register a new device (interactive prompts if options omitted)
ascelerate devices register
ascelerate devices register --name "My iPhone" --udid 00008101-XXXXXXXXXXXX --platform IOS

# Update a device (interactive picker and update prompts if omitted)
ascelerate devices update
ascelerate devices update "My iPhone" --name "Work iPhone"
ascelerate devices update "My iPhone" --status DISABLED
```

### Certificates

```bash
# List signing certificates
ascelerate certs list
ascelerate certs list --type DISTRIBUTION

# Show certificate details (interactive picker if omitted)
ascelerate certs info
ascelerate certs info "Apple Distribution: Example Inc"

# Create a certificate (interactive type picker if --type omitted)
# Auto-generates RSA key pair and CSR, imports into login keychain
ascelerate certs create
ascelerate certs create --type DISTRIBUTION
ascelerate certs create --type DEVELOPMENT --csr my-request.pem

# Revoke a certificate (interactive picker if omitted)
ascelerate certs revoke
ascelerate certs revoke ABC123DEF456
```

### Bundle Identifiers

```bash
# List bundle identifiers
ascelerate bundle-ids list
ascelerate bundle-ids list --platform IOS

# Show details and capabilities (interactive picker if omitted)
ascelerate bundle-ids info
ascelerate bundle-ids info com.example.MyApp

# Register a new bundle ID (interactive prompts if options omitted)
ascelerate bundle-ids register
ascelerate bundle-ids register --name "My App" --identifier com.example.MyApp --platform IOS

# Rename a bundle ID (identifier itself is immutable)
ascelerate bundle-ids update
ascelerate bundle-ids update com.example.MyApp --name "My Renamed App"

# Delete a bundle ID (interactive picker if omitted)
ascelerate bundle-ids delete
ascelerate bundle-ids delete com.example.MyApp

# Enable a capability (interactive pickers if omitted)
# Shows only capabilities not already enabled
ascelerate bundle-ids enable-capability
ascelerate bundle-ids enable-capability com.example.MyApp --type PUSH_NOTIFICATIONS

# Disable a capability (picks from currently enabled capabilities)
ascelerate bundle-ids disable-capability
ascelerate bundle-ids disable-capability com.example.MyApp
```

After enabling or disabling a capability, if provisioning profiles exist for that bundle ID, the command offers to regenerate them (required for changes to take effect).

> **Note:** Some capabilities (e.g. App Groups, iCloud, Associated Domains) require additional configuration in the [Apple Developer portal](https://developer.apple.com/account/resources) after enabling.

### Provisioning Profiles

```bash
# List provisioning profiles
ascelerate profiles list
ascelerate profiles list --type IOS_APP_STORE --state ACTIVE

# Show profile details (interactive picker if omitted)
ascelerate profiles info
ascelerate profiles info "My App Store Profile"

# Download a profile (interactive picker if omitted)
ascelerate profiles download
ascelerate profiles download "My App Store Profile" --output ./profiles/

# Create a profile (fully interactive if options omitted)
# Prompts for name, type, bundle ID, certificates, and devices
ascelerate profiles create
ascelerate profiles create --name "My Profile" --type IOS_APP_STORE --bundle-id com.example.MyApp --certificates all

# --certificates all uses all certs of the matching family (distribution, development, or Developer ID)
# You can also specify serial numbers: --certificates ABC123,DEF456

# Delete a profile (interactive picker if omitted)
ascelerate profiles delete
ascelerate profiles delete "My App Store Profile"

# Reissue profiles (delete + recreate with latest certs of matching family)
ascelerate profiles reissue                         # Interactive: pick from all profiles (shows status)
ascelerate profiles reissue "My Profile"            # Reissue a specific profile by name
ascelerate profiles reissue --all-invalid           # Reissue all invalid profiles
ascelerate profiles reissue --all                   # Reissue all profiles regardless of state
ascelerate profiles reissue --all --all-devices     # Reissue all, using all enabled devices for dev/adhoc
ascelerate profiles reissue --all --to-certs ABC123,DEF456  # Use specific certificates instead of auto-detect
```

### Builds

```bash
# List all builds (shows app version and build number)
ascelerate builds list
ascelerate builds list --bundle-id <bundle-id>
ascelerate builds list --bundle-id <bundle-id> --version 2.1.0

# Archive an Xcode project
ascelerate builds archive
ascelerate builds archive --scheme MyApp --output ./archives

# Validate a build before uploading
ascelerate builds validate MyApp.ipa

# Upload a build to App Store Connect
ascelerate builds upload MyApp.ipa

# Wait for a build to finish processing
ascelerate builds await-processing <bundle-id>
ascelerate builds await-processing <bundle-id> --build-version 903
```

The `archive` command auto-detects the `.xcworkspace` or `.xcodeproj` in the current directory and resolves the scheme if only one exists. It accepts `.ipa`, `.pkg`, or `.xcarchive` files for `upload` and `validate`. When given an `.xcarchive`, it automatically exports to `.ipa` before uploading.

### In-App Purchases

```bash
# List and inspect
ascelerate iap list <bundle-id>
ascelerate iap list <bundle-id> --type consumable --state approved
ascelerate iap info <bundle-id> <product-id>
ascelerate iap promoted <bundle-id>

# Create, update, and delete
ascelerate iap create <bundle-id> --name "100 Coins" --product-id <product-id> --type CONSUMABLE
ascelerate iap update <bundle-id> <product-id> --name "100 Gold Coins"
ascelerate iap delete <bundle-id> <product-id>

# Submit for review
ascelerate iap submit <bundle-id> <product-id>

# Manage localizations
ascelerate iap localizations view <bundle-id> <product-id>
ascelerate iap localizations export <bundle-id> <product-id>
ascelerate iap localizations import <bundle-id> <product-id> --file iap-de.json

# Pricing — set the base region price (auto-equalizes to all other territories)
ascelerate iap pricing show <bundle-id> <product-id>
ascelerate iap pricing tiers <bundle-id> <product-id> --territory USA
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99 --base-territory GBR

# Pricing — manage per-territory manual overrides
ascelerate iap pricing override <bundle-id> <product-id> --price 5.99 --territory FRA
ascelerate iap pricing remove <bundle-id> <product-id> --territory FRA

# Per-IAP territory availability (independent of the app's territories)
ascelerate iap availability <bundle-id> <product-id>
ascelerate iap availability <bundle-id> <product-id> --add CHN,RUS --remove ITA --available-in-new-territories true

# Offer codes (campaigns + redeem codes)
ascelerate iap offer-code list <bundle-id> <product-id>
ascelerate iap offer-code create <bundle-id> <product-id> --name "Launch Promo" --eligibility NON_SPENDER,ACTIVE_SPENDER --price 0.99 --territory USA --equalize-all-territories
ascelerate iap offer-code toggle <bundle-id> <product-id> <offer-code-id> --active true
ascelerate iap offer-code gen-codes <bundle-id> <product-id> <offer-code-id> --count 100 --expires 2026-12-31
ascelerate iap offer-code add-custom-codes <bundle-id> <product-id> <offer-code-id> --code PROMO2026 --count 1000 --expires 2026-12-31
ascelerate iap offer-code view-codes <one-time-use-batch-id> --output codes.txt

# Promotional images + App Review screenshot
ascelerate iap images list <bundle-id> <product-id>
ascelerate iap images upload <bundle-id> <product-id> ./hero.png
ascelerate iap images delete <bundle-id> <product-id> <image-id>
ascelerate iap review-screenshot view <bundle-id> <product-id>
ascelerate iap review-screenshot upload <bundle-id> <product-id> ./review.png
ascelerate iap review-screenshot delete <bundle-id> <product-id>
```

Filter values are case-insensitive. Types: `CONSUMABLE`, `NON_CONSUMABLE`, `NON_RENEWING_SUBSCRIPTION`. States: `APPROVED`, `MISSING_METADATA`, `READY_TO_SUBMIT`, `WAITING_FOR_REVIEW`, `IN_REVIEW`, etc.

`iap info` and `iap pricing show` warn when an IAP has no price schedule — the same condition surfaced in `apps review preflight`. When `set` changes the base territory price, existing per-territory manual overrides are preserved by default. If overrides exist, an interactive menu offers to revert any of them; pass `--remove-all-overrides` for a non-interactive wipe.

Offer code one-time-use codes are generated asynchronously. After `gen-codes`, run `view-codes <batch-id>` to fetch the actual code values. If the response is empty, retry in a few seconds. Custom codes (`add-custom-codes`) are developer-supplied strings that don't need separate generation.

Images and review screenshots use Apple's 3-step file upload flow (reserve → PUT chunks → commit with MD5). The CLI handles all three steps in `upload`.

### Subscriptions

```bash
# List and inspect
ascelerate sub groups <bundle-id>
ascelerate sub list <bundle-id>
ascelerate sub info <bundle-id> <product-id>

# Create, update, and delete subscriptions
ascelerate sub create <bundle-id> --name "Monthly" --product-id <product-id> --period ONE_MONTH --group-id <group-id>
ascelerate sub update <bundle-id> <product-id> --name "Monthly Plan"
ascelerate sub delete <bundle-id> <product-id>

# Manage subscription groups
ascelerate sub create-group <bundle-id> --name "Premium"
ascelerate sub update-group <bundle-id> --name "Premium Plus"
ascelerate sub delete-group <bundle-id>

# Submit for review
ascelerate sub submit <bundle-id> <product-id>

# Subscription localizations
ascelerate sub localizations view <bundle-id> <product-id>
ascelerate sub localizations export <bundle-id> <product-id>
ascelerate sub localizations import <bundle-id> <product-id> --file sub-de.json

# Subscription group localizations
ascelerate sub group-localizations view <bundle-id>
ascelerate sub group-localizations export <bundle-id>
ascelerate sub group-localizations import <bundle-id> --file group-de.json

# Pricing — single territory or fan-out across all territories
ascelerate sub pricing show <bundle-id> <product-id>
ascelerate sub pricing tiers <bundle-id> <product-id> --territory USA
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --territory USA
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --equalize-all-territories

# Standard global price raise: grandfather existing subscribers at the old price
ascelerate sub pricing set <bundle-id> <product-id> --price 9.99 --equalize-all-territories --preserve-current

# Per-subscription territory availability (independent of the app's territories)
ascelerate sub availability <bundle-id> <product-id>
ascelerate sub availability <bundle-id> <product-id> --add CHN,RUS --remove ITA --available-in-new-territories true

# Introductory offers (free trials and intro discounts for new subscribers)
ascelerate sub intro-offer list <bundle-id> <product-id>
ascelerate sub intro-offer create <bundle-id> <product-id> --mode FREE_TRIAL --duration ONE_WEEK --periods 1
ascelerate sub intro-offer create <bundle-id> <product-id> --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 --territory USA --price 0.99
ascelerate sub intro-offer update <bundle-id> <product-id> <offer-id> --end-date 2026-12-31
ascelerate sub intro-offer delete <bundle-id> <product-id> <offer-id>

# Promotional offers (server-signed offers for existing subscribers)
ascelerate sub promo-offer list <bundle-id> <product-id>
ascelerate sub promo-offer create <bundle-id> <product-id> --name "Loyalty 50%" --code LOYALTY50 --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 --price 4.99 --territory USA --equalize-all-territories
ascelerate sub promo-offer update <bundle-id> <product-id> <offer-id> --price 5.99 --equalize-all-territories
ascelerate sub promo-offer delete <bundle-id> <product-id> <offer-id>

# Offer codes (redeemable codes — one-time-use batches and custom codes)
ascelerate sub offer-code list <bundle-id> <product-id>
ascelerate sub offer-code create <bundle-id> <product-id> --name "Launch Free Month" --eligibility NEW --offer-eligibility STACK_WITH_INTRO_OFFERS --mode FREE_TRIAL --duration ONE_MONTH --periods 1 --price 0 --territory USA --equalize-all-territories
ascelerate sub offer-code toggle <bundle-id> <product-id> <offer-code-id> --active true
ascelerate sub offer-code gen-codes <bundle-id> <product-id> <offer-code-id> --count 500 --expires 2026-12-31
ascelerate sub offer-code add-custom-codes <bundle-id> <product-id> <offer-code-id> --code SUBPROMO --count 1000 --expires 2026-12-31
ascelerate sub offer-code view-codes <one-time-use-batch-id> --output codes.txt

# Submit a subscription group for review (mirror of `sub submit` but for the whole group)
ascelerate sub submit-group <bundle-id>

# Promotional images + App Review screenshot
ascelerate sub images list <bundle-id> <product-id>
ascelerate sub images upload <bundle-id> <product-id> ./hero.png
ascelerate sub images delete <bundle-id> <product-id> <image-id>
ascelerate sub review-screenshot view <bundle-id> <product-id>
ascelerate sub review-screenshot upload <bundle-id> <product-id> ./review.png
ascelerate sub review-screenshot delete <bundle-id> <product-id>
```

When submitting an app version for review, `apps review submit` automatically detects IAPs and subscriptions that may have pending changes and offers to submit them alongside the app version.

The localization import commands create missing locales automatically with confirmation, so you can add new languages without visiting App Store Connect.

`sub intro-offer` is for new subscribers (free trials and intro discounts). `sub promo-offer` is for existing subscribers (requires server-side signing of the offer payload at runtime). `sub offer-code` produces redeemable code campaigns — one-time-use batches generate asynchronously (use `view-codes <batch-id>` to fetch values), while custom codes are developer-supplied strings.

Images and review screenshots use Apple's 3-step upload flow (reserve → PUT chunks → commit with MD5) — `upload` handles all three steps.

**Win-back offers** are intentionally not yet implemented because asc-swift's generated `WinBackOfferPriceInlineCreate` is missing the territory and price-point relationships the API requires. Will revisit once the dependency is updated.

Subscription pricing is per-territory. There is no auto-equalize concept like IAPs have, so `--equalize-all-territories` mirrors what the App Store Connect web UI does behind the scenes: looks up the equivalent local-currency tier in every territory and POSTs one price record per territory.

Apple treats price changes differently for existing subscribers depending on direction — `sub pricing set` enforces this:

- **Decrease**: existing subscribers automatically move to the lower price. Interactive runs prompt; `--yes` mode requires `--confirm-decrease` to acknowledge the revenue impact.
- **Increase**: you must explicitly choose how to handle existing subscribers. Errors unless `--preserve-current` (grandfather them at the old price) or `--no-preserve-current` (push them to the new price after Apple's notification period) is set. Same rule applies aggregated across `--equalize-all-territories`.
- **New territory** (no existing price): no existing subscribers to consider; flags optional.
- **Unchanged**: skipped silently.

### Rate Limit

Check your current API usage against the rolling hourly quota:

```bash
ascelerate rate-limit
```

```
Hourly limit: 3600 requests (rolling window)
Used:         57
Remaining:    3543 (98%)
```

### Workflows

Chain multiple commands into a single automated run with a workflow file:

```bash
ascelerate run-workflow release.txt
ascelerate run-workflow release.txt --yes   # skip all prompts (CI/CD)
ascelerate run-workflow                     # interactively select from .workflow/.txt files
```

A workflow file is a plain text file with one command per line (without the `ascelerate` prefix). Lines starting with `#` are comments, blank lines are ignored. Both `.workflow` and `.txt` extensions are supported.

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
ascelerate apps build attach-latest <bundle-id> --yes
ascelerate apps review submit <bundle-id> --yes
```

### Version

```bash
ascelerate version     # Prints version number
ascelerate --version   # Same as above
ascelerate -v          # Same as above
```

## Acknowledgments

Built on top of [asc-swift](https://github.com/aaronsky/asc-swift) by Aaron Sky.

*"A Swift Client, App Store Connect"* — [@validatedev](https://x.com/validatedev/status/2026613415012118674)

The [app-store-screenshots](https://github.com/keremerkan/ascelerate/tree/main/skills/app-store-screenshots) skill is based on [ParthJadhav/app-store-screenshots](https://github.com/ParthJadhav/app-store-screenshots), significantly rewritten with device bezel framing, iPad support, localization, and ascelerate-compatible export.

Developed with [Claude Code](https://claude.ai/code).

## License

MIT
