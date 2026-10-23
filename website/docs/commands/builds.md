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

Without `--destination`, it archives for the scheme's platform (`generic/platform=macOS` for a macOS app). An app that builds for several platforms archives for iOS unless you pass `--destination`.

## Archives

```bash
ascelerate builds archives
ascelerate builds archives --bundle-id com.example.MyApp --platform macos --limit 1 --json
```

Lists the archives in Xcode's archive location (`~/Library/Developer/Xcode/Archives`), newest first, with their bundle ID, version, build number, platform and date. `--bundle-id` and `--platform` narrow the list; `--json` also gives each archive's path.

## Validate

```bash
ascelerate builds validate MyApp.ipa
```

## Upload

```bash
ascelerate builds upload MyApp.ipa
```

Accepts `.ipa`, `.pkg`, or `.xcarchive` files. When given an `.xcarchive`, it detects the archive's platform and automatically exports to `.ipa` (iOS-family) or `.pkg` (macOS) before uploading, passing the matching platform to altool.

```bash
ascelerate builds upload --latest --bundle-id com.example.MyApp --platform macos
```

With `--latest`, it uploads the newest archive in Xcode's archive location: the newest of an app with `--bundle-id`, and of one platform with `--platform` (an app sold on iOS and macOS under one bundle ID has archives of both).

An `.xcarchive` signed with App Store distribution profiles (a project signed manually) is exported with the installed App Store profiles of its app and its extensions, so Xcode creates none; other archives are exported with automatic signing. With a file, `--bundle-id` refuses one that holds another app, before anything is exported or sent.

### Upload through the App Store Connect API

```bash
ascelerate builds upload MyApp.ipa --api
ascelerate builds upload --latest --bundle-id com.example.MyApp --api
```

With `--api`, the build goes through the App Store Connect API's build uploads instead of altool, using the same API key as every other command. It takes an `.ipa` or a Mac `.pkg` (or an `.xcarchive`, exported first), reads the version and build number from the app inside, uploads the file in chunks with a progress bar on a terminal (one at a time; see [Upload chunks](../guides/automation.md#upload-chunks)), and then waits until App Store Connect has accepted the file. If Apple rejects it, the command fails with Apple's error codes and descriptions; warnings are printed after a successful upload. Processing then continues as usual (see [Await processing](#await-processing)).

altool stays the default for now.

### Progress for other tools

```bash
ascelerate builds archive --scheme MyApp --json-events
ascelerate builds upload MyApp.ipa --api --json-events
```

With `--json-events`, both commands print one JSON object per line on stdout (`step`, `archived` with the archive's path, `uploading`, `progress`, `processing`, and `finished` with Apple's warnings) and move their readable output, xcodebuild's included, to stderr, as `screenshot run --json-events` does. When archiving, xcodebuild then prints only warnings and errors.

## Upload history

```bash
ascelerate builds uploads <bundle-id>
ascelerate builds uploads <bundle-id> --platform macos --limit 20
ascelerate builds uploads <bundle-id> --delete-stale
```

Lists the app's recent uploads, whether they were made with altool, Xcode or `--api`, with their state (Awaiting Upload, Processing, Complete, Failed) and the errors and warnings Apple attached to them. Look here when an upload never turns into a build. Add `--json` for machine-readable output.

A connection that drops at the wrong moment can leave an upload record waiting for a file that will never arrive. `--api` uploads remove such records of the same build after they succeed, and `--delete-stale` removes any that are left: records still waiting for a file while another upload of the same build has moved on, or for more than a day. An upload still in progress is never removed.

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
