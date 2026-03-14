---
sidebar_position: 2
title: Setup
---

# Setup

## 1. Create an API Key

Go to [App Store Connect > Users and Access > Integrations > App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) and generate a new key. Download the `.p8` private key file.

## 2. Configure

```bash
asc configure
```

This will prompt for your **Key ID**, **Issuer ID**, and the path to your `.p8` file. The private key is copied into `~/.asc/` with strict file permissions (owner-only access).

The configuration is stored at `~/.asc/config.json`:

```json
{
    "keyId": "KEY_ID",
    "issuerId": "ISSUER_ID",
    "privateKeyPath": "/Users/.../.asc/AuthKey_XXXXXXXXXX.p8"
}
```

## 3. Verify

Run a quick command to verify everything is working:

```bash
asc apps list
```

If your credentials are correct, you'll see a list of all your apps.

## Rate limit

The App Store Connect API has a rolling hourly quota of 3600 requests. You can check your current usage at any time:

```bash
asc rate-limit
```

```
Hourly limit: 3600 requests (rolling window)
Used:         57
Remaining:    3543 (98%)
```
