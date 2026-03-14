---
sidebar_position: 6
title: In-App Purchases
---

# In-App Purchases

## List

```bash
asc iap list <bundle-id>
asc iap list <bundle-id> --type consumable --state approved
```

Filter values are case-insensitive. Types: `CONSUMABLE`, `NON_CONSUMABLE`, `NON_RENEWING_SUBSCRIPTION`. States: `APPROVED`, `MISSING_METADATA`, `READY_TO_SUBMIT`, `WAITING_FOR_REVIEW`, `IN_REVIEW`, etc.

## Details

```bash
asc iap info <bundle-id> <product-id>
```

## Promoted purchases

```bash
asc iap promoted <bundle-id>
```

## Create, update, and delete

```bash
asc iap create <bundle-id> --name "100 Coins" --product-id <product-id> --type CONSUMABLE
asc iap update <bundle-id> <product-id> --name "100 Gold Coins"
asc iap delete <bundle-id> <product-id>
```

## Submit for review

```bash
asc iap submit <bundle-id> <product-id>
```

## Localizations

```bash
asc iap localizations view <bundle-id> <product-id>
asc iap localizations export <bundle-id> <product-id>
asc iap localizations import <bundle-id> <product-id> --file iap-de.json
```

The import command creates missing locales automatically with confirmation, so you can add new languages without visiting App Store Connect.
