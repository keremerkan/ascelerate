---
sidebar_position: 2
title: Builds
---

# Builds

## List builds

```bash
asc builds list
asc builds list --bundle-id <bundle-id>
asc builds list --bundle-id <bundle-id> --version 2.1.0
```

## Archive

```bash
asc builds archive
asc builds archive --scheme MyApp --output ./archives
```

The `archive` command auto-detects the `.xcworkspace` or `.xcodeproj` in the current directory and resolves the scheme if only one exists.

## Validate

```bash
asc builds validate MyApp.ipa
```

## Upload

```bash
asc builds upload MyApp.ipa
```

Accepts `.ipa`, `.pkg`, or `.xcarchive` files. When given an `.xcarchive`, it automatically exports to `.ipa` before uploading.

## Await processing

```bash
asc builds await-processing <bundle-id>
asc builds await-processing <bundle-id> --build-version 903
```

Recently uploaded builds may take a few minutes to appear in the API — the command polls with a progress indicator until the build is found and finishes processing.

## Attach a build to a version

```bash
# Interactively select and attach a build
asc apps build attach <bundle-id>
asc apps build attach <bundle-id> --version 2.1.0

# Attach the most recent build automatically
asc apps build attach-latest <bundle-id>

# Remove the attached build from a version
asc apps build detach <bundle-id>
```

`build attach-latest` prompts to wait if the latest build is still processing. With `--yes`, it waits automatically.
