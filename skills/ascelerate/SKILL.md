---
name: ascelerate
description: Use when working with App Store Connect tasks — app submissions, localizations, screenshots, builds, provisioning, in-app purchases, subscriptions, or release workflows — and with Apple Ads (Search Ads) — campaigns, keywords, bids, budgets, search terms, ad performance reports, keyword research and popularity. Triggers on App Store, App Store Connect, asc, ascelerate, app review, provisioning profiles, screenshots, localizations, IAP, subscriptions, Apple Ads, Search Ads, ad campaigns, keywords, CPT, CPI, ASO.
---

# ascelerate

A command-line tool for the App Store Connect API. Use `ascelerate` for all App Store Connect operations instead of the web interface.

## Quick Reference

### App aliases

Use aliases instead of full bundle IDs:

```bash
ascelerate alias add myapp    # Interactive app picker
ascelerate apps info myapp    # Use alias anywhere
```

Any argument without a dot is treated as an alias. Real bundle IDs work unchanged.

### JSON output

Read commands support `--json` for machine-readable output — prefer it over parsing tables:

```bash
ascelerate apps list --json
ascelerate apps info <app> --json
ascelerate apps versions <app> --json
ascelerate apps review preflight <app> --json     # {passed, checks: [{group?, name, passed, detail, skipped?}]}; exits non-zero on failures; skipped = product the developer removed from sale (counts as passed)
ascelerate apps review status <app> --json        # submissions incl. per-item states
ascelerate builds list --bundle-id <app> --json
ascelerate testflight builds <app> --json
ascelerate testflight status <app> --json
ascelerate reviews list <app> --json              # includes full review bodies + developer responses (no per-review info calls needed)
ascelerate reviews info <review-id> --json
ascelerate iap list <app> --json
ascelerate iap info <app> <product-id> --json     # includes "hasPricing" boolean
ascelerate iap pricing show <app> <product-id> --json
ascelerate sub groups <app> --json
ascelerate sub list <app> --json
ascelerate sub info <app> <product-id> --json     # includes "hasPricing" boolean
ascelerate sub pricing show <app> <product-id> --json
ascelerate rate-limit --json
ascelerate ads campaigns list --json              # every ads read command takes --json; see "Apple Ads" below
ascelerate ads reports campaigns|keywords|search-terms --json
```

Conventions: list commands emit a top-level JSON array, detail commands a single object; raw API enum values (`WAITING_FOR_REVIEW`, `IOS`); ISO 8601 dates; resource `id` always included; null fields omitted; empty results emit `[]`. `--json` implies non-interactive — ambiguity errors instead of prompting (disambiguate with `--platform` etc.). Errors go to stderr, so stdout is always valid JSON.

### Version management

```bash
ascelerate apps create-version <app> <version>
ascelerate apps copyright <app> --set "2026 Your Name"   # View/update version copyright
ascelerate apps build attach-latest <app>
ascelerate apps build attach <app>        # Interactive build picker
ascelerate apps build detach <app>
```

`--version` targets a specific version. Without it, commands prefer the latest editable version (Prepare for Submission or Waiting for Review).

Universal-purchase apps (one app record, several platforms) can hold the same version per platform. Version-scoped commands (localizations, media, build attach, review, `builds list`/`await-processing`) accept `--platform ios|macos|tvos|visionos` to disambiguate; without it they prompt when ambiguous. `apps create-version` and `apps review submit` default to iOS — pass `--platform macos` for the Mac version/submission.

### Localizations

Two layers: **version-level** (description, what's new, keywords) and **app-level** (name, subtitle, privacy URL).

```bash
# Version localizations
ascelerate apps localizations export <app>
ascelerate apps localizations import <app> --file localizations.json

# App info localizations
ascelerate apps app-info export <app>
ascelerate apps app-info import <app> --file app-infos.json
```

#### Version localization JSON format

```json
{
  "en-US": {
    "description": "App description.",
    "whatsNew": "- Bug fixes",
    "keywords": "keyword1,keyword2",
    "promotionalText": "Promo text",
    "marketingURL": "https://example.com",
    "supportURL": "https://example.com/support"
  }
}
```

#### App info localization JSON format

```json
{
  "en-US": {
    "name": "My App",
    "subtitle": "Best app ever",
    "privacyPolicyURL": "https://example.com/privacy",
    "privacyChoicesURL": "https://example.com/choices"
  }
}
```

Only fields present in the JSON get updated — omitted fields are left unchanged. Import commands create missing locales automatically with confirmation.

### Screenshots & App Previews

```bash
ascelerate apps media download <app>
ascelerate apps media download <app> --locale en-US,tr          # Only some locales
ascelerate apps media upload <app> media/
ascelerate apps media upload <app> screenshots.zip            # Zip/tar/tar.gz support
ascelerate apps media upload <app>                            # Interactive picker
ascelerate apps media upload <app> media/ --replace           # Replace existing
ascelerate apps media verify <app>                            # Check processing status
ascelerate apps media verify <app> media/                     # Retry stuck items (incl. screenshots whose asset library placement is stuck processing, which App Review refuses with ASSET_IN_POST_PROCESSING)
ascelerate apps media prune <app> media/                      # Delete server sets with no matching local folder
ascelerate apps media remove <app> PRODUCT_PAGE_HEADER [--locale en-US,tr]   # Remove a header/search image or video, or Duo screenshots (APP_IPHONE_DUO; --previews for Duo previews)
ascelerate apps media library <app> [--only APP_IPHONE_DUO,PRODUCT_PAGE_HEADER,APP_STORE_SEARCH_RESULTS] [--delete-unused]  # Count library images, list (and delete) unused never-reviewed ones; --only also takes screenshot display types (APP_IPHONE_67, ...) and UNFINISHED_UPLOADS; images <1 h old are kept
```

iPhone Duo screenshots go in an `APP_IPHONE_DUO` folder: uploaded to the app's asset library and placed on the version localization (no screenshot set exists for them). Accepted sizes: 2853×2007 / 2007×2853 (unfolded) or 2034×1398 / 1398×2034 (cover). `media verify` lists them (file name + state) and, given the folder, flags locales whose Duo files or order differ (fix: `media upload --replace`); a file that still fails after retries makes `media upload` re-place that locale's Duo set at the end of the run. `media download` skips them; `media prune` never deletes them. Product page header and search results images work the same way: `PRODUCT_PAGE_HEADER/` (PNG 3840×1646 or 5244×2950) and `APP_STORE_SEARCH_RESULTS/` (3:2 JPG/PNG from 1920×1280 to 3840×2560, or PNG 5244×2950), one image per locale shown on every device (not per display type), any platform; an upload replaces the current image. Each slot takes a video instead too (header 3840×1646, search 3:2; 5–30 s at 30/60 fps), and `APP_IPHONE_DUO/` takes app previews (1920×886 or 886×1920, 15–30 s, 23–30 fps, with audio). Custom product pages: `product-pages media upload --display-type PRODUCT_PAGE_HEADER|APP_STORE_SEARCH_RESULTS|APP_IPHONE_DUO`. `media download [--locale X]` saves library images; library videos have no download URL. Removing a placement (`media remove`, `--replace`, replacing a header/search image) also deletes its library image when no placement anywhere uses it and it was never reviewed; versions share images and old versions keep theirs, so never delete library images by other means. Classic set `--replace` cleans up the same way (it reads the set's library images before clearing it and keeps any still placed elsewhere, e.g. on the live version). Leftovers from earlier runs: `media library --delete-unused`.

#### Folder structure

```
media/
├── en-US/
│   ├── APP_IPHONE_67/
│   │   ├── 01_home.png
│   │   └── 02_settings.png
│   └── APP_IPAD_PRO_3GEN_129/
│       └── 01_home.png
└── de-DE/
    └── APP_IPHONE_67/
        └── 01_home.png
```

Required display types: `APP_IPHONE_67` (iPhone) and `APP_IPAD_PRO_3GEN_129` (iPad). Files sorted alphabetically = upload order. Images become screenshots, videos become previews.

### Review submission

```bash
ascelerate apps review preflight <app>           # Pre-submission checks
ascelerate apps review submit <app>              # Submit (offers to include IAPs/subs)
ascelerate apps review status <app>              # Check status (active submissions list app version + IAP/sub items)
ascelerate apps review resolve-issues <app>      # After fixing rejection
ascelerate apps review cancel-submission <app>   # Cancel active review
ascelerate apps release <app>                    # Release an approved version in Pending Developer Release
ascelerate apps review info <app>                # View App Review Information
ascelerate apps review info <app> [--contact-email X] [--demo-account-name X] [--demo-account-password X] [--demo-account-required true|false] [--notes X]  # Update (per-version upsert; omitted fields unchanged)
ascelerate apps review attachment list <app> [--version X]
ascelerate apps review attachment upload <app> [--version X] <file>   # reserve/PUT/commit; any file type
ascelerate apps review attachment delete <attachment-id>
```

`preflight` checks build attachment, localizations, app info, screenshots across all locales, plus IAP/subscription state and pricing (warns when an IAP has no price schedule or a sub has no prices; products in Developer Removed from Sale are skipped, not failed). Exits non-zero on failures. With `--json` it emits the structured check list (same exit code) — ideal as a CI gate.

When submitting, the tool detects IAPs and subscriptions and offers to submit them alongside the app version.

### In-app purchases

```bash
ascelerate iap list <app>
ascelerate iap info <app> <product-id>                   # warns if no price schedule set

# Promoted purchases (IAPs or subscriptions, shown on the App Store product page)
ascelerate iap promoted list <app>
ascelerate iap promoted add <app> <product-id> [--visible-for-all true|false] [--enabled true|false]
ascelerate iap promoted remove <app> <product-id>
ascelerate iap promoted reorder <app> <product-id,product-id,...>   # omitted ones appended after
ascelerate iap promoted toggle <app> <product-id> --enabled true|false

ascelerate iap create <app> --name "Name" --product-id <id> --type CONSUMABLE
ascelerate iap update <app> <product-id> --name "New Name"
ascelerate iap delete <app> <product-id>
ascelerate iap submit <app> <product-id>                       # needs a pending version (any edit since last approval)

# Localizations
ascelerate iap localizations view <app> <product-id>
ascelerate iap localizations export <app> <product-id>
ascelerate iap localizations import <app> <product-id> --file iap-de.json

# Pricing — wholesale schedule POST is read-modify-write, preserves overrides
ascelerate iap pricing show <app> <product-id>
ascelerate iap pricing tiers <app> <product-id> --territory USA
ascelerate iap pricing set <app> <product-id> --price 4.99 [--base-territory USA] [--remove-all-overrides]
ascelerate iap pricing override <app> <product-id> --price 5.99 --territory FRA
ascelerate iap pricing remove <app> <product-id> --territory FRA   # revert to auto-equalize
ascelerate iap pricing export <app> <product-id> [--output prices.json]
ascelerate iap pricing import <app> <product-id> [--file prices.json]   # copy schedule from another product/app

# Per-IAP territory availability (independent of app's)
ascelerate iap availability <app> <product-id> [--add CHN,RUS] [--remove ITA] [--available-in-new-territories true]

# Offer codes (one-time-use batches + custom codes)
ascelerate iap offer-code list <app> <product-id>
ascelerate iap offer-code info <app> <product-id> <offer-code-id>
ascelerate iap offer-code create <app> <product-id> --name X --eligibility NON_SPENDER,ACTIVE_SPENDER --price 0.99 [--territory USA] [--equalize-all-territories]
ascelerate iap offer-code toggle <app> <product-id> <offer-code-id> --active true
ascelerate iap offer-code gen-codes <app> <product-id> <offer-code-id> --count 100 --expires 2026-12-31
ascelerate iap offer-code add-custom-codes <app> <product-id> <offer-code-id> --code PROMO2026 --count 1000 --expires 2026-12-31
ascelerate iap offer-code view-codes <one-time-use-batch-id> [--output codes.txt]   # async; may need retry

# Promotional images + App Review screenshot (Apple's 3-step file upload flow)
ascelerate iap images list/upload/delete <app> <product-id> [<file>|<image-id>]
ascelerate iap review-screenshot view/upload/delete <app> <product-id> [<file>]   # one screenshot per IAP
```

IAP types: `CONSUMABLE`, `NON_CONSUMABLE`, `NON_RENEWING_SUBSCRIPTION`. Offer code eligibilities: `NON_SPENDER`, `ACTIVE_SPENDER`, `CHURNED_SPENDER`.

Pricing notes:
- `set` preserves per-territory overrides by default; interactive menu offers to drop them, or `--remove-all-overrides` for non-interactive wipe.
- `override` and `remove` only operate on non-base territories.
- `export`/`import` copy the schedule between products (any app): a JSON file of customer prices keyed by territory, matched to the target's own tiers by price on import. Import replaces the schedule wholesale — territories not in the file revert to auto-equalize; a schedule already matching the file is a no-op.
- One-time-use offer codes generate asynchronously — `gen-codes` returns a batch ID; use `view-codes <batch-id>` to fetch values once ready.

### Subscriptions

```bash
ascelerate sub list <app>
ascelerate sub groups <app>
ascelerate sub info <app> <product-id>                         # warns if no prices set
ascelerate sub create <app> --name "Monthly" --product-id <id> --period ONE_MONTH --group-id <gid>
ascelerate sub update <app> <product-id> --name "New Name"
ascelerate sub delete <app> <product-id>
ascelerate sub submit <app> <product-id>                       # needs a pending version (any edit since last approval)
ascelerate sub submit-group <app>                              # submit whole group for review

# Subscription localizations
ascelerate sub localizations export <app> <product-id>
ascelerate sub localizations import <app> <product-id> --file sub-de.json

# Group management
ascelerate sub create-group <app> --name "Premium"
ascelerate sub update-group <app> --name "Premium Plus"
ascelerate sub delete-group <app>

# Group localizations
ascelerate sub group-localizations export <app>
ascelerate sub group-localizations import <app> --file group-de.json

# Pricing — per-territory; --equalize-all-territories fans out via Apple's equalizations
ascelerate sub pricing show <app> <product-id>
ascelerate sub pricing tiers <app> <product-id> --territory USA
ascelerate sub pricing set <app> <product-id> --price 4.99 [--territory USA] [--equalize-all-territories]
  [--preserve-current | --no-preserve-current]   # required on price increases
  [--confirm-decrease]                           # required on decreases in --yes mode
ascelerate sub pricing export <app> <product-id> [--output prices.json]
ascelerate sub pricing import <app> <product-id> [--file prices.json]   # copy prices from another product/app; same safety flags as set

# Per-subscription territory availability (independent of app's)
ascelerate sub availability <app> <product-id> [--add CHN,RUS] [--remove ITA] [--available-in-new-territories true] [--plan upfront|monthly]   # monthly = "Monthly with 12-Month Commitment" plan (annual subs; not in USA/SGP); default upfront

# Introductory offers (free trials + intro discounts for NEW subscribers)
ascelerate sub intro-offer list <app> <product-id>
ascelerate sub intro-offer create <app> <product-id> --mode FREE_TRIAL --duration ONE_WEEK --periods 1
ascelerate sub intro-offer create <app> <product-id> --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 --territory USA --price 0.99
ascelerate sub intro-offer update <app> <product-id> <offer-id> --end-date 2026-12-31
ascelerate sub intro-offer delete <app> <product-id> <offer-id>

# Promotional offers (server-signed offers for EXISTING subscribers)
ascelerate sub promo-offer list/info/delete <app> <product-id> [<offer-id>]
ascelerate sub promo-offer create <app> <product-id> --name X --code LOYALTY50 --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 --price 4.99 --territory USA --equalize-all-territories
ascelerate sub promo-offer update <app> <product-id> <offer-id> --price 5.99 --equalize-all-territories   # only prices can change

# Offer codes (one-time-use batches + custom codes)
ascelerate sub offer-code list/info <app> <product-id> [<offer-code-id>]
ascelerate sub offer-code create <app> <product-id> --name X --eligibility NEW --offer-eligibility STACK_WITH_INTRO_OFFERS --mode FREE_TRIAL --duration ONE_MONTH --periods 1 --price 0 --territory USA --equalize-all-territories
ascelerate sub offer-code toggle <app> <product-id> <offer-code-id> --active true
ascelerate sub offer-code gen-codes <app> <product-id> <offer-code-id> --count 500 --expires 2026-12-31
ascelerate sub offer-code add-custom-codes <app> <product-id> <offer-code-id> --code SUBPROMO --count 1000 --expires 2026-12-31
ascelerate sub offer-code view-codes <one-time-use-batch-id> [--output codes.txt]

# Promotional images + App Review screenshot (Apple's 3-step file upload flow)
ascelerate sub images list/upload/delete <app> <product-id> [<file>|<image-id>]
ascelerate sub review-screenshot view/upload/delete <app> <product-id> [<file>]   # one screenshot per sub
```

Subscription pricing safety:
- **Price increase** in any territory requires `--preserve-current` (grandfather existing subs at old price) OR `--no-preserve-current` (push new price after Apple's notification period). Errors if neither set.
- **Price decrease** prompts interactively; under `--yes`, requires `--confirm-decrease` to acknowledge revenue impact.
- **`--equalize-all-territories`** aggregates the analysis: if any territory in the fan-out is an increase, the preserve flag is required for all.
- **`import`** applies the same aggregated rules; it only touches territories listed in the file and skips ones already at the listed price.
- Transient ASC errors (429/5xx) during multi-territory writes are retried automatically (in-place backoff + end-of-run sweep). Remaining failures are listed with a re-run hint and exit non-zero — re-running retries only the failed territories.

Offer code eligibilities for subs: `NEW`, `EXISTING`, `EXPIRED`. Offer eligibility: `STACK_WITH_INTRO_OFFERS` or `REPLACE_INTRO_OFFERS`. Modes: `FREE_TRIAL`, `PAY_AS_YOU_GO`, `PAY_UP_FRONT`.

NOT YET IMPLEMENTED: `sub win-back-offer` is blocked by Apple's API spec (win-back offer price entries have no territory or price point relationships). Custom product page search-keyword linkages are blocked the same way (the spec's `AppKeyword` exposes no keyword text). `iap hosted-content` is intentionally skipped.

### Customer reviews

```bash
ascelerate reviews list <app> [--rating 1-5] [--territory USA] [--sort recent|oldest|critical|best] [--unanswered] [--limit 50]
ascelerate reviews info <review-id>                       # full text + developer response
ascelerate reviews respond <review-id> --body "..."       # publish/replace developer response
ascelerate reviews delete-response <review-id>
```

Reviews are read-only; only the developer response is writable. Review IDs come from `reviews list`. Use `reviews list --json` to get full review bodies and existing developer responses in one call — no per-review `info` calls needed.

The App Store Connect API does **not** expose aggregate rating counts or the star-rating average/histogram — only individual reviews (above). For download/unit numbers and revenue, use `reports` (below).

### Featuring nominations

```bash
ascelerate nominations [--app <app>] [--state draft|submitted|archived] [--json]
ascelerate nominations create --app <app> --type launch|enhancements|new-content --name "..." --description "..." --publish-start 2026-11-01 [--devices iphone,ipad] [--locales en-US,tr-TR] [--territories USA,TUR] [--materials https://...] [--notes "..."] [--pre-order] [--submit]
ascelerate nominations update <id> [--name ...] [--description ...] [--publish-start ...]   # drafts only
ascelerate nominations submit <id>      # send a draft to Apple's editors
ascelerate nominations archive <id>
ascelerate nominations delete <id>
```

`create` saves a draft unless `--submit`; review the draft with the user before submitting. When drafting the description, lead with what's new and why it matters to users (the editors read it), mention localization and accessibility work, and nominate well ahead of the publish date.

### Webhooks (App Store Connect event notifications)

```bash
ascelerate webhooks <app> [--json]
ascelerate webhooks create <app> --name "Release bot" --url https://example.com/hook --events app-store-version-app-version-state-updated,build-upload-state-updated [--secret ...] [--disabled]
ascelerate webhooks update <app> "Release bot" [--url ...] [--events ...|all] [--secret ...] [--enabled true|false]
ascelerate webhooks delete <app> "Release bot"
ascelerate webhooks ping <app> "Release bot"                 # test event
ascelerate webhooks deliveries <app> "Release bot" [--state failed] [--json]   # HTTP status + error per delivery
ascelerate webhooks redeliver <delivery-id>
```

Event types (`--events`, or `all`): `app-store-version-app-version-state-updated` (review/release state), `build-upload-state-updated`, `build-beta-detail-external-build-state-updated` (TestFlight external), `beta-feedback-crash-submission-created`, `beta-feedback-screenshot-submission-created`, plus background asset and alternative distribution events. Without `--secret`, `create` generates the signing secret and prints it once: tell the user to store it on the receiving server. To debug a receiver: `ping`, then `deliveries --state failed` for the HTTP status and error, fix, `redeliver`.

### Reports (downloads, proceeds, analytics)

```bash
# Sales & Trends — units/downloads + proceeds. Summarizes units by title/product type.
ascelerate reports sales [--frequency DAILY|WEEKLY|MONTHLY|YEARLY] [--date X] [--type SALES] [--sub-type SUMMARY] [--bundle-id <app>] [--vendor-number X] [--output report.tsv] [--raw]
# Financial report — units + partner proceeds for a fiscal period.
ascelerate reports finance --date YYYY-MM --region US [--type FINANCIAL|FINANCE_DETAIL] [--vendor-number X] [--output X] [--raw]
# App Analytics — downloads, impressions, sessions, etc. (async: creates/reuses a report request, downloads segments).
ascelerate reports analytics <app> [--category APP_STORE_ENGAGEMENT|APP_USAGE|COMMERCE|FRAMEWORK_USAGE|PERFORMANCE] [--granularity DAILY|WEEKLY|MONTHLY] [--report-name X] [--processing-date YYYY-MM-DD] [--ongoing] [--output dir/] [-y]
```

- **Vendor number** is required for `sales`/`finance` (App Store Connect → Payments and Financial Reports). Save it once with `ascelerate configure`, or pass `--vendor-number`.
- `sales`/`finance` default to a parsed **summary**; add `--raw` to print the TSV or `--output PATH` to save it. `--date` defaults to the most recent completed period for sales; for `finance` it's a *fiscal* period `YYYY-MM` (not a calendar month) and is required along with `--region`.
- `analytics` reuses an existing report request or prompts to create one (a one-time snapshot by default; `--ongoing` for recurring). A freshly created snapshot isn't ready immediately — re-run the command after a few minutes to download the segments.

### Apple Ads (campaigns, keywords, search terms, insights)

`ascelerate ads` drives the Apple Ads Platform API: performance reports, campaign/keyword/negative management, and Apple's keyword research data, across every app and campaign of the ad account. App names come from App Store Connect, so `--app` takes the same bundle IDs and aliases as the rest of ascelerate.

**Setup (once):** `ascelerate ads configure` — separate credentials from App Store Connect: an Apple Ads user with an API role (Account Settings → User Management), whose public key (ascelerate creates the key pair and prints it) is pasted into Account Settings → API; then it asks for the clientId/teamId/keyId shown there and the ad account to use. `ads accounts` lists accessible ad accounts.

```bash
# Read
ascelerate ads campaigns list [--app <app>] [--json]                  # status, countries, daily budget, bidding (Manual CPT / Max Conversions)
ascelerate ads adgroups [--app <app>] [--campaign X] [--json]         # default bid, CPA goal, Search Match on/off
ascelerate ads keywords list [--app <app>] [--campaign X] [--json]    # text, match type, status, bid
ascelerate ads negatives list [--app <app>] [--campaign X] [--json]   # campaign- or ad group-level
ascelerate ads reports campaigns    [--days 7 | --from YYYY-MM-DD --to YYYY-MM-DD] [--app <app>] [--campaign X] [--all] [--by age gender device country region city] [--json]
ascelerate ads reports adgroups     [same options]                    # per ad group (compare test groups, e.g. age splits)
ascelerate ads reports ads          [same options]                    # per ad, i.e. per product page (default vs custom)
ascelerate ads reports keywords     [same options]                    # per keyword, with Apple's suggested bid
ascelerate ads reports search-terms [same options]                    # what people actually searched, the keyword that matched, TARGETED vs AUTO (Search Match)
ascelerate ads recommendations [--app <app>] [--json]                 # Apple's open daily budget / target CPA recommendations with expected outcome
ascelerate ads campaigns target-cpa --app <app> [--country US] [--json]   # Apple's suggested target CPA for a new Max Conversions campaign
ascelerate ads history [--app <app>] [--campaign X] [--days 7] [--json]   # who changed what (UI, API, Apple support), with old → new values
ascelerate ads opportunities [--app <app>] [--campaign X] [--days 30] [--min-taps 10] [--brand "be gone" ...] [--json]   # search terms to add as exact keywords / give their own bid / exclude (last 30 complete days)

# Keyword research
ascelerate ads keywords suggest --app <app> --seed "qr code" "barcode" [--country US GB] [--limit 50] [--json]   # popularity 0-100 + where you already target it
ascelerate ads keywords popularity --country US (--app <app> | --genre PRODUCTIVITY_UTILITIES) [--term a b | --contains x] [--monthly] [--limit 100] [--json]
ascelerate ads insights impression-share --app <app> [--country US] [--term a b] [--weeks 1-4] [--first-slot] [--json]

# Write (confirm first; -y skips; --dry-run prints the request without sending)
ascelerate ads campaigns pause|resume <campaign>...
ascelerate ads campaigns create --like <campaign> --name N [--app <app>] [--country US] --daily 25 (--max-conversions --bid 2.50 | --default-bid 1.00 [--search-match on|off]) [--enabled]   # created PAUSED with its ad group (Max Conversions: the automated one)
ascelerate ads campaigns budget <campaign> --daily 120
ascelerate ads campaigns bid <campaign> --amount 0.80          # campaign-level bid; for Max Conversions the per-auction ceiling
ascelerate ads keywords add --campaign X [--ad-group Y] --match exact|broad [--bid 1.50] "kw 1" "kw 2"   # skips keywords already there
ascelerate ads keywords pause|resume --campaign X [--ad-group Y] [--match exact|broad] "kw"...
ascelerate ads keywords bid --campaign X [--ad-group Y] [--match exact|broad] --bid 1.25 "kw"...
ascelerate ads negatives add --campaign X [--ad-group Y] [--match exact|broad] "term"...                 # campaign-level unless --ad-group; default exact
ascelerate ads negatives remove --campaign X [--match exact|broad] "term"...
ascelerate ads adgroups create --campaign X --name "Exact" [--like "Existing Group"] [--default-bid 1.00] [--search-match on|off] [--cpa-goal 0.80] [--min-age 18] [--max-age 24] [--enabled]   # copies --like's pricing, bidding, CPA goal and targeting; created PAUSED unless --enabled
ascelerate ads keywords copy --campaign X --from "Group A" --to "Group B" [--match exact|broad]   # text, match type, bid, status; skips ones already there
ascelerate ads adgroups update "Group" --campaign X [--name N] [--default-bid B] [--search-match on|off] [--cpa-goal G]
ascelerate ads adgroups create --campaign X --automated               # the automated ad group a Max Conversions campaign needs (campaigns create adds it)
ascelerate ads adgroups pause|resume --campaign X "Group"...
ascelerate ads recommendations apply|dismiss <recommendation-id>...    # IDs from `ads recommendations`; apply changes the budget/target CPA
ascelerate ads product-pages --app <app> [--json]                      # the app's product pages as Apple Ads sees them (custom pages come from App Store Connect)
ascelerate ads ads [--app <app>] [--campaign X] [--json]               # ads you created, with product page and review state
ascelerate ads ads create --campaign X [--ad-group Y] --product-page <name|id|default> [--name N] [--enabled]   # ad variation: sends the ad group's taps to that page (Apple reviews it)
ascelerate ads ads pause|resume --campaign X <ad>                      # resume pauses the ad group's serving ad (one serves per ad group)
```

`--campaign` takes a campaign name (case-insensitive) or ID; a wrong name lists the valid ones. Report dates are in the ad account's time zone and `--days N` includes today (partial data) — for decisions, end ranges yesterday (`--to`) or compare complete periods. Keyword and search term reports take one request per campaign (Apple requires it), so an unscoped report over many campaigns takes a few seconds.

**Reading the metrics** (every report row has the same `metrics` object):
- `spend` (amount + currency), `impressions`, `taps`, `installs` (tap + view-through), `tapInstalls`.
- `ttr` = taps / impressions: how relevant the ad looks for the search. Low TTR on a keyword usually means the search intent doesn't match the app.
- `tapConversionRate` = tapInstalls / taps: how well the product page converts people who tapped. **`totalConversionRate`** = all installs / taps and includes people who saw the ad but installed without tapping; above 100% means strong view-through (brand or organic halo). Judge keyword quality on the tap rate; credit the campaign with the total.
- `averageCPT` = what a tap actually cost; the keyword's `bid` is the maximum. A bid far above average CPT has room to come down; Apple's `suggestedBid` (keywords report) is its estimate to win more auctions.
- `averageCPI` = spend / all installs. Compare across keywords and campaigns of the same app and country, not across countries.
- Search terms: `source` `TARGETED` matched one of your keywords; `AUTO` came from Search Match. A row without `searchTerm` is Apple hiding low-volume searches — it can't be added as a keyword.
- Impression share: `lowImpressionShare`–`highImpressionShare` (a range; 0.91–1.0 means over 90%), `rank` among advertisers (1 = most impressions), `popularityTier` 1–5. A low share on a popular, converting term is room to grow; a share under 100% on your own brand name means competitors bid on it.
- Popularity: `popularity` 1–100 across the storefront, `popularityInGenre` 1–100, `rankInGenre`. Only terms in the genre's ranked list come back; `--term`s that aren't are listed as `unranked` (less popular in that genre, or ranked under another one), not an error. Keyword suggestions are only relevant with `--seed`; without it Apple returns generic popular apps. Suggestion data is thin in some storefronts (in Turkey a seed only returned itself, with popularity on a 1–5 scale) — fall back to search terms and impression share there.
- Exact match includes close variants: a search can be served by a different exact keyword (search "qr" by exact "qr kodu"; "karekod okuyucu" by exact "barkod okuyucu"), at that keyword's bid. Aggregate the search terms report by `searchTerm` and compare with the keyword list: a converting search term without its own exact keyword deserves one with its own bid, and a cheap term riding an expensive keyword's bid is overpaying.
- `--by` breakdowns (campaign report only; JSON `breakdown`): **device** is reliable. **Age, gender, region and city are almost always `UNKNOWN`** (verified on four storefronts: 100% of spend for age and region, over 99.5% for gender), because Apple only knows them for users who allowed Personalized Ads. Don't base age or gender decisions on them; targeting an ad group by age or gender also limits it to those users, which cuts reach.
- Ignore keywords with too little data (rough rule: fewer than ~20 taps) before calling them good or bad.

`ads opportunities` automates the search-term analysis below with fixed rules against each campaign's own averages (JSON `kind`: `add-exact` = converting, no exact keyword of its own, CPI ≤ 1.25× the campaign's; `own-bid` = no own exact keyword, CPI above that, served by another keyword's bid; `negative` = no installs, tap conversion under half, TTR under a third on 1,000+ impressions, or CPI over 2×; never a term that is one of the campaign's keywords; terms need `--min-taps`). Each entry has `reason`, `metrics` and `servedBy` (keyword, match type, current bid; empty = Search Match). Brand searches (containing the app's name before ":" or " - ", or a `--brand` spelling) are left out of the campaign averages and never suggested as negatives: in brand-heavy campaigns their very cheap installs would otherwise make core generic terms look like negatives (seen live). Pass misspellings and spaced variants of the brand with `--brand`. Treat it as candidates: check relevance (competitor app names, off-topic intent such as a search for a web browser or an exam answer-sheet reader that happens to convert cheaply) before acting. Pass search terms to `keywords add`/`negatives add` exactly as the JSON returns them: Apple stores a typed Turkish "İ" as `i` + U+0307, which a retyped term won't match (add the plain spelling as well if unsure).

**Age/gender targeting caveats:** ages 18–64 only (no `--max-age` = 65+); it reaches only users who allowed Personalized Ads; and since September 2026 Apple's AdServices returns no attribution for installs from age- or gender-targeted ad groups, so RevenueCat/MMPs can't tie their purchases to the campaign. Judge such groups on Apple Ads' own spend, installs and CPI (`ads reports adgroups`).

Ad groups may carry a legacy **CPA goal** (`cpaGoal`). Apple deprecates it in favour of the Max Conversions bid strategy (target CPA) and doesn't document whether it still steers bidding; don't build new setups on it, and judge Manual CPT campaigns on bids, keywords and revenue. A typical restructure: `adgroups create --name "Exact" --search-match off` (copies the existing group, paused), move proven terms there as exact keywords, add them as exact negatives to the discovery group (broad + Search Match), then `adgroups resume`.

**Workflows:**
1. *Account review across apps:* `ads reports campaigns --days 30 --json` and `--days 7`; compare CPI, TTR and conversion per campaign; `ads recommendations` for budget-limited campaigns. Summarize per app: spend, installs, CPI, what changed.
2. *Keyword tuning (Manual CPT campaigns):* `ads reports keywords --campaign X --days 30 --json`. Pause or lower bids on keywords with meaningful spend and no or very expensive installs; raise bids toward `suggestedBid` on keywords with good CPI and few impressions; lower bids that sit far above average CPT.
3. *Search term mining:* start with `ads opportunities --campaign X --json`; for detail, `ads reports search-terms --campaign X --days 30 --json` (plus `ads keywords list` and `ads negatives list` for what exists; a campaign may have no negatives at all). Converting AUTO or broad-matched terms with good CPI → `ads keywords add --match exact`. Irrelevant or non-converting terms with real spend → `ads negatives add` (exact by default; broad only for a clearly irrelevant word). Never add a negative that blocks one of the campaign's own converting keywords.
4. *Where to grow:* `ads insights impression-share --app X --country C --weeks 4 --json`: popular terms where the app has a low share or rank 2+ (a competitor wins) and the search terms report shows good CPI are the place to raise bids or add exact keywords; a high share on irrelevant terms is wasted reach to exclude.
5. *Keyword discovery / ASO:* `ads keywords suggest --app X --seed ...` (shows where each is already targeted), `ads keywords popularity --app X --country US --term ...` to size them, `ads insights impression-share --app X` to see where you are weak. The same popularity data helps App Store keyword (ASO) choices.
6. *Revenue per campaign/keyword:* Apple Ads reports installs, not purchases. If the app uses RevenueCat with AdServices attribution (`Purchases.shared.attribution.enableAdServicesAttributionTokenCollection()`), RevenueCat's v2 Charts API (`GET /v2/projects/<id>/charts/revenue|conversion_to_paying`) segments and filters by `apple_search_ads_campaign`, `apple_search_ads_ad_group` and `apple_search_ads_keyword` (its `/options` endpoint lists `attribution_*` names the chart endpoint rejects); join with `ads reports campaigns|keywords --json` spend for spend per paying user and revenue on spend. Cheap installs and paying users can point in opposite directions (a keyword with the lowest CPI can bring the fewest payers). Expect small payer counts per keyword: treat them as direction.
A new campaign for an app shares auctions with that app's other campaigns in the same storefront: Apple lets one of them into each auction, so a test campaign next to a running one only gets leftovers (seen live: a Max Conversions campaign beside its manual twin got 1% of the volume). To test, move the traffic: e.g. keep the old campaign brand-only (pause non-brand keywords, Search Match off) and let the new one take the rest.

7. *Max Conversions campaigns* set bids themselves, but under the campaign bid, which Apple treats as a per-auction ceiling: a ceiling below the storefront's typical tap cost starves the campaign (seen live: 0.20 in France delivered ~2 spend in 9 months). Set it from what an install is worth, not as a target. Keyword bids don't apply there (ascelerate refuses `--bid`); steer them with this bid, the budget and Apple's target CPA recommendations.

**Custom product pages as ad variations:** an ad sends an ad group's taps to a product page; only one ad per ad group serves, so a custom page for specific searches needs an ad group of its own with those keywords (`adgroups create`, `keywords add`, then `ads create --product-page`). Custom pages are made in App Store Connect (`ascelerate product-pages create`). Ad groups without an ad you created serve Apple's implicit "Default Ad" (it shows in `reports ads` but not in `ads ads`). A good use: searches whose intent the default page doesn't speak to (low tap conversion on a relevant term).

**Change history:** `ads history` lists every change to campaigns, ad groups, keywords and negatives, including ones made in the web interface (By "UI") and by Apple support, for up to 6 months. Use it to check what changed before reading a performance shift, and to confirm a log matches reality. Apple records some bulk keyword updates and ad group bid changes as "Create" events; their details show the resulting values (match type, bid) instead of old → new.

**Rules for changes:** writes spend real money. Present the proposed changes (current → new, per keyword or campaign) and get the user's approval first; run the command with `--dry-run` to show the exact requests, then with `-y`. Prefer gradual bid changes over large jumps. Amounts are in the ad account's currency.

### In-app events

```bash
ascelerate events list <app> [--state PUBLISHED]
ascelerate events info <app> <ref-or-id>
ascelerate events create <app> --reference-name X [--badge SPECIAL_EVENT] [--purpose ATTRACT_NEW_USERS] [--priority HIGH] [--deep-link URL] [--primary-locale en-US] [--territories USA,GBR --publish-start 2026-07-01 --event-start 2026-07-05 --event-end 2026-07-12]
ascelerate events update <app> <ref-or-id> [--badge NONE]   # --badge NONE clears the badge
ascelerate events delete <app> <ref-or-id>

# Localizations (name, shortDescription, longDescription)
ascelerate events localizations view <app> <ref-or-id>
ascelerate events localizations export <app> <ref-or-id>
ascelerate events localizations import <app> <ref-or-id> --file event-locales.json

# Media (png/jpg -> screenshot, mp4/mov -> video clip)
ascelerate events media list <app> <ref-or-id>
ascelerate events media upload <app> <ref-or-id> --locale en-US --asset-type EVENT_CARD|EVENT_DETAILS_PAGE <file> [--preview-frame 00:00:03]
ascelerate events media delete <app> <ref-or-id> <media-id>
```

Badges: `LIVE_EVENT`, `PREMIERE`, `CHALLENGE`, `COMPETITION`, `NEW_SEASON`, `MAJOR_UPDATE`, `SPECIAL_EVENT`. Purposes: `APPROPRIATE_FOR_ALL_USERS`, `ATTRACT_NEW_USERS`, `KEEP_ACTIVE_USERS_INFORMED`, `BRING_BACK_LAPSED_USERS`. Schedule dates: ISO8601 or `yyyy-MM-dd`. Event localization locales must match the app's locales (e.g. `tr`, not `tr-TR`).

#### Event localization JSON format

```json
{ "en-US": { "name": "Summer Sale", "shortDescription": "...", "longDescription": "..." } }
```

### Custom product pages

```bash
ascelerate product-pages list <app>
ascelerate product-pages info <app> <name-or-id>
ascelerate product-pages create <app> --name X --locale en-US [--promotional-text "..."]   # compound create (page + version + first locale)
ascelerate product-pages update <app> <name-or-id> [--name X] [--visible true|false]
ascelerate product-pages delete <app> <name-or-id>
ascelerate product-pages localizations view <app> <name-or-id>
ascelerate product-pages localizations export <app> <name-or-id>
ascelerate product-pages localizations import <app> <name-or-id> --file page-locales.json    # promotional text per locale

# Media (png/jpg -> screenshot by --display-type, mp4/mov -> app preview by --preview-type; set auto-created)
ascelerate product-pages media list <app> <name-or-id>
ascelerate product-pages media upload <app> <name-or-id> --locale en-US --display-type APP_IPHONE_67 shot.png
ascelerate product-pages media upload <app> <name-or-id> --locale en-US --preview-type APP_IPHONE_67 clip.mp4 [--preview-frame 00:00:03]
ascelerate product-pages media delete <app> <name-or-id> <media-id>
```

Pages are referenced by name or ID. `create` issues a compound POST (page + version + localization linked via `${local-id}` inline references).

### Product page optimization (A/B tests)

```bash
ascelerate experiments <app> [--json]
ascelerate experiments info <app> "<test>" [--json]                      # treatments, locales, media per locale
ascelerate experiments create <app> --name "Screenshot order" --traffic 50 --treatment "Map first" [--treatment "..."]   # up to 3 treatments
ascelerate experiments treatments add <app> "<test>" --name "Icon B" --app-icon AppIconB   # alternate icon must ship in the live build
ascelerate experiments media upload <app> "<test>" "<treatment>" --locale en-US --display-type APP_IPHONE_67 01.png   # locale created if missing
ascelerate experiments media list <app> "<test>" [--treatment "..."]
ascelerate experiments media delete <app> "<test>" <media-id>
ascelerate experiments treatments remove-locale <app> "<test>" "<treatment>" --locale de-DE
ascelerate experiments submit <app> "<test>"    # App Review (new media needs it)
ascelerate experiments start <app> "<test>"     # after approval
ascelerate experiments stop <app> "<test>"
```

Workflow: create the test with its treatments, upload each treatment's screenshots per locale (same display types and library slots as `product-pages media`), check with `info`, `submit`, then `start` once approved. A treatment's locale starts as a copy of the original page's media (Apple seeds it when it's created, e.g. by the first upload), so uploads append to that copy: delete the copied screenshots you're replacing (`media list` shows their IDs). A locale a treatment doesn't cover shows the original page. Test one idea per treatment (e.g. first screenshot, or icon) so the result is attributable. Results are read in App Store Connect; ascelerate doesn't fetch them.

#### Custom product page localization JSON format

```json
{ "en-US": { "promotionalText": "Limited-time offer" } }
```

### Screenshots (Simulator Capture)

Capture App Store screenshots from simulators using UI tests. Replaces fastlane snapshot.

```bash
ascelerate screenshot init                          # Generate config and helper in ascelerate/ directory
ascelerate screenshot create-helper                 # Generate ScreenshotHelper.swift for UITest target
ascelerate screenshot run                           # Capture screenshots
ascelerate screenshot run -l en-US,tr-TR            # Override languages (subset of configured), comma-separated
ascelerate screenshot frame                         # Frame captured screenshots with device bezels
ascelerate screenshot doctor                        # Check config and environment for problems
```

#### Config (`ascelerate/screenshot.yml`)

```yaml
project: MyApp.xcodeproj
scheme: AppUITests
devices:
  - simulator: iPhone 17 Pro Max
    # frameDevice: true
    # deviceBezel: ./bezels/iPhone 17 Pro Max.png
  - simulator: iPad Pro 13-inch (M5)
    # frameDevice: true
    # deviceBezel: ./bezels/iPad Pro 13-inch (M5).png
languages: [en-US, de-DE]
outputDirectory: ./screenshots
clearPreviousScreenshots: true
localizeSimulator: true
overrideStatusBar: true
# helperPath: AppUITests/ScreenshotHelper.swift
# testWithoutBuilding: true
# headless: true
# darkMode: false
# disableAnimations: true
# waitAfterBoot: 5
# waitAfterEraseAndReboot: 30   # extra wait for first-run system alerts; fires on first language and on retries (the iOS 26 Apple Intelligence banner is suppressed automatically)
# configuration: Debug
# testplan: MyTestPlan
# numberOfRetries: 1
# stopAfterFirstError: false
# reinstallApp: false
# disableAssetDownloads: false   # disable mobileassetd: no Siri/keyboard/ML asset downloads into erased simulators (also blocks on-device ML assets some apps need)
# xcargs: SWIFT_ACTIVE_COMPILATION_CONDITIONS=SCREENSHOTS
# framedOutputDirectory: ./screenshots/framed
```

Supports dark mode capture, animation disabling, automatic retries (erases simulator, re-localizes, reboots), custom test plans, Xcode build configurations, and arbitrary xcodebuild arguments.

#### Device framing

Frame screenshots with Apple device bezels (from [Apple Design Resources](https://developer.apple.com/design/resources/)). Per-device: set `frameDevice: true` and `deviceBezel` path to the bezel PNG. Framing runs automatically after capture, or standalone via `screenshot frame`. Output goes to `framedOutputDirectory` (defaults to `{outputDirectory}/framed`). Use `screenshot doctor` to validate config, simulators, bezels, and environment.

#### UITest usage

```swift
override func setUp() {
    setupScreenshots(app)
    app.launch()
}

func testScreenshots() {
    screenshot("01-home")
    app.buttons["Settings"].tap()
    screenshot("02-settings")
}
```

Builds once, runs tests concurrently across devices per language. Output: `screenshots/{language}/{device}-{name}.png`. Errors skip and continue with summary table.

iPhone Duo simulator (Xcode 27.1+): `setHinge(.open)` / `setHinge(.closed)` unfold/fold mid-test (boots folded; no official API, so a future Xcode may break it). Unfolded apps often lay out like iPad while the runner's idiom stays `.phone`; detect with `ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4"`. `deviceBezel` accepts a list (e.g. the Duo's Outer Closed + Inner Open bezels); each screenshot uses the bezel whose screen area fits its size.

### Builds

```bash
ascelerate builds archive                           # Auto-detects workspace/scheme
ascelerate builds upload MyApp.ipa
ascelerate builds upload MyApp.ipa --api      # through the App Store Connect API instead of altool (.ipa or Mac .pkg; waits until App Store Connect has taken it in)
ascelerate builds uploads <app> [--json]       # recent uploads (any method) with state and Apple's errors/warnings: check here when an upload never became a build
ascelerate builds uploads <app> --delete-stale # remove upload records that will never complete
ascelerate builds await-processing <app>             # Wait for processing
ascelerate builds list --bundle-id <app>
```

### TestFlight

```bash
# Beta groups
ascelerate testflight groups list <app>
ascelerate testflight groups info <app> "External Testers"        # details + testers + builds
ascelerate testflight groups create <app> --name "Friends" --public-link --public-link-limit 100
ascelerate testflight groups update <app> "Friends" --public-link false
ascelerate testflight groups add-build <app> "Friends" --build 123 # omit --build for latest
ascelerate testflight groups delete <app> "Friends"

# Recruitment criteria (device/OS filters for public links)
ascelerate testflight groups criteria view <app> "Friends" --options
ascelerate testflight groups criteria set <app> "Friends" --filter IPHONE:18.0 --filter IPAD:17.0:26
ascelerate testflight groups criteria clear <app> "Friends"

# Testers
ascelerate testflight testers list <app> [--group "Friends"]
ascelerate testflight testers add <app> --email t@example.com --group "Friends"
ascelerate testflight testers remove <app> t@example.com --group "Friends"  # omit --group to remove from whole app
ascelerate testflight testers invite <app> t@example.com  # re-send invitation email
ascelerate testflight testers import <app> --file testers.csv --group "Friends"  # CSV: email[,first[,last]]

# Builds & distribution
ascelerate testflight builds <app>                        # TestFlight states per build
ascelerate testflight versions <app>                      # pre-release version trains
ascelerate testflight status <app> [--build 123]          # processing/internal/external/beta review
ascelerate testflight expire <app> --build 123
ascelerate testflight notify <app>                        # notify testers of latest build
ascelerate testflight auto-notify <app> --enabled true    # toggle automatic notification

# Tester feedback
ascelerate testflight feedback crashes list <app> [--build 123]
ascelerate testflight feedback crashes log <submission-id> [--output crash.log]
ascelerate testflight feedback screenshots list <app>
ascelerate testflight feedback screenshots download <app> [submission-id] [--output X.zip]  # zip of screenshots + comment; picker if ID omitted
ascelerate testflight feedback crashes|screenshots info <submission-id>    # full device details + comment
ascelerate testflight feedback crashes|screenshots delete <submission-id>

# What to Test (per build, per locale)
ascelerate testflight whats-new view <app>
ascelerate testflight whats-new set <app> --text "Bug fixes" [--locale en-US]  # all locales if omitted
ascelerate testflight whats-new export <app> --output notes.json
ascelerate testflight whats-new import <app> --file notes.json

# Beta review (required for external testing)
ascelerate testflight submit <app> [--build 123]
ascelerate testflight app-info view <app>                 # beta description, feedback email per locale
ascelerate testflight app-info update <app> --locale en-US --feedback-email me@example.com
ascelerate testflight review-info <app>                   # contact + demo account; pass flags to update
ascelerate testflight eula <app> [--file eula.txt | --text "..."]  # --text "" reverts to Apple's standard
```

Build-scoped commands default to the latest non-expired build; pass `--build <number>` (and `--platform` for universal-purchase apps) to target a specific one. What to Test JSON format: `{"en-US": {"whatsNew": "..."}}`.

### Provisioning

All provisioning commands support interactive mode (run without arguments for guided prompts):

```bash
# Devices
ascelerate devices list
ascelerate devices register

# Certificates (auto-generates CSR)
ascelerate certs create --type DISTRIBUTION
ascelerate certs revoke

# Bundle IDs & capabilities
ascelerate bundle-ids register --name "My App" --identifier com.example.MyApp --platform IOS
ascelerate bundle-ids enable-capability com.example.MyApp --type PUSH_NOTIFICATIONS

# Profiles
ascelerate profiles create --name "My Profile" --type IOS_APP_STORE --bundle-id com.example.MyApp --certificates all
ascelerate profiles reissue --all-invalid
```

Note: provisioning commands (devices, certs, bundle-ids, profiles) do NOT support aliases.

### App configuration

```bash
ascelerate apps app-info view <app>
ascelerate apps app-info update <app> --primary-category UTILITIES
ascelerate apps app-info age-rating <app>
ascelerate apps app-info age-rating export <app>
ascelerate apps app-info age-rating import <app> --file age-rating.json
ascelerate apps availability <app> --add CHN,RUS
ascelerate apps encryption <app> --create --description "Uses HTTPS"
ascelerate apps eula <app> --file eula.txt
ascelerate apps phased-release <app> --enable

# App Store accessibility declarations (per device family: iphone, ipad, mac, apple-tv, apple-watch, vision)
ascelerate apps accessibility <app>                                       # which features are declared, and draft/published state
ascelerate apps accessibility set <app> --device iphone --supports voiceover,voice-control,larger-text,dark-interface,differentiate-without-color,sufficient-contrast,reduced-motion [--publish]   # full declaration: unlisted = not supported ('none' for none)
ascelerate apps accessibility publish <app>                               # publish drafts as they are
# App-level subscription grace period (after failed renewal payments)
ascelerate apps subscription-grace-period <app>                         # view
ascelerate apps subscription-grace-period <app> --opt-in true --duration SIXTEEN_DAYS --renewal-type ALL_RENEWALS
ascelerate apps subscription-grace-period <app> --sandbox-opt-in true
```

Grace period durations: `THREE_DAYS`, `SIXTEEN_DAYS`, `TWENTY_EIGHT_DAYS`. Renewal types: `ALL_RENEWALS`, `PAID_TO_PAID_ONLY`.

### Workflow files

Automate multi-step releases with a plain text file:

```
# release.workflow
apps create-version com.example.MyApp 2.1.0
builds archive --scheme MyApp
builds upload --latest --bundle-id com.example.MyApp
builds await-processing com.example.MyApp
apps localizations import com.example.MyApp --file localizations.json
apps build attach-latest com.example.MyApp
apps review preflight com.example.MyApp
apps review submit com.example.MyApp
```

```bash
ascelerate run-workflow release.workflow
ascelerate run-workflow release.workflow --yes   # Skip all prompts (CI/CD)
```

Commands are one per line, without the `ascelerate` prefix. Lines starting with `#` are comments. `builds upload` automatically passes the build version to subsequent commands.

## Adding a new language to an app

When the user asks to add a new language/locale to an app, translate **all** of these:

1. **App info localizations** (name, subtitle, privacy URLs) — always
2. **Version localizations** (description, what's new, keywords, promo text) — always
3. **In-app purchases** — ask the user: translate all IAPs, or specific ones?
4. **Subscription groups** — ask the user: translate all groups, or specific ones?
5. **Subscriptions** — ask the user: translate all subscriptions, or specific ones?

### Workflow

1. Export existing localizations to see the source text:
   ```bash
   ascelerate apps app-info export <app>
   ascelerate apps localizations export <app>
   ascelerate iap localizations view <app> <product-id>       # for each IAP
   ascelerate sub group-localizations export <app>
   ascelerate sub localizations export <app> <product-id>     # for each subscription
   ```
2. Ask the user which IAPs, subscription groups, and subscriptions to translate (or all).
3. Translate the source text into the new locale.
4. Import the translations (use `-y` to skip confirmation prompts):
   ```bash
   ascelerate apps app-info import <app> --file app-infos.json -y
   ascelerate apps localizations import <app> --file localizations.json -y
   ascelerate iap localizations import <app> <product-id> --file iap.json -y
   ascelerate sub group-localizations import <app> --file group.json -y
   ascelerate sub localizations import <app> <product-id> --file sub.json -y
   ```

## Tips

- Add `--yes` / `-y` to skip confirmation prompts (for scripting/CI)
- Hitting App Store Connect's hourly API limit (3,600/key, rolling): ascelerate waits the `Retry-After` time with a notice on stderr and continues; set `ASCELERATE_MAX_RATE_LIMIT_WAIT=<seconds>` (total per run, `0` = fail at once) for CI. `rate-limit` shows the remaining quota and never waits
- Add `--dry-run` (anywhere on the command line, or set `ASCELERATE_DRY_RUN=1`) to try commands or a whole workflow without changing anything: reads run, every write is printed to stderr instead of sent, `builds upload` is skipped, and `run-workflow` continues past blocked steps
- Add `--json` to read commands for machine-readable output (see JSON output above)
- Use `ascelerate rate-limit` to check API quota (3600 requests/hour)
- Run `ascelerate install-completions` after updates for tab completion
- Only editable versions (Prepare for Submission / Waiting for Review) accept updates
- `promotionalText` can be updated on any version state
- Export JSON → edit → import is the fastest way to update localizations across locales
