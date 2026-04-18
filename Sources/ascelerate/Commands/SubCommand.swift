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
      Localizations.self, GroupLocalizations.self, Pricing.self, Availability.self,
      IntroOffer.self, OfferCode.self, PromoOffer.self, SubmitGroup.self,
      Images.self, ReviewScreenshot.self,
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

  /// Returns true if the subscription has at least one price entry.
  static func subscriptionHasPrices(
    subscriptionID: String, client: AppStoreConnectClient
  ) async throws -> Bool {
    let response = try await client.send(
      Resources.v1.subscriptions.id(subscriptionID).prices.get(limit: 1)
    )
    return !response.data.isEmpty
  }

  static let missingPricesWarning =
    "⚠ No prices set — subscription cannot be submitted. Use 'sub pricing set ...' to configure."

  /// Direction of a proposed price change relative to the current price.
  enum PriceDirection: Sendable {
    case new       // no current price exists for this territory
    case unchanged // new == current
    case increase  // new > current
    case decrease  // new < current

    var label: String {
      switch self {
      case .new: return "new"
      case .unchanged: return "unchanged"
      case .increase: return "increase"
      case .decrease: return "decrease"
      }
    }
  }

  /// Compares a target customer price against an existing one. Both are nil-safe.
  static func priceDirection(current: String?, target: String?) -> PriceDirection {
    guard let target = target.flatMap({ Double($0) }) else { return .new }
    guard let current = current.flatMap({ Double($0) }) else { return .new }
    if abs(target - current) < 0.001 { return .unchanged }
    return target > current ? .increase : .decrease
  }

  /// Fetches the customer-price string for a single territory's current SubscriptionPrice.
  /// Returns nil if no price exists. Picks the most recent record (by startDate desc).
  static func fetchCurrentPrice(
    subID: String, territoryID: String, client: AppStoreConnectClient
  ) async throws -> String? {
    var prices: [SubscriptionPrice] = []
    var pointPrices: [String: String] = [:]
    for try await page in client.pages(
      Resources.v1.subscriptions.id(subID).prices.get(
        filterTerritory: [territoryID],
        limit: 200,
        include: [.subscriptionPricePoint]
      )
    ) {
      prices.append(contentsOf: page.data)
      for item in page.included ?? [] {
        if case .subscriptionPricePoint(let p) = item, let cp = p.attributes?.customerPrice {
          pointPrices[p.id] = cp
        }
      }
    }
    guard let latest = prices.sorted(by: {
      ($0.attributes?.startDate ?? "") > ($1.attributes?.startDate ?? "")
    }).first else {
      return nil
    }
    let pointID = latest.relationships?.subscriptionPricePoint?.data?.id ?? ""
    return pointPrices[pointID]
  }

  /// Fetches the current customer price for every territory the subscription is priced in.
  /// Returns a [territoryID: customerPrice] map. Picks the most recent record per territory.
  static func fetchCurrentPricesByTerritory(
    subID: String, client: AppStoreConnectClient
  ) async throws -> [String: String] {
    var prices: [SubscriptionPrice] = []
    var pointPrices: [String: String] = [:]
    for try await page in client.pages(
      Resources.v1.subscriptions.id(subID).prices.get(
        limit: 200, include: [.subscriptionPricePoint, .territory]
      )
    ) {
      prices.append(contentsOf: page.data)
      for item in page.included ?? [] {
        if case .subscriptionPricePoint(let p) = item, let cp = p.attributes?.customerPrice {
          pointPrices[p.id] = cp
        }
      }
    }
    // Group by territory, picking the most recent record per territory by startDate desc
    var latestByTerritory: [String: SubscriptionPrice] = [:]
    for price in prices {
      guard let territoryID = price.relationships?.territory?.data?.id else { continue }
      if let existing = latestByTerritory[territoryID] {
        let existingDate = existing.attributes?.startDate ?? ""
        let newDate = price.attributes?.startDate ?? ""
        if newDate > existingDate { latestByTerritory[territoryID] = price }
      } else {
        latestByTerritory[territoryID] = price
      }
    }
    var result: [String: String] = [:]
    for (territoryID, price) in latestByTerritory {
      let pointID = price.relationships?.subscriptionPricePoint?.data?.id ?? ""
      if let cp = pointPrices[pointID] {
        result[territoryID] = cp
      }
    }
    return result
  }

  /// Builds a clear error message for a price increase that lacks --preserve-current.
  static func priceIncreaseGuidance(
    from current: String?, to new: String?, currency: String?, territoryID: String
  ) -> String {
    var msg = "This is a price increase from \(current ?? "?") to \(new ?? "?") \(currency ?? "") in \(territoryID).\n"
    msg += "You must explicitly choose how to handle existing subscribers:\n"
    msg += "  --preserve-current        Grandfather existing subscribers at the old price\n"
    msg += "  --no-preserve-current     Push the new price to existing subscribers (after Apple's notification period)"
    return msg
  }

  /// Builds a clear error message for a price decrease in --yes mode without --confirm-decrease.
  static func priceDecreaseGuidance(
    from current: String?, to new: String?, currency: String?, territoryID: String
  ) -> String {
    var msg = "This is a price decrease from \(current ?? "?") to \(new ?? "?") \(currency ?? "") in \(territoryID).\n"
    msg += "Existing subscribers will move to the new lower price.\n"
    msg += "Plain --yes is not enough for price decreases. Add --confirm-decrease to acknowledge the revenue impact."
    return msg
  }

  /// Resolved offer-pricing tuples for promo offers, offer codes, and win-back offers
  /// — they all need the same shape: a (territory, pricePointID) list, optionally
  /// equalized across all territories from a single source price.
  struct ResolvedOfferPrices: Sendable {
    let entries: [(territoryID: String, pricePointID: String)]
    let sourceCustomerPrice: String
    let sourceCurrency: String?
    let isEqualized: Bool
  }

  /// Resolves `customerPrice` to a SubscriptionPricePoint in `sourceTerritory`. If
  /// `equalize` is true, fans out across every territory by walking the source point's
  /// equalizations endpoint. Throws ValidationError with nearest tiers when no exact match.
  static func resolveSubOfferPrices(
    subID: String, sourceTerritory: String, customerPrice: String,
    equalize: Bool, client: AppStoreConnectClient
  ) async throws -> ResolvedOfferPrices {
    guard let target = Double(customerPrice.trimmingCharacters(in: .whitespaces)) else {
      throw ValidationError("Invalid price '\(customerPrice)'. Use a decimal number like 4.99.")
    }
    var sourceTiers: [SubscriptionPricePoint] = []
    var sourceCurrency: String?
    for try await page in client.pages(
      Resources.v1.subscriptions.id(subID).pricePoints.get(
        filterTerritory: [sourceTerritory], limit: 200, include: [.territory]
      )
    ) {
      sourceTiers.append(contentsOf: page.data)
      for t in page.included ?? [] {
        if sourceCurrency == nil { sourceCurrency = t.attributes?.currency }
      }
    }
    guard let sourcePoint = sourceTiers.first(where: {
      guard let cp = $0.attributes?.customerPrice, let v = Double(cp) else { return false }
      return abs(v - target) < 0.001
    }) else {
      let nearest = sourceTiers.compactMap { $0.attributes?.customerPrice }.prefix(5).joined(separator: ", ")
      throw ValidationError("No tier with customer price \(customerPrice) in \(sourceTerritory). Nearby: \(nearest)")
    }

    if !equalize {
      return ResolvedOfferPrices(
        entries: [(sourceTerritory, sourcePoint.id)],
        sourceCustomerPrice: sourcePoint.attributes?.customerPrice ?? customerPrice,
        sourceCurrency: sourceCurrency,
        isEqualized: false
      )
    }

    var equalized: [SubscriptionPricePoint] = []
    for try await page in client.pages(
      Resources.v1.subscriptionPricePoints.id(sourcePoint.id).equalizations.get(
        limit: 200, include: [.territory]
      )
    ) {
      equalized.append(contentsOf: page.data)
    }
    if !equalized.contains(where: { $0.relationships?.territory?.data?.id == sourceTerritory }) {
      equalized.insert(sourcePoint, at: 0)
    }
    var entries: [(territoryID: String, pricePointID: String)] = []
    for point in equalized {
      guard let t = point.relationships?.territory?.data?.id else { continue }
      entries.append((t, point.id))
    }
    return ResolvedOfferPrices(
      entries: entries,
      sourceCustomerPrice: sourcePoint.attributes?.customerPrice ?? customerPrice,
      sourceCurrency: sourceCurrency,
      isEqualized: true
    )
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

      let hasPrices = try await SubCommand.subscriptionHasPrices(subscriptionID: sub.id, client: client)
      if !hasPrices {
        print()
        print(yellow(SubCommand.missingPricesWarning))
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

  // MARK: - Pricing

  struct Pricing: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "pricing",
      abstract: "Manage subscription pricing.",
      subcommands: [Show.self, Tiers.self, Set.self]
    )

    // MARK: Show

    struct Show: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Show the current prices for a subscription."
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
          productID: productID, appID: app.id, client: client)

        var prices: [SubscriptionPrice] = []
        var pricePoints: [String: SubscriptionPricePoint] = [:]
        var territoryCurrencies: [String: String] = [:]
        for try await page in client.pages(
          Resources.v1.subscriptions.id(sub.id).prices.get(
            limit: 200,
            include: [.territory, .subscriptionPricePoint]
          )
        ) {
          prices.append(contentsOf: page.data)
          for item in page.included ?? [] {
            switch item {
            case .subscriptionPricePoint(let point):
              pricePoints[point.id] = point
            case .territory(let t):
              if let cur = t.attributes?.currency {
                territoryCurrencies[t.id] = cur
              }
            }
          }
        }

        guard !prices.isEmpty else {
          print(yellow(missingPricesWarning))
          return
        }

        let sorted = prices.sorted {
          ($0.relationships?.territory?.data?.id ?? "") < ($1.relationships?.territory?.data?.id ?? "")
        }
        Table.print(
          headers: ["Territory", "Customer Price", "Start Date", "Preserved"],
          rows: sorted.map { price in
            let territoryID = price.relationships?.territory?.data?.id ?? "—"
            let pointID = price.relationships?.subscriptionPricePoint?.data?.id ?? ""
            let priceStr: String
            if let cp = pricePoints[pointID]?.attributes?.customerPrice {
              priceStr = "\(cp) \(territoryCurrencies[territoryID] ?? "")"
            } else {
              priceStr = "(unknown tier)"
            }
            return [
              territoryID,
              priceStr,
              price.attributes?.startDate ?? "—",
              price.attributes?.isPreserved == true ? "Yes" : "No",
            ]
          }
        )
      }
    }

    // MARK: Tiers

    struct Tiers: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "List available price tiers for a subscription in a territory."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Option(name: .long, help: "Territory code (default: USA).")
      var territory: String = "USA"

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let (sub, _) = try await SubCommand.findSubscription(
          productID: productID, appID: app.id, client: client)

        let territoryID = territory.uppercased()
        var tiers: [SubscriptionPricePoint] = []
        var currency: String?
        for try await page in client.pages(
          Resources.v1.subscriptions.id(sub.id).pricePoints.get(
            filterTerritory: [territoryID],
            limit: 200,
            include: [.territory]
          )
        ) {
          tiers.append(contentsOf: page.data)
          for t in page.included ?? [] {
            if currency == nil {
              currency = t.attributes?.currency
            }
          }
        }

        if tiers.isEmpty {
          print("No price tiers found for territory \(territoryID).")
          return
        }

        let cur = currency ?? ""
        let sorted = tiers.sorted {
          (Double($0.attributes?.customerPrice ?? "0") ?? 0)
            < (Double($1.attributes?.customerPrice ?? "0") ?? 0)
        }
        Table.print(
          headers: ["Tier ID", "Customer Price", "Proceeds", "Currency"],
          rows: sorted.map { tier in
            [
              tier.id,
              tier.attributes?.customerPrice ?? "—",
              tier.attributes?.proceeds ?? "—",
              cur,
            ]
          }
        )
      }
    }

    // MARK: Set

    struct Set: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Set the price for a subscription in a territory.",
        discussion: """
          Creates a new subscription price record for the given territory. Use --start-date
          to schedule a future price change. Use --preserve-current to keep existing
          subscribers on their current price.
          """
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Option(name: .long, help: "Customer price in the territory's currency (e.g. 4.99).")
      var price: String

      @Option(name: .long, help: "Territory code (default: USA).")
      var territory: String = "USA"

      @Option(name: .long, help: "Start date in YYYY-MM-DD format (default: immediate).")
      var startDate: String?

      @Flag(name: .customLong("preserve-current"), inversion: .prefixedNo,
            help: "Required for price increases. --preserve-current grandfathers existing subscribers at their old price; --no-preserve-current pushes the new price to them after Apple's notification period.")
      var preserveCurrent: Bool?

      @Flag(name: .customLong("equalize-all-territories"), help: "After resolving the source price, fan out the equivalent price tier to every territory (one POST per territory).")
      var equalizeAllTerritories = false

      @Flag(name: .customLong("confirm-decrease"), help: "Required with --yes when the new price is lower than the current price in any territory. Plain -y is not enough — price decreases need explicit confirmation.")
      var confirmDecrease = false

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let (sub, _) = try await SubCommand.findSubscription(
          productID: productID, appID: app.id, client: client)

        guard let targetPrice = Double(price.trimmingCharacters(in: .whitespaces)) else {
          throw ValidationError("Invalid price '\(price)'. Use a decimal number like 4.99.")
        }

        let territoryID = territory.uppercased()
        var tiers: [SubscriptionPricePoint] = []
        var currency: String?
        for try await page in client.pages(
          Resources.v1.subscriptions.id(sub.id).pricePoints.get(
            filterTerritory: [territoryID],
            limit: 200,
            include: [.territory]
          )
        ) {
          tiers.append(contentsOf: page.data)
          for t in page.included ?? [] {
            if currency == nil {
              currency = t.attributes?.currency
            }
          }
        }

        guard !tiers.isEmpty else {
          throw ValidationError("No price tiers available for territory \(territoryID).")
        }

        let match = tiers.first {
          guard let cp = $0.attributes?.customerPrice, let val = Double(cp) else { return false }
          return abs(val - targetPrice) < 0.001
        }

        guard let match else {
          let nearest = tiers
            .compactMap { tier -> (SubscriptionPricePoint, Double)? in
              guard let cp = tier.attributes?.customerPrice, let val = Double(cp) else { return nil }
              return (tier, abs(val - targetPrice))
            }
            .sorted { $0.1 < $1.1 }
            .prefix(5)
            .map(\.0)
          var msg = "No tier with customer price \(price) \(currency ?? "") in territory \(territoryID).\n"
          msg += "Nearest tiers: " + nearest.compactMap { $0.attributes?.customerPrice }.joined(separator: ", ")
          throw ValidationError(msg)
        }

        if equalizeAllTerritories {
          try await runEqualizeAllTerritories(
            sub: sub, sourceTerritory: territoryID, sourcePoint: match,
            sourceCurrency: currency, client: client)
        } else {
          try await runSingleTerritory(
            sub: sub, territoryID: territoryID, point: match,
            currency: currency, client: client)
        }
      }

      private func runSingleTerritory(
        sub: Subscription, territoryID: String, point: SubscriptionPricePoint,
        currency: String?, client: AppStoreConnectClient
      ) async throws {
        // Fetch existing price for this territory (if any) and compare against the target.
        let currentPriceStr = try await SubCommand.fetchCurrentPrice(
          subID: sub.id, territoryID: territoryID, client: client)
        let direction = SubCommand.priceDirection(
          current: currentPriceStr, target: point.attributes?.customerPrice)

        switch direction {
        case .unchanged:
          print()
          print("Already at \(point.attributes?.customerPrice ?? "?") \(currency ?? "") in \(territoryID). Nothing to do.")
          return
        case .increase:
          if preserveCurrent == nil {
            throw ValidationError(SubCommand.priceIncreaseGuidance(
              from: currentPriceStr, to: point.attributes?.customerPrice,
              currency: currency, territoryID: territoryID))
          }
        case .decrease:
          if autoConfirm && !confirmDecrease {
            throw ValidationError(SubCommand.priceDecreaseGuidance(
              from: currentPriceStr, to: point.attributes?.customerPrice,
              currency: currency, territoryID: territoryID))
          }
        case .new:
          break
        }

        print()
        print("Set price:")
        print("  Product ID:       \(productID)")
        print("  Territory:        \(territoryID)")
        if let cp = currentPriceStr {
          print("  Current Price:    \(cp) \(currency ?? "")")
        }
        print("  New Price:        \(point.attributes?.customerPrice ?? "—") \(currency ?? "") (\(direction.label))")
        if let startDate {
          print("  Start Date:       \(startDate)")
        } else {
          print("  Start Date:       Immediate")
        }
        if let p = preserveCurrent {
          print("  Preserve Current: \(p ? "Yes" : "No")")
        }
        if direction == .decrease {
          print()
          print(yellow("⚠ Price decrease:") + " all existing subscribers in \(territoryID) will move to the new lower price.")
        }
        print()

        guard confirm("Set this price? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        try await postSubscriptionPrice(
          subID: sub.id, territoryID: territoryID, pricePointID: point.id, client: client)

        print()
        print(green("Updated") + " price for '\(sub.attributes?.name ?? productID)' in \(territoryID).")
      }

      private func runEqualizeAllTerritories(
        sub: Subscription, sourceTerritory: String, sourcePoint: SubscriptionPricePoint,
        sourceCurrency: String?, client: AppStoreConnectClient
      ) async throws {
        // Fetch the equivalent price points for every territory by walking the
        // source point's equalizations. Each entry has its own territory + tier.
        var equalized: [SubscriptionPricePoint] = []
        for try await page in client.pages(
          Resources.v1.subscriptionPricePoints.id(sourcePoint.id).equalizations.get(
            limit: 200, include: [.territory]
          )
        ) {
          equalized.append(contentsOf: page.data)
        }

        // Make sure the source territory itself is included even if equalizations omit it.
        if !equalized.contains(where: {
          $0.relationships?.territory?.data?.id == sourceTerritory
        }) {
          equalized.insert(sourcePoint, at: 0)
        }

        // Fetch all current prices for the subscription so we can categorize per territory.
        let currentByTerritory = try await SubCommand.fetchCurrentPricesByTerritory(
          subID: sub.id, client: client)

        // Categorize each target territory
        struct Target {
          let territoryID: String
          let pricePointID: String
          let currentPrice: String?
          let newPrice: String?
          let direction: SubCommand.PriceDirection
        }
        var targets: [Target] = []
        for point in equalized {
          guard let territoryID = point.relationships?.territory?.data?.id else { continue }
          let current = currentByTerritory[territoryID]
          let newPrice = point.attributes?.customerPrice
          let direction = SubCommand.priceDirection(current: current, target: newPrice)
          targets.append(Target(
            territoryID: territoryID, pricePointID: point.id,
            currentPrice: current, newPrice: newPrice, direction: direction))
        }

        let increases = targets.filter { $0.direction == .increase }
        let decreases = targets.filter { $0.direction == .decrease }
        let news = targets.filter { $0.direction == .new }
        let unchanged = targets.filter { $0.direction == .unchanged }

        if !increases.isEmpty && preserveCurrent == nil {
          var msg = "\(increases.count) territor\(increases.count == 1 ? "y has" : "ies have") an existing price lower than the new equalized price (i.e. price increases).\n"
          msg += "You must explicitly choose how to handle existing subscribers across all increases:\n"
          msg += "  --preserve-current        Grandfather existing subscribers at their old price\n"
          msg += "  --no-preserve-current     Push the new price to existing subscribers (after Apple's notification period)\n"
          msg += "\nExample increases (first 5):\n"
          for t in increases.prefix(5) {
            msg += "  \(t.territoryID): \(t.currentPrice ?? "?") → \(t.newPrice ?? "?")\n"
          }
          throw ValidationError(msg)
        }

        if !decreases.isEmpty && autoConfirm && !confirmDecrease {
          var msg = "\(decreases.count) territor\(decreases.count == 1 ? "y" : "ies") will see a price decrease — existing subscribers will move to the lower price.\n"
          msg += "Plain --yes is not enough for price decreases. Add --confirm-decrease to acknowledge the revenue impact.\n"
          msg += "\nExample decreases (first 5):\n"
          for t in decreases.prefix(5) {
            msg += "  \(t.territoryID): \(t.currentPrice ?? "?") → \(t.newPrice ?? "?")\n"
          }
          throw ValidationError(msg)
        }

        let toApply = targets.filter { $0.direction != .unchanged }

        print()
        print("Equalize across all territories:")
        print("  Product ID:        \(productID)")
        print("  Source Territory:  \(sourceTerritory) at \(sourcePoint.attributes?.customerPrice ?? "?") \(sourceCurrency ?? "")")
        print("  Total territories: \(equalized.count)")
        print("    New:             \(news.count)")
        print("    Increases:       \(increases.count)")
        print("    Decreases:       \(decreases.count)")
        print("    Unchanged:       \(unchanged.count) (skipped)")
        if let startDate {
          print("  Start Date:        \(startDate)")
        } else {
          print("  Start Date:        Immediate")
        }
        if let p = preserveCurrent {
          print("  Preserve Current:  \(p ? "Yes" : "No")")
        }
        if !decreases.isEmpty {
          print()
          print(yellow("⚠ \(decreases.count) territor\(decreases.count == 1 ? "y" : "ies") will see a price decrease") + " — existing subscribers in those territories will move to the new lower price.")
        }
        print()
        print(yellow("Note:") + " This will issue \(toApply.count) API call\(toApply.count == 1 ? "" : "s") (one per territory that needs updating).")
        print()

        guard confirm("Apply equalized pricing? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        print()

        var succeeded = 0
        var failed = 0
        for target in toApply {
          do {
            try await postSubscriptionPrice(
              subID: sub.id, territoryID: target.territoryID,
              pricePointID: target.pricePointID, client: client)
            succeeded += 1
          } catch {
            print("  FAIL \(target.territoryID) — \(error.localizedDescription)")
            failed += 1
          }
        }

        print()
        print("Done. \(succeeded) territor\(succeeded == 1 ? "y" : "ies") updated, \(failed) failed, \(unchanged.count) unchanged (skipped).")
      }

      private func postSubscriptionPrice(
        subID: String, territoryID: String, pricePointID: String, client: AppStoreConnectClient
      ) async throws {
        _ = try await client.send(
          Resources.v1.subscriptionPrices.post(
            SubscriptionPriceCreateRequest(
              data: .init(
                attributes: .init(
                  startDate: startDate,
                  isPreserveCurrentPrice: preserveCurrent
                ),
                relationships: .init(
                  subscription: .init(data: .init(id: subID)),
                  territory: .init(data: .init(id: territoryID)),
                  subscriptionPricePoint: .init(data: .init(id: pricePointID))
                )
              )
            )
          )
        )
      }
    }
  }

  // MARK: - Availability

  struct Availability: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "availability",
      abstract: "View or update per-subscription territory availability.",
      discussion: """
        A subscription's availability is distinct from its app's. Use --add / --remove
        to change the per-subscription territory list. Each edit replaces the full
        availability schedule (wholesale POST).
        """
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Argument(help: "The product identifier of the subscription.")
    var productID: String

    @Option(name: .long, help: "Comma-separated territory codes to make available (e.g. CHN,RUS).")
    var add: String?

    @Option(name: .long, help: "Comma-separated territory codes to make unavailable.")
    var remove: String?

    @Option(name: .customLong("available-in-new-territories"), help: "Auto-enable new territories Apple adds (true/false). Defaults to keeping the current setting.")
    var availableInNewTerritories: String?

    @Flag(name: .long, help: "Show full country names.")
    var verbose = false

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let (sub, _) = try await SubCommand.findSubscription(
        productID: productID, appID: app.id, client: client)

      // Fetch current availability
      var currentAvailableInNew: Bool?
      var currentTerritories: [String] = []
      var hasAvailability = false
      do {
        let response = try await client.send(
          Resources.v1.subscriptions.id(sub.id).subscriptionAvailability.get(
            include: [.availableTerritories],
            limitAvailableTerritories: 50
          )
        )
        currentAvailableInNew = response.data.attributes?.isAvailableInNewTerritories
        hasAvailability = true
        for try await page in client.pages(
          Resources.v1.subscriptionAvailabilities.id(response.data.id).availableTerritories.get(limit: 200)
        ) {
          currentTerritories.append(contentsOf: page.data.map(\.id))
        }
      } catch is DecodingError {
        hasAvailability = false
      } catch let error as ResponseError {
        if case .requestFailure(_, let statusCode, _) = error, statusCode == 404 {
          hasAvailability = false
        } else {
          throw error
        }
      }

      let isEditMode = add != nil || remove != nil || availableInNewTerritories != nil

      let newAvailableInNewFlag: Bool?
      if let s = availableInNewTerritories {
        guard let b = Bool(s.lowercased()) else {
          throw ValidationError("Invalid value for --available-in-new-territories. Use 'true' or 'false'.")
        }
        newAvailableInNewFlag = b
      } else {
        newAvailableInNewFlag = nil
      }

      if !isEditMode {
        print("Product ID: \(productID)")
        if !hasAvailability {
          print(yellow("⚠ No per-subscription availability set — inherits the app's territories."))
          return
        }
        print("Available in new territories: \(currentAvailableInNew == true ? "Yes" : currentAvailableInNew == false ? "No" : "—")")
        print()
        let sorted = currentTerritories.sorted()
        print("Available (\(sorted.count)):")
        printTerritories(sorted)
        return
      }

      let addCodes = Swift.Set(add?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() } ?? [])
      let removeCodes = Swift.Set(remove?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() } ?? [])

      let overlap = addCodes.intersection(removeCodes)
      if !overlap.isEmpty {
        throw ValidationError("Territory codes in both --add and --remove: \(overlap.sorted().joined(separator: ", "))")
      }

      var newTerritories = Swift.Set(currentTerritories)
      newTerritories.formUnion(addCodes)
      newTerritories.subtract(removeCodes)

      let effectiveAvailableInNew = newAvailableInNewFlag ?? currentAvailableInNew ?? true
      let finalList = newTerritories.sorted()

      if finalList.isEmpty {
        throw ValidationError("Cannot have zero available territories — at least one is required.")
      }

      print("Product ID: \(productID)")
      print("Available in new territories: \(effectiveAvailableInNew ? "Yes" : "No")")
      let addedCodes = addCodes.subtracting(currentTerritories).sorted()
      let removedCodes = removeCodes.intersection(currentTerritories).sorted()
      if !addedCodes.isEmpty {
        print("Adding:    \(addedCodes.joined(separator: ", "))")
      }
      if !removedCodes.isEmpty {
        print("Removing:  \(removedCodes.joined(separator: ", "))")
      }
      if addedCodes.isEmpty && removedCodes.isEmpty && newAvailableInNewFlag == nil {
        print("No changes.")
        return
      }
      print("New total available: \(finalList.count) territor\(finalList.count == 1 ? "y" : "ies")")
      print()

      guard confirm("Apply this availability? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

      _ = try await client.send(
        Resources.v1.subscriptionAvailabilities.post(
          SubscriptionAvailabilityCreateRequest(
            data: .init(
              attributes: .init(isAvailableInNewTerritories: effectiveAvailableInNew),
              relationships: .init(
                subscription: .init(data: .init(id: sub.id)),
                availableTerritories: .init(data: finalList.map { .init(id: $0) })
              )
            )
          )
        )
      )

      print()
      print(green("Updated") + " availability for \(productID) (\(finalList.count) territories).")
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

  // MARK: - IntroOffer

  struct IntroOffer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "intro-offer",
      abstract: "Manage introductory offers for new subscribers (free trials and discounts).",
      subcommands: [List.self, Create.self, Update.self, Delete.self]
    )

    // MARK: List

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "List introductory offers on a subscription."
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
          productID: productID, appID: app.id, client: client)

        var offers: [SubscriptionIntroductoryOffer] = []
        var pricePoints: [String: SubscriptionPricePoint] = [:]
        for try await page in client.pages(
          Resources.v1.subscriptions.id(sub.id).introductoryOffers.get(
            limit: 200, include: [.subscriptionPricePoint, .territory]
          )
        ) {
          offers.append(contentsOf: page.data)
          for item in page.included ?? [] {
            if case .subscriptionPricePoint(let p) = item {
              pricePoints[p.id] = p
            }
          }
        }

        if offers.isEmpty {
          print("No introductory offers configured for \(productID).")
          return
        }

        Table.print(
          headers: ["ID", "Mode", "Duration", "Periods", "Territory", "Price", "Start", "End"],
          rows: offers.map { o in
            let attrs = o.attributes
            let territoryID = o.relationships?.territory?.data?.id ?? "Global"
            let pointID = o.relationships?.subscriptionPricePoint?.data?.id ?? ""
            let priceStr: String
            if attrs?.offerMode == .freeTrial {
              priceStr = "Free"
            } else {
              priceStr = pricePoints[pointID]?.attributes?.customerPrice ?? "—"
            }
            return [
              o.id,
              attrs?.offerMode.map { formatState($0) } ?? "—",
              attrs?.duration.map { formatState($0) } ?? "—",
              attrs?.numberOfPeriods.map { "\($0)" } ?? "—",
              territoryID,
              priceStr,
              attrs?.startDate ?? "—",
              attrs?.endDate ?? "—",
            ]
          }
        )
      }
    }

    // MARK: Create

    struct Create: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Create an introductory offer.",
        discussion: """
          Free trials don't need a price. Pay-as-you-go and pay-up-front modes need
          --price (in the territory's currency). Without --territory, the offer applies
          globally; with --territory, it's scoped to that one territory.
          """
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Option(name: .long, help: "Offer mode. Valid values: FREE_TRIAL, PAY_AS_YOU_GO, PAY_UP_FRONT.")
      var mode: String

      @Option(name: .long, help: "Duration. Valid values: THREE_DAYS, ONE_WEEK, TWO_WEEKS, ONE_MONTH, TWO_MONTHS, THREE_MONTHS, SIX_MONTHS, ONE_YEAR.")
      var duration: String

      @Option(name: .long, help: "Number of periods (e.g. 3 for three months at one-month duration).")
      var periods: Int

      @Option(name: .long, help: "Territory code. Omit for a global offer.")
      var territory: String?

      @Option(name: .long, help: "Customer price (required for PAY_AS_YOU_GO / PAY_UP_FRONT, not allowed for FREE_TRIAL).")
      var price: String?

      @Option(name: .long, help: "Start date in YYYY-MM-DD format (default: immediate).")
      var startDate: String?

      @Option(name: .long, help: "End date in YYYY-MM-DD format (default: open-ended).")
      var endDate: String?

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let (sub, _) = try await SubCommand.findSubscription(
          productID: productID, appID: app.id, client: client)

        let offerMode: SubscriptionOfferMode = try parseEnum(mode, name: "mode")
        let offerDuration: SubscriptionOfferDuration = try parseEnum(duration, name: "duration")
        guard periods > 0 else {
          throw ValidationError("--periods must be greater than 0.")
        }

        // Validate price is set when needed
        if offerMode == .freeTrial && price != nil {
          throw ValidationError("--price is not allowed for FREE_TRIAL mode.")
        }
        if (offerMode == .payAsYouGo || offerMode == .payUpFront) && price == nil {
          throw ValidationError("--price is required for \(offerMode.rawValue) mode.")
        }

        // Resolve price point if needed
        var pricePointID: String?
        var resolvedTerritoryID: String?
        let territoryForPriceLookup = (territory ?? "USA").uppercased()

        if let price = price {
          guard let target = Double(price.trimmingCharacters(in: .whitespaces)) else {
            throw ValidationError("Invalid price '\(price)'. Use a decimal number like 4.99.")
          }
          var tiers: [SubscriptionPricePoint] = []
          for try await page in client.pages(
            Resources.v1.subscriptions.id(sub.id).pricePoints.get(
              filterTerritory: [territoryForPriceLookup], limit: 200
            )
          ) {
            tiers.append(contentsOf: page.data)
          }
          guard !tiers.isEmpty else {
            throw ValidationError("No price tiers available for territory \(territoryForPriceLookup).")
          }
          guard let match = tiers.first(where: {
            guard let cp = $0.attributes?.customerPrice, let v = Double(cp) else { return false }
            return abs(v - target) < 0.001
          }) else {
            let nearest = tiers.compactMap { $0.attributes?.customerPrice }.prefix(5).joined(separator: ", ")
            throw ValidationError("No tier with customer price \(price) in \(territoryForPriceLookup). Nearby tiers: \(nearest)")
          }
          pricePointID = match.id
          // If user explicitly set --territory, scope the offer to that territory.
          // Otherwise, leave territory unset → offer is global with this territory's price as the equalization base.
          if territory != nil {
            resolvedTerritoryID = territoryForPriceLookup
          }
        } else if territory != nil {
          // --territory without --price means a free-trial scoped to that territory
          resolvedTerritoryID = territoryForPriceLookup
        }

        // Summary
        print()
        print("Create introductory offer:")
        print("  Subscription:   \(productID)")
        print("  Mode:           \(formatState(offerMode))")
        print("  Duration:       \(periods) × \(formatState(offerDuration))")
        print("  Territory:      \(resolvedTerritoryID ?? "Global")")
        if let price { print("  Price:          \(price)") }
        if let startDate { print("  Start Date:     \(startDate)") }
        if let endDate { print("  End Date:       \(endDate)") }
        print()

        guard confirm("Create this offer? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        let territoryRel: SubscriptionIntroductoryOfferCreateRequest.Data.Relationships.Territory?
        if let id = resolvedTerritoryID {
          territoryRel = .init(data: .init(id: id))
        } else {
          territoryRel = nil
        }

        let pricePointRel: SubscriptionIntroductoryOfferCreateRequest.Data.Relationships.SubscriptionPricePoint?
        if let id = pricePointID {
          pricePointRel = .init(data: .init(id: id))
        } else {
          pricePointRel = nil
        }

        let response = try await client.send(
          Resources.v1.subscriptionIntroductoryOffers.post(
            SubscriptionIntroductoryOfferCreateRequest(
              data: .init(
                attributes: .init(
                  startDate: startDate,
                  endDate: endDate,
                  duration: offerDuration,
                  offerMode: offerMode,
                  numberOfPeriods: periods
                ),
                relationships: .init(
                  subscription: .init(data: .init(id: sub.id)),
                  territory: territoryRel,
                  subscriptionPricePoint: pricePointRel
                )
              )
            )
          )
        )

        print()
        print(green("Created") + " introductory offer (id: \(response.data.id)).")
      }
    }

    // MARK: Update

    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Update an introductory offer's end date.",
        discussion: "Only the end date can be updated. To change other fields, delete and recreate."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Argument(help: "The introductory offer ID (from `intro-offer list`).")
      var offerID: String

      @Option(name: .long, help: "New end date in YYYY-MM-DD format. Use empty string to clear.")
      var endDate: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()

        print("Update introductory offer \(offerID):")
        print("  New End Date: \(endDate.isEmpty ? "(cleared)" : endDate)")
        print()

        guard confirm("Apply update? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        _ = try await client.send(
          Resources.v1.subscriptionIntroductoryOffers.id(offerID).patch(
            SubscriptionIntroductoryOfferUpdateRequest(
              data: .init(
                id: offerID,
                attributes: .init(endDate: endDate.isEmpty ? nil : endDate)
              )
            )
          )
        )

        print()
        print(green("Updated") + " introductory offer end date.")
      }
    }

    // MARK: Delete

    struct Delete: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Delete an introductory offer."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Argument(help: "The introductory offer ID (from `intro-offer list`).")
      var offerID: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()

        guard confirm("Delete introductory offer \(offerID)? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        _ = try await client.send(
          Resources.v1.subscriptionIntroductoryOffers.id(offerID).delete
        )

        print()
        print(green("Deleted") + " introductory offer \(offerID).")
      }
    }
  }

  // MARK: - OfferCode

  struct OfferCode: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "offer-code",
      abstract: "Manage offer codes for subscriptions.",
      subcommands: [List.self, Info.self, Create.self, Toggle.self, GenCodes.self, AddCustomCodes.self, ViewCodes.self]
    )

    // MARK: List

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "List offer codes for a subscription."
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
          productID: productID, appID: app.id, client: client)

        var codes: [SubscriptionOfferCode] = []
        for try await page in client.pages(
          Resources.v1.subscriptions.id(sub.id).offerCodes.get(limit: 200)
        ) {
          codes.append(contentsOf: page.data)
        }

        if codes.isEmpty {
          print("No offer codes for \(productID).")
          return
        }

        Table.print(
          headers: ["ID", "Name", "Active", "Mode", "Duration", "Periods", "Eligibilities"],
          rows: codes.map { c in
            let attrs = c.attributes
            let elig = attrs?.customerEligibilities?.map { $0.rawValue }.joined(separator: ", ") ?? "—"
            return [
              c.id,
              attrs?.name ?? "—",
              attrs?.isActive == true ? "Yes" : attrs?.isActive == false ? "No" : "—",
              attrs?.offerMode.map { formatState($0) } ?? "—",
              attrs?.duration.map { formatState($0) } ?? "—",
              attrs?.numberOfPeriods.map { "\($0)" } ?? "—",
              elig,
            ]
          }
        )
      }
    }

    // MARK: Info

    struct Info: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Show details for an offer code."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Argument(help: "The offer code ID (from `offer-code list`).")
      var offerCodeID: String

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        _ = try await SubCommand.findSubscription(
          productID: productID, appID: app.id, client: client)

        let response = try await client.send(
          Resources.v1.subscriptionOfferCodes.id(offerCodeID).get(
            include: [.prices, .oneTimeUseCodes, .customCodes],
            limitCustomCodes: 50,
            limitOneTimeUseCodes: 50,
            limitPrices: 200
          )
        )
        let attrs = response.data.attributes
        print("Offer Code:    \(attrs?.name ?? "—")")
        print("ID:            \(response.data.id)")
        print("Active:        \(attrs?.isActive == true ? "Yes" : attrs?.isActive == false ? "No" : "—")")
        print("Eligibilities: \(attrs?.customerEligibilities?.map { $0.rawValue }.joined(separator: ", ") ?? "—")")
        print("Offer Eligib:  \(attrs?.offerEligibility.map { formatState($0) } ?? "—")")
        print("Duration:      \(attrs?.numberOfPeriods.map { "\($0)" } ?? "—") × \(attrs?.duration.map { formatState($0) } ?? "—")")
        print("Mode:          \(attrs?.offerMode.map { formatState($0) } ?? "—")")
        print("Auto-Renew:    \(attrs?.isAutoRenewEnabled == true ? "Yes" : attrs?.isAutoRenewEnabled == false ? "No" : "—")")

        let priceCount = response.data.relationships?.prices?.data?.count ?? 0
        let oneTimeCount = response.data.relationships?.oneTimeUseCodes?.data?.count ?? 0
        let customCount = response.data.relationships?.customCodes?.data?.count ?? 0
        print()
        print("Prices:                 \(priceCount) territor\(priceCount == 1 ? "y" : "ies")")
        print("One-Time Code Batches:  \(oneTimeCount)")
        print("Custom Codes:           \(customCount)")
        print("Total Codes:   prod=\(attrs?.productionCodeCount ?? 0), sandbox=\(attrs?.sandboxCodeCount ?? 0)")
      }
    }

    // MARK: Create

    struct Create: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Create an offer code with prices.",
        discussion: """
          Either set --price + --territory for a single-territory price, or use
          --equalize-all-territories to fan the price out across every territory using
          local-currency tier equivalents.
          """
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Option(name: .long, help: "Reference name for this offer code.")
      var name: String

      @Option(name: .long, help: "Comma-separated customer eligibilities. Valid values: NEW, EXISTING, EXPIRED.")
      var eligibility: String

      @Option(name: .customLong("offer-eligibility"), help: "How this offer interacts with intro offers. Valid values: STACK_WITH_INTRO_OFFERS, REPLACE_INTRO_OFFERS.")
      var offerEligibility: String

      @Option(name: .long, help: "Offer mode. Valid values: FREE_TRIAL, PAY_AS_YOU_GO, PAY_UP_FRONT.")
      var mode: String

      @Option(name: .long, help: "Duration. Valid values: THREE_DAYS, ONE_WEEK, TWO_WEEKS, ONE_MONTH, TWO_MONTHS, THREE_MONTHS, SIX_MONTHS, ONE_YEAR.")
      var duration: String

      @Option(name: .long, help: "Number of periods.")
      var periods: Int

      @Flag(name: .customLong("auto-renew"), inversion: .prefixedNo, help: "Whether the subscription auto-renews after the offer ends. Defaults to API default.")
      var autoRenew: Bool?

      @Option(name: .long, help: "Customer price (in territory's currency, e.g. 0.99).")
      var price: String

      @Option(name: .long, help: "Territory code (default: USA). Used for price lookup and as the source for equalization.")
      var territory: String = "USA"

      @Flag(name: .customLong("equalize-all-territories"), help: "Fan the price out across every territory using local-currency tier equivalents.")
      var equalizeAllTerritories = false

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let (sub, _) = try await SubCommand.findSubscription(
          productID: productID, appID: app.id, client: client)

        let eligibilities: [SubscriptionCustomerEligibility] = try eligibility
          .split(separator: ",")
          .map { $0.trimmingCharacters(in: .whitespaces) }
          .map { try parseEnum($0, name: "eligibility") }
        guard !eligibilities.isEmpty else {
          throw ValidationError("--eligibility cannot be empty.")
        }
        let offerElig: SubscriptionOfferEligibility = try parseEnum(offerEligibility, name: "offer-eligibility")
        let offerMode: SubscriptionOfferMode = try parseEnum(mode, name: "mode")
        let offerDuration: SubscriptionOfferDuration = try parseEnum(duration, name: "duration")
        guard periods > 0 else {
          throw ValidationError("--periods must be greater than 0.")
        }

        let territoryID = territory.uppercased()
        let resolved = try await SubCommand.resolveSubOfferPrices(
          subID: sub.id, sourceTerritory: territoryID, customerPrice: price,
          equalize: equalizeAllTerritories, client: client)

        print()
        print("Create offer code:")
        print("  Subscription:      \(productID)")
        print("  Name:              \(name)")
        print("  Eligibilities:     \(eligibilities.map { $0.rawValue }.joined(separator: ", "))")
        print("  Offer Eligibility: \(formatState(offerElig))")
        print("  Mode:              \(formatState(offerMode))")
        print("  Duration:          \(periods) × \(formatState(offerDuration))")
        if let autoRenew { print("  Auto-Renew:        \(autoRenew ? "Yes" : "No")") }
        print("  Source Tier:       \(resolved.sourceCustomerPrice) \(resolved.sourceCurrency ?? "") (\(territoryID))")
        print("  Territories:       \(resolved.entries.count)\(resolved.isEqualized ? " (equalized)" : " (single)")")
        print()

        guard confirm("Create this offer code? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        // Build inline price entries
        var inlines: [SubscriptionOfferCodePriceInlineCreate] = []
        var refs: [SubscriptionOfferCodeCreateRequest.Data.Relationships.Prices.Datum] = []
        for (i, entry) in resolved.entries.enumerated() {
          let localID = "${price\(i)}"
          inlines.append(
            SubscriptionOfferCodePriceInlineCreate(
              id: localID,
              relationships: .init(
                territory: .init(data: .init(id: entry.territoryID)),
                subscriptionPricePoint: .init(data: .init(id: entry.pricePointID))
              )
            )
          )
          refs.append(.init(id: localID))
        }

        let response = try await client.send(
          Resources.v1.subscriptionOfferCodes.post(
            SubscriptionOfferCodeCreateRequest(
              data: .init(
                attributes: .init(
                  name: name,
                  customerEligibilities: eligibilities,
                  offerEligibility: offerElig,
                  duration: offerDuration,
                  offerMode: offerMode,
                  numberOfPeriods: periods,
                  isAutoRenewEnabled: autoRenew
                ),
                relationships: .init(
                  subscription: .init(data: .init(id: sub.id)),
                  prices: .init(data: refs)
                )
              ),
              included: inlines
            )
          )
        )

        print()
        print(green("Created") + " offer code '\(name)' (id: \(response.data.id)).")
      }
    }

    // MARK: Toggle

    struct Toggle: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Activate or deactivate an offer code."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Argument(help: "The offer code ID.")
      var offerCodeID: String

      @Option(name: .long, help: "Set active state (true or false).")
      var active: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        guard let activeBool = Bool(active.lowercased()) else {
          throw ValidationError("--active must be 'true' or 'false'.")
        }
        let client = try ClientFactory.makeClient()
        _ = try await findApp(bundleID: bundleID, client: client)

        guard confirm("Set offer code \(offerCodeID) active=\(activeBool)? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        _ = try await client.send(
          Resources.v1.subscriptionOfferCodes.id(offerCodeID).patch(
            SubscriptionOfferCodeUpdateRequest(
              data: .init(id: offerCodeID, attributes: .init(isActive: activeBool))
            )
          )
        )
        print()
        print(green("Updated") + " offer code \(offerCodeID) (active=\(activeBool)).")
      }
    }

    // MARK: GenCodes (one-time-use)

    struct GenCodes: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "gen-codes",
        abstract: "Generate a batch of one-time-use codes for an offer code."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Argument(help: "The offer code ID to generate codes against.")
      var offerCodeID: String

      @Option(name: .long, help: "Number of codes to generate.")
      var count: Int

      @Option(name: .long, help: "Expiration date in YYYY-MM-DD format.")
      var expires: String

      @Option(name: .long, help: "Environment. Valid values: PRODUCTION, SANDBOX. Defaults to PRODUCTION.")
      var environment: String?

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        guard count > 0 else {
          throw ValidationError("--count must be greater than 0.")
        }
        let env: OfferCodeEnvironment? = try environment.map {
          try parseEnum($0, name: "environment")
        }
        let client = try ClientFactory.makeClient()
        _ = try await findApp(bundleID: bundleID, client: client)

        print("Generate \(count) one-time-use code(s):")
        print("  Offer Code ID: \(offerCodeID)")
        print("  Expires:       \(expires)")
        print("  Environment:   \(env.map { $0.rawValue } ?? "PRODUCTION (default)")")
        print()

        guard confirm("Generate? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        let response = try await client.send(
          Resources.v1.subscriptionOfferCodeOneTimeUseCodes.post(
            SubscriptionOfferCodeOneTimeUseCodeCreateRequest(
              data: .init(
                attributes: .init(
                  numberOfCodes: count,
                  expirationDate: expires,
                  environment: env
                ),
                relationships: .init(
                  offerCode: .init(data: .init(id: offerCodeID))
                )
              )
            )
          )
        )

        let batchID = response.data.id
        print()
        print(green("Created") + " one-time-use code batch (id: \(batchID)).")
        print()
        print("Codes are generated asynchronously. Fetch with:")
        print("  ascelerate sub offer-code view-codes \(batchID)")
      }
    }

    // MARK: AddCustomCodes

    struct AddCustomCodes: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "add-custom-codes",
        abstract: "Add a custom code (e.g. PROMO2026) to an offer code."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Argument(help: "The offer code ID.")
      var offerCodeID: String

      @Option(name: .long, help: "The custom code string (e.g. 'PROMO2026').")
      var code: String

      @Option(name: .long, help: "Total number of times this code can be redeemed.")
      var count: Int

      @Option(name: .long, help: "Optional expiration date in YYYY-MM-DD format.")
      var expires: String?

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        guard count > 0 else {
          throw ValidationError("--count must be greater than 0.")
        }
        let client = try ClientFactory.makeClient()
        _ = try await findApp(bundleID: bundleID, client: client)

        print("Add custom code:")
        print("  Offer Code ID: \(offerCodeID)")
        print("  Code:          \(code)")
        print("  Redemptions:   \(count)")
        if let expires { print("  Expires:       \(expires)") }
        print()

        guard confirm("Create? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        let response = try await client.send(
          Resources.v1.subscriptionOfferCodeCustomCodes.post(
            SubscriptionOfferCodeCustomCodeCreateRequest(
              data: .init(
                attributes: .init(
                  customCode: code,
                  numberOfCodes: count,
                  expirationDate: expires
                ),
                relationships: .init(
                  offerCode: .init(data: .init(id: offerCodeID))
                )
              )
            )
          )
        )

        print()
        print(green("Created") + " custom code '\(code)' (id: \(response.data.id)).")
      }
    }

    // MARK: ViewCodes

    struct ViewCodes: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "view-codes",
        abstract: "Print the actual one-time-use code values for a generated batch.",
        discussion: """
          The codes are generated asynchronously after `gen-codes`. If the batch isn't ready
          yet, the response will be empty — wait a few seconds and try again.
          """
      )

      @Argument(help: "The one-time-use code batch ID (returned by `gen-codes`).")
      var batchID: String

      @Option(name: .long, help: "Optional output file. If omitted, prints to stdout.")
      var output: String?

      func run() async throws {
        let client = try ClientFactory.makeClient()

        let raw = try await client.send(
          Resources.v1.subscriptionOfferCodeOneTimeUseCodes.id(batchID).values.get
        )

        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          print(yellow("⚠ No codes returned. Generation may still be in progress; retry in a few seconds."))
          return
        }

        if let output {
          let path = expandPath(confirmOutputPath(output, isDirectory: false))
          try raw.write(toFile: path, atomically: true, encoding: .utf8)
          let lineCount = raw.split(separator: "\n").count
          print(green("Wrote") + " \(lineCount) code(s) to \(path).")
        } else {
          print(raw)
        }
      }
    }
  }

  // MARK: - PromoOffer

  struct PromoOffer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "promo-offer",
      abstract: "Manage promotional offers (server-signed offers for existing subscribers).",
      subcommands: [List.self, Info.self, Create.self, Update.self, Delete.self]
    )

    // MARK: List

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "List promotional offers on a subscription."
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
          productID: productID, appID: app.id, client: client)

        var offers: [SubscriptionPromotionalOffer] = []
        for try await page in client.pages(
          Resources.v1.subscriptions.id(sub.id).promotionalOffers.get(limit: 200)
        ) {
          offers.append(contentsOf: page.data)
        }

        if offers.isEmpty {
          print("No promotional offers for \(productID).")
          return
        }

        Table.print(
          headers: ["ID", "Name", "Offer Code", "Mode", "Duration", "Periods"],
          rows: offers.map { o in
            let attrs = o.attributes
            return [
              o.id,
              attrs?.name ?? "—",
              attrs?.offerCode ?? "—",
              attrs?.offerMode.map { formatState($0) } ?? "—",
              attrs?.duration.map { formatState($0) } ?? "—",
              attrs?.numberOfPeriods.map { "\($0)" } ?? "—",
            ]
          }
        )
      }
    }

    // MARK: Info

    struct Info: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Show details for a promotional offer."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Argument(help: "The promotional offer ID.")
      var offerID: String

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        _ = try await SubCommand.findSubscription(
          productID: productID, appID: app.id, client: client)

        let response = try await client.send(
          Resources.v1.subscriptionPromotionalOffers.id(offerID).get(
            include: [.prices], limitPrices: 200
          )
        )
        let attrs = response.data.attributes
        print("Promotional Offer: \(attrs?.name ?? "—")")
        print("ID:                \(response.data.id)")
        print("Offer Code:        \(attrs?.offerCode ?? "—")")
        print("Mode:              \(attrs?.offerMode.map { formatState($0) } ?? "—")")
        print("Duration:          \(attrs?.numberOfPeriods.map { "\($0)" } ?? "—") × \(attrs?.duration.map { formatState($0) } ?? "—")")
        let priceCount = response.data.relationships?.prices?.data?.count ?? 0
        print("Prices:            \(priceCount) territor\(priceCount == 1 ? "y" : "ies")")
      }
    }

    // MARK: Create

    struct Create: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Create a promotional offer.",
        discussion: """
          The --code value is the unique offer code your app passes when redeeming the
          offer in StoreKit. It must be embedded in the signed payload your server
          generates at runtime. Either set --price + --territory for a single-territory
          price, or use --equalize-all-territories to fan it out using local-currency
          tier equivalents.
          """
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Option(name: .long, help: "Reference name for this offer.")
      var name: String

      @Option(name: .long, help: "Offer code identifier (must be unique within the subscription).")
      var code: String

      @Option(name: .long, help: "Offer mode. Valid values: FREE_TRIAL, PAY_AS_YOU_GO, PAY_UP_FRONT.")
      var mode: String

      @Option(name: .long, help: "Duration. Valid values: THREE_DAYS, ONE_WEEK, TWO_WEEKS, ONE_MONTH, TWO_MONTHS, THREE_MONTHS, SIX_MONTHS, ONE_YEAR.")
      var duration: String

      @Option(name: .long, help: "Number of periods.")
      var periods: Int

      @Option(name: .long, help: "Customer price (in territory's currency, e.g. 0.99).")
      var price: String

      @Option(name: .long, help: "Territory code (default: USA). Used for price lookup and as the source for equalization.")
      var territory: String = "USA"

      @Flag(name: .customLong("equalize-all-territories"), help: "Fan the price out across every territory using local-currency tier equivalents.")
      var equalizeAllTerritories = false

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let (sub, _) = try await SubCommand.findSubscription(
          productID: productID, appID: app.id, client: client)

        let offerMode: SubscriptionOfferMode = try parseEnum(mode, name: "mode")
        let offerDuration: SubscriptionOfferDuration = try parseEnum(duration, name: "duration")
        guard periods > 0 else {
          throw ValidationError("--periods must be greater than 0.")
        }

        let territoryID = territory.uppercased()
        let resolved = try await SubCommand.resolveSubOfferPrices(
          subID: sub.id, sourceTerritory: territoryID, customerPrice: price,
          equalize: equalizeAllTerritories, client: client)

        print()
        print("Create promotional offer:")
        print("  Subscription:  \(productID)")
        print("  Name:          \(name)")
        print("  Offer Code:    \(code)")
        print("  Mode:          \(formatState(offerMode))")
        print("  Duration:      \(periods) × \(formatState(offerDuration))")
        print("  Source Tier:   \(resolved.sourceCustomerPrice) \(resolved.sourceCurrency ?? "") (\(territoryID))")
        print("  Territories:   \(resolved.entries.count)\(resolved.isEqualized ? " (equalized)" : " (single)")")
        print()

        guard confirm("Create this promotional offer? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        var inlines: [SubscriptionPromotionalOfferPriceInlineCreate] = []
        var refs: [SubscriptionPromotionalOfferCreateRequest.Data.Relationships.Prices.Datum] = []
        for (i, entry) in resolved.entries.enumerated() {
          let localID = "${price\(i)}"
          inlines.append(
            SubscriptionPromotionalOfferPriceInlineCreate(
              id: localID,
              relationships: .init(
                territory: .init(data: .init(id: entry.territoryID)),
                subscriptionPricePoint: .init(data: .init(id: entry.pricePointID))
              )
            )
          )
          refs.append(.init(id: localID))
        }

        let response = try await client.send(
          Resources.v1.subscriptionPromotionalOffers.post(
            SubscriptionPromotionalOfferCreateRequest(
              data: .init(
                attributes: .init(
                  duration: offerDuration,
                  name: name,
                  numberOfPeriods: periods,
                  offerCode: code,
                  offerMode: offerMode
                ),
                relationships: .init(
                  subscription: .init(data: .init(id: sub.id)),
                  prices: .init(data: refs)
                )
              ),
              included: inlines
            )
          )
        )

        print()
        print(green("Created") + " promotional offer '\(name)' (id: \(response.data.id)).")
      }
    }

    // MARK: Update

    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Update a promotional offer's prices.",
        discussion: "Only prices can be changed. Other attributes require delete + recreate."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Argument(help: "The promotional offer ID.")
      var offerID: String

      @Option(name: .long, help: "New customer price.")
      var price: String

      @Option(name: .long, help: "Territory code (default: USA).")
      var territory: String = "USA"

      @Flag(name: .customLong("equalize-all-territories"), help: "Fan the price out across every territory.")
      var equalizeAllTerritories = false

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let (sub, _) = try await SubCommand.findSubscription(
          productID: productID, appID: app.id, client: client)

        let territoryID = territory.uppercased()
        let resolved = try await SubCommand.resolveSubOfferPrices(
          subID: sub.id, sourceTerritory: territoryID, customerPrice: price,
          equalize: equalizeAllTerritories, client: client)

        print()
        print("Update promotional offer prices:")
        print("  Offer ID:      \(offerID)")
        print("  New Source:    \(resolved.sourceCustomerPrice) \(resolved.sourceCurrency ?? "") (\(territoryID))")
        print("  Territories:   \(resolved.entries.count)\(resolved.isEqualized ? " (equalized)" : " (single)")")
        print()

        guard confirm("Apply update? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        var inlines: [SubscriptionPromotionalOfferPriceInlineCreate] = []
        var refs: [SubscriptionPromotionalOfferUpdateRequest.Data.Relationships.Prices.Datum] = []
        for (i, entry) in resolved.entries.enumerated() {
          let localID = "${price\(i)}"
          inlines.append(
            SubscriptionPromotionalOfferPriceInlineCreate(
              id: localID,
              relationships: .init(
                territory: .init(data: .init(id: entry.territoryID)),
                subscriptionPricePoint: .init(data: .init(id: entry.pricePointID))
              )
            )
          )
          refs.append(.init(id: localID))
        }

        _ = try await client.send(
          Resources.v1.subscriptionPromotionalOffers.id(offerID).patch(
            SubscriptionPromotionalOfferUpdateRequest(
              data: .init(
                id: offerID,
                relationships: .init(prices: .init(data: refs))
              ),
              included: inlines
            )
          )
        )

        print()
        print(green("Updated") + " promotional offer prices.")
      }
    }

    // MARK: Delete

    struct Delete: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Delete a promotional offer."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Argument(help: "The promotional offer ID.")
      var offerID: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()

        guard confirm("Delete promotional offer \(offerID)? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        _ = try await client.send(
          Resources.v1.subscriptionPromotionalOffers.id(offerID).delete
        )
        print()
        print(green("Deleted") + " promotional offer \(offerID).")
      }
    }
  }

  // MARK: - SubmitGroup

  struct SubmitGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "submit-group",
      abstract: "Submit a subscription group for review."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let group = try await SubCommand.pickGroup(appID: app.id, client: client)

      print()
      print("Submit subscription group for review:")
      print("  Group:         \(group.name)")
      print("  Subscriptions: \(group.subscriptions.count)")
      print()
      print(yellow("Note:") + " Subscription groups are reviewed alongside the next app version.")
      print()

      guard confirm("Submit group '\(group.name)' for review? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

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

      print()
      print(green("Submitted") + " group '\(group.name)' for review.")
    }
  }

  // MARK: - Images

  struct Images: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "images",
      abstract: "Manage promotional images for a subscription.",
      subcommands: [List.self, Upload.self, Delete.self]
    )

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "List uploaded images for a subscription."
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
          productID: productID, appID: app.id, client: client)

        var images: [SubscriptionImage] = []
        for try await page in client.pages(
          Resources.v1.subscriptions.id(sub.id).images.get(limit: 50)
        ) {
          images.append(contentsOf: page.data)
        }

        if images.isEmpty {
          print("No images uploaded for \(productID).")
          return
        }

        Table.print(
          headers: ["ID", "File", "Size", "State"],
          rows: images.map { img in
            [
              img.id,
              img.attributes?.fileName ?? "—",
              img.attributes?.fileSize.map { formatBytes($0) } ?? "—",
              img.attributes?.state.map { formatState($0) } ?? "—",
            ]
          }
        )
      }
    }

    struct Upload: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Upload a promotional image (.png or .jpg) for a subscription."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Argument(help: "Path to the image file.",
                completion: .file(extensions: ["png", "jpg", "jpeg"]))
      var file: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let (sub, _) = try await SubCommand.findSubscription(
          productID: productID, appID: app.id, client: client)

        let path = expandPath(file)
        let url = URL(fileURLWithPath: path)
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let fileSize = (attrs[.size] as? Int) ?? 0
        let fileName = url.lastPathComponent

        print("Upload image:")
        print("  Subscription: \(productID)")
        print("  File:         \(fileName)")
        print("  Size:         \(formatBytes(fileSize))")
        print()

        guard confirm("Upload? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        let createResponse = try await client.send(
          Resources.v1.subscriptionImages.post(
            SubscriptionImageCreateRequest(
              data: .init(
                attributes: .init(fileSize: fileSize, fileName: fileName),
                relationships: .init(subscription: .init(data: .init(id: sub.id)))
              )
            )
          )
        )
        let imageID = createResponse.data.id
        let operations = createResponse.data.attributes?.uploadOperations ?? []
        guard !operations.isEmpty else {
          throw MediaUploadError.noUploadOperations
        }

        try await uploadChunks(filePath: path, operations: operations)
        let md5 = try md5Hex(filePath: path)

        _ = try await client.send(
          Resources.v1.subscriptionImages.id(imageID).patch(
            SubscriptionImageUpdateRequest(
              data: .init(
                id: imageID,
                attributes: .init(sourceFileChecksum: md5, isUploaded: true)
              )
            )
          )
        )

        print()
        print(green("Uploaded") + " \(fileName) (id: \(imageID)).")
      }
    }

    struct Delete: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Delete an uploaded image."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Argument(help: "The image ID (from `images list`).")
      var imageID: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        _ = try await findApp(bundleID: bundleID, client: client)

        guard confirm("Delete image \(imageID)? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        _ = try await client.send(
          Resources.v1.subscriptionImages.id(imageID).delete
        )
        print()
        print(green("Deleted") + " image \(imageID).")
      }
    }
  }

  // MARK: - ReviewScreenshot

  struct ReviewScreenshot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "review-screenshot",
      abstract: "Manage the App Review screenshot for a subscription (one per sub).",
      subcommands: [View.self, Upload.self, Delete.self]
    )

    struct View: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Show the current App Review screenshot."
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
          productID: productID, appID: app.id, client: client)

        do {
          let response = try await client.send(
            Resources.v1.subscriptions.id(sub.id).appStoreReviewScreenshot.get()
          )
          let attrs = response.data.attributes
          print("Review Screenshot:")
          print("  ID:    \(response.data.id)")
          print("  File:  \(attrs?.fileName ?? "—")")
          print("  Size:  \(attrs?.fileSize.map { formatBytes($0) } ?? "—")")
          print("  State: \(attrs?.assetDeliveryState?.state.map { formatState($0) } ?? "—")")
        } catch is DecodingError {
          print("No review screenshot uploaded for \(productID).")
        } catch let error as ResponseError {
          if case .requestFailure(_, let statusCode, _) = error, statusCode == 404 {
            print("No review screenshot uploaded for \(productID).")
          } else {
            throw error
          }
        }
      }
    }

    struct Upload: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Upload an App Review screenshot. Replaces any existing one."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Argument(help: "Path to the screenshot file (.png, .jpg).",
                completion: .file(extensions: ["png", "jpg", "jpeg"]))
      var file: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let (sub, _) = try await SubCommand.findSubscription(
          productID: productID, appID: app.id, client: client)

        let path = expandPath(file)
        let url = URL(fileURLWithPath: path)
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let fileSize = (attrs[.size] as? Int) ?? 0
        let fileName = url.lastPathComponent

        print("Upload review screenshot:")
        print("  Subscription: \(productID)")
        print("  File:         \(fileName)")
        print("  Size:         \(formatBytes(fileSize))")
        print()

        guard confirm("Upload? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        let createResponse = try await client.send(
          Resources.v1.subscriptionAppStoreReviewScreenshots.post(
            SubscriptionAppStoreReviewScreenshotCreateRequest(
              data: .init(
                attributes: .init(fileSize: fileSize, fileName: fileName),
                relationships: .init(subscription: .init(data: .init(id: sub.id)))
              )
            )
          )
        )
        let screenshotID = createResponse.data.id
        let operations = createResponse.data.attributes?.uploadOperations ?? []
        guard !operations.isEmpty else {
          throw MediaUploadError.noUploadOperations
        }

        try await uploadChunks(filePath: path, operations: operations)
        let md5 = try md5Hex(filePath: path)

        _ = try await client.send(
          Resources.v1.subscriptionAppStoreReviewScreenshots.id(screenshotID).patch(
            SubscriptionAppStoreReviewScreenshotUpdateRequest(
              data: .init(
                id: screenshotID,
                attributes: .init(sourceFileChecksum: md5, isUploaded: true)
              )
            )
          )
        )

        print()
        print(green("Uploaded") + " review screenshot (id: \(screenshotID)).")
      }
    }

    struct Delete: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Delete the App Review screenshot."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let (sub, _) = try await SubCommand.findSubscription(
          productID: productID, appID: app.id, client: client)

        let response = try await client.send(
          Resources.v1.subscriptions.id(sub.id).appStoreReviewScreenshot.get()
        )
        let screenshotID = response.data.id

        guard confirm("Delete review screenshot for \(productID)? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        _ = try await client.send(
          Resources.v1.subscriptionAppStoreReviewScreenshots.id(screenshotID).delete
        )
        print()
        print(green("Deleted") + " review screenshot.")
      }
    }
  }
}
