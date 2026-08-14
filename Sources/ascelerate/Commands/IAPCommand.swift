import AppStoreAPI
import AppStoreConnect
import ArgumentParser
import Foundation

extension InAppPurchaseLocalization {
  /// Reduces this API localization to the shared `LocalizationRecord` used by the import/export helpers.
  var localizationRecord: LocalizationRecord {
    LocalizationRecord(
      id: id, locale: attributes?.locale ?? "", name: attributes?.name,
      description: attributes?.description)
  }
}

extension InAppPurchasePricePoint: ResolvablePricePoint {
  var resolverCustomerPrice: String? { attributes?.customerPrice }
}

struct IAPCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "iap",
    abstract: "Manage in-app purchases.",
    subcommands: [List.self, Info.self, Promoted.self, Create.self, Update.self, Delete.self, Submit.self, Localizations.self, Pricing.self, Availability.self, OfferCode.self, Images.self, ReviewScreenshot.self]
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

  /// Resolves the IAP from bundle/product ID and verifies the offer code actually
  /// belongs to it — a stale or mistyped ID from another product must not be mutated.
  static func validateOwnedOfferCode(
    _ offerCodeID: String, bundleID: String, productID: String, client: AppStoreConnectClient
  ) async throws {
    let app = try await findApp(bundleID: bundleID, client: client)
    let iap = try await findIAP(productID: productID, appID: app.id, client: client)
    for try await page in client.pages(
      Resources.v2.inAppPurchases.id(iap.id).offerCodes.get(limit: 200)
    ) where page.data.contains(where: { $0.id == offerCodeID }) {
      return
    }
    throw ValidationError("Offer code '\(offerCodeID)' does not belong to '\(productID)'.")
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
  /// `customerPrice`/`currency` are display data captured from the schedule fetch's
  /// included payload (write paths that build new entries don't need them).
  struct ManualPriceEntry: Sendable {
    let territoryID: String
    let pricePointID: String
    var customerPrice: String?
    var currency: String?
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

    // A schedule exists at this point (the GET succeeded) — failing to hydrate any
    // part of it must throw, not degrade: every write path POSTs the schedule
    // wholesale, so a silently dropped entry would be permanently deleted.
    guard let baseID = scheduleResponse.data.relationships?.baseTerritory?.data?.id else {
      throw ValidationError("Could not resolve the price schedule's base territory. Retry, or inspect with 'iap pricing show'.")
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
      // The included payload already carries each point's customer price and each
      // territory's currency — capture them here instead of refetching per entry.
      var pointPrices: [String: String] = [:]
      var territoryCurrencies: [String: String] = [:]
      for item in page.included ?? [] {
        switch item {
        case .inAppPurchasePricePoint(let p):
          if let cp = p.attributes?.customerPrice { pointPrices[p.id] = cp }
        case .territory(let t):
          if let c = t.attributes?.currency { territoryCurrencies[t.id] = c }
        }
      }
      for price in page.data {
        guard let territoryID = price.relationships?.territory?.data?.id,
              let pricePointID = price.relationships?.inAppPurchasePricePoint?.data?.id
        else {
          throw ValidationError("Could not resolve territory/price point for a manual price entry. Retry, or inspect with 'iap pricing show'.")
        }
        entries.append(ManualPriceEntry(
          territoryID: territoryID, pricePointID: pricePointID,
          customerPrice: pointPrices[pricePointID], currency: territoryCurrencies[territoryID]))
      }
    }
    return ExistingSchedule(baseTerritoryID: baseID, manualPrices: entries)
  }

  /// POSTs a new schedule that fully replaces any prior one, retrying transient API
  /// errors. The first entry in `manualPrices` must be the base territory's entry.
  /// The POST is atomic — on failure the existing schedule is untouched.
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

    _ = try await withTransientRetry { try await client.send(
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
    ) }
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
    let target = try parseCustomerPrice(customerPrice)

    var tiers: [InAppPurchasePricePoint] = []
    var currency: String?
    for try await page in client.pages(
      Resources.v2.inAppPurchases.id(iapID).pricePoints.get(
        filterTerritory: [territoryID], limit: 200, include: [.territory]
      )
    ) {
      tiers.append(contentsOf: page.data)
      for t in page.included ?? [] where currency == nil {
        currency = t.attributes?.currency
      }
    }

    let point = try findPricePoint(
      in: tiers, target: target, priceLabel: customerPrice, territoryID: territoryID,
      currency: currency)
    return (point, currency)
  }

  /// Batch-resolves (territory, customer price) pairs to this IAP's price points,
  /// fetching several territories' tier lists per request instead of one request per
  /// territory. Prints one progress dot per chunk.
  static func resolvePricePointsBatched(
    iapID: String, prices: [(territoryID: String, price: String)],
    client: AppStoreConnectClient
  ) async throws -> [(territoryID: String, point: InAppPurchasePricePoint, currency: String?)] {
    var results: [(territoryID: String, point: InAppPurchasePricePoint, currency: String?)] = []
    for chunk in prices.chunked(into: 10) {
      var tiersByTerritory: [String: [InAppPurchasePricePoint]] = [:]
      var currencyByTerritory: [String: String] = [:]
      for try await page in client.pages(
        Resources.v2.inAppPurchases.id(iapID).pricePoints.get(
          filterTerritory: chunk.map(\.territoryID),
          fieldsInAppPurchasePricePoints: [.customerPrice, .territory],
          limit: 8000, include: [.territory]
        )
      ) {
        for point in page.data {
          guard let t = point.relationships?.territory?.data?.id else { continue }
          tiersByTerritory[t, default: []].append(point)
        }
        for t in page.included ?? [] {
          if let cur = t.attributes?.currency { currencyByTerritory[t.id] = cur }
        }
      }
      results.append(contentsOf: try matchPricePoints(
        prices: chunk, tiersByTerritory: tiersByTerritory,
        currencyByTerritory: currencyByTerritory))
      print(".", terminator: "")
      fflush(stdout)
    }
    return results
  }

  /// Looks up the customer price string for a given price point ID in a given territory.
  /// Used for display purposes. Returns nil if not found.

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

    @OptionGroup var jsonOption: JSONOption

    private struct Entry: Encodable {
      let id: String
      let productID: String?
      let name: String?
      let type: String?
      let state: String?
      let familySharable: Bool?
    }

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      typealias Params = Resources.V1.Apps.WithID.InAppPurchasesV2

      let filterType: [Params.FilterInAppPurchaseType]? = try parseFilter(type, name: "type")
      let filterState: [Params.FilterState]? = try parseFilter(state, name: "state")

      var entries: [Entry] = []
      let request = Resources.v1.apps.id(app.id).inAppPurchasesV2.get(
        filterState: filterState,
        filterInAppPurchaseType: filterType,
        limit: 200
      )

      for try await page in client.pages(request) {
        for iap in page.data {
          let attrs = iap.attributes
          entries.append(Entry(
            id: iap.id,
            productID: attrs?.productID,
            name: attrs?.name,
            type: attrs?.inAppPurchaseType?.rawValue,
            state: attrs?.state?.rawValue,
            familySharable: attrs?.isFamilySharable
          ))
        }
      }

      if jsonOption.json {
        try printJSON(entries)
        return
      }

      if entries.isEmpty {
        print("No in-app purchases found.")
      } else {
        Table.print(
          headers: ["Name", "Product ID", "Type", "State", "Family"],
          rows: entries.map { e in
            [
              e.name ?? "—",
              e.productID ?? "—",
              e.type.map { formatState($0) } ?? "—",
              e.state.map { formatState($0) } ?? "—",
              e.familySharable == true ? "Yes" : "No",
            ]
          }
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

    @OptionGroup var jsonOption: JSONOption

    private struct Detail: Encodable {
      struct Localization: Encodable {
        let id: String
        let locale: String?
        let name: String?
        let description: String?
      }
      let id: String
      let productID: String?
      let name: String?
      let type: String?
      let state: String?
      let familySharable: Bool?
      let contentHosting: Bool?
      let reviewNote: String?
      let localizations: [Localization]
      let hasPricing: Bool
    }

    func run() async throws {
      jsonOption.activate()
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

      let hasSchedule = try await IAPCommand.iapPriceScheduleExists(iapID: iap.id, client: client)

      let attrs = iap.attributes
      let detail = Detail(
        id: iap.id,
        productID: attrs?.productID,
        name: attrs?.name,
        type: attrs?.inAppPurchaseType?.rawValue,
        state: attrs?.state?.rawValue,
        familySharable: attrs?.isFamilySharable,
        contentHosting: attrs?.isContentHosting,
        reviewNote: attrs?.reviewNote,
        localizations: localizations
          .sorted { ($0.attributes?.locale ?? "") < ($1.attributes?.locale ?? "") }
          .map {
            Detail.Localization(
              id: $0.id,
              locale: $0.attributes?.locale,
              name: $0.attributes?.name,
              description: $0.attributes?.description
            )
          },
        hasPricing: hasSchedule
      )

      if jsonOption.json {
        try printJSON(detail)
        return
      }

      print("Name:             \(detail.name ?? "—")")
      print("Product ID:       \(detail.productID ?? "—")")
      print("Type:             \(detail.type.map { formatState($0) } ?? "—")")
      print("State:            \(detail.state.map { formatState($0) } ?? "—")")
      print("Family Shareable: \(detail.familySharable == true ? "Yes" : "No")")
      print("Content Hosting:  \(detail.contentHosting == true ? "Yes" : "No")")
      print("Review Note:      \(detail.reviewNote ?? "—")")

      if !detail.localizations.isEmpty {
        print()
        print("Localizations:")
        for loc in detail.localizations {
          print("  [\(localeName(loc.locale ?? "?"))] \(loc.name ?? "—") — \(loc.description ?? "—")")
        }
      }

      if !detail.hasPricing {
        print()
        print(yellow(IAPCommand.missingScheduleWarning))
      }
    }
  }

  // MARK: - Promoted

  struct Promoted: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "promoted",
      abstract: "View and manage promoted purchases.",
      subcommands: [List.self, Add.self, Remove.self, Reorder.self, Toggle.self]
    )

    /// A promoted purchase resolved to its underlying product.
    struct PromotedInfo {
      let promotedID: String
      let productID: String
      let name: String
      let kind: String
      let state: String
      let isVisible: Bool
      let isEnabled: Bool
    }

    /// Fetches the app's promoted purchases in display order, resolved to their products.
    static func fetchPromoted(
      appID: String, client: AppStoreConnectClient
    ) async throws -> [PromotedInfo] {
      var result: [PromotedInfo] = []
      for try await page in client.pages(
        Resources.v1.apps.id(appID).promotedPurchases.get(
          limit: 200, include: [.inAppPurchaseV2, .subscription])
      ) {
        var iapInfo: [String: (productID: String, name: String)] = [:]
        var subInfo: [String: (productID: String, name: String)] = [:]
        for item in page.included ?? [] {
          switch item {
          case .inAppPurchaseV2(let iap):
            iapInfo[iap.id] = (iap.attributes?.productID ?? "—", iap.attributes?.name ?? "—")
          case .subscription(let sub):
            subInfo[sub.id] = (sub.attributes?.productID ?? "—", sub.attributes?.name ?? "—")
          }
        }
        for promo in page.data {
          let a = promo.attributes
          var productID = "—", name = "—", kind = "—"
          if let iapID = promo.relationships?.inAppPurchaseV2?.data?.id, let info = iapInfo[iapID] {
            productID = info.productID; name = info.name; kind = "IAP"
          } else if let subID = promo.relationships?.subscription?.data?.id, let info = subInfo[subID] {
            productID = info.productID; name = info.name; kind = "Subscription"
          }
          result.append(
            PromotedInfo(
              promotedID: promo.id, productID: productID, name: name, kind: kind,
              state: a?.state.map { formatState($0) } ?? "—",
              isVisible: a?.isVisibleForAllUsers == true, isEnabled: a?.isEnabled == true))
        }
      }
      return result
    }

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "List promoted purchases (in App Store display order)."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let promoted = try await Promoted.fetchPromoted(appID: app.id, client: client)

        if promoted.isEmpty {
          print("No promoted purchases found.")
          return
        }
        let rows = promoted.map {
          [
            $0.productID, $0.name, $0.kind, $0.state,
            $0.isVisible ? "Yes" : "No", $0.isEnabled ? "Yes" : "No",
          ]
        }
        Table.print(
          headers: ["Product ID", "Name", "Kind", "State", "Visible", "Enabled"], rows: rows)
      }
    }

    struct Add: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Promote an in-app purchase or subscription."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the IAP or subscription to promote.")
      var productID: String

      @Option(name: .long, help: "Visible to all users (true) or a limited audience (false). Default: true.")
      var visibleForAll: Bool = true

      @Option(name: .long, help: "Whether the promotion is enabled. Default: true.")
      var enabled: Bool = true

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)

        // Resolve the product to either an IAP or a subscription.
        var iap: InAppPurchaseV2?
        do {
          iap = try await findIAP(productID: productID, appID: app.id, client: client)
        } catch is ValidationError {
          iap = nil
        }

        let relationships: PromotedPurchaseCreateRequest.Data.Relationships
        let label: String
        if let iap {
          relationships = .init(
            app: .init(data: .init(id: app.id)),
            inAppPurchaseV2: .init(data: .init(id: iap.id)))
          label = "IAP '\(iap.attributes?.name ?? productID)'"
        } else {
          let (sub, _) = try await SubCommand.findSubscription(
            productID: productID, appID: app.id, client: client)
          relationships = .init(
            app: .init(data: .init(id: app.id)),
            subscription: .init(data: .init(id: sub.id)))
          label = "subscription '\(sub.attributes?.name ?? productID)'"
        }

        guard confirm("Promote \(label)? [y/N] ") else {
          cancelled()
          return
        }

        let resp = try await client.send(
          Resources.v1.promotedPurchases.post(
            PromotedPurchaseCreateRequest(
              data: .init(
                attributes: .init(isVisibleForAllUsers: visibleForAll, isEnabled: enabled),
                relationships: relationships))))

        print()
        success("Promoted", "\(label) (id: \(resp.data.id)).")
      }
    }

    struct Remove: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Stop promoting an in-app purchase or subscription."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the promoted IAP or subscription.")
      var productID: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let promoted = try await Promoted.fetchPromoted(appID: app.id, client: client)
        guard let target = promoted.first(where: { $0.productID == productID }) else {
          throw ValidationError("No promoted purchase found for product '\(productID)'.")
        }

        guard confirm("Stop promoting '\(target.name)'? [y/N] ") else {
          cancelled()
          return
        }
        _ = try await client.send(Resources.v1.promotedPurchases.id(target.promotedID).delete)
        print()
        success("Removed", "promoted purchase '\(target.name)'.")
      }
    }

    struct Toggle: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Enable or disable a promoted purchase."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the promoted IAP or subscription.")
      var productID: String

      @Option(name: .long, help: "Whether the promotion is enabled (true/false).")
      var enabled: Bool

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let promoted = try await Promoted.fetchPromoted(appID: app.id, client: client)
        guard let target = promoted.first(where: { $0.productID == productID }) else {
          throw ValidationError("No promoted purchase found for product '\(productID)'.")
        }

        guard confirm("Set '\(target.name)' enabled=\(enabled)? [y/N] ") else {
          cancelled()
          return
        }
        _ = try await client.send(
          Resources.v1.promotedPurchases.id(target.promotedID).patch(
            PromotedPurchaseUpdateRequest(
              data: .init(id: target.promotedID, attributes: .init(isEnabled: enabled)))))
        print()
        success("Updated", "'\(target.name)' (enabled=\(enabled)).")
      }
    }

    struct Reorder: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Set the App Store display order of promoted purchases.",
        discussion: """
          Pass product identifiers in the desired order. Any promoted purchases you omit are
          kept and appended after the ones you list.
          """
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "Comma-separated product identifiers in the desired order.")
      var productIDs: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let promoted = try await Promoted.fetchPromoted(appID: app.id, client: client)

        let requested = productIDs.split(separator: ",").map {
          $0.trimmingCharacters(in: .whitespaces)
        }
        var orderedIDs: [String] = []
        for pid in requested {
          guard let target = promoted.first(where: { $0.productID == pid }) else {
            throw ValidationError("No promoted purchase found for product '\(pid)'.")
          }
          orderedIDs.append(target.promotedID)
        }
        // Preserve any promoted purchases the user didn't list, after the requested ones.
        let requestedSet = Set(requested)
        for p in promoted where !requestedSet.contains(p.productID) {
          orderedIDs.append(p.promotedID)
        }

        guard confirm("Reorder \(orderedIDs.count) promoted purchase(s)? [y/N] ") else {
          cancelled()
          return
        }
        _ = try await client.send(
          Resources.v1.apps.id(app.id).relationships.promotedPurchases.patch(
            AppPromotedPurchasesLinkagesRequest(data: orderedIDs.map { .init(id: $0) })))
        print()
        success("Reordered", "promoted purchases.")
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

      let pid = try productID ?? promptText("Product ID: ")
      let refName = try name ?? promptText("Reference Name: ")

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
        cancelled()
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

      success("Created", "in-app purchase '\(response.data.attributes?.name ?? refName)'.")
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
        cancelled()
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

      success("Updated", "'\(name ?? iap.attributes?.name ?? productID)'.")
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
        cancelled()
        return
      }

      _ = try await client.send(Resources.v2.inAppPurchases.id(iap.id).delete)

      success("Deleted", "'\(iap.attributes?.name ?? productID)'.")
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
        cancelled()
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

      success("Submitted", "'\(iap.attributes?.name ?? productID)' for review.")
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
        try exportProductLocalizations(
          locsResponse.data.map(\.localizationRecord), productID: productID, output: output)
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

        let locsResponse = try await client.send(
          Resources.v2.inAppPurchases.id(iap.id).inAppPurchaseLocalizations.get(limit: 50)
        )

        try await importProductLocalizations(
          localeUpdates,
          productName: iap.attributes?.name ?? productID,
          existing: locsResponse.data.map(\.localizationRecord),
          verbose: verbose,
          create: { locale, name, description in
            let response = try await client.send(
              Resources.v1.inAppPurchaseLocalizations.post(
                InAppPurchaseLocalizationCreateRequest(
                  data: .init(
                    attributes: .init(name: name, locale: locale, description: description),
                    relationships: .init(inAppPurchaseV2: .init(data: .init(id: iap.id)))
                  )
                )
              )
            )
            return response.data.localizationRecord
          },
          update: { id, name, description in
            let response = try await client.send(
              Resources.v1.inAppPurchaseLocalizations.id(id).patch(
                InAppPurchaseLocalizationUpdateRequest(
                  data: .init(id: id, attributes: .init(name: name, description: description))
                )
              )
            )
            return response.data.localizationRecord
          }
        )
      }
    }
  }

  // MARK: - Pricing

  struct Pricing: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "pricing",
      abstract: "Manage in-app purchase pricing.",
      subcommands: [Show.self, Tiers.self, Set.self, Override.self, Remove.self, Export.self, Import.self]
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

      @OptionGroup var jsonOption: JSONOption

      private struct Schedule: Encodable {
        struct Price: Encodable {
          let territory: String
          let price: String?
          let currency: String?
        }
        let baseTerritory: String?
        let prices: [Price]
      }

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let iap = try await findIAP(productID: productID, appID: app.id, client: client)

        guard let existing = try await IAPCommand.fetchExistingSchedule(iapID: iap.id, client: client),
              !existing.manualPrices.isEmpty else {
          if jsonOption.json {
            try printJSON(Schedule(baseTerritory: nil, prices: []))
            return
          }
          print(yellow(missingScheduleWarning))
          return
        }

        // The base entry comes first; overrides follow.
        let ordered: [IAPCommand.ManualPriceEntry] =
          (existing.basePriceEntry.map { [$0] } ?? []) + existing.nonBaseOverrides
        let schedule = Schedule(
          baseTerritory: existing.baseTerritoryID,
          prices: ordered.map {
            Schedule.Price(territory: $0.territoryID, price: $0.customerPrice, currency: $0.currency)
          }
        )

        if jsonOption.json {
          try printJSON(schedule)
          return
        }

        print("Base region: \(existing.baseTerritoryID)")
        print()

        let rows = schedule.prices.map { entry -> [String] in
          let label = entry.territory == schedule.baseTerritory ? "\(entry.territory) (base)" : entry.territory
          let priceStr = entry.price.map { "\($0) \(entry.currency ?? "")" } ?? "(unknown tier)"
          return [label, priceStr]
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
        var tiers: [PriceTier] = []
        var currency: String?
        for try await page in client.pages(
          Resources.v2.inAppPurchases.id(iap.id).pricePoints.get(
            filterTerritory: [territoryID],
            limit: 200,
            include: [.territory]
          )
        ) {
          tiers.append(
            contentsOf: page.data.map {
              PriceTier(
                id: $0.id, customerPrice: $0.attributes?.customerPrice,
                proceeds: $0.attributes?.proceeds)
            })
          for t in page.included ?? [] where currency == nil {
            currency = t.attributes?.currency
          }
        }

        printPriceTiers(tiers, currency: currency, territoryID: territoryID)
      }
    }

    // MARK: Set
    struct Set: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Set the base price for an in-app purchase.",
        discussion: """
          Sets or updates the price in the base territory (the territory Apple uses to
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

      @Option(name: .long, help: "Customer price in the base territory's currency (e.g. 4.99).")
      var price: String

      @Option(name: .customLong("base-territory"), help: "Base territory code. Defaults to the existing base territory, or USA if no schedule exists yet.")
      var baseTerritory: String?

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
        let newBase = (baseTerritory ?? existing?.baseTerritoryID ?? "USA").uppercased()

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
            // Customer prices for the menu come from the schedule fetch's included payload
            let labels = preservableOverrides.map {
              "\($0.territoryID) — \($0.customerPrice ?? "?") \($0.currency ?? "")"
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
        print("  Base Territory: \(newBase)")
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
          cancelled()
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
        success("Updated", "price for '\(iap.attributes?.name ?? productID)'.")
      }
    }

    // MARK: Override

    struct Override: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Add or update a per-territory manual price override.",
        discussion: """
          Adds an explicit price for a single territory on top of the existing base price.
          The base territory's price and any other manual overrides are preserved. To revert
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
          throw ValidationError("\(territoryID) is the base territory. Use 'iap pricing set' to change the base price.")
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
        print("  Base Territory: \(existing.baseTerritoryID) (preserved)")
        let otherOverrides = existing.nonBaseOverrides.filter { $0.territoryID != territoryID }
        if !otherOverrides.isEmpty {
          print("  Other overrides: \(otherOverrides.map(\.territoryID).sorted().joined(separator: ", ")) (preserved)")
        }
        print()

        guard confirm("Apply this override? [y/N] ") else {
          cancelled()
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
        success(isUpdate ? "Updated" : "Added", "manual price for \(territoryID).")
      }
    }

    // MARK: Remove

    struct Remove: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Remove a per-territory manual price override.",
        discussion: """
          Drops the manual price for a territory; that territory will revert to the
          auto-equalized price computed from the base territory. The base territory itself
          cannot be removed — use 'iap pricing set --base-territory X' to change the base.
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
          throw ValidationError("\(territoryID) is the base territory. Use 'iap pricing set --base-territory X' to change the base territory first.")
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
          cancelled()
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
        success("Removed", "manual price for \(territoryID).")
      }
    }

    // MARK: Export

    struct Export: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Export the price schedule to a JSON file.",
        discussion: """
          Writes the base territory and every manual price to a JSON file that
          'iap pricing import' can apply to another in-app purchase — in this app or
          any other. Auto-equalized territories are not part of the schedule and are
          not exported.
          """
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

        guard let existing = try await IAPCommand.fetchExistingSchedule(iapID: iap.id, client: client),
              !existing.manualPrices.isEmpty else {
          throw ValidationError("No price schedule exists for '\(productID)' — nothing to export.")
        }

        var prices: [String: String] = [:]
        for entry in existing.manualPrices {
          guard let cp = entry.customerPrice else {
            throw ValidationError("Could not resolve the customer price for territory \(entry.territoryID). Retry, or inspect with 'iap pricing show'.")
          }
          prices[entry.territoryID] = cp
        }

        try exportProductPrices(
          ProductPricesFile(baseTerritory: existing.baseTerritoryID, prices: prices),
          productID: productID, output: output)
      }
    }

    // MARK: Import

    struct Import: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Import a price schedule from a JSON file.",
        discussion: """
          Applies a file produced by 'iap pricing export' (from this or any other
          product): the base territory plus one manual price per listed territory.
          Prices are matched to this product's own tiers by customer price. The
          schedule is replaced wholesale — existing overrides in territories not
          listed in the file revert to auto-equalize.
          """
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the in-app purchase.")
      var productID: String

      @Option(name: .long, help: "Path to JSON file.",
              completion: .file(extensions: ["json"]))
      var file: String?

      @Option(name: .long, help: "Start date in YYYY-MM-DD format (default: today).")
      var startDate: String?

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let iap = try await findIAP(productID: productID, appID: app.id, client: client)

        let priceFile = try loadProductPricesFile(file)
        let existing = try await IAPCommand.fetchExistingSchedule(iapID: iap.id, client: client)
        let base = priceFile.baseTerritory ?? existing?.baseTerritoryID ?? "USA"
        guard priceFile.prices[base] != nil else {
          throw ValidationError("The file has no price for the base territory \(base).")
        }

        // Resolve every listed price against this product's own tiers.
        let sortedPrices = priceFile.prices.sorted { $0.key < $1.key }
          .map { (territoryID: $0.key, price: $0.value) }
        print("Resolving price points for \(sortedPrices.count) territor\(sortedPrices.count == 1 ? "y" : "ies")", terminator: "")
        fflush(stdout)
        let resolved = try await IAPCommand.resolvePricePointsBatched(
          iapID: iap.id, prices: sortedPrices, client: client)
        print(" done.")

        let entries = resolved.map {
          IAPCommand.ManualPriceEntry(
            territoryID: $0.territoryID, pricePointID: $0.point.id,
            customerPrice: $0.point.attributes?.customerPrice, currency: $0.currency)
        }
        guard let baseEntry = entries.first(where: { $0.territoryID == base }) else {
          throw ValidationError("The file has no price for the base territory \(base).")
        }
        let overrides = entries.filter { $0.territoryID != base }

        if let existing, existing.baseTerritoryID == base {
          let existingByTerritory = Dictionary(
            existing.manualPrices.map { ($0.territoryID, $0.pricePointID) },
            uniquingKeysWith: { first, _ in first })
          let newByTerritory = Dictionary(
            entries.map { ($0.territoryID, $0.pricePointID) },
            uniquingKeysWith: { first, _ in first })
          if existingByTerritory == newByTerritory {
            print("The current price schedule already matches the file. Nothing to do.")
            return
          }
        }

        let dateStr = startDate ?? IAPCommand.todayDateString()
        let dropped = (existing?.nonBaseOverrides ?? [])
          .map(\.territoryID)
          .filter { $0 != base && priceFile.prices[$0] == nil }

        print()
        print("Import price schedule:")
        print("  Product ID:     \(productID)")
        print("  Base Territory: \(base) at \(baseEntry.customerPrice ?? "?") \(baseEntry.currency ?? "")")
        if overrides.count <= 10 {
          for entry in overrides {
            print("  Override:       \(entry.territoryID) at \(entry.customerPrice ?? "?") \(entry.currency ?? "")")
          }
        } else if !overrides.isEmpty {
          print("  Overrides:      \(overrides.count) territories")
        }
        if let existingBase = existing?.baseTerritoryID, existingBase != base {
          print("  Old base:       \(existingBase) (will revert to auto-equalize)")
        }
        if !dropped.isEmpty {
          print("  Drop overrides: \(dropped.sorted().joined(separator: ", ")) (not in file; revert to auto-equalize)")
        }
        print("  Start Date:     \(dateStr)")
        print()

        guard confirm("Apply this schedule? [y/N] ") else {
          cancelled()
          return
        }

        do {
          try await IAPCommand.postSchedule(
            iapID: iap.id,
            baseTerritoryID: base,
            manualPrices: [baseEntry] + overrides,
            startDate: dateStr,
            client: client
          )
        } catch {
          print()
          print(red("The schedule POST failed") + " — no changes were applied. Re-run the same command to retry.")
          throw error
        }

        print()
        success("Imported", "price schedule for '\(iap.attributes?.name ?? productID)'.")
      }
    }

  }

  // MARK: - Availability

  struct Availability: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "availability",
      abstract: "View or update per-IAP territory availability.",
      discussion: """
        An IAP's availability is distinct from the app's. By default an IAP inherits its
        app's territories. Use --add / --remove to change the per-IAP territory list.
        Each edit replaces the full availability schedule (wholesale POST).
        """
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Argument(help: "The product identifier of the in-app purchase.")
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
      let iap = try await findIAP(productID: productID, appID: app.id, client: client)

      try await runProductAvailability(
        productID: productID,
        productNoun: "IAP",
        add: add,
        remove: remove,
        availableInNewTerritories: availableInNewTerritories,
        verbose: verbose,
        fetchCurrent: {
          let response = try await client.send(
            Resources.v2.inAppPurchases.id(iap.id).inAppPurchaseAvailability.get(
              include: [.availableTerritories],
              limitAvailableTerritories: 50
            )
          )
          // Paginate for the full list
          var territories: [String] = []
          for try await page in client.pages(
            Resources.v1.inAppPurchaseAvailabilities.id(response.data.id).availableTerritories.get(limit: 200)
          ) {
            territories.append(contentsOf: page.data.map(\.id))
          }
          return (response.data.attributes?.isAvailableInNewTerritories, territories)
        },
        post: { availableInNew, territories in
          _ = try await client.send(
            Resources.v1.inAppPurchaseAvailabilities.post(
              InAppPurchaseAvailabilityCreateRequest(
                data: .init(
                  attributes: .init(isAvailableInNewTerritories: availableInNew),
                  relationships: .init(
                    inAppPurchase: .init(data: .init(id: iap.id)),
                    availableTerritories: .init(data: territories.map { .init(id: $0) })
                  )
                )
              )
            )
          )
        }
      )
    }
  }

  // MARK: - OfferCode

  struct OfferCode: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "offer-code",
      abstract: "Manage offer codes for in-app purchases.",
      subcommands: [List.self, Info.self, Create.self, Toggle.self, GenCodes.self, AddCustomCodes.self, ViewCodes.self]
    )

    // MARK: List

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "List offer codes for an in-app purchase."
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

        var codes: [InAppPurchaseOfferCode] = []
        for try await page in client.pages(
          Resources.v2.inAppPurchases.id(iap.id).offerCodes.get(limit: 200)
        ) {
          codes.append(contentsOf: page.data)
        }

        if codes.isEmpty {
          print("No offer codes for \(productID).")
          return
        }

        Table.print(
          headers: ["ID", "Name", "Active", "Eligibilities"],
          rows: codes.map { c in
            let attrs = c.attributes
            let elig = attrs?.customerEligibilities?.map { $0.rawValue }.joined(separator: ", ") ?? "—"
            return [
              c.id,
              attrs?.name ?? "—",
              attrs?.isActive == true ? "Yes" : attrs?.isActive == false ? "No" : "—",
              elig,
            ]
          }
        )
      }
    }

    // MARK: Info

    struct Info: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Show details for an offer code (prices + code counts)."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the in-app purchase.")
      var productID: String

      @Argument(help: "The offer code ID (from `offer-code list`).")
      var offerCodeID: String

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        _ = try await findIAP(productID: productID, appID: app.id, client: client)

        let response = try await client.send(
          Resources.v1.inAppPurchaseOfferCodes.id(offerCodeID).get(
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

        let priceCount = response.data.relationships?.prices?.data?.count ?? 0
        let oneTimeCount = response.data.relationships?.oneTimeUseCodes?.data?.count ?? 0
        let customCount = response.data.relationships?.customCodes?.data?.count ?? 0
        print()
        print("Prices:        \(priceCount) territor\(priceCount == 1 ? "y" : "ies")")
        print("One-Time Codes Batches: \(oneTimeCount)")
        print("Custom Codes:           \(customCount)")
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

      @Argument(help: "The product identifier of the in-app purchase.")
      var productID: String

      @Option(name: .long, help: "Reference name for this offer code.")
      var name: String

      @Option(name: .long, help: "Comma-separated customer eligibilities. Valid values: NON_SPENDER, ACTIVE_SPENDER, CHURNED_SPENDER.")
      var eligibility: String

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
        let iap = try await findIAP(productID: productID, appID: app.id, client: client)

        let eligibilities: [InAppPurchaseOfferCodeCreateRequest.Data.Attributes.CustomerEligibility] = try eligibility
          .split(separator: ",")
          .map { $0.trimmingCharacters(in: .whitespaces) }
          .map { try parseEnum($0, name: "eligibility") }
        guard !eligibilities.isEmpty else {
          throw ValidationError("--eligibility cannot be empty.")
        }

        let territoryID = territory.uppercased()
        let resolved = try await IAPCommand.resolvePricePoint(
          iapID: iap.id, territoryID: territoryID, customerPrice: price, client: client)

        // Build (territory, pricePointID) tuples
        var priceEntries: [(territory: String, pricePointID: String)] = []
        if equalizeAllTerritories {
          var equalized: [InAppPurchasePricePoint] = []
          for try await page in client.pages(
            Resources.v1.inAppPurchasePricePoints.id(resolved.point.id).equalizations.get(
              filterInAppPurchaseV2: [iap.id], limit: 200, include: [.territory]
            )
          ) {
            equalized.append(contentsOf: page.data)
          }
          if !equalized.contains(where: { $0.relationships?.territory?.data?.id == territoryID }) {
            equalized.insert(resolved.point, at: 0)
          }
          for point in equalized {
            guard let t = point.relationships?.territory?.data?.id else { continue }
            priceEntries.append((t, point.id))
          }
        } else {
          priceEntries.append((territoryID, resolved.point.id))
        }

        print()
        print("Create offer code:")
        print("  Subscription:  (n/a — IAP)")
        print("  IAP:           \(productID)")
        print("  Name:          \(name)")
        print("  Eligibilities: \(eligibilities.map { $0.rawValue }.joined(separator: ", "))")
        print("  Source Tier:   \(resolved.point.attributes?.customerPrice ?? "?") \(resolved.currency ?? "") (\(territoryID))")
        print("  Territories:   \(priceEntries.count)\(equalizeAllTerritories ? " (equalized)" : " (single)")")
        print()

        guard confirm("Create this offer code? [y/N] ") else {
          cancelled()
          return
        }

        // Build inline price entries
        var inlines: [InAppPurchaseOfferPriceInlineCreate] = []
        var refs: [InAppPurchaseOfferCodeCreateRequest.Data.Relationships.Prices.Datum] = []
        for (i, entry) in priceEntries.enumerated() {
          let localID = "${price\(i)}"
          inlines.append(
            InAppPurchaseOfferPriceInlineCreate(
              id: localID,
              relationships: .init(
                territory: .init(data: .init(id: entry.territory)),
                pricePoint: .init(data: .init(id: entry.pricePointID))
              )
            )
          )
          refs.append(.init(id: localID))
        }

        let response = try await client.send(
          Resources.v1.inAppPurchaseOfferCodes.post(
            InAppPurchaseOfferCodeCreateRequest(
              data: .init(
                attributes: .init(name: name, customerEligibilities: eligibilities),
                relationships: .init(
                  inAppPurchase: .init(data: .init(id: iap.id)),
                  prices: .init(data: refs)
                )
              ),
              included: inlines
            )
          )
        )

        print()
        success("Created", "offer code '\(name)' (id: \(response.data.id)).")
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

      @Argument(help: "The product identifier of the in-app purchase.")
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
        try await IAPCommand.validateOwnedOfferCode(
          offerCodeID, bundleID: bundleID, productID: productID, client: client)

        guard confirm("Set offer code \(offerCodeID) active=\(activeBool)? [y/N] ") else {
          cancelled()
          return
        }

        _ = try await client.send(
          Resources.v1.inAppPurchaseOfferCodes.id(offerCodeID).patch(
            InAppPurchaseOfferCodeUpdateRequest(
              data: .init(id: offerCodeID, attributes: .init(isActive: activeBool))
            )
          )
        )
        print()
        success("Updated", "offer code \(offerCodeID) (active=\(activeBool)).")
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

      @Argument(help: "The product identifier of the in-app purchase.")
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
        try await IAPCommand.validateOwnedOfferCode(
          offerCodeID, bundleID: bundleID, productID: productID, client: client)

        print("Generate \(count) one-time-use code(s):")
        print("  Offer Code ID: \(offerCodeID)")
        print("  Expires:       \(expires)")
        print("  Environment:   \(env.map { $0.rawValue } ?? "PRODUCTION (default)")")
        print()

        guard confirm("Generate? [y/N] ") else {
          cancelled()
          return
        }

        let response = try await client.send(
          Resources.v1.inAppPurchaseOfferCodeOneTimeUseCodes.post(
            InAppPurchaseOfferCodeOneTimeUseCodeCreateRequest(
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
        success("Created", "one-time-use code batch (id: \(batchID)).")
        print()
        print("Codes are generated asynchronously. Fetch with:")
        print("  ascelerate iap offer-code view-codes \(batchID)")
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

      @Argument(help: "The product identifier of the in-app purchase.")
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
        try await IAPCommand.validateOwnedOfferCode(
          offerCodeID, bundleID: bundleID, productID: productID, client: client)

        print("Add custom code:")
        print("  Offer Code ID: \(offerCodeID)")
        print("  Code:          \(code)")
        print("  Redemptions:   \(count)")
        if let expires { print("  Expires:       \(expires)") }
        print()

        guard confirm("Create? [y/N] ") else {
          cancelled()
          return
        }

        let response = try await client.send(
          Resources.v1.inAppPurchaseOfferCodeCustomCodes.post(
            InAppPurchaseOfferCodeCustomCodeCreateRequest(
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
        success("Created", "custom code '\(code)' (id: \(response.data.id)).")
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

        try await runOfferCodeViewCodes(output: output) {
          try await client.send(
            Resources.v1.inAppPurchaseOfferCodeOneTimeUseCodes.id(batchID).values.get
          )
        }
      }
    }
  }

  // MARK: - Images

  struct Images: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "images",
      abstract: "Manage promotional images for an in-app purchase.",
      subcommands: [List.self, Upload.self, Delete.self]
    )

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "List uploaded images for an in-app purchase."
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

        try await runProductImagesList(productID: productID) {
          var images: [InAppPurchaseImage] = []
          for try await page in client.pages(
            Resources.v2.inAppPurchases.id(iap.id).images.get(limit: 50)
          ) {
            images.append(contentsOf: page.data)
          }
          return images.map { img in
            [
              img.id,
              img.attributes?.fileName ?? "—",
              img.attributes?.fileSize.map { formatBytes($0) } ?? "—",
              img.attributes?.state.map { formatState($0) } ?? "—",
            ]
          }
        }
      }
    }

    struct Upload: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Upload a promotional image (.png or .jpg) for an in-app purchase."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the in-app purchase.")
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
        let iap = try await findIAP(productID: productID, appID: app.id, client: client)

        try await runProductAssetUpload(
          file: file,
          summary: { media in
            [
              "Upload image:",
              "  Product:  \(productID)",
              "  File:     \(media.fileName)",
              "  Size:     \(formatBytes(media.fileSize))",
            ]
          },
          reserve: { media in
            let response = try await client.send(
              Resources.v1.inAppPurchaseImages.post(
                InAppPurchaseImageCreateRequest(
                  data: .init(
                    attributes: .init(fileSize: media.fileSize, fileName: media.fileName),
                    relationships: .init(inAppPurchase: .init(data: .init(id: iap.id)))
                  )
                )
              )
            )
            return (response.data.id, response.data.attributes?.uploadOperations ?? [])
          },
          commit: { id, md5 in
            _ = try await client.send(
              Resources.v1.inAppPurchaseImages.id(id).patch(
                InAppPurchaseImageUpdateRequest(
                  data: .init(
                    id: id,
                    attributes: .init(sourceFileChecksum: md5, isUploaded: true)
                  )
                )
              )
            )
          },
          successDetail: { imageID, media in "\(media.fileName) (id: \(imageID))." }
        )
      }
    }

    struct Delete: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Delete an uploaded image."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the in-app purchase.")
      var productID: String

      @Argument(help: "The image ID (from `images list`).")
      var imageID: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        _ = try await findApp(bundleID: bundleID, client: client)

        try await runProductImageDelete(imageID: imageID) {
          _ = try await client.send(
            Resources.v1.inAppPurchaseImages.id(imageID).delete
          )
        }
      }
    }
  }

  // MARK: - ReviewScreenshot

  struct ReviewScreenshot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "review-screenshot",
      abstract: "Manage the App Review screenshot for an in-app purchase (one per IAP).",
      subcommands: [View.self, Upload.self, Delete.self]
    )

    struct View: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Show the current App Review screenshot."
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

        try await runReviewScreenshotView(productID: productID) {
          let response = try await client.send(
            Resources.v2.inAppPurchases.id(iap.id).appStoreReviewScreenshot.get()
          )
          let attrs = response.data.attributes
          return (
            response.data.id,
            attrs?.fileName,
            attrs?.fileSize.map { formatBytes($0) },
            attrs?.assetDeliveryState?.state.map { formatState($0) }
          )
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

      @Argument(help: "The product identifier of the in-app purchase.")
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
        let iap = try await findIAP(productID: productID, appID: app.id, client: client)

        try await runProductAssetUpload(
          file: file,
          summary: { media in
            [
              "Upload review screenshot:",
              "  Product: \(productID)",
              "  File:    \(media.fileName)",
              "  Size:    \(formatBytes(media.fileSize))",
            ]
          },
          reserve: { media in
            let response = try await client.send(
              Resources.v1.inAppPurchaseAppStoreReviewScreenshots.post(
                InAppPurchaseAppStoreReviewScreenshotCreateRequest(
                  data: .init(
                    attributes: .init(fileSize: media.fileSize, fileName: media.fileName),
                    relationships: .init(inAppPurchaseV2: .init(data: .init(id: iap.id)))
                  )
                )
              )
            )
            return (response.data.id, response.data.attributes?.uploadOperations ?? [])
          },
          commit: { id, md5 in
            _ = try await client.send(
              Resources.v1.inAppPurchaseAppStoreReviewScreenshots.id(id).patch(
                InAppPurchaseAppStoreReviewScreenshotUpdateRequest(
                  data: .init(
                    id: id,
                    attributes: .init(sourceFileChecksum: md5, isUploaded: true)
                  )
                )
              )
            )
          },
          successDetail: { screenshotID, _ in "review screenshot (id: \(screenshotID))." }
        )
      }
    }

    struct Delete: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Delete the App Review screenshot."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The product identifier of the in-app purchase.")
      var productID: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let iap = try await findIAP(productID: productID, appID: app.id, client: client)

        try await runReviewScreenshotDelete(
          productID: productID,
          fetchID: {
            let response = try await client.send(
              Resources.v2.inAppPurchases.id(iap.id).appStoreReviewScreenshot.get()
            )
            return response.data.id
          },
          delete: { screenshotID in
            _ = try await client.send(
              Resources.v1.inAppPurchaseAppStoreReviewScreenshots.id(screenshotID).delete
            )
          }
        )
      }
    }
  }
}
