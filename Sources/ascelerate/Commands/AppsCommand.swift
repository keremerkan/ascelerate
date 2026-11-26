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
      CommandGroup(name: "Configuration", subcommands: [AccessibilityCommand.self, TagsCommand.self, Availability.self, PricingCommand.self, Encryption.self, EULACommand.self, SubscriptionGracePeriod.self, StreamlinedPurchasing.self, GroupPurchaseInvitations.self]),
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
              completion: appAliasCompletion)
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
      /// Per platform: the version not yet live (being prepared, in or back from review, or
      /// pending release), else the live one (Kerem, 2026-11-26).
      let latestVersions: [Version]
      /// The first of `latestVersions`, kept for programs reading the earlier single field.
      var latestVersion: Version? { latestVersions.first }

      private enum CodingKeys: String, CodingKey { case id, name, bundleID, sku, primaryLocale, latestVersion, latestVersions }

      func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(bundleID, forKey: .bundleID)
        try c.encodeIfPresent(sku, forKey: .sku)
        try c.encodeIfPresent(primaryLocale, forKey: .primaryLocale)
        try c.encodeIfPresent(latestVersion, forKey: .latestVersion)
        try c.encode(latestVersions, forKey: .latestVersions)
      }
    }

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let versions = try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.appsAppStoreVersionsGetToManyRelated(path: .init(id: app.id), query: .init(limit: 200)).ok.body.json
      }.flatMap(\.data).sorted { ($0.attributes?.createdDate ?? .distantPast) > ($1.attributes?.createdDate ?? .distantPast) }
      let notLive: Swift.Set<String> = AscelerateCore.Preflight.submittableStates.union([
        "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE", "ACCEPTED",
        "PROCESSING_FOR_DISTRIBUTION", "WAITING_FOR_EXPORT_COMPLIANCE",
      ])
      let platforms = Array(Swift.Set(versions.compactMap { $0.attributes?.platform })).sorted()
      let latest = platforms.compactMap { platform -> Components.Schemas.AppStoreVersion? in
        let own = versions.filter { $0.attributes?.platform == platform }
        return own.first { notLive.contains($0.attributes?.appVersionState ?? "") }
          ?? own.first { $0.attributes?.appVersionState == "READY_FOR_DISTRIBUTION" }
      }
      let attrs = app.attributes
      let detail = Detail(
        id: app.id,
        name: attrs?.name,
        bundleID: attrs?.bundleId,
        sku: attrs?.sku,
        primaryLocale: attrs?.primaryLocale,
        latestVersions: latest.map { latest in
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

      for v in detail.latestVersions {
        print("")
        print("Latest Version:  \(v.version ?? "—") (\(v.platform.map { formatState($0) } ?? "—"))")
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
              completion: appAliasCompletion)
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

      // Every version (it used to be the first page only).
      let versions = try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.appsAppStoreVersionsGetToManyRelated(path: .init(id: app.id), query: .init(limit: 200)).ok.body.json
      }.flatMap(\.data)

      let entries = versions.map { version -> Entry in
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
    
    /// A URL the core would drop (one that doesn't parse, or an empty one) is refused, rather than
    /// sending nothing and reporting "Updated".
    static func checkURLs(_ fields: LocaleFields, locale: String?) throws {
      for (name, value) in [("marketing URL", fields.marketingURL), ("support URL", fields.supportURL)] {
        guard let value, validURL(value) == nil else { continue }
        throw ValidationError("The \(name)\(locale.map { " for \($0)" } ?? "") '\(value)' isn't a URL; nothing was sent.")
      }
    }

    static func checkEditable(_ version: Components.Schemas.AppStoreVersion, promotionalTextOnly: Bool) throws {
      guard let state = version.attributes?.appVersionState, !VersionLocalizations.editableStates.contains(state) else {
        return // editable — all fields allowed
      }
      if promotionalTextOnly {
        return // promotional text can be updated in any state
      }
      throw ValidationError("Version is in state '\(state)' — only promotional text can be updated. The other fields change while a version is being prepared, waits for review, or is back from review (rejected or taken back).")
    }
    
    // MARK: - View
    
    struct View: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "List localizations for an App Store version."
      )
      
      @Argument(help: "The bundle identifier of the app.",
                completion: appAliasCompletion)
      var bundleID: String
      
      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the version that can be edited (asked when several platforms have one), else the latest.")
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
                completion: appAliasCompletion)
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

      @Option(name: .long, help: "Version string (default: the version being prepared). Promotional text can change on a live version too.")
      var version: String?
      
      func run() async throws {
        try Localizations.checkURLs(LocaleFields(marketingURL: marketingURL, supportURL: supportURL), locale: nil)
        guard description != nil || whatsNew != nil || keywords != nil
                || promotionalText != nil || marketingURL != nil || supportURL != nil else {
          throw ValidationError("Provide at least one field to update (--description, --whats-new, --keywords, --promotional-text, --marketing-url, --support-url).")
        }
        
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let version = try await findVersion(appID: app.id, versionString: self.version, platform: try platformOption.parsed(), client: client)
        
        let onlyPromoText = promotionalText != nil && description == nil && whatsNew == nil
        && keywords == nil && marketingURL == nil && supportURL == nil
        try Localizations.checkEditable(version, promotionalTextOnly: onlyPromoText)
        
        // Find the localization: the one named, or the app's primary language's.
        guard let wantedLocale = locale ?? app.attributes?.primaryLocale else {
          throw ValidationError("Couldn't read the app's primary language; name the language with --locale.")
        }
        // All of the version's languages, matched without case ('en-us' is Apple's 'en-US').
        let locsResponse = try await client.appStoreVersionsAppStoreVersionLocalizationsGetToManyRelated(
          path: .init(id: version.id), query: .init(limit: 200)
        ).ok.body.json
        guard let localization = locsResponse.data.first(where: { $0.attributes?.locale?.lowercased() == wantedLocale.lowercased() }) else {
          let known = locsResponse.data.compactMap(\.attributes?.locale).sorted().joined(separator: ", ")
          throw ValidationError("No localization found for locale '\(wantedLocale)'. The version has: \(known).")
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
                completion: appAliasCompletion)
      var bundleID: String

      @Option(name: .long, help: "Path to the JSON file with localization data.",
              completion: .file(extensions: ["json"]))
      var file: String?

      @OptionGroup var platformOption: PlatformOption
      
      @Flag(name: .long, help: "Show full API response for each locale update.")
      var verbose = false

      @Option(name: .long, help: "Version string (default: the version being prepared). Promotional text can change on a live version too.")
      var version: String?
      
      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false
      
      func run() async throws {
        if yes { autoConfirm = true }
        let expandedPath = try resolveFile(file, extension: "json", prompt: "Select localizations JSON file")

        // Parse JSON
        let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
        // The core's reader and wording (Kerem, 2026-11-26), shared with the app.
        let localeUpdates: [String: LocaleFields]
        do {
          localeUpdates = try LocalizationFile.decode(data, as: LocaleFields.self)
        } catch let error as LocalizationFile.FileError {
          throw ValidationError(error.localizedDescription)
        }
        for (locale, fields) in localeUpdates { try Localizations.checkURLs(fields, locale: locale) }
        
        // Show summary and confirm
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let version = try await findVersion(appID: app.id, versionString: self.version, platform: try platformOption.parsed(), client: client)
        
        let effectiveUpdates = try resolveEffectiveUpdates(
          version: version, localeUpdates: localeUpdates)
        // Lengths are checked before the summary and the confirmation: nothing goes out then.
        if let tooLong = FieldsOverLimit(effectiveUpdates.mapValues(\.overLimit)) { throw tooLong }

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
        var done = 0
        for (locale, fields) in updates.sorted(by: { $0.key < $1.key }) {
          do {
            try await sendLocale(locale, fields, versionID: versionID, existing: locByLocale[locale], client: client)
            done += 1
          } catch where ASCDryRunStop.from(error) == nil {
            // The language that failed is named, and what was sent before it.
            throw ValidationError("[\(localeName(locale))] \(describeError(error)) (\(done) language\(done == 1 ? "" : "s") updated before it; the rest weren't sent).")
          }
        }
      }

      private func sendLocale(
        _ locale: String, _ fields: LocaleFields, versionID: String,
        existing localization: Components.Schemas.AppStoreVersionLocalization?, client: ASCClient
      ) async throws {
        guard let localization else {
          guard confirm("  [\(localeName(locale))] Locale not found in current localizations for the app. Create it? [y/N] ") else {
            print("  [\(localeName(locale))] Skipped.")
            return
          }
          let created = try await VersionLocalizations.create(
            versionID: versionID, locale: locale, fields: fields, client: client)
          print("  [\(localeName(locale))] \(green("Created."))")
          if verbose { printLocaleResponse(created.attributes) }
          return
        }

        let updated = try await VersionLocalizations.update(
          localizationID: localization.id, fields: fields, client: client)
        print("  [\(localeName(locale))] Updated.")
        if verbose { printLocaleResponse(updated.attributes) }
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
                completion: appAliasCompletion)
      var bundleID: String
      
      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the version that can be edited (asked when several platforms have one), else the latest.")
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
          try confirmOutputPath(output ?? "\(bundleID)-localizations.json", isDirectory: false))
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
              completion: appAliasCompletion)
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
              completion: appAliasCompletion)
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

      // In any state, as promotional text: App Store Connect takes a copyright change on a live version too.
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
                completion: appAliasCompletion)
      var bundleID: String
      
      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the version that can be edited (asked when several platforms have one), else the latest.")
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
                completion: appAliasCompletion)
      var bundleID: String
      
      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the version that can be edited (asked when several platforms have one), else the latest.")
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
        if let uploaded = lastUploadedBuild(for: versionPlatform(appVersion), bundleID: app.attributes?.bundleId) {
          let pendingBuild = uploaded.number
          print("Waiting for uploaded build \(pendingBuild) to become available...")
          print()
          let awaitedBuild = try await awaitBuildProcessing(
            appID: app.id,
            buildVersion: pendingBuild,
            platform: versionPlatform(appVersion),
            version: uploaded.version,
            client: client
          )
          let uploadedOn = awaitedBuild.uploadedDate.map { formatDate($0) } ?? "—"
          print()
          print("Version: \(versionString)")
          print("Build:   \(pendingBuild)  VALID  \(uploadedOn)")
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
                completion: appAliasCompletion)
      var bundleID: String
      
      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the version that can be edited (asked when several platforms have one), else the latest.")
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
              completion: appAliasCompletion)
    var bundleID: String
    
    @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the version that can be edited (asked when several platforms have one), else the latest.")
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
    
    /// The live version (of the platform, if given) whose phased release is active or paused; the
    /// one to choose when several platforms roll out at once; nil when none is rolling out.
    private func rollingOutVersion(appID: String, platform: Platform?, client: ASCClient) async throws -> Components.Schemas.AppStoreVersion? {
      let live = try await client.appsAppStoreVersionsGetToManyRelated(
        path: .init(id: appID),
        query: .init(filterPlatform: platformFilter(platform), filterAppVersionState: [.readyForDistribution], limit: 50)
      ).ok.body.json.data
      var rolling: [Components.Schemas.AppStoreVersion] = []
      for candidate in live {
        if let state = try await Releases.phasedRelease(versionID: candidate.id, client: client)?.state, ["ACTIVE", "PAUSED"].contains(state) {
          rolling.append(candidate)
        }
      }
      guard rolling.count > 1 else { return rolling.first }
      return try promptSelection(
        "Versions rolling out", items: rolling,
        display: { "\(formatState($0.attributes?.platform ?? "")) \($0.attributes?.versionString ?? "?")" },
        prompt: "Select version", nonInteractiveHint: "Pass --platform or --version to choose.")
    }

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
      let platform = try platformOption.parsed()
      // Pausing, resuming, completing and viewing act on the rollout: the live version whose
      // phased release is active or paused, not the version being prepared.
      var rolling: Components.Schemas.AppStoreVersion?
      if version == nil && !enable && !disable {
        rolling = try await rollingOutVersion(appID: app.id, platform: platform, client: client)
      }
      let appVersion: Components.Schemas.AppStoreVersion
      if let rolling {
        appVersion = rolling
      } else if version == nil && (pause || resume || complete) {
        throw ValidationError("No version is rolling out a phased release; name one with --version.")
      } else {
        appVersion = try await findVersion(appID: app.id, versionString: version, platform: platform, client: client)
      }
      
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
              completion: appAliasCompletion)
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
              completion: appAliasCompletion)
    var bundleID: String
    
    @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the version that can be edited (asked when several platforms have one), else the latest.")
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
      // Checked before the current file is deleted: a GeoJSON object App Store Connect can read.
      guard fileSize > 0,
        let json = try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: expandedPath))) as? [String: Any],
        json["type"] is String
      else {
        throw ValidationError("'\(fileName)' isn't a GeoJSON file (a JSON object with a \"type\").")
      }
      
      // Check for existing coverage
      var removed: String?
      if let existingCoverage = try await AscelerateCore.RoutingCoverage.coverage(versionID: appVersion.id, client: client) {
        let existingName = existingCoverage.fileName ?? "unknown"
        print("Existing routing coverage: \(existingName)")
        guard confirm("Replace existing routing coverage with '\(fileName)'? [y/N] ") else {
          cancelled()
          return
        }
        guard try await unlessDryRunStopped({
          try await AscelerateCore.RoutingCoverage.delete(id: existingCoverage.id, client: client)
        }) != nil else { return }
        success("Deleted", "existing coverage.")
        removed = existingName
        print()
      }
      
      print("Uploading \(fileName) (\(formatBytes(fileSize)))...")
      fflush(stdout)
      
      do {
        try await AscelerateCore.RoutingCoverage.upload(
          MediaFile(path: expandedPath, fileName: fileName, fileSize: fileSize), versionID: appVersion.id, client: client)
      } catch {
        if let removed {
          try? FileHandle.standardError.write(contentsOf: Data("The previous routing coverage (\(removed)) was removed; upload it again to put it back.\n".utf8))
        }
        throw error
      }
      
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
                completion: appAliasCompletion)
      var bundleID: String

      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the version that can be edited (asked when several platforms have one), else the latest.")
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
        // The API has no App Privacy endpoints, and a submission without published answers is refused.
        print("Not checked: App Privacy. Its answers must be published in App Store Connect: https://appstoreconnect.apple.com/apps/\(app.id)/distribution/privacy")

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
          case .ageRating:
            (name, detail) = ("Age rating", check.passed ? "Answered" : "\(report.unansweredAgeRatingQuestions) question\(report.unansweredAgeRatingQuestions == 1 ? "" : "s") unanswered")
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

      /// A product taken off sale is listed as skipped (neither its state nor its prices are
      /// checked); see `Preflight.productState`.
      private static func productCheck(group: String, name: String, state: String?, hasPrices: Bool, missingPrices: String) -> Check {
        let stateStr = state.map { formatState($0) } ?? "unknown"
        let verdict = AscelerateCore.Preflight.productState(state)
        if verdict == .skipped {
          return Check(group: group, name: name, passed: true, detail: "\(stateStr) (skipped)", skipped: true)
        }
        return Check(group: group, name: name, passed: hasPrices && verdict == .submittable, detail: hasPrices ? stateStr : missingPrices)
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
                completion: appAliasCompletion)
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
        abstract: "Submit an App Store version for review.",
        discussion: """
          Checks first and writes after the confirmation: the version must be one App Review takes
          (being prepared, or back from review), and a submission of its platform already in review
          is never touched. A draft submission that holds the version, or the platform's open draft,
          is used, and its other items are listed before you confirm: they go to App Review too.
          Without a build attached, you pick one (with --yes, attach one first with 'apps build
          attach-latest'). In-app purchases, subscriptions and Game Center items with changes
          waiting for review are offered to go with it.
          """
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: appAliasCompletion)
      var bundleID: String

      @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the version being prepared.")
      var version: String?

      @Option(name: .long, help: "Platform: ios, macos, tvos, visionos (default: the version's; asked when several are being prepared).")
      var platform: String?

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      /// The active submission this run uses, from reads only.
      private enum Plan {
        /// The version is in a submission App Review has already.
        case submitted(state: String)
        /// A draft (or one with unresolved issues) to use; `holdsVersion` says whether the version
        /// is in it yet. `others` are its other items.
        case reuse(id: String, state: String, holdsVersion: Bool, others: [ReviewSubmissions.Item])
        /// No active submission on the platform: a new one is made.
        case new
      }

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appVersion = try await findVersion(
          appID: app.id, versionString: version, platform: try platform.map(parsePlatform), client: client)

        let versionString = appVersion.attributes?.versionString ?? "unknown"
        let rawState = appVersion.attributes?.appVersionState ?? ""
        guard let platformValue = appVersion.attributes?.platform.flatMap(Platform.init(rawValue:)) else {
          throw ValidationError("Couldn't read version \(versionString)'s platform.")
        }
        // Before anything is written: App Review takes a version only from these states.
        guard AscelerateCore.Preflight.submittableStates.contains(rawState) else {
          throw ValidationError(
            "Version \(versionString) (\(formatState(platformValue.rawValue))) is \(formatState(rawState)); only a version being prepared or back from review can be submitted.")
        }

        let plan = try await submissionPlan(app: app, appVersion: appVersion, platform: platformValue, client: client)
        if case .submitted(let state) = plan {
          print("Version \(versionString) is already submitted for review (state: \(formatState(state))).")
          return
        }

        // A build: the one attached, or one picked now (never under --yes).
        let attached = try await attachedBuild(versionID: appVersion.id, client: client)
        let build: String
        if let attached, let number = attached.attributes?.version {
          build = "\(number) (uploaded \(attached.attributes?.uploadedDate.map { formatDate($0) } ?? "—"))"
        } else {
          print("No build attached to version \(versionString). Select a build first:")
          print()
          let selected = try await selectBuild(
            appID: app.id, versionID: appVersion.id, versionString: versionString, platform: platformValue, client: client)
          build = "\(selected.number ?? "unknown") (just attached)"
          print()
        }

        print("App:      \(app.attributes?.name ?? bundleID)")
        print("Version:  \(versionString)")
        print("Build:    \(build)")
        print("State:    \(formatState(rawState))")
        print("Platform: \(formatState(platformValue.rawValue))")
        let resubmit: Bool
        switch plan {
          case .reuse(let id, let state, _, let others):
            resubmit = state == "UNRESOLVED_ISSUES"
            print("Submission: the open \(state == "UNRESOLVED_ISSUES" ? "submission with unresolved issues" : "draft") (\(id))")
            if !others.isEmpty {
              print("  It also holds, which goes to App Review with it:")
              for item in others {
                print("    \(formatFieldName(item.kind)): \(item.name ?? "—")\(item.state.map { " (\(formatState($0)))" } ?? "")")
              }
            }
          default:
            resubmit = false
        }
        print()
        guard confirm(resubmit ? "Resubmit for review? [y/N] " : "Submit this version for App Review? [y/N] ") else {
          cancelled()
          return
        }
        print()

        // The writes.
        let submissionID: String
        switch plan {
          case .reuse(let id, _, let holdsVersion, _):
            submissionID = id
            if !holdsVersion {
              try await addVersion(appVersion, versionString: versionString, to: id, client: client)
            }
          default:
            submissionID = try await ReviewSubmissions.create(appID: app.id, platform: platformValue.rawValue, client: client)
            print("Created review submission (\(submissionID))")
            try await addVersion(appVersion, versionString: versionString, to: submissionID, client: client)
        }

        try await addBundledProducts(app: app, submissionID: submissionID, platform: platformValue.rawValue, client: client)
        try await addPendingGameCenterItems(
          app: app, versionID: appVersion.id, submissionID: submissionID, platform: platformValue.rawValue, client: client)

        let state = try await ReviewSubmissions.submit(id: submissionID, client: client).map { formatState($0) } ?? "unknown"
        print()
        success("Submitted for review.")
        print("  State: \(state)")
      }

      /// Which active submission of the platform this version goes in. The one that holds it is
      /// its: already with App Review (waiting or in review), or a draft to submit. Otherwise the
      /// platform's open draft (or one with unresolved issues) takes it. A platform has one active
      /// submission, so one App Review already has, without this version, is refused.
      private func submissionPlan(
        app: Components.Schemas.App, appVersion: Components.Schemas.AppStoreVersion, platform: Platform, client: ASCClient
      ) async throws -> Plan {
        let active = try await client.appsReviewSubmissionsGetToManyRelated(
          path: .init(id: app.id),
          query: .init(filterState: [.readyForReview, .waitingForReview, .inReview, .unresolvedIssues])
        ).ok.body.json.data.filter { $0.attributes?.platform == platform.rawValue }
        var reusable: (id: String, state: String, others: [ReviewSubmissions.Item])?
        for submission in active {
          let state = submission.attributes?.state ?? ""
          // Matched by the version's ID (a version string can repeat across platforms).
          // No builds read: the plan names none.
          let items = try await ReviewSubmissions.items(submissionID: submission.id, builds: false, client: client)
          let holds = items.contains { $0.appStoreVersionID == appVersion.id }
          let others = items.filter { $0.appStoreVersionID != appVersion.id }
          switch state {
            case "WAITING_FOR_REVIEW", "IN_REVIEW":
              if holds { return .submitted(state: state) }
              let list = items.map { "\(formatFieldName($0.kind)): \($0.name ?? "—")" }.joined(separator: ", ")
              throw ValidationError(
                "The \(formatState(platform.rawValue)) submission \(submission.id) is \(formatState(state)) without this version (\(list.isEmpty ? "no items" : list)). Wait for it or cancel it ('apps review cancel-submission') first.")
            case "READY_FOR_REVIEW", "UNRESOLVED_ISSUES":
              if holds { return .reuse(id: submission.id, state: state, holdsVersion: true, others: others) }
              if reusable == nil { reusable = (submission.id, state, others) }
            default:
              continue
          }
        }
        if let reusable { return .reuse(id: reusable.id, state: reusable.state, holdsVersion: false, others: reusable.others) }
        return .new
      }

      /// Adds the version to a review submission. App Store Connect checks the version here: a
      /// 409 "not in valid state" lists what's missing in its associated errors, which the error
      /// output prints.
      private func addVersion(
        _ appVersion: Components.Schemas.AppStoreVersion, versionString: String, to submissionID: String, client: ASCClient
      ) async throws {
        try await ReviewSubmissions.addItem(.appStoreVersion(appVersion.id), to: submissionID, client: client)
        print("Added version \(versionString) to submission")
      }

      /// Offers the in-app purchases, subscriptions and groups with a version waiting for review
      /// (`ReviewProducts.pending`) to go in the same submission, and adds the ready ones that aren't
      /// in a draft yet (`addReady`, groups before their subscriptions). A product App Store Connect
      /// refuses is reported and the rest still go.
      private func addBundledProducts(app: Components.Schemas.App, submissionID: String, platform: String, client: ASCClient) async throws {
        let products = try await ReviewProducts.pending(appID: app.id, client: client)
        guard !products.isEmpty else { return }
        func label(_ product: ReviewProducts.Product) -> String {
          let kind = product.kind == .inAppPurchase ? "IAP" : product.kind == .subscription ? "Sub" : "Group"
          return "\(kind): \(product.name)\(product.productID.map { " (\($0))" } ?? "") — \(product.pending.label)"
        }
        let notReady = products.filter { !$0.isReady }
        let inDraft = products.filter { $0.isReady && $0.isInDraft }
        let ready = products.filter { $0.isReady && !$0.isInDraft }
        if !notReady.isEmpty {
          print()
          print("Not ready for review (skipped):")
          for product in notReady { print("  \(label(product))\(product.state.map { ", \(formatState($0))" } ?? "")") }
        }
        if !inDraft.isEmpty {
          print()
          print("Already in a draft submission:")
          for product in inDraft { print("  \(label(product))") }
        }
        guard !ready.isEmpty else { return }
        print()
        print(yellow("In-app purchases and subscriptions with changes waiting for review:"))
        for product in ready { print("  \(label(product))") }
        print()
        guard confirm("Add these to the submission? [y/N] ") else { return }
        let (added, refused) = try await ReviewProducts.addReady(
          products, appID: app.id, platform: platform, draftID: submissionID, client: client)
        for product in added { print("  \(green("Added")) \(label(product))") }
        for refusal in refused { print("  \(yellow("Refused")) \(label(refusal.product)): \(refusal.reason)") }
      }

      /// Offers to add the Game Center items with a version waiting for review (achievements,
      /// leaderboards, sets, activities, challenges) to the submission; they're reviewed with the
      /// app version. Items already in it are left alone.
      private func addPendingGameCenterItems(
        app: Components.Schemas.App, versionID: String, submissionID: String, platform: String, client: ASCClient
      ) async throws {
        guard let detail = try await GameCenter.detail(appID: app.id, client: client) else { return }
        // A version already in a draft reads READY_FOR_REVIEW, so these aren't in one yet.
        let pending = try await GameCenter.pendingItems(owner: detail.owner, client: client)
        guard !pending.isEmpty else { return }
        print()
        print(yellow("Game Center items with changes waiting for review:"))
        for item in pending {
          print("  \(item.noun.prefix(1).uppercased() + item.noun.dropFirst()): \(item.name) (version \(item.version.version ?? 0), \(formatState(item.version.state ?? "-")))")
        }
        if try await GameCenter.isEnabled(versionID: versionID, client: client) != true {
          print(yellow("Game Center is off on this version;") + " turn it on so they can be reviewed: ascelerate game-center version \(bundleID) --enabled true")
        }
        print()
        guard confirm("Add them to the submission? [y/N] ") else { return }
        for item in pending {
          do {
            try await ReviewSubmissions.add(item.reviewItem, appID: app.id, platform: platform, draftID: submissionID, client: client)
            if !ClientFactory.isDryRun { print("  \(green("Added")) \(item.noun) '\(item.name)'") }
          } catch let error where ASCError.from(error)?.statusCode == 409 {
            // One item Apple refuses (a missing language, say) shouldn't stop the submission.
            print("  \(yellow("Skipped")) \(item.noun) '\(item.name)': \(describeError(error))")
          }
        }
      }

      // Safety net in case the version-state mapping in ProductVersions over-reports —
      // treat the API's "no pending version" 409 as a per-item skip, not a hard failure.
    }

    // MARK: - Resolve Issues
    
    struct ResolveIssues: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Mark rejected review items as resolved."
      )
      
      @Argument(help: "The bundle identifier of the app.",
                completion: appAliasCompletion)
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
          try await ReviewSubmissions.resolveItem(id: item.id, client: client)
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
                completion: appAliasCompletion)
      var bundleID: String

      @OptionGroup var platformOption: PlatformOption

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)

        // Only what can be cancelled (Kerem, 2026-11-26): a draft (Ready for Review) can't be
        // through the API, so it isn't offered.
        let response = try await client.appsReviewSubmissionsGetToManyRelated(
          path: .init(id: app.id),
          query: .init(
            filterState: [.waitingForReview, .inReview, .unresolvedIssues],
            fieldsAppStoreVersions: [.versionString],
            include: [.appStoreVersionForReview])
        ).ok.body.json

        guard let (submission, versionString) = try selectSubmission(
          from: response, platform: platformOption.parsed())
        else {
          let platform = try platformOption.parsed()?.rawValue
          let drafts = try await client.appsReviewSubmissionsGetToManyRelated(
            path: .init(id: app.id), query: .init(filterState: [.readyForReview])
          ).ok.body.json.data.filter { platform == nil || $0.attributes?.platform == platform }
          print("No review submission that can be cancelled (waiting for review, in review or with unresolved issues).")
          if !drafts.isEmpty {
            print("\(drafts.count == 1 ? "A draft submission is" : "\(drafts.count) draft submissions are") open; the API can't cancel a draft (App Store Connect can empty one).")
          }
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
        
        let newState = try await ReviewSubmissions.cancel(id: submission.id, client: client).map { formatState($0) } ?? "unknown"
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
                completion: appAliasCompletion)
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

        let wanted = ReviewInformation(
          contactFirstName: contactFirstName, contactLastName: contactLastName, contactPhone: contactPhone,
          contactEmail: contactEmail, demoAccountRequired: demoAccountRequired, demoAccountName: demoAccountName,
          demoAccountPassword: demoAccountPassword, notes: notes)
        printChanges("App Review Information for version \(versionString):", reviewInformationChanges(from: existing?.information, to: wanted))
        guard confirm("Update App Review Information for version \(versionString)? [y/N] ") else {
          cancelled()
          return
        }

        try await ReviewInformation.saveAppStore(
          wanted,
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
                  completion: appAliasCompletion)
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
                  completion: appAliasCompletion)
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
                completion: appAliasCompletion)
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
        
        let appInfo: Components.Schemas.AppInfo
        let localizations: [Components.Schemas.AppInfoLocalization]
        do {
          (appInfo, localizations) = try await AppInfos.activeWithLocalizations(appID: app.id, client: client)
        } catch let error as AppInfos.AppInfoError {
          throw ValidationError(error.localizedDescription)
        }
        
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
                completion: appAliasCompletion)
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
        
        // The language named, or the app's primary one.
        let wantedLocale = locale ?? app.attributes?.primaryLocale
        if hasLocalizationFields && wantedLocale == nil {
          throw ValidationError("Couldn't read the app's primary language; name the language with --locale.")
        }

        let appName = app.attributes?.name ?? bundleID
        print("App:   \(appName)")
        print("State: \(appInfo.attributes?.state.map { formatState($0) } ?? "—")")
        print()
        
        if hasLocalizationFields, let wantedLocale {
          print("Localization [\(localeName(wantedLocale))\(locale == nil ? ", the primary language" : "")]:")
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
          // All of the app info's languages, matched without case ('en-us' is Apple's 'en-US').
          let locsResponse = try await client.appInfosAppInfoLocalizationsGetToManyRelated(
            path: .init(id: appInfo.id), query: .init(limit: 200)
          ).ok.body.json
          guard let localization = locsResponse.data.first(where: {
            $0.attributes?.locale?.lowercased() == wantedLocale?.lowercased()
          }) else {
            let known = locsResponse.data.compactMap(\.attributes?.locale).sorted().joined(separator: ", ")
            throw ValidationError("No localization found for locale '\(wantedLocale ?? "?")'. The app info has: \(known).")
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
                completion: appAliasCompletion)
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
        // The core's reader and wording (Kerem, 2026-11-26), shared with the app.
        let localeUpdates: [String: AppInfoLocaleFields]
        do {
          localeUpdates = try LocalizationFile.decode(data, as: AppInfoLocaleFields.self)
        } catch let error as LocalizationFile.FileError {
          throw ValidationError(error.localizedDescription)
        }
        if let tooLong = FieldsOverLimit(localeUpdates.mapValues(\.overLimit)) { throw tooLong }

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
        
        // Send updates; a failure names its language and how many went before it.
        let ordered = localeUpdates.sorted(by: { $0.key < $1.key })
        var current = 0
        do {
          for (index, (locale, fields)) in ordered.enumerated() {
            current = index
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
        } catch where ASCDryRunStop.from(error) == nil {
          throw ValidationError("[\(localeName(ordered[current].key))] \(describeError(error)) (\(current) language\(current == 1 ? "" : "s") sent before it; the rest weren't sent).")
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
                completion: appAliasCompletion)
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
          try confirmOutputPath(output ?? "\(bundleID)-app-infos.json", isDirectory: false))
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
                  completion: appAliasCompletion)
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
      
        // Intensity-based and yes-or-no ratings, from the core's one list of the questions.
        let intensityRows: [(String, String)] = AgeRatingFields.intensityQuestions.map { ($0.label, intensityLabel(attrs[keyPath: $0.key])) }
        let boolRows: [(String, String)] = AgeRatingFields.yesNoQuestions.map { ($0.label, boolLabel(attrs[keyPath: $0.key])) }
      
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
                  completion: appAliasCompletion)
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

          let outputPath = try confirmOutputPath(output ?? "age-rating.json", isDirectory: false)
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
                  completion: appAliasCompletion)
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
          // A key the file format doesn't have is refused (Kerem, 2026-11-26): it used to be
          // dropped, so a file with Apple's attribute names lost those answers.
          let known = Swift.Set(Mirror(reflecting: AgeRatingFields()).children.compactMap(\.label))
          if let given = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let unknown = given.keys.filter { !known.contains($0) }.sorted()
            if !unknown.isEmpty {
              let named = unknown.map { key -> String in
                let ours = key == "ageRatingOverrideV2" ? "ageRatingOverride" : "is" + key.prefix(1).uppercased() + key.dropFirst()
                return known.contains(ours) ? "'\(key)' (this file's name for it is '\(ours)')" : "'\(key)'"
              }
              throw ValidationError("Unknown key\(unknown.count == 1 ? "" : "s"): \(named.joined(separator: ", ")). Nothing was sent; 'age-rating export' writes the format.")
            }
          }

          print("App: \(appName)")
          print()
          print("Age rating updates:")
          var changeCount = 0
          for question in AgeRatingFields.intensityQuestions {
            if let v = fields[keyPath: question.key] { print("  \(question.label): \(v)"); changeCount += 1 }
          }
          for question in AgeRatingFields.yesNoQuestions {
            if let v = fields[keyPath: question.key] { print("  \(question.label): \(v)"); changeCount += 1 }
          }
          if let v = fields.kidsAgeBand { print("  Kids Age Band: \(v)"); changeCount += 1 }
          if let v = fields.ageRatingOverride { print("  Age Rating Override: \(v)"); changeCount += 1 }
          if let v = fields.koreaAgeRatingOverride { print("  Korea Age Rating Override: \(v)"); changeCount += 1 }
          if let v = fields.developerAgeRatingInfoUrl { print("  Developer Age Rating Info URL: \(v)"); changeCount += 1 }
          if let v = fields.gracRatingClassificationNumber { print("  GRAC Rating Classification Number: \(v)"); changeCount += 1 }

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
            datingAndRelationships: fields.isDatingAndRelationships,
            developerAgeRatingInfoUrl: fields.developerAgeRatingInfoUrl,
            gambling: fields.isGambling,
            gamblingSimulated: try value(fields.gamblingSimulated, "gamblingSimulated", E.AgeRatingDeclarationUpdateRequestGamblingSimulated.self),
            gracRatingClassificationNumber: fields.gracRatingClassificationNumber,
            gunsOrOtherWeapons: try value(fields.gunsOrOtherWeapons, "gunsOrOtherWeapons", E.AgeRatingDeclarationUpdateRequestGunsOrOtherWeapons.self),
            healthOrWellnessTopics: fields.isHealthOrWellnessTopics,
            horrorOrFearThemes: try value(fields.horrorOrFearThemes, "horrorOrFearThemes", E.AgeRatingDeclarationUpdateRequestHorrorOrFearThemes.self),
            kidsAgeBand: try value(fields.kidsAgeBand, "kidsAgeBand", E.KidsAgeBand.self),
            koreaAgeRatingOverride: try value(
              fields.koreaAgeRatingOverride, "koreaAgeRatingOverride", E.AgeRatingDeclarationUpdateRequestKoreaAgeRatingOverride.self),
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
            sharedLocation: fields.isSharedLocation,
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
              completion: appAliasCompletion)
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
          throw ExitCode.failure
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
      abstract: "View or create encryption declarations, and upload their documentation."
    )
    
    @Argument(help: "The bundle identifier of the app.",
              completion: appAliasCompletion)
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

    @Option(name: .long, help: "Upload this file as a declaration's documentation (export compliance paperwork).",
            completion: .file())
    var uploadDocument: String?

    @Option(name: .long, help: "The declaration to upload to, by ID. Defaults to the newest one.")
    var declaration: String?
    
    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false
    
    func validate() throws {
      if create && appDescription == nil {
        throw ValidationError("--description is required when using --create.")
      }
      if create && uploadDocument != nil {
        throw ValidationError("Create the declaration first, then upload its document.")
      }
      if declaration != nil && uploadDocument == nil {
        throw ValidationError("--declaration names where --upload-document goes.")
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
      
      if let uploadDocument {
        let path = expandPath(uploadDocument)
        let all = try await EncryptionDeclarations.list(appID: app.id, client: client)
        guard let target = declaration.map({ id in all.first { $0.id == id } }) ?? all.max(by: { ($0.createdDate ?? .distantPast) < ($1.createdDate ?? .distantPast) }) else {
          throw ValidationError(declaration.map { "No encryption declaration '\($0)' for \(appName)." } ?? "\(appName) has no encryption declaration; create one first.")
        }
        let existing = try await EncryptionDeclarations.document(declarationID: target.id, client: client)
        print("App: \(appName)")
        print("Declaration: \(target.id) (\(target.state.map { formatState($0) } ?? "—"), created \(target.createdDate.map(formatDate) ?? "—"))")
        // Whether Apple replaces it, keeps both or refuses the second hasn't been seen: said as such.
        if let existing { print("It has a document already: \(existing.fileName ?? existing.id). Uploading another adds the new one; whether App Store Connect then replaces the old one or refuses this one hasn't been checked.") }
        print("File: \((path as NSString).lastPathComponent)")
        guard confirm("Upload? [y/N] ") else {
          cancelled()
          return
        }
        _ = try await EncryptionDeclarations.uploadDocument(declarationID: target.id, filePath: path, client: client)
        success("Uploaded", "\((path as NSString).lastPathComponent).")
        return
      }

      // View mode
      print("App: \(appName)")
      print()
      
      let declarations = try await EncryptionDeclarations.list(appID: app.id, client: client)
      let documents = try await boundedConcurrentMap(declarations) { decl in
        try await EncryptionDeclarations.document(declarationID: decl.id, client: client)
      }
      let rows: [[String]] = zip(declarations, documents).map { decl, document in
        [
          decl.state.map { formatState($0) } ?? "—",
          decl.platform.map { formatState($0) } ?? "—",
          decl.containsProprietaryCryptography.map { $0 ? "Yes" : "No" } ?? "—",
          decl.containsThirdPartyCryptography.map { $0 ? "Yes" : "No" } ?? "—",
          decl.exempt.map { $0 ? "Yes" : "No" } ?? "—",
          decl.createdDate.map { formatDate($0) } ?? "—",
          document?.fileName ?? "—",
          decl.id,
        ]
      }
      
      if rows.isEmpty {
        print("No encryption declarations found.")
        return
      }
      
      Table.print(
        headers: ["State", "Platform", "Proprietary", "Third-Party", "Exempt", "Created", "Document", "ID"],
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
              completion: appAliasCompletion)
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
              completion: appAliasCompletion)
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
              completion: appAliasCompletion)
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


func describeDecodingError(_ error: DecodingError) -> String {
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
  try await findApp(exactBundleID: try resolveAlias(bundleID), client: client)
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
  version: String? = nil,
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
      appID: appID, number: buildVersion, platform: platform, version: version, interval: interval, timeout: timeout,
      client: client
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
      case .rejected: print(error.localizedDescription)
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
    // The newest build may be processing, expired or invalid: --yes doesn't pick one.
    throw ValidationError(
      "--yes doesn't pick a build. Attach the newest processed one with 'ascelerate apps build attach-latest', or pick one without --yes.")
  } else {
    guard let input = readAnswer("Select a build (1-\(builds.count)): ")?.trimmingCharacters(in: .whitespacesAndNewlines),
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

