import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

struct AppsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "apps",
    abstract: "Manage apps.",
    subcommands: [List.self, Info.self, Versions.self],
    groupedSubcommands: [
      CommandGroup(name: "Version", subcommands: [CreateVersion.self, Copyright.self, BuildCommand.self, PhasedRelease.self, Release.self, RoutingCoverage.self]),
      CommandGroup(name: "Info & Content", subcommands: [AppInfoCommand.self, Localizations.self, MediaCommand.self]),
      CommandGroup(name: "Configuration", subcommands: [AccessibilityCommand.self, Availability.self, PricingCommand.self, Encryption.self, EULACommand.self, SubscriptionGracePeriod.self, StreamlinedPurchasing.self]),
      CommandGroup(name: "Review", subcommands: [ReviewCommand.self]),
    ]
  )
  
  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List all apps."
    )

    @OptionGroup var jsonOption: JSONOption

    private struct Entry: Encodable {
      let id: String
      let bundleID: String?
      let name: String?
      let sku: String?
    }

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let pages = try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.appsGetCollection().ok.body.json
      }
      let allApps = pages.flatMap(\.data).map { app in
        Entry(id: app.id, bundleID: app.attributes?.bundleId, name: app.attributes?.name, sku: app.attributes?.sku)
      }

      if jsonOption.json {
        try printJSON(allApps)
        return
      }

      Table.print(
        headers: ["Bundle ID", "Name", "SKU"],
        rows: allApps.map { [$0.bundleID ?? "—", $0.name ?? "—", $0.sku ?? "—"] }
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

    @OptionGroup var jsonOption: JSONOption

    private struct Detail: Encodable {
      struct Version: Encodable {
        let version: String?
        let platform: String?
        let state: String?
        let releaseType: String?
        let createdDate: Date?
      }
      let id: String
      let name: String?
      let bundleID: String?
      let sku: String?
      let primaryLocale: String?
      let latestVersion: Version?
    }

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let versions = try await client.appsAppStoreVersionsGetToManyRelated(
        path: .init(id: app.id),
        query: .init(filterAppVersionState: [.prepareForSubmission, .waitingForReview, .inReview, .pendingDeveloperRelease, .readyForDistribution])
      ).ok.body.json
      let attrs = app.attributes
      let detail = Detail(
        id: app.id,
        name: attrs?.name,
        bundleID: attrs?.bundleId,
        sku: attrs?.sku,
        primaryLocale: attrs?.primaryLocale,
        latestVersion: versions.data.first.map { latest in
          let v = latest.attributes
          return Detail.Version(
            version: v?.versionString,
            platform: v?.platform,
            state: v?.appVersionState,
            releaseType: v?.releaseType,
            createdDate: v?.createdDate
          )
        }
      )

      if jsonOption.json {
        try printJSON(detail)
        return
      }

      print("Name:            \(detail.name ?? "—")")
      print("Bundle ID:       \(detail.bundleID ?? "—")")
      print("SKU:             \(detail.sku ?? "—")")
      print("Primary Locale:  \(detail.primaryLocale.map { localeName($0) } ?? "—")")

      if let v = detail.latestVersion {
        print("")
        print("Latest Version:  \(v.version ?? "—")")
        print("Platform:        \(v.platform.map { formatState($0) } ?? "—")")
        print("State:           \(v.state.map { formatState($0) } ?? "—")")
        print("Release Type:    \(v.releaseType.map { formatState($0) } ?? "—")")
        print("Created:         \(v.createdDate.map { formatDate($0) } ?? "—")")
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

    @OptionGroup var jsonOption: JSONOption

    private struct Entry: Encodable {
      let id: String
      let version: String?
      let platform: String?
      let state: String?
      let releaseType: String?
      let createdDate: Date?
    }

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let response = try await client.appsAppStoreVersionsGetToManyRelated(path: .init(id: app.id)).ok.body.json

      let entries = response.data.map { version -> Entry in
        let attrs = version.attributes
        return Entry(
          id: version.id,
          version: attrs?.versionString,
          platform: attrs?.platform,
          state: attrs?.appVersionState,
          releaseType: attrs?.releaseType,
          createdDate: attrs?.createdDate
        )
      }

      if jsonOption.json {
        try printJSON(entries)
        return
      }

      Table.print(
        headers: ["Version", "Platform", "State", "Release Type", "Created"],
        rows: entries.map { e in
          [
            e.version ?? "—",
            e.platform.map { formatState($0) } ?? "—",
            e.state.map { formatState($0) } ?? "—",
            e.releaseType.map { formatState($0) } ?? "—",
            e.createdDate.map { formatDate($0) } ?? "—",
          ]
        }
      )
    }
  }
  
  struct Localizations: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "View and manage version localizations.",
      subcommands: [View.self, Update.self, Import.self, Export.self]
    )
    
    static func checkEditable(_ version: Components.Schemas.AppStoreVersion, promotionalTextOnly: Bool) throws {
      guard let state = version.attributes?.appVersionState, !VersionLocalizations.editableStates.contains(state) else {
        return // editable — all fields allowed
      }
      if promotionalTextOnly {
        return // promotional text can be updated in any state
      }
      throw ValidationError("Version is in state '\(state)' — only promotional text can be updated. Other fields require PREPARE_FOR_SUBMISSION or WAITING_FOR_REVIEW.")
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
        
        let response = try await client.appStoreVersionsAppStoreVersionLocalizationsGetToManyRelated(
          path: .init(id: version.id), query: .init(filterLocale: locale.map { [$0] })
        ).ok.body.json
        
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
          if let url = attrs?.marketingUrl {
            print("  Marketing URL:    \(url)")
          }
          if let url = attrs?.supportUrl {
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
        let locsResponse = try await client.appStoreVersionsAppStoreVersionLocalizationsGetToManyRelated(
          path: .init(id: version.id), query: .init(filterLocale: locale.map { [$0] })
        ).ok.body.json
        guard let localization = locsResponse.data.first else {
          let localeDesc = locale ?? "primary"
          throw ValidationError("No localization found for locale '\(localeDesc)'.")
        }
        
        let updated = try await VersionLocalizations.update(
          localizationID: localization.id,
          fields: LocaleFields(
            description: description, whatsNew: whatsNew, keywords: keywords, promotionalText: promotionalText,
            marketingURL: marketingURL, supportURL: supportURL),
          client: client)
        let attrs = updated.attributes
        let versionString = version.attributes?.versionString ?? "unknown"
        success("Updated", "localization for version \(versionString) [\(attrs?.locale.map { localeName($0) } ?? "—")]")
        
        if let d = attrs?.description, !d.isEmpty { print("  Description:      \(d.prefix(80))\(d.count > 80 ? "..." : "")") }
        if let w = attrs?.whatsNew, !w.isEmpty { print("  What's New:       \(w.prefix(80))\(w.count > 80 ? "..." : "")") }
        if let k = attrs?.keywords, !k.isEmpty { print("  Keywords:         \(k.prefix(80))\(k.count > 80 ? "..." : "")") }
        if let p = attrs?.promotionalText, !p.isEmpty { print("  Promotional Text: \(p.prefix(80))\(p.count > 80 ? "..." : "")") }
        if let u = attrs?.marketingUrl { print("  Marketing URL:    \(u)") }
        if let u = attrs?.supportUrl { print("  Support URL:      \(u)") }
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
        let locsResponse = try await client.appStoreVersionsAppStoreVersionLocalizationsGetToManyRelated(
          path: .init(id: version.id)
        ).ok.body.json
        
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
        version: Components.Schemas.AppStoreVersion, localeUpdates: [String: LocaleFields]
      ) throws -> [String: LocaleFields] {
        guard let state = version.attributes?.appVersionState,
          !VersionLocalizations.editableStates.contains(state)
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
        existing locByLocale: [String: Components.Schemas.AppStoreVersionLocalization],
        client: ASCClient
      ) async throws {
        for (locale, fields) in updates.sorted(by: { $0.key < $1.key }) {
          guard let localization = locByLocale[locale] else {
            guard confirm("  [\(localeName(locale))] Locale not found in current localizations for the app. Create it? [y/N] ") else {
              print("  [\(localeName(locale))] Skipped.")
              continue
            }
            let created = try await VersionLocalizations.create(
              versionID: versionID, locale: locale, fields: fields, client: client)
            print("  [\(localeName(locale))] \(green("Created."))")
            if verbose { printLocaleResponse(created.attributes) }
            continue
          }

          let updated = try await VersionLocalizations.update(
            localizationID: localization.id, fields: fields, client: client)
          print("  [\(localeName(locale))] Updated.")
          if verbose { printLocaleResponse(updated.attributes) }
        }
      }

      /// Prints the verbose API response for a single localization (shared by create and update).
      private func printLocaleResponse(_ attrs: Components.Schemas.AppStoreVersionLocalization.AttributesPayload?) {
        print("    Response:")
        print("      Locale:           \(attrs?.locale.map { localeName($0) } ?? "—")")
        if let d = attrs?.description { print("      Description:      \(d.prefix(120))\(d.count > 120 ? "..." : "")") }
        if let w = attrs?.whatsNew { print("      What's New:       \(w.prefix(120))\(w.count > 120 ? "..." : "")") }
        if let k = attrs?.keywords { print("      Keywords:         \(k.prefix(120))\(k.count > 120 ? "..." : "")") }
        if let p = attrs?.promotionalText { print("      Promotional Text: \(p.prefix(120))\(p.count > 120 ? "..." : "")") }
        if let u = attrs?.marketingUrl { print("      Marketing URL:    \(u)") }
        if let u = attrs?.supportUrl { print("      Support URL:      \(u)") }
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
        
        let locsResponse = try await client.appStoreVersionsAppStoreVersionLocalizationsGetToManyRelated(
          path: .init(id: version.id)
        ).ok.body.json
        
        var result: [String: LocaleFields] = [:]
        for loc in locsResponse.data {
          guard let locale = loc.attributes?.locale else { continue }
          let attrs = loc.attributes
          result[locale] = LocaleFields(
            description: attrs?.description,
            whatsNew: attrs?.whatsNew,
            keywords: attrs?.keywords,
            promotionalText: attrs?.promotionalText,
            marketingURL: attrs?.marketingUrl,
            supportURL: attrs?.supportUrl
          )
        }
        
        let data = try LocalizationFile.encode(result)
        
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

      let releaseTypeValue: ASCEnum.AppStoreVersionCreateRequestReleaseType?
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

      let created: Components.Schemas.AppStoreVersion
      do {
        switch try await createVersion(
          appID: app.id, versionString: versionString, platform: platformValue,
          releaseType: releaseTypeValue, copyright: copyright, client: client)
        {
          case .created(let version):
            created = version
          case .alreadyInPreparation:
            print("Version \(versionString) already exists for \(platform) (PREPARE_FOR_SUBMISSION). Continuing.")
            return
        }
      } catch VersionCreationError.alreadyExists(_, _, let state) {
        throw ValidationError("Version \(versionString) already exists for \(platform) (state: \(state.map { formatState($0) } ?? "unknown")).")
      }

      let attrs = created.attributes
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
      guard state == "PREPARE_FOR_SUBMISSION" || state == "WAITING_FOR_REVIEW" else {
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

      _ = try await updateVersion(versionID: appVersion.id, copyright: newCopyright, client: client)

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
          platform: versionPlatform(appVersion), client: client)
        let buildNumber = build.number ?? "unknown"
        let uploaded = build.uploadedDate.map { formatDate($0) } ?? "—"
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
        if let pendingBuild = lastUploadedBuild(for: versionPlatform(appVersion)) {
          print("Waiting for uploaded build \(pendingBuild) to become available...")
          print()
          let awaitedBuild = try await awaitBuildProcessing(
            appID: app.id,
            buildVersion: pendingBuild,
            platform: versionPlatform(appVersion),
            client: client
          )
          let uploaded = awaitedBuild.uploadedDate.map { formatDate($0) } ?? "—"
          print()
          print("Version: \(versionString)")
          print("Build:   \(pendingBuild)  VALID  \(uploaded)")
          print()
          
          guard confirm("Attach this build? [y/N] ") else {
            cancelled()
            return
          }
          
          try await Builds.attach(buildID: awaitedBuild.id, toVersion: appVersion.id, client: client)
          
          print()
          success("Attached", "build \(pendingBuild) (uploaded \(uploaded)) to version \(versionString).")
          return
        }
        
        let builds = try await Builds.list(
          appID: app.id, platform: versionPlatform(appVersion), version: versionString, limit: 1, client: client)
        
        guard let build = builds.first else {
          throw ValidationError("No builds found for version \(versionString). Upload a build first via Xcode or Transporter.")
        }
        
        var latestBuild = build
        let buildNumber = latestBuild.number ?? "unknown"
        let state = latestBuild.processingState
        let uploaded = latestBuild.uploadedDate.map { formatDate($0) } ?? "—"
        
        print("Version: \(versionString)")
        print("Build:   \(buildNumber)  \(state.map { formatState($0) } ?? "—")  \(uploaded)")
        print()
        
        if state == "PROCESSING" {
          if confirm("Build \(buildNumber) is still processing. Wait for it to finish? [y/N] ") {
            print()
            latestBuild = try await awaitBuildProcessing(
              appID: app.id,
              buildVersion: buildNumber,
              platform: versionPlatform(appVersion),
              client: client
            )
            print()
          } else {
            cancelled()
            return
          }
        } else if state == "FAILED" || state == "INVALID" {
          print("Build \(buildNumber) has state \(state.map { formatState($0) } ?? "—") and cannot be attached.")
          throw ExitCode.failure
        }
        
        guard confirm("Attach this build? [y/N] ") else {
          cancelled()
          return
        }
        
        try await Builds.attach(buildID: latestBuild.id, toVersion: appVersion.id, client: client)

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
        guard let existingBuild = try await attachedBuild(versionID: appVersion.id, client: client),
          existingBuild.attributes?.version != nil
        else {
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
        
        try await Builds.detach(fromVersion: appVersion.id, client: client)
        
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
        let release = try await Releases.enablePhasedRelease(versionID: appVersion.id, client: client)
        let state = release.state.map { formatState($0) } ?? "—"
        success("Enabled", "phased release for version \(versionString).")
        print("  State: \(state)")
        return
      }
      
      // All other actions require an existing phased release
      let existing = try await Releases.phasedRelease(versionID: appVersion.id, client: client)
      
      if pause {
        guard let pr = existing else {
          throw ValidationError("No phased release configured for version \(versionString). Use --enable first.")
        }
        let state = try await setPhasedReleaseState(.paused, id: pr.id, client: client)
        success("Paused", "phased release for version \(versionString).")
        print("  State: \(state)")
        return
      }
      
      if resume {
        guard let pr = existing else {
          throw ValidationError("No phased release configured for version \(versionString). Use --enable first.")
        }
        let state = try await setPhasedReleaseState(.active, id: pr.id, client: client)
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
        let state = try await setPhasedReleaseState(.complete, id: pr.id, client: client)
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
        try await Releases.removePhasedRelease(id: pr.id, client: client)
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
      
      let state = pr.state.map { formatState($0) } ?? "—"
      let startDate = pr.startDate.map { formatDate($0) } ?? "—"
      let day = pr.currentDayNumber.map { "\($0)" } ?? "—"
      let pauseDuration = pr.totalPauseDuration ?? 0
      
      print("App:            \(appName)")
      print("Version:        \(versionString)")
      print("Phased Release: \(state)")
      print("  Start date:   \(startDate)")
      print("  Day:          \(day) of 7")
      print("  Paused:       \(pauseDuration) day\(pauseDuration == 1 ? "" : "s")")
    }

    /// Sets a phased release's state; returns the new state for display.
    private func setPhasedReleaseState(
      _ state: ASCEnum.PhasedReleaseState, id: String, client: ASCClient
    ) async throws -> String {
      try await Releases.setPhasedReleaseState(state, id: id, client: client).state.map { formatState($0) } ?? "—"
    }
  }

  struct Release: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "release",
      abstract: "Release an approved version that is in Pending Developer Release."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the version pending developer release.")
    var version: String?

    @OptionGroup var platformOption: PlatformOption

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appName = app.attributes?.name ?? bundleID

      let response = try await client.appsAppStoreVersionsGetToManyRelated(
        path: .init(id: app.id),
        query: .init(
          filterPlatform: platformFilter(try platformOption.parsed()),
          filterVersionString: version.map { [$0] },
          filterAppVersionState: [.pendingDeveloperRelease])
      ).ok.body.json
      let candidates = response.data

      guard !candidates.isEmpty else {
        let scope = version.map { "Version \($0) of \(appName) is not" } ?? "No version of \(appName) is"
        throw ValidationError("\(scope) in Pending Developer Release.")
      }

      func describe(_ v: Components.Schemas.AppStoreVersion) -> String {
        let p = v.attributes?.platform.map { formatState($0) } ?? "?"
        return "\(p) — \(v.attributes?.versionString ?? "?")"
      }

      let appVersion = candidates.count == 1
        ? candidates[0]
        : try promptSelection(
            "Multiple versions pending developer release", items: candidates, display: describe,
            nonInteractiveHint: "Pass --platform to disambiguate.")

      guard confirm("Release \(appName) \(describe(appVersion)) to the App Store? [y/N] ") else {
        cancelled()
        return
      }

      try await Releases.release(versionID: appVersion.id, client: client)
      success("Released", "\(appName) \(describe(appVersion)) — release request submitted.")
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
        guard let coverage = try await AscelerateCore.RoutingCoverage.coverage(versionID: appVersion.id, client: client) else {
          print("App:              \(appName)")
          print("Version:          \(versionString)")
          print("Routing Coverage: Not configured")
          return
        }
        
        let fileName = coverage.fileName ?? "—"
        let state = coverage.state.map { formatState($0) } ?? "—"
        let fileSize = coverage.fileSize.map { "\(formatBytes($0))" } ?? "—"
        
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
      if let existingCoverage = try await AscelerateCore.RoutingCoverage.coverage(versionID: appVersion.id, client: client) {
        let existingName = existingCoverage.fileName ?? "unknown"
        print("Existing routing coverage: \(existingName)")
        guard confirm("Replace existing routing coverage with '\(fileName)'? [y/N] ") else {
          cancelled()
          return
        }
        try await AscelerateCore.RoutingCoverage.delete(id: existingCoverage.id, client: client)
        success("Deleted", "existing coverage.")
        print()
      }
      
      print("Uploading \(fileName) (\(formatBytes(fileSize)))...")
      fflush(stdout)
      
      try await AscelerateCore.RoutingCoverage.upload(
        MediaFile(path: expandedPath, fileName: fileName, fileSize: fileSize), versionID: appVersion.id, client: client)
      
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

      @OptionGroup var jsonOption: JSONOption

      /// One preflight check. `group` is nil for top-level checks, a locale code for
      /// per-locale checks, or the "inAppPurchases"/"subscriptions" section sentinels.
      /// `skipped` (omitted unless true) marks a check that wasn't evaluated because the
      /// developer took the item out on purpose; it counts as passed.
      fileprivate struct Check: Encodable {
        let group: String?
        let name: String
        let passed: Bool
        let detail: String
        var skipped: Bool? = nil
      }

      private struct Report: Encodable {
        let versionID: String
        let version: String?
        let platform: String?
        let state: String?
        let passed: Bool
        let checks: [Check]
      }

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appVersion = try await findVersion(appID: app.id, versionString: version, platform: try platformOption.parsed(), client: client)

        let versionString = appVersion.attributes?.versionString ?? "unknown"
        let versionState = appVersion.attributes?.appVersionState
        let stateStr = versionState.map { formatState($0) } ?? "unknown"
        let appName = app.attributes?.name ?? bundleID

        // Progress messages would corrupt the JSON stream.
        func progress(_ message: String) {
          if !jsonOption.json { print(message) }
        }

        progress("Preflight checks for \(appName) v\(versionString) (\(stateStr))")
        progress("")

        progress("Reading the version, its languages and the app's information...")
        let report = try await AscelerateCore.Preflight.report(appID: app.id, versionID: appVersion.id, client: client)
        var checks = report.checks.map { Self.check($0, report: report) }

        // 7. In-app purchases
        progress("Checking in-app purchases...")
        checks += try await checkInAppPurchases(appID: app.id, client: client)

        // 8. Subscriptions
        progress("Checking subscriptions...")
        checks += try await checkSubscriptions(appID: app.id, client: client)

        let failCount = checks.count(where: { !$0.passed })
        let skipCount = checks.count(where: { $0.skipped == true })

        if jsonOption.json {
          try printJSON(Report(
            versionID: appVersion.id,
            version: appVersion.attributes?.versionString,
            platform: appVersion.attributes?.platform,
            state: versionState,
            passed: failCount == 0,
            checks: checks
          ))
          if failCount > 0 { throw ExitCode.failure }
          return
        }

        // Render the table: a header row per group (locale or product section),
        // grouped checks indented beneath it.
        func groupTitle(_ group: String) -> String {
          let count = checks.count(where: { $0.group == group })
          switch group {
          case "inAppPurchases": return "In-App Purchases (\(count))"
          case "subscriptions": return "Subscriptions (\(count))"
          default: return localeName(group)
          }
        }

        var rows: [[String]] = []
        var currentGroup: String?
        for check in checks {
          if let group = check.group, group != currentGroup {
            currentGroup = group
            rows.append(["", ""])
            rows.append([groupTitle(group), ""])
          }
          let mark = check.skipped == true ? yellow("–") : check.passed ? green("✓") : red("✗")
          rows.append([(check.group == nil ? "" : "  ") + check.name, "\(mark) \(check.detail)"])
        }

        print()

        Table.print(
          headers: ["Check", "Status"],
          rows: rows
        )

        print()
        let passCount = checks.count - failCount - skipCount
        let skipText = skipCount > 0 ? ", \(yellow("\(skipCount) skipped"))" : ""
        let resultText = "\(green("\(passCount) passed"))\(skipText), \(failCount > 0 ? red("\(failCount) failed") : "\(failCount) failed")"
        print("Result: \(resultText)")

        if failCount > 0 {
          throw ExitCode.failure
        }
      }

      /// A core check as a table row.
      private static func check(_ check: AscelerateCore.Preflight.Check, report: AscelerateCore.Preflight.Report) -> Check {
        func fields(_ fields: [AscelerateCore.Preflight.Field]) -> String {
          fields.map { formatFieldName($0.rawValue) }.joined(separator: ", ")
        }
        var details: [String] = []
        for problem in check.problems {
          switch problem {
            case .missingFields(let missing): details.append("Missing: \(fields(missing))")
            case .tooLong(let field): details.append("\(formatFieldName(field.rawValue)) too long (>\(field.limit ?? 0) chars)")
            case .notValid: details.append("Build \(report.build?.number ?? "?") is \(formatState(report.build?.processingState ?? "unknown"))")
            case .exportCompliance: details.append("Export compliance not answered")
            default: break
          }
        }
        let language = report.languages.first { $0.locale == check.item.locale }
        let review = report.review
        let detail: String
        let name: String
        switch check.item {
          case .versionState:
            let state = formatState(report.state ?? "unknown")
            (name, detail) = ("Version state", check.passed ? state : "\(state) (can't be submitted)")
          case .build:
            name = "Build attached"
            detail = report.build == nil ? "No build attached" : check.passed ? "Build \(report.build?.number ?? "?")" : details.joined(separator: "; ")
          case .copyright:
            (name, detail) = ("Copyright", check.passed ? report.copyright ?? "" : "Missing")
          case .reviewContact:
            name = "Review contact"
            detail = check.passed
              ? "\(review?.contactFirstName ?? "") \(review?.contactLastName ?? ""), \(review?.contactEmail ?? "")"
              : "Missing: a first and last name, a phone number and an email address are needed"
          case .signIn:
            name = "Sign-in"
            detail = review?.demoAccountRequired == false ? "Not required" : check.passed ? "User name and password given" : "Required, but the user name or password is empty"
          case .category:
            (name, detail) = ("Category", report.primaryCategory.map(formatState) ?? "Not set")
          case .contentRights:
            (name, detail) = ("Content rights", report.contentRights.map(formatState) ?? "Not answered")
          case .price:
            (name, detail) = ("Price", check.passed ? "Set" : "Not set")
          case .availability:
            name = "Availability"
            detail = report.availableTerritories.map { $0 == 0 ? "Not available anywhere" : "\($0) territor\($0 == 1 ? "y" : "ies")" } ?? "Not set up"
          case .appInformation:
            (name, detail) = ("App info", check.passed ? "All fields filled" : details.joined(separator: "; "))
          case .localization:
            (name, detail) = ("Localizations", check.passed ? "All fields filled" : details.joined(separator: "; "))
          case .screenshots:
            let sets = language?.screenshotSets ?? 0, count = language?.screenshots ?? 0
            name = "Screenshots"
            detail = count > 0
              ? "\(sets) set\(sets == 1 ? "" : "s"), \(count) screenshot\(count == 1 ? "" : "s")"
              : check.passed ? "None (uses \(report.primaryLocale)'s)" : "No screenshots"
        }
        return Check(group: check.item.locale, name: name, passed: check.passed, detail: detail)
      }

      /// IAP/subscription states that can ride along a submission.
      private static let submittableProductStates: Set<String> = ["READY_TO_SUBMIT", "APPROVED", "WAITING_FOR_REVIEW", "IN_REVIEW"]

      /// A product the developer took off sale is a deliberate choice, not a problem: it's
      /// listed as skipped (neither its state nor its prices are checked).
      private static func productCheck(group: String, name: String, state: String?, hasPrices: Bool, missingPrices: String) -> Check {
        let stateStr = state.map { formatState($0) } ?? "unknown"
        if state == "DEVELOPER_REMOVED_FROM_SALE" {
          return Check(group: group, name: name, passed: true, detail: "\(stateStr) (skipped)", skipped: true)
        }
        let submittable = state.map(submittableProductStates.contains) ?? false
        return Check(group: group, name: name, passed: hasPrices && submittable, detail: hasPrices ? stateStr : missingPrices)
      }

      /// Checks each in-app purchase's price schedule and state.
      private func checkInAppPurchases(appID: String, client: ASCClient) async throws -> [Check] {
        let iaps = try await ASCPaging.allPages(next: { $0.links.next }) {
          try await client.appsInAppPurchasesV2GetToManyRelated(path: .init(id: appID), query: .init(limit: 200)).ok.body.json
        }.flatMap(\.data)

        var checks: [Check] = []
        let sortedIAPs = iaps.sorted(by: { ($0.attributes?.productId ?? "") < ($1.attributes?.productId ?? "") })
        let schedules = try await boundedConcurrentMap(sortedIAPs.map(\.id)) { id in
          try await IAPCommand.iapPriceScheduleExists(iapID: id, client: client)
        }
        for (iap, hasSchedule) in zip(sortedIAPs, schedules) {
          checks.append(Self.productCheck(
            group: "inAppPurchases", name: iap.attributes?.productId ?? iap.attributes?.name ?? iap.id,
            state: iap.attributes?.state, hasPrices: hasSchedule, missingPrices: "No price schedule"))
        }
        return checks
      }

      /// Checks each subscription's prices and state.
      private func checkSubscriptions(appID: String, client: ASCClient) async throws -> [Check] {
        let subGroups = try await SubCommand.fetchGroups(appID: appID, client: client)
        let allSubs = subGroups.flatMap(\.subscriptions)

        var checks: [Check] = []
        let sortedSubs = allSubs.sorted(by: { $0.productID < $1.productID })
        let priced = try await boundedConcurrentMap(sortedSubs.map(\.id)) { id in
          try await SubCommand.subscriptionHasPrices(subscriptionID: id, client: client)
        }
        for (sub, hasPrices) in zip(sortedSubs, priced) {
          checks.append(Self.productCheck(
            group: "subscriptions", name: sub.productID.isEmpty ? sub.id : sub.productID,
            state: sub.state, hasPrices: hasPrices, missingPrices: "No prices set"))
        }
        return checks
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

      @OptionGroup var jsonOption: JSONOption

      private struct Entry: Encodable {
        struct Item: Encodable {
          let id: String
          let state: String?
          /// Resolved for active submissions only: APP_STORE_VERSION, IN_APP_PURCHASE,
          /// SUBSCRIPTION, SUBSCRIPTION_GROUP.
          let kind: String?
          /// App version string, or the product's name.
          let name: String?
          /// Product version number and state (nil for app versions).
          let version: Int?
          let versionState: String?
        }
        let id: String
        let platform: String?
        let version: String?
        let versionState: String?
        let state: String?
        let submittedDate: Date?
        let items: [Item]
      }

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)

        let response = try await client.appsReviewSubmissionsGetToManyRelated(
          path: .init(id: app.id),
          query: .init(fieldsAppStoreVersions: [.versionString, .appVersionState], include: [.appStoreVersionForReview, .items])
        ).ok.body.json

        // Index included items for lookup
        var includedVersions: [String: Components.Schemas.AppStoreVersion] = [:]
        var includedItems: [String: Components.Schemas.ReviewSubmissionItem] = [:]
        for item in response.included ?? [] {
          switch item {
            case .appStoreVersions(let v): includedVersions[v.id] = v
            case .reviewSubmissionItems(let i): includedItems[i.id] = i
            default: break
          }
        }

        // Resolve what each item refers to, but only for active submissions — it
        // costs extra requests per product item.
        let activeStates: Set<String> = ["UNRESOLVED_ISSUES", "IN_REVIEW", "WAITING_FOR_REVIEW"]

        var allEntries: [Entry] = []
        for submission in response.data {
          let attrs = submission.attributes
          let reviewVersion = submission.relationships?.appStoreVersionForReview?.data
            .flatMap { includedVersions[$0.id] }
          let isActive = attrs?.state.map { activeStates.contains($0) } ?? false
          let resolved = isActive
            ? try await ProductVersions.reviewItems(submissionID: submission.id, client: client)
            : [:]
          let items = (submission.relationships?.items?.data ?? []).compactMap { ref in
            includedItems[ref.id].map {
              let info = resolved[$0.id]
              return Entry.Item(
                id: $0.id, state: $0.attributes?.state,
                kind: info?.kind, name: info?.name, version: info?.version, versionState: info?.versionState
              )
            }
          }
          allEntries.append(Entry(
            id: submission.id,
            platform: attrs?.platform,
            version: reviewVersion?.attributes?.versionString,
            versionState: reviewVersion?.attributes?.appVersionState,
            state: attrs?.state,
            submittedDate: attrs?.submittedDate,
            items: items
          ))
        }
        let entries = version != nil ? allEntries.filter { $0.version == version } : allEntries

        if jsonOption.json {
          try printJSON(entries)
          return
        }

        if allEntries.isEmpty {
          print("No review submissions found.")
          return
        }
        if entries.isEmpty {
          print("No review submissions found for version \(version!).")
          return
        }

        Table.print(
          headers: ["Platform", "Version", "State", "Submitted"],
          rows: entries.map { e in
            [
              e.platform.map { formatState($0) } ?? "—",
              e.version ?? "—",
              e.state.map { formatState($0) } ?? "—",
              e.submittedDate.map { formatDate($0) } ?? "—",
            ]
          }
        )

        // Show details for active submissions with issues
        for e in entries {
          guard let state = e.state, activeStates.contains(state) else { continue }

          let versionInfo = e.version.map {
            " — v\($0) (\(e.versionState.map { formatState($0) } ?? "?"))"
          } ?? ""

          print()
          print("--- Submission \(e.id) (\(formatState(state)))\(versionInfo) ---")

          for item in e.items {
            let target = item.kind.map { kind in
              let versionLabel = item.version.map { " v\($0)" } ?? ""
              let stateLabel = item.versionState.map { " (\(formatState($0)))" } ?? ""
              return "\(formatState(kind)) \(item.name ?? "—")\(versionLabel)\(stateLabel) — "
            } ?? ""
            print("  Item: \(target)\(item.state.map { formatState($0) } ?? "—")")
          }

          if state == "UNRESOLVED_ISSUES" {
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
        let result = try await client.reviewSubmissionsUpdateInstance(
          path: .init(id: submissionID),
          body: .json(.init(data: .init(
            attributes: .init(submitted: true), id: submissionID, _type: "reviewSubmissions")))
        ).ok.body.json
        let state = result.data.attributes?.state.map { formatState($0) } ?? "unknown"
        print()
        success("Submitted for review.")
        print("  State: \(state)")
      }

      private func confirmBuildAttached(
        app: Components.Schemas.App, appVersion: Components.Schemas.AppStoreVersion, versionString: String,
        versionState: String, platformValue: Platform, client: ASCClient
      ) async throws -> Bool {
        // Check if a build is already attached
        let existingBuild = try await attachedBuild(versionID: appVersion.id, client: client)
        
        if let build = existingBuild, build.attributes?.version != nil {
          let buildNumber = build.attributes?.version ?? "unknown"
          let uploaded = build.attributes?.uploadedDate.map { formatDate($0) } ?? "—"
          print("App:      \(app.attributes?.name ?? bundleID)")
          print("Version:  \(versionString)")
          print("Build:    \(buildNumber) (uploaded \(uploaded))")
          print("State:    \(versionState)")
          print("Platform: \(formatState(platformValue.rawValue))")
          print()
          guard confirm("Submit this version for App Review? [y/N] ") else {
            cancelled()
            return false
          }
        } else {
          print("App:      \(app.attributes?.name ?? bundleID)")
          print("Version:  \(versionString)")
          print("State:    \(versionState)")
          print("Platform: \(formatState(platformValue.rawValue))")
          print()
          print("No build attached to this version. Select a build first:")
          print()
          let selected = try await selectBuild(
            appID: app.id, versionID: appVersion.id, versionString: versionString,
            platform: platformValue, client: client)
          let buildNumber = selected.number ?? "unknown"
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
        app: Components.Schemas.App, appVersion: Components.Schemas.AppStoreVersion, versionString: String,
        platformValue: Platform, client: ASCClient
      ) async throws -> String? {
        // Check for existing active review submissions
        let existingSubmissions = try await client.appsReviewSubmissionsGetToManyRelated(
          path: .init(id: app.id),
          query: .init(filterState: [.readyForReview, .waitingForReview, .inReview, .unresolvedIssues])
        ).ok.body.json
        
        // A universal-purchase app can have one active submission per platform —
        // only an active submission for THIS platform counts.
        let submissionID: String
        if let active = existingSubmissions.data.first(where: { $0.attributes?.platform == platformValue.rawValue }) {
          let activeState = active.attributes?.state
          
          switch activeState {
            case "WAITING_FOR_REVIEW", "IN_REVIEW":
              print("Version is already submitted for review (state: \(activeState.map { formatState($0) } ?? "—")).")
              return nil
            case "READY_FOR_REVIEW":
              print("Found an existing draft review submission; using it.")
              submissionID = active.id
            case "UNRESOLVED_ISSUES":
              print("Found existing review submission with unresolved issues from a previous review.")
              guard confirm("Resubmit for review? [y/N] ") else {
                cancelled()
                return nil
              }
              submissionID = active.id
            default:
              submissionID = active.id
          }
          // A draft left by a failed submit (the version was rejected when added) has no items:
          // add the version if the submission doesn't hold it yet.
          // The version relationship only carries its ID when included.
          let items = try await client.reviewSubmissionsItemsGetToManyRelated(
            path: .init(id: submissionID), query: .init(fieldsAppStoreVersions: [.versionString], include: [.appStoreVersion])
          ).ok.body.json.data
          if !items.contains(where: { $0.relationships?.appStoreVersion?.data?.id == appVersion.id }) {
            try await addVersion(appVersion, versionString: versionString, to: submissionID, client: client)
          }
        } else {
          // Step 1: Create a review submission
          let submission = try await client.reviewSubmissionsCreateInstance(body: .json(.init(data: .init(
            attributes: .init(platform: platformValue.rawValue),
            relationships: .init(app: .init(data: .init(id: app.id, _type: "apps"))),
            _type: "reviewSubmissions"
          )))).created.body.json
          submissionID = submission.data.id
          print("Created review submission (\(submissionID))")
          
          // Step 2: Add the app store version as a review item
          try await addVersion(appVersion, versionString: versionString, to: submissionID, client: client)
        }
        return submissionID
      }

      /// Adds the version to a review submission. App Store Connect checks the version here: a
      /// 409 "not in valid state" lists what's missing in its associated errors, which the error
      /// output prints.
      private func addVersion(
        _ appVersion: Components.Schemas.AppStoreVersion, versionString: String, to submissionID: String, client: ASCClient
      ) async throws {
        _ = try await client.reviewSubmissionItemsCreateInstance(body: .json(.init(data: .init(
          relationships: .init(
            appStoreVersion: .init(data: .init(id: appVersion.id, _type: "appStoreVersions")),
            reviewSubmission: .init(data: .init(id: submissionID, _type: "reviewSubmissions"))
          ),
          _type: "reviewSubmissionItems"
        )))).created
        print("Added version \(versionString) to submission")
      }

      private func submitBundledProducts(app: Components.Schemas.App, client: ASCClient) async throws {
        // Offer to submit IAPs/subscriptions alongside the app version.
        // APPROVED products keep that state even when they have pending edits, so the
        // product state alone can't tell. The version history can (ProductVersions);
        // the API rejects submissions with no pending version (HTTP 409).
        let candidateStates: Set<String> = ["READY_TO_SUBMIT", "APPROVED"]

        let fetchedIAPs = try await ASCPaging.allPages(next: { $0.links.next }) {
          try await client.appsInAppPurchasesV2GetToManyRelated(path: .init(id: app.id), query: .init(limit: 200)).ok.body.json
        }.flatMap(\.data)

        let groups = try await SubCommand.fetchGroups(appID: app.id, client: client)
        let fetchedSubs = groups.flatMap(\.subscriptions)

        let skippedIAPs = fetchedIAPs.filter { !candidateStates.contains($0.attributes?.state ?? "") }
        let skippedSubs = fetchedSubs.filter { !candidateStates.contains($0.state) }

        // Partition candidates by whether they actually have a pending version.
        var pendingLabels: [String: String] = [:]  // product/group ID → "v2 (Prepare for Submission)"

        let candidateIAPs = fetchedIAPs.filter { candidateStates.contains($0.attributes?.state ?? "") }
        let iapPending = try await boundedConcurrentMap(candidateIAPs.map(\.id)) {
          try await ProductVersions.pendingIAP($0, client: client)
        }
        var submittableIAPs: [Components.Schemas.InAppPurchaseV2] = []
        var unchangedIAPs: [Components.Schemas.InAppPurchaseV2] = []
        for (iap, pending) in zip(candidateIAPs, iapPending) {
          if let pending {
            submittableIAPs.append(iap)
            pendingLabels[iap.id] = pending.label
          } else {
            unchangedIAPs.append(iap)
          }
        }

        let candidateSubs = fetchedSubs.filter { candidateStates.contains($0.state) }
        let subPending = try await boundedConcurrentMap(candidateSubs.map(\.id)) {
          try await ProductVersions.pendingSubscription($0, client: client)
        }
        var submittableSubIDs: Set<String> = []
        var unchangedSubs: [Subscriptions.Subscription] = []
        for (sub, pending) in zip(candidateSubs, subPending) {
          if let pending {
            submittableSubIDs.insert(sub.id)
            pendingLabels[sub.id] = pending.label
          } else {
            unchangedSubs.append(sub)
          }
        }

        // A group is submitted for its pending subscriptions and/or its own
        // pending version (group-level edits such as localizations).
        var submittableGroups: [SubCommand.GroupInfo] = []
        for group in groups {
          let hasPendingSubs = group.subscriptions.contains { submittableSubIDs.contains($0.id) }
          if let pending = try await ProductVersions.pendingGroup(group.id, client: client) {
            pendingLabels[group.id] = pending.label
          }
          if hasPendingSubs || pendingLabels[group.id] != nil {
            submittableGroups.append(group)
          }
        }

        if !skippedIAPs.isEmpty || !skippedSubs.isEmpty || !unchangedIAPs.isEmpty || !unchangedSubs.isEmpty {
          print()
          print("Skipping items not eligible for submission:")
          for iap in skippedIAPs {
            print("  IAP: \(iap.attributes?.name ?? "—") (\(iap.attributes?.productId ?? "—")) — \(iap.attributes?.state.map { formatState($0) } ?? "—")")
          }
          for sub in skippedSubs {
            print("  Sub: \(sub.name.isEmpty ? "—" : sub.name) (\(sub.productID.isEmpty ? "—" : sub.productID)) — \(sub.state.isEmpty ? "—" : formatState(sub.state))")
          }
          for iap in unchangedIAPs {
            print("  IAP: \(iap.attributes?.name ?? "—") (\(iap.attributes?.productId ?? "—")) — Approved (no pending changes)")
          }
          for sub in unchangedSubs {
            print("  Sub: \(sub.name.isEmpty ? "—" : sub.name) (\(sub.productID.isEmpty ? "—" : sub.productID)) — Approved (no pending changes)")
          }
        }

        if !submittableIAPs.isEmpty || !submittableGroups.isEmpty {
          print()
          print(yellow("In-app purchases/subscriptions with pending changes:"))
          for iap in submittableIAPs {
            print("  IAP: \(iap.attributes?.name ?? "—") (\(iap.attributes?.productId ?? "—")) — \(pendingLabels[iap.id] ?? "—")")
          }
          for group in submittableGroups {
            let groupNote = pendingLabels[group.id].map { " — group changes \($0)" } ?? ""
            print("  Group: \(group.name)\(groupNote)")
            for sub in group.subscriptions where submittableSubIDs.contains(sub.id) {
              print("    Sub: \(sub.name.isEmpty ? "—" : sub.name) (\(sub.productID.isEmpty ? "—" : sub.productID)) — \(pendingLabels[sub.id] ?? "—")")
            }
          }
          print()

          if confirm("Submit these with the app version? [y/N] ") {
            for iap in submittableIAPs {
              do {
                _ = try await client.inAppPurchaseSubmissionsCreateInstance(body: .json(.init(data: .init(
                  relationships: .init(inAppPurchaseV2: .init(data: .init(id: iap.id, _type: "inAppPurchases"))),
                  _type: "inAppPurchaseSubmissions"
                )))).created
                print("  \(green("Submitted")) IAP '\(iap.attributes?.name ?? "—")'")
              } catch let error where isNoPendingVersionError(error) {
                print("  Skipped IAP '\(iap.attributes?.name ?? "—")' — no pending version")
              }
            }
            for group in submittableGroups {
              // Submit individual subscriptions
              for sub in group.subscriptions where submittableSubIDs.contains(sub.id) {
                do {
                  _ = try await client.subscriptionSubmissionsCreateInstance(body: .json(.init(data: .init(
                    relationships: .init(subscription: .init(data: .init(id: sub.id, _type: "subscriptions"))),
                    _type: "subscriptionSubmissions"
                  )))).created
                  print("  \(green("Submitted")) subscription '\(sub.name.isEmpty ? "—" : sub.name)'")
                } catch let error where isNoPendingVersionError(error) {
                  print("  Skipped subscription '\(sub.name.isEmpty ? "—" : sub.name)' — no pending version")
                }
              }
              // Submit the group itself only when it has its own pending version
              guard pendingLabels[group.id] != nil else { continue }
              do {
                _ = try await client.subscriptionGroupSubmissionsCreateInstance(body: .json(.init(data: .init(
                  relationships: .init(subscriptionGroup: .init(data: .init(id: group.id, _type: "subscriptionGroups"))),
                  _type: "subscriptionGroupSubmissions"
                )))).created
                print("  \(green("Submitted")) subscription group '\(group.name)'")
              } catch let error where isNoPendingVersionError(error) {
                print("  Skipped subscription group '\(group.name)' — no pending version")
              }
            }
          }
        }
      }

      // Safety net in case the version-state mapping in ProductVersions over-reports —
      // treat the API's "no pending version" 409 as a per-item skip, not a hard failure.
      private func isNoPendingVersionError(_ error: Error) -> Bool {
        guard let ascError = ASCError.from(error), ascError.statusCode == 409 else { return false }
        return ascError.errors.contains { $0.detail.localizedCaseInsensitiveContains("no pending version") }
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
        let response = try await client.appsReviewSubmissionsGetToManyRelated(
          path: .init(id: app.id),
          query: .init(
            filterState: [.unresolvedIssues],
            fieldsAppStoreVersions: [.versionString, .appVersionState],
            include: [.appStoreVersionForReview, .items])
        ).ok.body.json

        guard let (submission, versionString) = try selectSubmission(
          from: response, platform: platformOption.parsed())
        else {
          print("No submissions with unresolved issues found.")
          return
        }

        // Get rejected items from included data
        let itemRefs = submission.relationships?.items?.data ?? []
        var rejectedItems: [Components.Schemas.ReviewSubmissionItem] = []
        if let included = response.included {
          for ref in itemRefs {
            for item in included {
              if case .reviewSubmissionItems(let i) = item,
                 i.id == ref.id,
                 i.attributes?.state == "REJECTED" {
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
          _ = try await client.reviewSubmissionItemsUpdateInstance(
            path: .init(id: item.id),
            body: .json(.init(data: .init(
              attributes: .init(resolved: true), id: item.id, _type: "reviewSubmissionItems")))
          ).ok
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
        let response = try await client.appsReviewSubmissionsGetToManyRelated(
          path: .init(id: app.id),
          query: .init(
            filterState: [.readyForReview, .waitingForReview, .inReview, .unresolvedIssues],
            fieldsAppStoreVersions: [.versionString],
            include: [.appStoreVersionForReview])
        ).ok.body.json

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
        
        let result = try await client.reviewSubmissionsUpdateInstance(
          path: .init(id: submission.id),
          body: .json(.init(data: .init(
            attributes: .init(canceled: true), id: submission.id, _type: "reviewSubmissions")))
        ).ok.body.json
        
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

        let existing = try await ReviewInformation.appStore(versionID: appVersion.id, client: client)

        let hasUpdates =
          contactFirstName != nil || contactLastName != nil || contactPhone != nil
          || contactEmail != nil || demoAccountName != nil || demoAccountPassword != nil
          || demoAccountRequired != nil || notes != nil

        let versionString = appVersion.attributes?.versionString ?? "unknown"

        if !hasUpdates {
          guard let a = existing?.information else {
            print("No App Review Information set for version \(versionString).")
            return
          }
          let name = [a.contactFirstName, a.contactLastName].compactMap { $0 }.joined(separator: " ")
          print("App Review Information for \(app.attributes?.name ?? bundleID) v\(versionString):")
          print("  Contact:       \(name.isEmpty ? "—" : name)")
          print("  Phone:         \(a.contactPhone ?? "—")")
          print("  Email:         \(a.contactEmail ?? "—")")
          print("  Demo Required: \(a.demoAccountRequired == true ? "Yes" : "No")")
          print("  Demo Account:  \(a.demoAccountName ?? "—")")
          print("  Demo Password: \(a.demoAccountPassword ?? "—")")
          print("  Notes:         \(a.notes ?? "—")")
          return
        }

        guard confirm("Update App Review Information for version \(versionString)? [y/N] ") else {
          cancelled()
          return
        }

        try await ReviewInformation.saveAppStore(
          ReviewInformation(
            contactFirstName: contactFirstName, contactLastName: contactLastName, contactPhone: contactPhone,
            contactEmail: contactEmail, demoAccountRequired: demoAccountRequired, demoAccountName: demoAccountName,
            demoAccountPassword: demoAccountPassword, notes: notes),
          from: existing?.information ?? .init(), detailID: existing?.id, versionID: appVersion.id, client: client)

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

          guard let detailID = try await ReviewAttachments.detailID(versionID: appVersion.id, client: client) else {
            print("No App Review Information (or attachments) set for this version.")
            return
          }

          let attachments = try await ReviewAttachments.list(detailID: detailID, client: client)
          if attachments.isEmpty {
            print("No attachments found.")
            return
          }

          var rows: [[String]] = []
          for att in attachments {
            rows.append([
              att.fileName ?? "—",
              att.fileSize.map { formatBytes($0) } ?? "—",
              att.state.map { formatState($0) } ?? "—",
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

          let detailID = try await ReviewAttachments.ensureDetailID(versionID: appVersion.id, client: client)
          let attachmentID = try await ReviewAttachments.upload(media, detailID: detailID, client: client)

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

          // Only for display: a failed lookup falls back to the ID.
          let name = (try? await ReviewAttachments.attachment(id: attachmentID, client: client))?.fileName
          print("Attachment: \(name ?? attachmentID)")
          print()
          guard confirm("Delete this attachment? [y/N] ") else {
            cancelled()
            return
          }

          try await ReviewAttachments.delete(id: attachmentID, client: client)
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
    
    // The core's lookups, with their errors as validation errors (the CLI's message format).
    static func findActiveAppInfo(appID: String, client: ASCClient) async throws -> Components.Schemas.AppInfo {
      try pickActiveAppInfo(from: await client.appsAppInfosGetToManyRelated(path: .init(id: appID)).ok.body.json.data)
    }

    static func pickActiveAppInfo(from appInfos: [Components.Schemas.AppInfo]) throws -> Components.Schemas.AppInfo {
      do {
        return try AppInfos.pickActive(from: appInfos)
      } catch let error as AppInfos.AppInfoError {
        throw ValidationError(error.localizedDescription)
      }
    }

    static func checkEditable(_ appInfo: Components.Schemas.AppInfo) throws {
      do {
        try AppInfos.checkEditable(appInfo)
      } catch let error as AppInfos.AppInfoError {
        throw ValidationError(error.localizedDescription)
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
          print("Categories (iOS):")
          for category in try await AppInfos.categories(platforms: [.ios], client: client) {
            print("  \(category.id)")
            for subcategory in category.subcategories {
              print("    \(subcategory)")
            }
          }
          return
        }
        
        guard let bundleID else {
          throw ValidationError("Please provide a <bundle-id>.")
        }
        
        let app = try await findApp(bundleID: bundleID, client: client)
        
        let response = try await client.appsAppInfosGetToManyRelated(
          path: .init(id: app.id),
          query: .init(include: [.primaryCategory, .secondaryCategory, .appInfoLocalizations], limitAppInfoLocalizations: 50)
        ).ok.body.json
        
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
        let localizations = response.included?.compactMap { item -> Components.Schemas.AppInfoLocalization? in
          if case .appInfoLocalizations(let loc) = item, locIDs.contains(loc.id) {
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
            if let url = locAttrs?.privacyPolicyUrl, !url.isEmpty {
              print("    Privacy Policy URL:  \(url)")
            }
            if let url = locAttrs?.privacyChoicesUrl, !url.isEmpty {
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
          let locsResponse = try await client.appInfosAppInfoLocalizationsGetToManyRelated(
            path: .init(id: appInfo.id), query: .init(filterLocale: locale.map { [$0] })
          ).ok.body.json
          guard let localization = locsResponse.data.first else {
            let localeDesc = locale ?? "primary"
            throw ValidationError("No localization found for locale '\(localeDesc)'.")
          }
          
          let updated = try await AppInfos.updateLocalization(
            id: localization.id, name: name, subtitle: subtitle, privacyPolicyURL: privacyPolicyURL,
            privacyChoicesURL: privacyChoicesURL, client: client)
          let updatedLocale = updated.attributes?.locale ?? locale ?? "primary"
          success("Updated", "localization [\(updatedLocale)].")
        }
        
        // Update categories
        if hasCategoryFields {
          var changes: [AppInfos.CategorySlot: String?] = [:]
          if let primaryCategory { changes[.primaryCategory] = primaryCategory }
          if let secondaryCategory { changes[.secondaryCategory] = secondaryCategory }
          try await AppInfos.updateCategories(appInfoID: appInfo.id, changes, client: client)
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
        let locsResponse = try await client.appInfosAppInfoLocalizationsGetToManyRelated(
          path: .init(id: appInfo.id)
        ).ok.body.json
        
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

            let response = try await client.appInfoLocalizationsCreateInstance(body: .json(.init(data: .init(
              attributes: .init(
                locale: locale, name: name, privacyChoicesUrl: fields.privacyChoicesURL,
                privacyPolicyUrl: fields.privacyPolicyURL, subtitle: fields.subtitle),
              relationships: .init(appInfo: .init(data: .init(id: appInfo.id, _type: "appInfos"))),
              _type: "appInfoLocalizations"
            )))).created.body.json
            print("  [\(localeName(locale))] \(green("Created."))")

            if verbose {
              let attrs = response.data.attributes
              print("    Response:")
              print("      Locale:             \(attrs?.locale.map { localeName($0) } ?? "—")")
              if let v = attrs?.name { print("      Name:               \(v)") }
              if let v = attrs?.subtitle { print("      Subtitle:           \(v)") }
              if let v = attrs?.privacyPolicyUrl { print("      Privacy Policy URL: \(v)") }
              if let v = attrs?.privacyChoicesUrl { print("      Privacy Choices URL: \(v)") }
            }
            continue
          }

          let updated = try await AppInfos.updateLocalization(
            id: localization.id, name: fields.name, subtitle: fields.subtitle, privacyPolicyURL: fields.privacyPolicyURL,
            privacyChoicesURL: fields.privacyChoicesURL, client: client)
          print("  [\(localeName(locale))] Updated.")

          if verbose {
            let attrs = updated.attributes
            print("    Response:")
            print("      Locale:             \(attrs?.locale.map { localeName($0) } ?? "—")")
            if let v = attrs?.name { print("      Name:               \(v)") }
            if let v = attrs?.subtitle { print("      Subtitle:           \(v)") }
            if let v = attrs?.privacyPolicyUrl { print("      Privacy Policy URL: \(v)") }
            if let v = attrs?.privacyChoicesUrl { print("      Privacy Choices URL: \(v)") }
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
        
        let locsResponse = try await client.appInfosAppInfoLocalizationsGetToManyRelated(
          path: .init(id: appInfo.id)
        ).ok.body.json
        
        var result: [String: AppInfoLocaleFields] = [:]
        for loc in locsResponse.data {
          guard let locale = loc.attributes?.locale else { continue }
          let attrs = loc.attributes
          result[locale] = AppInfoLocaleFields(
            name: attrs?.name,
            subtitle: attrs?.subtitle,
            privacyPolicyURL: attrs?.privacyPolicyUrl,
            privacyChoicesURL: attrs?.privacyChoicesUrl
          )
        }
        
        let data = try LocalizationFile.encode(result)
        
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

      static func fetchDeclaration(appID: String, client: ASCClient) async throws -> Components.Schemas.AgeRatingDeclaration {
        let appInfo = try await AppInfoCommand.findActiveAppInfo(appID: appID, client: client)
        return try await AppInfos.ageRatingDeclaration(appInfoID: appInfo.id, client: client)
      }

      static func toFields(attrs: Components.Schemas.AgeRatingDeclaration.AttributesPayload?) -> AgeRatingFields {
        AgeRatingFields(attrs)
      }

      struct View: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "View age rating declaration.")

        @Argument(help: "The bundle identifier of the app.",
                  completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
        var bundleID: String

        func run() async throws {
          let client = try ClientFactory.makeClient()
          let app = try await findApp(bundleID: bundleID, client: client)
          let declaration = try await AgeRating.fetchDeclaration(appID: app.id, client: client)
          let attrs = AgeRating.toFields(attrs: declaration.attributes)
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
          ("Alcohol, Tobacco, or Drug Use", intensityLabel(attrs.alcoholTobaccoOrDrugUseOrReferences)),
          ("Contests", intensityLabel(attrs.contests)),
          ("Gambling (simulated)", intensityLabel(attrs.gamblingSimulated)),
          ("Guns or Other Weapons", intensityLabel(attrs.gunsOrOtherWeapons)),
          ("Horror or Fear Themes", intensityLabel(attrs.horrorOrFearThemes)),
          ("Mature or Suggestive Themes", intensityLabel(attrs.matureOrSuggestiveThemes)),
          ("Profanity or Crude Humor", intensityLabel(attrs.profanityOrCrudeHumor)),
          ("Sexual Content or Nudity", intensityLabel(attrs.sexualContentOrNudity)),
          ("Sexual Content (graphic)", intensityLabel(attrs.sexualContentGraphicAndNudity)),
          ("Violence (cartoon/fantasy)", intensityLabel(attrs.violenceCartoonOrFantasy)),
          ("Violence (realistic)", intensityLabel(attrs.violenceRealistic)),
          ("Violence (graphic/sadistic)", intensityLabel(attrs.violenceRealisticProlongedGraphicOrSadistic)),
          ("Medical Information", intensityLabel(attrs.medicalOrTreatmentInformation)),
        ]
      
        // Boolean ratings
        let boolRows: [(String, String)] = [
          ("Advertising", boolLabel(attrs.isAdvertising)),
          ("Gambling", boolLabel(attrs.isGambling)),
          ("Unrestricted Web Access", boolLabel(attrs.isUnrestrictedWebAccess)),
          ("User-Generated Content", boolLabel(attrs.isUserGeneratedContent)),
          ("Messaging and Chat", boolLabel(attrs.isMessagingAndChat)),
          ("Loot Box", boolLabel(attrs.isLootBox)),
          ("Health/Wellness Topics", boolLabel(attrs.isHealthOrWellnessTopics)),
          ("Parental Controls", boolLabel(attrs.isParentalControls)),
          ("Age Assurance", boolLabel(attrs.isAgeAssurance)),
          ("Social Media", boolLabel(attrs.isSocialMedia)),
          ("Social Media Age Restricted", boolLabel(attrs.isSocialMediaAgeRestricted)),
        ]
      
        // Other
        let kidsAgeBand = attrs.kidsAgeBand?
          .replacingOccurrences(of: "_", with: " ")
          .capitalized ?? "—"
        let ageOverride = attrs.ageRatingOverride?
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
          let declaration = try await AgeRating.fetchDeclaration(appID: app.id, client: client)
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
          let declaration = try await AgeRating.fetchDeclaration(appID: app.id, client: client)
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
          if let v = fields.isSocialMedia { print("  Social Media: \(v)"); changeCount += 1 }
          if let v = fields.isSocialMediaAgeRestricted { print("  Social Media Age Restricted: \(v)"); changeCount += 1 }
          if let v = fields.kidsAgeBand { print("  Kids Age Band: \(v)"); changeCount += 1 }
          if let v = fields.ageRatingOverride { print("  Age Rating Override: \(v)"); changeCount += 1 }

          if changeCount == 0 {
            throw ValidationError("JSON file contains no age rating fields.")
          }

          // Validate every enum value up front: the request carries plain strings.
          typealias E = ASCEnum
          func value<T: RawRepresentable & CaseIterable>(_ raw: String?, _ name: String, _: T.Type) throws -> String?
          where T.RawValue == String {
            try raw.map { (try parseEnum($0, name: name) as T).rawValue }
          }
          let attributes = Components.Schemas.AgeRatingDeclarationUpdateRequest.DataPayload.AttributesPayload(
            advertising: fields.isAdvertising,
            ageAssurance: fields.isAgeAssurance,
            ageRatingOverrideV2: try value(fields.ageRatingOverride, "ageRatingOverride", E.AgeRatingDeclarationUpdateRequestAgeRatingOverrideV2.self),
            alcoholTobaccoOrDrugUseOrReferences: try value(
              fields.alcoholTobaccoOrDrugUseOrReferences, "alcoholTobaccoOrDrugUseOrReferences",
              E.AgeRatingDeclarationUpdateRequestAlcoholTobaccoOrDrugUseOrReferences.self),
            contests: try value(fields.contests, "contests", E.AgeRatingDeclarationUpdateRequestContests.self),
            gambling: fields.isGambling,
            gamblingSimulated: try value(fields.gamblingSimulated, "gamblingSimulated", E.AgeRatingDeclarationUpdateRequestGamblingSimulated.self),
            gunsOrOtherWeapons: try value(fields.gunsOrOtherWeapons, "gunsOrOtherWeapons", E.AgeRatingDeclarationUpdateRequestGunsOrOtherWeapons.self),
            healthOrWellnessTopics: fields.isHealthOrWellnessTopics,
            horrorOrFearThemes: try value(fields.horrorOrFearThemes, "horrorOrFearThemes", E.AgeRatingDeclarationUpdateRequestHorrorOrFearThemes.self),
            kidsAgeBand: try value(fields.kidsAgeBand, "kidsAgeBand", E.KidsAgeBand.self),
            lootBox: fields.isLootBox,
            matureOrSuggestiveThemes: try value(
              fields.matureOrSuggestiveThemes, "matureOrSuggestiveThemes", E.AgeRatingDeclarationUpdateRequestMatureOrSuggestiveThemes.self),
            medicalOrTreatmentInformation: try value(
              fields.medicalOrTreatmentInformation, "medicalOrTreatmentInformation",
              E.AgeRatingDeclarationUpdateRequestMedicalOrTreatmentInformation.self),
            messagingAndChat: fields.isMessagingAndChat,
            parentalControls: fields.isParentalControls,
            profanityOrCrudeHumor: try value(
              fields.profanityOrCrudeHumor, "profanityOrCrudeHumor", E.AgeRatingDeclarationUpdateRequestProfanityOrCrudeHumor.self),
            sexualContentGraphicAndNudity: try value(
              fields.sexualContentGraphicAndNudity, "sexualContentGraphicAndNudity",
              E.AgeRatingDeclarationUpdateRequestSexualContentGraphicAndNudity.self),
            sexualContentOrNudity: try value(
              fields.sexualContentOrNudity, "sexualContentOrNudity", E.AgeRatingDeclarationUpdateRequestSexualContentOrNudity.self),
            socialMedia: fields.isSocialMedia,
            socialMediaAgeRestricted: fields.isSocialMediaAgeRestricted,
            unrestrictedWebAccess: fields.isUnrestrictedWebAccess,
            userGeneratedContent: fields.isUserGeneratedContent,
            violenceCartoonOrFantasy: try value(
              fields.violenceCartoonOrFantasy, "violenceCartoonOrFantasy", E.AgeRatingDeclarationUpdateRequestViolenceCartoonOrFantasy.self),
            violenceRealistic: try value(fields.violenceRealistic, "violenceRealistic", E.AgeRatingDeclarationUpdateRequestViolenceRealistic.self),
            violenceRealisticProlongedGraphicOrSadistic: try value(
              fields.violenceRealisticProlongedGraphicOrSadistic, "violenceRealisticProlongedGraphicOrSadistic",
              E.AgeRatingDeclarationUpdateRequestViolenceRealisticProlongedGraphicOrSadistic.self)
          )

          print()
          guard confirm("Update \(changeCount) age rating field\(changeCount == 1 ? "" : "s")? [y/N] ") else {
            cancelled()
            return
          }

          try await AppInfos.updateAgeRatingDeclaration(id: declaration.id, attributes, client: client)
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
      
      guard let availability = try await AppAvailability.availability(appID: app.id, client: client) else {
        throw AppAvailability.NotSetUpError(appName: appName)
      }
      let availableInNew: Bool? = availability.availableInNewTerritories
      let territoryMap = availability.territories.map { (code: $0.territoryID, id: $0.id, isAvailable: $0.available) }
      
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
            try await AppAvailability.update(id: change.id, available: change.newValue, client: client)
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
        
        let created = try await EncryptionDeclarations.create(
          appID: app.id, appDescription: desc, containsProprietaryCryptography: proprietaryCrypto,
          containsThirdPartyCryptography: thirdPartyCrypto, availableOnFrenchStore: availableOnFrenchStore, client: client)
        let state = created.state.map { formatState($0) } ?? "—"
        let exempt = created.exempt.map { $0 ? "Yes" : "No" } ?? "—"
        print()
        success("Created", "encryption declaration.")
        print("  State:  \(state)")
        print("  Exempt: \(exempt)")
        return
      }
      
      // View mode
      print("App: \(appName)")
      print()
      
      let declarations = try await EncryptionDeclarations.list(appID: app.id, client: client)
      let rows: [[String]] = declarations.map { decl in
        [
          decl.state.map { formatState($0) } ?? "—",
          decl.platform.map { formatState($0) } ?? "—",
          decl.containsProprietaryCryptography.map { $0 ? "Yes" : "No" } ?? "—",
          decl.containsThirdPartyCryptography.map { $0 ? "Yes" : "No" } ?? "—",
          decl.exempt.map { $0 ? "Yes" : "No" } ?? "—",
          decl.createdDate.map { formatDate($0) } ?? "—",
        ]
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
      
      let existing = try await LicenseAgreements.agreement(appID: app.id, client: client)
      
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
        
        try await LicenseAgreements.delete(id: eula.id, client: client)
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
          
          try await LicenseAgreements.update(id: eula.id, text: text, client: client)
          print()
          success("Updated", "EULA.")
        } else {
          // Create new — need all territory IDs
          let allTerritoryIDs = try await LicenseAgreements.allTerritoryIDs(client: client)
          
          guard confirm("Create custom EULA for all \(allTerritoryIDs.count) territories? [y/N] ") else {
            cancelled()
            return
          }
          
          try await LicenseAgreements.create(appID: app.id, text: text, territoryIDs: allTerritoryIDs, client: client)
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

      let current = try await Subscriptions.gracePeriod(appID: app.id, client: client)

      let isEdit = optIn != nil || sandboxOptIn != nil || duration != nil || renewalType != nil

      if !isEdit {
        print("Subscription Grace Period:")
        print("  Opt-in (production): \(current.optIn ? "Yes" : "No")")
        print("  Opt-in (sandbox):    \(current.sandboxOptIn ? "Yes" : "No")")
        print("  Duration:            \(current.duration.map { formatState($0) } ?? "—")")
        print("  Renewal Type:        \(current.renewalType.map { formatState($0) } ?? "—")")
        return
      }

      // Parse updates
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
      let newDuration: ASCEnum.SubscriptionGracePeriodDuration? = try duration.map {
        try parseEnum($0, name: "duration")
      }
      let newRenewalType: ASCEnum.SubscriptionGracePeriodUpdateRequestRenewalType? = try renewalType.map {
        try parseEnum($0, name: "renewal-type")
      }

      print("Updates for subscription grace period:")
      if let v = newOptIn { print("  Opt-in (production): \(v ? "Yes" : "No")") }
      if let v = newSandboxOptIn { print("  Opt-in (sandbox):    \(v ? "Yes" : "No")") }
      if let v = newDuration { print("  Duration:            \(formatState(v.rawValue))") }
      if let v = newRenewalType { print("  Renewal Type:        \(formatState(v.rawValue))") }
      print()

      guard confirm("Apply these changes? [y/N] ") else {
        cancelled()
        return
      }

      let saved = try await Subscriptions.updateGracePeriod(
        id: current.id, optIn: newOptIn, sandboxOptIn: newSandboxOptIn, duration: newDuration?.rawValue,
        renewalType: newRenewalType?.rawValue, client: client)

      print()
      success("Updated", "subscription grace period: production \(saved.optIn ? "on" : "off"), sandbox \(saved.sandboxOptIn ? "on" : "off")\(saved.duration.map { ", \(formatState($0))" } ?? "")\(saved.renewalType.map { ", \(formatState($0))" } ?? "").")
    }
  }

  // MARK: - Streamlined Purchasing

  struct StreamlinedPurchasing: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "streamlined-purchasing",
      abstract: "View or change whether customers can buy the app's subscriptions outside the app.",
      discussion: """
        On by default. Turning it off needs an approved build that uses the StoreKit purchase APIs;
        customers then subscribe only from within the app. Applies to all the app's subscriptions.
        """
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .long, help: "Turn streamlined purchasing on or off (true/false).")
    var enabled: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let newValue: Bool? = try enabled.map {
        guard let b = Bool($0.lowercased()) else {
          throw ValidationError("Invalid value for --enabled. Use 'true' or 'false'.")
        }
        return b
      }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let current = try await Subscriptions.streamlinedPurchasing(appID: app.id, client: client)
      guard let newValue else {
        print("Streamlined Purchasing: \(current ? "On" : "Off")")
        return
      }
      if newValue == current {
        print("Streamlined Purchasing is already \(current ? "on" : "off").")
        return
      }
      guard confirm("Turn streamlined purchasing \(newValue ? "on" : "off")? [y/N] ") else {
        cancelled()
        return
      }
      let saved = try await Subscriptions.setStreamlinedPurchasing(appID: app.id, enabled: newValue, client: client)
      success("Turned", "streamlined purchasing \(saved ? "on" : "off").")
    }
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

func parsePlatform(_ raw: String) throws -> Platform {
  switch raw.lowercased() {
    case "ios": return .ios
    case "macos": return .macOs
    case "tvos": return .tvOs
    case "visionos": return .visionOs
    default: throw ValidationError("Invalid platform '\(raw)'. Use: ios, macos, tvos, visionos.")
  }
}

/// Looks up an app by bundle ID or alias.
func findApp(bundleID: String, client: ASCClient) async throws -> Components.Schemas.App {
  try await findApp(exactBundleID: resolveAlias(bundleID), client: client)
}

/// Resolves an App Store version, prompting when several platforms match.
func findVersion(appID: String, versionString: String?, platform: Platform? = nil, client: ASCClient) async throws -> Components.Schemas.AppStoreVersion {
  try await findVersion(appID: appID, versionString: versionString, platform: platform, client: client) {
    try promptSelection($0, items: $1, display: $2, nonInteractiveHint: "Pass --platform to disambiguate.")
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

/// Polls until a build finishes processing, printing where it stands. Returns the final build.
/// Exits with a failure on timeout or if the build ends in a non-valid state.
func awaitBuildProcessing(
  appID: String,
  buildVersion: String?,
  platform: Platform? = nil,
  client: ASCClient,
  interval: Int = 30,
  timeout: Int = 30
) async throws -> Builds.Build {
  // Whether the "not found" line is still open.
  var waiting = false
  func endWaitingLine() {
    if waiting {
      print()
      waiting = false
    }
  }
  do {
    let build = try await Builds.waitForProcessing(
      appID: appID, number: buildVersion, platform: platform, interval: interval, timeout: timeout, client: client
    ) { update in
      switch update {
        case .notFound(let elapsed):
          if !waiting {
            print("Build not found yet", terminator: "")
            waiting = true
          }
          print("...\(elapsed)s", terminator: "")
          fflush(stdout)
        case .processing(let build):
          endWaitingLine()
          print("Build \(build.number ?? "?"): still processing...")
      }
    }
    endWaitingLine()
    print("Build \(build.number ?? "?") is ready (VALID).")
    return build
  } catch let error as Builds.ProcessingError {
    endWaitingLine()
    switch error {
      case .ended(let number, let state): print("Build \(number) processing ended with state: \(state.lowercased())")
      case .timedOut(let minutes): print("\nTimed out after \(minutes) minutes.")
    }
    throw ExitCode.failure
  }
}

/// Picks a review submission from a response, prompting when more than one matches
/// (a universal-purchase app can have one active submission per platform).
/// A `platform` filter narrows the candidates first.
/// Returns nil when no submissions match.
private func selectSubmission(
  from response: Components.Schemas.ReviewSubmissionsResponse,
  platform: Platform? = nil
) throws -> (submission: Components.Schemas.ReviewSubmission, versionString: String)? {
  var includedVersions: [String: Components.Schemas.AppStoreVersion] = [:]
  for item in response.included ?? [] {
    if case .appStoreVersions(let v) = item {
      includedVersions[v.id] = v
    }
  }
  func versionString(_ submission: Components.Schemas.ReviewSubmission) -> String {
    guard let ref = submission.relationships?.appStoreVersionForReview?.data,
          let v = includedVersions[ref.id] else { return "unknown" }
    return v.attributes?.versionString ?? "unknown"
  }

  var candidates = response.data
  if let platform {
    candidates = candidates.filter { $0.attributes?.platform == platform.rawValue }
  }

  guard !candidates.isEmpty else { return nil }
  let submission: Components.Schemas.ReviewSubmission
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
private func selectBuild(appID: String, versionID: String, versionString: String?, platform: Platform? = nil, client: ASCClient) async throws -> Builds.Build {
  let builds = try await Builds.list(appID: appID, platform: platform, version: versionString, limit: 10, client: client)
  guard !builds.isEmpty else {
    if let v = versionString {
      throw ValidationError("No builds found for version \(v). Upload a build first via Xcode or Transporter.")
    }
    throw ValidationError("No builds found for this app. Upload a build first via Xcode or Transporter.")
  }
  
  print("Builds for version \(versionString ?? "all"):")
  for (i, build) in builds.enumerated() {
    let number = build.number ?? "—"
    let state = build.processingState.map { formatState($0) } ?? "—"
    let uploaded = build.uploadedDate.map { formatDate($0) } ?? "—"
    print("  [\(i + 1)] \(number)  \(state)  \(uploaded)")
  }
  print()
  
  let selected: Builds.Build
  if autoConfirm {
    selected = builds[0]
    let number = selected.number ?? "—"
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
  try await Builds.attach(buildID: selected.id, toVersion: versionID, client: client)
  
  return selected
}

