import ASCKit
import Foundation

/// Multiseat subscriptions: an auto-renewable subscription bought for several people, by
/// organizations through Apple Business Manager and Apple School Manager, or by App Store
/// customers who then invite others to their seats. A subscription's multiseat switch and markets,
/// the app's invitation host, and volume pricing: up to four more per-seat prices, each from a seat
/// count on, on a price in a territory.
extension Subscriptions {
  // MARK: Invitation host

  /// Who sends the seat invitations of the app's multiseat App Store purchases: `APPLE_HOSTED`
  /// (Apple's default) or `DEVELOPER_HOSTED` (the app's own flow, which then verifies invited
  /// members' ages and gets any parental consent). Applies to purchases made after a change.
  public static func groupPurchaseInvitationMode(appID: String, client: ASCClient) async throws -> String {
    try await client.appsGetInstance(path: .init(id: appID), query: .init(fieldsApps: [.groupPurchaseInvitationMode]))
      .ok.body.json.data.attributes?.groupPurchaseInvitationMode ?? "APPLE_HOSTED"
  }

  /// Changes who hosts seat invitations and returns it as saved.
  public static func setGroupPurchaseInvitationMode(appID: String, mode: String, client: ASCClient) async throws -> String {
    try await client.appsUpdateInstance(
      path: .init(id: appID),
      body: .json(.init(data: .init(attributes: .init(groupPurchaseInvitationMode: mode), id: appID, _type: "apps")))
    ).ok.body.json.data.attributes?.groupPurchaseInvitationMode ?? mode
  }

  // MARK: Multiseat purchasing

  /// Whether a subscription can be bought in quantities over one, and where.
  public struct MultiSeat: Codable, Equatable, Sendable {
    /// `multiSeatStatus` ENABLED, Apple's default for every auto-renewable subscription. Family
    /// Sharing doesn't turn it off (a family-shareable subscription read Allowed in App Store
    /// Connect, 2026-11-25), although Apple's article says it does.
    public var enabled: Bool
    /// `APP_STORE`, `APPLE_BUSINESS`, `APPLE_SCHOOL`: where it's offered while enabled.
    public var markets: [String]

    public init(enabled: Bool, markets: [String]) {
      self.enabled = enabled
      self.markets = markets
    }

    init(_ attributes: Components.Schemas.Subscription.AttributesPayload?) {
      enabled = (attributes?.multiSeatStatus ?? "ENABLED") == "ENABLED"
      markets = attributes?.marketSettings ?? []
    }
  }

  public static func multiSeat(subscriptionID: String, client: ASCClient) async throws -> MultiSeat {
    MultiSeat(try await client.subscriptionsGetInstance(
      path: .init(id: subscriptionID), query: .init(fieldsSubscriptions: [.multiSeatStatus, .marketSettings])
    ).ok.body.json.data.attributes)
  }

  /// Changes what's given and returns the setting as saved.
  public static func setMultiSeat(
    subscriptionID: String, enabled: Bool? = nil, markets: [String]? = nil, client: ASCClient
  ) async throws -> MultiSeat {
    MultiSeat(try await client.subscriptionsUpdateInstance(
      path: .init(id: subscriptionID),
      body: .json(.init(data: .init(
        attributes: .init(marketSettings: markets, multiSeatStatus: enabled.map { $0 ? "ENABLED" : "DISABLED" }),
        id: subscriptionID, _type: "subscriptions")))
    ).ok.body.json.data.attributes)
  }

  // MARK: Volume pricing

  /// A per-seat price from `minQuantity` seats up to the next tier's; the single seat is the
  /// price's own price point. Prices come with the tiers read back, not with proposed ones.
  public struct VolumeTier: Codable, Hashable, Sendable {
    public let minQuantity: Int
    public let pricePointID: String
    public var customerPrice: String?
    public var proceeds: String?

    public init(minQuantity: Int, pricePointID: String, customerPrice: String? = nil, proceeds: String? = nil) {
      self.minQuantity = minQuantity
      self.pricePointID = pricePointID
      self.customerPrice = customerPrice
      self.proceeds = proceeds
    }
  }

  /// Apple's rules for a price's tiers, checked before anything is sent (Apple answers each with a
  /// 409: TOO_MANY_PRICE_TIERS, INVALID_PRICE_TIER_QUANTITY, PRICE_TIERS_NOT_ASCENDING,
  /// PRICE_TIERS_NOT_DECREASING).
  public enum VolumeTierError: LocalizedError, Equatable {
    case tooMany
    case firstBelowTwo
    case notAscending
    case notDecreasing(minQuantity: Int)

    public var errorDescription: String? {
      switch self {
        case .tooMany: "A price takes at most four tiers besides the single seat."
        case .firstBelowTwo: "The first tier starts at 2 seats or more."
        case .notAscending: "Each tier starts at more seats than the one before it."
        case .notDecreasing(let minQuantity): "The tier from \(minQuantity) seats must cost less per seat than the one before it."
      }
    }
  }

  /// Checks tiers (with their customer prices) against the single-seat price, in order.
  public static func validate(singleSeatPrice: String, tiers: [VolumeTier]) throws {
    guard tiers.count <= 4 else { throw VolumeTierError.tooMany }
    guard tiers.first.map({ $0.minQuantity >= 2 }) ?? true else { throw VolumeTierError.firstBelowTwo }
    for (earlier, later) in zip(tiers, tiers.dropFirst()) where later.minQuantity <= earlier.minQuantity {
      throw VolumeTierError.notAscending
    }
    var previous = Decimal(string: singleSeatPrice) ?? 0
    for tier in tiers {
      let price = Decimal(string: tier.customerPrice ?? "") ?? previous
      guard price < previous else { throw VolumeTierError.notDecreasing(minQuantity: tier.minQuantity) }
      previous = price
    }
  }

  /// The tiers of every price of the subscription that has any, by price ID, cheapest last. Two
  /// lists: the prices name their tiers, and the tiers (which don't name their territory or
  /// price) carry their price points.
  public static func volumeTiers(subscriptionID: String, client: ASCClient) async throws -> [String: [VolumeTier]] {
    let pricePages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.subscriptionsPricesGetToManyRelated(
          path: .init(id: subscriptionID),
          query: .init(filterPlanType: [.upfront], fieldsSubscriptionPrices: [.additionalPriceTiers], limit: 200, include: [.additionalPriceTiers], limitAdditionalPriceTiers: 50)
        ).ok.body.json
      }
    }
    // A price can come twice (on two pages); the first is kept rather than trapping.
    let tierIDsByPrice = Dictionary(pricePages.flatMap(\.data).compactMap { price -> (String, [String])? in
      guard let ids = price.relationships?.additionalPriceTiers?.data?.map(\.id), !ids.isEmpty else { return nil }
      return (price.id, ids)
    }, uniquingKeysWith: { first, _ in first })
    guard !tierIDsByPrice.isEmpty else { return [:] }
    let tierPages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.subscriptionPriceTiersGetCollection(query: .init(
          filterSubscription: [subscriptionID], fieldsSubscriptionPricePoints: [.customerPrice, .proceeds], limit: 50,
          include: [.subscriptionPricePoint])
        ).ok.body.json
      }
    }
    var points: [String: Components.Schemas.SubscriptionPricePoint] = [:]
    for point in tierPages.flatMap({ $0.included ?? [] }) { points[point.id] = point }
    var tiers: [String: VolumeTier] = [:]
    for tier in tierPages.flatMap(\.data) {
      guard let pointID = tier.relationships?.subscriptionPricePoint?.data?.id else { continue }
      let point = points[pointID]
      tiers[tier.id] = VolumeTier(
        minQuantity: tier.attributes?.minQuantity ?? 0, pricePointID: pointID,
        customerPrice: point?.attributes?.customerPrice, proceeds: point?.attributes?.proceeds)
    }
    return tierIDsByPrice.mapValues { ids in ids.compactMap { tiers[$0] }.sorted { $0.minQuantity < $1.minQuantity } }
  }

  /// A territory's price as Apple equalizes it from a base territory: its single-seat price point
  /// and its tiers, with the same seat counts.
  public struct EqualizedTiers: Hashable, Sendable {
    public let territoryID: String
    public let pricePointID: String
    public let tiers: [VolumeTier]
  }

  /// What a base territory's price and tiers come to in every other territory. Saves nothing.
  public static func equalizeVolumeTiers(
    subscriptionID: String, basePricePointID: String, tiers: [VolumeTier], client: ASCClient
  ) async throws -> [EqualizedTiers] {
    let request = Components.Schemas.SubscriptionPriceTierEqualizationCreateRequest(data: .init(
      attributes: .init(additionalPriceTiers: tiers.map { .init(minQuantity: $0.minQuantity, subscriptionPricePointId: $0.pricePointID) }),
      relationships: .init(
        basePricePoint: .init(data: .init(id: basePricePointID, _type: "subscriptionPricePoints")),
        subscription: .init(data: .init(id: subscriptionID, _type: "subscriptions"))),
      _type: "subscriptionPriceTierEqualizations"))
    let equalization = try await withTransientRetry {
      try await client.subscriptionPriceTierEqualizationsCreateInstance(
        query: .init(fieldsSubscriptionPricePoints: [.customerPrice]), body: .json(request)
      ).created.body.json.data
    }
    return (equalization.attributes?.equalizedPrices ?? []).compactMap { price in
      guard let territoryID = price.territoryId, let pointID = price.basePricePointId else { return nil }
      return EqualizedTiers(
        territoryID: territoryID, pricePointID: pointID,
        tiers: (price.additionalPriceTiers ?? []).map { VolumeTier(minQuantity: $0.minQuantity, pricePointID: $0.subscriptionPricePointId) })
    }
  }

  /// A price a territory would get, for `previewPriceChanges`.
  public struct ProposedPrice: Hashable, Sendable {
    public let territoryID: String
    public let pricePointID: String
    public let tiers: [VolumeTier]
    /// yyyy-MM-dd; nil for now.
    public let startDate: String?

    public init(territoryID: String, pricePointID: String, tiers: [VolumeTier] = [], startDate: String? = nil) {
      self.territoryID = territoryID
      self.pricePointID = pricePointID
      self.tiers = tiers
      self.startDate = startDate
    }
  }

  /// How proposed prices change what existing subscribers pay, by territory, compared at every
  /// seat count: INCREASE_PRESERVABLE (higher or equal everywhere, higher somewhere; they can keep
  /// their price with `preserveCurrent`), DECREASE_NOT_PRESERVABLE, MIXED_NOT_PRESERVABLE (higher
  /// for some seat counts, lower for others, or seat ranges that can't be compared; tiers only),
  /// NO_CHANGE. Saves nothing.
  public static func previewPriceChanges(
    subscriptionID: String, prices: [ProposedPrice], client: ASCClient
  ) async throws -> [String: String] {
    let request = Components.Schemas.SubscriptionPriceChangePreviewCreateRequest(data: .init(
      attributes: .init(proposedChanges: prices.map { price in
        .init(
          additionalPriceTiers: price.tiers.map { .init(minQuantity: $0.minQuantity, subscriptionPricePointId: $0.pricePointID) },
          basePricePointId: price.pricePointID, startDate: price.startDate, territoryId: price.territoryID)
      }),
      relationships: .init(subscription: .init(data: .init(id: subscriptionID, _type: "subscriptions"))),
      _type: "subscriptionPriceChangePreviews"))
    let preview = try await withTransientRetry {
      try await client.subscriptionPriceChangePreviewsCreateInstance(body: .json(request)).created.body.json.data
    }
    var results: [String: String] = [:]
    for result in preview.attributes?.changeResults ?? [] {
      if let territoryID = result.territoryId { results[territoryID] = result.changeType }
    }
    return results
  }

  /// Sets a territory's price with its volume tiers, as one unit that can't be edited afterwards
  /// (a planned one is deleted and made again; one in effect is replaced by a later price). A
  /// price without tiers has the single tier. Upfront plan only: Apple refuses tiers on MONTHLY.
  public static func setPrice(
    subscriptionID: String, territoryID: String, pricePointID: String, tiers: [VolumeTier], startDate: String? = nil,
    preserveCurrent: Bool? = nil, client: ASCClient
  ) async throws {
    guard !tiers.isEmpty else {
      return try await setPrice(
        subscriptionID: subscriptionID, territoryID: territoryID, pricePointID: pricePointID, startDate: startDate,
        preserveCurrent: preserveCurrent, client: client)
    }
    let localIDs = tiers.map { "${tier-\($0.minQuantity)}" }
    let request = Components.Schemas.SubscriptionPriceCreateRequest(
      data: .init(
        attributes: .init(planType: "UPFRONT", preserveCurrentPrice: preserveCurrent, startDate: startDate),
        relationships: .init(
          additionalPriceTiers: .init(data: localIDs.map { .init(id: $0, _type: "subscriptionPriceTiers") }),
          subscription: .init(data: .init(id: subscriptionID, _type: "subscriptions")),
          subscriptionPricePoint: .init(data: .init(id: pricePointID, _type: "subscriptionPricePoints")),
          territory: .init(data: .init(id: territoryID, _type: "territories"))),
        _type: "subscriptionPrices"),
      included: zip(tiers, localIDs).map { tier, localID in
        .init(
          attributes: .init(minQuantity: tier.minQuantity), id: localID,
          relationships: .init(subscriptionPricePoint: .init(data: .init(id: tier.pricePointID, _type: "subscriptionPricePoints"))),
          _type: "subscriptionPriceTiers")
      })
    _ = try await withTransientRetry {
      try await client.subscriptionPricesCreateInstance(body: .json(request)).created
    }
  }
}
