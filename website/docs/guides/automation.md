---
sidebar_position: 2
title: Automation & CI/CD
---

# Automation & CI/CD

Most commands that prompt for confirmation support `--yes` / `-y` to skip prompts, making them suitable for CI/CD pipelines and scripts.

```bash
ascelerate apps build attach-latest <bundle-id> --yes
ascelerate apps review submit <bundle-id> --yes
```

:::warning
When using `--yes` with provisioning commands, all required arguments must be provided explicitly — interactive mode is disabled.
:::

## Xcode signing in CI

Both `builds archive` and the archive-to-IPA export pass `-allowProvisioningUpdates` to `xcodebuild`. Without this, `xcodebuild` only uses locally cached provisioning profiles and won't fetch updated ones from the Developer Portal.

For CI environments without an Xcode GUI login, pass authentication flags:

```bash
ascelerate builds archive \
  --authentication-key-path /path/to/AuthKey.p8 \
  --authentication-key-id YOUR_KEY_ID \
  --authentication-key-issuer-id YOUR_ISSUER_ID
```

## Exit codes

Commands exit with a non-zero status on failure, making them safe to use in scripts with `set -e` or `&&` chaining. The `preflight` command specifically exits non-zero when any check fails, so you can gate submissions on it:

```bash
ascelerate apps review preflight <bundle-id> && ascelerate apps review submit <bundle-id>
```
