import ASCKit
import Foundation

/// A subscription's win-back offers: discounts or free time the App Store offers people whose
/// subscription ended, from a start date (and to an end date). Only an approved subscription takes
/// one (409 "Offers can only be created for approved subscriptions"). Apple's rules, from its 409s
/// on 2026-11-05: months since they last subscribed as a range, minimum 1–23 and maximum 2–24 (the
/// maximum is required); paid subscription duration 1–24, 36, 48 or 60 months; wait between offers
/// 2–24 months; a start date from tomorrow; an end date at least 3 days after the start. Prices
/// are inline like a retention offer's (the prepare script supplies their relationships).
extension Subscriptions {
  public struct WinBackOffer: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    /// The offer's identifier (unique within the subscription).
    public let offerID: String?
    public let mode: String?
    public let duration: String?
    public let periods: Int?
    public let paidMonths: Int?
    /// Months since they last subscribed: at least, and at most.
    public let sinceMonths: ClosedRange<Int>?
    public let waitMonths: Int?
    /// yyyy-MM-dd
    public let startDate: String?
    public let endDate: String?
    /// HIGH or NORMAL: which offer the App Store shows first.
    public let priority: String?
    /// NOT_PROMOTED or USE_AUTO_GENERATED_ASSETS (promoted on the App Store).
    public let promotionIntent: String?
    public let planType: String?
  }

  /// What changes on an offer (nil: left as it is): its eligibility, dates, priority and promotion.
  public struct WinBackChanges: Sendable {
    public var paidMonths: Int?
    public var sinceMonths: ClosedRange<Int>?
    public var waitMonths: Int?
    public var startDate: String?
    public var endDate: String?
    public var priority: String?
    public var promotionIntent: String?

    public init(
      paidMonths: Int? = nil, sinceMonths: ClosedRange<Int>? = nil, waitMonths: Int? = nil, startDate: String? = nil,
      endDate: String? = nil, priority: String? = nil, promotionIntent: String? = nil
    ) {
      (self.paidMonths, self.sinceMonths, self.waitMonths, self.startDate) = (paidMonths, sinceMonths, waitMonths, startDate)
      (self.endDate, self.priority, self.promotionIntent) = (endDate, priority, promotionIntent)
    }

    public var isEmpty: Bool {
      paidMonths == nil && sinceMonths == nil && waitMonths == nil && startDate == nil && endDate == nil && priority == nil
        && promotionIntent == nil
    }
  }

  public static let winBackSinceMinimum = 1...23
  public static let winBackSinceMaximum = 2...24

  public static func winBackOffers(subscriptionID: String, client: ASCClient) async throws -> [WinBackOffer] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.subscriptionsWinBackOffersGetToManyRelated(path: .init(id: subscriptionID), query: .init(limit: 200))
        .ok.body.json
    }.flatMap(\.data).map(winBackOffer)
  }

  /// One offer, with how many territories it has a price in.
  public static func winBackOffer(id: String, client: ASCClient) async throws -> (offer: WinBackOffer, priceCount: Int) {
    let data = try await client.winBackOffersGetInstance(path: .init(id: id), query: .init(include: [.prices], limitPrices: 50))
      .ok.body.json.data
    let prices = data.relationships?.prices
    return (winBackOffer(data), prices?.meta?.paging.total ?? prices?.data?.count ?? 0)
  }

  /// Creates an offer with its prices in one request.
  public static func createWinBackOffer(
    subscriptionID: String, name: String, offerID: String, mode: String, duration: String, periods: Int,
    paidMonths: Int, sinceMonths: ClosedRange<Int>, waitMonths: Int?, startDate: String, endDate: String?,
    priority: String, promotionIntent: String?, planType: String?, prices: [OfferPrice], client: ASCClient
  ) async throws -> WinBackOffer {
    let localIDs = prices.indices.map { "${price\($0)}" }
    let inlines = zip(localIDs, prices).map { localID, price in
      Components.Schemas.WinBackOfferPriceInlineCreate(
        id: localID,
        relationships: .init(
          subscriptionPricePoint: price.pricePointID.map { .init(data: .init(id: $0, _type: "subscriptionPricePoints")) },
          territory: .init(data: .init(id: price.territoryID, _type: "territories"))),
        _type: "winBackOfferPrices")
    }
    return winBackOffer(try await client.winBackOffersCreateInstance(body: .json(.init(
      data: .init(
        attributes: .init(
          customerEligibilityPaidSubscriptionDurationInMonths: paidMonths,
          customerEligibilityTimeSinceLastSubscribedInMonths: .init(maximum: sinceMonths.upperBound, minimum: sinceMonths.lowerBound),
          customerEligibilityWaitBetweenOffersInMonths: waitMonths, duration: duration, endDate: endDate, offerId: offerID,
          offerMode: mode, periodCount: periods, priority: priority, promotionIntent: promotionIntent, referenceName: name,
          startDate: startDate, targetSubscriptionPlanType: planType),
        relationships: .init(
          prices: .init(data: localIDs.map { .init(id: $0, _type: "winBackOfferPrices") }),
          subscription: .init(data: .init(id: subscriptionID, _type: "subscriptions"))),
        _type: "winBackOffers"),
      included: inlines
    ))).created.body.json.data)
  }

  public static func updateWinBackOffer(id: String, _ changes: WinBackChanges, client: ASCClient) async throws {
    _ = try await client.winBackOffersUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(
        attributes: .init(
          customerEligibilityPaidSubscriptionDurationInMonths: changes.paidMonths,
          customerEligibilityTimeSinceLastSubscribedInMonths: changes.sinceMonths.map {
            .init(maximum: $0.upperBound, minimum: $0.lowerBound)
          },
          customerEligibilityWaitBetweenOffersInMonths: changes.waitMonths, endDate: changes.endDate, priority: changes.priority,
          promotionIntent: changes.promotionIntent, startDate: changes.startDate),
        id: id, _type: "winBackOffers")))
    ).ok
  }

  public static func deleteWinBackOffer(id: String, client: ASCClient) async throws {
    _ = try await client.winBackOffersDeleteInstance(path: .init(id: id)).noContent
  }

  private static func winBackOffer(_ data: Components.Schemas.WinBackOffer) -> WinBackOffer {
    let a = data.attributes
    let since = a?.customerEligibilityTimeSinceLastSubscribedInMonths
    return WinBackOffer(
      id: data.id, name: a?.referenceName, offerID: a?.offerId, mode: a?.offerMode, duration: a?.duration, periods: a?.periodCount,
      paidMonths: a?.customerEligibilityPaidSubscriptionDurationInMonths,
      sinceMonths: since.flatMap { since in since.minimum.flatMap { min in since.maximum.map { min...max($0, min) } } },
      waitMonths: a?.customerEligibilityWaitBetweenOffersInMonths, startDate: a?.startDate, endDate: a?.endDate,
      priority: a?.priority, promotionIntent: a?.promotionIntent, planType: a?.targetSubscriptionPlanType)
  }
}
