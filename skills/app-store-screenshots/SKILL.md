---
name: app-store-screenshots
description: Use when building App Store screenshot pages, generating exportable marketing screenshots for iOS apps or iPad apps, or creating programmatic screenshot generators with Next.js. Triggers on app store, screenshots, marketing assets, device mockup, app-store-screenshots.
---

# App Store Screenshots Generator

Builds a small web app in the project's `app-store-screenshots/` folder that turns the screenshots `ascelerate screenshot` captures into App Store marketing images: each screenshot in its real device frame on a designed background with a headline, in every language, at the sizes App Store Connect takes, exported in the folder layout `ascelerate apps media upload` uploads.

The instructions ship with the ascelerate command-line tool, so they always match its capture, framing and upload commands. In the project root, run:

```bash
ascelerate screenshot setup-prompt --design
```

and follow what it prints. It starts from what the project already has (the capture configuration, framing, an existing `app-store-screenshots/` folder and its exports), so running it again shows what's left.

- It needs ascelerate 0.25.0 or later: check with `ascelerate version`, update with `brew upgrade ascelerate`.
- If screenshot capture isn't set up yet, start with `ascelerate screenshot setup-prompt`, which sets up the UI tests, the screenshot helper and the configuration.
