---
sidebar_position: 8
title: Devices
---

# Devices

All device commands support interactive mode — arguments are optional. When omitted, the command prompts with numbered lists.

## List

```bash
asc devices list
asc devices list --platform IOS --status ENABLED
```

## Details

```bash
# Interactive picker
asc devices info

# By name or UDID
asc devices info "My iPhone"
```

## Register

```bash
# Interactive prompts
asc devices register

# Non-interactive
asc devices register --name "My iPhone" --udid 00008101-XXXXXXXXXXXX --platform IOS
```

## Update

```bash
# Interactive picker and update prompts
asc devices update

# Rename a device
asc devices update "My iPhone" --name "Work iPhone"

# Disable a device
asc devices update "My iPhone" --status DISABLED
```
