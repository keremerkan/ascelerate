---
sidebar_position: 2
title: Builds
---

# Builds

## List builds

```bash
ascelerate builds list
ascelerate builds list --bundle-id <bundle-id>
ascelerate builds list --bundle-id <bundle-id> --version 2.1.0
ascelerate builds list --bundle-id <bundle-id> --platform macos
```

The output shows each build's app version, platform, build number, processing state, and upload date. Add `--json` for machine-readable output ([conventions](../guides/automation.md#json-output)).

## Archive

```bash
ascelerate builds archive
ascelerate builds archive --scheme MyApp --output ./archives
```

The `archive` command auto-detects the `.xcworkspace` or `.xcodeproj` in the current directory and resolves the scheme if only one exists.

## Validate

```bash
ascelerate builds validate MyApp.ipa
```

## Upload

```bash
ascelerate builds upload MyApp.ipa
```

Accepts `.ipa`, `.pkg`, or `.xcarchive` files. When given an `.xcarchive`, it detects the archive's platform and automatically exports to `.ipa` (iOS-family) or `.pkg` (macOS) before uploading, passing the matching platform to altool.

## Await processing

```bash
ascelerate builds await-processing <bundle-id>
ascelerate builds await-processing <bundle-id> --build-version 903
ascelerate builds await-processing <bundle-id> --build-version 903 --platform macos
```

Recently uploaded builds may take a few minutes to appear in the API — the command polls with a progress indicator until the build is found and finishes processing.

## Attach a build to a version

```bash
# Interactively select and attach a build
ascelerate apps build attach <bundle-id>
ascelerate apps build attach <bundle-id> --version 2.1.0

# Attach the most recent build automatically
ascelerate apps build attach-latest <bundle-id>
ascelerate apps build attach-latest <bundle-id> --platform macos

# Remove the attached build from a version
ascelerate apps build detach <bundle-id>
```

`build attach-latest` prompts to wait if the latest build is still processing. With `--yes`, it waits automatically.

Build lookups are platform-aware: on universal-purchase apps, iOS and macOS builds can share build numbers, so the attach commands only consider builds matching the target version's platform.
