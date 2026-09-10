# ascelerate

A command-line tool for the App Store Connect API, built with Swift.

## Build & Run

```bash
swift build                           # Debug build
swift build -c release                # Release build (slow — AppStoreAPI has ~2500 generated files)
swift run ascelerate <command>        # Run directly
swift run ascelerate --help           # Show all commands
```

Install globally:
```bash
strip .build/release/ascelerate              # Strip debug symbols (~175 MB → ~59 MB)
cp .build/release/ascelerate /usr/local/bin/
```

## Project Structure

```
Package.swift                         # SPM manifest (Swift 6.0, macOS 13+)
Sources/ascelerate/
  Ascelerate.swift                    # @main entry, root AsyncParsableCommand, central error handling
  Config.swift                        # ~/.ascelerate/config.json loader, ConfigError
  ClientFactory.swift                 # Creates authenticated AppStoreConnectClient
  Formatting.swift                    # Shared helpers: Table.print, ANSI colors, formatFieldName/formatState, formatDate, expandPath
  Aliases.swift                        # Alias storage (~/.ascelerate/aliases.json), resolveAlias()
  MediaUpload.swift                   # Media management: upload, download, retry screenshots/previews
  ProductAvailability.swift           # Shared driver for iap/sub availability commands
  ProductMedia.swift                  # Shared drivers for iap/sub images, review-screenshot, offer-code view-codes
  Reports.swift                       # Shared report plumbing: gunzip (gzip -dc), TSV parse, vendor-number resolve, sales/finance summarizers
  Commands/
    ConfigureCommand.swift            # Interactive credential setup, file permissions
    AppsCommand.swift                 # All app subcommands + findApp/findVersion helpers
    BuildsCommand.swift               # Build subcommands
    IAPCommand.swift                  # In-app purchase subcommands
    SubCommand.swift                 # Subscription subcommands
    CustomerReviewsCommand.swift      # Customer reviews + developer responses (list, info, respond, delete-response)
    AppEventsCommand.swift            # In-app events: CRUD + scheduling + localizations + media (screenshots/video clips); findAppEvent helper
    ProductPagesCommand.swift         # Custom product pages: CRUD (compound create) + localizations + media (screenshot/preview sets); findProductPage helper
    DevicesCommand.swift              # Device management subcommands + findDevice helper
    CertsCommand.swift                # Signing certificate subcommands + findCertificate helper
    BundleIDsCommand.swift            # Bundle identifier subcommands + findBundleID helper
    ProfilesCommand.swift             # Provisioning profile subcommands + findProfile helper
    AliasCommand.swift                # Alias management (add, remove, list) for bundle ID shortcuts
    RunWorkflowCommand.swift          # Sequential command runner from workflow files
    InstallCompletionsCommand.swift   # Shell completion installer with post-processing patches
    InstallSkillCommand.swift         # Multi-agent skill installer (Claude Code+Grok Build/Cursor/Windsurf/Copilot; fetches from GitHub)
    RateLimitCommand.swift            # API rate limit status check
    TestFlightCommand.swift           # TestFlight: beta groups, testers, build states, What to Test, beta review; findBetaGroup/findBuild helpers
    ReportsCommand.swift              # Sales/Finance/Analytics report downloads (reports sales/finance/analytics)
skills/
  ascelerate/SKILL.md                # AI coding skill (single source of truth)
  package.json                        # npm package for npx installer
  bin/install.js                      # npx installer (fetches SKILL.md from GitHub)
```

## Dependencies

- **[asc-swift](https://github.com/aaronsky/asc-swift)** (1.0.0+) — App Store Connect API client
  - Product used: `AppStoreConnect` (bundles both `AppStoreConnect` core and `AppStoreAPI` endpoints)
  - `AppStoreAPI` is a target, NOT a separate product — do not add it to Package.swift dependencies
  - API path pattern: `Resources.v1.apps.get()`, `Resources.v1.apps.id("ID").appStoreVersions.get()`
  - Sub-resource access: `Resources.v1.appStoreVersions.id("ID").appStoreVersionLocalizations.get()`
  - Client is a Swift actor: `AppStoreConnectClient`
  - Pagination: `for try await page in client.pages(request)`
  - Resolved version: 1.5.0 (with swift-crypto, URLQueryEncoder, swift-asn1 as transitive deps)
- **[swift-argument-parser](https://github.com/apple/swift-argument-parser)** (1.3.0+) — CLI framework
- **[swift-certificates](https://github.com/apple/swift-certificates)** (1.0.0+) — X.509 certificate and CSR generation (used by `certs create` auto-CSR flow)
- **[Yams](https://github.com/jpsim/Yams)** (5.0.0+) — YAML parsing (used by `screenshot` command for `ascelerate.yml`)

## Authentication

Config file at `~/.ascelerate/config.json`:
```json
{
    "keyId": "KEY_ID",
    "issuerId": "ISSUER_ID",
    "privateKeyPath": "/Users/.../.ascelerate/AuthKey_XXXXXXXXXX.p8",
    "vendorNumber": "80012345"
}
```

- `configure` command copies the .p8 file into `~/.ascelerate/` and writes the config
- `vendorNumber` is **optional** — only the `reports sales`/`reports finance` commands use it (App Store Connect → Payments and Financial Reports). `configure` prompts for it (skippable); `--vendor-number` overrides per-invocation. Resolved by `Reports.resolveVendorNumber()`.
- File permissions set to 700 (dir) and 600 (files) — owner-only access
- JWT tokens use ES256 (P256) signing, 20-minute expiry, auto-renewed by asc-swift
- Private key loaded via `JWT.PrivateKey(contentsOf: URL(fileURLWithPath: path))`

## Commands

```
ascelerate configure                                              # Interactive setup
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
ascelerate apps review submit <bundle-id> [--version X]            # Submit version for App Review
ascelerate apps review resolve-issues <bundle-id> [--platform X]  # Mark rejected items as resolved
ascelerate apps review cancel-submission <bundle-id> [--platform X]  # Cancel an active review submission
ascelerate apps review info <bundle-id> [--version X] [--platform X] [--contact-first-name X] [--contact-last-name X] [--contact-phone X] [--contact-email X] [--demo-account-name X] [--demo-account-password X] [--demo-account-required true|false] [--notes X] [-y]  # View/update App Review Information
ascelerate apps review attachment list <bundle-id> [--version X] [--platform X]              # List App Review attachment files
ascelerate apps review attachment upload <bundle-id> [--version X] [--platform X] <file> [-y]  # Upload an App Review attachment
ascelerate apps review attachment delete <attachment-id> [-y]               # Delete an App Review attachment
ascelerate apps media upload <bundle-id> [folder] [--version X] [--platform X] [--replace]  # Upload screenshots/previews
ascelerate apps media download <bundle-id> [--folder X] [--version X] [--platform X]        # Download screenshots/previews
ascelerate apps media verify <bundle-id> [--version X] [--platform X] [folder]              # Check media status, retry stuck
ascelerate apps media prune <bundle-id> [folder] [--version X] [--platform X] [-y]          # Delete server sets with no matching local folder
ascelerate apps app-info view <bundle-id>                         # View app info, categories, and localizations
ascelerate apps app-info view --list-categories                   # List available category IDs
ascelerate apps app-info update <bundle-id> [--name X] [--subtitle X] [--primary-category X] [-y]  # Update localization fields and/or categories
ascelerate apps app-info import <bundle-id> [--file X] [--verbose] [-y]  # Bulk update localizations from JSON
ascelerate apps app-info export <bundle-id> [--output X]          # Export localizations to JSON
ascelerate apps availability <bundle-id> [--add X] [--remove X]  # View/update territory availability
ascelerate apps encryption <bundle-id> [--create]                 # View/create encryption declarations
ascelerate apps eula <bundle-id> [--file X] [--delete]            # View/manage custom EULA
ascelerate apps subscription-grace-period <bundle-id> [--opt-in true|false] [--sandbox-opt-in true|false] [--duration X] [--renewal-type X] [-y]  # View/update app-level subscription grace period
ascelerate builds list [--bundle-id <id>] [--version X] [--platform X] [--json]  # List builds
ascelerate builds archive [--workspace X] [--scheme X] [--output X]  # Archive Xcode project
ascelerate builds upload [file]                                   # Upload build via altool
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
ascelerate iap pricing import <bundle-id> <product-id> [--file X] [--start-date X] [-y]  # Apply exported schedule (wholesale replace; matches by customer price)
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
ascelerate sub pricing import <bundle-id> <product-id> [--file X] [--start-date X] [--preserve-current|--no-preserve-current] [--confirm-decrease] [-y]  # Apply exported prices (same increase/decrease safety as pricing set)
ascelerate sub availability <bundle-id> <product-id> [--add X] [--remove X] [--available-in-new-territories true|false] [-y]  # View/update per-subscription territory availability
ascelerate sub intro-offer list <bundle-id> <product-id>          # List intro offers (free trials, intro discounts)
ascelerate sub intro-offer create <bundle-id> <product-id> --mode FREE_TRIAL|PAY_AS_YOU_GO|PAY_UP_FRONT --duration X --periods N [--territory USA] [--price 4.99] [--start-date Y] [--end-date Y] [-y]  # Create intro offer
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
ascelerate sub submit-group <bundle-id> [-y]                      # Submit a subscription group for review (mirror of `sub submit`)
ascelerate sub images list <bundle-id> <product-id>               # List uploaded promotional images
ascelerate sub images upload <bundle-id> <product-id> <file> [-y] # Upload image (3-step reserve/PUT/commit)
ascelerate sub images delete <bundle-id> <product-id> <image-id> [-y]  # Delete an image
ascelerate sub review-screenshot view <bundle-id> <product-id>    # Show current App Review screenshot
ascelerate sub review-screenshot upload <bundle-id> <product-id> <file> [-y]  # Upload (replaces existing)
ascelerate sub review-screenshot delete <bundle-id> <product-id> [-y]  # Delete
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
ascelerate product-pages media upload <bundle-id> <name-or-id> --locale X [--display-type APP_IPHONE_67 | --preview-type APP_IPHONE_67] <file> [--preview-frame X] [-y]  # Upload screenshot/preview (creates set)
ascelerate product-pages media delete <bundle-id> <name-or-id> <media-id> [-y]  # Delete a screenshot or app preview
ascelerate reviews list <bundle-id> [--rating N] [--territory X] [--sort recent|oldest|critical|best] [--unanswered] [--limit N] [--json]  # List customer reviews
ascelerate reviews info <review-id> [--json]                      # Full review text + developer response
ascelerate reviews respond <review-id> --body "X" [-y]           # Publish/replace developer response
ascelerate reviews delete-response <review-id> [-y]              # Delete developer response
ascelerate testflight groups list <bundle-id>                     # List beta groups
ascelerate testflight groups info <bundle-id> [group-name]        # Group details + testers + assigned builds
ascelerate testflight groups create <bundle-id> --name X [--internal] [--all-builds] [--public-link] [--public-link-limit N] [--feedback true|false] [-y]  # Create beta group
ascelerate testflight groups update <bundle-id> [group-name] [--name X] [--public-link true|false] [--public-link-limit N] [--feedback true|false] [-y]  # Update group (limit 0 removes the limit)
ascelerate testflight groups delete <bundle-id> [group-name] [-y] # Delete beta group
ascelerate testflight groups add-build <bundle-id> [group-name] [--build N] [--platform X] [-y]     # Give group access to a build
ascelerate testflight groups remove-build <bundle-id> [group-name] [--build N] [--platform X] [-y]  # Remove a build from a group
ascelerate testflight groups criteria view <bundle-id> [group-name] [--options]  # View public-link recruitment criteria (+available device/OS options)
ascelerate testflight groups criteria set <bundle-id> [group-name] --filter FAMILY[:MIN[:MAX]] ... [-y]  # Set recruitment criteria (replaces existing)
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
ascelerate testflight whats-new view <bundle-id> [--build N] [--platform X]  # View test notes (What to Test) per locale
ascelerate testflight whats-new set <bundle-id> --text X [--locale X] [--build N] [--platform X] [-y]  # Set test notes (all existing locales if --locale omitted)
ascelerate testflight whats-new export <bundle-id> [--build N] [--output X]  # Export test notes to JSON
ascelerate testflight whats-new import <bundle-id> [--build N] [--file X] [-y]  # Import test notes from JSON
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
ascelerate rate-limit [--json]                                    # Show API rate limit status
ascelerate install-skill [--all] [--uninstall]                    # Install/update the skill for detected AI agents (Claude Code+Grok Build/Cursor/Windsurf; +Copilot with --all)
ascelerate screenshot [--languages en-US,tr-TR]                   # Capture screenshots (optional language subset override)
ascelerate screenshot init                                        # Create ascelerate/screenshot.yml + ScreenshotHelper.swift
ascelerate screenshot create-helper [-o file]                     # Generate UITest helper file
ascelerate version                                                # Print version number (also: --version, -v)
```

## Key Patterns

### Adding a new subcommand
1. Add the command struct inside `AppsCommand` (or create a new command group)
2. Use `AsyncParsableCommand` for commands that call the API
3. Register in the appropriate `CommandGroup` in the parent's configuration (see below)
4. Use `findApp(bundleID:client:)` to resolve bundle ID to app ID
5. Use `findVersion(appID:versionString:platform:client:)` to resolve version (nil = prefers editable, prompts if multiple platforms); version-scoped commands should add `@OptionGroup var platformOption: PlatformOption` and pass `platform: try platformOption.parsed()`
6. Use shared helpers from Formatting.swift: `formatDate()`, `expandPath()`, `formatState()` for enum display, color helpers (`green()`, `red()`, `yellow()`, `bold()`)
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
- `install-completions` stamps `# ascelerate vX.Y.Z` into completion scripts (after `#compdef` line for zsh) and `install-skill` stamps `<!-- ascelerate vX.Y.Z -->` into each installed skill file (across all targeted agents). The update-check (`skillVersionDetail()`) scans every installed agent path and only flags **stamped** skills (npx-installed ones are unstamped and skipped, so they don't false-positive). `install-skill` targets agents that are detected (`~/.claude` or `~/.grok` for the shared Claude Code/Grok Build entry, `~/.cursor`, `~/.windsurf`) or already have the skill; `--all` forces all four entries (incl. Copilot, which has no detectable dir). Grok Build reads the Claude Code skill path natively, so both share one entry/target file.
- `checkForUpdates()` (non-interactive, API commands) and `checkForUpdatesInteractively()` (bare invocation) detect outdated completions and/or skill, offering a single Y/n prompt or NOTE line. The version compare uses `isVersionOlder()` (numeric, component-wise) and only flags a stamp that is **strictly older** than the running binary — so an older `ascelerate` earlier in PATH never offers to *downgrade* completions/skill that a newer build installed.
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
- `apps review preflight --json` emits `{versionID, version, platform, state, passed, checks: [{group?, name, passed, detail}]}` — `group` is nil for top-level checks, a locale code for per-locale checks, or the `inAppPurchases`/`subscriptions` sentinels; the text table (group headers, indentation) is rendered FROM this model, and the exit code stays non-zero on failures in both modes (CI gate). Progress messages ("Checking build...") are suppressed under `--json`.
- `pricing show --json` is the rich per-territory view (price + currency + start date/preserved for subs) and deliberately does NOT mirror the `pricing export` JSON — export/import keep their own import-compatible format.
- Shared entry structs: `CustomerReviewsCommand.ReviewEntry` (list element + info object), `SubCommand.SubEntry` (sub groups nests it, sub list flattens it with a `group` ref). `ResolvedBuild` (TestFlightCommand) carries raw `platform`/`version` and derives the display `train`/`label` from them.

### Output formatting
- **ANSI colors** — `red()`, `green()`, `yellow()` (orange 208), `bold()` in Formatting.swift. Auto-disabled when stdout is not a terminal (`isatty` check). `stderrRed()` uses a separate `isStderrTerminal` check for error messages.
- **Colored output conventions** — `green()` for success verbs ("Created", "Updated", "Deleted", etc.), `yellow()` for "Cancelled.", `stderrRed("Error:")` in central error handler. `red()` for failure indicators (e.g. preflight ✗).
- **`formatFieldName()`** — converts camelCase (`whatsNew` → "What's New") and SCREAMING_SNAKE_CASE (`PREPARE_FOR_SUBMISSION` → "Prepare for Submission") to human-readable titles. Has override map for special cases (URL suffixes, OS names, `CANCELED` → "Cancelled").
- **`formatState()`** — generic wrapper: `formatFieldName("\(value)")`. Use for any enum/state value displayed to the user (e.g. `.map { formatState($0) }`). Applied globally across all command files for platform, status, type, and state fields.
- **`localeName()`** — resolves locale codes to human-readable names via `Locale.current.localizedString(forIdentifier:)` (e.g. `en-US` → `en-US (English (United States))`). Applied to all locale display across commands.
- **`parseEnum()`** — validates a string against a `RawRepresentable & CaseIterable` enum, returning the matched case or throwing `ValidationError` with valid values list. Use instead of inline `guard let X = T(rawValue: .uppercased())` blocks. `parseFilter()` wraps `parseEnum()` for optional API filter values (returns `[T]?`).
- **`fetchAll()`** — collects all items from paginated API responses (`client.pages()`) into a single array with empty guard and optional sort. Used by `promptDevice()`, `promptCertificate()`, `promptBundleID()`, `promptProfile()`.
- **`resolveFile()`** — resolves a file path from an optional argument; lists matching files by extension in the current directory as a numbered picker, with manual path entry fallback. Used by `localizations import` and `app-info import`.
- **ANSI-aware Table** — `Table.print` uses `visibleLength()` (strips ANSI codes via regex) and `padToVisible()` for correct column alignment when cells contain colored text. All-empty rows (`["", ""]`) render as blank lines for visual grouping.

### Error handling
- `ASCClient.main()` overrides the default entry point to catch and format errors centrally.
- `ResponseError` (from asc-swift): handles rate limit (429), HTTP status codes (401/403/5xx), and empty responses.
- `URLError`: handles connectivity issues (no internet, DNS, timeout, connection lost, TLS).

### Workflow files (used by run-workflow)
- One command per line, without the `ascelerate` prefix
- Lines starting with `#` are comments, blank lines are ignored
- Quoted strings are respected for arguments with spaces (e.g. `--file "path with spaces.json"`)
- Without `--yes`: prompts once to confirm the workflow, then individual commands still prompt normally
- With `--yes`: sets `autoConfirm = true` globally, all prompts are skipped
- `autoConfirm` is restored after each step — a single step with `-y` (or a nested `run-workflow --yes`) must not auto-accept prompts in later steps of a non-`--yes` workflow
- Commands are dispatched via `ASCClient.parseAsRoot(args)` — any registered subcommand works
- Nested workflows supported (`run-workflow` can call another workflow file) with circular reference detection via `activeWorkflows` path stack
- `builds upload` records the uploaded build number **per platform** (`recordUploadedBuild`/`lastUploadedBuild(for:)` in Formatting.swift) — subsequent `await-processing` (via its `--platform`) and `build attach-latest` (via the target version's platform) target the just-uploaded build for the RIGHT platform, avoiding both API propagation races and cross-platform build-number mixups when one workflow uploads iOS and macOS. A platform-specific miss never falls back to another platform's number; only a platform-less lookup uses the most recent upload.

### Xcode signing
- Both `builds archive` and the `.xcarchive` → `.ipa` export pass `-allowProvisioningUpdates` to `xcodebuild`. Without this, `xcodebuild` only uses locally cached provisioning profiles and won't fetch updated ones from the Developer Portal (Xcode GUI does this automatically, CLI does not).
- Xcode no longer downloads profiles to `~/Library/MobileDevice/Provisioning Profiles/` — with automatic signing it manages them internally. That folder is legacy.
- `-allowProvisioningUpdates` authenticates via the Apple ID in Xcode > Settings > Accounts. For CI, pass `-authenticationKeyPath`/`-authenticationKeyID`/`-authenticationKeyIssuerID`.

### Build processing
- `awaitBuildProcessing()` is a shared helper in `AppsCommand.swift` (alongside `findApp`/`findVersion`) — used by both `builds await-processing` and `build attach-latest`
- Recently uploaded builds may take a few minutes to appear in the API — the helper polls with a dot-based progress indicator until the build is found
- `build attach-latest` prompts to wait if the latest build is still `PROCESSING`; with `--yes` it waits automatically

### Reports (`reports sales` / `reports finance` / `reports analytics`)
- **Sales/Finance endpoints return `Request<Data>` (a gzipped TSV body), NOT JSON.** `client.send` would try to JSON-decode it and fail — use `client.download(request)` (returns a temp file URL) instead. `Reports.fetchReportText()` wraps this: download → `gzip -dc` (via `Process`, no new dependency; the `Compression` framework only does raw zlib, not gzip-with-header) → UTF-8 text. The body is `application/a-gzip`, so URLSession does NOT auto-decompress it.
- **Vendor number** is required for sales/finance (not analytics). Stored optionally in `config.json` (`vendorNumber`), overridable via `--vendor-number`, resolved by `Reports.resolveVendorNumber()`.
- **Sales report summary** groups `Units` by (Title, SKU, Product Type Identifier); `--bundle-id` filters rows by the `Apple Identifier` column (== app's numeric ID from `findApp`). `--raw`/`--output` emit the unparsed TSV. Default `--date` is the most recent completed period in Apple's reporting time zone (`Reports.defaultSalesDate`); weekly keys off the Sunday ending the week.
- **Finance report `--date` is a *fiscal* period** `YYYY-MM` (MM = Apple fiscal period 01–12, not a calendar month); `--region` is required. Summary sums `Quantity` by title and `Extended Partner Share` by currency, skipping footer/total lines (non-numeric `Quantity`).
- **A 404 from a download is surfaced via `Reports.notFoundHint()`** — the download path doesn't parse the JSON error body, so a bare "HTTP 404" is rewritten to "report not available yet / no activity; try an earlier date".
- **Analytics is async + multi-step**: find-or-create an `analyticsReportRequest` for the app (`apps/{id}/analyticsReportRequests` filtered by accessType; reuse one not `isStoppedDueToInactivity`, else POST — prompts first, never auto-creates without `-y`) → list `reports` by `--category` (picker if multiple, or `--report-name`) → list `instances` by `--granularity` (picks latest `processingDate`, or `--processing-date`) → page `segments` → download each segment's `attributes.url` (presigned, gzipped) via plain `URLSession`, gunzip, save one CSV per segment to `--output` dir. A freshly created snapshot has no instances yet — the command tells the user to re-run later.
- Deeply-nested generated `*CreateRequest` inits don't infer through chained `.init` — spell out the full types (see the `AnalyticsReportRequestCreateRequest` construction with a `typealias Body`).

### API calls
- **`Certificate` type is ambiguous** — both `AppStoreAPI.Certificate` and `X509.Certificate` exist. In `CertsCommand.swift` (which imports both), use `AppStoreAPI.Certificate` explicitly for API response types.
- **`filterBundleID` does prefix matching** — `com.foo.Bar` also matches `com.foo.BarPro`. Always use `findApp()` which filters for exact `bundleID` match from results.
- **Null data in non-optional response fields** — Several GET sub-resource endpoints return `{"data": null}` when no related object exists (e.g. build on version, EULA on app), but generated response types have non-optional `data`. Catch `DecodingError` for these. For EULA, also catch `ResponseError` with 404 status.
- Builds don't have `filterBundleID` — look up app first, then use `filterApp: [appID]`
- **Encryption declarations use top-level endpoint** — `Resources.v1.apps.id(appID).appEncryptionDeclarations` returns 404 for some apps. Use `Resources.v1.appEncryptionDeclarations.get(filterApp: [appID])` instead.
- **Territory availability limit is 50** — The v1 `include: [.territoryAvailabilities]` has a max limit of 50. Use the v2 sub-resource endpoint `Resources.v2.appAvailabilities.id(availabilityID).territoryAvailabilities.get(limit: 50, include: [.territory])` with `client.pages()` pagination.
- **Multiple AppInfo objects per app** — `appInfos.get()` can return multiple objects (current + replaced). `pickActiveAppInfo()` handles selection: filters out `replacedWithNewInfo`, prefers editable state (prepareForSubmission/waitingForReview) over live. Used by both `findActiveAppInfo()` and `app-info view`. Included localizations must be filtered by the selected AppInfo's `relationships.appInfoLocalizations.data` IDs — back-references on included items aren't populated.
- **`findVersion()` prefers editable versions** — when `versionString` is nil, first queries for prepareForSubmission/waitingForReview versions. If multiple exist (multi-platform apps), prompts user to select by platform. Falls back to latest version if none are editable.
- **Universal-purchase apps hold the same version string per platform** — one app record can have e.g. iOS 5.0 AND macOS 5.0, and iOS/macOS builds can share build numbers. Any lookup by version string or build number must also match platform: `findVersion()` takes a `platform:` param (filters server-side, prompts if still ambiguous), `selectBuild()`/`awaitBuildProcessing()` filter via `buildPlatformFilter()` (`filter[preReleaseVersion.platform]`), and review submissions are matched by `attributes.platform` (one active submission per platform; `selectSubmission()` prompts when several are active). Version-scoped commands expose this via the shared `PlatformOption` option group (`--platform ios|macos|tvos|visionos`, parsed by `parsePlatform()`).
- **AppCategory has no name attribute** — The category `id` IS the human-readable name (e.g. `UTILITIES`, `GAMES_ACTION`). No separate name field exists.
- **IAP/sub submissions 409 without a pending version** — `inAppPurchaseSubmissions`/`subscriptionSubmissions`/`subscriptionGroupSubmissions` POSTs used to be a no-op for items with no pending changes; the API now rejects them with 409 "has no pending version for submission". An APPROVED product with pending edits *stays* APPROVED — the pending version surfaces as non-approved child localization states (`PREPARE_FOR_SUBMISSION`/`REJECTED`). `submitBundledProducts()` in `apps review submit` checks localizations to only offer items with pending versions (READY_TO_SUBMIT always qualifies), submits a group only when its group localizations changed, and catches the specific 409 per item as a graceful skip (screenshot-only edits aren't detectable from localization states).
- Localizations are per-version: get version ID first, then fetch/update localizations
- Updates are one API call per locale — no bulk endpoint in the API
- Only versions in editable states (`PREPARE_FOR_SUBMISSION` or `WAITING_FOR_REVIEW`) accept localization updates — except `promotionalText`, which can be updated in any state
- `create-version` `--release-type` is optional; omitting it uses the previous version's setting
- **`bundleIDCapabilities` sub-resource rejects `limit`** — despite the generated code accepting `limit: Int?`, the API returns an error if `limit` is passed. Use `.get()` with no arguments.
- **TestFlight endpoints** — `betaAppReviewDetails` always exists per app (PATCH only, no POST); same for `betaLicenseAgreements` (empty `agreementText` = Apple's standard agreement). Internal groups with `hasAccessToAllBuilds` have no explicit build list (skip the builds fetch). On `betaTesters.get`, don't combine `filterApps` with `filterBetaGroups` — the group already scopes to one app. `findBuild()` in TestFlightCommand.swift resolves `--build`/`--platform` to a build (latest non-expired by default, expired allowed when an explicit number is given) with the same cross-platform ambiguity prompting as `findVersion()`.
- **Recruitment criteria quirks** — `GET betaGroups/{id}/betaRecruitmentCriteria` on a group with no criteria returns HTTP **409** ("BetaRecruitmentCriteria with id '…' does not exist"), not 404 or a null payload — `Criteria.fetch()` maps both 404 and 409 to nil. Unbounded OS limits come back as **empty strings**, not nil. Device-family enum case names (`iphone`, `ipad`, `appleTv`, `vision`) have `formatFieldName` overrides for proper display (iPhone, iPad, Apple TV, Apple Vision).
- **Tester invites need an installable build** — `betaTesterInvitations` POST fails with a clear API error if the tester's groups have no builds assigned; surface it as-is.
- **TestFlight locales ≠ App Store metadata locales** — `betaBuildLocalizations`/`betaAppLocalizations` use TestFlight's own locale set: `tr`, `ja`, `ko` (bare codes) but `en-US`, `de-DE`, `fr-FR` (region-qualified). Creating with `tr-TR` fails with 409 "The 'locale' value is invalid" (verified live). App Store version localizations, by contrast, use `tr-TR`.
- **Beta review is instant for follow-up builds** — only the first build of a version gets a full beta review; later builds of an approved version go straight to APPROVED on submission (verified live: QuakeLens 1.0 build 9 after build 8 was approved).
- Filter parameters vary per endpoint — check the generated PathsV1*.swift files for exact signatures
- **IAP price schedule fetches need fields[] AND include[] for relationships to populate** — Two related quirks discovered when wiring `iap pricing`:
  - `Resources.v2.inAppPurchases.id(iapID).iapPriceSchedule.get(...)` returns the schedule but `relationships.baseTerritory.data.id` is nil unless you pass `fieldsInAppPurchasePriceSchedules: [.baseTerritory, .manualPrices]` AND `include: [.baseTerritory]`. Both are required.
  - `Resources.v1.inAppPurchasePriceSchedules.id(scheduleID).manualPrices.get(...)` returns the price records but each record's `relationships.territory.data.id` and `relationships.inAppPurchasePricePoint.data.id` are nil unless you pass `include: [.inAppPurchasePricePoint, .territory]`. Without it you get just resource links.
  - Bottom line: for relationship `data` IDs, always pass both `include` and (where required) the matching `fields[]`. The schedule POST replaces the whole schedule wholesale, so you need these IDs to round-trip existing manualPrices through a read-modify-write.
- **IAP schedule POST is wholesale, but additive in practice** — `POST /v1/inAppPurchasePriceSchedules` fully replaces any existing schedule. To preserve manual overrides across a base-territory change or any edit, fetch the existing schedule first and include all entries you want kept in the new payload. Apple's web UI's "all manual prices will be deleted" warning is UI-conservatism — the API itself preserves whatever you send. The `iap pricing set/override/remove` commands all do this read-modify-write.
- **Subscription pricing is per-territory** — there's no `manualPrices`/`automaticPrices` split like IAPs have. Every entry in `subscription.prices` is an explicit `SubscriptionPrice` you POST. The `--equalize-all-territories` flag on `sub pricing set` mimics the web UI's auto-fill by walking `subscriptionPricePoints/{id}/equalizations` and POSTing one record per territory.
- **`isPreserveCurrentPrice` keeps existing subscribers on their old price** — On `SubscriptionPrice` POST, set `isPreserveCurrentPrice: true` to grandfather existing subscribers when raising prices. Apple's behavior:
  - **Decrease** (new < current): existing subscribers automatically get the lower price; `isPreserveCurrentPrice` is meaningless. `sub pricing set` warns and prompts interactively. Under `-y`, requires `--confirm-decrease` to acknowledge the revenue impact — plain `-y` is not enough.
  - **Increase** (new > current): the dev MUST decide. `--preserve-current` keeps existing subs at old price; `--no-preserve-current` pushes new price after Apple's notification period. The `sub pricing set` command errors if neither flag is passed for any increase (single territory or any territory in `--equalize-all-territories`).
  - **New territory** (no current price): no existing subs to consider; the flag is unnecessary.
  - **Unchanged**: `sub pricing set` skips silently. In equalize mode, only changed territories are POSTed.

### Price export JSON format (used by iap/sub pricing export/import)
```json
{
  "baseTerritory": "USA",
  "prices": { "USA": "4.99", "FRA": "5.99" }
}
```
- `baseTerritory` is present in IAP exports, omitted in subscription exports (sub import ignores it; IAP import falls back to the target's existing base, then USA)
- Import resolves each customer price against the **target** product's own tiers (exact match required; nearest tiers listed on mismatch), so a file can be applied to any product in any app. Territory keys are normalized to uppercase on load.
- IAP import replaces the schedule wholesale — territories not in the file revert to auto-equalize; if the resulting schedule equals the current one it's a no-op. Sub import only touches listed territories, skips unchanged ones, and runs through the shared increase/decrease gates (`gateAndApplyPriceChanges`).
- **Batched tier resolution**: fetching one territory's tier list is ~4 paged calls (limit 200, ~800 tiers/territory), so a 175-territory file would be ~700 requests. `resolvePricePointsBatched` (IAP) / `resolveSubPricePointsBatched` (sub) instead pass 10 territories per `filterTerritory` with `limit: 8000` (accepted by both pricePoints endpoints) — ~18 requests total. Points are grouped via `relationships.territory.data.id`, which requires BOTH `fields[...PricePoints]: [.customerPrice, .territory]` AND `include: [.territory]` (same hydration gotcha as the IAP schedule). Sub import first walks the anchor territory's equalizations — territories whose file price matches the equalized tier resolve with no extra fetch.
- **Transient-error retry**: ASC intermittently returns bursts of HTTP 500s during multi-territory price writes (observed live: 23 consecutive territories failing in one window, all succeeding on retry). `withTransientRetry` (Formatting.swift) wraps the price POSTs — `postSubscriptionPrice` and `postSchedule` — retrying 429/5xx in place (2s/5s backoff); `gateAndApplyPriceChanges` additionally sweeps transient failures in a second pass after a 5s pause, then reports the failed territory list with a re-run hint and exits non-zero. Client-side 4xx errors are never retried. Re-running an import/equalize is idempotent (already-applied territories categorize as unchanged and are skipped).

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

Same convention — only fields present get updated. The `AppInfoLocaleFields` struct in AppsCommand.swift defines the schema. The `app-info update` and `app-info import` commands check that the AppInfo is in an editable state (`PREPARE_FOR_SUBMISSION` or `WAITING_FOR_REVIEW`) before proceeding.

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
- `--replace` deletes existing assets in matching sets before uploading
- Download filenames are prefixed with `01_`, `02_` etc. to avoid collisions (same name can appear multiple times in a set)
- `ImageAsset.templateURL` uses `{w}x{h}bb.{f}` placeholders — resolve with actual width/height/format for download
- `AppPreview.videoURL` provides direct download URL for preview videos
- Reorder screenshots via `PATCH /v1/appScreenshotSets/{id}/relationships/appScreenshots` with `AppScreenshotSetAppScreenshotsLinkagesRequest`
- `AppMediaAssetState.State` values: `.awaitingUpload`, `.uploadComplete`, `.complete`, `.failed` — stuck items show `uploadComplete`
- `media verify` checks all media status; with `--folder` retries stuck items: delete → upload → reorder
- `media upload` filters the folder's display types to the target version's platform (APP_DESKTOP → macOS, APP_APPLE_TV* → tvOS, APP_APPLE_VISION* → visionOS, rest incl. Watch/iMessage → iOS; ASC 409s on foreign sets) and continues past per-set failures (non-zero exit if any failed)
- `media prune` deletes server sets with no matching local locale/display-type folder (stale screen sizes) — `--replace` never touches those; locales absent from the folder are skipped entirely
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
# xcargs: -resultBundlePath ./results
```

### Flow

1. `build-for-testing` with `generic/platform=iOS Simulator` and `-configuration` (default Release)
2. xcodebuild writes to project's actual derived data (custom `-derivedDataPath` is ignored by Xcode workspace settings)
3. Resolve xctestrun file from `~/Library/Developer/Xcode/DerivedData/{ProjectName}[-hash]/Build/Products/`
4. For each language: boot all simulators → wait (`waitAfterBoot`) → set dark mode → localize → override status bar → uninstall app (`reinstallApp`) → `test-without-building` concurrently per device → collect screenshots
5. Each device gets isolated cache at `~/Library/Caches/tools.ascelerate/{UDID}/`
6. ScreenshotHelper.swift uses `SIMULATOR_UDID` env var to find its cache directory
7. Errors skip failing device/language, error logs saved as `{language}/{device}-error.log` (unless `stopAfterFirstError`)
8. Summary table printed at end

### Key decisions

- `-parallel-testing-enabled NO` prevents simulator cloning (needed for status bar override)
- **Xcode 27 writes a dangling `UITargetAppPath` into the xctestrun** when another project in the workspace has a target with the same name as the UI test's `TEST_TARGET_NAME` but a different `PRODUCT_NAME` (e.g. an iOS `MyApp` target building "MyApp.app" and a macOS `MyApp` target with `PRODUCT_NAME = "My App"` → the xctestrun references "My App.app"). xcodebuild then fails the runner instantly, blocks on `simctl diagnose --timeout=600` (a silent 10-minute stall per run, during which SIGTERM is deferred, so Ctrl-C only lands after the wait), and only then runs the tests with the correct app it already mapped from `DependentProductPaths`. `ScreenshotTestRunner.repairXctestrunIfNeeded` detects the missing app, substitutes the single other `.app` in `DependentProductPaths`, and writes a repaired copy with `__TESTROOT__` made absolute to `~/Library/Caches/tools.ascelerate/xctestrun/` (kept out of Products so the newest-xctestrun discovery never picks it up). Not deterministic: of two clean Xcode 27.0 RC builds of the same workspace, the first wrote the wrong path and the second the right one; Xcode 26.6 always wrote the right one. Verified live 2026-09-10.
- `xcrun simctl bootstatus` waits for full boot before applying status bar override
- Test output goes to log files (not stdout) to prevent interleaved output from concurrent devices
- Helper version tracked via `// ScreenshotHelperVersion [X.Y]` comment in generated file
- `clearPreviousScreenshots` only clears per-language after all devices succeed
- `numberOfRetries` — retries failed languages by erasing the failed simulators, re-localizing, rebooting, and rerunning tests. Works around simulator localization bugs where translated labels aren't found. Only failed devices are retried.
- `testplan` and `xcargs` are passed to both build and test phases
- `disableAnimations` passes `-ASC_DISABLE_ANIMATIONS YES` as a launch argument; app must call `disableAnimationsIfNeeded()` to act on it
- SIGINT handler (via `sigaction`) forwards Ctrl-C to child xcodebuild processes
- **Helper uses `app.windows.firstMatch.screenshot()`, not `app.screenshot()` or `XCUIScreen.main.screenshot()`.** XCUIScreen captures the simulator framebuffer via the render server, so if the target app has terminated at the moment of capture (seen intermittently on iPad when the last test tap triggers a locale-dependent crash in the app), the call silently returns a home-screen PNG and the test "passes" with a bad screenshot. `app.screenshot()` detects the dead app but composites a broken buffer on rotated simulators (portrait frame with landscape content pasted un-rotated and cropped — unrecoverable). The window screenshot is still an RPC into the target process — if the process is gone it throws `Lost connection to the application (pid N)`, XCTest marks the test failed, and `numberOfRetries` retries the device+language automatically — and it returns complete rotated content, merely orientation-tagged. Since PNG has no orientation metadata (`pngData()` drops non-`.up` tags), the helper bakes the orientation by re-rendering before saving. Do not switch capture APIs without preserving both the dead-app detection and the rotation handling.
- **CGContext rotation direction is counterintuitive**: `rotate(by: -.pi/2)` in CG's y-up coordinate space appears *clockwise* in the displayed image. `ScreenshotFramer.rotated90CCW` (used to rotate the portrait bezel for landscape framing, Dynamic Island to the left = landscapeLeft) uses `translateBy(x: height, y: 0)` + `rotate(by: .pi/2)` for a true displayed-CCW rotation. Verify any rotation change empirically with a marker-pixel test image — the angle sign misleads.

### Commands

```
ascelerate screenshot [-l en-US,tr-TR]        # Capture screenshots (optionally filter to a subset of configured languages)
ascelerate screenshot init                    # Create ascelerate/screenshot.yml + ScreenshotHelper.swift
ascelerate screenshot create-helper [-o file] # Generate ScreenshotHelper.swift (default: ascelerate/)
```

## Website (`website/`)

Docusaurus 3 docs site (ascelerate.dev), 5 locales (en/de/fr/ja/tr, translations under `website/i18n/`), deployed via git-integrated **Cloudflare Pages** building from `main` (root `website/`, output `build/`). No local deploy step — pushing to `main` deploys.

### Markdown for agents (2026-08)

Every docs page has a `.md` twin served via `Accept: text/markdown` content negotiation (same workspace-wide pattern as the sites under `~/Developer/Web` — see that workspace's CLAUDE.md; reference implementation: keremerkan.dev):

- `website/scripts/generate-md-twins.mjs` copies all docs source `.md` files (all 5 locales) into the build output at their route paths (`/docs/<page>.md`, `/de/docs/<page>.md`, …). It runs as part of `npm run build` — **the Pages build command must stay `npm run build`**, not `docusaurus build`, or twins won't generate.
- `website/functions/_middleware.js` (Cloudflare Pages Function) does the negotiation: markdown-accepting requests get the twin with `Content-Type: text/markdown; charset=utf-8`; HTML responses get `Vary: Accept`. Pages HTML is never edge-cached, so there is no Vary/cache-poisoning risk here.
- `website/static/index.md` is the **hand-written** homepage twin — update it when the homepage copy in `src/pages/index.tsx` changes. Docs twins are verbatim source and need no maintenance.
- `website/scripts/generate-agent-skills.mjs` (also in `npm run build`) publishes the repo's `skills/*/SKILL.md` files at `/.well-known/agent-skills/` with an `index.json` manifest (Agent Skills discovery convention) — sourced from the repo's skills, so they can't drift.
- `website/static/robots.txt` carries `Content-Signal: ai-train=yes, search=yes, ai-input=yes`. The zone's Cloudflare **managed robots.txt is deliberately disabled** (it declared ai-train=no and blocked AI crawlers, which is counterproductive for a developer tool) — don't re-enable it.

## Not Yet Implemented

asc-swift exposes the full App Store Connect surface (~185 top-level v1 resources). ascelerate wraps **82** of them — deep coverage where it exists (apps, versions, version/app-info localizations, screenshots/previews, full IAP + subscriptions incl. promoted-purchase CRUD, provisioning, review submissions + App Review Information (details + attachments), builds, territories/availability, encryption, EULA, age rating, routing coverage, customer reviews + responses, in-app events incl. localizations + media, TestFlight core), but several whole product areas are untouched. Gap analysis last refreshed against **asc-swift 1.7.0**.

### Partially covered
- **Monetization** — IAP and subscriptions have CRUD + localizations + pricing (per-territory overrides for IAPs, equalize fan-out for subs with increase/decrease safety, cross-product export/import of price schedules) + per-product availability + app-level grace period + subscription introductory offers + IAP/sub offer codes (with one-time-use + custom code generation) + subscription promotional offers + group submissions + IAP/sub promotional images + App Review screenshots. Remaining: **win-back offers** (blocked: asc-swift's `WinBackOfferPriceInlineCreate` doesn't expose territory/pricePoint relationships — can't reach the API correctly until the generator is updated. Confirmed still broken as of asc-swift 1.7.0: it remains the only `*PriceInlineCreate` type with just `type`+`id`, while all siblings — IAP/sub price, offer-code, promotional-offer — carry territory/pricePoint. The read-side `WinBackOfferPrice` does expose them, so it's specifically the CreateAPI-generated inline-create schema that's wrong), IAP hosted content (`inAppPurchaseContents`; read-only via API; low value).
- **Build upload** — done via `altool` (binary upload); the API-native `buildUploads`/`buildUploadFiles`/`buildBundles` path is intentionally unused. `.xcarchive` platform is detected from the archived app's Info.plist (`DTPlatformName`, falling back to Contents/ bundle layout): macOS exports to `.pkg` and uploads with `--type macos` (needs a Mac Installer Distribution cert), iOS-family exports to `.ipa`.
- **Custom product pages** — page CRUD (`product-pages list/info/create/update/delete`; create is a compound version+localization request using `${local-id}` inline references) + localizations (`product-pages localizations view/export/import`; promotional text per locale) + media (`product-pages media list/upload/delete`; per-locale screenshot sets by display type and app preview sets). Remaining: **per-locale search-keyword linkages** (blocked, same class of asc-swift codegen gap as win-back offers — as of 1.7.0 the `AppKeyword` entity exposes no attributes, only `type`+`id`+`links`, so the keyword *text* is unavailable, and there's no endpoint to create keywords. The relationship endpoints exist — `appCustomProductPageLocalizations/{id}/relationships/searchKeywords` GET/POST/DELETE link keyword IDs to a localization, sourced from the read-only app pool `apps/{id}/searchKeywords` — but a command could only shuffle opaque, undisplayable IDs. Not shippable until `AppKeyword` exposes the keyword text).
- **App metadata** — no commands for app tags, app categories CRUD, app clips, nominations (editorial).
- **TestFlight** — **fully covered** as of 0.16.0: beta groups (CRUD + public links + build assignment + recruitment criteria), beta testers (list/add/remove/invite-resend/CSV bulk import), builds with internal/external states (`buildBetaDetails`) + auto-notify toggle, expire, tester notifications (`buildBetaNotifications`), pre-release version trains, What to Test (`betaBuildLocalizations` view/set/export/import), beta review submissions (`submit`/`status`), beta app info (`betaAppLocalizations`), beta review information (`betaAppReviewDetails`), beta license agreement (`betaLicenseAgreements`), and tester feedback (`betaFeedbackCrashSubmissions` incl. crash log text, `betaFeedbackScreenshotSubmissions` incl. image download). Note: Apple's public API has no bulk-tester endpoint — `testers import` loops `betaTesters` POSTs client-side.

### Missing entirely
Counts are approximate top-level resources from the 1.7.0 surface.
- **Game Center** (~38) — achievements, leaderboards (+sets), challenges, activities, matchmaking (queues/rules/teams), groups, details, enabled versions, releases.
- **Xcode Cloud (CI/CD) + SCM** (~17) — `ci*` (products, workflows, build runs/actions, artifacts, issues, test results, macOS/Xcode versions) and `scm*` (providers, repositories, git refs, pull requests).
- **A/B experiments** (3) — App Store version experiments + treatments + treatment localizations.
- **App Clips** (7) — app clips, advanced/default experiences, header/advanced images, app-clip review details.
- **Background Assets** (6) — assets, versions, upload files, app-store/internal/external beta releases.
- **Alternative distribution / EU** (~8) — `alternativeDistribution*` (domains, keys, packages + variants/deltas/versions) and `marketplace*` (search details, webhooks).
- **Webhooks** (3) — webhooks + deliveries + pings (ASC event notifications; newer).
- **Analytics / Sales / Finance** — **covered** via `reports sales/finance/analytics` (Sales & Trends, Financial, and App Analytics reports; gzipped TSV/CSV downloaded + summarized). Remaining: analytics-report `segments`/`instances` are exposed only through the `analytics` flow (no standalone commands), and **diagnostic signatures** (`diagnosticSignatures`) are untouched.
- **Users & access** (3) — users, user invitations, actors (team management).
- **App-level pricing & release** — `appPriceSchedules` (paid-app pricing), `subscriptionPlanAvailabilities`, `appStoreVersionPromotions`, `endAppAvailabilityPreOrders`. (`appStoreVersionReleaseRequests` is covered via `apps release`.)
- **Provisioning extras** — `merchantIDs` (Apple Pay), `passTypeIDs` (Wallet).
- **Niche** — accessibility declarations, `appEncryptionDeclarationDocuments`, Android-to-iOS app mapping.

## Release build note

`swift build -c release` is very slow due to whole-module optimization of AppStoreAPI's ~2500 generated files. Debug builds are fast for development.


<claude-mem-context>
# Recent Activity

<!-- This section is auto-generated by claude-mem. Edit content outside the tags. -->

*No recent activity*
</claude-mem-context>