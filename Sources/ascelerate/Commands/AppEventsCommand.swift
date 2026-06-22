import AppStoreAPI
import AppStoreConnect
import ArgumentParser
import Foundation

struct AppEventsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "events",
    abstract: "Manage in-app events.",
    subcommands: [List.self, Info.self, Create.self, Update.self, Delete.self, Localizations.self]
  )

  // MARK: - Shared helpers

  /// Resolves a reference name or event ID to an AppEvent for the given app.
  static func findAppEvent(
    ref: String, appID: String, client: AppStoreConnectClient
  ) async throws -> AppEvent {
    var events: [AppEvent] = []
    for try await page in client.pages(
      Resources.v1.apps.id(appID).appEvents.get(limit: 200)
    ) {
      events.append(contentsOf: page.data)
    }
    if let match = events.first(where: { $0.attributes?.referenceName == ref || $0.id == ref }) {
      return match
    }
    throw ValidationError("No in-app event '\(ref)' found for this app.")
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

      let stateFilter: [Resources.V1.Apps.WithID.AppEvents.FilterEventState]? =
        try parseFilter(state, name: "state")

      var events: [AppEvent] = []
      for try await page in client.pages(
        Resources.v1.apps.id(app.id).appEvents.get(filterEventState: stateFilter, limit: 200)
      ) {
        events.append(contentsOf: page.data)
      }

      if events.isEmpty {
        print("No in-app events found.")
        return
      }

      var rows: [[String]] = []
      for event in events.sorted(by: {
        ($0.attributes?.referenceName ?? "") < ($1.attributes?.referenceName ?? "")
      }) {
        let a = event.attributes
        rows.append([
          a?.referenceName ?? "—",
          a?.eventState.map { formatState($0) } ?? "—",
          a?.badge.map { formatState($0) } ?? "—",
          a?.priority.map { formatState($0) } ?? "—",
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
      let a = appEvent.attributes

      print("Reference Name:       \(a?.referenceName ?? "—")")
      print("State:                \(a?.eventState.map { formatState($0) } ?? "—")")
      print("Badge:                \(a?.badge.map { formatState($0) } ?? "—")")
      print("Priority:             \(a?.priority.map { formatState($0) } ?? "—")")
      print("Purpose:              \(a?.purpose.map { formatState($0) } ?? "—")")
      print("Primary Locale:       \(a?.primaryLocale.flatMap { $0.isEmpty ? nil : localeName($0) } ?? "—")")
      print("Deep Link:            \(a?.deepLink.map { "\($0)" } ?? "—")")
      print("Purchase Requirement: \(a?.purchaseRequirement ?? "—")")
      print("Event ID:             \(appEvent.id)")

      if let schedules = a?.territorySchedules, !schedules.isEmpty {
        print()
        print("Territory Schedules:")
        for s in schedules {
          let terrs = s.territories?.joined(separator: ", ") ?? "all territories"
          print("  • \(terrs)")
          print("    Publish: \(s.publishStart.map { formatDate($0) } ?? "—")")
          print("    Event:   \(s.eventStart.map { formatDate($0) } ?? "—") → \(s.eventEnd.map { formatDate($0) } ?? "—")")
        }
      }

      let locs = try await client.send(
        Resources.v1.appEvents.id(appEvent.id).localizations.get(limit: 50))
      if !locs.data.isEmpty {
        print()
        print("Localizations (\(locs.data.count)):")
        for loc in locs.data.sorted(by: {
          ($0.attributes?.locale ?? "") < ($1.attributes?.locale ?? "")
        }) {
          let la = loc.attributes
          print("  [\(la?.locale.map { localeName($0) } ?? "—")] \(la?.name ?? "—")")
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

      let badgeValue: AppEventCreateRequest.Data.Attributes.Badge? =
        try badge.map { try parseEnum($0, name: "badge") }
      let priorityValue: AppEventCreateRequest.Data.Attributes.Priority? =
        try priority.map { try parseEnum($0, name: "priority") }
      let purposeValue: AppEventCreateRequest.Data.Attributes.Purpose? =
        try purpose.map { try parseEnum($0, name: "purpose") }

      var schedules: [AppEventCreateRequest.Data.Attributes.TerritorySchedule]?
      if territories != nil || publishStart != nil || eventStart != nil || eventEnd != nil {
        schedules = [
          .init(
            territories: AppEventsCommand.territoryList(territories),
            publishStart: try publishStart.map {
              try AppEventsCommand.parseEventDate($0, field: "--publish-start")
            },
            eventStart: try eventStart.map {
              try AppEventsCommand.parseEventDate($0, field: "--event-start")
            },
            eventEnd: try eventEnd.map {
              try AppEventsCommand.parseEventDate($0, field: "--event-end")
            }
          )
        ]
      }

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

      let response = try await client.send(
        Resources.v1.appEvents.post(
          AppEventCreateRequest(
            data: .init(
              attributes: .init(
                referenceName: referenceName,
                badge: badgeValue,
                deepLink: deepLink.flatMap { URL(string: $0) },
                purchaseRequirement: purchaseRequirement,
                primaryLocale: primaryLocale,
                priority: priorityValue,
                purpose: purposeValue,
                territorySchedules: schedules
              ),
              relationships: .init(app: .init(data: .init(id: app.id)))
            )
          )
        ))

      print()
      success("Created", "in-app event '\(referenceName)' (id: \(response.data.id)).")
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

      let priorityValue: AppEventUpdateRequest.Data.Attributes.Priority? =
        try priority.map { try parseEnum($0, name: "priority") }
      let purposeValue: AppEventUpdateRequest.Data.Attributes.Purpose? =
        try purpose.map { try parseEnum($0, name: "purpose") }
      let badgeValue: AppEventUpdateRequest.Data.Attributes.Badge? =
        try badge.flatMap { $0.uppercased() == "NONE" ? nil : try parseEnum($0, name: "badge") }

      var schedules: [AppEventUpdateRequest.Data.Attributes.TerritorySchedule]?
      if territories != nil || publishStart != nil || eventStart != nil || eventEnd != nil {
        schedules = [
          .init(
            territories: AppEventsCommand.territoryList(territories),
            publishStart: try publishStart.map {
              try AppEventsCommand.parseEventDate($0, field: "--publish-start")
            },
            eventStart: try eventStart.map {
              try AppEventsCommand.parseEventDate($0, field: "--event-start")
            },
            eventEnd: try eventEnd.map {
              try AppEventsCommand.parseEventDate($0, field: "--event-end")
            }
          )
        ]
      }

      guard confirm("Update event '\(appEvent.attributes?.referenceName ?? event)'? [y/N] ") else {
        cancelled()
        return
      }

      _ = try await client.send(
        Resources.v1.appEvents.id(appEvent.id).patch(
          AppEventUpdateRequest(
            data: .init(
              id: appEvent.id,
              attributes: .init(
                referenceName: referenceName,
                badge: badgeValue,
                deepLink: deepLink.flatMap { URL(string: $0) },
                purchaseRequirement: purchaseRequirement,
                priority: priorityValue,
                purpose: purposeValue,
                territorySchedules: schedules
              )
            )
          )
        ))

      print()
      success("Updated", "in-app event '\(appEvent.attributes?.referenceName ?? event)'.")
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
      let name = appEvent.attributes?.referenceName ?? event

      print("In-app event: \(name) (\(appEvent.attributes?.eventState.map { formatState($0) } ?? "—"))")
      print()
      guard confirm("Delete this event? [y/N] ") else {
        cancelled()
        return
      }

      _ = try await client.send(Resources.v1.appEvents.id(appEvent.id).delete)
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

        let resp = try await client.send(
          Resources.v1.appEvents.id(appEvent.id).localizations.get(limit: 50))
        if resp.data.isEmpty {
          print("No localizations found.")
          return
        }

        print("Localizations for '\(appEvent.attributes?.referenceName ?? event)':")
        print()
        for loc in resp.data.sorted(by: {
          ($0.attributes?.locale ?? "") < ($1.attributes?.locale ?? "")
        }) {
          let a = loc.attributes
          print("[\(localeName(a?.locale ?? "?"))]")
          print("  Name:              \(a?.name ?? "—")")
          print("  Short Description: \(a?.shortDescription ?? "—")")
          if let long = a?.longDescription, !long.isEmpty {
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

        let resp = try await client.send(
          Resources.v1.appEvents.id(appEvent.id).localizations.get(limit: 50))

        var result: [String: EventLocaleFields] = [:]
        for loc in resp.data {
          guard let locale = loc.attributes?.locale else { continue }
          result[locale] = EventLocaleFields(
            name: loc.attributes?.name,
            shortDescription: loc.attributes?.shortDescription,
            longDescription: loc.attributes?.longDescription
          )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)

        let refName = appEvent.attributes?.referenceName ?? "event"
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

        print("Importing \(localeUpdates.count) locale(s) for '\(appEvent.attributes?.referenceName ?? event)':")
        for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
          print("  [\(localeName(locale))] \(fields.name ?? "—")")
        }
        print()

        guard confirm("Send updates for \(localeUpdates.count) locale(s)? [y/N] ") else {
          cancelled()
          return
        }
        print()

        let existing = try await client.send(
          Resources.v1.appEvents.id(appEvent.id).localizations.get(limit: 50))
        let byLocale = Dictionary(
          existing.data.compactMap { loc in loc.attributes?.locale.map { ($0, loc) } },
          uniquingKeysWith: { first, _ in first })

        for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
          if let loc = byLocale[locale] {
            let response = try await client.send(
              Resources.v1.appEventLocalizations.id(loc.id).patch(
                AppEventLocalizationUpdateRequest(
                  data: .init(
                    id: loc.id,
                    attributes: .init(
                      name: fields.name,
                      shortDescription: fields.shortDescription,
                      longDescription: fields.longDescription
                    )
                  )
                )
              ))
            print("  [\(localeName(locale))] Updated.")
            if verbose { Self.printResponse(response.data.attributes) }
          } else {
            guard confirm("  [\(localeName(locale))] Locale not present. Create it? [y/N] ") else {
              print("  [\(localeName(locale))] Skipped.")
              continue
            }
            let response = try await client.send(
              Resources.v1.appEventLocalizations.post(
                AppEventLocalizationCreateRequest(
                  data: .init(
                    attributes: .init(
                      locale: locale,
                      name: fields.name,
                      shortDescription: fields.shortDescription,
                      longDescription: fields.longDescription
                    ),
                    relationships: .init(appEvent: .init(data: .init(id: appEvent.id)))
                  )
                )
              ))
            print("  [\(localeName(locale))] \(green("Created."))")
            if verbose { Self.printResponse(response.data.attributes) }
          }
        }

        print()
        print("Done.")
      }

      private static func printResponse(_ attrs: AppEventLocalization.Attributes?) {
        print("    Response:")
        print("      Locale:            \(attrs?.locale.map { localeName($0) } ?? "—")")
        if let v = attrs?.name { print("      Name:              \(v)") }
        if let v = attrs?.shortDescription { print("      Short Description: \(v)") }
        if let v = attrs?.longDescription {
          print("      Long Description:  \(v.prefix(120))\(v.count > 120 ? "…" : "")")
        }
      }
    }
  }
}
