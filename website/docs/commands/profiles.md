---
sidebar_position: 11
title: Provisioning Profiles
---

# Provisioning Profiles

All profile commands support interactive mode — arguments are optional.

## List

```bash
ascelerate profiles list
ascelerate profiles list --type IOS_APP_STORE --state ACTIVE
```

## Details

```bash
ascelerate profiles info
ascelerate profiles info "My App Store Profile"
```

## Download

```bash
ascelerate profiles download
ascelerate profiles download "My App Store Profile" --output ./profiles/
```

## Create

```bash
# Fully interactive
ascelerate profiles create

# Non-interactive
ascelerate profiles create --name "My Profile" --type IOS_APP_STORE --bundle-id com.example.MyApp --certificates all
```

`--certificates all` uses all certs of the matching family (distribution, development, or Developer ID). You can also specify serial numbers: `--certificates ABC123,DEF456`.

## Delete

```bash
ascelerate profiles delete
ascelerate profiles delete "My App Store Profile"
```

## Reissue

Reissue profiles by deleting and recreating them with the latest certificates of the matching family:

```bash
# Interactive: pick from all profiles (shows status)
ascelerate profiles reissue

# Reissue a specific profile by name
ascelerate profiles reissue "My Profile"

# Reissue all invalid profiles
ascelerate profiles reissue --all-invalid

# Reissue all profiles regardless of state
ascelerate profiles reissue --all

# Reissue all, using all enabled devices for dev/adhoc
ascelerate profiles reissue --all --all-devices

# Use specific certificates instead of auto-detect
ascelerate profiles reissue --all --to-certs ABC123,DEF456
```
