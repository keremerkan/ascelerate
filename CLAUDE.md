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
  ASCClient.swift                     # @main entry, root AsyncParsableCommand, central error handling
  Config.swift                        # ~/.ascelerate/config.json loader, ConfigError
  ClientFactory.swift                 # Creates authenticated AppStoreConnectClient
  Formatting.swift                    # Shared helpers: Table.print, ANSI colors, formatFieldName/formatState, formatDate, expandPath
  Aliases.swift                        # Alias storage (~/.ascelerate/aliases.json), resolveAlias()
  MediaUpload.swift                   # Media management: upload, download, retry screenshots/previews
  Commands/
    ConfigureCommand.swift            # Interactive credential setup, file permissions
    AppsCommand.swift                 # All app subcommands + findApp/findVersion helpers
    BuildsCommand.swift               # Build subcommands
    IAPCommand.swift                  # In-app purchase subcommands
    SubCommand.swift                 # Subscription subcommands
    DevicesCommand.swift              # Device management subcommands + findDevice helper
    CertsCommand.swift                # Signing certificate subcommands + findCertificate helper
    BundleIDsCommand.swift            # Bundle identifier subcommands + findBundleID helper
    ProfilesCommand.swift             # Provisioning profile subcommands + findProfile helper
    AliasCommand.swift                # Alias management (add, remove, list) for bundle ID shortcuts
    RunWorkflowCommand.swift          # Sequential command runner from workflow files
    InstallCompletionsCommand.swift   # Shell completion installer with post-processing patches
    InstallSkillCommand.swift         # Claude Code skill installer (fetches from GitHub)
    RateLimitCommand.swift            # API rate limit status check
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
    "privateKeyPath": "/Users/.../.ascelerate/AuthKey_XXXXXXXXXX.p8"
}
```

- `configure` command copies the .p8 file into `~/.ascelerate/` and writes the config
- File permissions set to 700 (dir) and 600 (files) — owner-only access
- JWT tokens use ES256 (P256) signing, 20-minute expiry, auto-renewed by asc-swift
- Private key loaded via `JWT.PrivateKey(contentsOf: URL(fileURLWithPath: path))`

## Commands

```
ascelerate configure                                              # Interactive setup
ascelerate apps list                                              # List all apps
ascelerate apps info <bundle-id>                                  # App details
ascelerate apps versions <bundle-id>                              # List App Store versions
ascelerate apps localizations view <bundle-id> [--version X]      # View localizations
ascelerate apps localizations update <bundle-id> [--locale X]     # Update single locale via flags
ascelerate apps localizations import <bundle-id> [--file X]       # Bulk update from JSON file
ascelerate apps localizations export <bundle-id> [--version X]    # Export to JSON file
ascelerate apps review preflight <bundle-id> [--version X]           # Pre-submission checks
ascelerate apps review status <bundle-id> [--version X]             # Review submission status
ascelerate apps create-version <bundle-id> <ver> [--platform X]   # Create new version
ascelerate apps build attach <bundle-id> [--version X]             # Interactively select and attach a build
ascelerate apps build attach-latest <bundle-id> [--version X]     # Attach the most recent build
ascelerate apps build detach <bundle-id> [--version X]            # Remove the attached build
ascelerate apps phased-release <bundle-id> [--version X]          # View/manage phased release
ascelerate apps app-info age-rating <bundle-id> [--version X] [--file X]   # View/update age rating
ascelerate apps routing-coverage <bundle-id> [--file X]           # View/upload routing coverage
ascelerate apps review submit <bundle-id> [--version X]            # Submit version for App Review
ascelerate apps review resolve-issues <bundle-id>                 # Mark rejected items as resolved
ascelerate apps review cancel-submission <bundle-id>              # Cancel an active review submission
ascelerate apps media upload <bundle-id> [--folder X] [--version X] [--replace]  # Upload screenshots/previews
ascelerate apps media download <bundle-id> [--folder X] [--version X]            # Download screenshots/previews
ascelerate apps media verify <bundle-id> [--version X] [--folder X]              # Check media status, retry stuck
ascelerate apps app-info view <bundle-id>                         # View app info, categories, and localizations
ascelerate apps app-info view --list-categories                   # List available category IDs
ascelerate apps app-info update <bundle-id> [--name X] [--subtitle X] [--primary-category X] [-y]  # Update localization fields and/or categories
ascelerate apps app-info import <bundle-id> [--file X] [--verbose] [-y]  # Bulk update localizations from JSON
ascelerate apps app-info export <bundle-id> [--output X]          # Export localizations to JSON
ascelerate apps availability <bundle-id> [--add X] [--remove X]  # View/update territory availability
ascelerate apps encryption <bundle-id> [--create]                 # View/create encryption declarations
ascelerate apps eula <bundle-id> [--file X] [--delete]            # View/manage custom EULA
ascelerate builds list [--bundle-id <id>] [--version X]           # List builds
ascelerate builds archive [--workspace X] [--scheme X] [--output X]  # Archive Xcode project
ascelerate builds upload [file]                                   # Upload build via altool
ascelerate builds validate [file]                                 # Validate build via altool
ascelerate builds await-processing <bundle-id> [--build-version X]  # Wait for build to finish processing
ascelerate iap list <bundle-id> [--type X] [--state X]            # List in-app purchases
ascelerate iap info <bundle-id> <product-id>                       # IAP details with localizations
ascelerate iap promoted <bundle-id>                                # List promoted purchases
ascelerate sub groups <bundle-id>                                 # List subscription groups with subscriptions
ascelerate sub list <bundle-id>                                   # Flat list of all subscriptions
ascelerate sub info <bundle-id> <product-id>                      # Subscription details with localizations
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
ascelerate run-workflow [file] [--yes]                            # Run commands from a workflow file
ascelerate rate-limit                                             # Show API rate limit status
ascelerate install-skill [--uninstall]                            # Install/remove Claude Code skill
ascelerate screenshot run [-c ascelerate.yml]                     # Capture screenshots from simulators
ascelerate screenshot init [-o ascelerate.yml]                    # Generate sample config
ascelerate screenshot create-helper [-o ScreenshotHelper.swift]   # Generate UITest helper file
ascelerate version                                                # Print version number (also: --version, -v)
```

## Key Patterns

### Adding a new subcommand
1. Add the command struct inside `AppsCommand` (or create a new command group)
2. Use `AsyncParsableCommand` for commands that call the API
3. Register in the appropriate `CommandGroup` in the parent's configuration (see below)
4. Use `findApp(bundleID:client:)` to resolve bundle ID to app ID
5. Use `findVersion(appID:versionString:platform:client:)` to resolve version (nil = prefers editable, prompts if multiple platforms)
6. Use shared helpers from Formatting.swift: `formatDate()`, `expandPath()`, `formatState()` for enum display, color helpers (`green()`, `red()`, `yellow()`, `bold()`)
7. Run `ascelerate install-completions` to regenerate completions after adding commands

### Subcommand grouping
`AppsCommand` uses `CommandGroup` (swift-argument-parser 1.7+) to organize subcommands into sections in `--help` output:
- **ungrouped** (`subcommands:`): list, info, versions — general browse commands
- **Version**: create-version, build (attach, attach-latest, detach), phased-release, routing-coverage
- **Info & Content**: app-info (view, update, import, export, age-rating), localizations (view, update, import, export), media (upload, download, verify)
- **Configuration**: availability, encryption, eula
- **Review**: review (preflight, status, submit, resolve-issues, cancel-submission)

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
- `install-completions` stamps `# ascelerate vX.Y.Z` into completion scripts (after `#compdef` line for zsh) and `install-skill` stamps `<!-- ascelerate vX.Y.Z -->` into the installed skill file.
- `checkForUpdates()` (non-interactive, API commands) and `checkForUpdatesInteractively()` (bare invocation) detect outdated completions and/or skill, offering a single Y/n prompt or NOTE line.
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
- Text inputs use a recursive `promptText()` that retries on empty input (same pattern as ConfigureCommand's `prompt()`).
- Selection lists use `[\(i + 1)]` numbering, `readLine()` input, `Int()` parsing, and range validation.
- `--yes` / `autoConfirm` is incompatible with interactive mode — commands throw `ValidationError` when required options are missing with `--yes`.
- `enable-capability` filters the type picker to exclude already-enabled capabilities; `disable-capability` only shows enabled ones.
- `enable-capability` and `disable-capability` offer to regenerate provisioning profiles after changes (delete + recreate with same settings) via `regenerateProfilesIfNeeded()` helper in BundleIDsCommand.swift.

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
- Commands are dispatched via `ASCClient.parseAsRoot(args)` — any registered subcommand works
- Nested workflows supported (`run-workflow` can call another workflow file) with circular reference detection via `activeWorkflows` path stack
- `builds upload` sets `lastUploadedBuildVersion` global — subsequent `await-processing` and `build attach-latest` automatically target the just-uploaded build, avoiding race conditions with API propagation delay

### Xcode signing
- Both `builds archive` and the `.xcarchive` → `.ipa` export pass `-allowProvisioningUpdates` to `xcodebuild`. Without this, `xcodebuild` only uses locally cached provisioning profiles and won't fetch updated ones from the Developer Portal (Xcode GUI does this automatically, CLI does not).
- Xcode no longer downloads profiles to `~/Library/MobileDevice/Provisioning Profiles/` — with automatic signing it manages them internally. That folder is legacy.
- `-allowProvisioningUpdates` authenticates via the Apple ID in Xcode > Settings > Accounts. For CI, pass `-authenticationKeyPath`/`-authenticationKeyID`/`-authenticationKeyIssuerID`.

### Build processing
- `awaitBuildProcessing()` is a shared helper in `AppsCommand.swift` (alongside `findApp`/`findVersion`) — used by both `builds await-processing` and `build attach-latest`
- Recently uploaded builds may take a few minutes to appear in the API — the helper polls with a dot-based progress indicator until the build is found
- `build attach-latest` prompts to wait if the latest build is still `PROCESSING`; with `--yes` it waits automatically

### API calls
- **`Certificate` type is ambiguous** — both `AppStoreAPI.Certificate` and `X509.Certificate` exist. In `CertsCommand.swift` (which imports both), use `AppStoreAPI.Certificate` explicitly for API response types.
- **`filterBundleID` does prefix matching** — `com.foo.Bar` also matches `com.foo.BarPro`. Always use `findApp()` which filters for exact `bundleID` match from results.
- **Null data in non-optional response fields** — Several GET sub-resource endpoints return `{"data": null}` when no related object exists (e.g. build on version, EULA on app), but generated response types have non-optional `data`. Catch `DecodingError` for these. For EULA, also catch `ResponseError` with 404 status.
- Builds don't have `filterBundleID` — look up app first, then use `filterApp: [appID]`
- **Encryption declarations use top-level endpoint** — `Resources.v1.apps.id(appID).appEncryptionDeclarations` returns 404 for some apps. Use `Resources.v1.appEncryptionDeclarations.get(filterApp: [appID])` instead.
- **Territory availability limit is 50** — The v1 `include: [.territoryAvailabilities]` has a max limit of 50. Use the v2 sub-resource endpoint `Resources.v2.appAvailabilities.id(availabilityID).territoryAvailabilities.get(limit: 50, include: [.territory])` with `client.pages()` pagination.
- **Multiple AppInfo objects per app** — `appInfos.get()` can return multiple objects (current + replaced). `pickActiveAppInfo()` handles selection: filters out `replacedWithNewInfo`, prefers editable state (prepareForSubmission/waitingForReview) over live. Used by both `findActiveAppInfo()` and `app-info view`. Included localizations must be filtered by the selected AppInfo's `relationships.appInfoLocalizations.data` IDs — back-references on included items aren't populated.
- **`findVersion()` prefers editable versions** — when `versionString` is nil, first queries for prepareForSubmission/waitingForReview versions. If multiple exist (multi-platform apps), prompts user to select by platform. Falls back to latest version if none are editable.
- **AppCategory has no name attribute** — The category `id` IS the human-readable name (e.g. `UTILITIES`, `GAMES_ACTION`). No separate name field exists.
- Localizations are per-version: get version ID first, then fetch/update localizations
- Updates are one API call per locale — no bulk endpoint in the API
- Only versions in editable states (`PREPARE_FOR_SUBMISSION` or `WAITING_FOR_REVIEW`) accept localization updates — except `promotionalText`, which can be updated in any state
- `create-version` `--release-type` is optional; omitting it uses the previous version's setting
- **`bundleIDCapabilities` sub-resource rejects `limit`** — despite the generated code accepting `limit: Int?`, the API returns an error if `limit` is passed. Use `.get()` with no arguments.
- Filter parameters vary per endpoint — check the generated PathsV1*.swift files for exact signatures

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
- File matching: server position N = Nth file alphabetically in local `locale/displayType/` folder

## Screenshot Module (`ascelerate screenshot`)

Captures App Store screenshots from iOS/iPadOS simulators. Replaces fastlane snapshot.

### Architecture

```
Sources/ascelerate/
  Screenshot/
    ScreenshotConfig.swift       # YAML config model (via Yams), AscelerateConfig wrapper
    ScreenshotRunner.swift       # Orchestrator: build → boot simulators → run tests → collect
    ScreenshotTestRunner.swift   # xcodebuild wrapper: build-for-testing + test-without-building
    ScreenshotCollector.swift    # Moves PNGs from per-device cache to output dir
    SimulatorManager.swift       # xcrun simctl: boot, shutdown, erase, localize, status bar
    ScreenshotShell.swift        # Process wrapper: run (capture), stream (passthrough), runToLog (to file)
    ScreenshotError.swift        # Error types
  Commands/
    ScreenshotCommand.swift      # Subcommands: run, init, create-helper + embedded ScreenshotHelper.swift
```

### Config (`ascelerate.yml`)

```yaml
screenshot:
  project: App.xcodeproj
  scheme: AppUITests
  devices:
    - simulator: iPhone 16 Pro Max
    - simulator: iPad Pro 13-inch (M4)
  languages: [en-US, tr-TR]
  outputDirectory: ./screenshots
  clearPreviousScreenshots: true
  eraseSimulator: false
  localizeSimulator: true
  overrideStatusBar: true
  # helperPath: AppUITests/ScreenshotHelper.swift
```

Top-level `screenshot:` key namespaces the config — other sections can be added later.

### Flow

1. `build-for-testing` with `generic/platform=iOS Simulator` (or find existing xctestrun if `testWithoutBuilding`)
2. xcodebuild writes to project's actual derived data (custom `-derivedDataPath` is ignored by Xcode workspace settings)
3. Resolve xctestrun file from `~/Library/Developer/Xcode/DerivedData/{ProjectName}[-hash]/Build/Products/`
4. For each language: boot all simulators → localize → override status bar → `test-without-building` concurrently per device → collect screenshots
5. Each device gets isolated cache at `~/Library/Caches/tools.ascelerate/{UDID}/`
6. ScreenshotHelper.swift uses `SIMULATOR_UDID` env var to find its cache directory
7. Errors skip failing device/language, error logs saved as `{language}/{device}-error.log`
8. Summary table printed at end

### Key decisions

- `-parallel-testing-enabled NO` prevents simulator cloning (needed for status bar override)
- `xcrun simctl bootstatus` waits for full boot before applying status bar override
- Test output goes to log files (not stdout) to prevent interleaved output from concurrent devices
- Helper version tracked via `// ScreenshotHelperVersion [X.Y]` comment in generated file
- `clearPreviousScreenshots` only clears per-language after all devices succeed

### Commands

```
ascelerate screenshot run [-c ascelerate.yml]  # Capture screenshots
ascelerate screenshot init [-o ascelerate.yml] # Generate sample config
ascelerate screenshot create-helper [-o file]  # Generate ScreenshotHelper.swift
```

## Not Yet Implemented

API endpoints available but not yet added (43 app sub-resources + 5 top-level resources):
- **TestFlight**: beta groups, beta testers, pre-release versions, beta app localizations
- **Monetization**: price points, in-app purchase management (create/update/delete), subscription management (create/update/delete)
- **Feedback**: customer reviews, review summarizations
- **Analytics**: analytics reports, performance power metrics
- **Configuration**: app events, app clips, custom product pages, A/B experiments

## Release build note

`swift build -c release` is very slow due to whole-module optimization of AppStoreAPI's ~2500 generated files. Debug builds are fast for development.


<claude-mem-context>
# Recent Activity

<!-- This section is auto-generated by claude-mem. Edit content outside the tags. -->

*No recent activity*
</claude-mem-context>