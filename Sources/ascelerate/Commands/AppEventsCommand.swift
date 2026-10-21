import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

struct AppEventsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "events",
    abstract: "Manage in-app events.",
    subcommands: [List.self, Info.self, Create.self, Update.self, Delete.self, Localizations.self, Media.self]
  )

  // MARK: - Shared helpers

  /// Resolves a reference name or event ID to an event of the given app.
  static func findAppEvent(ref: String, appID: String, client: ASCClient) async throws -> AppEvents.Event {
    do {
      return try await AppEvents.find(ref, appID: appID, client: client)
    } catch let error as AppEvents.LookupError {
      throw ValidationError(error.localizedDescription)
    }
  }

  /// Parses an event schedule date — ISO8601 (`2026-07-01T09:00:00Z`) or `yyyy-MM-dd` (UTC midnight).
  static func parseEventDate(_ value: String, field: String) throws -> Date {
    if let d = ISO8601DateFormatter().date(from: value) { return d }
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "UTC")
    f.locale = Locale(identifier: "en_US_POSIX")
    if let d = f.date(from: value) { return d }
    throw ValidationError(
      "Invalid \(field) date '\(value)'. Use ISO8601 (2026-07-01T09:00:00Z) or yyyy-MM-dd.")
  }

  /// Parses the `--publish-start`/`--event-start`/`--event-end` options.
  static func scheduleDates(
    publishStart: String?, eventStart: String?, eventEnd: String?
  ) throws -> (publishStart: Date?, eventStart: Date?, eventEnd: Date?) {
    (
      try publishStart.map { try parseEventDate($0, field: "--publish-start") },
      try eventStart.map { try parseEventDate($0, field: "--event-start") },
      try eventEnd.map { try parseEventDate($0, field: "--event-end") }
    )
  }

  /// Validates a `--deep-link` value; a typo'd URL must throw, not silently drop the field.
  static func parseDeepLink(_ value: String?) throws -> String? {
    guard let value else { return nil }
    guard let url = URL(string: value), url.scheme != nil else {
      throw ValidationError("Invalid --deep-link URL: '\(value)'.")
    }
    return url.absoluteString
  }

  /// Splits a comma-separated territory list into uppercased codes.
  static func territoryList(_ value: String?) -> [String]? {
    value.map {
      $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
    }
  }

  // MARK: - List

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List in-app events for an app."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .long, help: "Filter by state (DRAFT, READY_FOR_REVIEW, IN_REVIEW, APPROVED, PUBLISHED, PAST, ARCHIVED, etc.).")
    var state: String?

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let stateFilter: [Operations.AppsAppEventsGetToManyRelated.Input.Query.FilterEventStatePayloadPayload]? =
        try parseFilter(state, name: "state")

      let events = try await AppEvents.list(appID: app.id, states: stateFilter?.map(\.rawValue), client: client)

      if events.isEmpty {
        print("No in-app events found.")
        return
      }

      var rows: [[String]] = []
      for event in events.sorted(by: { $0.referenceName < $1.referenceName }) {
        rows.append([
          event.referenceName,
          event.state.map { formatState($0) } ?? "—",
          event.badge.map { formatState($0) } ?? "—",
          event.priority.map { formatState($0) } ?? "—",
          event.id,
        ])
      }

      Table.print(
        headers: ["Reference Name", "State", "Badge", "Priority", "Event ID"],
        rows: rows
      )
    }
  }

  // MARK: - Info

  struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Show details for an in-app event, including schedules and localizations."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Argument(help: "The event reference name or ID.")
    var event: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appEvent = try await AppEventsCommand.findAppEvent(
        ref: event, appID: app.id, client: client)
      let a = appEvent

      print("Reference Name:       \(a.referenceName)")
      print("State:                \(a.state.map { formatState($0) } ?? "—")")
      print("Badge:                \(a.badge.map { formatState($0) } ?? "—")")
      print("Priority:             \(a.priority.map { formatState($0) } ?? "—")")
      print("Purpose:              \(a.purpose.map { formatState($0) } ?? "—")")
      print("Primary Locale:       \(a.primaryLocale.flatMap { $0.isEmpty ? nil : localeName($0) } ?? "—")")
      print("Deep Link:            \(a.deepLink ?? "—")")
      print("Purchase Requirement: \(a.purchaseRequirement ?? "—")")
      print("Event ID:             \(appEvent.id)")

      if !a.schedules.isEmpty {
        let schedules = a.schedules
        print()
        print("Territory Schedules:")
        for s in schedules {
          let terrs = s.territories?.joined(separator: ", ") ?? "all territories"
          print("  • \(terrs)")
          print("    Publish: \(s.publishStart.map { formatDate($0) } ?? "—")")
          print("    Event:   \(s.eventStart.map { formatDate($0) } ?? "—") → \(s.eventEnd.map { formatDate($0) } ?? "—")")
        }
      }

      let locs = try await AppEvents.localizations(eventID: appEvent.id, client: client)
      if !locs.isEmpty {
        print()
        print("Localizations (\(locs.count)):")
        for loc in locs.sorted(by: { $0.locale < $1.locale }) {
          print("  [\(localeName(loc.locale))] \(loc.name ?? "—")")
        }
      }
    }
  }

  // MARK: - Create

  struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Create an in-app event."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .long, help: "Internal reference name for the event (required).")
    var referenceName: String

    @Option(name: .long, help: "Badge: LIVE_EVENT, PREMIERE, CHALLENGE, COMPETITION, NEW_SEASON, MAJOR_UPDATE, SPECIAL_EVENT.")
    var badge: String?

    @Option(name: .long, help: "Priority: HIGH or NORMAL.")
    var priority: String?

    @Option(name: .long, help: "Purpose: APPROPRIATE_FOR_ALL_USERS, ATTRACT_NEW_USERS, KEEP_ACTIVE_USERS_INFORMED, BRING_BACK_LAPSED_USERS.")
    var purpose: String?

    @Option(name: .long, help: "Primary locale (e.g. en-US).")
    var primaryLocale: String?

    @Option(name: .long, help: "Deep link URL opened when the event card is tapped.")
    var deepLink: String?

    @Option(name: .long, help: "Purchase requirement description.")
    var purchaseRequirement: String?

    @Option(name: .long, help: "Comma-separated territory codes for the schedule (omit for all territories).")
    var territories: String?

    @Option(name: .long, help: "Schedule publish start (ISO8601 or yyyy-MM-dd).")
    var publishStart: String?

    @Option(name: .long, help: "Schedule event start (ISO8601 or yyyy-MM-dd).")
    var eventStart: String?

    @Option(name: .long, help: "Schedule event end (ISO8601 or yyyy-MM-dd).")
    var eventEnd: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let badgeValue: ASCEnum.AppEventCreateRequestBadge? =
        try badge.map { try parseEnum($0, name: "badge") }
      let priorityValue: ASCEnum.AppEventCreateRequestPriority? =
        try priority.map { try parseEnum($0, name: "priority") }
      let purposeValue: ASCEnum.AppEventCreateRequestPurpose? =
        try purpose.map { try parseEnum($0, name: "purpose") }

      var schedules: [AppEvents.Schedule]?
      if territories != nil || publishStart != nil || eventStart != nil || eventEnd != nil {
        let dates = try AppEventsCommand.scheduleDates(
          publishStart: publishStart, eventStart: eventStart, eventEnd: eventEnd)
        schedules = [
          AppEvents.Schedule(
            territories: AppEventsCommand.territoryList(territories), publishStart: dates.publishStart,
            eventStart: dates.eventStart, eventEnd: dates.eventEnd)
        ]
      }

      let deepLinkValue = try AppEventsCommand.parseDeepLink(deepLink)

      print("Create in-app event:")
      print("  Reference Name: \(referenceName)")
      if let badge { print("  Badge:          \(badge.uppercased())") }
      if let priority { print("  Priority:       \(priority.uppercased())") }
      if let purpose { print("  Purpose:        \(purpose.uppercased())") }
      print()

      guard confirm("Create this event? [y/N] ") else {
        cancelled()
        return
      }

      let created = try await AppEvents.create(
        appID: app.id, referenceName: referenceName, badge: badgeValue?.rawValue, deepLink: deepLinkValue,
        primaryLocale: primaryLocale, priority: priorityValue?.rawValue, purchaseRequirement: purchaseRequirement,
        purpose: purposeValue?.rawValue, schedules: schedules, client: client)

      print()
      success("Created", "in-app event '\(referenceName)' (id: \(created.id)).")
    }
  }

  // MARK: - Update

  struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Update an in-app event's attributes or schedule."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Argument(help: "The event reference name or ID.")
    var event: String

    @Option(name: .long, help: "New reference name.")
    var referenceName: String?

    @Option(name: .long, help: "Badge (see `events create`), or NONE to clear.")
    var badge: String?

    @Option(name: .long, help: "Priority: HIGH or NORMAL.")
    var priority: String?

    @Option(name: .long, help: "Purpose (see `events create`).")
    var purpose: String?

    @Option(name: .long, help: "Deep link URL.")
    var deepLink: String?

    @Option(name: .long, help: "Purchase requirement description.")
    var purchaseRequirement: String?

    @Option(name: .long, help: "Comma-separated territory codes for the schedule.")
    var territories: String?

    @Option(name: .long, help: "Schedule publish start (ISO8601 or yyyy-MM-dd).")
    var publishStart: String?

    @Option(name: .long, help: "Schedule event start (ISO8601 or yyyy-MM-dd).")
    var eventStart: String?

    @Option(name: .long, help: "Schedule event end (ISO8601 or yyyy-MM-dd).")
    var eventEnd: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      guard referenceName != nil || badge != nil || priority != nil || purpose != nil
        || deepLink != nil || purchaseRequirement != nil || territories != nil
        || publishStart != nil || eventStart != nil || eventEnd != nil
      else {
        throw ValidationError("Provide at least one field to update.")
      }

      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appEvent = try await AppEventsCommand.findAppEvent(
        ref: event, appID: app.id, client: client)

      let priorityValue: ASCEnum.AppEventUpdateRequestPriority? =
        try priority.map { try parseEnum($0, name: "priority") }
      let purposeValue: ASCEnum.AppEventUpdateRequestPurpose? =
        try purpose.map { try parseEnum($0, name: "purpose") }
      let clearBadge = badge?.uppercased() == "NONE"
      let badgeValue: ASCEnum.AppEventUpdateRequestBadge? =
        try badge.flatMap { $0.uppercased() == "NONE" ? nil : try parseEnum($0, name: "badge") }

      var schedules: [AppEvents.Schedule]?
      if territories != nil || publishStart != nil || eventStart != nil || eventEnd != nil {
        // The PATCH replaces the whole territorySchedules array — merge omitted
        // fields from the existing schedule instead of clearing them.
        let existing = appEvent.schedules.first
        if appEvent.schedules.count > 1 {
          print(yellow("⚠ This event has multiple territory schedules — the update replaces them with a single schedule."))
        }
        let dates = try AppEventsCommand.scheduleDates(
          publishStart: publishStart, eventStart: eventStart, eventEnd: eventEnd)
        schedules = [
          AppEvents.Schedule(
            territories: AppEventsCommand.territoryList(territories) ?? existing?.territories,
            publishStart: dates.publishStart ?? existing?.publishStart,
            eventStart: dates.eventStart ?? existing?.eventStart,
            eventEnd: dates.eventEnd ?? existing?.eventEnd)
        ]
      }

      let deepLinkValue = try AppEventsCommand.parseDeepLink(deepLink)

      guard confirm("Update event '\(appEvent.referenceName)'? [y/N] ") else {
        cancelled()
        return
      }

      try await AppEvents.update(
        id: appEvent.id, referenceName: referenceName,
        badge: clearBadge ? .some(nil) : badgeValue.map { .some($0.rawValue) }, deepLink: deepLinkValue.map { .some($0) },
        priority: priorityValue?.rawValue, purchaseRequirement: purchaseRequirement, purpose: purposeValue?.rawValue,
        schedules: schedules, client: client)

      print()
      success("Updated", "in-app event '\(appEvent.referenceName)'.")
    }
  }

  // MARK: - Delete

  struct Delete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Delete an in-app event."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Argument(help: "The event reference name or ID.")
    var event: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appEvent = try await AppEventsCommand.findAppEvent(
        ref: event, appID: app.id, client: client)
      let name = appEvent.referenceName

      print("In-app event: \(name) (\(appEvent.state.map { formatState($0) } ?? "—"))")
      print()
      guard confirm("Delete this event? [y/N] ") else {
        cancelled()
        return
      }

      try await AppEvents.delete(id: appEvent.id, state: appEvent.state, client: client)
      print()
      success("Deleted", "in-app event '\(name)'.")
    }
  }

  // MARK: - Localizations

  /// JSON schema for in-app event localizations.
  struct EventLocaleFields: Codable {
    var name: String?
    var shortDescription: String?
    var longDescription: String?
  }

  struct Localizations: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "localizations",
      abstract: "View, export, and import in-app event localizations.",
      subcommands: [View.self, Export.self, Import.self]
    )

    struct View: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "View localizations for an in-app event."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The event reference name or ID.")
      var event: String

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appEvent = try await AppEventsCommand.findAppEvent(
          ref: event, appID: app.id, client: client)

        let locs = try await AppEvents.localizations(eventID: appEvent.id, client: client)
        if locs.isEmpty {
          print("No localizations found.")
          return
        }

        print("Localizations for '\(appEvent.referenceName)':")
        print()
        for a in locs.sorted(by: { $0.locale < $1.locale }) {
          print("[\(localeName(a.locale))]")
          print("  Name:              \(a.name ?? "—")")
          print("  Short Description: \(a.shortDescription ?? "—")")
          if let long = a.longDescription, !long.isEmpty {
            print("  Long Description:  \(long.prefix(100))\(long.count > 100 ? "…" : "")")
          }
          print()
        }
      }
    }

    struct Export: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Export in-app event localizations to a JSON file."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The event reference name or ID.")
      var event: String

      @Option(name: .long, help: "Output file path.",
              completion: .file(extensions: ["json"]))
      var output: String?

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appEvent = try await AppEventsCommand.findAppEvent(
          ref: event, appID: app.id, client: client)

        var result: [String: EventLocaleFields] = [:]
        for loc in try await AppEvents.localizations(eventID: appEvent.id, client: client) {
          result[loc.locale] = EventLocaleFields(
            name: loc.name, shortDescription: loc.shortDescription, longDescription: loc.longDescription)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)

        let refName = appEvent.referenceName
        let outputPath = expandPath(
          confirmOutputPath(output ?? "\(refName)-localizations.json", isDirectory: false))
        try data.write(to: URL(fileURLWithPath: outputPath))

        print(green("Exported") + " \(result.count) locale(s) to \(outputPath)")
      }
    }

    struct Import: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Import in-app event localizations from a JSON file."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The event reference name or ID.")
      var event: String

      @Option(name: .long, help: "Path to JSON file.",
              completion: .file(extensions: ["json"]))
      var file: String?

      @Flag(name: .long, help: "Show detailed API responses.")
      var verbose: Bool = false

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes: Bool = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appEvent = try await AppEventsCommand.findAppEvent(
          ref: event, appID: app.id, client: client)

        let filePath = try resolveFile(file, extension: "json", prompt: "Select a JSON file")
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let localeUpdates = try JSONDecoder().decode([String: EventLocaleFields].self, from: data)

        guard !localeUpdates.isEmpty else {
          throw ValidationError("JSON file contains no locale data.")
        }

        print("Importing \(localeUpdates.count) locale(s) for '\(appEvent.referenceName)':")
        for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
          print("  [\(localeName(locale))] \(fields.name ?? "—")")
        }
        print()

        guard confirm("Send updates for \(localeUpdates.count) locale(s)? [y/N] ") else {
          cancelled()
          return
        }
        print()

        let byLocale = Dictionary(
          try await AppEvents.localizations(eventID: appEvent.id, client: client).map { ($0.locale, $0) },
          uniquingKeysWith: { first, _ in first })

        for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
          if let loc = byLocale[locale] {
            let response = try await AppEvents.updateLocalization(
              id: loc.id, name: fields.name, shortDescription: fields.shortDescription,
              longDescription: fields.longDescription, client: client)
            print("  [\(localeName(locale))] Updated.")
            if verbose { Self.printResponse(response) }
          } else {
            guard confirm("  [\(localeName(locale))] Locale not present. Create it? [y/N] ") else {
              print("  [\(localeName(locale))] Skipped.")
              continue
            }
            let response = try await AppEvents.createLocalization(
              eventID: appEvent.id, locale: locale, name: fields.name, shortDescription: fields.shortDescription,
              longDescription: fields.longDescription, client: client)
            print("  [\(localeName(locale))] \(green("Created."))")
            if verbose { Self.printResponse(response) }
          }
        }

        print()
        print("Done.")
      }

      private static func printResponse(_ attrs: AppEvents.Localization?) {
        print("    Response:")
        print("      Locale:            \(attrs.map { localeName($0.locale) } ?? "—")")
        if let v = attrs?.name { print("      Name:              \(v)") }
        if let v = attrs?.shortDescription { print("      Short Description: \(v)") }
        if let v = attrs?.longDescription {
          print("      Long Description:  \(v.prefix(120))\(v.count > 120 ? "…" : "")")
        }
      }
    }
  }

  // MARK: - Media

  struct Media: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "media",
      abstract: "Manage in-app event card screenshots and video clips.",
      subcommands: [List.self, Upload.self, Delete.self]
    )

    /// Resolves a locale to its localization ID on the event.
    static func localizationID(
      forLocale locale: String, eventID: String, client: ASCClient
    ) async throws -> String {
      let localizations = try await AppEvents.localizations(eventID: eventID, client: client)
      guard let loc = localizations.first(where: { $0.locale == locale }) else {
        throw ValidationError(
          "No '\(locale)' localization on this event. Create it first with 'events localizations import'.")
      }
      return loc.id
    }

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "List event card screenshots and video clips across localizations."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The event reference name or ID.")
      var event: String

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appEvent = try await AppEventsCommand.findAppEvent(
          ref: event, appID: app.id, client: client)

        var rows: [[String]] = []
        for loc in try await AppEvents.localizations(eventID: appEvent.id, client: client).sorted(by: { $0.locale < $1.locale }) {
          for media in try await AppEvents.media(localizationID: loc.id, client: client) {
            rows.append([
              loc.locale, media.isVideo ? "Video" : "Screenshot",
              media.assetType.map { formatState($0) } ?? "—",
              media.state.map { formatState($0) } ?? "—",
              media.id,
            ])
          }
        }

        if rows.isEmpty {
          print("No event media found.")
          return
        }
        Table.print(
          headers: ["Locale", "Type", "Asset Type", "State", "Media ID"], rows: rows)
      }
    }

    struct Upload: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Upload an event card screenshot (.png/.jpg) or video clip (.mp4/.mov)."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The event reference name or ID.")
      var event: String

      @Option(name: .long, help: "Locale of the localization to attach media to (e.g. en-US).")
      var locale: String

      @Option(name: .long, help: "Asset type: EVENT_CARD or EVENT_DETAILS_PAGE.")
      var assetType: String

      @Option(name: .long, help: "Preview frame timecode for video clips, hh:mm:ss:frame (e.g. 00:00:03:00).")
      var previewFrame: String?

      @Argument(help: "Path to the media file.",
                completion: .file(extensions: ["png", "jpg", "jpeg", "mp4", "mov"]))
      var file: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appEvent = try await AppEventsCommand.findAppEvent(
          ref: event, appID: app.id, client: client)
        let assetTypeValue: AppEvents.AssetType = try parseEnum(assetType, name: "asset-type")
        let locID = try await Media.localizationID(
          forLocale: locale, eventID: appEvent.id, client: client)

        let media = try MediaFile(readingFrom: file)
        let ext = (media.fileName as NSString).pathExtension.lowercased()
        let isImage = ["png", "jpg", "jpeg"].contains(ext)
        let isVideo = ["mp4", "mov"].contains(ext)
        guard isImage || isVideo else {
          throw ValidationError(
            "Unsupported file type '.\(ext)'. Use png/jpg for screenshots or mp4/mov for video clips.")
        }

        print("Upload \(isImage ? "screenshot" : "video clip"):")
        print("  Event:      \(appEvent.referenceName)")
        print("  Locale:     \(localeName(locale))")
        print("  Asset Type: \(assetType.uppercased())")
        print("  File:       \(media.fileName) (\(formatBytes(media.fileSize)))")
        print()
        guard confirm("Upload? [y/N] ") else {
          cancelled()
          return
        }

        let mediaID = isImage
          ? try await AppEvents.uploadImage(media, localizationID: locID, assetType: assetTypeValue, client: client)
          : try await AppEvents.uploadVideo(
            media, localizationID: locID, assetType: assetTypeValue, previewFrame: previewFrame, client: client)

        print()
        success("Uploaded", "\(isImage ? "screenshot" : "video clip") (id: \(mediaID)).")
      }
    }

    struct Delete: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Delete an event card screenshot or video clip."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The event reference name or ID.")
      var event: String

      @Argument(help: "The media ID (from `events media list`).")
      var mediaID: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let appEvent = try await AppEventsCommand.findAppEvent(
          ref: event, appID: app.id, client: client)

        // Locate the media across the event's localizations to pick the right endpoint.
        var found: AppEvents.Media?
        for loc in try await AppEvents.localizations(eventID: appEvent.id, client: client) {
          found = try await AppEvents.media(localizationID: loc.id, client: client).first { $0.id == mediaID }
          if found != nil { break }
        }

        guard let found else {
          throw ValidationError("Media '\(mediaID)' not found on this event.")
        }

        let kind = found.isVideo ? "video" : "screenshot"
        guard confirm("Delete this \(kind)? [y/N] ") else {
          cancelled()
          return
        }

        try await AppEvents.deleteMedia(found, client: client)
        print()
        success("Deleted", "\(kind) \(mediaID).")
      }
    }
  }
}
