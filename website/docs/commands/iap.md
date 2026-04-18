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

`iap pricing` reads and writes the price schedule. The schedule has a single base territory — the territory Apple uses to auto-equalize prices in every other territory — plus zero or more per-territory manual overrides.

```bash
# Show the current price schedule (warns if none is set yet)
ascelerate iap pricing show <bundle-id> <product-id>

# List all price tiers available in a territory
ascelerate iap pricing tiers <bundle-id> <product-id> --territory USA
```

### Set the base territory price

```bash
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99 --base-territory GBR
```

`--base-territory` defaults to the existing base territory (or USA on a brand-new schedule). When the schedule has per-territory manual overrides, `set` shows an interactive menu offering to revert any of them to auto-equalize from the new base. To wipe all overrides without the prompt, pass `--remove-all-overrides`.

### Per-territory overrides

```bash
# Add or update a manual override
ascelerate iap pricing override <bundle-id> <product-id> --price 5.99 --territory FRA

# Drop the override (territory reverts to auto-equalize from base)
ascelerate iap pricing remove <bundle-id> <product-id> --territory FRA
```

`override` and `remove` only operate on non-base territories. To change the base territory's price, use `set`.

When an IAP has no price schedule, `iap info` and `iap pricing show` both surface a warning, and the `apps review preflight` command flags it as a blocker for submission.

## Availability

Each IAP has its own territory availability, independent of the app's. By default an IAP inherits its app's territories; once you call `iap availability` with changes, the IAP has an explicit list.

```bash
# View current per-IAP territories
ascelerate iap availability <bundle-id> <product-id>

# Edit the territory list (wholesale POST replaces the full list)
ascelerate iap availability <bundle-id> <product-id> --add CHN,RUS
ascelerate iap availability <bundle-id> <product-id> --remove ITA
ascelerate iap availability <bundle-id> <product-id> --available-in-new-territories true
```

## Offer codes

Offer codes are redeemable codes that unlock a one-time discount on an IAP. They come in two flavors, managed under the same offer code resource:

- **One-time-use codes**: Apple generates N unique codes in a batch. Each can only be redeemed once. Codes are generated asynchronously.
- **Custom codes**: developer-supplied string (e.g. `PROMO2026`) redeemable N times.

```bash
# List all offer codes on an IAP
ascelerate iap offer-code list <bundle-id> <product-id>

# Show details + code batch counts for one offer code
ascelerate iap offer-code info <bundle-id> <product-id> <offer-code-id>

# Create an offer code with a discounted price (auto-equalized across all territories)
ascelerate iap offer-code create <bundle-id> <product-id> \
  --name "Launch Promo" \
  --eligibility NON_SPENDER,ACTIVE_SPENDER \
  --price 0.99 --territory USA --equalize-all-territories

# Activate or deactivate
ascelerate iap offer-code toggle <bundle-id> <product-id> <offer-code-id> --active true

# Generate a batch of one-time-use codes (codes are generated asynchronously)
ascelerate iap offer-code gen-codes <bundle-id> <product-id> <offer-code-id> \
  --count 100 --expires 2026-12-31

# Fetch the actual code values after generation completes
ascelerate iap offer-code view-codes <one-time-use-batch-id> --output codes.txt

# Add a developer-supplied custom code
ascelerate iap offer-code add-custom-codes <bundle-id> <product-id> <offer-code-id> \
  --code PROMO2026 --count 1000 --expires 2026-12-31
```

Customer eligibilities for IAP offer codes: `NON_SPENDER`, `ACTIVE_SPENDER`, `CHURNED_SPENDER`.

## Promotional images

Upload promotional artwork shown alongside the IAP in the App Store.

```bash
ascelerate iap images list <bundle-id> <product-id>
ascelerate iap images upload <bundle-id> <product-id> ./hero.png
ascelerate iap images delete <bundle-id> <product-id> <image-id>
```

Uploads use Apple's 3-step flow: reserve with `fileSize` + `fileName`, PUT file chunks to presigned URLs, then PATCH with the file MD5 to commit. The CLI handles all three steps in a single `upload` call.

## App Review screenshot

Each IAP can have at most one App Review screenshot (shown to Apple's reviewers). Uploading replaces any existing one.

```bash
ascelerate iap review-screenshot view <bundle-id> <product-id>
ascelerate iap review-screenshot upload <bundle-id> <product-id> ./review.png
ascelerate iap review-screenshot delete <bundle-id> <product-id>
```
