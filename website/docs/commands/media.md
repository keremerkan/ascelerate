---
sidebar_position: 4
title: Screenshots & Previews
---

# Screenshots & App Previews

## Download

```bash
ascelerate apps media download <bundle-id>
ascelerate apps media download <bundle-id> --folder my-media/ --version 2.1.0
```

Downloads to `<bundle-id>-media/` by default, using the same folder structure expected by upload.

## Upload

```bash
# Upload from a folder
ascelerate apps media upload <bundle-id> --folder media/

# Upload from a zip file (e.g. exported from asc-screenshots)
ascelerate apps media upload <bundle-id> --folder screenshots.zip

# Upload to a specific version
ascelerate apps media upload <bundle-id> --folder media/ --version 2.1.0

# Replace existing media in matching sets before uploading
ascelerate apps media upload <bundle-id> --folder media/ --replace

# Interactive mode: pick a folder or zip from the current directory
ascelerate apps media upload <bundle-id>
```

When `--folder` is omitted, the command lists all subdirectories and `.zip` files in the current directory as a numbered picker. Zip files are extracted automatically before upload.

## Folder structure

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
- **Level 3:** Media files — images (`.png`, `.jpg`, `.jpeg`) become screenshots, videos (`.mp4`, `.mov`) become app previews
- Files are uploaded in alphabetical order by filename
- Unsupported files are skipped with a warning

## Display types

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

:::note
Watch and iMessage display types support screenshots only — video files in those folders are skipped with a warning. The `--replace` flag deletes all existing assets in each matching set before uploading new ones.
:::

## Using with asc-screenshots

[asc-screenshots](https://github.com/keremerkan/asc-screenshots) is a companion skill for AI coding agents that generates production-ready App Store screenshots. It creates a Next.js page that renders ad-style screenshot layouts with device bezels and exports them as a zip file in the exact folder structure ascelerate expects:

```
en-US/APP_IPHONE_67/01_hero.png
en-US/APP_IPAD_PRO_3GEN_129/01_hero.png
de-DE/APP_IPHONE_67/01_hero.png
```

Upload the exported zip directly:

```bash
ascelerate apps media upload <bundle-id> --folder screenshots.zip --replace
```

## Verify and retry stuck media

Sometimes screenshots or previews get stuck in "processing" after upload. Use `media verify` to check the status and optionally retry stuck items:

```bash
# Check status of all screenshots and previews
ascelerate apps media verify <bundle-id>

# Check a specific version
ascelerate apps media verify <bundle-id> --version 2.1.0

# Retry stuck items using local files from the media folder
ascelerate apps media verify <bundle-id> --folder media/
```

Without `--folder`, the command shows a read-only status report. Sets where all items are complete show a compact one-liner; sets with stuck items expand to show each file and its state. With `--folder`, it prompts to retry stuck items by deleting them and re-uploading from the matching local files, preserving the original position order.
