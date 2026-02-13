# asc-client

A command-line tool for the [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi), built with Swift.

> **Note:** This is an early prototype focused on app version workflows -- creating versions, managing localizations, uploading screenshots, and submitting for review. More API coverage is planned but not yet implemented.

## Requirements

- macOS 13+
- Swift 6.0+ (only for building from source)

## Installation

### Homebrew

```bash
brew tap keremerkan/tap
brew install asc-client
```

The tap provides a pre-built binary for Apple Silicon Macs, so installation is instant.

### Download the binary

Download the latest release from [GitHub Releases](https://github.com/keremerkan/asc-client/releases):

```bash
curl -L https://github.com/keremerkan/asc-client/releases/latest/download/asc-client-macos-arm64.tar.gz -o asc-client.tar.gz
tar xzf asc-client.tar.gz
mv asc-client /usr/local/bin/
```

Since the binary is not signed or notarized, macOS will quarantine it on first download. Remove the quarantine attribute:

```bash
xattr -d com.apple.quarantine /usr/local/bin/asc-client
```

> **Note:** Pre-built binaries are provided for Apple Silicon (arm64) only. Intel Mac users should build from source.

### Build from source

```bash
git clone https://github.com/keremerkan/asc-client.git
cd asc-client
swift build -c release
strip .build/release/asc-client
cp .build/release/asc-client /usr/local/bin/
```

> **Note:** The release build takes a few minutes because the [asc-swift](https://github.com/aaronsky/asc-swift) dependency includes ~2500 generated source files covering the entire App Store Connect API surface. `strip` removes debug symbols, reducing the binary from ~175 MB to ~59 MB.

### Shell completions

Set up tab completion for subcommands, options, and flags (supports zsh and bash):

```bash
asc-client install-shell-completions
```

This detects your shell and configures everything automatically. Restart your shell or open a new tab to activate.

## Setup

### 1. Create an API Key

Go to [App Store Connect > Users and Access > Integrations > App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) and generate a new key. Download the `.p8` private key file.

### 2. Configure

```bash
asc-client configure
```

This will prompt for your **Key ID**, **Issuer ID**, and the path to your `.p8` file. The private key is copied into `~/.asc-client/` with strict file permissions (owner-only access).

## Usage

### Apps

```bash
# List all apps
asc-client apps list

# Show app details
asc-client apps info <bundle-id>

# List App Store versions
asc-client apps versions <bundle-id>

# Create a new version
asc-client apps create-version <bundle-id> <version-string>
asc-client apps create-version <bundle-id> 2.1.0 --platform ios --release-type manual

# Check review submission status
asc-client apps review-status <bundle-id>
```

### Localizations

```bash
# View localizations (latest version by default)
asc-client apps localizations <bundle-id>
asc-client apps localizations <bundle-id> --version 1.2.0 --locale en-US

# Export localizations to JSON
asc-client apps export-localizations <bundle-id>
asc-client apps export-localizations <bundle-id> --version 1.2.0 --output my-localizations.json

# Update a single locale
asc-client apps update-localization <bundle-id> --whats-new "Bug fixes" --locale en-US

# Bulk update from JSON file
asc-client apps update-localizations <bundle-id> --file localizations.json
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
asc-client apps download-media <bundle-id>
asc-client apps download-media <bundle-id> --folder my-media/ --version 2.1.0

# Upload screenshots and preview videos from a folder
asc-client apps upload-media <bundle-id> --folder media/

# Upload to a specific version
asc-client apps upload-media <bundle-id> --folder media/ --version 2.1.0

# Replace existing media in matching sets before uploading
asc-client apps upload-media <bundle-id> --folder media/ --replace
```

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

| Folder name | Device | Screenshots | Previews |
|---|---|---|---|
| `APP_IPHONE_67` | iPhone 6.7" (iPhone 16 Pro Max, 15 Pro Max, 14 Pro Max) | Yes | Yes |
| `APP_IPHONE_61` | iPhone 6.1" (iPhone 16 Pro, 15 Pro, 14 Pro) | Yes | Yes |
| `APP_IPHONE_65` | iPhone 6.5" (iPhone 11 Pro Max, XS Max) | Yes | Yes |
| `APP_IPHONE_58` | iPhone 5.8" (iPhone 11 Pro, X, XS) | Yes | Yes |
| `APP_IPHONE_55` | iPhone 5.5" (iPhone 8 Plus, 7 Plus, 6s Plus) | Yes | Yes |
| `APP_IPHONE_47` | iPhone 4.7" (iPhone SE 3rd gen, 8, 7, 6s) | Yes | Yes |
| `APP_IPHONE_40` | iPhone 4" (iPhone SE 1st gen, 5s, 5c) | Yes | Yes |
| `APP_IPHONE_35` | iPhone 3.5" (iPhone 4s and earlier) | Yes | Yes |
| `APP_IPAD_PRO_3GEN_129` | iPad Pro 12.9" (3rd gen+) | Yes | Yes |
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

> **Note:** Watch and iMessage display types support screenshots only -- video files in those folders are skipped with a warning. The `--replace` flag deletes all existing assets in each matching set before uploading new ones.
>
> `download-media` saves files in this same folder structure (defaults to `<bundle-id>-media/`), so you can download, edit, and re-upload.

#### Verify and retry stuck media

Sometimes screenshots or previews get stuck in "processing" after upload. Use `verify-media` to check the status of all media at once and optionally retry stuck items:

```bash
# Check status of all screenshots and previews
asc-client apps verify-media <bundle-id>

# Check a specific version
asc-client apps verify-media <bundle-id> --version 2.1.0

# Retry stuck items using local files from the media folder
asc-client apps verify-media <bundle-id> --folder media/
```

Without `--folder`, the command shows a read-only status report. Sets where all items are complete show a compact one-liner; sets with stuck items expand to show each file and its state. With `--folder`, it prompts to retry stuck items by deleting them and re-uploading from the matching local files, preserving the original position order.

### Builds

```bash
# List all builds
asc-client builds list

# Filter by app
asc-client builds list --bundle-id <bundle-id>
```

## Acknowledgments

Built on top of [asc-swift](https://github.com/aaronsky/asc-swift) by Aaron Sky.

Developed with [Claude Code](https://claude.ai/code).

## License

MIT
