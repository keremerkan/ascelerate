---
sidebar_position: 10
title: Bundle IDs
---

# Bundle IDs

All bundle ID commands support interactive mode — arguments are optional.

## List

```bash
ascelerate bundle-ids list
ascelerate bundle-ids list --platform IOS
```

## Details

```bash
# Interactive picker
ascelerate bundle-ids info

# By identifier
ascelerate bundle-ids info com.example.MyApp
```

## Register

```bash
# Interactive prompts
ascelerate bundle-ids register

# Non-interactive
ascelerate bundle-ids register --name "My App" --identifier com.example.MyApp --platform IOS
```

## Rename

```bash
ascelerate bundle-ids update
ascelerate bundle-ids update com.example.MyApp --name "My Renamed App"
```

The identifier itself is immutable — only the name can be changed.

## Delete

```bash
ascelerate bundle-ids delete
ascelerate bundle-ids delete com.example.MyApp
```

## Capabilities

### Enable

```bash
# Interactive pickers (shows only capabilities not already enabled)
ascelerate bundle-ids enable-capability

# Non-interactive
ascelerate bundle-ids enable-capability com.example.MyApp --type PUSH_NOTIFICATIONS
```

### Disable

```bash
# Picks from currently enabled capabilities
ascelerate bundle-ids disable-capability
ascelerate bundle-ids disable-capability com.example.MyApp
```

After enabling or disabling a capability, if provisioning profiles exist for that bundle ID, the command offers to regenerate them (required for changes to take effect).

:::note
Some capabilities (e.g. App Groups, iCloud, Associated Domains) require additional configuration in the [Apple Developer portal](https://developer.apple.com/account/resources) after enabling.
:::
