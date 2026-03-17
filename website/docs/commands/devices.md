---
sidebar_position: 8
title: Devices
---

# Devices

All device commands support interactive mode — arguments are optional. When omitted, the command prompts with numbered lists.

## List

```bash
ascelerate devices list
ascelerate devices list --platform IOS --status ENABLED
```

## Details

```bash
# Interactive picker
ascelerate devices info

# By name or UDID
ascelerate devices info "My iPhone"
```

## Register

```bash
# Interactive prompts
ascelerate devices register

# Non-interactive
ascelerate devices register --name "My iPhone" --udid 00008101-XXXXXXXXXXXX --platform IOS
```

## Update

```bash
# Interactive picker and update prompts
ascelerate devices update

# Rename a device
ascelerate devices update "My iPhone" --name "Work iPhone"

# Disable a device
ascelerate devices update "My iPhone" --status DISABLED
```
