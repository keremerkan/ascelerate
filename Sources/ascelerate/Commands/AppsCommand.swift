import AppStoreAPI
import AppStoreConnect
import ArgumentParser
import Foundation

struct AppsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "apps",
    abstract: "Manage apps.",
    subcommands: [List.self, Info.self, Versions.self],
    groupedSubcommands: [
      CommandGroup(name: "Version", subcommands: [CreateVersion.self, Copyright.self, BuildCommand.self, PhasedRelease.self, RoutingCoverage.self]),
      CommandGroup(name: "Info & Content", subcommands: [AppInfoCommand.self, Localizations.self, MediaCommand.self]),
      CommandGroup(name: "Configuration", subcommands: [Availability.self, Encryption.self, EULACommand.self, SubscriptionGracePeriod.self]),
      CommandGroup(name: "Review", subcommands: [ReviewCommand.self]),
    ]
  )
  
  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List all apps."
    )
    
    func run() async throws {
      let client = try ClientFactory.makeClient()
      var allApps: [(String, String, String)] = []
      
      for try await page in client.pages(Resources.v1.apps.get()) {
        for app in page.data {
          let name = app.attributes?.name ?? "—"
          let bundleID = app.attributes?.bundleID ?? "—"
          let sku = app.attributes?.sku ?? "—"
          allApps.append((bundleID, name, sku))
        }
      }
      
      Table.print(
        headers: ["Bundle ID", "Name", "SKU"],
        rows: allApps.map { [$0.0, $0.1, $0.2] }
      )
    }
  }
  
  struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Show info for an app."
    )
    
    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String
    
    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let attrs = app.attributes
      print("Name:            \(attrs?.name ?? "—")")
      print("Bundle ID:       \(attrs?.bundleID ?? "—")")
      print("SKU:             \(attrs?.sku ?? "—")")
      print("Primary Locale:  \(attrs?.primaryLocale.map { localeName($0) } ?? "—")")

      let versions = try await client.send(
        Resources.v1.apps.id(app.id).appStoreVersions.get(
          filterAppVersionState: [.prepareForSubmission, .waitingForReview, .inReview, .pendingDeveloperRelease, .readyForDistribution]
        )
      )
      if let latest = versions.data.first {
        let v = latest.attributes
        print("")
        print("Latest Version:  \(v?.versionString ?? "—")")
        print("Platform:        \(v?.platform.map { formatState($0) } ?? "—")")
        print("State:           \(v?.appVersionState.map { formatState($0) } ?? "—")")
        print("Release Type:    \(v?.releaseType.map { formatState($0) } ?? "—")")
        print("Created:         \(v?.createdDate.map { formatDate($0) } ?? "—")")
      }
    }
  }
  
  struct Versions: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List App Store versions."
    )
    
    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String
    
    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      
      let response = try await client.send(
        Resources.v1.apps.id(app.id).appStoreVersions.get()
      )
      
      var rows: [[String]] = []
      for version in response.data {
        let attrs = version.attributes
        let versionString = attrs?.versionString ?? "—"
        let platform = attrs?.platform.map { formatState($0) } ?? "—"
        let state = attrs?.appVersionState.map { formatState($0) } ?? "—"
        let releaseType = attrs?.releaseType.map { formatState($0) } ?? "—"
        let created = attrs?.createdDate.map { formatDate($0) } ?? "—"
        rows.append([versionString, platform, state, releaseType, created])
      }
      
      Table.print(
        headers: ["Version", "Platform", "State", "Release Type", "Created"],
        rows: rows
      )
    }
  }
  
  struct Localizations: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "View and manage version localizations.",
      subcommands: [View.self, Update.self, Import.self, Export.self]
    )
    
    static let editableStates: Set<AppVersionState> = [.prepareForSubmission, .waitingForReview]
    
    static func checkEditable(_ version: AppStoreVersion, promotionalTextOnly: Bool) throws {
      guard let state = version.attributes?.appVersionState, !editableStates.contains(state) else {
        return // editable — all fields allowed
      }
      let stateStr = "\(state)"
      if promotionalTextOnly {
        return // promotional text can be updated in any state
      }
      throw ValidationError("Version is in state '\(stateStr)' — only promotional text can be updated. Other fields require PREPARE_FOR_SUBMISSION or WAITING_FOR_REVIEW.")
    }
    
    // MARK: - View
    
    struct View: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "List localizations for an App Store version."
      )
      
      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String
      
      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
      var version: String?

      @OptionGroup var platformOption: PlatformOption
      
      @Option(name: .long, help: "Filter by locale (e.g. en-US).")
      var locale: String?
      
      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let version = try await findVersion(appID: app.id, versionString: version, platform: try platformOption.parsed(), client: client)
        
        let versionString = version.attributes?.versionString ?? "unknown"
        print("Version: \(versionString)")
        print()
        
        let request = Resources.v1.appStoreVersions.id(version.id)
          .appStoreVersionLocalizations.get(
            filterLocale: locale.map { [$0] }
          )
        
        let response = try await client.send(request)
        
        for loc in response.data {
          let attrs = loc.attributes
          let localeStr = attrs?.locale.map { localeName($0) } ?? "—"
          print("[\(localeStr)]")
          if let desc = attrs?.description, !desc.isEmpty {
            print("  Description:      \(desc.prefix(80))\(desc.count > 80 ? "..." : "")")
          }
          if let whatsNew = attrs?.whatsNew, !whatsNew.isEmpty {
            print("  What's New:       \(whatsNew.prefix(80))\(whatsNew.count > 80 ? "..." : "")")
          }
          if let keywords = attrs?.keywords, !keywords.isEmpty {
            print("  Keywords:         \(keywords.prefix(80))\(keywords.count > 80 ? "..." : "")")
          }
          if let promo = attrs?.promotionalText, !promo.isEmpty {
            print("  Promotional Text: \(promo.prefix(80))\(promo.count > 80 ? "..." : "")")
          }
          if let url = attrs?.marketingURL {
            print("  Marketing URL:    \(url)")
          }
          if let url = attrs?.supportURL {
            print("  Support URL:      \(url)")
          }
          print()
        }
      }
    }
    
    // MARK: - Update
    
    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Update localization metadata for the latest App Store version."
      )
      
      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String
      
      @Option(name: .long, help: "The locale to update (e.g. en-US). Defaults to the app's primary locale.")
      var locale: String?

      @OptionGroup var platformOption: PlatformOption

      @Option(name: .long, help: "App description.")
      var description: String?
      
      @Option(name: .long, help: "What's new in this version.")
      var whatsNew: String?
      
      @Option(name: .long, help: "Comma-separated keywords.")
      var keywords: String?
      
      @Option(name: .long, help: "Promotional text.")
      var promotionalText: String?
      
      @Option(name: .long, help: "Marketing URL.")
      var marketingURL: String?
      
      @Option(name: .long, help: "Support URL.")
      var supportURL: String?
      
      func run() async throws {
        guard description != nil || whatsNew != nil || keywords != nil
                || promotionalText != nil || marketingURL != nil || supportURL != nil else {
          throw ValidationError("Provide at least one field to update (--description, --whats-new, --keywords, --promotional-text, --marketing-url, --support-url).")
        }
        
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let version = try await findVersion(appID: app.id, versionString: nil, platform: try platformOption.parsed(), client: client)
        
        let onlyPromoText = promotionalText != nil && description == nil && whatsNew == nil
        && keywords == nil && marketingURL == nil && supportURL == nil
        try Localizations.checkEditable(version, promotionalTextOnly: onlyPromoText)
        
        // Find the localization
        let locsResponse = try await client.send(
          Resources.v1.appStoreVersions.id(version.id)
            .appStoreVersionLocalizations.get(
              filterLocale: locale.map { [$0] }
            )
        )
        guard let localization = locsResponse.data.first else {
          let localeDesc = locale ?? "primary"
          throw ValidationError("No localization found for locale '\(localeDesc)'.")
        }
        
        let request = Resources.v1.appStoreVersionLocalizations.id(localization.id).patch(
          AppStoreVersionLocalizationUpdateRequest(
            data: .init(
              id: localization.id,
              attributes: .init(
                description: description,
                keywords: keywords,
                marketingURL: marketingURL.flatMap { URL(string: $0) },
                promotionalText: promotionalText,
                supportURL: supportURL.flatMap { URL(string: $0) },
                whatsNew: whatsNew
              )
            )
          )
        )
        
        let response = try await client.send(request)
        let attrs = response.data.attributes
        let versionString = version.attributes?.versionString ?? "unknown"
        success("Updated", "localization for version \(versionString) [\(attrs?.locale.map { localeName($0) } ?? "—")]")
        
        if let d = attrs?.description, !d.isEmpty { print("  Description:      \(d.prefix(80))\(d.count > 80 ? "..." : "")") }
        if let w = attrs?.whatsNew, !w.isEmpty { print("  What's New:       \(w.prefix(80))\(w.count > 80 ? "..." : "")") }
        if let k = attrs?.keywords, !k.isEmpty { print("  Keywords:         \(k.prefix(80))\(k.count > 80 ? "..." : "")") }
        if let p = attrs?.promotionalText, !p.isEmpty { print("  Promotional Text: \(p.prefix(80))\(p.count > 80 ? "..." : "")") }
        if let u = attrs?.marketingURL { print("  Marketing URL:    \(u)") }
        if let u = attrs?.supportURL { print("  Support URL:      \(u)") }
      }
    }
    
    // MARK: - Import
    
    struct Import: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Update localizations from a JSON file for the latest App Store version."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Path to the JSON file with localization data.",
              completion: .file(extensions: ["json"]))
      var file: String?

      @OptionGroup var platformOption: PlatformOption
      
      @Flag(name: .long, help: "Show full API response for each locale update.")
      var verbose = false
      
      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false
      
      func run() async throws {
        if yes { autoConfirm = true }
        let expandedPath = try resolveFile(file, extension: "json", prompt: "Select localizations JSON file")

        // Parse JSON
        let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
        let localeUpdates: [String: LocaleFields]
        do {
          localeUpdates = try JSONDecoder().decode([String: LocaleFields].self, from: data)
        } catch let error as DecodingError {
          throw ValidationError("Invalid JSON: \(describeDecodingError(error))")
        }
        
        if localeUpdates.isEmpty {
          throw ValidationError("JSON file contains no locale entries.")
        }
        
        // Show summary and confirm
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let version = try await findVersion(appID: app.id, versionString: nil, platform: try platformOption.parsed(), client: client)
        
        let effectiveUpdates = try resolveEffectiveUpdates(
          version: version, localeUpdates: localeUpdates)

        let versionString = version.attributes?.versionString ?? "unknown"
        let versionState = version.attributes?.appVersionState.map { formatState($0) } ?? "unknown"
        print("App:     \(app.attributes?.name ?? bundleID)")
        print("Version: \(versionString)")
        print("State:   \(versionState)")
        print()
        
        for (locale, fields) in effectiveUpdates.sorted(by: { $0.key < $1.key }) {
          print("[\(localeName(locale))]")
          if let d = fields.description { print("  Description:      \(d.prefix(80))\(d.count > 80 ? "..." : "")") }
          if let w = fields.whatsNew { print("  What's New:       \(w.prefix(80))\(w.count > 80 ? "..." : "")") }
          if let k = fields.keywords { print("  Keywords:         \(k.prefix(80))\(k.count > 80 ? "..." : "")") }
          if let p = fields.promotionalText { print("  Promotional Text: \(p.prefix(80))\(p.count > 80 ? "..." : "")") }
          if let u = fields.marketingURL { print("  Marketing URL:    \(u)") }
          if let u = fields.supportURL { print("  Support URL:      \(u)") }
          print()
        }

        guard confirm("Send updates for \(effectiveUpdates.count) locale(s)? [y/N] ") else {
          cancelled()
          return
        }
        print()
        
        // Fetch all localizations for this version
        let locsResponse = try await client.send(
          Resources.v1.appStoreVersions.id(version.id)
            .appStoreVersionLocalizations.get()
        )
        
        let locByLocale = Dictionary(
          locsResponse.data.compactMap { loc in
            loc.attributes?.locale.map { ($0, loc) }
          },
          uniquingKeysWith: { first, _ in first }
        )
        
        try await sendLocaleUpdates(
          effectiveUpdates, versionID: version.id, existing: locByLocale, client: client)

        print()
        print("Done.")
      }

      /// Computes which locale updates to send: when the version is no longer editable, keeps only
      /// promotional text (warning about ignored fields) and throws if nothing remains.
      private func resolveEffectiveUpdates(
        version: AppStoreVersion, localeUpdates: [String: LocaleFields]
      ) throws -> [String: LocaleFields] {
        guard let state = version.attributes?.appVersionState,
          !Localizations.editableStates.contains(state)
        else {
          return localeUpdates
        }
        let hasNonPromoFields = localeUpdates.values.contains { fields in
          fields.description != nil || fields.whatsNew != nil || fields.keywords != nil
            || fields.marketingURL != nil || fields.supportURL != nil
        }
        if hasNonPromoFields {
          print("Warning: Version is in state '\(state)' — only promotional text can be updated. Other fields will be ignored.")
          print()
        }
        let filtered = localeUpdates.compactMapValues { fields in
          fields.promotionalText != nil ? LocaleFields(promotionalText: fields.promotionalText) : nil
        }
        if filtered.isEmpty {
          throw ValidationError("No promotional text fields found in JSON — nothing to update in current version state.")
        }
        return filtered
      }

      /// Sends each locale's update, creating the localization (after confirmation) when absent.
      private func sendLocaleUpdates(
        _ updates: [String: LocaleFields], versionID: String,
        existing locByLocale: [String: AppStoreVersionLocalization],
        client: AppStoreConnectClient
      ) async throws {
        for (locale, fields) in updates.sorted(by: { $0.key < $1.key }) {
          guard let localization = locByLocale[locale] else {
            guard confirm("  [\(localeName(locale))] Locale not found in current localizations for the app. Create it? [y/N] ") else {
              print("  [\(localeName(locale))] Skipped.")
              continue
            }
            let response = try await client.send(
              Resources.v1.appStoreVersionLocalizations.post(
                AppStoreVersionLocalizationCreateRequest(
                  data: .init(
                    attributes: .init(
                      description: fields.description,
                      locale: locale,
                      keywords: fields.keywords,
                      marketingURL: fields.marketingURL.flatMap { URL(string: $0) },
                      promotionalText: fields.promotionalText,
                      supportURL: fields.supportURL.flatMap { URL(string: $0) },
                      whatsNew: fields.whatsNew
                    ),
                    relationships: .init(
                      appStoreVersion: .init(data: .init(id: versionID))
                    )
                  )
                )
              )
            )
            print("  [\(localeName(locale))] \(green("Created."))")
            if verbose { printLocaleResponse(response.data.attributes) }
            continue
          }

          let response = try await client.send(
            Resources.v1.appStoreVersionLocalizations.id(localization.id).patch(
              AppStoreVersionLocalizationUpdateRequest(
                data: .init(
                  id: localization.id,
                  attributes: .init(
                    description: fields.description,
                    keywords: fields.keywords,
                    marketingURL: fields.marketingURL.flatMap { URL(string: $0) },
                    promotionalText: fields.promotionalText,
                    supportURL: fields.supportURL.flatMap { URL(string: $0) },
                    whatsNew: fields.whatsNew
                  )
                )
              )
            )
          )
          print("  [\(localeName(locale))] Updated.")
          if verbose { printLocaleResponse(response.data.attributes) }
        }
      }

      /// Prints the verbose API response for a single localization (shared by create and update).
      private func printLocaleResponse(_ attrs: AppStoreVersionLocalization.Attributes?) {
        print("    Response:")
        print("      Locale:           \(attrs?.locale.map { localeName($0) } ?? "—")")
        if let d = attrs?.description { print("      Description:      \(d.prefix(120))\(d.count > 120 ? "..." : "")") }
        if let w = attrs?.whatsNew { print("      What's New:       \(w.prefix(120))\(w.count > 120 ? "..." : "")") }
        if let k = attrs?.keywords { print("      Keywords:         \(k.prefix(120))\(k.count > 120 ? "..." : "")") }
        if let p = attrs?.promotionalText { print("      Promotional Text: \(p.prefix(120))\(p.count > 120 ? "..." : "")") }
        if let u = attrs?.marketingURL { print("      Marketing URL:    \(u)") }
        if let u = attrs?.supportURL { print("      Support URL:      \(u)") }
      }
    }
    
    // MARK: - Export
    
    struct Export: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Export localizations to a JSON file from an App Store version."
      )
      
      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String
      
      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
      var version: String?

      @OptionGroup var platformOption: PlatformOption
      
      @Option(name: .long, help: "Output file path (default: <bundle-id>-localizations.json).",
              completion: .file(extensions: ["json"]))
      var output: String?
      
      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let version = try await findVersion(appID: app.id, versionString: version, platform: try platformOption.parsed(), client: client)
        
        let locsResponse = try await client.send(
          Resources.v1.appStoreVersions.id(version.id)
            .appStoreVersionLocalizations.get()
        )
        
        var result: [String: LocaleFields] = [:]
        for loc in locsResponse.data {
          guard let locale = loc.attributes?.locale else { continue }
          let attrs = loc.attributes
          result[locale] = LocaleFields(
            description: attrs?.description,
            whatsNew: attrs?.whatsNew,
            keywords: attrs?.keywords,
            promotionalText: attrs?.promotionalText,
            marketingURL: attrs?.marketingURL?.absoluteString,
            supportURL: attrs?.supportURL?.absoluteString
          )
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        
        let outputPath = expandPath(
          confirmOutputPath(output ?? "\(bundleID)-localizations.json", isDirectory: false))
        try data.write(to: URL(fileURLWithPath: outputPath))
        
        let versionString = version.attributes?.versionString ?? "unknown"
        success("Exported", "\(result.count) locale(s) for version \(versionString) to \(outputPath)")
      }
    }
  }
  
  struct CreateVersion: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "create-version",
      abstract: "Create a new App Store version."
    )
    
    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String
    
    @Argument(help: "The version string (e.g. 2.1.0).")
    var versionString: String
    
    @Option(name: .long, help: "Platform: ios, macos, tvos, visionos (default: ios).")
    var platform: String = "ios"
    
    @Option(name: .long, help: "Release type: manual, after-approval, scheduled. Defaults to previous version's setting.")
    var releaseType: String?
    
    @Option(name: .long, help: "Copyright notice (e.g. \"2026 Your Name\").")
    var copyright: String?
    
    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      
      let platformValue = try parsePlatform(platform)

      // Check if version already exists — for THIS platform: one app record
      // can hold the same version string per platform (universal purchase).
      let existingVersions = try await client.send(
        Resources.v1.apps.id(app.id).appStoreVersions.get(
          filterVersionString: [versionString]
        )
      )
      if let existing = existingVersions.data.first(where: {
        $0.attributes?.versionString == versionString && $0.attributes?.platform == platformValue
      }) {
        let state = existing.attributes?.appVersionState
        if state == .prepareForSubmission {
          print("Version \(versionString) already exists for \(platform) (PREPARE_FOR_SUBMISSION). Continuing.")
          return
        }
        throw ValidationError("Version \(versionString) already exists for \(platform) (state: \(state.map { formatState($0) } ?? "unknown")).")
      }
      
      let releaseTypeValue: AppStoreVersionCreateRequest.Data.Attributes.ReleaseType?
      if let releaseType {
        releaseTypeValue = switch releaseType.lowercased() {
          case "manual": .manual
          case "after-approval": .afterApproval
          case "scheduled": .scheduled
          default: throw ValidationError("Invalid release type '\(releaseType)'. Use: manual, after-approval, scheduled.")
        }
      } else {
        releaseTypeValue = nil
      }
      
      let request = Resources.v1.appStoreVersions.post(
        AppStoreVersionCreateRequest(
          data: .init(
            attributes: .init(
              platform: platformValue,
              versionString: versionString,
              copyright: copyright,
              releaseType: releaseTypeValue
            ),
            relationships: .init(
              app: .init(data: .init(id: app.id))
            )
          )
        )
      )
      
      let response = try await client.send(request)
      let attrs = response.data.attributes
      success("Created", "version \(attrs?.versionString ?? versionString)")
      print("  Platform:     \(attrs?.platform.map { formatState($0) } ?? "—")")
      print("  State:        \(attrs?.appVersionState.map { formatState($0) } ?? "—")")
      print("  Release Type: \(attrs?.releaseType.map { formatState($0) } ?? "—")")
    }
  }
  
  struct Copyright: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "View or update the copyright notice for an App Store version."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest editable version.")
    var version: String?

    @OptionGroup var platformOption: PlatformOption

    @Option(name: .customLong("set"), help: "New copyright notice (e.g. \"2026 Your Name\"). Omit to view the current one.")
    var newCopyright: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appVersion = try await findVersion(
        appID: app.id, versionString: version, platform: try platformOption.parsed(), client: client)

      let versionString = appVersion.attributes?.versionString ?? "unknown"
      let platformStr = appVersion.attributes?.platform.map { formatState($0) } ?? "—"
      let current = appVersion.attributes?.copyright

      guard let newCopyright else {
        print("App:       \(app.attributes?.name ?? bundleID)")
        print("Version:   \(versionString) (\(platformStr))")
        print("Copyright: \(current?.isEmpty == false ? current! : "—")")
        return
      }

      let state = appVersion.attributes?.appVersionState
      guard state == .prepareForSubmission || state == .waitingForReview else {
        throw ValidationError(
          "Version \(versionString) (\(platformStr)) is in state '\(state.map { formatState($0) } ?? "unknown")' — copyright can only be updated on an editable version.")
      }

      print("App:       \(app.attributes?.name ?? bundleID)")
      print("Version:   \(versionString) (\(platformStr))")
      print("Copyright: \(current?.isEmpty == false ? current! : "—") → \(newCopyright)")
      print()
      guard confirm("Update copyright? [y/N] ") else {
        cancelled()
        return
      }

      _ = try await client.send(
        Resources.v1.appStoreVersions.id(appVersion.id).patch(
          AppStoreVersionUpdateRequest(
            data: .init(
              id: appVersion.id,
              attributes: .init(copyright: newCopyright)
            )
          )
        )
      )

      print()
      success("Updated", "copyright for version \(versionString) (\(platformStr)).")
    }
  }

  struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "build",
      abstract: "Manage build attachments for App Store versions.",
      subcommands: [Attach.self, AttachLatest.self, Detach.self]
    )
    
    // MARK: - Attach
    
    struct Attach: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Interactively select and attach a build to an App Store version."
      )
      
      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String
      
      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
      var version: String?

      @OptionGroup var platformOption: PlatformOption
      
      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false
      
      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appVersion = try await findVersion(appID: app.id, versionString: version, platform: try platformOption.parsed(), client: client)
        
        let versionString = appVersion.attributes?.versionString ?? "unknown"
        print("Version: \(versionString)")
        print()
        
        let build = try await selectBuild(
          appID: app.id, versionID: appVersion.id, versionString: versionString,
          platform: appVersion.attributes?.platform, client: client)
        let buildNumber = build.attributes?.version ?? "unknown"
        let uploaded = build.attributes?.uploadedDate.map { formatDate($0) } ?? "—"
        print()
        success("Attached", "build \(buildNumber) (uploaded \(uploaded)) to version \(versionString).")
      }
    }
    
    // MARK: - Attach Latest
    
    struct AttachLatest: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "attach-latest",
        abstract: "Attach the most recent build to an App Store version."
      )
      
      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String
      
      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
      var version: String?

      @OptionGroup var platformOption: PlatformOption
      
      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false
      
      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appVersion = try await findVersion(appID: app.id, versionString: version, platform: try platformOption.parsed(), client: client)
        
        let versionString = appVersion.attributes?.versionString ?? "unknown"
        
        // If a build was just uploaded in this workflow for THIS version's platform,
        // wait for it to appear and process
        if let pendingBuild = lastUploadedBuild(for: appVersion.attributes?.platform) {
          print("Waiting for uploaded build \(pendingBuild) to become available...")
          print()
          let awaitedBuild = try await awaitBuildProcessing(
            appID: app.id,
            buildVersion: pendingBuild,
            platform: appVersion.attributes?.platform,
            client: client
          )
          let uploaded = awaitedBuild.attributes?.uploadedDate.map { formatDate($0) } ?? "—"
          print()
          print("Version: \(versionString)")
          print("Build:   \(pendingBuild)  VALID  \(uploaded)")
          print()
          
          guard confirm("Attach this build? [y/N] ") else {
            cancelled()
            return
          }
          
          try await client.send(
            Resources.v1.appStoreVersions.id(appVersion.id).relationships.build.patch(
              AppStoreVersionBuildLinkageRequest(
                data: .init(id: awaitedBuild.id)
              )
            )
          )
          
          print()
          success("Attached", "build \(pendingBuild) (uploaded \(uploaded)) to version \(versionString).")
          return
        }
        
        let buildsResponse = try await client.send(
          Resources.v1.builds.get(
            filterPreReleaseVersionVersion: [versionString],
            filterPreReleaseVersionPlatform: platformFilter(appVersion.attributes?.platform),
            filterApp: [app.id],
            sort: [.minusUploadedDate],
            limit: 1
          )
        )
        
        guard let build = buildsResponse.data.first else {
          throw ValidationError("No builds found for version \(versionString). Upload a build first via Xcode or Transporter.")
        }
        
        var latestBuild = build
        let buildNumber = latestBuild.attributes?.version ?? "unknown"
        let state = latestBuild.attributes?.processingState
        let uploaded = latestBuild.attributes?.uploadedDate.map { formatDate($0) } ?? "—"
        
        print("Version: \(versionString)")
        print("Build:   \(buildNumber)  \(state.map { formatState($0) } ?? "—")  \(uploaded)")
        print()
        
        if state == .processing {
          if confirm("Build \(buildNumber) is still processing. Wait for it to finish? [y/N] ") {
            print()
            latestBuild = try await awaitBuildProcessing(
              appID: app.id,
              buildVersion: buildNumber,
              platform: appVersion.attributes?.platform,
              client: client
            )
            print()
          } else {
            cancelled()
            return
          }
        } else if state == .failed || state == .invalid {
          print("Build \(buildNumber) has state \(state.map { formatState($0) } ?? "—") and cannot be attached.")
          throw ExitCode.failure
        }
        
        guard confirm("Attach this build? [y/N] ") else {
          cancelled()
          return
        }
        
        try await client.send(
          Resources.v1.appStoreVersions.id(appVersion.id).relationships.build.patch(
            AppStoreVersionBuildLinkageRequest(
              data: .init(id: latestBuild.id)
            )
          )
        )

        print()
        success("Attached", "build \(buildNumber) (uploaded \(uploaded)) to version \(versionString).")
      }
    }

    // MARK: - Detach
    
    struct Detach: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Remove the attached build from an App Store version."
      )
      
      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String
      
      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
      var version: String?

      @OptionGroup var platformOption: PlatformOption
      
      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false
      
      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appVersion = try await findVersion(appID: app.id, versionString: version, platform: try platformOption.parsed(), client: client)
        
        let versionString = appVersion.attributes?.versionString ?? "unknown"
        
        // Check if a build is attached
        let buildResponse = try await fetchOptionalResource(
          Resources.v1.appStoreVersions.id(appVersion.id).build.get(), client: client)
        guard let existingBuild = buildResponse?.data, existingBuild.attributes?.version != nil else {
          print("No build attached to version \(versionString).")
          return
        }
        
        let buildNumber = existingBuild.attributes?.version ?? "unknown"
        let uploaded = existingBuild.attributes?.uploadedDate.map { formatDate($0) } ?? "—"
        
        print("Version: \(versionString)")
        print("Build:   \(buildNumber) (uploaded \(uploaded))")
        print()
        
        guard confirm("Detach this build from version \(versionString)? [y/N] ") else {
          cancelled()
          return
        }
        
        // The API uses PATCH with {"data": null} to detach a build.
        // The typed AppStoreVersionBuildLinkageRequest requires non-null data,
        // so we construct the request manually using Request<Void>.
        let request = Request<Void>.patch(
          "/v1/appStoreVersions/\(appVersion.id)/relationships/build",
          body: NullRelationship()
        )
        try await client.send(request)
        
        print()
        success("Detached", "build \(buildNumber) from version \(versionString).")
      }
    }
  }
  
  struct PhasedRelease: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "phased-release",
      abstract: "View or manage phased release for an App Store version."
    )
    
    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String
    
    @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
    var version: String?

    @OptionGroup var platformOption: PlatformOption
    
    @Flag(name: .long, help: "Enable phased release (starts inactive, activates when version goes live).")
    var enable = false
    
    @Flag(name: .long, help: "Pause an active phased release.")
    var pause = false
    
    @Flag(name: .long, help: "Resume a paused phased release.")
    var resume = false
    
    @Flag(name: .long, help: "Complete immediately — release to all users.")
    var complete = false
    
    @Flag(name: .long, help: "Remove phased release entirely.")
    var disable = false
    
    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false
    
    func validate() throws {
      let flags = [enable, pause, resume, complete, disable].filter { $0 }
      if flags.count > 1 {
        throw ValidationError("Only one action flag can be used at a time (--enable, --pause, --resume, --complete, --disable).")
      }
    }
    
    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appVersion = try await findVersion(appID: app.id, versionString: version, platform: try platformOption.parsed(), client: client)
      
      let versionString = appVersion.attributes?.versionString ?? "unknown"
      let appName = app.attributes?.name ?? bundleID
      
      if enable {
        let request = Resources.v1.appStoreVersionPhasedReleases.post(
          AppStoreVersionPhasedReleaseCreateRequest(
            data: .init(
              attributes: .init(phasedReleaseState: .inactive),
              relationships: .init(
                appStoreVersion: .init(data: .init(id: appVersion.id))
              )
            )
          )
        )
        let response = try await client.send(request)
        let state = response.data.attributes?.phasedReleaseState.map { formatState($0) } ?? "—"
        success("Enabled", "phased release for version \(versionString).")
        print("  State: \(state)")
        return
      }
      
      // All other actions require an existing phased release
      let existing: AppStoreVersionPhasedRelease? = try await fetchOptionalResource(
        Resources.v1.appStoreVersions.id(appVersion.id).appStoreVersionPhasedRelease.get(),
        client: client
      )?.data
      
      if pause {
        guard let pr = existing else {
          throw ValidationError("No phased release configured for version \(versionString). Use --enable first.")
        }
        let request = Resources.v1.appStoreVersionPhasedReleases.id(pr.id).patch(
          AppStoreVersionPhasedReleaseUpdateRequest(
            data: .init(id: pr.id, attributes: .init(phasedReleaseState: .paused))
          )
        )
        let response = try await client.send(request)
        let state = response.data.attributes?.phasedReleaseState.map { formatState($0) } ?? "—"
        success("Paused", "phased release for version \(versionString).")
        print("  State: \(state)")
        return
      }
      
      if resume {
        guard let pr = existing else {
          throw ValidationError("No phased release configured for version \(versionString). Use --enable first.")
        }
        let request = Resources.v1.appStoreVersionPhasedReleases.id(pr.id).patch(
          AppStoreVersionPhasedReleaseUpdateRequest(
            data: .init(id: pr.id, attributes: .init(phasedReleaseState: .active))
          )
        )
        let response = try await client.send(request)
        let state = response.data.attributes?.phasedReleaseState.map { formatState($0) } ?? "—"
        success("Resumed", "phased release for version \(versionString).")
        print("  State: \(state)")
        return
      }
      
      if complete {
        guard let pr = existing else {
          throw ValidationError("No phased release configured for version \(versionString). Use --enable first.")
        }
        guard confirm("Complete phased release for version \(versionString)? This will release to all users immediately. [y/N] ") else {
          cancelled()
          return
        }
        let request = Resources.v1.appStoreVersionPhasedReleases.id(pr.id).patch(
          AppStoreVersionPhasedReleaseUpdateRequest(
            data: .init(id: pr.id, attributes: .init(phasedReleaseState: .complete))
          )
        )
        let response = try await client.send(request)
        let state = response.data.attributes?.phasedReleaseState.map { formatState($0) } ?? "—"
        success("Completed", "phased release for version \(versionString) — released to all users.")
        print("  State: \(state)")
        return
      }
      
      if disable {
        guard let pr = existing else {
          print("No phased release configured for version \(versionString).")
          return
        }
        guard confirm("Remove phased release for version \(versionString)? [y/N] ") else {
          cancelled()
          return
        }
        try await client.send(
          Resources.v1.appStoreVersionPhasedReleases.id(pr.id).delete
        )
        success("Removed", "phased release for version \(versionString).")
        return
      }
      
      // No flag — show current status
      guard let pr = existing else {
        print("App:            \(appName)")
        print("Version:        \(versionString)")
        print("Phased Release: Not configured")
        return
      }
      
      let attrs = pr.attributes
      let state = attrs?.phasedReleaseState.map { formatState($0) } ?? "—"
      let startDate = attrs?.startDate.map { formatDate($0) } ?? "—"
      let day = attrs?.currentDayNumber.map { "\($0)" } ?? "—"
      let pauseDuration = attrs?.totalPauseDuration ?? 0
      
      print("App:            \(appName)")
      print("Version:        \(versionString)")
      print("Phased Release: \(state)")
      print("  Start date:   \(startDate)")
      print("  Day:          \(day) of 7")
      print("  Paused:       \(pauseDuration) day\(pauseDuration == 1 ? "" : "s")")
    }
  }
  
  struct RoutingCoverage: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "routing-coverage",
      abstract: "View or upload routing app coverage (.geojson)."
    )
    
    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String
    
    @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
    var version: String?

    @OptionGroup var platformOption: PlatformOption
    
    @Option(name: .long, help: "Path to a .geojson file to upload.",
            completion: .file(extensions: ["geojson"]))
    var file: String?
    
    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false
    
    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appVersion = try await findVersion(appID: app.id, versionString: version, platform: try platformOption.parsed(), client: client)
      
      let versionString = appVersion.attributes?.versionString ?? "unknown"
      let appName = app.attributes?.name ?? bundleID
      
      guard let filePath = file else {
        // View mode
        let existing: RoutingAppCoverage? = try await fetchOptionalResource(
          Resources.v1.appStoreVersions.id(appVersion.id).routingAppCoverage.get(),
          client: client
        )?.data
        
        guard let coverage = existing else {
          print("App:              \(appName)")
          print("Version:          \(versionString)")
          print("Routing Coverage: Not configured")
          return
        }
        
        let attrs = coverage.attributes
        let fileName = attrs?.fileName ?? "—"
        let state = attrs?.assetDeliveryState?.state.map { formatState($0) } ?? "—"
        let fileSize = attrs?.fileSize.map { "\(formatBytes($0))" } ?? "—"
        
        print("App:              \(appName)")
        print("Version:          \(versionString)")
        print("Routing Coverage: \(fileName)")
        print("  Status:         \(state)")
        print("  Size:           \(fileSize)")
        return
      }
      
      // Upload mode
      let expandedPath = expandPath(filePath)
      let fm = FileManager.default
      
      guard fm.fileExists(atPath: expandedPath) else {
        throw ValidationError("File not found at '\(expandedPath)'.")
      }
      
      let fileAttrs = try fm.attributesOfItem(atPath: expandedPath)
      let fileSize = (fileAttrs[.size] as? Int) ?? 0
      let fileName = (expandedPath as NSString).lastPathComponent
      
      // Check for existing coverage
      let existing: RoutingAppCoverage? = try await fetchOptionalResource(
        Resources.v1.appStoreVersions.id(appVersion.id).routingAppCoverage.get(),
        client: client
      )?.data
      
      if let existingCoverage = existing {
        let existingName = existingCoverage.attributes?.fileName ?? "unknown"
        print("Existing routing coverage: \(existingName)")
        guard confirm("Replace existing routing coverage with '\(fileName)'? [y/N] ") else {
          cancelled()
          return
        }
        try await client.send(
          Resources.v1.routingAppCoverages.id(existingCoverage.id).delete
        )
        success("Deleted", "existing coverage.")
        print()
      }
      
      print("Uploading \(fileName) (\(formatBytes(fileSize)))...")
      fflush(stdout)
      
      // Reserve
      let reserveResponse = try await client.send(
        Resources.v1.routingAppCoverages.post(
          RoutingAppCoverageCreateRequest(
            data: .init(
              attributes: .init(fileSize: fileSize, fileName: fileName),
              relationships: .init(
                appStoreVersion: .init(data: .init(id: appVersion.id))
              )
            )
          )
        )
      )
      
      let coverageID = reserveResponse.data.id
      guard let operations = reserveResponse.data.attributes?.uploadOperations,
            !operations.isEmpty else {
        throw MediaUploadError.noUploadOperations
      }
      
      // Upload chunks
      try await uploadChunks(filePath: expandedPath, operations: operations)
      
      // Commit
      let checksum = try md5Hex(filePath: expandedPath)
      _ = try await client.send(
        Resources.v1.routingAppCoverages.id(coverageID).patch(
          RoutingAppCoverageUpdateRequest(
            data: .init(
              id: coverageID,
              attributes: .init(sourceFileChecksum: checksum, isUploaded: true)
            )
          )
        )
      )
      
      success("Uploaded", "routing coverage '\(fileName)' for version \(versionString).")
    }
  }
  
  struct ReviewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "review",
      abstract: "Manage review submissions.",
      subcommands: [Preflight.self, Status.self, Submit.self, ResolveIssues.self, CancelSubmission.self, Info.self, Attachment.self]
    )
    
    // MARK: - Preflight

    struct Preflight: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Run pre-submission checks for a version."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
      var version: String?

      @OptionGroup var platformOption: PlatformOption

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appVersion = try await findVersion(appID: app.id, versionString: version, platform: try platformOption.parsed(), client: client)

        let versionString = appVersion.attributes?.versionString ?? "unknown"
        let versionState = appVersion.attributes?.appVersionState
        let stateStr = versionState.map { formatState($0) } ?? "unknown"
        let appName = app.attributes?.name ?? bundleID

        print("Preflight checks for \(appName) v\(versionString) (\(stateStr))")
        print()

        var rows: [[String]] = []
        var failCount = 0

        // 1. Version state
        print("Checking version state...")
        let editable = versionState.map { Localizations.editableStates.contains($0) } ?? false
        if editable {
          rows.append(["Version state", green("✓") + " \(stateStr)"])
        } else {
          rows.append(["Version state", red("✗") + " \(stateStr) (not editable)"])
          failCount += 1
        }

        // 2. Build attached
        print("Checking build...")
        do {
          let buildResponse = try await client.send(
            Resources.v1.appStoreVersions.id(appVersion.id).build.get()
          )
          let buildNumber = buildResponse.data.attributes?.version ?? "unknown"
          rows.append(["Build attached", green("✓") + " Build \(buildNumber)"])
        } catch is DecodingError {
          rows.append(["Build attached", red("✗") + " No build attached"])
          failCount += 1
        }

        // 3. Fetch version localizations
        // What's New only exists for updates — if no earlier version of this platform
        // was ever released, the field isn't required (or even settable).
        let releasedResponse = try await client.send(
          Resources.v1.apps.id(app.id).appStoreVersions.get(
            filterPlatform: platformFilter(appVersion.attributes?.platform),
            filterAppVersionState: [.readyForDistribution, .replacedWithNewVersion],
            limit: 2
          )
        )
        let hasReleasedVersion = releasedResponse.data.contains { $0.id != appVersion.id }
        print("Fetching localizations...")
        let locsResponse = try await client.send(
          Resources.v1.appStoreVersions.id(appVersion.id)
            .appStoreVersionLocalizations.get()
        )
        let versionLocs = locsResponse.data.sorted {
          ($0.attributes?.locale ?? "") < ($1.attributes?.locale ?? "")
        }

        // 4. Fetch app-info localizations
        print("Fetching app info...")
        let appInfoResponse = try await client.send(
          Resources.v1.apps.id(app.id).appInfos.get(
            include: [.appInfoLocalizations],
            limitAppInfoLocalizations: 50
          )
        )
        var appInfoByLocale: [String: AppInfoLocalization] = [:]
        if let appInfo = appInfoResponse.data.first(where: { $0.attributes?.state != .replacedWithNewInfo })
            ?? appInfoResponse.data.first {
          let locIDs = Set(appInfo.relationships?.appInfoLocalizations?.data?.map(\.id) ?? [])
          let infoLocs = appInfoResponse.included?.compactMap { item -> AppInfoLocalization? in
            if case .appInfoLocalization(let loc) = item, locIDs.contains(loc.id) {
              return loc
            }
            return nil
          } ?? []
          for loc in infoLocs {
            if let locale = loc.attributes?.locale {
              appInfoByLocale[locale] = loc
            }
          }
        }

        // 5. Fetch screenshots per locale. Two bounded-concurrency phases (sets, then
        // screenshots) replace the sequential L + L×S call chain with identical counts.
        print("Fetching screenshots...")
        let setsByLocale = try await boundedConcurrentMap(versionLocs) { loc in
          let setsResponse = try await client.send(
            Resources.v1.appStoreVersionLocalizations.id(loc.id)
              .appScreenshotSets.get(limit: 50)
          )
          return (loc.attributes?.locale ?? "unknown", setsResponse.data.map(\.id))
        }

        let countsBySet = Dictionary(
          try await boundedConcurrentMap(setsByLocale.flatMap(\.1)) { setID in
            let screenshotsResponse = try await client.send(
              Resources.v1.appScreenshotSets.id(setID).appScreenshots.get()
            )
            return (setID, screenshotsResponse.data.count)
          },
          uniquingKeysWith: { first, _ in first }
        )

        var screenshotsByLocale: [String: (sets: Int, count: Int)] = [:]
        for (locale, setIDs) in setsByLocale {
          let nonEmpty = setIDs.compactMap { countsBySet[$0] }.filter { $0 > 0 }
          screenshotsByLocale[locale] = (nonEmpty.count, nonEmpty.reduce(0, +))
        }

        // 6. Build per-locale rows
        let localeCheck = buildLocaleRows(
          versionLocs: versionLocs, appInfoByLocale: appInfoByLocale,
          screenshotsByLocale: screenshotsByLocale, requireWhatsNew: hasReleasedVersion)
        rows += localeCheck.rows
        failCount += localeCheck.failures

        // 7. In-app purchases
        let iapCheck = try await checkInAppPurchases(appID: app.id, client: client)
        rows += iapCheck.rows
        failCount += iapCheck.failures

        // 8. Subscriptions
        let subCheck = try await checkSubscriptions(appID: app.id, client: client)
        rows += subCheck.rows
        failCount += subCheck.failures

        let passCount = rows.count(where: { $0[1].contains("✓") })
        print()

        Table.print(
          headers: ["Check", "Status"],
          rows: rows
        )

        print()
        let resultText = "\(green("\(passCount) passed")), \(failCount > 0 ? red("\(failCount) failed") : "\(failCount) failed")"
        print("Result: \(resultText)")

        if failCount > 0 {
          throw ExitCode.failure
        }
      }

      /// Builds the per-locale app-info / localization / screenshot rows for the preflight table.
      private func buildLocaleRows(
        versionLocs: [AppStoreVersionLocalization],
        appInfoByLocale: [String: AppInfoLocalization],
        screenshotsByLocale: [String: (sets: Int, count: Int)],
        requireWhatsNew: Bool
      ) -> (rows: [[String]], failures: Int) {
        var rows: [[String]] = []
        var failures = 0
        let allLocales = Set(versionLocs.compactMap { $0.attributes?.locale })
          .union(appInfoByLocale.keys)
          .sorted()

        for locale in allLocales {
          rows.append(["", ""])
          rows.append([localeName(locale), ""])

          // App info
          if let info = appInfoByLocale[locale] {
            var missing: [String] = []
            if info.attributes?.name == nil || info.attributes?.name?.isEmpty == true {
              missing.append(formatFieldName("name"))
            }
            if info.attributes?.subtitle == nil || info.attributes?.subtitle?.isEmpty == true {
              missing.append(formatFieldName("subtitle"))
            }
            if info.attributes?.privacyPolicyURL == nil || info.attributes?.privacyPolicyURL?.isEmpty == true {
              missing.append(formatFieldName("privacyPolicyURL"))
            }
            if missing.isEmpty {
              rows.append(["  App info", green("✓") + " All fields filled"])
            } else {
              rows.append(["  App info", red("✗") + " Missing: \(missing.joined(separator: ", "))"])
              failures += 1
            }
          }

          // Version localizations
          if let loc = versionLocs.first(where: { $0.attributes?.locale == locale }) {
            var missing: [String] = []
            var invalid: [String] = []
            let desc = loc.attributes?.description ?? ""
            if desc.isEmpty {
              missing.append(formatFieldName("description"))
            } else if desc.count < 10 {
              invalid.append("\(formatFieldName("description")) too short (<10 chars)")
            } else if desc.count > 4000 {
              invalid.append("\(formatFieldName("description")) too long (>4000 chars)")
            }
            if requireWhatsNew {
              let whatsNew = loc.attributes?.whatsNew ?? ""
              if whatsNew.isEmpty {
                missing.append(formatFieldName("whatsNew"))
              } else if whatsNew.count < 7 {
                invalid.append("\(formatFieldName("whatsNew")) too short (<7 chars)")
              } else if whatsNew.count > 4000 {
                invalid.append("\(formatFieldName("whatsNew")) too long (>4000 chars)")
              }
            }
            if loc.attributes?.keywords == nil || loc.attributes?.keywords?.isEmpty == true {
              missing.append(formatFieldName("keywords"))
            }
            if loc.attributes?.supportURL == nil {
              missing.append(formatFieldName("supportURL"))
            }
            if missing.isEmpty && invalid.isEmpty {
              rows.append(["  Localizations", green("✓") + " All fields filled"])
            } else {
              var parts: [String] = []
              if !missing.isEmpty { parts.append("Missing: \(missing.joined(separator: ", "))") }
              if !invalid.isEmpty { parts.append(invalid.joined(separator: ", ")) }
              rows.append(["  Localizations", red("✗") + " \(parts.joined(separator: "; "))"])
              failures += 1
            }
          }

          // Screenshots
          if let ss = screenshotsByLocale[locale] {
            if ss.count > 0 {
              rows.append(["  Screenshots", green("✓") + " \(ss.sets) set\(ss.sets == 1 ? "" : "s"), \(ss.count) screenshot\(ss.count == 1 ? "" : "s")"])
            } else {
              rows.append(["  Screenshots", red("✗") + " No screenshots"])
              failures += 1
            }
          }
        }
        return (rows, failures)
      }

      /// Checks each in-app purchase's price schedule and state, returning preflight rows.
      private func checkInAppPurchases(
        appID: String, client: AppStoreConnectClient
      ) async throws -> (rows: [[String]], failures: Int) {
        print("Checking in-app purchases...")
        var rows: [[String]] = []
        var failures = 0
        var iaps: [InAppPurchaseV2] = []
        for try await page in client.pages(
          Resources.v1.apps.id(appID).inAppPurchasesV2.get(limit: 200)
        ) {
          iaps.append(contentsOf: page.data)
        }

        if !iaps.isEmpty {
          rows.append(["", ""])
          rows.append(["In-App Purchases (\(iaps.count))", ""])
          let sortedIAPs = iaps.sorted(by: { ($0.attributes?.productID ?? "") < ($1.attributes?.productID ?? "") })
          let schedules = try await boundedConcurrentMap(sortedIAPs.map(\.id)) { id in
            try await IAPCommand.iapPriceScheduleExists(iapID: id, client: client)
          }
          for (iap, hasSchedule) in zip(sortedIAPs, schedules) {
            let label = "  " + (iap.attributes?.productID ?? iap.attributes?.name ?? iap.id)
            let state = iap.attributes?.state
            let stateStr = state.map { formatState($0) } ?? "unknown"

            if !hasSchedule {
              rows.append([label, red("✗") + " No price schedule"])
              failures += 1
            } else if state == .readyToSubmit || state == .approved
                      || state == .waitingForReview || state == .inReview {
              rows.append([label, green("✓") + " \(stateStr)"])
            } else {
              rows.append([label, red("✗") + " \(stateStr)"])
              failures += 1
            }
          }
        }
        return (rows, failures)
      }

      /// Checks each subscription's prices and state, returning preflight rows.
      private func checkSubscriptions(
        appID: String, client: AppStoreConnectClient
      ) async throws -> (rows: [[String]], failures: Int) {
        print("Checking subscriptions...")
        var rows: [[String]] = []
        var failures = 0
        let subGroups = try await SubCommand.fetchGroups(appID: appID, client: client)
        let allSubs = subGroups.flatMap(\.subscriptions)

        if !allSubs.isEmpty {
          rows.append(["", ""])
          rows.append(["Subscriptions (\(allSubs.count))", ""])
          let sortedSubs = allSubs.sorted(by: { ($0.attributes?.productID ?? "") < ($1.attributes?.productID ?? "") })
          let priced = try await boundedConcurrentMap(sortedSubs.map(\.id)) { id in
            try await SubCommand.subscriptionHasPrices(subscriptionID: id, client: client)
          }
          for (sub, hasPrices) in zip(sortedSubs, priced) {
            let label = "  " + (sub.attributes?.productID ?? sub.attributes?.name ?? sub.id)
            let state = sub.attributes?.state
            let stateStr = state.map { formatState($0) } ?? "unknown"

            if !hasPrices {
              rows.append([label, red("✗") + " No prices set"])
              failures += 1
            } else if state == .readyToSubmit || state == .approved
                      || state == .waitingForReview || state == .inReview {
              rows.append([label, green("✓") + " \(stateStr)"])
            } else {
              rows.append([label, red("✗") + " \(stateStr)"])
              failures += 1
            }
          }
        }
        return (rows, failures)
      }
    }

    // MARK: - Status

    struct Status: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Show review submission status."
      )
      
      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String
      
      @Option(name: .long, help: "Filter by version string (e.g. 14.3).")
      var version: String?
      
      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        
        let response = try await client.send(
          Resources.v1.apps.id(app.id).reviewSubmissions.get(
            fieldsAppStoreVersions: [.versionString, .appVersionState],
            include: [.appStoreVersionForReview, .items]
          )
        )
        
        if response.data.isEmpty {
          print("No review submissions found.")
          return
        }
        
        // Index included items for lookup
        var includedVersions: [String: AppStoreVersion] = [:]
        var includedItems: [String: ReviewSubmissionItem] = [:]
        for item in response.included ?? [] {
          switch item {
            case .appStoreVersion(let v): includedVersions[v.id] = v
            case .reviewSubmissionItem(let i): includedItems[i.id] = i
            default: break
          }
        }
        
        // Resolve version string for each submission and filter if requested
        func versionString(for submission: ReviewSubmission) -> String {
          guard let versionRef = submission.relationships?.appStoreVersionForReview?.data,
                let v = includedVersions[versionRef.id] else { return "—" }
          return v.attributes?.versionString ?? "—"
        }
        
        let submissions = version != nil
        ? response.data.filter { versionString(for: $0) == version }
        : response.data
        
        if submissions.isEmpty {
          print("No review submissions found for version \(version!).")
          return
        }
        
        var rows: [[String]] = []
        for submission in submissions {
          let attrs = submission.attributes
          let platform = attrs?.platform.map { formatState($0) } ?? "—"
          let state = attrs?.state.map { formatState($0) } ?? "—"
          let submitted = attrs?.submittedDate.map { formatDate($0) } ?? "—"
          rows.append([platform, versionString(for: submission), state, submitted])
        }

        Table.print(
          headers: ["Platform", "Version", "State", "Submitted"],
          rows: rows
        )

        // Show details for active submissions with issues
        for submission in submissions {
          guard let state = submission.attributes?.state,
                state == .unresolvedIssues || state == .inReview || state == .waitingForReview
          else { continue }

          // Get version info
          var versionInfo = ""
          if let versionRef = submission.relationships?.appStoreVersionForReview?.data,
             let v = includedVersions[versionRef.id] {
            let vs = v.attributes?.versionString ?? "?"
            let vState = v.attributes?.appVersionState.map { formatState($0) } ?? "?"
            versionInfo = " — v\(vs) (\(vState))"
          }

          print()
          print("--- Submission \(submission.id) (\(formatState(state)))\(versionInfo) ---")

          // Show items from included data
          let itemRefs = submission.relationships?.items?.data ?? []
          if !itemRefs.isEmpty {
            for ref in itemRefs {
              if let item = includedItems[ref.id] {
                let itemState = item.attributes?.state.map { formatState($0) } ?? "—"
                print("  Item: \(itemState)")
              }
            }
          }
          
          if state == .unresolvedIssues {
            print()
            print("  View rejection notes in App Store Connect Resolution Center.")
          }
        }
      }
    }
    
    // MARK: - Submit
    
    struct Submit: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Submit an App Store version for review."
      )
      
      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String
      
      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
      var version: String?

      @Option(name: .long, help: "Platform: ios, macos, tvos, visionos (default: ios).")
      var platform: String = "ios"
      
      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false
      
      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let platformValue = try parsePlatform(platform)
        let app = try await findApp(bundleID: bundleID, client: client)
        let appVersion = try await findVersion(
          appID: app.id, versionString: version, platform: platformValue, client: client)

        let versionString = appVersion.attributes?.versionString ?? "unknown"
        let versionState = appVersion.attributes?.appVersionState.map { formatState($0) } ?? "unknown"

        guard try await confirmBuildAttached(
          app: app, appVersion: appVersion, versionString: versionString,
          versionState: versionState, platformValue: platformValue, client: client)
        else { return }
        print()

        guard
          let submissionID = try await resolveSubmission(
            app: app, appVersion: appVersion, versionString: versionString,
            platformValue: platformValue, client: client)
        else { return }

        try await submitBundledProducts(app: app, client: client)

        // Step 3: Submit for review
        let submitRequest = Resources.v1.reviewSubmissions.id(submissionID).patch(
          ReviewSubmissionUpdateRequest(
            data: .init(
              id: submissionID,
              attributes: .init(isSubmitted: true)
            )
          )
        )
        let result = try await client.send(submitRequest)
        let state = result.data.attributes?.state.map { formatState($0) } ?? "unknown"
        print()
        success("Submitted for review.")
        print("  State: \(state)")
      }

      private func confirmBuildAttached(
        app: App, appVersion: AppStoreVersion, versionString: String,
        versionState: String, platformValue: Platform, client: AppStoreConnectClient
      ) async throws -> Bool {
        // Check if a build is already attached
        let existingBuild: Build? = try await fetchOptionalResource(
          Resources.v1.appStoreVersions.id(appVersion.id).build.get(), client: client
        )?.data
        
        if let build = existingBuild, build.attributes?.version != nil {
          let buildNumber = build.attributes?.version ?? "unknown"
          let uploaded = build.attributes?.uploadedDate.map { formatDate($0) } ?? "—"
          print("App:      \(app.attributes?.name ?? bundleID)")
          print("Version:  \(versionString)")
          print("Build:    \(buildNumber) (uploaded \(uploaded))")
          print("State:    \(versionState)")
          print("Platform: \(platformValue)")
          print()
          guard confirm("Submit this version for App Review? [y/N] ") else {
            cancelled()
            return false
          }
        } else {
          print("App:      \(app.attributes?.name ?? bundleID)")
          print("Version:  \(versionString)")
          print("State:    \(versionState)")
          print("Platform: \(platformValue)")
          print()
          print("No build attached to this version. Select a build first:")
          print()
          let selected = try await selectBuild(
            appID: app.id, versionID: appVersion.id, versionString: versionString,
            platform: platformValue, client: client)
          let buildNumber = selected.attributes?.version ?? "unknown"
          print()
          print("Build \(buildNumber) attached. Continuing with submission...")
          print()
          guard confirm("Submit this version for App Review? [y/N] ") else {
            cancelled()
            print("Note: build \(buildNumber) remains attached to the version.")
            return false
          }
        }
        return true
      }

      private func resolveSubmission(
        app: App, appVersion: AppStoreVersion, versionString: String,
        platformValue: Platform, client: AppStoreConnectClient
      ) async throws -> String? {
        // Check for existing active review submissions
        let existingSubmissions = try await client.send(
          Resources.v1.apps.id(app.id).reviewSubmissions.get(
            filterState: [.readyForReview, .waitingForReview, .inReview, .unresolvedIssues]
          )
        )
        
        // A universal-purchase app can have one active submission per platform —
        // only an active submission for THIS platform counts.
        let submissionID: String
        if let active = existingSubmissions.data.first(where: { $0.attributes?.platform == platformValue }) {
          let activeState = active.attributes?.state
          
          switch activeState {
            case .waitingForReview, .inReview:
              print("Version is already submitted for review (state: \(activeState.map { formatState($0) } ?? "—")).")
              return nil
            case .readyForReview:
              print("Found existing review submission (state: readyForReview). Resubmitting...")
              submissionID = active.id
            case .unresolvedIssues:
              print("Found existing review submission with unresolved issues from a previous review.")
              guard confirm("Resubmit for review? [y/N] ") else {
                cancelled()
                return nil
              }
              submissionID = active.id
            default:
              submissionID = active.id
          }
        } else {
          // Step 1: Create a review submission
          let createSubmission = Resources.v1.reviewSubmissions.post(
            ReviewSubmissionCreateRequest(
              data: .init(
                attributes: .init(platform: platformValue),
                relationships: .init(
                  app: .init(data: .init(id: app.id))
                )
              )
            )
          )
          let submission = try await client.send(createSubmission)
          submissionID = submission.data.id
          print("Created review submission (\(submissionID))")
          
          // Step 2: Add the app store version as a review item
          let createItem = Resources.v1.reviewSubmissionItems.post(
            ReviewSubmissionItemCreateRequest(
              data: .init(
                relationships: .init(
                  reviewSubmission: .init(data: .init(id: submissionID)),
                  appStoreVersion: .init(data: .init(id: appVersion.id))
                )
              )
            )
          )
          _ = try await client.send(createItem)
          print("Added version \(versionString) to submission")
        }
        return submissionID
      }

      private func submitBundledProducts(app: App, client: AppStoreConnectClient) async throws {
        // Offer to submit IAPs/subscriptions alongside the app version.
        // APPROVED products keep that state even when they have pending edits — the
        // pending version surfaces as non-approved child localization states. The API
        // rejects submissions with no pending version (HTTP 409; used to be a no-op).
        let candidateIAPStates: Set<InAppPurchaseState> = [.readyToSubmit, .approved]
        let candidateSubStates: Set<Subscription.Attributes.State> = [.readyToSubmit, .approved]

        var fetchedIAPs: [InAppPurchaseV2] = []
        let iapRequest = Resources.v1.apps.id(app.id).inAppPurchasesV2.get(limit: 200)
        for try await page in client.pages(iapRequest) {
          fetchedIAPs.append(contentsOf: page.data)
        }

        let groups = try await SubCommand.fetchGroups(appID: app.id, client: client)
        let fetchedSubs = groups.flatMap(\.subscriptions)

        let skippedIAPs = fetchedIAPs.filter {
          !($0.attributes?.state.flatMap { candidateIAPStates.contains($0) } ?? false)
        }
        let skippedSubs = fetchedSubs.filter {
          !($0.attributes?.state.flatMap { candidateSubStates.contains($0) } ?? false)
        }

        // Partition candidates by whether they actually have a pending version.
        var submittableIAPs: [InAppPurchaseV2] = []
        var unchangedIAPs: [InAppPurchaseV2] = []
        for iap in fetchedIAPs where iap.attributes?.state.flatMap({ candidateIAPStates.contains($0) }) ?? false {
          if try await iapHasPendingVersion(iap, client: client) {
            submittableIAPs.append(iap)
          } else {
            unchangedIAPs.append(iap)
          }
        }

        var submittableSubIDs: Set<String> = []
        var unchangedSubs: [Subscription] = []
        for sub in fetchedSubs where sub.attributes?.state.flatMap({ candidateSubStates.contains($0) }) ?? false {
          if try await subHasPendingVersion(sub, client: client) {
            submittableSubIDs.insert(sub.id)
          } else {
            unchangedSubs.append(sub)
          }
        }

        // A group is submitted for its pending subscriptions and/or its own
        // pending group-level localizations.
        var groupLocalizationsPending: [String: Bool] = [:]
        var submittableGroups: [SubCommand.GroupInfo] = []
        for group in groups {
          let hasPendingSubs = group.subscriptions.contains { submittableSubIDs.contains($0.id) }
          let hasPendingLocs = try await groupHasPendingLocalizations(group, client: client)
          groupLocalizationsPending[group.id] = hasPendingLocs
          if hasPendingSubs || hasPendingLocs {
            submittableGroups.append(group)
          }
        }

        if !skippedIAPs.isEmpty || !skippedSubs.isEmpty || !unchangedIAPs.isEmpty || !unchangedSubs.isEmpty {
          print()
          print("Skipping items not eligible for submission:")
          for iap in skippedIAPs {
            print("  IAP: \(iap.attributes?.name ?? "—") (\(iap.attributes?.productID ?? "—")) — \(iap.attributes?.state.map { formatState($0) } ?? "—")")
          }
          for sub in skippedSubs {
            print("  Sub: \(sub.attributes?.name ?? "—") (\(sub.attributes?.productID ?? "—")) — \(sub.attributes?.state.map { formatState($0) } ?? "—")")
          }
          for iap in unchangedIAPs {
            print("  IAP: \(iap.attributes?.name ?? "—") (\(iap.attributes?.productID ?? "—")) — Approved (no pending changes)")
          }
          for sub in unchangedSubs {
            print("  Sub: \(sub.attributes?.name ?? "—") (\(sub.attributes?.productID ?? "—")) — Approved (no pending changes)")
          }
        }

        if !submittableIAPs.isEmpty || !submittableGroups.isEmpty {
          print()
          print(yellow("In-app purchases/subscriptions with pending changes:"))
          for iap in submittableIAPs {
            print("  IAP: \(iap.attributes?.name ?? "—") (\(iap.attributes?.productID ?? "—")) — \(iap.attributes?.state.map { formatState($0) } ?? "—")")
          }
          for group in submittableGroups {
            let locsNote = groupLocalizationsPending[group.id] == true ? " (group localizations changed)" : ""
            print("  Group: \(group.name)\(locsNote)")
            for sub in group.subscriptions where submittableSubIDs.contains(sub.id) {
              print("    Sub: \(sub.attributes?.name ?? "—") (\(sub.attributes?.productID ?? "—")) — \(sub.attributes?.state.map { formatState($0) } ?? "—")")
            }
          }
          print()

          if confirm("Submit these with the app version? [y/N] ") {
            for iap in submittableIAPs {
              do {
                _ = try await client.send(
                  Resources.v1.inAppPurchaseSubmissions.post(
                    InAppPurchaseSubmissionCreateRequest(
                      data: .init(
                        relationships: .init(
                          inAppPurchaseV2: .init(data: .init(id: iap.id))
                        )
                      )
                    )
                  )
                )
                print("  \(green("Submitted")) IAP '\(iap.attributes?.name ?? "—")'")
              } catch let error where isNoPendingVersionError(error) {
                print("  Skipped IAP '\(iap.attributes?.name ?? "—")' — no pending version")
              }
            }
            for group in submittableGroups {
              // Submit individual subscriptions
              for sub in group.subscriptions where submittableSubIDs.contains(sub.id) {
                do {
                  _ = try await client.send(
                    Resources.v1.subscriptionSubmissions.post(
                      SubscriptionSubmissionCreateRequest(
                        data: .init(
                          relationships: .init(
                            subscription: .init(data: .init(id: sub.id))
                          )
                        )
                      )
                    )
                  )
                  print("  \(green("Submitted")) subscription '\(sub.attributes?.name ?? "—")'")
                } catch let error where isNoPendingVersionError(error) {
                  print("  Skipped subscription '\(sub.attributes?.name ?? "—")' — no pending version")
                }
              }
              // Submit the group itself only when its localizations changed
              guard groupLocalizationsPending[group.id] == true else { continue }
              do {
                _ = try await client.send(
                  Resources.v1.subscriptionGroupSubmissions.post(
                    SubscriptionGroupSubmissionCreateRequest(
                      data: .init(
                        relationships: .init(
                          subscriptionGroup: .init(data: .init(id: group.id))
                        )
                      )
                    )
                  )
                )
                print("  \(green("Submitted")) subscription group '\(group.name)'")
              } catch let error where isNoPendingVersionError(error) {
                print("  Skipped subscription group '\(group.name)' — no pending version")
              }
            }
          }
        }
      }

      // READY_TO_SUBMIT always has a pending (first or edited) version. APPROVED
      // products need a localization check: any non-approved localization state
      // (PREPARE_FOR_SUBMISSION, REJECTED) means edits are awaiting submission.
      private func iapHasPendingVersion(_ iap: InAppPurchaseV2, client: AppStoreConnectClient) async throws -> Bool {
        if iap.attributes?.state == .readyToSubmit { return true }
        let locsResponse = try await client.send(
          Resources.v2.inAppPurchases.id(iap.id).inAppPurchaseLocalizations.get(limit: 50)
        )
        return locsResponse.data.contains { $0.attributes?.state != .approved }
      }

      private func subHasPendingVersion(_ sub: Subscription, client: AppStoreConnectClient) async throws -> Bool {
        if sub.attributes?.state == .readyToSubmit { return true }
        let locsResponse = try await client.send(
          Resources.v1.subscriptions.id(sub.id).subscriptionLocalizations.get(limit: 50)
        )
        return locsResponse.data.contains { $0.attributes?.state != .approved }
      }

      private func groupHasPendingLocalizations(_ group: SubCommand.GroupInfo, client: AppStoreConnectClient) async throws -> Bool {
        let locsResponse = try await client.send(
          Resources.v1.subscriptionGroups.id(group.id).subscriptionGroupLocalizations.get(limit: 50)
        )
        return locsResponse.data.contains { $0.attributes?.state != .approved }
      }

      // Safety net for when the localization-based detection over-reports — treat
      // the API's "no pending version" 409 as a per-item skip, not a hard failure.
      private func isNoPendingVersionError(_ error: Error) -> Bool {
        guard let responseError = error as? ResponseError,
              case .requestFailure(let errorResponse, let statusCode, _) = responseError,
              statusCode == 409 else { return false }
        return errorResponse?.errors?.contains {
          $0.detail.localizedCaseInsensitiveContains("no pending version")
        } ?? false
      }
    }

    // MARK: - Resolve Issues
    
    struct ResolveIssues: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Mark rejected review items as resolved."
      )
      
      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @OptionGroup var platformOption: PlatformOption

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)

        // Find submission with unresolved issues
        let response = try await client.send(
          Resources.v1.apps.id(app.id).reviewSubmissions.get(
            filterState: [.unresolvedIssues],
            fieldsAppStoreVersions: [.versionString, .appVersionState],
            include: [.appStoreVersionForReview, .items]
          )
        )

        guard let (submission, versionString) = try selectSubmission(
          from: response, platform: platformOption.parsed())
        else {
          print("No submissions with unresolved issues found.")
          return
        }

        // Get rejected items from included data
        let itemRefs = submission.relationships?.items?.data ?? []
        var rejectedItems: [ReviewSubmissionItem] = []
        if let included = response.included {
          for ref in itemRefs {
            for item in included {
              if case .reviewSubmissionItem(let i) = item,
                 i.id == ref.id,
                 i.attributes?.state == .rejected {
                rejectedItems.append(i)
              }
            }
          }
        }
        
        print("Submission: \(submission.id)")
        print("Platform:   \(submission.attributes?.platform.map { formatState($0) } ?? "—")")
        print("Version:    \(versionString)")
        print("State:      unresolvedIssues")
        print("Items:      \(rejectedItems.count) rejected")
        
        if rejectedItems.isEmpty {
          print()
          print("No rejected items to resolve.")
          return
        }
        
        print()
        print("WARNING: Before resolving, make sure you have:")
        print("  1. Read the rejection notes in App Store Connect Resolution Center")
        print("  2. Fixed the issues in your app or metadata")
        print("  3. Replied to the reviewer in the Resolution Center")
        print()
        print("Resolving without addressing the feedback will likely result in another rejection.")
        print()
        guard confirm("Mark \(rejectedItems.count) rejected item(s) as resolved? [y/N] ") else {
          cancelled()
          return
        }
        
        for item in rejectedItems {
          _ = try await client.send(
            Resources.v1.reviewSubmissionItems.id(item.id).patch(
              ReviewSubmissionItemUpdateRequest(
                data: .init(
                  id: item.id,
                  attributes: .init(isResolved: true)
                )
              )
            )
          )
        }
        
        print()
        success("Resolved", "\(rejectedItems.count) item(s).")
        print("Run 'ascelerate apps review submit \(bundleID)' to resubmit.")
      }
    }
    
    // MARK: - Cancel Submission
    
    struct CancelSubmission: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Cancel an active review submission."
      )
      
      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @OptionGroup var platformOption: PlatformOption

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)

        // Find active submissions
        let response = try await client.send(
          Resources.v1.apps.id(app.id).reviewSubmissions.get(
            filterState: [.readyForReview, .waitingForReview, .inReview, .unresolvedIssues],
            fieldsAppStoreVersions: [.versionString],
            include: [.appStoreVersionForReview]
          )
        )

        guard let (submission, versionString) = try selectSubmission(
          from: response, platform: platformOption.parsed())
        else {
          print("No active review submissions found.")
          return
        }

        let state = submission.attributes?.state.map { formatState($0) } ?? "unknown"

        print("Submission: \(submission.id)")
        print("Platform:   \(submission.attributes?.platform.map { formatState($0) } ?? "—")")
        print("Version:    \(versionString)")
        print("State:      \(state)")
        print()
        guard confirm("Cancel this review submission? [y/N] ") else {
          cancelled()
          return
        }
        
        let result = try await client.send(
          Resources.v1.reviewSubmissions.id(submission.id).patch(
            ReviewSubmissionUpdateRequest(
              data: .init(
                id: submission.id,
                attributes: .init(isCanceled: true)
              )
            )
          )
        )
        
        let newState = result.data.attributes?.state.map { formatState($0) } ?? "unknown"
        print()
        success("Submission cancelled.")
        print("  State: \(newState)")
      }
    }

    // MARK: - App Review Information

    struct Info: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "View or update App Review Information (contact, demo account, notes).",
        discussion: """
          With no update flags, prints the current App Review Information. Pass any field flag
          to update it (creating the record if the version doesn't have one yet); omitted fields
          are left unchanged.
          """
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest editable version.")
      var version: String?

      @OptionGroup var platformOption: PlatformOption

      @Option(name: .long, help: "Review contact first name.")
      var contactFirstName: String?

      @Option(name: .long, help: "Review contact last name.")
      var contactLastName: String?

      @Option(name: .long, help: "Review contact phone number.")
      var contactPhone: String?

      @Option(name: .long, help: "Review contact email.")
      var contactEmail: String?

      @Option(name: .long, help: "Demo account username.")
      var demoAccountName: String?

      @Option(name: .long, help: "Demo account password.")
      var demoAccountPassword: String?

      @Option(name: .long, help: "Whether a demo account is required to review the app (true/false).")
      var demoAccountRequired: Bool?

      @Option(name: .long, help: "Notes for the App Review team.")
      var notes: String?

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appVersion = try await findVersion(
          appID: app.id, versionString: version, platform: try platformOption.parsed(), client: client)

        // The endpoint returns {"data": null} when no review detail exists yet.
        let existing: AppStoreReviewDetail?
        do {
          existing = try await client.send(
            Resources.v1.appStoreVersions.id(appVersion.id).appStoreReviewDetail.get()
          ).data
        } catch is DecodingError {
          existing = nil
        }

        let hasUpdates =
          contactFirstName != nil || contactLastName != nil || contactPhone != nil
          || contactEmail != nil || demoAccountName != nil || demoAccountPassword != nil
          || demoAccountRequired != nil || notes != nil

        let versionString = appVersion.attributes?.versionString ?? "unknown"

        if !hasUpdates {
          guard let detail = existing, let a = detail.attributes else {
            print("No App Review Information set for version \(versionString).")
            return
          }
          let name = [a.contactFirstName, a.contactLastName].compactMap { $0 }.joined(separator: " ")
          print("App Review Information for \(app.attributes?.name ?? bundleID) v\(versionString):")
          print("  Contact:       \(name.isEmpty ? "—" : name)")
          print("  Phone:         \(a.contactPhone ?? "—")")
          print("  Email:         \(a.contactEmail ?? "—")")
          print("  Demo Required: \(a.isDemoAccountRequired == true ? "Yes" : "No")")
          print("  Demo Account:  \(a.demoAccountName ?? "—")")
          print("  Demo Password: \(a.demoAccountPassword ?? "—")")
          print("  Notes:         \(a.notes ?? "—")")
          return
        }

        guard confirm("Update App Review Information for version \(versionString)? [y/N] ") else {
          cancelled()
          return
        }

        if let detail = existing {
          _ = try await client.send(
            Resources.v1.appStoreReviewDetails.id(detail.id).patch(
              AppStoreReviewDetailUpdateRequest(
                data: .init(
                  id: detail.id,
                  attributes: .init(
                    contactFirstName: contactFirstName, contactLastName: contactLastName,
                    contactPhone: contactPhone, contactEmail: contactEmail,
                    demoAccountName: demoAccountName, demoAccountPassword: demoAccountPassword,
                    isDemoAccountRequired: demoAccountRequired, notes: notes
                  )
                )
              )))
        } else {
          _ = try await client.send(
            Resources.v1.appStoreReviewDetails.post(
              AppStoreReviewDetailCreateRequest(
                data: .init(
                  attributes: .init(
                    contactFirstName: contactFirstName, contactLastName: contactLastName,
                    contactPhone: contactPhone, contactEmail: contactEmail,
                    demoAccountName: demoAccountName, demoAccountPassword: demoAccountPassword,
                    isDemoAccountRequired: demoAccountRequired, notes: notes
                  ),
                  relationships: .init(appStoreVersion: .init(data: .init(id: appVersion.id)))
                )
              )))
        }

        print()
        success("Updated", "App Review Information for version \(versionString).")
      }
    }

    // MARK: - App Review Attachments

    struct Attachment: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "attachment",
        abstract: "Manage App Review attachment files.",
        subcommands: [List.self, Upload.self, Delete.self]
      )

      /// Fetches the version's App Review detail (nil when none exists yet).
      static func reviewDetail(
        versionID: String, client: AppStoreConnectClient
      ) async throws -> AppStoreReviewDetail? {
        do {
          return try await client.send(
            Resources.v1.appStoreVersions.id(versionID).appStoreReviewDetail.get()
          ).data
        } catch is DecodingError {
          return nil
        }
      }

      /// Returns the version's App Review detail ID, creating an empty detail if needed.
      static func ensureReviewDetailID(
        versionID: String, client: AppStoreConnectClient
      ) async throws -> String {
        if let detail = try await reviewDetail(versionID: versionID, client: client) {
          return detail.id
        }
        let created = try await client.send(
          Resources.v1.appStoreReviewDetails.post(
            AppStoreReviewDetailCreateRequest(
              data: .init(
                attributes: .init(),
                relationships: .init(appStoreVersion: .init(data: .init(id: versionID)))
              ))))
        return created.data.id
      }

      struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "List App Review attachment files for a version."
        )

        @Argument(help: "The bundle identifier of the app.",
                  completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
        var bundleID: String

        @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest editable version.")
        var version: String?

        @OptionGroup var platformOption: PlatformOption

        func run() async throws {
          let client = try ClientFactory.makeClient()
          let app = try await findApp(bundleID: bundleID, client: client)
          let appVersion = try await findVersion(
            appID: app.id, versionString: version, platform: try platformOption.parsed(), client: client)

          guard let detail = try await Attachment.reviewDetail(
            versionID: appVersion.id, client: client)
          else {
            print("No App Review Information (or attachments) set for this version.")
            return
          }

          let resp = try await client.send(
            Resources.v1.appStoreReviewDetails.id(detail.id).appStoreReviewAttachments.get(limit: 50))
          if resp.data.isEmpty {
            print("No attachments found.")
            return
          }

          var rows: [[String]] = []
          for att in resp.data {
            rows.append([
              att.attributes?.fileName ?? "—",
              att.attributes?.fileSize.map { formatBytes($0) } ?? "—",
              att.attributes?.assetDeliveryState?.state.map { formatState($0) } ?? "—",
              att.id,
            ])
          }
          Table.print(headers: ["File", "Size", "State", "Attachment ID"], rows: rows)
        }
      }

      struct Upload: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Upload an App Review attachment file."
        )

        @Argument(help: "The bundle identifier of the app.",
                  completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
        var bundleID: String

        @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest editable version.")
        var version: String?

        @OptionGroup var platformOption: PlatformOption

        @Argument(help: "Path to the attachment file.", completion: .file())
        var file: String

        @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          let client = try ClientFactory.makeClient()
          let app = try await findApp(bundleID: bundleID, client: client)
          let appVersion = try await findVersion(
            appID: app.id, versionString: version, platform: try platformOption.parsed(), client: client)
          let media = try MediaFile(readingFrom: file)

          print("Upload App Review attachment:")
          print("  Version: \(appVersion.attributes?.versionString ?? "—")")
          print("  File:    \(media.fileName) (\(formatBytes(media.fileSize)))")
          print()
          guard confirm("Upload? [y/N] ") else {
            cancelled()
            return
          }

          let detailID = try await Attachment.ensureReviewDetailID(
            versionID: appVersion.id, client: client)

          let attachmentID = try await uploadAsset(
            filePath: media.path,
            reserve: {
              let r = try await client.send(
                Resources.v1.appStoreReviewAttachments.post(
                  AppStoreReviewAttachmentCreateRequest(
                    data: .init(
                      attributes: .init(fileSize: media.fileSize, fileName: media.fileName),
                      relationships: .init(
                        appStoreReviewDetail: .init(data: .init(id: detailID)))))))
              return (r.data.id, r.data.attributes?.uploadOperations ?? [])
            },
            commit: { id, md5 in
              _ = try await client.send(
                Resources.v1.appStoreReviewAttachments.id(id).patch(
                  AppStoreReviewAttachmentUpdateRequest(
                    data: .init(
                      id: id, attributes: .init(sourceFileChecksum: md5, isUploaded: true)))))
            })

          print()
          success("Uploaded", "attachment \(media.fileName) (id: \(attachmentID)).")
        }
      }

      struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Delete an App Review attachment file."
        )

        @Argument(help: "The attachment ID (from `attachment list`).")
        var attachmentID: String

        @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          let client = try ClientFactory.makeClient()

          let name =
            (try? await client.send(
              Resources.v1.appStoreReviewAttachments.id(attachmentID).get()
            ).data.attributes?.fileName) ?? nil
          print("Attachment: \(name ?? attachmentID)")
          print()
          guard confirm("Delete this attachment? [y/N] ") else {
            cancelled()
            return
          }

          _ = try await client.send(Resources.v1.appStoreReviewAttachments.id(attachmentID).delete)
          print()
          success("Deleted", "attachment \(name ?? attachmentID).")
        }
      }
    }
  }

  // MARK: - Configuration Commands
  
  struct AppInfoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "app-info",
      abstract: "View and manage app info, categories, and localizations.",
      subcommands: [View.self, Update.self, Import.self, Export.self, AgeRating.self]
    )
    
    static func findActiveAppInfo(appID: String, client: AppStoreConnectClient) async throws -> AppInfo {
      let response = try await client.send(
        Resources.v1.apps.id(appID).appInfos.get()
      )
      return try pickActiveAppInfo(from: response.data)
    }

    /// Picks the most relevant AppInfo: prefers editable (prepareForSubmission/waitingForReview) over live, skips replaced.
    static func pickActiveAppInfo(from appInfos: [AppInfo]) throws -> AppInfo {
      let candidates = appInfos.filter { $0.attributes?.state != .replacedWithNewInfo }
      guard let appInfo = candidates.first(where: { editableStates.contains($0.attributes?.state ?? .readyForDistribution) })
              ?? candidates.first
              ?? appInfos.first else {
        throw ValidationError("No app info found.")
      }
      return appInfo
    }

    private static let editableStates: Set<AppInfo.Attributes.State> = [.prepareForSubmission, .waitingForReview]
    
    static func checkEditable(_ appInfo: AppInfo) throws {
      guard let state = appInfo.attributes?.state, editableStates.contains(state) else {
        let stateStr = appInfo.attributes?.state.map { formatState($0) } ?? "unknown"
        throw ValidationError("App info is in state '\(stateStr)' — updates are only allowed in PREPARE_FOR_SUBMISSION or WAITING_FOR_REVIEW.")
      }
    }
    
    // MARK: - View
    
    struct View: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "View app info, categories, and localizations."
      )
      
      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String?
      
      @Flag(name: .long, help: "List available category IDs (iOS categories).")
      var listCategories = false
      
      func validate() throws {
        if !listCategories && bundleID == nil {
          throw ValidationError("Please provide a <bundle-id>, or use --list-categories.")
        }
      }
      
      func run() async throws {
        let client = try ClientFactory.makeClient()
        
        if listCategories {
          let response = try await client.send(
            Resources.v1.appCategories.get(
              filterPlatforms: [.iOS],
              isExistsParent: false,
              limit: 200,
              include: [.subcategories],
              limitSubcategories: 50
            )
          )
          
          print("Categories (iOS):")
          for cat in response.data.sorted(by: { $0.id < $1.id }) {
            print("  \(cat.id)")
            if let subs = cat.relationships?.subcategories?.data, !subs.isEmpty {
              for sub in subs.sorted(by: { $0.id < $1.id }) {
                print("    \(sub.id)")
              }
            }
          }
          return
        }
        
        guard let bundleID else {
          throw ValidationError("Please provide a <bundle-id>.")
        }
        
        let app = try await findApp(bundleID: bundleID, client: client)
        
        let response = try await client.send(
          Resources.v1.apps.id(app.id).appInfos.get(
            include: [.primaryCategory, .secondaryCategory, .appInfoLocalizations],
            limitAppInfoLocalizations: 50
          )
        )
        
        let appInfo = try AppInfoCommand.pickActiveAppInfo(from: response.data)
        
        let appName = app.attributes?.name ?? bundleID
        let attrs = appInfo.attributes
        let state = attrs?.state.map { formatState($0) } ?? "—"
        let ageRating = attrs?.appStoreAgeRating.map { formatState($0) } ?? "—"
        let primaryCatID = appInfo.relationships?.primaryCategory?.data?.id ?? "—"
        let secondaryCatID = appInfo.relationships?.secondaryCategory?.data?.id ?? "—"
        
        print("App:                \(appName)")
        print("State:              \(state)")
        print("Age Rating:         \(ageRating)")
        print("Primary Category:   \(primaryCatID)")
        print("Secondary Category: \(secondaryCatID)")
        
        // Filter localizations to only those belonging to the selected AppInfo
        let locIDs = Set(appInfo.relationships?.appInfoLocalizations?.data?.map(\.id) ?? [])
        let localizations = response.included?.compactMap { item -> AppInfoLocalization? in
          if case .appInfoLocalization(let loc) = item, locIDs.contains(loc.id) {
            return loc
          }
          return nil
        } ?? []
        
        if !localizations.isEmpty {
          print()
          print("Localizations:")
          for loc in localizations {
            let locAttrs = loc.attributes
            let locale = locAttrs?.locale ?? "—"
            let name = locAttrs?.name ?? "—"
            let subtitle = locAttrs?.subtitle
            print()
            var line = "  [\(localeName(locale))] \(name)"
            if let sub = subtitle, !sub.isEmpty {
              line += " — \(sub)"
            }
            print(line)
            if let url = locAttrs?.privacyPolicyURL, !url.isEmpty {
              print("    Privacy Policy URL:  \(url)")
            }
            if let url = locAttrs?.privacyChoicesURL, !url.isEmpty {
              print("    Privacy Choices URL: \(url)")
            }
          }
        }
      }
    }
    
    // MARK: - Update
    
    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Update app info localizations and/or categories."
      )
      
      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String
      
      @Option(name: .long, help: "The locale to update (e.g. en-US). Defaults to the app's primary locale.")
      var locale: String?
      
      @Option(name: .long, help: "App name.")
      var name: String?
      
      @Option(name: .long, help: "App subtitle.")
      var subtitle: String?
      
      @Option(name: .long, help: "Privacy policy URL.")
      var privacyPolicyURL: String?
      
      @Option(name: .long, help: "Privacy choices URL.")
      var privacyChoicesURL: String?
      
      @Option(name: .long, help: "Primary category ID (e.g. UTILITIES, GAMES_ACTION).")
      var primaryCategory: String?
      
      @Option(name: .long, help: "Secondary category ID.")
      var secondaryCategory: String?
      
      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false
      
      func run() async throws {
        let hasLocalizationFields = name != nil || subtitle != nil || privacyPolicyURL != nil
        || privacyChoicesURL != nil
        let hasCategoryFields = primaryCategory != nil || secondaryCategory != nil
        
        guard hasLocalizationFields || hasCategoryFields else {
          throw ValidationError("Provide at least one field to update (--name, --subtitle, --privacy-policy-url, --privacy-choices-url, --primary-category, --secondary-category).")
        }
        
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appInfo = try await AppInfoCommand.findActiveAppInfo(appID: app.id, client: client)
        try AppInfoCommand.checkEditable(appInfo)
        
        let appName = app.attributes?.name ?? bundleID
        print("App:   \(appName)")
        print("State: \(appInfo.attributes?.state.map { formatState($0) } ?? "—")")
        print()
        
        if hasLocalizationFields {
          let localeDesc = locale.map { localeName($0) } ?? "primary"
          print("Localization [\(localeDesc)]:")
          if let v = name { print("  Name:               \(v)") }
          if let v = subtitle { print("  Subtitle:           \(v)") }
          if let v = privacyPolicyURL { print("  Privacy Policy URL: \(v)") }
          if let v = privacyChoicesURL { print("  Privacy Choices URL: \(v)") }
        }
        
        if hasCategoryFields {
          if hasLocalizationFields { print() }
          print("Categories:")
          if let cat = primaryCategory {
            print("  Primary Category:   \(cat)")
          }
          if let cat = secondaryCategory {
            print("  Secondary Category: \(cat)")
          }
        }
        print()
        
        guard confirm("Apply updates? [y/N] ") else {
          cancelled()
          return
        }
        print()
        
        // Update localization
        if hasLocalizationFields {
          let locsResponse = try await client.send(
            Resources.v1.appInfos.id(appInfo.id)
              .appInfoLocalizations.get(
                filterLocale: locale.map { [$0] }
              )
          )
          guard let localization = locsResponse.data.first else {
            let localeDesc = locale ?? "primary"
            throw ValidationError("No localization found for locale '\(localeDesc)'.")
          }
          
          let response = try await client.send(
            Resources.v1.appInfoLocalizations.id(localization.id).patch(
              AppInfoLocalizationUpdateRequest(
                data: .init(
                  id: localization.id,
                  attributes: .init(
                    name: name,
                    subtitle: subtitle,
                    privacyPolicyURL: privacyPolicyURL,
                    privacyChoicesURL: privacyChoicesURL
                  )
                )
              )
            )
          )
          let updatedLocale = response.data.attributes?.locale ?? locale ?? "primary"
          success("Updated", "localization [\(updatedLocale)].")
        }
        
        // Update categories
        if hasCategoryFields {
          typealias Rels = AppInfoUpdateRequest.Data.Relationships
          var relationships = Rels()
          if let cat = primaryCategory {
            relationships.primaryCategory = .init(data: .init(id: cat))
          }
          if let cat = secondaryCategory {
            relationships.secondaryCategory = .init(data: .init(id: cat))
          }
          _ = try await client.send(
            Resources.v1.appInfos.id(appInfo.id).patch(
              AppInfoUpdateRequest(
                data: .init(id: appInfo.id, relationships: relationships)
              )
            )
          )
          success("Updated", "categories.")
        }
        
        print()
        print("Done.")
      }
    }
    
    // MARK: - Import
    
    struct Import: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Update app info localizations from a JSON file."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Path to the JSON file with localization data.",
              completion: .file(extensions: ["json"]))
      var file: String?
      
      @Flag(name: .long, help: "Show full API response for each locale update.")
      var verbose = false
      
      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false
      
      func run() async throws {
        if yes { autoConfirm = true }
        let expandedPath = try resolveFile(file, extension: "json", prompt: "Select app info localizations JSON file")

        // Parse JSON
        let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
        let localeUpdates: [String: AppInfoLocaleFields]
        do {
          localeUpdates = try JSONDecoder().decode([String: AppInfoLocaleFields].self, from: data)
        } catch let error as DecodingError {
          throw ValidationError("Invalid JSON: \(describeDecodingError(error))")
        }
        
        if localeUpdates.isEmpty {
          throw ValidationError("JSON file contains no locale entries.")
        }
        
        // Show summary and confirm
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appInfo = try await AppInfoCommand.findActiveAppInfo(appID: app.id, client: client)
        try AppInfoCommand.checkEditable(appInfo)
        
        let appName = app.attributes?.name ?? bundleID
        let stateStr = appInfo.attributes?.state.map { formatState($0) } ?? "unknown"
        print("App:   \(appName)")
        print("State: \(stateStr)")
        print()
        
        for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
          print("[\(localeName(locale))]")
          if let v = fields.name { print("  Name:               \(v)") }
          if let v = fields.subtitle { print("  Subtitle:           \(v)") }
          if let v = fields.privacyPolicyURL { print("  Privacy Policy URL: \(v)") }
          if let v = fields.privacyChoicesURL { print("  Privacy Choices URL: \(v)") }
          print()
        }
        
        guard confirm("Send updates for \(localeUpdates.count) locale(s)? [y/N] ") else {
          cancelled()
          return
        }
        print()
        
        // Fetch all localizations for this app info
        let locsResponse = try await client.send(
          Resources.v1.appInfos.id(appInfo.id)
            .appInfoLocalizations.get()
        )
        
        let locByLocale = Dictionary(
          locsResponse.data.compactMap { loc in
            loc.attributes?.locale.map { ($0, loc) }
          },
          uniquingKeysWith: { first, _ in first }
        )
        
        // Send updates
        for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
          guard let localization = locByLocale[locale] else {
            guard let name = fields.name else {
              print("  [\(localeName(locale))] Skipped — locale not found in current localizations for the app and \"name\" is required to create it.")
              continue
            }

            guard confirm("  [\(localeName(locale))] Locale not found in current localizations for the app. Create it? [y/N] ") else {
              print("  [\(localeName(locale))] Skipped.")
              continue
            }

            let response = try await client.send(
              Resources.v1.appInfoLocalizations.post(
                AppInfoLocalizationCreateRequest(
                  data: .init(
                    attributes: .init(
                      locale: locale,
                      name: name,
                      subtitle: fields.subtitle,
                      privacyPolicyURL: fields.privacyPolicyURL,
                      privacyChoicesURL: fields.privacyChoicesURL
                    ),
                    relationships: .init(
                      appInfo: .init(data: .init(id: appInfo.id))
                    )
                  )
                )
              )
            )
            print("  [\(localeName(locale))] \(green("Created."))")

            if verbose {
              let attrs = response.data.attributes
              print("    Response:")
              print("      Locale:             \(attrs?.locale.map { localeName($0) } ?? "—")")
              if let v = attrs?.name { print("      Name:               \(v)") }
              if let v = attrs?.subtitle { print("      Subtitle:           \(v)") }
              if let v = attrs?.privacyPolicyURL { print("      Privacy Policy URL: \(v)") }
              if let v = attrs?.privacyChoicesURL { print("      Privacy Choices URL: \(v)") }
            }
            continue
          }

          let response = try await client.send(
            Resources.v1.appInfoLocalizations.id(localization.id).patch(
              AppInfoLocalizationUpdateRequest(
                data: .init(
                  id: localization.id,
                  attributes: .init(
                    name: fields.name,
                    subtitle: fields.subtitle,
                    privacyPolicyURL: fields.privacyPolicyURL,
                    privacyChoicesURL: fields.privacyChoicesURL
                  )
                )
              )
            )
          )
          print("  [\(localeName(locale))] Updated.")

          if verbose {
            let attrs = response.data.attributes
            print("    Response:")
            print("      Locale:             \(attrs?.locale.map { localeName($0) } ?? "—")")
            if let v = attrs?.name { print("      Name:               \(v)") }
            if let v = attrs?.subtitle { print("      Subtitle:           \(v)") }
            if let v = attrs?.privacyPolicyURL { print("      Privacy Policy URL: \(v)") }
            if let v = attrs?.privacyChoicesURL { print("      Privacy Choices URL: \(v)") }
          }
        }
        
        print()
        print("Done.")
      }
    }
    
    // MARK: - Export
    
    struct Export: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export app info localizations to a JSON file."
      )
      
      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String
      
      @Option(name: .long, help: "Output file path (default: <bundle-id>-app-infos.json).",
              completion: .file(extensions: ["json"]))
      var output: String?
      
      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appInfo = try await AppInfoCommand.findActiveAppInfo(appID: app.id, client: client)
        
        let locsResponse = try await client.send(
          Resources.v1.appInfos.id(appInfo.id)
            .appInfoLocalizations.get()
        )
        
        var result: [String: AppInfoLocaleFields] = [:]
        for loc in locsResponse.data {
          guard let locale = loc.attributes?.locale else { continue }
          let attrs = loc.attributes
          result[locale] = AppInfoLocaleFields(
            name: attrs?.name,
            subtitle: attrs?.subtitle,
            privacyPolicyURL: attrs?.privacyPolicyURL,
            privacyChoicesURL: attrs?.privacyChoicesURL
          )
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        
        let outputPath = expandPath(
          confirmOutputPath(output ?? "\(bundleID)-app-infos.json", isDirectory: false))
        try data.write(to: URL(fileURLWithPath: outputPath))
        
        success("Exported", "\(result.count) locale(s) to \(outputPath)")
      }
    }

    struct AgeRating: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "age-rating",
        abstract: "View, export, or import age rating declaration.",
        subcommands: [View.self, Export.self, Import.self],
        defaultSubcommand: View.self
      )

      static func fetchDeclaration(appID: String, client: AppStoreConnectClient) async throws -> (AgeRatingDeclaration, AppInfo) {
        let appInfo = try await AppInfoCommand.findActiveAppInfo(appID: appID, client: client)
        let response = try await client.send(
          Resources.v1.appInfos.id(appInfo.id).ageRatingDeclaration.get()
        )
        return (response.data, appInfo)
      }

      static func toFields(attrs: AgeRatingDeclaration.Attributes?) -> AgeRatingFields {
        AgeRatingFields(
          alcoholTobaccoOrDrugUseOrReferences: attrs?.alcoholTobaccoOrDrugUseOrReferences?.rawValue,
          contests: attrs?.contests?.rawValue,
          gamblingSimulated: attrs?.gamblingSimulated?.rawValue,
          gunsOrOtherWeapons: attrs?.gunsOrOtherWeapons?.rawValue,
          horrorOrFearThemes: attrs?.horrorOrFearThemes?.rawValue,
          matureOrSuggestiveThemes: attrs?.matureOrSuggestiveThemes?.rawValue,
          profanityOrCrudeHumor: attrs?.profanityOrCrudeHumor?.rawValue,
          sexualContentOrNudity: attrs?.sexualContentOrNudity?.rawValue,
          sexualContentGraphicAndNudity: attrs?.sexualContentGraphicAndNudity?.rawValue,
          violenceCartoonOrFantasy: attrs?.violenceCartoonOrFantasy?.rawValue,
          violenceRealistic: attrs?.violenceRealistic?.rawValue,
          violenceRealisticProlongedGraphicOrSadistic: attrs?.violenceRealisticProlongedGraphicOrSadistic?.rawValue,
          medicalOrTreatmentInformation: attrs?.medicalOrTreatmentInformation?.rawValue,
          isAdvertising: attrs?.isAdvertising,
          isGambling: attrs?.isGambling,
          isUnrestrictedWebAccess: attrs?.isUnrestrictedWebAccess,
          isUserGeneratedContent: attrs?.isUserGeneratedContent,
          isMessagingAndChat: attrs?.isMessagingAndChat,
          isLootBox: attrs?.isLootBox,
          isHealthOrWellnessTopics: attrs?.isHealthOrWellnessTopics,
          isParentalControls: attrs?.isParentalControls,
          isAgeAssurance: attrs?.isAgeAssurance,
          kidsAgeBand: attrs?.kidsAgeBand?.rawValue,
          ageRatingOverride: attrs?.ageRatingOverride?.rawValue
        )
      }

      struct View: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "View age rating declaration.")

        @Argument(help: "The bundle identifier of the app.",
                  completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
        var bundleID: String

        func run() async throws {
          let client = try ClientFactory.makeClient()
          let app = try await findApp(bundleID: bundleID, client: client)
          let (declaration, _) = try await AgeRating.fetchDeclaration(appID: app.id, client: client)
          let attrs = declaration.attributes
          let appName = app.attributes?.name ?? bundleID

          print("App: \(appName)")
          print()
          print("Age Rating Declaration:")
      
        func intensityLabel(_ raw: String?) -> String {
          switch raw {
            case "NONE": return "None"
            case "INFREQUENT_OR_MILD": return "Infrequent or Mild"
            case "FREQUENT_OR_INTENSE": return "Frequent or Intense"
            case "INFREQUENT": return "Infrequent"
            case "FREQUENT": return "Frequent"
            default: return raw ?? "—"
          }
        }
      
        func boolLabel(_ value: Bool?) -> String {
          guard let v = value else { return "—" }
          return v ? "Yes" : "No"
        }
      
        // Intensity-based ratings
        let intensityRows: [(String, String)] = [
          ("Alcohol, Tobacco, or Drug Use", intensityLabel(attrs?.alcoholTobaccoOrDrugUseOrReferences?.rawValue)),
          ("Contests", intensityLabel(attrs?.contests?.rawValue)),
          ("Gambling (simulated)", intensityLabel(attrs?.gamblingSimulated?.rawValue)),
          ("Guns or Other Weapons", intensityLabel(attrs?.gunsOrOtherWeapons?.rawValue)),
          ("Horror or Fear Themes", intensityLabel(attrs?.horrorOrFearThemes?.rawValue)),
          ("Mature or Suggestive Themes", intensityLabel(attrs?.matureOrSuggestiveThemes?.rawValue)),
          ("Profanity or Crude Humor", intensityLabel(attrs?.profanityOrCrudeHumor?.rawValue)),
          ("Sexual Content or Nudity", intensityLabel(attrs?.sexualContentOrNudity?.rawValue)),
          ("Sexual Content (graphic)", intensityLabel(attrs?.sexualContentGraphicAndNudity?.rawValue)),
          ("Violence (cartoon/fantasy)", intensityLabel(attrs?.violenceCartoonOrFantasy?.rawValue)),
          ("Violence (realistic)", intensityLabel(attrs?.violenceRealistic?.rawValue)),
          ("Violence (graphic/sadistic)", intensityLabel(attrs?.violenceRealisticProlongedGraphicOrSadistic?.rawValue)),
          ("Medical Information", intensityLabel(attrs?.medicalOrTreatmentInformation?.rawValue)),
        ]
      
        // Boolean ratings
        let boolRows: [(String, String)] = [
          ("Advertising", boolLabel(attrs?.isAdvertising)),
          ("Gambling", boolLabel(attrs?.isGambling)),
          ("Unrestricted Web Access", boolLabel(attrs?.isUnrestrictedWebAccess)),
          ("User-Generated Content", boolLabel(attrs?.isUserGeneratedContent)),
          ("Messaging and Chat", boolLabel(attrs?.isMessagingAndChat)),
          ("Loot Box", boolLabel(attrs?.isLootBox)),
          ("Health/Wellness Topics", boolLabel(attrs?.isHealthOrWellnessTopics)),
          ("Parental Controls", boolLabel(attrs?.isParentalControls)),
          ("Age Assurance", boolLabel(attrs?.isAgeAssurance)),
        ]
      
        // Other
        let kidsAgeBand = attrs?.kidsAgeBand?.rawValue
          .replacingOccurrences(of: "_", with: " ")
          .capitalized ?? "—"
        let ageOverride = attrs?.ageRatingOverride?.rawValue
          .replacingOccurrences(of: "_", with: " ")
          .capitalized ?? "—"
      
        let maxLabel = max(
          intensityRows.max(by: { $0.0.count < $1.0.count })?.0.count ?? 0,
          boolRows.max(by: { $0.0.count < $1.0.count })?.0.count ?? 0,
          "Kids Age Band".count,
          "Age Rating Override".count
        )
      
        for (label, value) in intensityRows {
          print("  \(label.padding(toLength: maxLabel, withPad: " ", startingAt: 0))  \(value)")
        }
        for (label, value) in boolRows {
          print("  \(label.padding(toLength: maxLabel, withPad: " ", startingAt: 0))  \(value)")
        }
        print("  \("Kids Age Band".padding(toLength: maxLabel, withPad: " ", startingAt: 0))  \(kidsAgeBand)")
        print("  \("Age Rating Override".padding(toLength: maxLabel, withPad: " ", startingAt: 0))  \(ageOverride)")
        }
      }

      struct Export: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Export age rating declaration to JSON.")

        @Argument(help: "The bundle identifier of the app.",
                  completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
        var bundleID: String

        @Option(name: .shortAndLong, help: "Output file path.",
                completion: .file(extensions: ["json"]))
        var output: String?

        func run() async throws {
          let client = try ClientFactory.makeClient()
          let app = try await findApp(bundleID: bundleID, client: client)
          let (declaration, _) = try await AgeRating.fetchDeclaration(appID: app.id, client: client)
          let appName = app.attributes?.name ?? bundleID

          let exported = AgeRating.toFields(attrs: declaration.attributes)
          let encoder = JSONEncoder()
          encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
          let jsonData = try encoder.encode(exported)

          let outputPath = confirmOutputPath(output ?? "age-rating.json", isDirectory: false)
          let expandedOutput = expandPath(outputPath)
          try jsonData.write(to: URL(fileURLWithPath: expandedOutput))
          success("Exported", "age rating for \(appName) → \(outputPath)")
        }
      }

      struct Import: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          commandName: "import",
          abstract: "Update age rating declaration from a JSON file."
        )

        @Argument(help: "The bundle identifier of the app.",
                  completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
        var bundleID: String

        @Option(name: .long, help: "Path to a JSON file with age rating fields.",
                completion: .file(extensions: ["json"]))
        var file: String?

        @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          let client = try ClientFactory.makeClient()
          let app = try await findApp(bundleID: bundleID, client: client)
          let (declaration, _) = try await AgeRating.fetchDeclaration(appID: app.id, client: client)
          let appName = app.attributes?.name ?? bundleID

          let filePath = try resolveFile(file, extension: "json", prompt: "Select an age rating JSON file:")
          let expandedPath = expandPath(filePath)

          let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
          let fields: AgeRatingFields
          do {
            fields = try JSONDecoder().decode(AgeRatingFields.self, from: data)
          } catch let error as DecodingError {
            throw ValidationError("Invalid JSON: \(describeDecodingError(error))")
          }

          print("App: \(appName)")
          print()
          print("Age rating updates:")
          var changeCount = 0
          if let v = fields.alcoholTobaccoOrDrugUseOrReferences { print("  Alcohol, Tobacco, or Drug Use: \(v)"); changeCount += 1 }
          if let v = fields.contests { print("  Contests: \(v)"); changeCount += 1 }
          if let v = fields.gamblingSimulated { print("  Gambling (simulated): \(v)"); changeCount += 1 }
          if let v = fields.gunsOrOtherWeapons { print("  Guns or Other Weapons: \(v)"); changeCount += 1 }
          if let v = fields.horrorOrFearThemes { print("  Horror or Fear Themes: \(v)"); changeCount += 1 }
          if let v = fields.matureOrSuggestiveThemes { print("  Mature or Suggestive Themes: \(v)"); changeCount += 1 }
          if let v = fields.profanityOrCrudeHumor { print("  Profanity or Crude Humor: \(v)"); changeCount += 1 }
          if let v = fields.sexualContentOrNudity { print("  Sexual Content or Nudity: \(v)"); changeCount += 1 }
          if let v = fields.sexualContentGraphicAndNudity { print("  Sexual Content (graphic): \(v)"); changeCount += 1 }
          if let v = fields.violenceCartoonOrFantasy { print("  Violence (cartoon/fantasy): \(v)"); changeCount += 1 }
          if let v = fields.violenceRealistic { print("  Violence (realistic): \(v)"); changeCount += 1 }
          if let v = fields.violenceRealisticProlongedGraphicOrSadistic { print("  Violence (graphic/sadistic): \(v)"); changeCount += 1 }
          if let v = fields.medicalOrTreatmentInformation { print("  Medical Information: \(v)"); changeCount += 1 }
          if let v = fields.isAdvertising { print("  Advertising: \(v)"); changeCount += 1 }
          if let v = fields.isGambling { print("  Gambling: \(v)"); changeCount += 1 }
          if let v = fields.isUnrestrictedWebAccess { print("  Unrestricted Web Access: \(v)"); changeCount += 1 }
          if let v = fields.isUserGeneratedContent { print("  User-Generated Content: \(v)"); changeCount += 1 }
          if let v = fields.isMessagingAndChat { print("  Messaging and Chat: \(v)"); changeCount += 1 }
          if let v = fields.isLootBox { print("  Loot Box: \(v)"); changeCount += 1 }
          if let v = fields.isHealthOrWellnessTopics { print("  Health/Wellness Topics: \(v)"); changeCount += 1 }
          if let v = fields.isParentalControls { print("  Parental Controls: \(v)"); changeCount += 1 }
          if let v = fields.isAgeAssurance { print("  Age Assurance: \(v)"); changeCount += 1 }
          if let v = fields.kidsAgeBand { print("  Kids Age Band: \(v)"); changeCount += 1 }
          if let v = fields.ageRatingOverride { print("  Age Rating Override: \(v)"); changeCount += 1 }

          if changeCount == 0 {
            throw ValidationError("JSON file contains no age rating fields.")
          }

          print()
          guard confirm("Update \(changeCount) age rating field\(changeCount == 1 ? "" : "s")? [y/N] ") else {
            cancelled()
            return
          }

          func parseIntensity<T: RawRepresentable>(_ value: String?, type: T.Type) -> T? where T.RawValue == String {
            guard let v = value else { return nil }
            return T(rawValue: v)
          }

          typealias Attrs = AgeRatingDeclarationUpdateRequest.Data.Attributes
          let updateRequest = Resources.v1.ageRatingDeclarations.id(declaration.id).patch(
            AgeRatingDeclarationUpdateRequest(
              data: .init(
                id: declaration.id,
                attributes: .init(
                  isAdvertising: fields.isAdvertising,
                  alcoholTobaccoOrDrugUseOrReferences: parseIntensity(fields.alcoholTobaccoOrDrugUseOrReferences, type: Attrs.AlcoholTobaccoOrDrugUseOrReferences.self),
                  contests: parseIntensity(fields.contests, type: Attrs.Contests.self),
                  isGambling: fields.isGambling,
                  gamblingSimulated: parseIntensity(fields.gamblingSimulated, type: Attrs.GamblingSimulated.self),
                  gunsOrOtherWeapons: parseIntensity(fields.gunsOrOtherWeapons, type: Attrs.GunsOrOtherWeapons.self),
                  isHealthOrWellnessTopics: fields.isHealthOrWellnessTopics,
                  kidsAgeBand: parseIntensity(fields.kidsAgeBand, type: KidsAgeBand.self),
                  isLootBox: fields.isLootBox,
                  medicalOrTreatmentInformation: parseIntensity(fields.medicalOrTreatmentInformation, type: Attrs.MedicalOrTreatmentInformation.self),
                  isMessagingAndChat: fields.isMessagingAndChat,
                  isParentalControls: fields.isParentalControls,
                  profanityOrCrudeHumor: parseIntensity(fields.profanityOrCrudeHumor, type: Attrs.ProfanityOrCrudeHumor.self),
                  isAgeAssurance: fields.isAgeAssurance,
                  sexualContentGraphicAndNudity: parseIntensity(fields.sexualContentGraphicAndNudity, type: Attrs.SexualContentGraphicAndNudity.self),
                  sexualContentOrNudity: parseIntensity(fields.sexualContentOrNudity, type: Attrs.SexualContentOrNudity.self),
                  horrorOrFearThemes: parseIntensity(fields.horrorOrFearThemes, type: Attrs.HorrorOrFearThemes.self),
                  matureOrSuggestiveThemes: parseIntensity(fields.matureOrSuggestiveThemes, type: Attrs.MatureOrSuggestiveThemes.self),
                  isUnrestrictedWebAccess: fields.isUnrestrictedWebAccess,
                  isUserGeneratedContent: fields.isUserGeneratedContent,
                  violenceCartoonOrFantasy: parseIntensity(fields.violenceCartoonOrFantasy, type: Attrs.ViolenceCartoonOrFantasy.self),
                  violenceRealisticProlongedGraphicOrSadistic: parseIntensity(fields.violenceRealisticProlongedGraphicOrSadistic, type: Attrs.ViolenceRealisticProlongedGraphicOrSadistic.self),
                  violenceRealistic: parseIntensity(fields.violenceRealistic, type: Attrs.ViolenceRealistic.self),
                  ageRatingOverride: parseIntensity(fields.ageRatingOverride, type: Attrs.AgeRatingOverride.self)
                )
              )
            )
          )

          _ = try await client.send(updateRequest)
          print()
          success("Updated", "age rating declaration for \(appName).")
        }
      }
    }
  }
  
  struct Availability: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "availability",
      abstract: "View or update territory availability."
    )
    
    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String
    
    @Option(name: .long, help: "Comma-separated territory codes to make available (e.g. CHN,RUS).")
    var add: String?
    
    @Option(name: .long, help: "Comma-separated territory codes to make unavailable (e.g. CHN,RUS).")
    var remove: String?
    
    @Flag(name: .long, help: "Show full country names.")
    var verbose = false
    
    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false
    
    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appName = app.attributes?.name ?? bundleID
      
      // Get availability info (without includes — territory limit is only 50)
      let response = try await client.send(
        Resources.v1.apps.id(app.id).appAvailabilityV2.get()
      )
      
      let availableInNew = response.data.attributes?.isAvailableInNewTerritories
      let availabilityID = response.data.id
      
      // Paginate through all territory availabilities via the v2 sub-resource
      var territoryMap: [(code: String, id: String, isAvailable: Bool)] = []
      
      for try await page in client.pages(
        Resources.v2.appAvailabilities.id(availabilityID).territoryAvailabilities.get(
          limit: 50,
          include: [.territory]
        )
      ) {
        for ta in page.data {
          guard let code = ta.relationships?.territory?.data?.id else { continue }
          let isAvail = ta.attributes?.isAvailable ?? false
          territoryMap.append((code, ta.id, isAvail))
        }
      }
      
      // Edit mode
      if add != nil || remove != nil {
        let addCodes = Set(add?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() } ?? [])
        let removeCodes = Set(remove?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() } ?? [])
        
        let allCodes = Set(territoryMap.map(\.code))
        let invalidCodes = addCodes.union(removeCodes).subtracting(allCodes)
        if !invalidCodes.isEmpty {
          throw ValidationError("Unknown territory codes: \(invalidCodes.sorted().joined(separator: ", "))")
        }
        
        let overlap = addCodes.intersection(removeCodes)
        if !overlap.isEmpty {
          throw ValidationError("Territory codes in both --add and --remove: \(overlap.sorted().joined(separator: ", "))")
        }
        
        var changes: [(code: String, id: String, newValue: Bool)] = []
        for t in territoryMap {
          if addCodes.contains(t.code) && !t.isAvailable {
            changes.append((t.code, t.id, true))
          } else if removeCodes.contains(t.code) && t.isAvailable {
            changes.append((t.code, t.id, false))
          }
        }
        
        // Report codes already in the requested state
        let alreadyAvailable = addCodes.filter { code in territoryMap.first { $0.code == code }?.isAvailable == true }
        let alreadyUnavailable = removeCodes.filter { code in territoryMap.first { $0.code == code }?.isAvailable == false }
        let en = Locale(identifier: "en")
        
        if !alreadyAvailable.isEmpty {
          for code in alreadyAvailable.sorted() {
            let name = en.localizedString(forRegionCode: code) ?? code
            print("  Already available: \(code)  \(name)")
          }
        }
        if !alreadyUnavailable.isEmpty {
          for code in alreadyUnavailable.sorted() {
            let name = en.localizedString(forRegionCode: code) ?? code
            print("  Already unavailable: \(code)  \(name)")
          }
        }
        
        if changes.isEmpty {
          print("No changes needed.")
          return
        }
        
        print("App: \(appName)")
        print()
        for change in changes.sorted(by: { $0.code < $1.code }) {
          let name = en.localizedString(forRegionCode: change.code) ?? change.code
          let action = change.newValue ? "  Add:    " : "  Remove: "
          print("\(action)\(change.code)  \(name)")
        }
        print()
        
        guard confirm("Apply \(changes.count) change\(changes.count == 1 ? "" : "s")? [y/N] ") else {
          cancelled()
          return
        }
        
        var failed: [String] = []
        for change in changes {
          do {
            _ = try await client.send(
              Resources.v1.territoryAvailabilities.id(change.id).patch(
                TerritoryAvailabilityUpdateRequest(
                  data: .init(id: change.id, attributes: .init(isAvailable: change.newValue))
                )
              )
            )
          } catch {
            failed.append(change.code)
            print("  Failed to update \(change.code): \(describeError(error))")
          }
        }
        
        print()
        let succeeded = changes.count - failed.count
        if succeeded > 0 {
          success("Updated", "\(succeeded) territory availability\(succeeded == 1 ? "" : " entries").")
        }
        if !failed.isEmpty {
          print("Failed: \(failed.joined(separator: ", "))")
        }
        return
      }
      
      // View mode
      let available = territoryMap.filter(\.isAvailable).map(\.code).sorted()
      let notAvailable = territoryMap.filter { !$0.isAvailable }.map(\.code).sorted()
      
      print("App:                          \(appName)")
      print("Available in new territories: \(availableInNew == true ? "Yes" : availableInNew == false ? "No" : "—")")
      print()
      
      if !available.isEmpty {
        print("Available (\(available.count)):")
        printTerritories(available)
      }
      
      if !notAvailable.isEmpty {
        if !available.isEmpty { print() }
        print("Not Available (\(notAvailable.count)):")
        printTerritories(notAvailable)
      }
      
      if available.isEmpty && notAvailable.isEmpty {
        print("No territory availability data found.")
      }
    }
    
    private func printTerritories(_ codes: [String]) {
      if verbose {
        let en = Locale(identifier: "en")
        for code in codes {
          let name = en.localizedString(forRegionCode: code) ?? code
          print("  \(code)  \(name)")
        }
      } else {
        for i in stride(from: 0, to: codes.count, by: 10) {
          let end = min(i + 10, codes.count)
          let row = codes[i..<end].joined(separator: "  ")
          print("  \(row)")
        }
      }
    }
  }
  
  struct Encryption: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "encryption",
      abstract: "View or create encryption declarations."
    )
    
    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String
    
    @Flag(name: .long, help: "Create a new encryption declaration.")
    var create = false
    
    @Option(name: .customLong("description"), help: "Description of encryption use (required with --create).")
    var appDescription: String?
    
    @Flag(name: .long, inversion: .prefixedNo, help: "App uses proprietary cryptography.")
    var proprietaryCrypto: Bool = false
    
    @Flag(name: .long, inversion: .prefixedNo, help: "App uses third-party cryptography.")
    var thirdPartyCrypto: Bool = false
    
    @Flag(name: .long, inversion: .prefixedNo, help: "App is available on the French store.")
    var availableOnFrenchStore: Bool = true
    
    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false
    
    func validate() throws {
      if create && appDescription == nil {
        throw ValidationError("--description is required when using --create.")
      }
    }
    
    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appName = app.attributes?.name ?? bundleID
      
      if create {
        let desc = appDescription!
        
        print("App: \(appName)")
        print()
        print("New encryption declaration:")
        print("  Description:            \(desc)")
        print("  Proprietary Crypto:     \(proprietaryCrypto ? "Yes" : "No")")
        print("  Third-Party Crypto:     \(thirdPartyCrypto ? "Yes" : "No")")
        print("  French Store Available: \(availableOnFrenchStore ? "Yes" : "No")")
        print()
        
        guard confirm("Create encryption declaration? [y/N] ") else {
          cancelled()
          return
        }
        
        let response = try await client.send(
          Resources.v1.appEncryptionDeclarations.post(
            AppEncryptionDeclarationCreateRequest(
              data: .init(
                attributes: .init(
                  appDescription: desc,
                  containsProprietaryCryptography: proprietaryCrypto,
                  containsThirdPartyCryptography: thirdPartyCrypto,
                  isAvailableOnFrenchStore: availableOnFrenchStore
                ),
                relationships: .init(
                  app: .init(data: .init(id: app.id))
                )
              )
            )
          )
        )
        
        let attrs = response.data.attributes
        let state = attrs?.appEncryptionDeclarationState.map { formatState($0) } ?? "—"
        let exempt = attrs?.isExempt.map { $0 ? "Yes" : "No" } ?? "—"
        print()
        success("Created", "encryption declaration.")
        print("  State:  \(state)")
        print("  Exempt: \(exempt)")
        return
      }
      
      // View mode
      print("App: \(appName)")
      print()
      
      var rows: [[String]] = []
      for try await page in client.pages(
        Resources.v1.appEncryptionDeclarations.get(filterApp: [app.id])
      ) {
        for decl in page.data {
          let attrs = decl.attributes
          let state = attrs?.appEncryptionDeclarationState.map { formatState($0) } ?? "—"
          let platform = attrs?.platform.map { formatState($0) } ?? "—"
          let proprietary = attrs?.containsProprietaryCryptography.map { $0 ? "Yes" : "No" } ?? "—"
          let thirdParty = attrs?.containsThirdPartyCryptography.map { $0 ? "Yes" : "No" } ?? "—"
          let exempt = attrs?.isExempt.map { $0 ? "Yes" : "No" } ?? "—"
          let created = attrs?.createdDate.map { formatDate($0) } ?? "—"
          rows.append([state, platform, proprietary, thirdParty, exempt, created])
        }
      }
      
      if rows.isEmpty {
        print("No encryption declarations found.")
        return
      }
      
      Table.print(
        headers: ["State", "Platform", "Proprietary", "Third-Party", "Exempt", "Created"],
        rows: rows
      )
    }
  }
  
  struct EULACommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "eula",
      abstract: "View or manage custom EULA."
    )
    
    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String
    
    @Option(name: .long, help: "Path to a text file with EULA content.",
            completion: .file(extensions: ["txt"]))
    var file: String?
    
    @Flag(name: .long, help: "Remove the custom EULA.")
    var delete = false
    
    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false
    
    func validate() throws {
      if file != nil && delete {
        throw ValidationError("Cannot use --file and --delete together.")
      }
    }
    
    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appName = app.attributes?.name ?? bundleID
      
      // Try to get existing EULA (API returns 404 or null data when none exists)
      let existing: EndUserLicenseAgreement?
      do {
        existing = try await client.send(
          Resources.v1.apps.id(app.id).endUserLicenseAgreement.get()
        ).data
      } catch let error as ResponseError {
        if case .requestFailure(_, let statusCode, _) = error, statusCode == 404 {
          existing = nil
        } else {
          throw error
        }
      } catch is DecodingError {
        existing = nil
      }
      
      if delete {
        guard let eula = existing else {
          print("No custom EULA to delete. The standard Apple EULA applies.")
          return
        }
        
        let textLen = eula.attributes?.agreementText?.count ?? 0
        print("App:  \(appName)")
        print("EULA: Custom (\(textLen) characters)")
        print()
        
        guard confirm("Delete custom EULA? This will revert to the standard Apple EULA. [y/N] ") else {
          cancelled()
          return
        }
        
        try await client.send(
          Resources.v1.endUserLicenseAgreements.id(eula.id).delete
        )
        print()
        success("Deleted", "custom EULA.")
        return
      }
      
      if let filePath = file {
        // Create or update EULA from file
        let expandedPath = expandPath(filePath)
        guard FileManager.default.fileExists(atPath: expandedPath) else {
          throw ValidationError("File not found at '\(expandedPath)'.")
        }
        
        let text = try String(contentsOfFile: expandedPath, encoding: .utf8)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw ValidationError("EULA file is empty.")
        }
        
        print("App:  \(appName)")
        print("EULA: \(text.count) characters from \((expandedPath as NSString).lastPathComponent)")
        print()
        let preview = String(text.prefix(200))
        print("  \(preview)\(text.count > 200 ? "..." : "")")
        print()
        
        if let eula = existing {
          // Update existing
          guard confirm("Update existing EULA? [y/N] ") else {
            cancelled()
            return
          }
          
          _ = try await client.send(
            Resources.v1.endUserLicenseAgreements.id(eula.id).patch(
              EndUserLicenseAgreementUpdateRequest(
                data: .init(id: eula.id, attributes: .init(agreementText: text))
              )
            )
          )
          print()
          success("Updated", "EULA.")
        } else {
          // Create new — need all territory IDs
          var allTerritoryIDs: [String] = []
          for try await page in client.pages(Resources.v1.territories.get(limit: 200)) {
            for territory in page.data {
              allTerritoryIDs.append(territory.id)
            }
          }
          
          guard confirm("Create custom EULA for all \(allTerritoryIDs.count) territories? [y/N] ") else {
            cancelled()
            return
          }
          
          _ = try await client.send(
            Resources.v1.endUserLicenseAgreements.post(
              EndUserLicenseAgreementCreateRequest(
                data: .init(
                  attributes: .init(agreementText: text),
                  relationships: .init(
                    app: .init(data: .init(id: app.id)),
                    territories: .init(data: allTerritoryIDs.map { .init(id: $0) })
                  )
                )
              )
            )
          )
          print()
          success("Created", "EULA for \(allTerritoryIDs.count) territories.")
        }
        return
      }
      
      // View mode
      print("App:  \(appName)")
      
      guard let eula = existing,
            let text = eula.attributes?.agreementText,
            !text.isEmpty else {
        print("EULA: No custom EULA. The standard Apple EULA applies.")
        return
      }
      
      print("EULA: Custom (\(text.count) characters)")
      print()
      let preview = String(text.prefix(500))
      print("  \(preview)\(text.count > 500 ? "\n  [truncated]" : "")")
    }
  }

  // MARK: - Subscription Grace Period

  struct SubscriptionGracePeriod: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "subscription-grace-period",
      abstract: "View or update the app's subscription grace period settings.",
      discussion: """
        The grace period lets subscribers keep access for a short window after a failed
        renewal payment while Apple retries billing. Settings apply to the whole app.
        """
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .customLong("opt-in"), help: "Enable the grace period for production (true/false).")
    var optIn: String?

    @Option(name: .customLong("sandbox-opt-in"), help: "Enable the grace period for sandbox testing (true/false).")
    var sandboxOptIn: String?

    @Option(name: .long, help: "Grace period duration. Valid values: THREE_DAYS, SIXTEEN_DAYS, TWENTY_EIGHT_DAYS.")
    var duration: String?

    @Option(name: .customLong("renewal-type"), help: "Which renewals get the grace period. Valid values: ALL_RENEWALS, PAID_TO_PAID_ONLY.")
    var renewalType: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let current: AppStoreAPI.SubscriptionGracePeriod
      do {
        let response = try await client.send(
          Resources.v1.apps.id(app.id).subscriptionGracePeriod.get()
        )
        current = response.data
      } catch is DecodingError {
        throw ValidationError("No subscription grace period configuration exists for this app.")
      } catch let error as ResponseError {
        if case .requestFailure(_, let statusCode, _) = error, statusCode == 404 {
          throw ValidationError("No subscription grace period configuration exists for this app.")
        }
        throw error
      }

      let isEdit = optIn != nil || sandboxOptIn != nil || duration != nil || renewalType != nil

      if !isEdit {
        let attrs = current.attributes
        print("Subscription Grace Period:")
        print("  Opt-in (production): \(attrs?.isOptIn == true ? "Yes" : attrs?.isOptIn == false ? "No" : "—")")
        print("  Opt-in (sandbox):    \(attrs?.isSandboxOptIn == true ? "Yes" : attrs?.isSandboxOptIn == false ? "No" : "—")")
        print("  Duration:            \(attrs?.duration.map { formatState($0) } ?? "—")")
        print("  Renewal Type:        \(attrs?.renewalType.map { formatState($0) } ?? "—")")
        return
      }

      // Parse updates
      typealias Attrs = SubscriptionGracePeriodUpdateRequest.Data.Attributes

      let newOptIn: Bool? = try optIn.map {
        guard let b = Bool($0.lowercased()) else {
          throw ValidationError("Invalid value for --opt-in. Use 'true' or 'false'.")
        }
        return b
      }
      let newSandboxOptIn: Bool? = try sandboxOptIn.map {
        guard let b = Bool($0.lowercased()) else {
          throw ValidationError("Invalid value for --sandbox-opt-in. Use 'true' or 'false'.")
        }
        return b
      }
      let newDuration: SubscriptionGracePeriodDuration? = try duration.map {
        try parseEnum($0, name: "duration")
      }
      let newRenewalType: Attrs.RenewalType? = try renewalType.map {
        try parseEnum($0, name: "renewal-type")
      }

      print("Updates for subscription grace period:")
      if let v = newOptIn { print("  Opt-in (production): \(v ? "Yes" : "No")") }
      if let v = newSandboxOptIn { print("  Opt-in (sandbox):    \(v ? "Yes" : "No")") }
      if let v = newDuration { print("  Duration:            \(formatState(v))") }
      if let v = newRenewalType { print("  Renewal Type:        \(formatState(v))") }
      print()

      guard confirm("Apply these changes? [y/N] ") else {
        cancelled()
        return
      }

      _ = try await client.send(
        Resources.v1.subscriptionGracePeriods.id(current.id).patch(
          SubscriptionGracePeriodUpdateRequest(
            data: .init(
              id: current.id,
              attributes: .init(
                isOptIn: newOptIn,
                isSandboxOptIn: newSandboxOptIn,
                duration: newDuration,
                renewalType: newRenewalType
              )
            )
          )
        )
      )

      print()
      success("Updated", "subscription grace period.")
    }
  }
}

struct AgeRatingFields: Codable {
  // Intensity-based (NONE, INFREQUENT_OR_MILD, FREQUENT_OR_INTENSE)
  var alcoholTobaccoOrDrugUseOrReferences: String?
  var contests: String?
  var gamblingSimulated: String?
  var gunsOrOtherWeapons: String?
  var horrorOrFearThemes: String?
  var matureOrSuggestiveThemes: String?
  var profanityOrCrudeHumor: String?
  var sexualContentOrNudity: String?
  var sexualContentGraphicAndNudity: String?
  var violenceCartoonOrFantasy: String?
  var violenceRealistic: String?
  var violenceRealisticProlongedGraphicOrSadistic: String?
  var medicalOrTreatmentInformation: String?
  
  // Boolean
  var isAdvertising: Bool?
  var isGambling: Bool?
  var isUnrestrictedWebAccess: Bool?
  var isUserGeneratedContent: Bool?
  var isMessagingAndChat: Bool?
  var isLootBox: Bool?
  var isHealthOrWellnessTopics: Bool?
  var isParentalControls: Bool?
  var isAgeAssurance: Bool?
  
  // Other
  var kidsAgeBand: String?
  var ageRatingOverride: String?
}

struct LocaleFields: Codable {
  var description: String?
  var whatsNew: String?
  var keywords: String?
  var promotionalText: String?
  var marketingURL: String?
  var supportURL: String?
}

struct AppInfoLocaleFields: Codable {
  var name: String?
  var subtitle: String?
  var privacyPolicyURL: String?
  var privacyChoicesURL: String?
}

/// Encodes as `{"data": null}` for clearing a to-one relationship.
private struct NullRelationship: Encodable, Sendable {
  enum CodingKeys: String, CodingKey { case data }
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeNil(forKey: .data)
  }
}

private func describeDecodingError(_ error: DecodingError) -> String {
  switch error {
    case .typeMismatch(let type, let context):
      return "Type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
    case .valueNotFound(let type, let context):
      return "Missing value for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
    case .keyNotFound(let key, _):
      return "Unknown key '\(key.stringValue)'"
    case .dataCorrupted(let context):
      return context.debugDescription
    @unknown default:
      return "\(error)"
  }
}

func findApp(bundleID: String, client: AppStoreConnectClient) async throws -> App {
  let bundleID = resolveAlias(bundleID)
  let response = try await client.send(
    Resources.v1.apps.get(filterBundleID: [bundleID])
  )
  // filterBundleID can return prefix matches, so find the exact match
  guard let app = response.data.first(where: { $0.attributes?.bundleID == bundleID }) else {
    throw AppLookupError.notFound(bundleID)
  }
  return app
}

func parsePlatform(_ raw: String) throws -> Platform {
  switch raw.lowercased() {
    case "ios": return .iOS
    case "macos": return .macOS
    case "tvos": return .tvOS
    case "visionos": return .visionOS
    default: throw ValidationError("Invalid platform '\(raw)'. Use: ios, macos, tvos, visionos.")
  }
}

/// Shared `--platform` option for commands that resolve an App Store version.
/// A universal-purchase app can hold the same version on multiple platforms;
/// without this option such commands prompt to disambiguate.
struct PlatformOption: ParsableArguments {
  @Option(name: .long, help: "Platform: ios, macos, tvos, visionos. Defaults to all (prompts if ambiguous).")
  var platform: String?

  func parsed() throws -> Platform? {
    try platform.map(parsePlatform)
  }
}

/// Maps a Platform to an endpoint-specific platform filter enum. Every generated
/// platform filter enum shares the same raw values (IOS, MAC_OS, TV_OS, VISION_OS),
/// so one generic mapping covers versions, builds, and future endpoints.
func platformFilter<F: RawRepresentable>(_ platform: Platform?) -> [F]? where F.RawValue == String {
  platform.map {
    guard let filter = F(rawValue: $0.rawValue) else {
      preconditionFailure("Platform \($0.rawValue) is missing from \(F.self) — asc-swift enums out of sync.")
    }
    return [filter]
  }
}

func findVersion(appID: String, versionString: String?, platform: Platform? = nil, client: AppStoreConnectClient) async throws -> AppStoreVersion {
  func describe(_ v: AppStoreVersion) -> String {
    let p = v.attributes?.platform.map { formatState($0) } ?? "?"
    let ver = v.attributes?.versionString ?? "?"
    let state = v.attributes?.appVersionState.map { formatState($0) } ?? "?"
    return "\(p) — \(ver) (\(state))"
  }

  // When no specific version requested, prefer editable versions (prepareForSubmission/waitingForReview)
  if versionString == nil {
    let editableRequest = Resources.v1.apps.id(appID).appStoreVersions.get(
      filterAppVersionState: [.prepareForSubmission, .waitingForReview]
    )
    let editableResponse = try await client.send(editableRequest)
    var editable = editableResponse.data

    // Filter by platform if specified
    if let platform {
      editable = editable.filter { $0.attributes?.platform == platform }
    }

    if editable.count == 1 {
      return editable[0]
    } else if editable.count > 1 {
      return try promptSelection(
        "Multiple editable versions found", items: editable, display: describe,
        nonInteractiveHint: "Pass --platform to disambiguate.")
    }
  }

  // A universal-purchase app can hold the same version string on multiple
  // platforms — filter by platform, and prompt if still ambiguous.
  let request = Resources.v1.apps.id(appID).appStoreVersions.get(
    filterPlatform: platformFilter(platform),
    filterVersionString: versionString.map { [$0] }
  )
  let response = try await client.send(request)
  var candidates = response.data
  if versionString == nil {
    // Fallback (no editable versions): reduce to the latest version per platform.
    // The API returns versions newest-first, so keep the first one seen per platform.
    var seenPlatforms = Set<Platform?>()
    candidates = candidates.filter { seenPlatforms.insert($0.attributes?.platform).inserted }
  }
  if candidates.count > 1 {
    return try promptSelection(
      "Multiple matching versions found", items: candidates, display: describe,
      nonInteractiveHint: "Pass --platform to disambiguate.")
  }
  guard let version = candidates.first else {
    if let v = versionString {
      throw AppLookupError.versionNotFound(v, platform)
    }
    throw AppLookupError.noVersions(platform)
  }
  return version
}

/// Polls until a build finishes processing. Returns the final build.
/// Throws on timeout or if the build ends in a non-valid state.
func awaitBuildProcessing(
  appID: String,
  buildVersion: String?,
  platform: Platform? = nil,
  client: AppStoreConnectClient,
  interval: Int = 30,
  timeout: Int = 30
) async throws -> Build {
  let deadline = Date().addingTimeInterval(Double(timeout * 60))
  var waitingElapsed = 0
  var waitingStarted = false

  while Date() < deadline {
    let request = Resources.v1.builds.get(
      filterVersion: buildVersion.map { [$0] },
      filterPreReleaseVersionPlatform: platformFilter(platform),
      filterApp: [appID],
      sort: [.minusUploadedDate],
      limit: 1
    )
    let response = try await client.send(request)
    
    if let build = response.data.first,
       let state = build.attributes?.processingState {
      let version = build.attributes?.version ?? "?"
      
      // End the "not found" line if we were waiting
      if waitingStarted {
        print()
        waitingStarted = false
      }
      
      switch state {
        case .valid:
          print("Build \(version) is ready (VALID).")
          return build
        case .failed, .invalid:
          print("Build \(version) processing ended with state: \(state)")
          throw ExitCode.failure
        case .processing:
          print("Build \(version): still processing...")
      }
    } else {
      waitingElapsed += interval
      if !waitingStarted {
        print("Build not found yet", terminator: "")
        waitingStarted = true
      }
      print("...\(waitingElapsed)s", terminator: "")
      fflush(stdout)
    }
    
    try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
  }
  
  if waitingStarted { print() }
  print("\nTimed out after \(timeout) minutes.")
  throw ExitCode.failure
}

/// Picks a review submission from a response, prompting when more than one matches
/// (a universal-purchase app can have one active submission per platform).
/// A `platform` filter narrows the candidates first.
/// Returns nil when no submissions match.
private func selectSubmission(
  from response: ReviewSubmissionsResponse,
  platform: Platform? = nil
) throws -> (submission: ReviewSubmission, versionString: String)? {
  var includedVersions: [String: AppStoreVersion] = [:]
  for item in response.included ?? [] {
    if case .appStoreVersion(let v) = item {
      includedVersions[v.id] = v
    }
  }
  func versionString(_ submission: ReviewSubmission) -> String {
    guard let ref = submission.relationships?.appStoreVersionForReview?.data,
          let v = includedVersions[ref.id] else { return "unknown" }
    return v.attributes?.versionString ?? "unknown"
  }

  var candidates = response.data
  if let platform {
    candidates = candidates.filter { $0.attributes?.platform == platform }
  }

  guard !candidates.isEmpty else { return nil }
  let submission: ReviewSubmission
  if candidates.count == 1 {
    submission = candidates[0]
  } else {
    submission = try promptSelection(
      "Multiple review submissions found", items: candidates,
      display: { s in
        let p = s.attributes?.platform.map { formatState($0) } ?? "?"
        let state = s.attributes?.state.map { formatState($0) } ?? "?"
        return "\(p) — \(versionString(s)) (\(state))"
      },
      nonInteractiveHint: "Pass --platform to disambiguate.")
  }
  return (submission, versionString(submission))
}

/// Fetches builds for the app matching the given version, prompts the user to pick one, and attaches it.
/// Returns the selected build.
@discardableResult
private func selectBuild(appID: String, versionID: String, versionString: String?, platform: Platform? = nil, client: AppStoreConnectClient) async throws -> Build {
  let buildsResponse = try await client.send(
    Resources.v1.builds.get(
      filterPreReleaseVersionVersion: versionString.map { [$0] },
      filterPreReleaseVersionPlatform: platformFilter(platform),
      filterApp: [appID],
      sort: [.minusUploadedDate],
      limit: 10
    )
  )
  
  let builds = buildsResponse.data
  guard !builds.isEmpty else {
    if let v = versionString {
      throw ValidationError("No builds found for version \(v). Upload a build first via Xcode or Transporter.")
    }
    throw ValidationError("No builds found for this app. Upload a build first via Xcode or Transporter.")
  }
  
  print("Builds for version \(versionString ?? "all"):")
  for (i, build) in builds.enumerated() {
    let number = build.attributes?.version ?? "—"
    let state = build.attributes?.processingState.map { formatState($0) } ?? "—"
    let uploaded = build.attributes?.uploadedDate.map { formatDate($0) } ?? "—"
    print("  [\(i + 1)] \(number)  \(state)  \(uploaded)")
  }
  print()
  
  let selected: Build
  if autoConfirm {
    selected = builds[0]
    let number = selected.attributes?.version ?? "—"
    print("Auto-selected build \(number) (most recent).")
  } else {
    print("Select a build (1-\(builds.count)): ", terminator: "")
    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
          let choice = Int(input),
          choice >= 1, choice <= builds.count else {
      throw ValidationError("Invalid selection.")
    }
    selected = builds[choice - 1]
  }
  
  // Attach the build to the version
  try await client.send(
    Resources.v1.appStoreVersions.id(versionID).relationships.build.patch(
      AppStoreVersionBuildLinkageRequest(
        data: .init(id: selected.id)
      )
    )
  )
  
  return selected
}

enum AppLookupError: LocalizedError {
  case notFound(String)
  case versionNotFound(String, Platform?)
  case noVersions(Platform?)

  private static func platformSuffix(_ platform: Platform?) -> String {
    platform.map { " for \(formatState($0))" } ?? ""
  }

  var errorDescription: String? {
    switch self {
      case .notFound(let bundleID):
        return "No app found with bundle ID '\(bundleID)'."
      case .versionNotFound(let version, let platform):
        return "No App Store version '\(version)' found\(Self.platformSuffix(platform))."
      case .noVersions(let platform):
        return "No App Store versions found\(Self.platformSuffix(platform))."
    }
  }
}

