---
sidebar_position: 1
title: Apps
---

# Apps

## List apps

```bash
asc apps list
```

## App details

```bash
asc apps info <bundle-id>
```

## List versions

```bash
asc apps versions <bundle-id>
```

## Create a version

```bash
asc apps create-version <bundle-id> <version-string>
asc apps create-version <bundle-id> 2.1.0 --platform ios --release-type manual
```

The `--release-type` is optional — omitting it uses the previous version's setting.

## Review

### Check review status

```bash
asc apps review status <bundle-id>
asc apps review status <bundle-id> --version 2.1.0
```

### Submit for review

```bash
asc apps review submit <bundle-id>
asc apps review submit <bundle-id> --version 2.1.0
```

When submitting, the command automatically detects IAPs and subscriptions with pending changes and offers to submit them alongside the app version.

### Resolve rejected items

After fixing issues and replying in Resolution Center:

```bash
asc apps review resolve-issues <bundle-id>
```

### Cancel submission

```bash
asc apps review cancel-submission <bundle-id>
```

## Preflight checks

Before submitting for review, run `preflight` to verify that all required fields are filled in across every locale:

```bash
# Check the latest editable version
asc apps review preflight <bundle-id>

# Check a specific version
asc apps review preflight <bundle-id> --version 2.1.0
```

The command checks version state, build attachment, and then goes through each locale to verify localization fields (description, what's new, keywords), app info fields (name, subtitle, privacy policy URL), and screenshots:

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

## Phased release

```bash
# View phased release status
asc apps phased-release <bundle-id>

# Enable phased release (starts inactive, activates when version goes live)
asc apps phased-release <bundle-id> --enable

# Pause, resume, or complete a phased release
asc apps phased-release <bundle-id> --pause
asc apps phased-release <bundle-id> --resume
asc apps phased-release <bundle-id> --complete

# Remove phased release entirely
asc apps phased-release <bundle-id> --disable
```

## Territory availability

```bash
# View which territories the app is available in
asc apps availability <bundle-id>

# Show full country names
asc apps availability <bundle-id> --verbose

# Make territories available or unavailable
asc apps availability <bundle-id> --add CHN,RUS
asc apps availability <bundle-id> --remove CHN
```

## Encryption declarations

```bash
# View existing encryption declarations
asc apps encryption <bundle-id>

# Create a new encryption declaration
asc apps encryption <bundle-id> --create --description "Uses HTTPS for API communication"
asc apps encryption <bundle-id> --create --description "Uses AES encryption" --proprietary-crypto --third-party-crypto
```

## EULA

```bash
# View the current EULA (or see that the standard Apple EULA applies)
asc apps eula <bundle-id>

# Set a custom EULA from a text file
asc apps eula <bundle-id> --file eula.txt

# Remove the custom EULA (reverts to standard Apple EULA)
asc apps eula <bundle-id> --delete
```
