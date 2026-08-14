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

## JSON output {#json-output}

Read commands support `--json` for machine-readable output, ready for `jq`, scripts, and AI agents:

```bash
ascelerate apps list --json
ascelerate apps info <bundle-id> --json
ascelerate apps versions <bundle-id> --json
ascelerate apps review preflight <bundle-id> --json
ascelerate apps review status <bundle-id> --json
ascelerate builds list --bundle-id <bundle-id> --json
ascelerate testflight builds <bundle-id> --json
ascelerate testflight status <bundle-id> --json
ascelerate reviews list <bundle-id> --json
ascelerate reviews info <review-id> --json
ascelerate iap list <bundle-id> --json
ascelerate iap info <bundle-id> <product-id> --json
ascelerate iap pricing show <bundle-id> <product-id> --json
ascelerate sub groups <bundle-id> --json
ascelerate sub list <bundle-id> --json
ascelerate sub info <bundle-id> <product-id> --json
ascelerate sub pricing show <bundle-id> <product-id> --json
ascelerate rate-limit --json
```

Output conventions:

- List commands emit a top-level JSON **array**; detail commands emit a single **object**.
- Enum values are raw API constants (`WAITING_FOR_REVIEW`, `IOS`), dates are ISO 8601, and every resource carries its `id`.
- Null fields are omitted, and empty results emit `[]` — never prose.
- Warnings become booleans: `iap info` and `sub info` report `"hasPricing": false` instead of a warning message.
- `--json` implies non-interactive mode: commands that would prompt (for example to disambiguate platforms) error out instead — pass `--platform` or other flags to disambiguate.
- Errors go to stderr, so stdout is always valid JSON.

Example — count unanswered reviews:

```bash
ascelerate reviews list <bundle-id> --json | jq '[.[] | select(.response == null)] | length'
```

## Exit codes

Commands exit with a non-zero status on failure, making them safe to use in scripts with `set -e` or `&&` chaining. The `preflight` command specifically exits non-zero when any check fails, so you can gate submissions on it:

```bash
ascelerate apps review preflight <bundle-id> && ascelerate apps review submit <bundle-id>
```

With `--json`, `preflight` emits a structured report (`{"passed": false, "checks": [{"group", "name", "passed", "detail"}]}`) while keeping the same exit-code behavior — ideal for CI gates that need to report *which* check failed.
