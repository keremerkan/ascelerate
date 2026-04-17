import AppStoreAPI
import AppStoreConnect
import ArgumentParser
import Foundation

struct IAPCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "iap",
    abstract: "Manage in-app purchases.",
    subcommands: [List.self, Info.self, Promoted.self, Create.self, Update.self, Delete.self, Submit.self, Localizations.self, Pricing.self]
  )

  // MARK: - Helpers

  static func findIAP(
    productID: String, appID: String, client: AppStoreConnectClient
  ) async throws -> InAppPurchaseV2 {
    let response = try await client.send(
      Resources.v1.apps.id(appID).inAppPurchasesV2.get(filterProductID: [productID])
    )
    guard let iap = response.data.first else {
      throw ValidationError("No in-app purchase found with product ID '\(productID)'.")
    }
    return iap
  }

  /// Returns true if the IAP has a price schedule. Returns false if the API responds with
  /// 404 or null `data` (decoded as DecodingError) — both indicate no schedule.
  static func iapPriceScheduleExists(
    iapID: String, client: AppStoreConnectClient
  ) async throws -> Bool {
    do {
      _ = try await client.send(
        Resources.v2.inAppPurchases.id(iapID).iapPriceSchedule.get()
      )
      return true
    } catch is DecodingError {
      return false
    } catch let error as ResponseError {
      if case .requestFailure(_, let statusCode, _) = error, statusCode == 404 {
        return false
      }
      throw error
    }
  }

  static let missingScheduleWarning =
    "⚠ No price schedule set — product cannot be submitted. Use 'iap pricing set ...' to configure."

  /// One manual-price entry: the territory and the price point it references.
  struct ManualPriceEntry: Sendable {
    let territoryID: String
    let pricePointID: String
  }

  /// Snapshot of an existing IAP price schedule.
  struct ExistingSchedule: Sendable {
    let baseTerritoryID: String
    let manualPrices: [ManualPriceEntry]  // includes the base territory entry

    var nonBaseOverrides: [ManualPriceEntry] {
      manualPrices.filter { $0.territoryID != baseTerritoryID }
    }

    var basePriceEntry: ManualPriceEntry? {
      manualPrices.first { $0.territoryID == baseTerritoryID }
    }
  }

  /// Fetches the IAP's current price schedule with all manual prices and their territories.
  /// Returns nil if no schedule exists (404 or null data).
  static func fetchExistingSchedule(
    iapID: String, client: AppStoreConnectClient
  ) async throws -> ExistingSchedule? {
    let scheduleResponse: InAppPurchasePriceScheduleResponse
    do {
      scheduleResponse = try await client.send(
        Resources.v2.inAppPurchases.id(iapID).iapPriceSchedule.get(
          fieldsInAppPurchasePriceSchedules: [.baseTerritory, .manualPrices],
          include: [.baseTerritory]
        )
      )
    } catch is DecodingError {
      return nil
    } catch let error as ResponseError {
      if case .requestFailure(_, let statusCode, _) = error, statusCode == 404 {
        return nil
      }
      throw error
    }

    guard let baseID = scheduleResponse.data.relationships?.baseTerritory?.data?.id else {
      return nil
    }

    // Fetch manual prices with relationships hydrated via the sub-resource endpoint.
    // The `include` parameter is required for the relationship `data` to populate;
    // without it the API returns links but not the inline ID references.
    var entries: [ManualPriceEntry] = []
    for try await page in client.pages(
      Resources.v1.inAppPurchasePriceSchedules.id(scheduleResponse.data.id).manualPrices.get(
        limit: 200, include: [.inAppPurchasePricePoint, .territory]
      )
    ) {
      for price in page.data {
        guard let territoryID = price.relationships?.territory?.data?.id,
              let pricePointID = price.relationships?.inAppPurchasePricePoint?.data?.id
        else { continue }
        entries.append(ManualPriceEntry(territoryID: territoryID, pricePointID: pricePointID))
      }
    }
    return ExistingSchedule(baseTerritoryID: baseID, manualPrices: entries)
  }

  /// POSTs a new schedule that fully replaces any prior one. The first entry in
  /// `manualPrices` must be the base territory's entry.
  static func postSchedule(
    iapID: String,
    baseTerritoryID: String,
    manualPrices: [ManualPriceEntry],
    startDate: String,
    client: AppStoreConnectClient
  ) async throws {
    var inlinePrices: [InAppPurchasePriceInlineCreate] = []
    var refs: [InAppPurchasePriceScheduleCreateRequest.Data.Relationships.ManualPrices.Datum] = []
    for (i, entry) in manualPrices.enumerated() {
      let localID = "${price\(i)}"
      inlinePrices.append(
        InAppPurchasePriceInlineCreate(
          id: localID,
          attributes: .init(startDate: startDate),
          relationships: .init(
            inAppPurchaseV2: .init(data: .init(id: iapID)),
            inAppPurchasePricePoint: .init(data: .init(id: entry.pricePointID))
          )
        )
      )
      refs.append(.init(id: localID))
    }

    _ = try await client.send(
      Resources.v1.inAppPurchasePriceSchedules.post(
        InAppPurchasePriceScheduleCreateRequest(
          data: .init(
            relationships: .init(
              inAppPurchase: .init(data: .init(id: iapID)),
              baseTerritory: .init(data: .init(id: baseTerritoryID)),
              manualPrices: .init(data: refs)
            )
          ),
          included: inlinePrices.map { .inAppPurchasePriceInlineCreate($0) }
        )
      )
    )
  }

  /// Returns today's date in YYYY-MM-DD UTC.
  static func todayDateString() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: Date())
  }

  /// Resolves a customer price (e.g. "4.99") to a price point ID in the given territory.
  /// Throws with nearest tiers if no exact match.
  static func resolvePricePoint(
    iapID: String, territoryID: String, customerPrice: String, client: AppStoreConnectClient
  ) async throws -> (point: InAppPurchasePricePoint, currency: String?) {
    guard let target = Double(customerPrice.trimmingCharacters(in: .whitespaces)) else {
      throw ValidationError("Invalid price '\(customerPrice)'. Use a decimal number like 4.99.")
    }

    var tiers: [InAppPurchasePricePoint] = []
    var currency: String?
    for try await page in client.pages(
      Resources.v2.inAppPurchases.id(iapID).pricePoints.get(
        filterTerritory: [territoryID], limit: 200, include: [.territory]
      )
    ) {
      tiers.append(contentsOf: page.data)
      for t in page.included ?? [] {
        if currency == nil { currency = t.attributes?.currency }
      }
    }

    guard !tiers.isEmpty else {
      throw ValidationError("No price tiers available for territory \(territoryID).")
    }

    if let exact = tiers.first(where: {
      guard let cp = $0.attributes?.customerPrice, let v = Double(cp) else { return false }
      return abs(v - target) < 0.001
    }) {
      return (exact, currency)
    }

    let nearest = tiers
      .compactMap { tier -> (InAppPurchasePricePoint, Double)? in
        guard let cp = tier.attributes?.customerPrice, let v = Double(cp) else { return nil }
        return (tier, abs(v - target))
      }
      .sorted { $0.1 < $1.1 }
      .prefix(5)
      .map(\.0)
    var msg = "No tier with customer price \(customerPrice) \(currency ?? "") in territory \(territoryID).\n"
    msg += "Nearest tiers: " + nearest.compactMap { $0.attributes?.customerPrice }.joined(separator: ", ")
    throw ValidationError(msg)
  }

  /// Looks up the customer price string for a given price point ID in a given territory.
  /// Used for display purposes. Returns nil if not found.
  static func customerPriceForPoint(
    iapID: String, territoryID: String, pricePointID: String, client: AppStoreConnectClient
  ) async throws -> (price: String?, currency: String?) {
    var currency: String?
    for try await page in client.pages(
      Resources.v2.inAppPurchases.id(iapID).pricePoints.get(
        filterTerritory: [territoryID], limit: 200, include: [.territory]
      )
    ) {
      for t in page.included ?? [] {
        if currency == nil { currency = t.attributes?.currency }
      }
      if let match = page.data.first(where: { $0.id == pricePointID }) {
        return (match.attributes?.customerPrice, currency)
      }
    }
    return (nil, currency)
  }

  // MARK: - List

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List in-app purchases for an app."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .long, help: "Filter by type (CONSUMABLE, NON_CONSUMABLE, NON_RENEWING_SUBSCRIPTION).")
    var type: String?

    @Option(name: .long, help: "Filter by state (APPROVED, MISSING_METADATA, READY_TO_SUBMIT, etc.).")
    var state: String?

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      typealias Params = Resources.V1.Apps.WithID.InAppPurchasesV2

      let filterType: [Params.FilterInAppPurchaseType]? = try parseFilter(type, name: "type")
      let filterState: [Params.FilterState]? = try parseFilter(state, name: "state")

      var rows: [[String]] = []
      let request = Resources.v1.apps.id(app.id).inAppPurchasesV2.get(
        filterState: filterState,
        filterInAppPurchaseType: filterType,
        limit: 200
      )

      for try await page in client.pages(request) {
        for iap in page.data {
          let attrs = iap.attributes
          rows.append([
            attrs?.name ?? "—",
            attrs?.productID ?? "—",
            attrs?.inAppPurchaseType.map { formatState($0) } ?? "—",
            attrs?.state.map { formatState($0) } ?? "—",
            attrs?.isFamilySharable == true ? "Yes" : "No",
          ])
        }
      }

      if rows.isEmpty {
        print("No in-app purchases found.")
      } else {
        Table.print(
          headers: ["Name", "Product ID", "Type", "State", "Family"],
          rows: rows
        )
      }
    }
  }

  // MARK: - Info

  struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Show details for an in-app purchase."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Argument(help: "The product identifier of the in-app purchase.")
    var productID: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let request = Resources.v1.apps.id(app.id).inAppPurchasesV2.get(
        filterProductID: [productID],
        include: [.inAppPurchaseLocalizations],
        limitInAppPurchaseLocalizations: 50
      )
      let response = try await client.send(request)

      guard let iap = response.data.first else {
        throw ValidationError("No in-app purchase found with product ID '\(productID)'.")
      }

      let attrs = iap.attributes
      print("Name:             \(attrs?.name ?? "—")")
      print("Product ID:       \(attrs?.productID ?? "—")")
      print("Type:             \(attrs?.inAppPurchaseType.map { formatState($0) } ?? "—")")
      print("State:            \(attrs?.state.map { formatState($0) } ?? "—")")
      print("Family Shareable: \(attrs?.isFamilySharable == true ? "Yes" : "No")")
      print("Content Hosting:  \(attrs?.isContentHosting == true ? "Yes" : "No")")
      print("Review Note:      \(attrs?.reviewNote ?? "—")")

      // Extract localizations from included items
      let locIDs = Set(
        iap.relationships?.inAppPurchaseLocalizations?.data?.map(\.id) ?? []
      )
      let localizations: [InAppPurchaseLocalization] = (response.included ?? []).compactMap {
        if case .inAppPurchaseLocalization(let loc) = $0,
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

      let hasSchedule = try await IAPCommand.iapPriceScheduleExists(iapID: iap.id, client: client)
      if !hasSchedule {
        print()
        print(yellow(IAPCommand.missingScheduleWarning))
      }
    }
  }

  // MARK: - Promoted

  struct Promoted: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List promoted purchases for an app."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      var rows: [[String]] = []
      let request = Resources.v1.apps.id(app.id).promotedPurchases.get(
        limit: 200,
        include: [.inAppPurchaseV2, .subscription]
      )

      for try await page in client.pages(request) {
        var iapInfo: [String: (String, String)] = [:]
        var subInfo: [String: (String, String)] = [:]

        for item in page.included ?? [] {
          switch item {
          case .inAppPurchaseV2(let iap):
            iapInfo[iap.id] = (
              iap.attributes?.name ?? "—",
              iap.attributes?.inAppPurchaseType.map { formatState($0) } ?? "—"
            )
          case .subscription(let sub):
            subInfo[sub.id] = (
              sub.attributes?.name ?? "—",
              sub.attributes?.subscriptionPeriod.map { formatState($0) } ?? "—"
            )
          }
        }

        for promo in page.data {
          let attrs = promo.attributes
          let promoState = attrs?.state.map { formatState($0) } ?? "—"
          let visible = attrs?.isVisibleForAllUsers == true ? "Yes" : "No"
          let enabled = attrs?.isEnabled == true ? "Yes" : "No"

          var productName = "—"
          var productType = "—"

          if let iapID = promo.relationships?.inAppPurchaseV2?.data?.id,
             let info = iapInfo[iapID] {
            productName = "\(info.0) (IAP)"
            productType = info.1
          } else if let subID = promo.relationships?.subscription?.data?.id,
                    let info = subInfo[subID] {
            productName = "\(info.0) (Subscription)"
            productType = info.1
          }

          rows.append([productName, productType, promoState, visible, enabled])
        }
      }

      if rows.isEmpty {
        print("No promoted purchases found.")
      } else {
        Table.print(
          headers: ["Product", "Type", "State", "Visible", "Enabled"],
          rows: rows
        )
      }
    }
  }

  // MARK: - Create

  struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Create a new in-app purchase."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .long, help: "IAP type (CONSUMABLE, NON_CONSUMABLE, NON_RENEWING_SUBSCRIPTION).")
    var type: String?

    @Option(name: .long, help: "Product identifier (e.g. com.example.premium).")
    var productID: String?

    @Option(name: .long, help: "Reference name.")
    var name: String?

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

      let iapType: InAppPurchaseType
      if let t = type {
        iapType = try parseEnum(t, name: "type")
      } else {
        iapType = try promptSelection(
          "Type",
          items: Array(InAppPurchaseType.allCases),
          display: { formatState($0) }
        )
      }

      let pid = productID ?? promptText("Product ID: ")
      let refName = name ?? promptText("Reference Name: ")

      var note: String? = reviewNote
      if note == nil && !autoConfirm {
        print("Review Note (optional, press Enter to skip): ", terminator: "")
        let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !input.isEmpty { note = input }
      }

      print()
      print("Type:             \(formatState(iapType))")
      print("Product ID:       \(pid)")
      print("Name:             \(refName)")
      print("Family Shareable: \(familySharable ? "Yes" : "No")")
      if let n = note { print("Review Note:      \(n)") }
      print()

      guard confirm("Create this in-app purchase? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

      let response = try await client.send(
        Resources.v2.inAppPurchases.post(
          InAppPurchaseV2CreateRequest(
            data: .init(
              attributes: .init(
                name: refName,
                productID: pid,
                inAppPurchaseType: iapType,
                reviewNote: note,
                isFamilySharable: familySharable ? true : nil
              ),
              relationships: .init(
                app: .init(data: .init(id: app.id))
              )
            )
          )
        )
      )

      print(green("Created") + " in-app purchase '\(response.data.attributes?.name ?? refName)'.")
    }
  }

  // MARK: - Update

  struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Update an in-app purchase."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Argument(help: "The product identifier of the in-app purchase.")
    var productID: String

    @Option(name: .long, help: "New reference name.")
    var name: String?

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
      let iap = try await findIAP(productID: productID, appID: app.id, client: client)

      let familyVal: Bool? = try familySharable.map {
        guard let val = Bool($0.lowercased()) else {
          throw ValidationError("Invalid value for --family-sharable. Use 'true' or 'false'.")
        }
        return val
      }

      guard name != nil || reviewNote != nil || familyVal != nil else {
        throw ValidationError("No updates specified. Use --name, --review-note, or --family-sharable.")
      }

      var changes: [String] = []
      if let v = name { changes.append("Name: \(v)") }
      if let v = reviewNote { changes.append("Review Note: \(v)") }
      if let v = familyVal { changes.append("Family Shareable: \(v ? "Yes" : "No")") }
      print("Updates for '\(iap.attributes?.name ?? productID)':")
      for c in changes { print("  \(c)") }
      print()

      guard confirm("Apply updates? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

      _ = try await client.send(
        Resources.v2.inAppPurchases.id(iap.id).patch(
          InAppPurchaseV2UpdateRequest(
            data: .init(
              id: iap.id,
              attributes: .init(
                name: name,
                reviewNote: reviewNote,
                isFamilySharable: familyVal
              )
            )
          )
        )
      )

      print(green("Updated") + " '\(name ?? iap.attributes?.name ?? productID)'.")
    }
  }

  // MARK: - Delete

  struct Delete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Delete an in-app purchase."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Argument(help: "The product identifier of the in-app purchase.")
    var productID: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes: Bool = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let iap = try await findIAP(productID: productID, appID: app.id, client: client)

      guard confirm("Delete in-app purchase '\(iap.attributes?.name ?? productID)'? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

      _ = try await client.send(Resources.v2.inAppPurchases.id(iap.id).delete)

      print(green("Deleted") + " '\(iap.attributes?.name ?? productID)'.")
    }
  }

  // MARK: - Submit

  struct Submit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Submit an in-app purchase for review."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Argument(help: "The product identifier of the in-app purchase.")
    var productID: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes: Bool = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let iap = try await findIAP(productID: productID, appID: app.id, client: client)

      let state = iap.attributes?.state
      guard state == .readyToSubmit else {
        let stateStr = state.map { formatState($0) } ?? "unknown"
        throw ValidationError("In-app purchase '\(iap.attributes?.name ?? productID)' is in state '\(stateStr)'. Only items in 'Ready to Submit' state can be submitted.")
      }

      print("In-app purchase: \(iap.attributes?.name ?? productID)")
      print("Product ID:      \(productID)")
      print("State:           \(formatState(state!))")
      print()
      print(yellow("Note:") + " In-app purchases are reviewed together with the app version.")
      print("Make sure you also submit a new app version for review.")
      print()

      guard confirm("Submit for review? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

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

      print(green("Submitted") + " '\(iap.attributes?.name ?? productID)' for review.")
    }
  }

  // MARK: - Localizations

  struct Localizations: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Manage in-app purchase localizations.",
      subcommands: [View.self, Export.self, Import.self]
    )

    // MARK: View

    struct View: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "View localizations for an in-app purchase."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the in-app purchase.")
      var productID: String

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let iap = try await findIAP(productID: productID, appID: app.id, client: client)

        let locsResponse = try await client.send(
          Resources.v2.inAppPurchases.id(iap.id).inAppPurchaseLocalizations.get(limit: 50)
        )

        if locsResponse.data.isEmpty {
          print("No localizations found.")
          return
        }

        print("Localizations for '\(iap.attributes?.name ?? productID)':")
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
        abstract: "Export in-app purchase localizations to a JSON file."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the in-app purchase.")
      var productID: String

      @Option(name: .long, help: "Output file path.",
              completion: .file(extensions: ["json"]))
      var output: String?

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let iap = try await findIAP(productID: productID, appID: app.id, client: client)

        let locsResponse = try await client.send(
          Resources.v2.inAppPurchases.id(iap.id).inAppPurchaseLocalizations.get(limit: 50)
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
        abstract: "Import in-app purchase localizations from a JSON file."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the in-app purchase.")
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
        let iap = try await findIAP(productID: productID, appID: app.id, client: client)

        let filePath = try resolveFile(file, extension: "json", prompt: "Select a JSON file")
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let localeUpdates = try JSONDecoder().decode([String: ProductLocaleFields].self, from: data)

        guard !localeUpdates.isEmpty else {
          throw ValidationError("JSON file contains no locale data.")
        }

        print("Importing \(localeUpdates.count) locale(s) for '\(iap.attributes?.name ?? productID)':")
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
          Resources.v2.inAppPurchases.id(iap.id).inAppPurchaseLocalizations.get(limit: 50)
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
              Resources.v1.inAppPurchaseLocalizations.post(
                InAppPurchaseLocalizationCreateRequest(
                  data: .init(
                    attributes: .init(
                      name: name,
                      locale: locale,
                      description: fields.description
                    ),
                    relationships: .init(
                      inAppPurchaseV2: .init(data: .init(id: iap.id))
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
            Resources.v1.inAppPurchaseLocalizations.id(localization.id).patch(
              InAppPurchaseLocalizationUpdateRequest(
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

  // MARK: - Pricing

  struct Pricing: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "pricing",
      abstract: "Manage in-app purchase pricing.",
      subcommands: [Show.self, Tiers.self, Set.self, Override.self, Remove.self]
    )

    // MARK: Show

    struct Show: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Show the current price schedule for an in-app purchase."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the in-app purchase.")
      var productID: String

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let iap = try await findIAP(productID: productID, appID: app.id, client: client)

        guard let existing = try await IAPCommand.fetchExistingSchedule(iapID: iap.id, client: client),
              !existing.manualPrices.isEmpty else {
          print(yellow(missingScheduleWarning))
          return
        }

        print("Base region: \(existing.baseTerritoryID)")
        print()

        // Resolve customer price for each entry. The base entry comes first; overrides follow.
        let baseEntry = existing.basePriceEntry
        let overrides = existing.nonBaseOverrides
        let ordered: [IAPCommand.ManualPriceEntry] = (baseEntry.map { [$0] } ?? []) + overrides

        var rows: [[String]] = []
        for entry in ordered {
          let info = try await IAPCommand.customerPriceForPoint(
            iapID: iap.id, territoryID: entry.territoryID,
            pricePointID: entry.pricePointID, client: client)
          let label = entry.territoryID == existing.baseTerritoryID ? "\(entry.territoryID) (base)" : entry.territoryID
          let priceStr = info.price.map { "\($0) \(info.currency ?? "")" } ?? "(unknown tier)"
          rows.append([label, priceStr])
        }

        Table.print(headers: ["Territory", "Customer Price"], rows: rows)
      }
    }

    // MARK: Tiers

    struct Tiers: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "List available price tiers for an in-app purchase in a territory."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the in-app purchase.")
      var productID: String

      @Option(name: .long, help: "Territory code (default: USA).")
      var territory: String = "USA"

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let iap = try await findIAP(productID: productID, appID: app.id, client: client)

        let territoryID = territory.uppercased()
        var tiers: [InAppPurchasePricePoint] = []
        var currency: String?
        for try await page in client.pages(
          Resources.v2.inAppPurchases.id(iap.id).pricePoints.get(
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
        abstract: "Set the base price for an in-app purchase.",
        discussion: """
          Sets or updates the price in the base region (the territory Apple uses to
          auto-equalize prices in all other territories). Existing per-territory manual
          overrides are preserved by default — when there are overrides, an interactive
          menu offers to revert any of them to auto-equalize from the new base.
          """
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the in-app purchase.")
      var productID: String

      @Option(name: .long, help: "Customer price in the base region's currency (e.g. 4.99).")
      var price: String

      @Option(name: .customLong("base-region"), help: "Base region code. Defaults to existing base region, or USA if no schedule exists yet.")
      var baseRegion: String?

      @Option(name: .long, help: "Start date in YYYY-MM-DD format (default: today).")
      var startDate: String?

      @Flag(name: .customLong("remove-all-overrides"), help: "Drop all per-territory manual overrides; revert all non-base territories to auto-equalize.")
      var removeAllOverrides = false

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let iap = try await findIAP(productID: productID, appID: app.id, client: client)

        let existing = try await IAPCommand.fetchExistingSchedule(iapID: iap.id, client: client)
        let newBase = (baseRegion ?? existing?.baseTerritoryID ?? "USA").uppercased()

        let resolved = try await IAPCommand.resolvePricePoint(
          iapID: iap.id, territoryID: newBase, customerPrice: price, client: client)
        let basePoint = resolved.point
        let baseCurrency = resolved.currency ?? ""

        // The OLD base entry is dropped automatically — that territory becomes
        // auto-equalized from the new base. Other manual overrides are preserved.
        let preservableOverrides: [IAPCommand.ManualPriceEntry] = (existing?.nonBaseOverrides ?? [])
          .filter { $0.territoryID != newBase }

        var keptOverrides: [IAPCommand.ManualPriceEntry] = preservableOverrides
        var droppedOverrideTerritories: [String] = []

        if !preservableOverrides.isEmpty {
          if removeAllOverrides {
            keptOverrides = []
            droppedOverrideTerritories = preservableOverrides.map(\.territoryID)
          } else if !autoConfirm {
            // Resolve customer prices for each override (for display in the menu)
            var labels: [String] = []
            for entry in preservableOverrides {
              let info = try await IAPCommand.customerPriceForPoint(
                iapID: iap.id, territoryID: entry.territoryID,
                pricePointID: entry.pricePointID, client: client)
              labels.append("\(entry.territoryID) — \(info.price ?? "?") \(info.currency ?? "")")
            }
            print()
            print("This product currently has manual prices in \(preservableOverrides.count) other territor\(preservableOverrides.count == 1 ? "y" : "ies"):")
            for (i, label) in labels.enumerated() {
              print("  [\(i + 1)] \(label)")
            }
            print()
            print("Revert any of these to auto-equalize from the new base?")
            print("Select to revert (comma-separated numbers, 'all', or press Enter to keep all): ", terminator: "")
            let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if input.isEmpty {
              // keep all
            } else if input.lowercased() == "all" {
              keptOverrides = []
              droppedOverrideTerritories = preservableOverrides.map(\.territoryID)
            } else {
              let parts = input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
              var dropIndices: Swift.Set<Int> = []
              for part in parts {
                guard let n = Int(part), n >= 1, n <= preservableOverrides.count else {
                  throw ValidationError("Invalid selection '\(part)'. Enter numbers between 1 and \(preservableOverrides.count).")
                }
                dropIndices.insert(n - 1)
              }
              keptOverrides = preservableOverrides.enumerated()
                .filter { !dropIndices.contains($0.offset) }
                .map(\.element)
              droppedOverrideTerritories = preservableOverrides.enumerated()
                .filter { dropIndices.contains($0.offset) }
                .map(\.element.territoryID)
            }
          }
        }

        let dateStr = startDate ?? IAPCommand.todayDateString()

        print()
        print("Set base price:")
        print("  Product ID:     \(productID)")
        print("  Base Region:    \(newBase)")
        print("  Customer Price: \(basePoint.attributes?.customerPrice ?? "—") \(baseCurrency)")
        print("  Start Date:     \(dateStr)")
        if let existingBase = existing?.baseTerritoryID, existingBase != newBase {
          print("  Old base:       \(existingBase) (will revert to auto-equalize)")
        }
        if !keptOverrides.isEmpty {
          print("  Keep overrides: \(keptOverrides.map(\.territoryID).sorted().joined(separator: ", "))")
        }
        if !droppedOverrideTerritories.isEmpty {
          print("  Drop overrides: \(droppedOverrideTerritories.sorted().joined(separator: ", ")) (revert to auto-equalize)")
        }
        print()

        guard confirm("Apply this schedule? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        let baseEntry = IAPCommand.ManualPriceEntry(
          territoryID: newBase, pricePointID: basePoint.id)
        let allEntries = [baseEntry] + keptOverrides

        try await IAPCommand.postSchedule(
          iapID: iap.id,
          baseTerritoryID: newBase,
          manualPrices: allEntries,
          startDate: dateStr,
          client: client
        )

        print()
        print(green("Updated") + " price for '\(iap.attributes?.name ?? productID)'.")
      }
    }

    // MARK: Override

    struct Override: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Add or update a per-territory manual price override.",
        discussion: """
          Adds an explicit price for a single territory on top of the existing base price.
          The base region's price and any other manual overrides are preserved. To revert
          a territory to auto-equalize, use 'iap pricing remove --territory X'.
          """
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the in-app purchase.")
      var productID: String

      @Option(name: .long, help: "Customer price in the territory's currency (e.g. 5.99).")
      var price: String

      @Option(name: .long, help: "Territory code to override (e.g. FRA).")
      var territory: String

      @Option(name: .long, help: "Start date in YYYY-MM-DD format (default: today).")
      var startDate: String?

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let iap = try await findIAP(productID: productID, appID: app.id, client: client)

        guard let existing = try await IAPCommand.fetchExistingSchedule(iapID: iap.id, client: client) else {
          throw ValidationError("No price schedule exists yet. Use 'iap pricing set' to create one first.")
        }

        let territoryID = territory.uppercased()
        if territoryID == existing.baseTerritoryID {
          throw ValidationError("\(territoryID) is the base region. Use 'iap pricing set' to change the base price.")
        }

        let resolved = try await IAPCommand.resolvePricePoint(
          iapID: iap.id, territoryID: territoryID, customerPrice: price, client: client)
        let newPoint = resolved.point
        let currency = resolved.currency ?? ""

        let isUpdate = existing.nonBaseOverrides.contains { $0.territoryID == territoryID }
        let dateStr = startDate ?? IAPCommand.todayDateString()

        print()
        print("\(isUpdate ? "Update" : "Add") manual price:")
        print("  Product ID:     \(productID)")
        print("  Territory:      \(territoryID)")
        print("  Customer Price: \(newPoint.attributes?.customerPrice ?? "—") \(currency)")
        print("  Start Date:     \(dateStr)")
        print("  Base Region:    \(existing.baseTerritoryID) (preserved)")
        let otherOverrides = existing.nonBaseOverrides.filter { $0.territoryID != territoryID }
        if !otherOverrides.isEmpty {
          print("  Other overrides: \(otherOverrides.map(\.territoryID).sorted().joined(separator: ", ")) (preserved)")
        }
        print()

        guard confirm("Apply this override? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        var newEntries: [IAPCommand.ManualPriceEntry] = []
        if let baseEntry = existing.basePriceEntry {
          newEntries.append(baseEntry)
        }
        newEntries.append(contentsOf: otherOverrides)
        newEntries.append(IAPCommand.ManualPriceEntry(
          territoryID: territoryID, pricePointID: newPoint.id))

        try await IAPCommand.postSchedule(
          iapID: iap.id,
          baseTerritoryID: existing.baseTerritoryID,
          manualPrices: newEntries,
          startDate: dateStr,
          client: client
        )

        print()
        print(green(isUpdate ? "Updated" : "Added") + " manual price for \(territoryID).")
      }
    }

    // MARK: Remove

    struct Remove: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Remove a per-territory manual price override.",
        discussion: """
          Drops the manual price for a territory; that territory will revert to the
          auto-equalized price computed from the base region. The base region itself
          cannot be removed — use 'iap pricing set --base-region X' to change the base.
          """
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the in-app purchase.")
      var productID: String

      @Option(name: .long, help: "Territory code to revert to auto-equalize (e.g. FRA).")
      var territory: String

      @Option(name: .long, help: "Start date in YYYY-MM-DD format (default: today).")
      var startDate: String?

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let iap = try await findIAP(productID: productID, appID: app.id, client: client)

        guard let existing = try await IAPCommand.fetchExistingSchedule(iapID: iap.id, client: client) else {
          throw ValidationError("No price schedule exists yet. Use 'iap pricing set' to create one first.")
        }

        let territoryID = territory.uppercased()
        if territoryID == existing.baseTerritoryID {
          throw ValidationError("\(territoryID) is the base region. Use 'iap pricing set --base-region X' to change the base region first.")
        }
        guard existing.nonBaseOverrides.contains(where: { $0.territoryID == territoryID }) else {
          throw ValidationError("No manual override exists for territory \(territoryID).")
        }

        let dateStr = startDate ?? IAPCommand.todayDateString()

        print()
        print("Remove manual price:")
        print("  Product ID:    \(productID)")
        print("  Territory:     \(territoryID) (will auto-equalize from \(existing.baseTerritoryID))")
        let remainingOverrides = existing.nonBaseOverrides.filter { $0.territoryID != territoryID }
        if !remainingOverrides.isEmpty {
          print("  Other manual:  \(remainingOverrides.map(\.territoryID).sorted().joined(separator: ", ")) (preserved)")
        }
        print()

        guard confirm("Remove this override? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        var newEntries: [IAPCommand.ManualPriceEntry] = []
        if let baseEntry = existing.basePriceEntry {
          newEntries.append(baseEntry)
        }
        newEntries.append(contentsOf: remainingOverrides)

        try await IAPCommand.postSchedule(
          iapID: iap.id,
          baseTerritoryID: existing.baseTerritoryID,
          manualPrices: newEntries,
          startDate: dateStr,
          client: client
        )

        print()
        print(green("Removed") + " manual price for \(territoryID).")
      }
    }

  }
}
