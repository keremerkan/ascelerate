# ascelerate

A command-line tool for the App Store Connect API, built with Swift.

Findings about how Apple's APIs, Xcode and the simulators behave live (spec bugs, rate limits, live-verified behaviour, coverage) are kept in a private notes file, loaded through `CLAUDE.local.md` when present. Add new findings there, not here.

## Build & Run

```bash
swift build                           # Debug build
swift build -c release                # Release build (~6 min cold, mostly ASCKit's and the Ads client's generated code)
swift run ascelerate <command>        # Run directly
swift run ascelerate --help           # Show all commands
```

Install globally:
```bash
strip .build/release/ascelerate              # Strip debug symbols (~156 MB → ~41 MB)
cp .build/release/ascelerate /usr/local/bin/
```

## Project Structure

```
Package.swift                         # SPM manifest (Swift tools 6.2, macOS 15+; the Apple Ads client needs both); the libraries also declare iOS 27 (ASCKit and AscelerateCore build for it; AscelerateAds needs Apple's Ads package to declare iOS, which declares macOS only)
Scripts/
  update-asc-spec.sh                  # Checks Apple's spec for a newer version; prepares it and regenerates ASCKit's client
  prepare-asc-spec.swift              # Apple spec → Sources/ASCKit/openapi.json + nameOverrides + ASCEnums.swift
  split-generated.swift               # Splits the generator's output into ~3,000-line files (parallel compiling)
  compare-with-release.sh             # Diff read-only command output: released binary vs debug build
Sources/ASCKit/                       # The App Store Connect client (see "ASCKit")
  openapi.json                        # Apple's spec, prepared
  openapi-generator-config.yaml       # Generated paths (filter.paths) + generated nameOverrides
  ASCKit.swift                        # Client factory, JWT, error/paging/nulls/dry-run/rate-limit/pacing middlewares, date transcoder
  ASCEnums.swift                      # Generated catalog of the spec's string enums (ASCEnum.*)
  Generated/                          # The generated client, split (never edit by hand)
Sources/AscelerateCore/               # App Store Connect logic without terminal I/O (see "AscelerateCore"), one file per area:
  Lookup.swift                        # findApp(exactBundleID:), findVersion(…, choose:), Platform, optionalRelated, AppLookupError
  ProductVersions.swift, ReviewProducts.swift, ReviewSubmissions.swift, Preflight.swift
  Versions.swift, Releases.swift, VersionLocalizations.swift, AppInfos.swift, LocalizationFile.swift, FieldLimits.swift
  AssetLibrary.swift, LocalizationMedia.swift, ClassicMedia.swift, MediaUpload.swift, MediaDownload.swift
  Builds.swift, BuildUploadRecords.swift, BetaGroups.swift, BetaTesters.swift, TestInformation.swift, ReviewInformation.swift,
  BetaReview.swift, BetaFeedback.swift, RecruitmentCriteria.swift, ReviewAttachments.swift
  InAppPurchases.swift, Subscriptions.swift, IntroductoryOffers.swift, OfferCodes.swift, PromotionalOffers.swift,
  RetentionMessages.swift, WinBackOffers.swift, PromotedPurchases.swift, SubscriptionSettings.swift, AppPricing.swift, AppAvailability.swift
  GameCenter*.swift                   # Game Center: detail and versions, achievements, leaderboards, sets, activities, challenges, groups, matchmaking
  AppEvents.swift, CustomProductPages.swift, Experiments.swift, Nominations.swift, CustomerReviews.swift, AppTags.swift,
  AccessibilityDeclarations.swift, LicenseAgreements.swift, RoutingCoverage.swift, EncryptionDeclarations.swift
  Certificates.swift, BundleIDs.swift, Profiles.swift, Devices.swift, Users.swift, SandboxTesters.swift
  Diagnostics.swift, Analytics.swift, SalesReports.swift, XcodeCloud.swift, ZipReader.swift, XcodeProjectFile.swift
  CSV.swift, Formatting.swift, Concurrency.swift, Retry.swift
Sources/AscelerateAds/                # Apple Ads logic without terminal I/O, on AppleAdsClient and AscelerateCore (see "Apple Ads")
  Ads.swift                           # Credentials, Options, withClient, middleware, lookups, /query paging, reports, bulk/decodeRaw
  AdsMetrics.swift, AdsReports.swift, AdsWrites.swift
Sources/ascelerate/
  Ascelerate.swift                    # @main entry, root AsyncParsableCommand, central error handling
  Config.swift                        # ~/.ascelerate/config.json loader, APICredentials, ConfigError
  ClientFactory.swift                 # makeClient(): the authenticated ASCKit client (honors ASCELERATE_DRY_RUN)
  Settings.swift                      # settings.json, `settings` command, XcodebuildOutput
  Formatting.swift                    # CLI helpers: Table.print, ANSI colors, prompts, readAnswer, describeError, expandPath, --json/--yes/--dry-run globals
  Aliases.swift                       # Alias storage (~/.ascelerate/aliases.json), resolveAlias()
  EventOutput.swift, WorkflowEvent.swift  # --json-events output
  MediaUpload.swift                   # Media management: folder scan, upload, download, verify; UploadProgressLine
  AssetLibrary.swift, LocalizationMedia.swift  # CLI extensions of the core types (validation, upload and place, one-file media)
  ProductAvailability.swift, ProductMedia.swift  # Shared drivers for the iap/sub commands
  BuildUpload.swift                   # builds upload --api
  Reports.swift                       # Shared report plumbing
  Ads/                                # Ads.swift (config, dry-run gate, lookups, prompts, Scope), AdsReports.swift (tables), AdsASC.swift (the only Ads file importing ASCKit)
  Commands/                           # One file per command group (AppsCommand, BuildsCommand, TestFlightCommand, IAPCommand, SubCommand, Ads*Command, GameCenter*Command, …)
  Screenshot/                         # The screenshot module (see "Screenshot Module")
Tests/ASCKitTests/                    # Middlewares against a fake server (rate limit wait, paging, error decoding)
Tests/AscelerateCoreTests/            # Core logic (pricing, price files, project files, set sync, zip reader, …)
skills/
  ascelerate/SKILL.md                 # AI coding skill (single source of truth)
  package.json                        # npm package for npx installer
  bin/install.js                      # npx installer (fetches SKILL.md from GitHub)
website/                              # Docs site (see "Website")
```

## Dependencies

- **ASCKit** (local target, `Sources/ASCKit`) — the App Store Connect client, generated by [swift-openapi-generator](https://github.com/apple/swift-openapi-generator) from Apple's own spec (the generated sources are committed; the generator is no package dependency), on [swift-openapi-runtime](https://github.com/apple/swift-openapi-runtime) and [swift-openapi-urlsession](https://github.com/apple/swift-openapi-urlsession); see "ASCKit" below. It replaced asc-swift in 0.22.0.
- **AscelerateCore** (local target, `Sources/AscelerateCore`) — the commands' App Store Connect logic, on ASCKit; see "AscelerateCore" below. Both are also library products.
- **[swift-argument-parser](https://github.com/apple/swift-argument-parser)** (1.3.0+) — CLI framework
- **[swift-certificates](https://github.com/apple/swift-certificates)** (1.0.0+) — X.509 certificate and CSR generation (CSRs in AscelerateCore's `Certificates.signingRequest`, used by `certs create`'s auto-CSR flow)
- **[Yams](https://github.com/jpsim/Yams)** (5.0.0+) — YAML parsing (used by `screenshot` command for `ascelerate.yml`)
- **[apple-ads-platform-api-swift](https://github.com/apple/apple-ads-platform-api-swift)** (`AppleAdsClient`, traits off), through the fork [keremerkan/apple-ads-platform-api-swift](https://github.com/keremerkan/apple-ads-platform-api-swift) pinned `exact: "1.109.0-ios.1"`: Apple's v1.109.0 plus one commit declaring iOS 18 (Apple's declares macOS only), so the libraries build for iOS. On a new Apple release, put that commit on its tag and tag the fork `<version>-ios.1` (a pre-release tag never clashes with Apple's; `from:` doesn't match pre-releases, hence `exact:`); drop the fork once Apple declares iOS. Apple's generated client for the Apple Ads Platform API, used by the `ads` commands. It requires macOS 15 and swift-tools 6.2 and brings AsyncHTTPClient/NIO (its token fetch always uses them); the stripped release binary grew from 42.8 MB (0.23.1) to 64.4 MB (0.24.0, which also generates more ASCKit paths). Apple publishes no raw spec, so it can't be path-filtered like ASCKit; copying its generated `Client.swift`/`Types.swift` into an own target would drop NIO without changing command code.

## Authentication

Config file at `~/.ascelerate/config.json`:
```json
{
    "keyId": "KEY_ID",
    "issuerId": "ISSUER_ID",
    "privateKeyPath": "/Users/.../.ascelerate/AuthKey_XXXXXXXXXX.p8",
    "vendorNumber": "80012345",
    "ads": {
        "clientId": "SEARCHADS.…", "teamId": "SEARCHADS.…", "keyId": "…",
        "privateKeyPath": "/Users/.../.ascelerate/ads-private-key.pem",
        "adAccountId": 123456
    }
}
```

- `ads` is **optional** — only the `ads` commands use it; `ads configure` writes it (generating the P-256 key pair) and `configure` keeps it when rewriting the file.

- `configure` command copies the .p8 file into `~/.ascelerate/` and writes the config
- `vendorNumber` is **optional** — only the `reports sales`/`reports finance` commands use it (App Store Connect → Payments and Financial Reports). `configure` prompts for it (skippable); `--vendor-number` overrides per-invocation. Resolved by `Reports.resolveVendorNumber()`.
- **A key for one run:** `ASCELERATE_KEY_ID`, `ASCELERATE_ISSUER_ID` and `ASCELERATE_PRIVATE_KEY_PATH` (all three, or the run fails naming the missing ones) take precedence over `config.json` without changing it (`APICredentials` in Config.swift; the API client, `altool` and `configure --show` use it). With them, `builds archive` and the export also pass `-authenticationKeyPath`/`-authenticationKeyID`/`-authenticationKeyIssuerID` to `xcodebuild`, which provisions with the key instead of Xcode's Apple ID accounts; the configured key isn't passed, so provisioning without the variables is as before. Verified 2026-10-23: archive and export of a manually signed app with a key from the environment. `main` reads the three variables once and then removes them from its environment (`APICredentials.removeFromEnvironment`), so the tools it starts (xcodebuild with the project's build phases, package plugins and test runners) don't inherit the key's location; the CLI passes the key to xcodebuild itself.
- File permissions set to 700 (dir) and 600 (files) — owner-only access
- JWT tokens use ES256 (P256, CryptoKit) signing with a 20-minute expiry; ASCKit's `TokenStore` reuses a token until its last minute
- The private key is read as PEM text from `privateKeyPath`

## Commands

```
ascelerate configure                                              # Interactive setup
ascelerate configure --stdin                                      # Non-interactive: {"keyId","issuerId","privateKey"} JSON on stdin; keeps vendorNumber + ads
ascelerate configure --show                                       # Print the key ID and issuer ID in use (and whether they come from the environment)
ascelerate apps list [--json]                                     # List all apps
ascelerate apps info <bundle-id> [--json]                         # App details
ascelerate apps versions <bundle-id> [--json]                     # List App Store versions
ascelerate apps localizations view <bundle-id> [--version X] [--platform X]      # View localizations
ascelerate apps localizations update <bundle-id> [--locale X] [--platform X]     # Update single locale via flags
ascelerate apps localizations import <bundle-id> [--file X] [--platform X]       # Bulk update from JSON file
ascelerate apps localizations export <bundle-id> [--version X] [--platform X]    # Export to JSON file
ascelerate apps review preflight <bundle-id> [--version X] [--platform X] [--json]  # Pre-submission checks (includes IAP/sub state and pricing)
ascelerate apps review status <bundle-id> [--version X] [--json]    # Review submission status
ascelerate apps create-version <bundle-id> <ver> [--platform X]   # Create new version
ascelerate apps copyright <bundle-id> [--set X] [--version X] [--platform X] [-y]  # View/update version copyright notice
ascelerate apps build attach <bundle-id> [--version X] [--platform X]             # Interactively select and attach a build
ascelerate apps build attach-latest <bundle-id> [--version X] [--platform X]     # Attach the most recent build
ascelerate apps build detach <bundle-id> [--version X] [--platform X]            # Remove the attached build
ascelerate apps phased-release <bundle-id> [--version X] [--platform X]          # View/manage phased release
ascelerate apps release <bundle-id> [--version X] [--platform X] [-y]            # Release a version in Pending Developer Release
ascelerate apps app-info age-rating <bundle-id>                            # View age rating
ascelerate apps app-info age-rating export <bundle-id>                     # Export age rating to JSON
ascelerate apps app-info age-rating import <bundle-id> [--file X]          # Update age rating from JSON
ascelerate apps routing-coverage <bundle-id> [--file X]           # View/upload routing coverage
ascelerate apps review submit <bundle-id> [--version X]            # Submit version for App Review (offers IAPs/subs and Game Center items with pending versions)
ascelerate apps review resolve-issues <bundle-id> [--platform X]  # Mark rejected items as resolved
ascelerate apps review cancel-submission <bundle-id> [--platform X]  # Cancel an active review submission
ascelerate apps review info <bundle-id> [--version X] [--platform X] [--contact-first-name X] [--contact-last-name X] [--contact-phone X] [--contact-email X] [--demo-account-name X] [--demo-account-password X] [--demo-account-required true|false] [--notes X] [-y]  # View/update App Review Information
ascelerate apps review attachment list <bundle-id> [--version X] [--platform X]              # List App Review attachment files
ascelerate apps review attachment upload <bundle-id> [--version X] [--platform X] <file> [-y]  # Upload an App Review attachment
ascelerate apps review attachment delete <attachment-id> [-y]               # Delete an App Review attachment
ascelerate apps media upload <bundle-id> [folder] [--version X] [--platform X] [--replace]  # Upload screenshots/previews (--replace: only new or changed files, then reorder)
ascelerate apps media download <bundle-id> [--folder X] [--locale X,Y] [--version X] [--platform X]  # Download screenshots/previews (+ library images)
ascelerate apps media verify <bundle-id> [--version X] [--platform X] [folder]              # Check media status, retry stuck
ascelerate apps media prune <bundle-id> [folder] [--version X] [--platform X] [-y]          # Delete server sets with no matching local folder
ascelerate apps media remove <bundle-id> PRODUCT_PAGE_HEADER|APP_STORE_SEARCH_RESULTS|APP_IPHONE_DUO [--previews] [--locale X,Y] [--version X] [--platform X] [-y]  # Remove asset library images/videos from a version (+ delete them from the library when unused)
ascelerate apps media library <bundle-id> [--only KIND,KIND] [--delete-unused] [-y]          # Count library images; list (and delete) unused, never-reviewed ones; --only: PRODUCT_PAGE_HEADER/APP_STORE_SEARCH_RESULTS/APP_IPHONE_DUO/UNFINISHED_UPLOADS or a display type (APP_IPHONE_67, ...)
ascelerate apps app-info view <bundle-id>                         # View app info, categories, and localizations
ascelerate apps app-info view --list-categories                   # List available category IDs
ascelerate apps app-info update <bundle-id> [--name X] [--subtitle X] [--primary-category X] [-y]  # Update localization fields and/or categories
ascelerate apps app-info import <bundle-id> [--file X] [--verbose] [-y]  # Bulk update localizations from JSON
ascelerate apps app-info export <bundle-id> [--output X]          # Export localizations to JSON
ascelerate apps accessibility [view] <bundle-id> [--all] [--json]   # App Store accessibility declarations per device family (--all: incl. replaced)
ascelerate apps accessibility set <bundle-id> --device iphone|ipad|mac|apple-tv|apple-watch|vision --supports a,b,…|none [--publish] [-y]  # Full declaration (unlisted = unsupported); creates or updates
ascelerate apps accessibility publish <bundle-id> [-y]            # Publish draft declarations as they are
ascelerate apps availability <bundle-id> [--add X] [--remove X]  # View/update territory availability
ascelerate apps pricing [show] <bundle-id> [--all] [--json]       # App price schedule: base price, prices set by hand, planned changes (--all: every territory)
ascelerate apps pricing tiers <bundle-id> [--territory USA]       # A territory's price tiers
ascelerate apps pricing set <bundle-id> --price X [--base-territory X] [--start-date X] [--drop-manual] [-y]  # Base price, now or dated
ascelerate apps pricing override <bundle-id> --territory X --price X [-y]   # A territory's price by hand
ascelerate apps pricing keep|remove <bundle-id> --territories X,Y|all [-y]  # Keep Apple's current prices by hand / back to Apple's
ascelerate apps pricing sale <bundle-id> --territories X,Y|all --price X --start-date X --end-date X [-y]  # Temporary price change
ascelerate apps pricing cancel <bundle-id> --territory X --start-date X [-y]  # Remove a planned change
ascelerate apps pricing export|import <bundle-id> [--output X|--file X] [--snap] [-y]  # iap pricing export format; import replaces the schedule (--snap: nearest tier for a price that isn't one)
ascelerate apps encryption <bundle-id> [--create]                 # View/create encryption declarations
ascelerate apps encryption <bundle-id> --upload-document X [--declaration ID]  # Attach a compliance document (newest declaration by default)
ascelerate apps tags [view] <bundle-id> [--json]                  # Apple's App Store tags: shown/hidden, territories
ascelerate apps tags hide|show <bundle-id> <name-or-id> [-y]      # Hide or show a tag
ascelerate apps eula <bundle-id> [--file X] [--delete]            # View/manage custom EULA
ascelerate apps subscription-grace-period <bundle-id> [--opt-in true|false] [--sandbox-opt-in true|false] [--duration X] [--renewal-type X] [-y]  # View/update app-level subscription grace period
ascelerate apps streamlined-purchasing <bundle-id> [--enabled true|false] [-y]  # View/turn on or off buying subscriptions outside the app
ascelerate builds list [--bundle-id <id>] [--version X] [--platform X] [--json]  # List builds
ascelerate builds archive [--workspace X] [--scheme X] [--output X] [--build-number N|auto] [--xcodebuild-output quiet|full]  # Archive Xcode project (--build-number: CURRENT_PROJECT_VERSION for this archive only, every embedded target; auto: the app target's, or the one after the highest uploaded for the platform when that's taken, `Builds.numberNeeded`; always passed, so extensions match the app)
ascelerate settings [--xcodebuild-output quiet|full|default]     # The tool's settings (~/.ascelerate/settings.json): xcodebuild output; ASCELERATE_XCODEBUILD_OUTPUT overrides for one run
ascelerate builds archives [--bundle-id X] [--platform X] [--limit N] [--json]  # Xcode's archives, newest first (bundle ID, version, build, platform, date, path)
ascelerate builds upload [file] [--api]                           # Upload build via altool, or the App Store Connect API (--api, .ipa or Mac .pkg)
ascelerate builds upload --latest [--bundle-id X] [--platform X]  # Upload the newest archive in Xcode's archive location (of an app, of a platform)
ascelerate builds uploads <bundle-id> [--platform X] [--limit N] [--json]  # Recent uploads (API and altool) with state + Apple's errors/warnings
ascelerate builds uploads <bundle-id> --delete-stale [-y]          # Delete upload records that will never complete
ascelerate builds validate [file]                                 # Validate build via altool
ascelerate builds await-processing <bundle-id> [--build-version X] [--platform X]  # Wait for build to finish processing
ascelerate iap list <bundle-id> [--type X] [--state X] [--json]   # List in-app purchases
ascelerate iap info <bundle-id> <product-id> [--json]              # IAP details, localizations, missing-pricing warning
ascelerate iap promoted list <bundle-id>                           # List promoted purchases (display order)
ascelerate iap promoted add <bundle-id> <product-id> [--visible-for-all true|false] [--enabled true|false] [-y]  # Promote an IAP/subscription
ascelerate iap promoted remove <bundle-id> <product-id> [-y]       # Stop promoting
ascelerate iap promoted reorder <bundle-id> <product-id,product-id,...> [-y]  # Set App Store display order
ascelerate iap promoted toggle <bundle-id> <product-id> --enabled true|false [-y]  # Enable/disable a promotion
ascelerate iap create <bundle-id> [--type X] [--product-id X] [--name X] [--review-note X] [--family-sharable] [-y]  # Create IAP
ascelerate iap update <bundle-id> <product-id> [--name X] [--review-note X] [--family-sharable true|false] [-y]  # Update IAP
ascelerate iap delete <bundle-id> <product-id> [-y]               # Delete IAP
ascelerate iap submit <bundle-id> <product-id> [-y]               # Submit IAP for review
ascelerate iap localizations view <bundle-id> <product-id>        # View IAP localizations
ascelerate iap localizations export <bundle-id> <product-id> [--output X]  # Export IAP localizations to JSON
ascelerate iap localizations import <bundle-id> <product-id> [--file X] [--verbose] [-y]  # Import IAP localizations from JSON
ascelerate iap pricing show <bundle-id> <product-id> [--json]     # Show current price schedule (warns if missing)
ascelerate iap pricing tiers <bundle-id> <product-id> [--territory USA]  # List available price tiers for a territory
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99 [--base-territory USA] [--start-date YYYY-MM-DD] [--remove-all-overrides] [-y]  # Set base price; preserves overrides (interactive menu to drop)
ascelerate iap pricing override <bundle-id> <product-id> --price 5.99 --territory FRA [--start-date YYYY-MM-DD] [-y]  # Add/update per-territory manual price override
ascelerate iap pricing remove <bundle-id> <product-id> --territory FRA [-y]  # Drop a per-territory override (revert to auto-equalize)
ascelerate iap pricing export <bundle-id> <product-id> [--output X]  # Export price schedule (base + manual prices) to JSON
ascelerate iap pricing import <bundle-id> <product-id> [--file X] [--start-date X] [--snap] [-y]  # Apply exported schedule (wholesale replace; matches by customer price; --snap: nearest tier for a price that isn't one)
ascelerate iap availability <bundle-id> <product-id> [--add X] [--remove X] [--available-in-new-territories true|false] [-y]  # View/update per-IAP territory availability
ascelerate iap offer-code list <bundle-id> <product-id>           # List offer codes for an IAP
ascelerate iap offer-code info <bundle-id> <product-id> <offer-code-id>  # Show details + price/code counts
ascelerate iap offer-code create <bundle-id> <product-id> --name X --eligibility N,A,C --price 4.99 [--territory USA] [--equalize-all-territories] [-y]  # Create offer code with single-territory or fan-out prices
ascelerate iap offer-code toggle <bundle-id> <product-id> <offer-code-id> --active true|false [-y]  # Activate / deactivate
ascelerate iap offer-code gen-codes <bundle-id> <product-id> <offer-code-id> --count N --expires YYYY-MM-DD [--environment PRODUCTION|SANDBOX] [-y]  # Generate one-time-use code batch
ascelerate iap offer-code add-custom-codes <bundle-id> <product-id> <offer-code-id> --code X --count N [--expires YYYY-MM-DD] [-y]  # Add a custom redeem code
ascelerate iap offer-code view-codes <one-time-use-batch-id> [--output X]  # Fetch actual code values (async; may need retry)
ascelerate iap images list <bundle-id> <product-id>               # List uploaded promotional images
ascelerate iap images upload <bundle-id> <product-id> <file> [-y] # Upload image (3-step reserve/PUT/commit)
ascelerate iap images delete <bundle-id> <product-id> <image-id> [-y]  # Delete an image
ascelerate iap review-screenshot view <bundle-id> <product-id>    # Show current App Review screenshot
ascelerate iap review-screenshot upload <bundle-id> <product-id> <file> [-y]  # Upload (replaces existing)
ascelerate iap review-screenshot delete <bundle-id> <product-id> [-y]  # Delete
ascelerate sub groups <bundle-id> [--json]                        # List subscription groups with subscriptions
ascelerate sub list <bundle-id> [--json]                          # Flat list of all subscriptions
ascelerate sub info <bundle-id> <product-id> [--json]             # Subscription details, localizations, missing-prices warning
ascelerate sub create <bundle-id> [--product-id X] [--name X] [--period X] [--group-level N] [--review-note X] [--family-sharable] [-y]  # Create subscription
ascelerate sub update <bundle-id> <product-id> [--name X] [--review-note X] [--group-level N] [--family-sharable true|false] [-y]  # Update subscription
ascelerate sub delete <bundle-id> <product-id> [-y]               # Delete subscription
ascelerate sub submit <bundle-id> <product-id> [-y]               # Submit subscription for review
ascelerate sub create-group <bundle-id> [--name X] [-y]           # Create subscription group
ascelerate sub update-group <bundle-id> [--name X] [-y]           # Update subscription group
ascelerate sub delete-group <bundle-id> [-y]                      # Delete subscription group
ascelerate sub localizations view <bundle-id> <product-id>        # View subscription localizations
ascelerate sub localizations export <bundle-id> <product-id> [--output X]  # Export subscription localizations to JSON
ascelerate sub localizations import <bundle-id> <product-id> [--file X] [--verbose] [-y]  # Import subscription localizations from JSON
ascelerate sub group-localizations view <bundle-id>               # View group localizations
ascelerate sub group-localizations export <bundle-id> [--output X]  # Export group localizations to JSON
ascelerate sub group-localizations import <bundle-id> [--file X] [--verbose] [-y]  # Import group localizations from JSON
ascelerate sub pricing show <bundle-id> <product-id> [--json]     # Show current prices per territory (warns if none)
ascelerate sub pricing tiers <bundle-id> <product-id> [--territory USA]  # List available price tiers for a territory
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 [--territory USA] [--start-date YYYY-MM-DD] [--preserve-current | --no-preserve-current] [--equalize-all-territories] [--confirm-decrease] [-y]  # Set price for one territory or fan out to all (equalized). Increases require --preserve-current/--no-preserve-current; decreases prompt interactively or require --confirm-decrease in -y mode.
ascelerate sub pricing export <bundle-id> <product-id> [--output X]  # Export per-territory prices to JSON
ascelerate sub pricing import <bundle-id> <product-id> [--file X] [--start-date X] [--preserve-current|--no-preserve-current] [--confirm-decrease] [--snap] [-y]  # Apply exported prices (same increase/decrease safety as pricing set; --snap: nearest tier for a price that isn't one)
ascelerate sub availability <bundle-id> <product-id> [--add X] [--remove X] [--available-in-new-territories true|false] [--plan upfront|monthly] [-y]  # View/update per-subscription territory availability (per billing plan)
ascelerate sub intro-offer list <bundle-id> <product-id>          # List intro offers (free trials, intro discounts)
ascelerate sub intro-offer create <bundle-id> <product-id> --mode FREE_TRIAL|PAY_AS_YOU_GO|PAY_UP_FRONT --duration X --periods N --territories USA,TUR|all [--price 4.99] [--start-date Y] [--end-date Y] [-y]  # Create intro offer (one request; price in the first territory, comparable elsewhere; conflicting territories skipped)
ascelerate sub intro-offer update <bundle-id> <product-id> <offer-id> --end-date Y [-y]  # Update intro offer end date
ascelerate sub intro-offer delete <bundle-id> <product-id> <offer-id> [-y]  # Delete intro offer
ascelerate sub offer-code list <bundle-id> <product-id>           # List offer codes for a subscription
ascelerate sub offer-code info <bundle-id> <product-id> <offer-code-id>  # Show details + price/code counts
ascelerate sub offer-code create <bundle-id> <product-id> --name X --eligibility N,E,X --offer-eligibility STACK_WITH_INTRO_OFFERS|REPLACE_INTRO_OFFERS --mode FREE_TRIAL|PAY_AS_YOU_GO|PAY_UP_FRONT --duration X --periods N [--auto-renew | --no-auto-renew] --price 4.99 [--territory USA] [--equalize-all-territories] [-y]  # Create offer code
ascelerate sub offer-code toggle <bundle-id> <product-id> <offer-code-id> --active true|false [-y]  # Activate / deactivate
ascelerate sub offer-code gen-codes <bundle-id> <product-id> <offer-code-id> --count N --expires YYYY-MM-DD [--environment PRODUCTION|SANDBOX] [-y]  # Generate one-time-use code batch
ascelerate sub offer-code add-custom-codes <bundle-id> <product-id> <offer-code-id> --code X --count N [--expires YYYY-MM-DD] [-y]  # Add a custom redeem code
ascelerate sub offer-code view-codes <one-time-use-batch-id> [--output X]  # Fetch actual code values (async; may need retry)
ascelerate sub promo-offer list <bundle-id> <product-id>          # List promotional offers (server-signed)
ascelerate sub promo-offer info <bundle-id> <product-id> <offer-id>  # Show details
ascelerate sub promo-offer create <bundle-id> <product-id> --name X --code X --mode X --duration X --periods N --price 4.99 [--territory USA] [--equalize-all-territories] [-y]  # Create
ascelerate sub promo-offer update <bundle-id> <product-id> <offer-id> --price 4.99 [--territory USA] [--equalize-all-territories] [-y]  # Update prices only
ascelerate sub promo-offer delete <bundle-id> <product-id> <offer-id> [-y]  # Delete
ascelerate sub retention-message [list|info] <bundle-id> [<message>] [--json]  # Retention messages: versions, languages, image, subscriptions showing them
ascelerate sub retention-message create <bundle-id> --name X [--locale X --header X --body X] [-y]  # Message + its first version
ascelerate sub retention-message localizations [view|set|delete] <bundle-id> <message> [--locale X --header X --body X] [-y]
ascelerate sub retention-message image upload|delete <bundle-id> <message> [file] [-y]  # One 16:9 image per version (asset library)
ascelerate sub retention-message new-version|submit|delete <bundle-id> <message> [-y]  # submit: adds the version to the draft submission
ascelerate sub retention-message assign <bundle-id> <product-id> <message|none> [--offers offer-id,…|none] [-y]  # The subscription's message and the offers it shows
ascelerate sub retention-offer [list|info|delete] <bundle-id> <product-id> [<offer-id>] [-y]
ascelerate sub retention-offer create <bundle-id> <product-id> --name X --offer-id X --mode X --duration X [--periods N] --paid-months N [--wait-months N] [--plan upfront|monthly] [--price X] [--territories X,Y|all] [-y]
ascelerate sub retention-offer update <bundle-id> <product-id> <offer-id> [--paid-months N] [--wait-months N] [-y]  # Eligibility only
ascelerate sub win-back-offer [list|info|delete] <bundle-id> <product-id> [<offer-id>] [--json] [-y]  # Offers for people whose subscription ended
ascelerate sub win-back-offer create <bundle-id> <product-id> --name X --offer-id X --mode X --duration X [--periods N] --since-months A-B --paid-months N [--wait-months N] [--start-date X] [--end-date X] [--priority normal|high] [--promote] [--plan upfront|monthly] [--price X] [--territories X,Y|all] [-y]
ascelerate sub win-back-offer update <bundle-id> <product-id> <offer-id> [--since-months A-B] [--paid-months N] [--wait-months N] [--start-date X] [--end-date X] [--priority X] [--promote true|false] [-y]
ascelerate sub submit-group <bundle-id> [-y]                      # Submit a subscription group for review (mirror of `sub submit`)
ascelerate sub images list <bundle-id> <product-id>               # List uploaded promotional images
ascelerate sub images upload <bundle-id> <product-id> <file> [-y] # Upload image (3-step reserve/PUT/commit)
ascelerate sub images delete <bundle-id> <product-id> <image-id> [-y]  # Delete an image
ascelerate sub review-screenshot view <bundle-id> <product-id>    # Show current App Review screenshot
ascelerate sub review-screenshot upload <bundle-id> <product-id> <file> [-y]  # Upload (replaces existing)
ascelerate sub review-screenshot delete <bundle-id> <product-id> [-y]  # Delete
ascelerate sandbox-testers [--json]                               # Sandbox testers: Apple Account, storefront, renewal rate, interrupted purchases, Apple Pay
ascelerate sandbox-testers update <email-or-id> [--territory X] [--interrupt-purchases true|false] [--renewal-rate 1h|30m|15m|5m|3m] [-y]  # Lists the changes, asks
ascelerate sandbox-testers clear-history <email-or-id>... | --all [-y]  # Clear purchase history (one request)
ascelerate diagnostics <app> [--build N] [--type hangs,launches,disk-writes] [--json]   # Signatures (App Store build by default)
ascelerate diagnostics logs <signature-id> [--frames N] [--json]  # Call stacks, ▶ blamed frame
ascelerate diagnostics metrics <app> [--build N] [--type launch,…] [--all] [--json]   # Per version, 50th/90th percentile; regressions first
ascelerate users [--json]                                         # Team: email, name, roles, apps, Certificates/IDs/Profiles access
ascelerate users info <email-or-id> [--json]
ascelerate users update <email-or-id> [--roles a,b] [--apps X,Y | --all-apps] [--provisioning true|false] [-y]   # Lists the changes, asks
ascelerate users remove <email-or-id> [-y]
ascelerate users invitations [--json]                             # Pending, with expiry
ascelerate users invite --email X --first-name X --last-name X --roles a,b [--apps X,Y] [--provisioning] [-y]   # Emailed at once
ascelerate users cancel-invitation <email-or-id> [-y]
ascelerate devices list [--name X] [--platform X] [--status X]   # List registered devices
ascelerate devices info [name-or-udid]                            # Device details (interactive picker if omitted)
ascelerate devices register [--name X] [--udid X] [--platform X] [-y]  # Register a new device (interactive if omitted)
ascelerate devices update [name-or-udid] [--name X] [--status X] [-y]  # Update device (interactive if omitted)
ascelerate certs list [--type X] [--display-name X]               # List signing certificates
ascelerate certs info [serial-or-name]                            # Certificate details (interactive picker if omitted)
ascelerate certs create [--type X] [--csr <file>] [--output X] [-y]  # Create certificate (interactive type picker if omitted)
ascelerate certs revoke [serial-number] [-y]                      # Revoke a certificate (interactive picker if omitted)
ascelerate bundle-ids list [--platform X] [--identifier X]        # List bundle identifiers
ascelerate bundle-ids info [identifier]                           # Bundle ID details with capabilities (interactive picker if omitted)
ascelerate bundle-ids register [--name X] [--identifier X] [--platform X] [-y]  # Register a bundle ID (interactive if omitted)
ascelerate bundle-ids update [identifier] [--name X] [-y]         # Rename a bundle ID (interactive if omitted)
ascelerate bundle-ids delete [identifier] [-y]                    # Delete a bundle ID (interactive picker if omitted)
ascelerate bundle-ids enable-capability [identifier] [--type X] [-y]   # Enable a capability (interactive if omitted)
ascelerate bundle-ids disable-capability [identifier] [-y]        # Disable a capability (interactive picker)
ascelerate profiles list [--name X] [--type X] [--state X]       # List provisioning profiles
ascelerate profiles info [name]                                   # Profile details (interactive picker if omitted)
ascelerate profiles download [name] [--output X]                  # Download profile (interactive picker if omitted)
ascelerate profiles create [--name X] [--type X] [--bundle-id X] [--certificates X] [--devices X] [--output X] [-y]  # Create a profile (interactive if omitted; --certificates all = all of matching family)
ascelerate profiles delete [name] [-y]                            # Delete a profile (interactive picker if omitted)
ascelerate profiles reissue [name] [--all] [--all-invalid] [--to-certs X] [--all-devices] [-y]  # Reissue profiles with latest cert (or specific certs)
ascelerate alias add [name]                                       # Add/update an alias (interactive app picker if name omitted)
ascelerate alias remove [name] [-y]                               # Remove an alias (interactive picker if name omitted)
ascelerate alias list                                             # List all aliases
ascelerate events list <bundle-id> [--state X]                    # List in-app events
ascelerate events info <bundle-id> <ref-or-id>                    # Event details + schedules + localizations
ascelerate events create <bundle-id> --reference-name X [--badge X] [--priority X] [--purpose X] [--deep-link URL] [--primary-locale X] [--territories USA,GBR] [--publish-start X] [--event-start X] [--event-end X] [-y]  # Create event
ascelerate events update <bundle-id> <ref-or-id> [--reference-name X] [--badge X|NONE] [--priority X] [--purpose X] [--territories X] [--publish-start X] [--event-start X] [--event-end X] [-y]  # Update event/schedule
ascelerate events delete <bundle-id> <ref-or-id> [-y]            # Delete event
ascelerate events localizations view <bundle-id> <ref-or-id>     # View event localizations
ascelerate events localizations export <bundle-id> <ref-or-id> [--output X]  # Export event localizations to JSON
ascelerate events localizations import <bundle-id> <ref-or-id> [--file X] [--verbose] [-y]  # Import event localizations from JSON
ascelerate events media list <bundle-id> <ref-or-id>             # List event card screenshots + video clips
ascelerate events media upload <bundle-id> <ref-or-id> --locale X --asset-type EVENT_CARD|EVENT_DETAILS_PAGE [--preview-frame X] <file> [-y]  # Upload screenshot/video clip
ascelerate events media delete <bundle-id> <ref-or-id> <media-id> [-y]  # Delete a screenshot or video clip
ascelerate product-pages list <bundle-id>                         # List custom product pages
ascelerate product-pages info <bundle-id> <name-or-id>            # Page versions + localizations
ascelerate product-pages create <bundle-id> --name X --locale X [--promotional-text X] [-y]  # Create page (compound: version + first locale)
ascelerate product-pages update <bundle-id> <name-or-id> [--name X] [--visible true|false] [-y]  # Rename / toggle visibility
ascelerate product-pages delete <bundle-id> <name-or-id> [-y]    # Delete page
ascelerate product-pages localizations view <bundle-id> <name-or-id>    # View page localizations
ascelerate product-pages localizations export <bundle-id> <name-or-id> [--output X]  # Export to JSON
ascelerate product-pages localizations import <bundle-id> <name-or-id> [--file X] [--verbose] [-y]  # Import promotional text from JSON
ascelerate product-pages media list <bundle-id> <name-or-id>     # List page screenshots + app previews
ascelerate product-pages media upload <bundle-id> <name-or-id> --locale X [--display-type APP_IPHONE_67 | --preview-type APP_IPHONE_67] <file> [--preview-frame X] [-y]  # Upload screenshot/preview (creates set); PRODUCT_PAGE_HEADER/APP_STORE_SEARCH_RESULTS/APP_IPHONE_DUO go through the asset library
ascelerate product-pages media delete <bundle-id> <name-or-id> <media-id> [-y]  # Delete a screenshot or app preview
ascelerate reviews list <bundle-id> [--rating N] [--territory X] [--sort recent|oldest|critical|best] [--unanswered] [--limit N] [--json]  # List customer reviews
ascelerate reviews info <review-id> [--json]                      # Full review text + developer response
ascelerate reviews respond <review-id> --body "X" [-y]           # Publish/replace developer response
ascelerate reviews delete-response <review-id> [-y]              # Delete developer response
ascelerate experiments [list] <bundle-id> [--json]                  # Product page optimization tests
ascelerate experiments info <bundle-id> <name-or-id> [--json]      # Test + treatments + localizations + media
ascelerate experiments create <bundle-id> --name X --traffic N [--platform ios] [--treatment X ...] [-y]  # Create (with up to 3 treatments)
ascelerate experiments update <bundle-id> <test> [--name X] [--traffic N] [-y]
ascelerate experiments delete <bundle-id> <test> [-y]
ascelerate experiments submit <bundle-id> <test> [-y]              # Submit for App Review (own submission, or added to an open draft)
ascelerate experiments start|stop <bundle-id> <test> [-y]          # PATCH started true/false
ascelerate experiments treatments add <bundle-id> <test> --name X [--app-icon X] [-y]
ascelerate experiments treatments update <bundle-id> <test> <treatment> [--name X] [--app-icon X] [-y]
ascelerate experiments treatments delete <bundle-id> <test> <treatment> [-y]
ascelerate experiments treatments remove-locale <bundle-id> <test> <treatment> --locale X [-y]
ascelerate experiments media list <bundle-id> <test> [--treatment X]
ascelerate experiments media upload <bundle-id> <test> <treatment> --locale X [--display-type X | --preview-type X] [--preview-frame X] <file> [-y]  # Creates the treatment locale if needed; PRODUCT_PAGE_HEADER/APP_STORE_SEARCH_RESULTS/APP_IPHONE_DUO via the asset library
ascelerate experiments media delete <bundle-id> <test> <media-id> [-y]
ascelerate game-center [status] <app> [--json]                    # On/off, counts, default leaderboard, group
ascelerate game-center enable <app> [-y]                          # Turn Game Center on (the API can't turn it off)
ascelerate game-center version <app> [--version X] [--platform X] [--enabled true|false] [-y]  # The App Store version's Game Center switch
ascelerate game-center achievements [list] <app> [--json]         # Display order, points total
ascelerate game-center achievements info <app> <ach> [--json]
ascelerate game-center achievements create <app> --id X --name X --points N [--hidden] [--repeatable] [-y]
ascelerate game-center achievements update <app> <ach> [--name X] [--points N] [--hidden B] [--repeatable B] [--archived B] [-y]
ascelerate game-center leaderboards [list|info] <app> [<lb>] [--json]
ascelerate game-center leaderboards create <app> --id X --name X [--formatter X] [--sort high|low] [--submission best|recent] [--min X] [--max X] [--recurrence-start ISO] [--recurrence-duration PT…] [--recurrence-rule X] [--hidden B] [-y]
ascelerate game-center leaderboards update <app> <lb> [same options] [--name X] [--archived B] [-y]   # "" clears range/recurrence
ascelerate game-center leaderboards default <app> <lb> [-y]
ascelerate game-center sets [list] <app> [--json]
ascelerate game-center sets create <app> --id X --name X [--leaderboards a,b] [-y]
ascelerate game-center sets update <app> <set> [--name X] [--leaderboards a,b] [-y]
ascelerate game-center activities [list|info] <app> [<act>] [--json]
ascelerate game-center activities create <app> --id X --name X [--play-style sync|async] [--min-players N] [--max-players N] [--party-code B] [--properties k=v,…] [--fallback-url URL] [-y]
ascelerate game-center activities update <app> <act> [same options] [--name X] [--archived B] [-y]
ascelerate game-center activities link <app> <act> [--achievements a,b] [--leaderboards a,b] [--remove] [-y]
ascelerate game-center challenges [list|info] <app> [<ch>] [--json]
ascelerate game-center challenges create <app> --id X --name X --leaderboard LB [--repeatable] [-y]
ascelerate game-center challenges update <app> <ch> [--name X] [--leaderboard LB] [--repeatable B] [--archived B] [-y]
ascelerate game-center achievements|leaderboards|sets reorder <app> a,b [-y]
ascelerate game-center achievements|leaderboards|sets|activities|challenges delete|submit <app> <item> [-y]   # submit: adds the latest version to the draft submission
ascelerate game-center <kind> localizations [view|set|export|import|delete] <app> <item> [--locale X] [--file X] [-y]
ascelerate game-center <kind> image upload|delete <app> <item> (--locale X | --default) [file] [-y]   # --default: activities/challenges
ascelerate game-center groups [list|create|rename|delete] ... [--json] [-y]          # Team-wide groups with their apps
ascelerate game-center groups add-app <group> <app> [-y]                          # Permanent; only ever dry-run it on our apps
ascelerate game-center matchmaking [rule-sets [list|info|create|update|delete]] [--json]   # Team-wide rule sets (players, rules, teams, queues)
ascelerate game-center matchmaking rules add|update|delete <set> ... [-y]          # --type compatible|distance|match|team --expression X --description X [--weight N]
ascelerate game-center matchmaking teams add|update|delete <set> ... [-y]          # --name X --min N --max N
ascelerate game-center matchmaking queues [list|create|update|delete] ... [-y]     # --rule-set X [--experiment-rule-set X|none] [--classic-apps a,b|none]
ascelerate game-center matchmaking test <set> --file requests.json [--json]        # Apple's rule set test: the matches and teams it would make
ascelerate nominations [list] [--app X] [--state draft|submitted|archived] [--json]  # Featuring nominations (all states by default)
ascelerate nominations create --app X [--app Y] --type launch|enhancements|new-content --name X --description X --publish-start YYYY-MM-DD [--publish-end X] [--devices iphone,ipad] [--locales en-US,tr-TR] [--territories USA,TUR] [--notes X] [--materials URL,URL] [--pre-order] [--submit] [-y]  # Create (draft unless --submit)
ascelerate nominations update <id> [--name X] [--description X] [--type X] [--publish-start X] [--publish-end X] [--devices X] [--locales X] [--notes X] [--materials X] [-y]  # Change a draft
ascelerate nominations submit|archive|delete <id> [-y]           # Submit a draft to Apple / archive / delete
ascelerate webhooks [list] <bundle-id> [--json]                    # App Store Connect webhooks of an app
ascelerate webhooks create <bundle-id> --name X --url URL --events a,b|all [--secret X] [--disabled] [-y]  # Create (random secret printed once if --secret omitted)
ascelerate webhooks update <bundle-id> <name-or-id> [--name X] [--url X] [--events X] [--secret X] [--enabled true|false] [-y]
ascelerate webhooks delete <bundle-id> <name-or-id> [-y]
ascelerate webhooks ping <bundle-id> <name-or-id>                  # Send a test event
ascelerate webhooks deliveries <bundle-id> <name-or-id> [--state succeeded|failed|pending] [--limit N] [--json]  # Recent deliveries, HTTP status, errors
ascelerate webhooks redeliver <delivery-id> [-y]                   # Send a delivery's event again
ascelerate xcode-cloud products [--json]                           # Xcode Cloud products (apps and frameworks; made in Xcode)
ascelerate xcode-cloud workflows <product> [--json]                # Workflows (product: bundle ID/alias, name or ID)
ascelerate xcode-cloud workflows info <product> <workflow> [--json]   # Start conditions, actions, repository, Xcode/macOS
ascelerate xcode-cloud workflows enable|disable|delete <product> <workflow> [-y]
ascelerate xcode-cloud workflows update <product> <workflow> [--manual-only] [--name X] [--description X] [--clean true|false] [--restrict-editing true|false] [--xcode X] [--macos X] [--branch-changes|--tag-changes|--pull-requests|--manual-branches|--manual-tags|--manual-pull-requests NAMES|any|off] [--pull-request-source X] [--auto-cancel true|false] [--remove-schedule] [--action TYPE:SCHEME[:PLATFORM]]... [--distribution internal|app-store|none] [-y]   # XcodeCloud.edit/save: lists the changes, asks; start conditions go as a set
ascelerate xcode-cloud workflows create <product> [--like <workflow>] --name X [same options as update] [--disabled] [-y]   # XcodeCloud.createWorkflow: a copy of a workflow (always one: Xcode makes the product with it)
ascelerate xcode-cloud runs <product> [--workflow X] [--limit N] [--json]   # Build runs, newest first
ascelerate xcode-cloud runs info|issues|tests|artifacts <product> <number> [--errors|--failed|--type X --download DIR] [--json]   # info: + the build it uploaded (XcodeCloud.builds(runID:): the run's builds endpoint gives only IDs, seen 2026-11-04, so each is read with Builds.build)
ascelerate xcode-cloud runs logs <product> <number> [--action X] [--show FILE]   # Each action's log bundle (ZipReader): list, or print one
ascelerate xcode-cloud start <product> <workflow> [--branch X | --tag X | --pull-request N] [--clean] [-y]
ascelerate xcode-cloud rerun <product> <number> [--clean] [-y]      # Same commit and workflow again
ascelerate xcode-cloud repositories|xcode-versions [--json]
ascelerate testflight groups list <bundle-id>                     # List beta groups
ascelerate testflight groups info <bundle-id> [group-name]        # Group details + testers + assigned builds
ascelerate testflight groups create <bundle-id> --name X [--internal] [--all-builds] [--public-link] [--public-link-limit N] [--feedback true|false] [-y]  # Create beta group
ascelerate testflight groups update <bundle-id> [group-name] [--name X] [--public-link true|false] [--public-link-limit N] [--feedback true|false] [--mac true|false] [--vision-pro true|false] [-y]  # Update group (limit 0 removes the limit; --mac/--vision-pro: iOS builds on Apple silicon Macs/Vision Pro)
ascelerate testflight groups delete <bundle-id> [group-name] [-y] # Delete beta group
ascelerate testflight groups add-build <bundle-id> [group-name] [--build N] [--platform X] [-y]     # Give group access to a build
ascelerate testflight groups remove-build <bundle-id> [group-name] [--build N] [--platform X] [-y]  # Remove a build from a group
ascelerate testflight groups criteria view <bundle-id> [group-name] [--options]  # View public-link recruitment criteria (+available device/OS options)
ascelerate testflight groups criteria set <bundle-id> [group-name] --filter FAMILY[:MIN[:MAX]] ... [-y]  # Replace existing recruitment criteria (new ones can no longer be added)
ascelerate testflight groups criteria clear <bundle-id> [group-name] [-y]  # Remove recruitment criteria
ascelerate testflight testers list <bundle-id> [--group X] [--email X]  # List beta testers
ascelerate testflight testers add <bundle-id> --email X [--first-name X] [--last-name X] --group X[,Y] [-y]  # Add tester to group(s)
ascelerate testflight testers remove <bundle-id> <email> [--group X] [-y]  # Remove from one group, or from the whole app if --group omitted
ascelerate testflight testers invite <bundle-id> <email> [-y]     # Re-send the invitation email
ascelerate testflight testers import <bundle-id> --file X.csv --group X[,Y] [-y]  # Bulk-add testers from CSV (email[,first[,last]])
ascelerate testflight builds <bundle-id> [--platform X] [--limit N] [--json]  # List builds with internal/external TestFlight states
ascelerate testflight versions <bundle-id> [--platform X] [--limit N]  # List pre-release version trains
ascelerate testflight expire <bundle-id> [--build N] [--platform X] [-y]  # Expire a build
ascelerate testflight notify <bundle-id> [--build N] [--platform X] [-y]  # Notify testers a build is available
ascelerate testflight auto-notify <bundle-id> --enabled true|false [--build N] [--platform X] [-y]  # Toggle automatic tester notification
ascelerate testflight what-to-test view <bundle-id> [--build N] [--platform X]  # View test notes (What to Test) per locale
ascelerate testflight what-to-test set <bundle-id> --text X [--locale X] [--build N] [--platform X] [-y]  # Set test notes (all existing locales if --locale omitted)
ascelerate testflight what-to-test copy <bundle-id> [--build N] [--from N] [--platform X] [-y]  # The newest earlier build's test notes (Builds.earlierTestNotes: the newest of the 20 builds before it with any text) to a build, every language
ascelerate testflight what-to-test export <bundle-id> [--build N] [--output X]  # Export test notes to JSON
ascelerate testflight what-to-test import <bundle-id> [--build N] [--file X] [-y]  # Import test notes from JSON
ascelerate testflight submit <bundle-id> [--build N] [--platform X] [-y]  # Submit build for beta review (external testing)
ascelerate testflight status <bundle-id> [--build N] [--platform X] [--json]  # Processing + internal/external + beta review states
ascelerate testflight app-info view <bundle-id>                   # View beta app information per locale
ascelerate testflight app-info update <bundle-id> [--locale X] [--description X] [--feedback-email X] [--marketing-url X] [--privacy-policy-url X] [-y]  # Update beta app information
ascelerate testflight app-info export <bundle-id> [--output X]    # Export beta app information to JSON
ascelerate testflight app-info import <bundle-id> [--file X] [-y] # Import beta app information from JSON
ascelerate testflight review-info <bundle-id> [--contact-first-name X] [--contact-last-name X] [--contact-phone X] [--contact-email X] [--demo-account-name X] [--demo-account-password X] [--demo-account-required true|false] [--notes X] [-y]  # View/update beta review information
ascelerate testflight eula <bundle-id> [--file X | --text X] [-y] # View/update beta license agreement (--text "" reverts to Apple's standard)
ascelerate testflight feedback crashes list <bundle-id> [--build N] [--platform X] [--limit N]  # List crash feedback
ascelerate testflight feedback crashes info <submission-id>       # Full crash feedback details
ascelerate testflight feedback crashes log <submission-id> [--output X]  # Print or save the crash log
ascelerate testflight feedback crashes delete <submission-id> [-y]  # Delete crash feedback
ascelerate testflight feedback screenshots list <bundle-id> [--build N] [--platform X] [--limit N]  # List screenshot feedback
ascelerate testflight feedback screenshots info <submission-id>   # Full screenshot feedback details
ascelerate testflight feedback screenshots download <bundle-id> [submission-id] [--output X.zip]  # Zip of screenshots + comment; paged interactive picker if ID omitted
ascelerate testflight feedback screenshots delete <submission-id> [-y]  # Delete screenshot feedback
ascelerate reports sales [--frequency DAILY|WEEKLY|MONTHLY|YEARLY] [--date X] [--type SALES] [--sub-type SUMMARY] [--bundle-id X] [--vendor-number X] [--output X] [--raw]  # Sales & Trends report (units/downloads); summarizes units by title/product type
ascelerate reports finance --date YYYY-MM --region US [--type FINANCIAL|FINANCE_DETAIL] [--vendor-number X] [--output X] [--raw]  # Financial report (units + partner proceeds) for a fiscal period
ascelerate reports analytics <bundle-id> [--category APP_STORE_ENGAGEMENT|APP_USAGE|COMMERCE|FRAMEWORK_USAGE|PERFORMANCE] [--granularity DAILY|WEEKLY|MONTHLY] [--report-name X] [--processing-date X] [--ongoing] [--output X] [-y]  # App Analytics report (downloads, impressions, sessions); reuses/creates a report request, downloads segments
ascelerate run-workflow [file] [--yes]                            # Run commands from a workflow file
ascelerate run-workflow <file> --check [--json]                   # Parse every step without running it
ascelerate run-workflow <file> --json-events [--yes]              # Events on stdout (steps, outcomes, prompts), readable output on stderr
ascelerate rate-limit [--json]                                    # Show API rate limit status
ascelerate install-skill [--all] [--uninstall]                    # Install/update the skill for detected AI agents (Claude Code+Grok Build/Cursor/Windsurf; +Copilot with --all)
ascelerate screenshot [--languages en-US,tr-TR]                   # Capture screenshots (optional language subset override)
ascelerate screenshot init                                        # Create ascelerate/screenshot.yml + ScreenshotHelper.swift
ascelerate screenshot create-helper [-o file]                     # Generate UITest helper file
ascelerate ads configure [--new-key]                              # Apple Ads API credentials: creates the key pair, prints the public key, picks the ad account
ascelerate ads accounts                                           # Ad accounts and roles of the API user
ascelerate ads campaigns list [--app X] [--json]                  # Campaigns with status, countries, daily budget, bidding
ascelerate ads campaigns pause|resume <campaign>... [-y]          # By name or ID
ascelerate ads campaigns create --name N (--app X | --like C) [--country CC...] --daily X (--max-conversions --bid X | --default-bid X [--search-match on|off]) [--enabled] [-y]  # Campaign + ad group, paused
ascelerate ads campaigns budget <campaign> --daily X [-y]         # Daily budget
ascelerate ads campaigns bid <campaign> --amount X [-y]           # Campaign bid (Max Conversions: per-auction ceiling); sends type+goal too
ascelerate ads adgroups [--app X] [--campaign X] [--json]         # Ad groups (default bid, CPA goal, Search Match)
ascelerate ads adgroups create --campaign X --name N [--like G] [--default-bid B] [--search-match on|off] [--cpa-goal G] [--min-age A] [--max-age A] [--enabled] [-y]  # Copy of G's settings/targeting, paused unless --enabled
ascelerate ads keywords copy --campaign X --from G --to G [--match M] [-y]  # Copy an ad group's keywords (text, match, bid, status)
ascelerate ads reports adgroups [same options as reports]         # Performance per ad group
ascelerate ads adgroups update <group> --campaign X [--name N] [--default-bid B] [--search-match on|off] [--cpa-goal G] [-y]
ascelerate ads adgroups pause|resume --campaign X <group>... [-y]
ascelerate ads opportunities [--app X] [--campaign X] [--days N | --from D --to D] [--min-taps N] [--json]  # Search terms to add/own-bid/exclude (default: last 30 complete days)
ascelerate ads keywords list [--app X] [--campaign X] [--json]
ascelerate ads keywords add --campaign X [--ad-group Y] --match exact|broad [--bid X] <kw>... [-y]
ascelerate ads keywords pause|resume|bid --campaign X [--ad-group Y] [--match M] [--bid X] <kw>... [-y]
ascelerate ads keywords suggest --app X [--seed T...] [--country C...] [--limit N] [--json]  # Apple's suggestions + where already targeted
ascelerate ads keywords popularity --country C... (--app X | --genre G) [--term T... | --contains T] [--monthly] [--json]
ascelerate ads negatives list|add|remove ...                      # Campaign- or ad group-level negative keywords
ascelerate ads reports campaigns|keywords|search-terms [--days N | --from D --to D] [--app X] [--campaign X] [--all] [--json]  # campaigns also: --by age gender device country region city
ascelerate ads insights impression-share --app X [--country C...] [--term T...] [--weeks 1-4] [--first-slot] [--json]
ascelerate ads recommendations [--app X] [--json]                 # Apple's open daily budget / target CPA recommendations
ascelerate ads recommendations apply|dismiss <id>... [-y]         # Apply (changes the campaign) or dismiss
ascelerate ads campaigns target-cpa --app X [--country CC...] [--json]  # Apple's suggested Max Conversions target CPA
ascelerate ads history [--app X] [--campaign X] [--days N | --from D --to D] [--json]  # Change history with old → new values
ascelerate ads product-pages --app X [--json]                     # Product pages Apple Ads can send taps to
ascelerate ads ads [--app X] [--campaign X] [--json]              # Ads (product page per ad group, review state)
ascelerate ads ads create --campaign X [--ad-group Y] --product-page <name|id|default> [--name N] [--enabled] [-y]  # Creative (reused if one exists) + ad
ascelerate ads ads pause|resume --campaign X <ad> [-y]            # Resume pauses the group's serving ad
ascelerate ads reports ads [same options as reports]              # Performance per ad / product page
ascelerate version [--json]                                       # Print version number (also: --version, -v); --json adds completions/skill status (current|outdated|missing|unsupported)
ascelerate update [--check] [-y]                                  # Update a GitHub-release install (not Homebrew's): digest + Developer ID (team GH4CGS3B5H) checked before replacing itself; sudo for /usr/local/bin
ascelerate <any command> --dry-run                                # Global: send reads, print writes instead of sending them (also: ASCELERATE_DRY_RUN=1)
```

## Key Patterns

### AscelerateCore
- **What:** App Store Connect logic the commands share, in its own target with no terminal I/O: no ArgumentParser, no `print`/`readLine`, no reads of `autoConfirm`/`jsonMode`/`dryRunFlag`. The `ascelerate` target keeps parsing, prompts, colours, aliases, tables and JSON rendering, and calls into the core. Areas still in the CLI move one at a time.
- **Rules:** a lookup that can be ambiguous takes a `choose: Choose<T>` closure (`findVersion`); the CLI wrapper of the same name passes `promptSelection` with its `--yes`/`--json` hint. Alias resolution stays in the CLI (`findApp(bundleID:)` → `resolveAlias` → `findApp(exactBundleID:)`). Errors are `LocalizedError`s, not `ValidationError`. Everything the commands use is `public`.
- **Moving code:** move it unchanged first, then adapt; verify with `Scripts/compare-with-release.sh` against the released binary (identical output and exit codes) plus `swift test`. A CLI file needs `import AscelerateCore` only when it uses a core symbol; the Ads files can import it (it doesn't re-export ASCKit).

### ASCKit (the App Store Connect client)
- **What:** a client generated by swift-openapi-generator from Apple's OpenAPI spec. `Scripts/prepare-asc-spec.swift` prepares the spec (schema string enums opened to `String`, error responses dropped, readable parameter names, spec fixes); only the paths under `filter.paths` in `openapi-generator-config.yaml` are generated; the output is committed in `Sources/ASCKit/Generated`, split into ~3,000-line files. The target builds with `-suppress-warnings` (the generated code references every deprecated item).
- **Adding a command:** add the endpoint paths to `filter.paths` and run `Scripts/update-asc-spec.sh --regenerate`, get a client with `ClientFactory.makeClient()`, and call the generated operation: `try await client.appsGetCollection(query: .init(filterBundleId: [id])).ok.body.json`, `.created.body.json` for a POST, `.noContent` for a DELETE. Request inits take their arguments in the spec's alphabetical order with `_type` last, and every relationship needs its `_type` (`.init(id: app.id, _type: "apps")`).
- **Updating the spec:** `Scripts/update-asc-spec.sh --check` (exit 1 when Apple's is newer), then `Scripts/update-asc-spec.sh` (prepare, generate, split); `--force` redoes the same version; a file argument prepares a downloaded `openapi.oas.json`. Then build and read the diff of `openapi.json`.
- **Enums:** write commands validate input with `parseEnum(value, name:) as ASCEnum.X` and send `.rawValue`; display raw values with `formatState(raw)`, never by interpolating the enum.
- **Helpers:** `ASCPaging.allPages` (any list operation), `ASCNulls.sending([...]) { … }` (send key paths as JSON null), `optionalRelated { … }` / `ASCError.isMissingRelated(_:)` (a missing to-one object), `ASCRateLimit.header(of:)`, `ASCError.from(_:)` and `ascUnderlyingError(_:)` (errors out of the runtime's `ClientError`), `withTransientRetry`, `unlessDryRunStopped`.
- **Dry run (`--dry-run` or `ASCELERATE_DRY_RUN=1`):** reads go out; every POST/PATCH/PUT/DELETE is printed to stderr and stopped with `ASCDryRunStop`. `--dry-run` is taken out of the command line before parsing (`extractDryRunFlag`, per workflow step too). A command with no confirmation prompt (`apps localizations update`, `apps create-version`, `apps phased-release --enable/--pause/--resume`) writes as soon as it runs, so only ever try those under dry run.
- **Hourly limit:** `RateLimitWaitMiddleware` waits out a 429's `Retry-After` and resends (one shared gate and notice; `ASCELERATE_MAX_RATE_LIMIT_WAIT` caps the total wait, `0` returns the first 429). `rate-limit` builds its client with `waitsForRateLimit: false`.
- **Other servers:** `Client.appStoreConnect(serverURL:headers:)` and `Ads.Options(server:headers:)` point the clients at a mock or proxy with the same paths.

### Adding a new subcommand
1. Add the command struct inside `AppsCommand` (or create a new command group)
2. Use `AsyncParsableCommand` for commands that call the API
3. Register in the appropriate `CommandGroup` in the parent's configuration (see below)
4. Use `findApp(bundleID:client:)` to resolve bundle ID or alias to app ID (CLI wrapper of the core's `findApp(exactBundleID:client:)`)
5. Use `findVersion(appID:versionString:platform:client:)` to resolve version (nil = prefers editable, prompts if multiple platforms; CLI wrapper passing `promptSelection` as the core's `choose`); version-scoped commands should add `@OptionGroup var platformOption: PlatformOption` and pass `platform: try platformOption.parsed()`
6. Use shared helpers: `formatDate()`, `formatState()` for enum display (AscelerateCore), `expandPath()`, color helpers (`green()`, `red()`, `yellow()`, `bold()`)
7. Run `ascelerate install-completions` to regenerate completions after adding commands

### Subcommand grouping
`AppsCommand` uses `CommandGroup` (swift-argument-parser 1.7+) to organize subcommands into sections in `--help` output:
- **ungrouped** (`subcommands:`): list, info, versions — general browse commands
- **Version**: create-version, copyright, build (attach, attach-latest, detach), phased-release, routing-coverage
- **Info & Content**: app-info (view, update, import, export, age-rating (view, export, import)), localizations (view, update, import, export), media (upload, download, verify)
- **Configuration**: availability, encryption, eula
- **Review**: review (preflight, status, submit, resolve-issues, cancel-submission, info, attachment)

When adding a new subcommand, place it in the appropriate `CommandGroup` or create a new one. Shell completions are alphabetically sorted by zsh — don't try to force custom ordering there.

### App aliases
- Aliases map short names to bundle IDs, stored in `~/.ascelerate/aliases.json`
- `resolveAlias()` in `Aliases.swift` is the single resolution function — if input contains no dots, look up in aliases
- `findApp()` in `AppsCommand.swift` calls `resolveAlias()` at the top — this covers all app, IAP, subscription, and build commands automatically
- Alias names must match `^[a-zA-Z0-9_-]+$` — no dots (dots distinguish real bundle IDs from aliases)
- `bundle-ids`, `profiles`, `devices`, `certs` commands do NOT resolve aliases (different domain)

### Version management
- **No `version:` on `CommandConfiguration`** — intentionally omitted. ArgumentParser leaks a root `--version` flag into every subcommand's completion function, which conflicts with subcommands that define their own `--version` option (e.g. `builds list --version`, `apps review status --version`).
- Version is stored as `static let appVersion` in `ASC.swift`.
- `ascelerate version` subcommand prints just the version number. `--version` and `-v` are intercepted in `main()` before ArgumentParser and produce the same output.
- `install-completions` stamps `# ascelerate vX.Y.Z` into completion scripts (after `#compdef` line for zsh) and `install-skill` stamps `<!-- ascelerate vX.Y.Z -->` into each installed skill file (across all targeted agents), right after its frontmatter (`InstallSkillCommand.stamped`): a stamp on the first line hid the frontmatter, and Claude Code showed the stamp as the skill's description (up to 0.34.0). The update-check (`skillVersionDetail()`) scans every installed agent path and only flags **stamped** skills (npx-installed ones are unstamped and skipped, so they don't false-positive). `install-skill` targets agents that are detected (`~/.claude` or `~/.grok` for the shared Claude Code/Grok Build entry, `~/.cursor`, `~/.windsurf`) or already have the skill; `--all` forces all four entries (incl. Copilot, which has no detectable dir). Grok Build reads the Claude Code skill path natively, so both share one entry/target file.
- `checkForUpdates()` (non-interactive, API commands; skipped under `--json`, `--json-events` and `-y`, whose output a program reads) and `checkForUpdatesInteractively()` (bare invocation) detect outdated completions and/or skill, offering a single Y/n prompt or NOTE line. The version compare uses `isVersionOlder()` (numeric, component-wise) and only flags a stamp that is **strictly older** than the running binary — so an older `ascelerate` earlier in PATH never offers to *downgrade* completions/skill that a newer build installed.
- Both `install-skill` and the npx installer (`npx ascelerate-skill`) fetch `SKILL.md` from GitHub — the skill content is NOT embedded in the binary. `skills/ascelerate/SKILL.md` in the repo is the single source of truth.

### Shell completions (`install-completions`)
- ArgumentParser's generated completion scripts need post-processing:
  - **`#compdef` must be line 1** in zsh completion files — never prepend content before it or compinit won't recognize the file.
  - `patchZshHelpCompletions` / `patchBashHelpCompletions` — fix `ascelerate help <tab>` to list subcommands (ArgumentParser generates a broken/empty help function).
  - `-V` flag removed from all `_describe` calls so zsh sorts completions alphabetically.
- **Argument-level completions** via ArgumentParser's `completion:` parameter:
  - `.file(extensions:)` — file path completion filtered by extension (e.g. `.json`, `.workflow`, `.ipa`)
  - `.shellCommand()` — dynamic completions from a shell command (used for alias names from `~/.ascelerate/aliases.json`)
  - Bundle ID arguments use `.shellCommand("grep ...")` to extract alias keys from the aliases JSON file
  - File arguments use `.file(extensions: ["json"])`, `.file(extensions: ["workflow", "txt"])`, etc.

### Interactive mode
- Most provisioning commands (devices, certs, bundle-ids, profiles) support interactive mode — arguments and options are optional.
- When omitted, commands prompt with numbered lists fetched from the API (e.g. bundle ID picker, certificate picker, profile type selection).
- Text inputs use a recursive `promptText()` that retries on empty input, throws on stdin EOF, and throws under `--yes` (interactive input can't be auto-confirmed).
- `promptSelection`/`promptMultiSelection` refuse under `--yes` instead of auto-picking; `promptSelection` takes a `nonInteractiveHint` (e.g. "Pass --platform to disambiguate.") shown in that error.
- Selection lists use `[\(i + 1)]` numbering, `readLine()` input, `Int()` parsing, and range validation.
- `--yes` / `autoConfirm` is incompatible with interactive mode — commands throw `ValidationError` when required options are missing with `--yes`.
- `enable-capability` filters the type picker to exclude already-enabled capabilities; `disable-capability` only shows enabled ones.
- `enable-capability` and `disable-capability` offer to regenerate provisioning profiles after changes (delete + recreate with same settings) via `regenerateProfilesIfNeeded()` helper in BundleIDsCommand.swift.

### JSON output (`--json`)
- Read commands can offer machine-readable output via the shared `JSONOption` option group (Formatting.swift): add `@OptionGroup var jsonOption: JSONOption`, call `jsonOption.activate()` at the top of `run()`.
- Pattern: build a private `Encodable` result struct FIRST (fetch everything, no printing), then branch — `if jsonOption.json { try printJSON(result); return }` — and render the text/table output from the same struct. One data assembly, two renderers.
- JSON conventions (LOCKED — the skill/docs advertise this shape, don't break it): list commands emit a bare top-level ARRAY of objects; detail commands emit a single top-level OBJECT. Every object representing an API resource carries its `id`. Raw API enum values (`WAITING_FOR_REVIEW`, `IOS`), ISO 8601 dates (`Date` fields + `printJSON`'s `.iso8601` strategy), sorted keys, `nil` fields omitted (synthesized `Encodable`), empty results emit `[]` — never prose like "No reviews found." Warnings the text UI prints as prose become explicit booleans (e.g. `hasPricing`).
- Text rendering from raw values: `formatFieldName` handles single all-caps words ("MANUAL" → "Manual") and has raw-value overrides for platforms ("IOS" → "iOS", "MAC_OS" → "macOS", …) — so `formatState(rawString)` renders the same as the old enum-based path.
- `--json` implies non-interactive: it sets the global `jsonMode` (mirror of `autoConfirm`); `promptText`/`promptSelection`/`promptMultiSelection` refuse with the `--json` flag named in the error. `run-workflow` restores `jsonMode` after each step like `autoConfirm`. Errors go to stderr (central handler), so stdout stays parseable.
- Currently on: `apps list/info/versions`, `apps review preflight/status`, `builds list`, `reviews list/info` (list includes full review bodies + developer responses, saving per-review `info` calls), `testflight builds/status`, `rate-limit`, `iap list/info`, `sub groups/list/info`, `iap pricing show`, `sub pricing show`. Fan out to other read commands using the same pattern; `--json` is not for write commands.
- `apps review preflight --json` emits `{versionID, version, platform, state, passed, checks: [{group?, name, passed, detail}]}` — `group` is nil for top-level checks, a locale code for per-locale checks, or the `inAppPurchases`/`subscriptions` sentinels; the text table (group headers, indentation) is rendered FROM this model, and the exit code stays non-zero on failures in both modes (CI gate). Progress messages ("Checking build...") are suppressed under `--json`. A product in `DEVELOPER_REMOVED_FROM_SALE` is a deliberate choice: its check is `passed: true` plus `skipped: true` (omitted otherwise), shown as a yellow – and counted as skipped in the result line; neither its state nor its prices are evaluated.
- `pricing show --json` is the rich per-territory view (price + currency + start date/preserved for subs) and deliberately does NOT mirror the `pricing export` JSON — export/import keep their own import-compatible format.
- Shared entry structs: `CustomerReviewsCommand.ReviewEntry` (list element + info object), `SubCommand.SubEntry` (sub groups nests it, sub list flattens it with a `group` ref). `ResolvedBuild` (TestFlightCommand) carries raw `platform`/`version` and derives the display `train`/`label` from them.

### Output formatting
- **ANSI colors** — `red()`, `green()`, `yellow()` (orange 208), `bold()` in Formatting.swift. Auto-disabled when stdout is not a terminal (`isatty` check). `stderrRed()` uses a separate `isStderrTerminal` check for error messages.
- **Colored output conventions** — `green()` for success verbs ("Created", "Updated", "Deleted", etc.), `yellow()` for "Cancelled.", `stderrRed("Error:")` in central error handler. `red()` for failure indicators (e.g. preflight ✗).
- **`formatFieldName()`** — converts camelCase (`whatsNew` → "What's New") and SCREAMING_SNAKE_CASE (`PREPARE_FOR_SUBMISSION` → "Prepare for Submission"; short words such as for/from/in stay lowercase unless first) to human-readable titles. Has override map for special cases (URL suffixes, OS names, `CANCELED` → "Cancelled").
- **`formatState()`** — generic wrapper: `formatFieldName("\(value)")`. Use for any enum/state value displayed to the user (e.g. `.map { formatState($0) }`). Applied globally across all command files for platform, status, type, and state fields.
- **`localeName()`** — resolves locale codes to human-readable names via `Locale.current.localizedString(forIdentifier:)` (e.g. `en-US` → `en-US (English (United States))`). Applied to all locale display across commands.
- **`parseEnum()`** — validates a string against a `RawRepresentable & CaseIterable` enum, returning the matched case or throwing `ValidationError` with valid values list. Use instead of inline `guard let X = T(rawValue: .uppercased())` blocks. `parseFilter()` wraps `parseEnum()` for optional API filter values (returns `[T]?`).
- **`fetchAll()`** — flattens already-fetched pages (`ASCPaging.allPages`) into a single array with an empty guard and optional sort. Used by `promptDevice()`, `promptCertificate()`, `promptBundleID()`, `promptProfile()`.
- **`resolveFile()`** — resolves a file path from an optional argument; lists matching files by extension in the current directory as a numbered picker, with manual path entry fallback. Used by `localizations import` and `app-info import`.
- **ANSI-aware Table** — `Table.print` uses `visibleLength()` (strips ANSI codes via regex) and `padToVisible()` for correct column alignment when cells contain colored text. All-empty rows (`["", ""]`) render as blank lines for visual grouping.

### Error handling
- `ASCClient.main()` overrides the default entry point to catch and format errors centrally.
- `ASCError`: rate limit (429, with the hourly limit and remaining requests), HTTP status codes (401/403/5xx) and Apple's error entries.
- `URLError` (unwrapped from the runtime's `ClientError` by `ascUnderlyingError`): connectivity issues (no internet, DNS, timeout, connection lost, TLS). Other wrapped failures print their underlying error, never the `ClientError` dump.
- `ASCDryRunStop`: a write blocked by `ASCELERATE_DRY_RUN=1`.

### Workflow files (used by run-workflow)
- **Events (`--json-events`):** `runWithEvents` keeps the original stdout for events (`EventOutput.eventDescriptor`) and points stdout at stderr for the run (`dup2`), so a step's partial lines (progress dots) can't run into an event line. Events: `workflow`, `step` (running, succeeded, failed, dry-run), `finished`, nested workflows with `depth`. The workflow isn't confirmed (the caller did). Every stdin read in the CLI goes through `readAnswer(_:kind:options:optional:)` (Formatting.swift), which in event mode prints the question as a whole line and emits a `prompt` event (kind confirm, choice, choices or text) before reading; never call `readLine()` directly. `--check` parses each step (ArgumentParser's message for one that doesn't, with its line). The steps' own command events (`builds upload`'s `finished`, the archive's and screenshot's) stay out of the workflow's stream (`EventOutput.inWorkflow`): a program took an upload's `finished` for the workflow's end. An `--api` upload's progress comes as the workflow's own `progress` event (step `index`, `sent`, `bytes`; `EventOutput.step`). A step whose xcodebuild or altool fails reports their error lines (`runReportingErrors` → `ToolFailure`; the output is still forwarded as it comes), and a bare `ExitCode` reads "The command ended with exit code N" (`describeError`).
- One command per line, without the `ascelerate` prefix
- Lines starting with `#` are comments, blank lines are ignored
- Quoted strings are respected for arguments with spaces (e.g. `--file "path with spaces.json"`)
- Without `--yes`: prompts once to confirm the workflow, then individual commands still prompt normally
- With `--yes`: sets `autoConfirm = true` globally, all prompts are skipped
- `autoConfirm` is restored after each step — a single step with `-y` (or a nested `run-workflow --yes`) must not auto-accept prompts in later steps of a non-`--yes` workflow
- Commands are dispatched via `ASCClient.parseAsRoot(args)` — any registered subcommand works
- Nested workflows supported (`run-workflow` can call another workflow file) with circular reference detection via `activeWorkflows` path stack
- `builds upload` records the uploaded build number **per platform** (`recordUploadedBuild`/`lastUploadedBuild(for:)` in Formatting.swift) — subsequent `await-processing` (via its `--platform`) and `build attach-latest` (via the target version's platform) target the just-uploaded build for the RIGHT platform, avoiding both API propagation races and cross-platform build-number mixups when one workflow uploads iOS and macOS. A platform-specific miss never falls back to another platform's number; only a platform-less lookup uses the most recent upload.

### Build processing
- `awaitBuildProcessing()` is a shared helper in `AppsCommand.swift` (alongside `findApp`/`findVersion`) — used by both `builds await-processing` and `build attach-latest`
- Recently uploaded builds may take a few minutes to appear in the API — the helper polls with a dot-based progress indicator until the build is found
- `build attach-latest` prompts to wait if the latest build is still `PROCESSING`; with `--yes` it waits automatically

### Apple Ads (`ads`, Apple Ads Platform API 1.0)
- The API logic lives in `AscelerateAds` (no terminal I/O, like AscelerateCore): `Ads.withClient(credentials, options:) { client in … }` builds Apple's `AppleAdsClient` with `Ads.Middleware` (errors as `AdsError`, 429 waits, read retries, the dry-run gate). The CLI's `Ads.withClient(ads)` extension reads the config's key and passes the dry-run gate and stderr notice. Core functions take the `X-AP-Context` value (`context:`); the CLI keeps overloads taking its `AdsConfig`.
- ASCKit and AppleAdsClient both generate top-level `Client`/`Components`/`Operations`, so **no file may import both**: App Store Connect lookups for ads live in `Ads/AdsASC.swift`.
- Writes confirm first (`-y` skips) and go through the same dry run as App Store Connect writes.

### Xcode signing
- `builds archive` and the `.xcarchive` → `.ipa`/`.pkg` export pass `-allowProvisioningUpdates` to `xcodebuild`, plus the `-authenticationKey…` flags when the API key comes from the environment.

### Price export JSON format (used by iap/sub pricing export/import)
```json
{
  "baseTerritory": "USA",
  "prices": { "USA": "4.99", "FRA": "5.99" }
}
```
- `baseTerritory` is present in IAP exports, omitted in subscription exports (sub import ignores it; IAP import falls back to the target's existing base, then USA)
- `PriceFile.decode` (core) reads prices as plain numbers: a decimal comma with one or two digits reads as a point ("4,99"), and anything else ("1,300", "4.99x") is refused with the prices named (`FileError.notNumbers`); before, "4,99" read as 4. The CLI's own import parses with `parseCustomerPrice` and refuses a comma.
- Import resolves each customer price against the **target** product's own tiers (exact match required, or with `--snap` the nearest tier, the cheaper of two as close, each snap listed before the confirmation (`PriceSnapping`, a task-local collector in `findPricePoint`); nearest tiers listed on mismatch, and `Mismatch.nearestTier` is the closest one, the cheaper of two as close, compared as decimals, for a client that snaps), so a file can be applied to any product in any app. Territory keys are normalized to uppercase on load.
- IAP import replaces the schedule wholesale — territories not in the file revert to auto-equalize; if the resulting schedule equals the current one it's a no-op. Sub import only touches listed territories, skips unchanged ones, and runs through the shared increase/decrease gates (`gateAndApplyPriceChanges`).

### Localization JSON format (used by export/update-localizations)
```json
{
  "en-US": {
    "description": "App description",
    "whatsNew": "- Bug fixes\n- New feature",
    "keywords": "keyword1,keyword2",
    "promotionalText": "Promo text",
    "marketingURL": "https://example.com",
    "supportURL": "https://example.com/support"
  }
}
```

Only fields present in the JSON get updated — omitted fields are left unchanged. The `LocaleFields` struct in AppsCommand.swift defines the schema.

### App info localization JSON format (used by app-info export/import)
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

Same convention — only fields present get updated. The `AppInfoLocaleFields` struct in AppsCommand.swift defines the schema. The `app-info update` and `app-info import` commands check that the AppInfo is in an editable state (`PREPARE_FOR_SUBMISSION`, `READY_FOR_REVIEW` or `WAITING_FOR_REVIEW`) before proceeding.

### Media upload folder structure (used by media upload)
```
media/
├── en-US/
│   ├── APP_IPHONE_67/
│   │   ├── 01_home.png
│   │   ├── 02_settings.png
│   │   └── preview.mp4
│   └── APP_IPAD_PRO_3GEN_129/
│       └── 01_home.png
└── de-DE/
    └── APP_IPHONE_67/
        └── 01_home.png
```

- Level 1: locale, Level 2: display type (ScreenshotDisplayType raw values), Level 3: files
- Images (`.png`, `.jpg`, `.jpeg`) → screenshot sets; Videos (`.mp4`, `.mov`) → preview sets
- Files sorted alphabetically = upload order
- Preview types derived by stripping `APP_` prefix; Watch/iMessage types are screenshots-only
- Upload flow: POST reserve → PUT chunks to presigned URLs → PATCH commit with MD5 checksum
- File matching: server position N = Nth file alphabetically in local `locale/displayType/` folder

## Screenshot Module (`ascelerate screenshot`)

Captures App Store screenshots from iOS/iPadOS simulators. Replaces fastlane snapshot.

### Architecture

```
Sources/ascelerate/
  Screenshot/
    ScreenshotConfig.swift       # YAML config model (via Yams), validation
    ScreenshotRunner.swift       # Orchestrator: build → boot simulators → run tests → collect
    ScreenshotTestRunner.swift   # xcodebuild wrapper: build-for-testing + test-without-building
    ScreenshotCollector.swift    # Moves PNGs from per-device cache to output dir
    SimulatorManager.swift       # xcrun simctl: boot, shutdown, erase, localize, status bar, dark mode
    ScreenshotShell.swift        # Process wrapper: run (capture), stream (passthrough), runToLog (to file)
    ScreenshotEvent.swift        # The --json-events event shapes (EventOutput.swift, shared with builds archive/upload, prints them)
    ScreenshotSetupPrompt.swift  # setup-prompt: project survey (projects, schemes from scheme files, UI test targets, knownRegions, simulators, config, helper) + the agent prompts
    ScreenshotError.swift        # Error types
  Commands/
    ScreenshotCommand.swift      # Subcommands: run, init, create-helper + embedded ScreenshotHelper.swift
```

### Config (`ascelerate/screenshot.yml`)

Config is decoded directly as `ScreenshotConfig` (no wrapper key). Created by `ascelerate screenshot init` in the `ascelerate/` directory.

```yaml
# project: App.xcodeproj
workspace: App.xcworkspace
scheme: AppUITests
devices:
  - simulator: iPhone 16 Pro Max
  - simulator: iPad Pro 13-inch (M4)
languages: [en-US, tr-TR]
outputDirectory: ./screenshots
clearPreviousScreenshots: true
eraseSimulator: false
localizeSimulator: true
# darkMode: false
# disableAnimations: false
# waitAfterBoot: 0
overrideStatusBar: true
# statusBarArguments: "--time '9:41' --dataNetwork wifi"
# configuration: Release
# testWithoutBuilding: true
# cleanBuild: false
# headless: false
# helperPath: AppUITests/ScreenshotHelper.swift
# testplan: MyTestPlan
# numberOfRetries: 0
# stopAfterFirstError: false
# reinstallApp: com.example.MyApp
# disableAssetDownloads: true
# xcargs: -resultBundlePath ./results
```

### Flow

1. `build-for-testing` with `generic/platform=iOS Simulator` and `-configuration` (default Release)
2. xcodebuild writes to project's actual derived data (custom `-derivedDataPath` is ignored by Xcode workspace settings)
3. Resolve xctestrun file from `~/Library/Developer/Xcode/DerivedData/{ProjectName}[-hash]/Build/Products/`
4. For each language: boot all simulators → silence system noise (see below) → wait (`waitAfterBoot`) → set dark mode → localize → override status bar → uninstall app (`reinstallApp`) → `test-without-building` concurrently per device → collect screenshots
5. Each device gets isolated cache at `~/Library/Caches/tools.ascelerate/{UDID}/`
6. ScreenshotHelper.swift uses `SIMULATOR_UDID` env var to find its cache directory
7. Errors skip failing device/language, error logs saved as `{language}/{device}-error.log` (unless `stopAfterFirstError`)
8. Summary table printed at end

### Commands

```
ascelerate screenshot [-l en-US,tr-TR] [--json-events]  # Capture screenshots (optionally a subset of configured languages; events: JSON Lines on stdout, log on stderr)
ascelerate screenshot init [-y]               # Create ascelerate/screenshot.yml + ScreenshotHelper.swift
ascelerate screenshot create-helper [-o file] [-y]  # Generate ScreenshotHelper.swift (default: ascelerate/)
ascelerate screenshot doctor [--json]         # Check the configuration and environment
ascelerate screenshot setup-prompt [--design] [--copy]  # Print a coding agent's setup instructions for this project (or a design generator's)
```

## Website (`website/`)

Docusaurus 3 docs site (ascelerate.dev), 6 locales (en/de/es/fr/ja/tr, translations under `website/i18n/`), deployed via git-integrated **Cloudflare Pages** building from `main` (root `website/`, output `build/`). No local deploy step — pushing to `main` deploys.

### Markdown for agents (2026-08)

Every docs page has a `.md` twin served via `Accept: text/markdown` content negotiation (same workspace-wide pattern as the sites under `~/Developer/Web` — see that workspace's CLAUDE.md; reference implementation: keremerkan.dev):

- `website/scripts/generate-md-twins.mjs` copies all docs source `.md` files (all 6 locales) into the build output at their route paths (`/docs/<page>.md`, `/de/docs/<page>.md`, …). It runs as part of `npm run build` — **the Pages build command must stay `npm run build`**, not `docusaurus build`, or twins won't generate.
- `website/functions/_middleware.js` (Cloudflare Pages Function) does the negotiation: markdown-accepting requests get the twin with `Content-Type: text/markdown; charset=utf-8`; HTML responses get `Vary: Accept`. Pages HTML is never edge-cached, so there is no Vary/cache-poisoning risk here.
- `website/static/index.md` is the **hand-written** homepage twin — update it when the homepage copy in `src/pages/index.tsx` changes. Docs twins are verbatim source and need no maintenance.
- `website/scripts/generate-agent-skills.mjs` (also in `npm run build`) publishes the repo's `skills/*/SKILL.md` files at `/.well-known/agent-skills/` with an `index.json` manifest (Agent Skills discovery convention) — sourced from the repo's skills, so they can't drift.
- `website/static/robots.txt` carries `Content-Signal: ai-train=yes, search=yes, ai-input=yes`. The zone's Cloudflare **managed robots.txt is deliberately disabled** (it declared ai-train=no and blocked AI crawlers, which is counterproductive for a developer tool) — don't re-enable it.

## Release build note

`swift build -c release` took about 7 minutes from a cold cache with the generator as a build plugin (measured 2026-10-07); with the client committed and split, 6 minutes (2026-10-30; ASCKit alone takes under 3 of them). The stripped binary is ~41 MB (0.21.0 with asc-swift: ~74 MB). Adding a path to `filter.paths` takes a regeneration (`Scripts/update-asc-spec.sh --regenerate`, about a minute).


<claude-mem-context>
# Recent Activity

<!-- This section is auto-generated by claude-mem. Edit content outside the tags. -->

*No recent activity*
</claude-mem-context>
