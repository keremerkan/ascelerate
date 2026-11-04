---
sidebar_position: 7
title: Sandbox Testers
---

# Sandbox Testers

The Apple Accounts that buy in-app purchases and subscriptions in the sandbox. A tester is named by its **Apple Account** (email) or ID. Creating and deleting testers is done in App Store Connect (Users and Access > Sandbox); the API doesn't offer it.

## List

```bash
ascelerate sandbox-testers
ascelerate sandbox-testers --json
```

Each tester's Apple Account, name, storefront, how fast its subscriptions renew, whether its purchases are interrupted, and whether it can use Apple Pay.

## Update

```bash
ascelerate sandbox-testers update tester@example.com --renewal-rate 3m
ascelerate sandbox-testers update tester@example.com --territory DEU --interrupt-purchases true
```

`--territory` sets the storefront (a three-letter territory code). `--interrupt-purchases` stops purchases for an extra step, such as accepting terms or updating payment. `--renewal-rate` sets how fast a monthly subscription renews for the tester: `1h`, `30m`, `15m`, `5m` or `3m` (other durations renew in proportion). The command lists what would change and asks first.

## Clear Purchase History

```bash
ascelerate sandbox-testers clear-history tester@example.com other@example.com
ascelerate sandbox-testers clear-history --all
```

Forgets the testers' in-app purchases and subscriptions, so they can be bought again from the start. It asks first.
