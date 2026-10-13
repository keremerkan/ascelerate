---
sidebar_position: 18
title: Product Page Optimization
---

# Product Page Optimization

Test alternative screenshots, app previews, and app icons against your original App Store product page. A test shows up to three **treatments** (variants of the page) to a share of App Store visitors and compares their conversion rates with the original's. Tests and treatments are referenced by **name** or ID.

## List & inspect

```bash
ascelerate experiments <bundle-id>
ascelerate experiments info <bundle-id> "Screenshot order"
```

`info` shows the test's state, traffic share, and dates, and each treatment with its locales and media per locale. Both commands accept `--json`.

## Create a test

```bash
ascelerate experiments create <bundle-id> --name "Screenshot order" --traffic 50 --treatment "Map first" --treatment "Alerts first"
```

`--traffic` is the percentage of App Store visitors who see one of the treatments; it is split evenly among them, and everyone else sees the original page. `--platform` defaults to `ios`.

## Treatments

```bash
ascelerate experiments treatments add <bundle-id> "Screenshot order" --name "Icon B" --app-icon AppIconB
ascelerate experiments treatments update <bundle-id> "Screenshot order" "Icon B" --name "Blue icon"
ascelerate experiments treatments delete <bundle-id> "Screenshot order" "Blue icon"
ascelerate experiments treatments remove-locale <bundle-id> "Screenshot order" "Map first" --locale de-DE
```

`--app-icon` tests an alternate app icon; it must be included in the live build as an alternate icon. A locale a treatment doesn't cover shows the original page, even to visitors in the test.

## Media

```bash
ascelerate experiments media list <bundle-id> "Screenshot order"
ascelerate experiments media upload <bundle-id> "Screenshot order" "Map first" --locale en-US --display-type APP_IPHONE_67 01.png
ascelerate experiments media upload <bundle-id> "Screenshot order" "Map first" --locale en-US --preview-type APP_IPHONE_67 preview.mp4
ascelerate experiments media delete <bundle-id> "Screenshot order" <media-id>
```

Uploads work like [custom product page media](product-pages.md): images go to screenshot sets by `--display-type`, videos to app preview sets by `--preview-type`, and `PRODUCT_PAGE_HEADER`, `APP_STORE_SEARCH_RESULTS`, and `APP_IPHONE_DUO` go through the asset library. The treatment's locale is created on the first upload.

:::note
A new treatment locale starts as a **copy of the original page's media**: App Store Connect fills it with the current version's screenshots and previews. Uploads are added after that copy, so delete the copied screenshots you are replacing (`media list` shows their IDs).
:::

## Review, start & stop

```bash
ascelerate experiments submit <bundle-id> "Screenshot order"
ascelerate experiments start <bundle-id> "Screenshot order"
ascelerate experiments stop <bundle-id> "Screenshot order"
```

A test with new media needs App Review before it can start (`info` says so). `submit` creates a review submission with just the test and submits it. If a draft submission with other items already exists for the platform (for example an app version), the test is added to it and goes to review with them through [`apps review submit`](apps.md#submit-for-review). Once the test is approved, `start` runs it; `stop` ends it. Results are shown in App Store Connect.

## Update & delete

```bash
ascelerate experiments update <bundle-id> "Screenshot order" --traffic 30
ascelerate experiments delete <bundle-id> "Screenshot order"
```

Change one thing per treatment (for example the first screenshot, or the icon) so the result tells you which change made the difference.
