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

## Availability

Each subscription has its own territory availability, independent of the app's. By default a subscription inherits its app's territories; once you call `sub availability` with changes, the subscription has an explicit list.

```bash
# View current per-subscription territories
ascelerate sub availability <bundle-id> <product-id>

# Edit the territory list (wholesale POST replaces the full list)
ascelerate sub availability <bundle-id> <product-id> --add CHN,RUS
ascelerate sub availability <bundle-id> <product-id> --remove ITA
ascelerate sub availability <bundle-id> <product-id> --available-in-new-territories true
```

## Introductory offers

Introductory offers target **new subscribers** — free trials and intro discounts.

```bash
ascelerate sub intro-offer list <bundle-id> <product-id>

# Free trial (no price needed; --periods + --duration set the trial length)
ascelerate sub intro-offer create <bundle-id> <product-id> \
  --mode FREE_TRIAL --duration ONE_WEEK --periods 1

# Pay-as-you-go discount (3 months at $0.99/mo, scoped to USA)
ascelerate sub intro-offer create <bundle-id> <product-id> \
  --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --territory USA --price 0.99

# Update only the end date (other fields require delete + recreate)
ascelerate sub intro-offer update <bundle-id> <product-id> <offer-id> --end-date 2026-12-31

ascelerate sub intro-offer delete <bundle-id> <product-id> <offer-id>
```

Modes: `FREE_TRIAL`, `PAY_AS_YOU_GO`, `PAY_UP_FRONT`. Without `--territory`, the offer applies globally; with `--territory`, it's scoped to that one territory. `--price` is required for the two paid modes and forbidden for `FREE_TRIAL`.

## Promotional offers

Promotional offers target **existing subscribers** — typically used for in-app upsell flows. The offer code (the `--code` value) must be embedded in a signed payload your server generates at runtime before clients can redeem it.

```bash
ascelerate sub promo-offer list <bundle-id> <product-id>
ascelerate sub promo-offer info <bundle-id> <product-id> <offer-id>

# Create — same single-territory or --equalize-all-territories pattern
ascelerate sub promo-offer create <bundle-id> <product-id> \
  --name "Loyalty 50%" --code LOYALTY50 \
  --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --price 4.99 --territory USA --equalize-all-territories

# Update only prices (other fields require delete + recreate)
ascelerate sub promo-offer update <bundle-id> <product-id> <offer-id> \
  --price 5.99 --equalize-all-territories

ascelerate sub promo-offer delete <bundle-id> <product-id> <offer-id>
```

## Offer codes

Offer codes are redeemable codes for subscriptions, with two flavors:

- **One-time-use codes**: Apple generates N unique codes in a batch (asynchronously). Each can only be redeemed once.
- **Custom codes**: developer-supplied string redeemable N times.

```bash
ascelerate sub offer-code list <bundle-id> <product-id>
ascelerate sub offer-code info <bundle-id> <product-id> <offer-code-id>

# Create an offer code (with all the offer-style attributes)
ascelerate sub offer-code create <bundle-id> <product-id> \
  --name "Launch Free Month" \
  --eligibility NEW \
  --offer-eligibility STACK_WITH_INTRO_OFFERS \
  --mode FREE_TRIAL --duration ONE_MONTH --periods 1 \
  --price 0 --territory USA --equalize-all-territories

ascelerate sub offer-code toggle <bundle-id> <product-id> <offer-code-id> --active true

# Generate one-time-use codes (async)
ascelerate sub offer-code gen-codes <bundle-id> <product-id> <offer-code-id> \
  --count 500 --expires 2026-12-31

# Fetch the actual code values once generation completes
ascelerate sub offer-code view-codes <one-time-use-batch-id> --output codes.txt

# Add a developer-supplied custom code
ascelerate sub offer-code add-custom-codes <bundle-id> <product-id> <offer-code-id> \
  --code SUBPROMO --count 1000 --expires 2026-12-31
```

Customer eligibilities for subscription offer codes: `NEW`, `EXISTING`, `EXPIRED`. Offer eligibility: `STACK_WITH_INTRO_OFFERS` or `REPLACE_INTRO_OFFERS`.

## Submit subscription group for review

Subscription groups are reviewed alongside the next app version. `sub submit-group` is the group-level mirror of `sub submit`.

```bash
ascelerate sub submit-group <bundle-id>
```

## Promotional images

Upload promotional artwork shown alongside the subscription in the App Store.

```bash
ascelerate sub images list <bundle-id> <product-id>
ascelerate sub images upload <bundle-id> <product-id> ./hero.png
ascelerate sub images delete <bundle-id> <product-id> <image-id>
```

## App Review screenshot

Each subscription can have at most one App Review screenshot. Uploading replaces any existing one.

```bash
ascelerate sub review-screenshot view <bundle-id> <product-id>
ascelerate sub review-screenshot upload <bundle-id> <product-id> ./review.png
ascelerate sub review-screenshot delete <bundle-id> <product-id>
```

Image and screenshot uploads use Apple's 3-step file upload flow (reserve → PUT chunks → commit with MD5). The CLI handles all three steps in a single `upload` call.

## Win-back offers (not yet implemented)

Win-back offers (offers for churned subscribers) are intentionally not implemented yet. The `WinBackOfferPriceInlineCreate` type in our `asc-swift` dependency is missing the `territory` and `subscriptionPricePoint` relationships the API requires, so we can't construct a valid create request. Will revisit once the upstream library is updated.
