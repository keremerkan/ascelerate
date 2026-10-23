---
sidebar_position: 2
title: Setup
---

# Setup

## 1. Create an API Key

Go to [App Store Connect > Users and Access > Integrations > App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) and generate a new key. Download the `.p8` private key file.

## 2. Configure

```bash
ascelerate configure
```

This will prompt for your **Key ID**, **Issuer ID**, and the path to your `.p8` file. The private key is copied into `~/.ascelerate/` with strict file permissions (owner-only access).

The configuration is stored at `~/.ascelerate/config.json`:

```json
{
    "keyId": "KEY_ID",
    "issuerId": "ISSUER_ID",
    "privateKeyPath": "/Users/.../.ascelerate/AuthKey_XXXXXXXXXX.p8"
}
```

`configure` also prompts for an optional **vendor number** (App Store Connect → Payments and Financial Reports). It's only needed for [Sales and Finance reports](../commands/reports.md) and is stored as a `vendorNumber` field; you can skip it and add it later, or pass `--vendor-number` per command.

For [Apple Ads](../commands/ads.md), ascelerate needs separate credentials, which `ascelerate ads configure` sets up and stores in an `ads` section of the same file. Running `configure` again keeps them.

### A key for one run

To run a command with another key, for another team or in CI, set all three environment variables. They take precedence over `config.json` for that run, and the file stays as it is:

```bash
export ASCELERATE_KEY_ID=KEY_ID
export ASCELERATE_ISSUER_ID=ISSUER_ID
export ASCELERATE_PRIVATE_KEY_PATH=~/keys/AuthKey_KEY_ID.p8
ascelerate apps list
```

`builds archive` and `builds upload` also hand this key to `xcodebuild` (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`), so profiles are fetched with the key instead of the Apple ID signed in to Xcode. That needs a key allowed to manage certificates, identifiers and profiles. `ascelerate configure --show` says which key a run uses.

## 3. Verify

Run a quick command to verify everything is working:

```bash
ascelerate apps list
```

If your credentials are correct, you'll see a list of all your apps.

## Rate limit

The App Store Connect API has a rolling hourly quota of 3600 requests. You can check your current usage at any time:

```bash
ascelerate rate-limit
```

```
Hourly limit: 3600 requests (rolling window)
Used:         57
Remaining:    3543 (98%)
```
