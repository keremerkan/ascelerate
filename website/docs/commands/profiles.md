---
sidebar_position: 11
title: Provisioning Profiles
---

# Provisioning Profiles

All profile commands support interactive mode — arguments are optional.

## List

```bash
asc profiles list
asc profiles list --type IOS_APP_STORE --state ACTIVE
```

## Details

```bash
asc profiles info
asc profiles info "My App Store Profile"
```

## Download

```bash
asc profiles download
asc profiles download "My App Store Profile" --output ./profiles/
```

## Create

```bash
# Fully interactive
asc profiles create

# Non-interactive
asc profiles create --name "My Profile" --type IOS_APP_STORE --bundle-id com.example.MyApp --certificates all
```

`--certificates all` uses all certs of the matching family (distribution, development, or Developer ID). You can also specify serial numbers: `--certificates ABC123,DEF456`.

## Delete

```bash
asc profiles delete
asc profiles delete "My App Store Profile"
```

## Reissue

Reissue profiles by deleting and recreating them with the latest certificates of the matching family:

```bash
# Interactive: pick from all profiles (shows status)
asc profiles reissue

# Reissue a specific profile by name
asc profiles reissue "My Profile"

# Reissue all invalid profiles
asc profiles reissue --all-invalid

# Reissue all profiles regardless of state
asc profiles reissue --all

# Reissue all, using all enabled devices for dev/adhoc
asc profiles reissue --all --all-devices

# Use specific certificates instead of auto-detect
asc profiles reissue --all --to-certs ABC123,DEF456
```
