---
title: "ASCelerate — A Swift CLI for App Store Connect"
description: "A command-line tool for building, archiving, and publishing apps to the App Store."
canonical: https://ascelerate.dev/
---

# ASCelerate

A Swift CLI for App Store Connect. Build, archive, and publish apps to the App Store — from Xcode archive to App Review submission. Manage versions, localizations, screenshots, provisioning, in-app purchases, subscriptions, and sales reports.

Open source: https://github.com/keremerkan/ascelerate

## Install

```bash
# Homebrew
brew tap keremerkan/tap
brew install ascelerate

# curl
curl -sSL https://raw.githubusercontent.com/keremerkan/ascelerate/main/install.sh | bash
```

## Features

- **Full Release Pipeline** — Archive, upload, manage versions and localizations, attach builds, run preflight checks, and submit for App Review, all from the terminal.
- **Provisioning Management** — Register devices, create certificates, manage bundle IDs and capabilities, create and reissue provisioning profiles. Most commands support interactive mode.
- **Screenshots & Media** — Capture screenshots from simulators with dark mode, localization, and status bar overrides. Frame screenshots with Apple device bezels. Upload and download screenshots and app previews with a simple folder structure.
- **In-App Purchases & Subscriptions** — List, create, update, and delete IAPs and subscriptions. Manage localizations and submit for review alongside your app version.
- **Reports & Analytics** — Download Sales, Finance, and App Analytics reports: units, downloads, and proceeds. Summarized in the terminal, or saved as raw data for your own analysis.
- **Workflows & Automation** — Chain commands into workflow files for repeatable release processes. Use `--yes` for fully unattended CI/CD execution.
- **AI-Ready** — Ships with a skill file that gives AI coding agents (Claude Code, Cursor, Windsurf, GitHub Copilot) full knowledge of all commands and workflows.

## Documentation

Docs are at https://ascelerate.dev/docs/getting-started/installation — every docs page is also available as markdown by appending `.md` to its URL or by requesting it with `Accept: text/markdown`. Start here:

- [Installation](https://ascelerate.dev/docs/getting-started/installation.md)
- [Setup](https://ascelerate.dev/docs/getting-started/setup.md)
- [Command reference](https://ascelerate.dev/docs/commands/apps.md)
- [Workflows](https://ascelerate.dev/docs/guides/workflows.md)
- [AI skill](https://ascelerate.dev/docs/guides/ai-skill.md)

Documentation is available in English, German, French, Japanese, and Turkish (e.g. `https://ascelerate.dev/de/docs/...`).

---

Maintained by [Kerem Erkan](https://keremerkan.dev). Not affiliated with Apple Inc. Apple, App Store, App Store Connect, Xcode, and macOS are trademarks of Apple Inc.
