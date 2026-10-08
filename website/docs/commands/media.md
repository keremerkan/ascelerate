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
ascelerate apps media upload <bundle-id> media/

# Upload from an archive (zip, tar, tar.gz supported)
ascelerate apps media upload <bundle-id> screenshots.zip

# Upload to a specific version (add --platform for universal-purchase apps)
ascelerate apps media upload <bundle-id> media/ --version 2.1.0
ascelerate apps media upload <bundle-id> media/ --version 2.1.0 --platform macos

# Replace existing media in matching sets before uploading
ascelerate apps media upload <bundle-id> media/ --replace

# Interactive mode: pick a folder or archive from the current directory
ascelerate apps media upload <bundle-id>
```

When the folder argument is omitted, the command lists all subdirectories and archive files in the current directory as a numbered picker. Archives (zip, tar, tar.gz) are extracted automatically before upload.

Each file's line starts with its position in the run (`[57/203]`). In a terminal, the line also shows how much of the file has been uploaded while it's being sent.

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
| `APP_IPHONE_DUO` | iPhone Duo (see [below](#iphone-duo)) | Yes | No |
| `PRODUCT_PAGE_HEADER` | Product page header (see [below](#header-and-search-results)) | Yes | No |
| `APP_STORE_SEARCH_RESULTS` | App Store search results (see [below](#header-and-search-results)) | Yes | No |
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

### iPhone Duo

App Store Connect has no screenshot set for iPhone Duo. ascelerate uploads the files in an `APP_IPHONE_DUO` folder to the app's asset library and places them on the version localization, in file order. Accepted sizes are 2853×2007 or 2007×2853 (inner display, unfolded) and 2034×1398 or 1398×2034 (cover display); other sizes are rejected before anything is uploaded. With `--replace`, each locale's existing iPhone Duo screenshots are removed first.

If a file still fails after retries, `media upload` places that locale's iPhone Duo screenshots again at the end of the run, so they stay in file order. `media verify` lists iPhone Duo screenshots with their file names and processing state; given the media folder, it also flags locales whose iPhone Duo screenshots differ from the folder in files or order (run `media upload` with `--replace` to fix them). iPhone Duo app previews are not supported yet, `media download` doesn't include iPhone Duo screenshots, and `media prune` never deletes them.

### Product page header and search results {#header-and-search-results}

Two more folders upload through the asset library. Each holds one image per locale, which isn't tied to a device class: the version shows it on every device (iPhone, iPad, iPhone Duo), and they work for every platform's versions.

- `PRODUCT_PAGE_HEADER`: the image at the top of the product page. PNG at 3840×1646 or 5244×2950.
- `APP_STORE_SEARCH_RESULTS`: the image shown with the app in App Store search results. JPG or PNG at 3:2, from 1920×1280 to 3840×2560, or a 5244×2950 PNG.

Uploading replaces the locale's current image, with or without `--replace`; the old one is removed only after the new one has been uploaded. Videos for these slots are not supported yet. `media verify` checks them the same way as iPhone Duo screenshots.

## Using with app-store-screenshots

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

## Verify and retry stuck media

Sometimes screenshots or previews get stuck in "processing" after upload. Use `media verify` to check the status and optionally retry stuck items:

```bash
# Check status of all screenshots and previews
ascelerate apps media verify <bundle-id>

# Check a specific version
ascelerate apps media verify <bundle-id> --version 2.1.0

# Retry stuck items using local files from the media folder
ascelerate apps media verify <bundle-id> media/
```

Without a folder argument, the command shows a read-only status report. Sets where all items are complete show a compact one-liner; sets with stuck items expand to show each file and its state. With a folder argument, it prompts to retry stuck items by deleting them and re-uploading from the matching local files, preserving the original position order.

## Prune stale sets

`--replace` on upload only clears sets that match a local folder — server sets for screen sizes you no longer ship keep their outdated screenshots. `media prune` deletes the sets with no matching local locale/display-type folder, after listing them with asset counts and confirming:

```bash
ascelerate apps media prune <bundle-id> media/
ascelerate apps media prune <bundle-id> media/ --version 2.1.0 --platform ios
```

Locales without a local folder are skipped entirely — the command only prunes within locales the folder actually manages.

## Remove asset library images

`media remove` takes one kind of asset library image off the version: `PRODUCT_PAGE_HEADER`, `APP_STORE_SEARCH_RESULTS` or `APP_IPHONE_DUO`. It works on the locales given with `--locale` or on all of them, and lists what it found before asking:

```bash
ascelerate apps media remove <bundle-id> PRODUCT_PAGE_HEADER --locale en-US
ascelerate apps media remove <bundle-id> APP_STORE_SEARCH_RESULTS
ascelerate apps media remove <bundle-id> APP_IPHONE_DUO --locale en-US,tr --version 2.1.0
```

## Clean up the asset library

Every app has an asset library holding its uploaded images, and versions share them: a new version's screenshots are the previous version's images, and old versions keep theirs. An image therefore stays in use as long as any version (old ones included), custom product page or event places it. When ascelerate removes a placement (`media remove`, `media upload --replace`, or replacing a header or search results image), it also deletes the image if nothing uses it any more and it never went through App Review.

Earlier uploads can still have left unused images in the library. `media library` counts the images and lists the unused ones; with `--delete-unused` it deletes them after asking:

```bash
ascelerate apps media library <bundle-id>
ascelerate apps media library <bundle-id> --delete-unused
ascelerate apps media library <bundle-id> --only APP_IPHONE_DUO --delete-unused
```

`--only` narrows the list to images that fit the given kinds, judged by asset category and pixel size: `PRODUCT_PAGE_HEADER`, `APP_STORE_SEARCH_RESULTS`, `APP_IPHONE_DUO`, a screenshot display type such as `APP_IPHONE_67` (sizes come from App Store Connect), or `UNFINISHED_UPLOADS` for uploads whose file never arrived. That way the library can be cleaned one device type at a time. Images less than an hour old are always kept, since an upload running at the same time may be about to place them, and a run that reaches App Store Connect's hourly API limit stops and tells you to run it again later.

Images that went through App Review are never deleted, whether placed or not, and each image is checked again right before it is deleted.
