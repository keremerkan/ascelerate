import AppStoreAPI
import AppStoreConnect
import ArgumentParser
import Foundation

struct SubCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "sub",
    abstract: "Manage subscriptions.",
    subcommands: [
      Groups.self, List.self, Info.self,
      Create.self, Update.self, Delete.self, Submit.self,
      CreateGroup.self, UpdateGroup.self, DeleteGroup.self,
      Localizations.self, GroupLocalizations.self,
    ]
  )

  // MARK: - Helpers

  struct GroupInfo: Sendable {
    let id: String
    let name: String
    let subscriptions: [Subscription]
  }

  static func fetchGroups(
    appID: String, client: AppStoreConnectClient
  ) async throws -> [GroupInfo] {
    var result: [GroupInfo] = []
    let request = Resources.v1.apps.id(appID).subscriptionGroups.get(
      include: [.subscriptions],
      limitSubscriptions: 50
    )
    for try await page in client.pages(request) {
      var subsByID: [String: Subscription] = [:]
      for item in page.included ?? [] {
        if case .subscription(let sub) = item {
          subsByID[sub.id] = sub
        }
      }
      for group in page.data {
        let name = group.attributes?.referenceName ?? "—"
        let subIDs = group.relationships?.subscriptions?.data?.map(\.id) ?? []
        let subs = subIDs.compactMap { subsByID[$0] }
        result.append(GroupInfo(id: group.id, name: name, subscriptions: subs))
      }
    }
    return result
  }

  static func findSubscription(
    productID: String, appID: String, client: AppStoreConnectClient
  ) async throws -> (subscription: Subscription, group: GroupInfo) {
    let groups = try await fetchGroups(appID: appID, client: client)
    for group in groups {
      if let match = group.subscriptions.first(where: { $0.attributes?.productID == productID }) {
        return (match, group)
      }
    }
    throw ValidationError("No subscription found with product ID '\(productID)'.")
  }

  static func pickGroup(
    appID: String, client: AppStoreConnectClient
  ) async throws -> GroupInfo {
    let groups = try await fetchGroups(appID: appID, client: client)
    guard !groups.isEmpty else {
      throw ValidationError("No subscription groups found. Create one first with 'sub create-group'.")
    }
    if groups.count == 1 { return groups[0] }
    return try promptSelection(
      "Subscription Groups",
      items: groups,
      display: { "\($0.name) (\($0.subscriptions.count) subscription\($0.subscriptions.count == 1 ? "" : "s"))" }
    )
  }

  // MARK: - Groups

  struct Groups: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List subscription groups with their subscriptions."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let groups = try await SubCommand.fetchGroups(appID: app.id, client: client)

      if groups.isEmpty {
        print("No subscription groups found.")
        return
      }

      for group in groups {
        let sorted = group.subscriptions.sorted { ($0.attributes?.groupLevel ?? 0) < ($1.attributes?.groupLevel ?? 0) }
        print("\(group.name) (\(sorted.count) subscription\(sorted.count == 1 ? "" : "s"))")

        if sorted.isEmpty {
          print("  (no subscriptions)")
        } else {
          Table.print(
            headers: ["Name", "Product ID", "Period", "State", "Level", "Family"],
            rows: sorted.map { sub in
              let attrs = sub.attributes
              return [
                attrs?.name ?? "—",
                attrs?.productID ?? "—",
                attrs?.subscriptionPeriod.map { formatState($0) } ?? "—",
                attrs?.state.map { formatState($0) } ?? "—",
                attrs?.groupLevel.map { "\($0)" } ?? "—",
                attrs?.isFamilySharable == true ? "Yes" : "No",
              ]
            }
          )
        }
        print()
      }
    }
  }

  // MARK: - List

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List all subscriptions across groups."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let groups = try await SubCommand.fetchGroups(appID: app.id, client: client)

      var rows: [[String]] = []
      for group in groups {
        for sub in group.subscriptions.sorted(by: { ($0.attributes?.groupLevel ?? 0) < ($1.attributes?.groupLevel ?? 0) }) {
          let attrs = sub.attributes
          rows.append([
            group.name,
            attrs?.name ?? "—",
            attrs?.productID ?? "—",
            attrs?.subscriptionPeriod.map { formatState($0) } ?? "—",
            attrs?.state.map { formatState($0) } ?? "—",
            attrs?.groupLevel.map { "\($0)" } ?? "—",
          ])
        }
      }

      if rows.isEmpty {
        print("No subscriptions found.")
      } else {
        Table.print(
          headers: ["Group", "Name", "Product ID", "Period", "State", "Level"],
          rows: rows
        )
      }
    }
  }

  // MARK: - Info

  struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Show details for a subscription."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Argument(help: "The product identifier of the subscription.")
    var productID: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let (sub, group) = try await SubCommand.findSubscription(
        productID: productID, appID: app.id, client: client
      )

      // Fetch full details with localizations
      let detailResponse = try await client.send(
        Resources.v1.subscriptions.id(sub.id).get(
          include: [.subscriptionLocalizations],
          limitSubscriptionLocalizations: 50
        )
      )
      let detail = detailResponse.data
      let attrs = detail.attributes

      print("Name:             \(attrs?.name ?? "—")")
      print("Product ID:       \(attrs?.productID ?? "—")")
      print("Group:            \(group.name)")
      print("Period:           \(attrs?.subscriptionPeriod.map { formatState($0) } ?? "—")")
      print("State:            \(attrs?.state.map { formatState($0) } ?? "—")")
      print("Group Level:      \(attrs?.groupLevel.map { "\($0)" } ?? "—")")
      print("Family Shareable: \(attrs?.isFamilySharable == true ? "Yes" : "No")")
      print("Review Note:      \(attrs?.reviewNote ?? "—")")

      // Extract localizations from included items
      let locIDs = Set(
        detail.relationships?.subscriptionLocalizations?.data?.map(\.id) ?? []
      )
      let localizations: [SubscriptionLocalization] = (detailResponse.included ?? []).compactMap {
        if case .subscriptionLocalization(let loc) = $0,
           locIDs.isEmpty || locIDs.contains(loc.id) {
          return loc
        }
        return nil
      }

      if !localizations.isEmpty {
        print()
        print("Localizations:")
        for loc in localizations.sorted(by: { ($0.attributes?.locale ?? "") < ($1.attributes?.locale ?? "") }) {
          let locale = loc.attributes?.locale ?? "?"
          let name = loc.attributes?.name ?? "—"
          let desc = loc.attributes?.description ?? "—"
          print("  [\(localeName(locale))] \(name) — \(desc)")
        }
      }
    }
  }

  // MARK: - Create Group

  struct CreateGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "create-group",
      abstract: "Create a new subscription group."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .long, help: "Reference name for the group.")
    var name: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes: Bool = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let refName = name ?? promptText("Group Reference Name: ")

      guard confirm("Create subscription group '\(refName)'? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

      let response = try await client.send(
        Resources.v1.subscriptionGroups.post(
          SubscriptionGroupCreateRequest(
            data: .init(
              attributes: .init(referenceName: refName),
              relationships: .init(
                app: .init(data: .init(id: app.id))
              )
            )
          )
        )
      )

      print(green("Created") + " subscription group '\(response.data.attributes?.referenceName ?? refName)'.")
    }
  }

  // MARK: - Update Group

  struct UpdateGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "update-group",
      abstract: "Update a subscription group."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .long, help: "New reference name.")
    var name: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes: Bool = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let group = try await SubCommand.pickGroup(appID: app.id, client: client)

      let newName = name ?? promptText("New Reference Name: ")

      guard confirm("Rename group '\(group.name)' to '\(newName)'? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

      _ = try await client.send(
        Resources.v1.subscriptionGroups.id(group.id).patch(
          SubscriptionGroupUpdateRequest(
            data: .init(
              id: group.id,
              attributes: .init(referenceName: newName)
            )
          )
        )
      )

      print(green("Updated") + " group '\(newName)'.")
    }
  }

  // MARK: - Delete Group

  struct DeleteGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "delete-group",
      abstract: "Delete a subscription group."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes: Bool = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let group = try await SubCommand.pickGroup(appID: app.id, client: client)

      guard confirm("Delete subscription group '\(group.name)' and all its subscriptions? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

      _ = try await client.send(Resources.v1.subscriptionGroups.id(group.id).delete)

      print(green("Deleted") + " group '\(group.name)'.")
    }
  }

  // MARK: - Create

  struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Create a new subscription."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .long, help: "Product identifier (e.g. com.example.monthly).")
    var productID: String?

    @Option(name: .long, help: "Reference name.")
    var name: String?

    @Option(name: .long, help: "Period (ONE_WEEK, ONE_MONTH, TWO_MONTHS, THREE_MONTHS, SIX_MONTHS, ONE_YEAR).")
    var period: String?

    @Option(name: .long, help: "Group level (1 = highest priority).")
    var groupLevel: Int?

    @Option(name: .long, help: "Review note for App Review.")
    var reviewNote: String?

    @Flag(name: .long, help: "Enable Family Sharing.")
    var familySharable: Bool = false

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes: Bool = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let group = try await SubCommand.pickGroup(appID: app.id, client: client)

      let pid = productID ?? promptText("Product ID: ")
      let refName = name ?? promptText("Reference Name: ")

      typealias CreateAttrs = SubscriptionCreateRequest.Data.Attributes

      let subPeriod: CreateAttrs.SubscriptionPeriod?
      if let p = period {
        subPeriod = try parseEnum(p, name: "period")
      } else if !autoConfirm {
        subPeriod = try promptSelection(
          "Period",
          items: Array(CreateAttrs.SubscriptionPeriod.allCases),
          display: { formatState($0) }
        )
      } else {
        subPeriod = nil
      }

      var level = groupLevel
      if level == nil && !autoConfirm {
        print("Group Level (1 = highest, press Enter to skip): ", terminator: "")
        let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let val = Int(input) { level = val }
      }

      var note: String? = reviewNote
      if note == nil && !autoConfirm {
        print("Review Note (optional, press Enter to skip): ", terminator: "")
        let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !input.isEmpty { note = input }
      }

      print()
      print("Group:            \(group.name)")
      print("Product ID:       \(pid)")
      print("Name:             \(refName)")
      if let p = subPeriod { print("Period:           \(formatState(p))") }
      if let l = level { print("Group Level:      \(l)") }
      print("Family Shareable: \(familySharable ? "Yes" : "No")")
      if let n = note { print("Review Note:      \(n)") }
      print()

      guard confirm("Create this subscription? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

      let response = try await client.send(
        Resources.v1.subscriptions.post(
          SubscriptionCreateRequest(
            data: .init(
              attributes: .init(
                name: refName,
                productID: pid,
                isFamilySharable: familySharable ? true : nil,
                subscriptionPeriod: subPeriod,
                reviewNote: note,
                groupLevel: level
              ),
              relationships: .init(
                group: .init(data: .init(id: group.id))
              )
            )
          )
        )
      )

      print(green("Created") + " subscription '\(response.data.attributes?.name ?? refName)'.")
    }
  }

  // MARK: - Update

  struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Update a subscription."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Argument(help: "The product identifier of the subscription.")
    var productID: String

    @Option(name: .long, help: "New reference name.")
    var name: String?

    @Option(name: .long, help: "New period (ONE_WEEK, ONE_MONTH, TWO_MONTHS, THREE_MONTHS, SIX_MONTHS, ONE_YEAR).")
    var period: String?

    @Option(name: .long, help: "New group level (1 = highest).")
    var groupLevel: Int?

    @Option(name: .long, help: "New review note.")
    var reviewNote: String?

    @Option(name: .long, help: "Enable or disable Family Sharing (true/false).")
    var familySharable: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes: Bool = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let (sub, _) = try await SubCommand.findSubscription(
        productID: productID, appID: app.id, client: client
      )

      typealias UpdateAttrs = SubscriptionUpdateRequest.Data.Attributes

      let periodVal: UpdateAttrs.SubscriptionPeriod? = try period.map {
        try parseEnum($0, name: "period")
      }

      let familyVal: Bool? = try familySharable.map {
        guard let val = Bool($0.lowercased()) else {
          throw ValidationError("Invalid value for --family-sharable. Use 'true' or 'false'.")
        }
        return val
      }

      guard name != nil || periodVal != nil || groupLevel != nil || reviewNote != nil || familyVal != nil else {
        throw ValidationError("No updates specified. Use --name, --period, --group-level, --review-note, or --family-sharable.")
      }

      var changes: [String] = []
      if let v = name { changes.append("Name: \(v)") }
      if let v = periodVal { changes.append("Period: \(formatState(v))") }
      if let v = groupLevel { changes.append("Group Level: \(v)") }
      if let v = reviewNote { changes.append("Review Note: \(v)") }
      if let v = familyVal { changes.append("Family Shareable: \(v ? "Yes" : "No")") }
      print("Updates for '\(sub.attributes?.name ?? productID)':")
      for c in changes { print("  \(c)") }
      print()

      guard confirm("Apply updates? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

      _ = try await client.send(
        Resources.v1.subscriptions.id(sub.id).patch(
          SubscriptionUpdateRequest(
            data: .init(
              id: sub.id,
              attributes: .init(
                name: name,
                isFamilySharable: familyVal,
                subscriptionPeriod: periodVal,
                reviewNote: reviewNote,
                groupLevel: groupLevel
              )
            )
          )
        )
      )

      print(green("Updated") + " '\(name ?? sub.attributes?.name ?? productID)'.")
    }
  }

  // MARK: - Delete

  struct Delete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Delete a subscription."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Argument(help: "The product identifier of the subscription.")
    var productID: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes: Bool = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let (sub, _) = try await SubCommand.findSubscription(
        productID: productID, appID: app.id, client: client
      )

      guard confirm("Delete subscription '\(sub.attributes?.name ?? productID)'? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

      _ = try await client.send(Resources.v1.subscriptions.id(sub.id).delete)

      print(green("Deleted") + " '\(sub.attributes?.name ?? productID)'.")
    }
  }

  // MARK: - Submit

  struct Submit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Submit a subscription for review."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Argument(help: "The product identifier of the subscription.")
    var productID: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes: Bool = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let (sub, group) = try await SubCommand.findSubscription(
        productID: productID, appID: app.id, client: client
      )

      let state = sub.attributes?.state
      guard state == .readyToSubmit else {
        let stateStr = state.map { formatState($0) } ?? "unknown"
        throw ValidationError("Subscription '\(sub.attributes?.name ?? productID)' is in state '\(stateStr)'. Only items in 'Ready to Submit' state can be submitted.")
      }

      print("Subscription: \(sub.attributes?.name ?? productID)")
      print("Product ID:   \(productID)")
      print("Group:        \(group.name)")
      print("State:        \(formatState(state!))")
      print()
      print(yellow("Note:") + " Subscriptions are reviewed together with the app version.")
      print("Make sure you also submit a new app version for review.")
      print()

      guard confirm("Submit for review? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

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

      print(green("Submitted") + " '\(sub.attributes?.name ?? productID)' for review.")
    }
  }

  // MARK: - Localizations

  struct Localizations: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Manage subscription localizations.",
      subcommands: [View.self, Export.self, Import.self]
    )

    // MARK: View

    struct View: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "View localizations for a subscription."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let (sub, _) = try await SubCommand.findSubscription(
          productID: productID, appID: app.id, client: client
        )

        let locsResponse = try await client.send(
          Resources.v1.subscriptions.id(sub.id).subscriptionLocalizations.get(limit: 50)
        )

        if locsResponse.data.isEmpty {
          print("No localizations found.")
          return
        }

        print("Localizations for '\(sub.attributes?.name ?? productID)':")
        print()

        for loc in locsResponse.data.sorted(by: { ($0.attributes?.locale ?? "") < ($1.attributes?.locale ?? "") }) {
          let locale = loc.attributes?.locale ?? "?"
          print("[\(localeName(locale))]")
          print("  Name:        \(loc.attributes?.name ?? "—")")
          print("  Description: \(loc.attributes?.description ?? "—")")
          print()
        }
      }
    }

    // MARK: Export

    struct Export: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Export subscription localizations to a JSON file."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Option(name: .long, help: "Output file path.",
              completion: .file(extensions: ["json"]))
      var output: String?

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let (sub, _) = try await SubCommand.findSubscription(
          productID: productID, appID: app.id, client: client
        )

        let locsResponse = try await client.send(
          Resources.v1.subscriptions.id(sub.id).subscriptionLocalizations.get(limit: 50)
        )

        var result: [String: ProductLocaleFields] = [:]
        for loc in locsResponse.data {
          guard let locale = loc.attributes?.locale else { continue }
          result[locale] = ProductLocaleFields(
            name: loc.attributes?.name,
            description: loc.attributes?.description
          )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)

        let outputPath = expandPath(
          confirmOutputPath(output ?? "\(productID)-localizations.json", isDirectory: false))
        try data.write(to: URL(fileURLWithPath: outputPath))

        print(green("Exported") + " \(result.count) locale(s) to \(outputPath)")
      }
    }

    // MARK: Import

    struct Import: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Import subscription localizations from a JSON file."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

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
        let (sub, _) = try await SubCommand.findSubscription(
          productID: productID, appID: app.id, client: client
        )

        let filePath = try resolveFile(file, extension: "json", prompt: "Select a JSON file")
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let localeUpdates = try JSONDecoder().decode([String: ProductLocaleFields].self, from: data)

        guard !localeUpdates.isEmpty else {
          throw ValidationError("JSON file contains no locale data.")
        }

        print("Importing \(localeUpdates.count) locale(s) for '\(sub.attributes?.name ?? productID)':")
        for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
          print("  [\(localeName(locale))] \(fields.name ?? "—") — \(fields.description?.prefix(60) ?? "—")\(fields.description.map { $0.count > 60 ? "..." : "" } ?? "")")
        }
        print()

        guard confirm("Send updates for \(localeUpdates.count) locale(s)? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        print()

        // Fetch existing localizations
        let locsResponse = try await client.send(
          Resources.v1.subscriptions.id(sub.id).subscriptionLocalizations.get(limit: 50)
        )

        let locByLocale = Dictionary(
          locsResponse.data.compactMap { loc in
            loc.attributes?.locale.map { ($0, loc) }
          },
          uniquingKeysWith: { first, _ in first }
        )

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
              Resources.v1.subscriptionLocalizations.post(
                SubscriptionLocalizationCreateRequest(
                  data: .init(
                    attributes: .init(
                      name: name,
                      locale: locale,
                      description: fields.description
                    ),
                    relationships: .init(
                      subscription: .init(data: .init(id: sub.id))
                    )
                  )
                )
              )
            )
            print("  [\(localeName(locale))] \(green("Created."))")

            if verbose {
              let attrs = response.data.attributes
              print("    Response:")
              print("      Locale:      \(attrs?.locale.map { localeName($0) } ?? "—")")
              if let v = attrs?.name { print("      Name:        \(v)") }
              if let v = attrs?.description { print("      Description: \(v.prefix(120))\(v.count > 120 ? "..." : "")") }
            }
            continue
          }

          let response = try await client.send(
            Resources.v1.subscriptionLocalizations.id(localization.id).patch(
              SubscriptionLocalizationUpdateRequest(
                data: .init(
                  id: localization.id,
                  attributes: .init(
                    name: fields.name,
                    description: fields.description
                  )
                )
              )
            )
          )
          print("  [\(localeName(locale))] Updated.")

          if verbose {
            let attrs = response.data.attributes
            print("    Response:")
            print("      Locale:      \(attrs?.locale.map { localeName($0) } ?? "—")")
            if let v = attrs?.name { print("      Name:        \(v)") }
            if let v = attrs?.description { print("      Description: \(v.prefix(120))\(v.count > 120 ? "..." : "")") }
          }
        }

        print()
        print("Done.")
      }
    }
  }

  // MARK: - Group Localizations

  struct GroupLocalizations: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "group-localizations",
      abstract: "Manage subscription group localizations.",
      subcommands: [View.self, Export.self, Import.self]
    )

    // MARK: View

    struct View: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "View localizations for a subscription group."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let group = try await SubCommand.pickGroup(appID: app.id, client: client)

        let locsResponse = try await client.send(
          Resources.v1.subscriptionGroups.id(group.id).subscriptionGroupLocalizations.get(limit: 50)
        )

        if locsResponse.data.isEmpty {
          print("No localizations found for group '\(group.name)'.")
          return
        }

        print("Localizations for group '\(group.name)':")
        print()

        for loc in locsResponse.data.sorted(by: { ($0.attributes?.locale ?? "") < ($1.attributes?.locale ?? "") }) {
          let locale = loc.attributes?.locale ?? "?"
          print("[\(localeName(locale))]")
          print("  Name:            \(loc.attributes?.name ?? "—")")
          print("  Custom App Name: \(loc.attributes?.customAppName ?? "—")")
          print()
        }
      }
    }

    // MARK: Export

    struct Export: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Export subscription group localizations to a JSON file."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Output file path.",
              completion: .file(extensions: ["json"]))
      var output: String?

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let group = try await SubCommand.pickGroup(appID: app.id, client: client)

        let locsResponse = try await client.send(
          Resources.v1.subscriptionGroups.id(group.id).subscriptionGroupLocalizations.get(limit: 50)
        )

        var result: [String: GroupLocaleFields] = [:]
        for loc in locsResponse.data {
          guard let locale = loc.attributes?.locale else { continue }
          result[locale] = GroupLocaleFields(
            name: loc.attributes?.name,
            customAppName: loc.attributes?.customAppName
          )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)

        let safeName = group.name.replacingOccurrences(of: " ", with: "-").lowercased()
        let outputPath = expandPath(
          confirmOutputPath(output ?? "\(safeName)-group-localizations.json", isDirectory: false))
        try data.write(to: URL(fileURLWithPath: outputPath))

        print(green("Exported") + " \(result.count) locale(s) to \(outputPath)")
      }
    }

    // MARK: Import

    struct Import: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Import subscription group localizations from a JSON file."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

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
        let group = try await SubCommand.pickGroup(appID: app.id, client: client)

        let filePath = try resolveFile(file, extension: "json", prompt: "Select a JSON file")
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let localeUpdates = try JSONDecoder().decode([String: GroupLocaleFields].self, from: data)

        guard !localeUpdates.isEmpty else {
          throw ValidationError("JSON file contains no locale data.")
        }

        print("Importing \(localeUpdates.count) locale(s) for group '\(group.name)':")
        for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
          print("  [\(localeName(locale))] \(fields.name ?? "—")")
        }
        print()

        guard confirm("Send updates for \(localeUpdates.count) locale(s)? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        print()

        // Fetch existing localizations
        let locsResponse = try await client.send(
          Resources.v1.subscriptionGroups.id(group.id).subscriptionGroupLocalizations.get(limit: 50)
        )

        let locByLocale = Dictionary(
          locsResponse.data.compactMap { loc in
            loc.attributes?.locale.map { ($0, loc) }
          },
          uniquingKeysWith: { first, _ in first }
        )

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
              Resources.v1.subscriptionGroupLocalizations.post(
                SubscriptionGroupLocalizationCreateRequest(
                  data: .init(
                    attributes: .init(
                      name: name,
                      customAppName: fields.customAppName,
                      locale: locale
                    ),
                    relationships: .init(
                      subscriptionGroup: .init(data: .init(id: group.id))
                    )
                  )
                )
              )
            )
            print("  [\(localeName(locale))] \(green("Created."))")

            if verbose {
              let attrs = response.data.attributes
              print("    Response:")
              print("      Locale:          \(attrs?.locale.map { localeName($0) } ?? "—")")
              if let v = attrs?.name { print("      Name:            \(v)") }
              if let v = attrs?.customAppName { print("      Custom App Name: \(v)") }
            }
            continue
          }

          let response = try await client.send(
            Resources.v1.subscriptionGroupLocalizations.id(localization.id).patch(
              SubscriptionGroupLocalizationUpdateRequest(
                data: .init(
                  id: localization.id,
                  attributes: .init(
                    name: fields.name,
                    customAppName: fields.customAppName
                  )
                )
              )
            )
          )
          print("  [\(localeName(locale))] Updated.")

          if verbose {
            let attrs = response.data.attributes
            print("    Response:")
            print("      Locale:          \(attrs?.locale.map { localeName($0) } ?? "—")")
            if let v = attrs?.name { print("      Name:            \(v)") }
            if let v = attrs?.customAppName { print("      Custom App Name: \(v)") }
          }
        }

        print()
        print("Done.")
      }
    }
  }
}
