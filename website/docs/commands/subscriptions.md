---
sidebar_position: 7
title: Subscriptions
---

# Subscriptions

## List and inspect

```bash
ascelerate sub groups <bundle-id>
ascelerate sub list <bundle-id>
ascelerate sub info <bundle-id> <product-id>
```

## Create, update, and delete subscriptions

```bash
ascelerate sub create <bundle-id> --name "Monthly" --product-id <product-id> --period ONE_MONTH --group-id <group-id>
ascelerate sub update <bundle-id> <product-id> --name "Monthly Plan"
ascelerate sub delete <bundle-id> <product-id>
```

## Subscription groups

```bash
ascelerate sub create-group <bundle-id> --name "Premium"
ascelerate sub update-group <bundle-id> --name "Premium Plus"
ascelerate sub delete-group <bundle-id>
```

## Submit for review

```bash
ascelerate sub submit <bundle-id> <product-id>
```

## Subscription localizations

```bash
ascelerate sub localizations view <bundle-id> <product-id>
ascelerate sub localizations export <bundle-id> <product-id>
ascelerate sub localizations import <bundle-id> <product-id> --file sub-de.json
```

## Group localizations

```bash
ascelerate sub group-localizations view <bundle-id>
ascelerate sub group-localizations export <bundle-id>
ascelerate sub group-localizations import <bundle-id> --file group-de.json
```

The import commands create missing locales automatically with confirmation, so you can add new languages without visiting App Store Connect.

## Pricing

Subscription pricing is per-territory. There is no auto-equalize concept like IAPs have — every territory you want to price needs its own record. The CLI either sets a single territory or fans the price out across all territories using Apple's local-currency tier equivalents.

```bash
# Show current per-territory prices (warns if none)
ascelerate sub pricing show <bundle-id> <product-id>

# List available tiers for a territory
ascelerate sub pricing tiers <bundle-id> <product-id> --territory USA

# Set the price for a single territory
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --territory USA

# Fan out a price across all territories (one POST per territory)
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --equalize-all-territories
```

### Price changes and existing subscribers

Apple treats price changes differently for existing subscribers depending on the direction. `sub pricing set` fetches the current price for each affected territory, classifies the change, and enforces the right behavior:

- **Decrease**: existing subscribers automatically move to the lower price. Interactive runs prompt with a warning. In `--yes` mode, you must add `--confirm-decrease` to acknowledge the revenue impact — plain `--yes` is not enough.
- **Increase**: you must explicitly choose how to handle existing subscribers. The command errors unless one of the following is set:
  - `--preserve-current` — grandfather existing subscribers at their old price
  - `--no-preserve-current` — push the new price to existing subscribers (after Apple's notification period)
- **New territory** (no existing price): no existing subscribers; flags optional.
- **Unchanged**: skipped silently.

The same rules apply aggregated across `--equalize-all-territories`. If any territory in the fan-out is an increase, the preserve flag is required for all of them. If any is a decrease in `--yes` mode, `--confirm-decrease` is required.

```bash
# Standard global price raise: $4.99 → $9.99 across all territories,
# grandfather existing subscribers at the old price
ascelerate sub pricing set myapp com.example.monthly \
  --price 9.99 --territory USA --equalize-all-territories \
  --preserve-current
```
