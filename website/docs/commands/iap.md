---
sidebar_position: 6
title: In-App Purchases
---

# In-App Purchases

## List

```bash
ascelerate iap list <bundle-id>
ascelerate iap list <bundle-id> --type consumable --state approved
```

Filter values are case-insensitive. Types: `CONSUMABLE`, `NON_CONSUMABLE`, `NON_RENEWING_SUBSCRIPTION`. States: `APPROVED`, `MISSING_METADATA`, `READY_TO_SUBMIT`, `WAITING_FOR_REVIEW`, `IN_REVIEW`, etc.

## Details

```bash
ascelerate iap info <bundle-id> <product-id>
```

## Promoted purchases

```bash
ascelerate iap promoted <bundle-id>
```

## Create, update, and delete

```bash
ascelerate iap create <bundle-id> --name "100 Coins" --product-id <product-id> --type CONSUMABLE
ascelerate iap update <bundle-id> <product-id> --name "100 Gold Coins"
ascelerate iap delete <bundle-id> <product-id>
```

## Submit for review

```bash
ascelerate iap submit <bundle-id> <product-id>
```

## Localizations

```bash
ascelerate iap localizations view <bundle-id> <product-id>
ascelerate iap localizations export <bundle-id> <product-id>
ascelerate iap localizations import <bundle-id> <product-id> --file iap-de.json
```

The import command creates missing locales automatically with confirmation, so you can add new languages without visiting App Store Connect.

## Pricing

`iap pricing` reads and writes the price schedule. The schedule has a single base region — the territory Apple uses to auto-equalize prices in every other territory — plus zero or more per-territory manual overrides.

```bash
# Show the current price schedule (warns if none is set yet)
ascelerate iap pricing show <bundle-id> <product-id>

# List all price tiers available in a territory
ascelerate iap pricing tiers <bundle-id> <product-id> --territory USA
```

### Set the base region price

```bash
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99 --base-region GBR
```

`--base-region` defaults to the existing base region (or USA on a brand-new schedule). When the schedule has per-territory manual overrides, `set` shows an interactive menu offering to revert any of them to auto-equalize from the new base. To wipe all overrides without the prompt, pass `--remove-all-overrides`.

### Per-territory overrides

```bash
# Add or update a manual override
ascelerate iap pricing override <bundle-id> <product-id> --price 5.99 --territory FRA

# Drop the override (territory reverts to auto-equalize from base)
ascelerate iap pricing remove <bundle-id> <product-id> --territory FRA
```

`override` and `remove` only operate on non-base territories. To change the base region's price, use `set`.

When an IAP has no price schedule, `iap info` and `iap pricing show` both surface a warning, and the `apps review preflight` command flags it as a blocker for submission.
