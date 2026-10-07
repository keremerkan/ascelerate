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

## Dry run {#dry-run}

Add `--dry-run` to try a command or a whole workflow without changing anything on App Store Connect. The option works anywhere on the command line, and setting `ASCELERATE_DRY_RUN=1` does the same. Reads go out as usual, so lookups and checks run against your real data, but every write is stopped before it is sent: ascelerate prints its method, path, and JSON body to stderr and reports that the request was not sent.

```bash
ascelerate apps localizations import <bundle-id> --file localizations.json --yes --dry-run
ascelerate run-workflow release.txt --yes --dry-run
ASCELERATE_DRY_RUN=1 ascelerate run-workflow release.txt --yes   # same, e.g. for a whole CI job
```

- A command stops at its first blocked write, or reports each blocked request as failed where it works through items one by one.
- `media upload` treats blocked writes as done and goes on, so every file's writes are shown; it ends with how many files would be uploaded.
- In `run-workflow`, a step whose writes were blocked doesn't stop the workflow, so a single run shows every step's writes. A step that relies on something an earlier step would have created, such as a new version or an uploaded build, can still fail.
- In a workflow file, `--dry-run` on a single step applies only to that step.
- `builds upload` skips the upload. `builds archive` and `builds validate` still run: they don't change anything on App Store Connect.

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
