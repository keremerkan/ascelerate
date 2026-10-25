import ASCKit
import Foundation

/// A subscription's promotional offers: discounts for existing or past subscribers that the app
/// offers with a payload its server signs, by the offer's code. Only the prices change after
/// creating one; anything else is delete and create.
extension Subscriptions {
  public struct PromotionalOffer: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    /// The identifier the app passes when it offers it (unique within the subscription).
    public let offerCode: String?
    /// FREE_TRIAL, PAY_AS_YOU_GO or PAY_UP_FRONT.
    public let mode: String?
    /// How long one period lasts (`ASCEnum.SubscriptionOfferDuration`).
    public let duration: String?
    public let periods: Int?
  }

  /// A price of an offer in one territory. A free trial's has no tier: Apple refuses one ("For
  /// FREE_TRIAL offerMode, subscriptionPricePoint must be null") but still needs a record per
  /// territory it's offered in (seen 2026-10-25).
  public struct OfferPrice: Hashable, Sendable {
    public let territoryID: String
    public let pricePointID: String?

    public init(territoryID: String, pricePointID: String?) {
      self.territoryID = territoryID
      self.pricePointID = pricePointID
    }
  }

  public static func promotionalOffers(subscriptionID: String, client: ASCClient) async throws -> [PromotionalOffer] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.subscriptionsPromotionalOffersGetToManyRelated(path: .init(id: subscriptionID), query: .init(limit: 200))
        .ok.body.json
    }.flatMap(\.data).map(promotionalOffer)
  }

  /// One offer, with how many territories it has a price in. Included prices are capped at 50 (a
  /// higher limit is refused), so the count is the relationship's total.
  public static func promotionalOffer(id: String, client: ASCClient) async throws -> (offer: PromotionalOffer, priceCount: Int) {
    let data = try await client.subscriptionPromotionalOffersGetInstance(
      path: .init(id: id), query: .init(include: [.prices], limitPrices: 50)
    ).ok.body.json.data
    let prices = data.relationships?.prices
    return (promotionalOffer(data), prices?.meta?.paging.total ?? prices?.data?.count ?? 0)
  }

  /// Creates an offer with its prices in one request.
  public static func createPromotionalOffer(
    subscriptionID: String, name: String, offerCode: String, mode: String, duration: String, periods: Int,
    prices: [OfferPrice], client: ASCClient
  ) async throws -> PromotionalOffer {
    let (localIDs, inlines) = promotionalOfferPrices(prices)
    return promotionalOffer(try await client.subscriptionPromotionalOffersCreateInstance(body: .json(.init(
      data: .init(
        attributes: .init(duration: duration, name: name, numberOfPeriods: periods, offerCode: offerCode, offerMode: mode),
        relationships: .init(
          prices: .init(data: localIDs.map { .init(id: $0, _type: "subscriptionPromotionalOfferPrices") }),
          subscription: .init(data: .init(id: subscriptionID, _type: "subscriptions"))
        ),
        _type: "subscriptionPromotionalOffers"
      ),
      included: inlines
    ))).created.body.json.data)
  }

  /// Replaces an offer's prices.
  public static func setPromotionalOfferPrices(id: String, prices: [OfferPrice], client: ASCClient) async throws {
    let (localIDs, inlines) = promotionalOfferPrices(prices)
    _ = try await client.subscriptionPromotionalOffersUpdateInstance(
      path: .init(id: id),
      body: .json(.init(
        data: .init(
          id: id,
          relationships: .init(
            prices: .init(data: localIDs.map { .init(id: $0, _type: "subscriptionPromotionalOfferPrices") })),
          _type: "subscriptionPromotionalOffers"
        ),
        included: inlines
      ))
    ).ok
  }

  public static func deletePromotionalOffer(id: String, client: ASCClient) async throws {
    _ = try await client.subscriptionPromotionalOffersDeleteInstance(path: .init(id: id)).noContent
  }

  /// Prices as inline creates, and the local IDs the offer refers to them by.
  private static func promotionalOfferPrices(
    _ prices: [OfferPrice]
  ) -> (localIDs: [String], inlines: [Components.Schemas.SubscriptionPromotionalOfferPriceInlineCreate]) {
    let localIDs = prices.indices.map { "${price\($0)}" }
    let inlines = zip(localIDs, prices).map { localID, price in
      Components.Schemas.SubscriptionPromotionalOfferPriceInlineCreate(
        id: localID,
        relationships: .init(
          subscriptionPricePoint: price.pricePointID.map { .init(data: .init(id: $0, _type: "subscriptionPricePoints")) },
          territory: .init(data: .init(id: price.territoryID, _type: "territories"))
        ),
        _type: "subscriptionPromotionalOfferPrices"
      )
    }
    return (localIDs, inlines)
  }

  private static func promotionalOffer(_ data: Components.Schemas.SubscriptionPromotionalOffer) -> PromotionalOffer {
    let a = data.attributes
    return PromotionalOffer(
      id: data.id, name: a?.name, offerCode: a?.offerCode, mode: a?.offerMode, duration: a?.duration,
      periods: a?.numberOfPeriods)
  }
}
