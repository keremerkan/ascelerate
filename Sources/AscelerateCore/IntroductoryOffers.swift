import ASCKit
import Foundation

/// A subscription's introductory offers for new subscribers: a free trial, or a lower price paid
/// each period (pay as you go) or once (pay up front).
///
/// Seen live 2026-10-22: an offer is one record per territory (creating one without a territory
/// is refused), and a subscription PATCH with the offers inline creates any number of them in one
/// request (175 in about four seconds), all or none. Only the end date changes afterwards; each
/// offer is deleted on its own. A territory's offers can't overlap (an offer without a start
/// date starts today, one without an end date never ends), and it takes one future offer at most.
extension Subscriptions {
  public struct IntroductoryOffer: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let territoryID: String
    /// FREE_TRIAL, PAY_AS_YOU_GO or PAY_UP_FRONT.
    public let mode: String
    /// How long one period lasts (`ASCEnum.SubscriptionOfferDuration`).
    public let duration: String
    public let periods: Int
    /// `yyyy-MM-dd`; Apple fills in the creation day when none was sent.
    public let startDate: String?
    /// `yyyy-MM-dd`, or nil when the offer doesn't end.
    public let endDate: String?
    /// What the customer pays per period (pay as you go) or once (pay up front); nil when free.
    public let customerPrice: String?

    /// Whether the offer still runs or is yet to start on `day` (`yyyy-MM-dd`).
    public func isCurrentOrFuture(on day: String) -> Bool {
      endDate.map { $0 >= day } ?? true
    }

    /// Whether the offer runs on any day of `start`…`end` (nil start: `today`; nil end: no end).
    public func overlaps(start: String?, end: String?, today: String) -> Bool {
      let newStart = start ?? today, newEnd = end ?? "9999-12-31"
      let ownStart = startDate ?? today, ownEnd = endDate ?? "9999-12-31"
      return ownStart <= newEnd && newStart <= ownEnd
    }
  }

  /// The subscription's offers, ended ones included.
  public static func introductoryOffers(subscriptionID: String, client: ASCClient) async throws -> [IntroductoryOffer] {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.subscriptionsIntroductoryOffersGetToManyRelated(
          path: .init(id: subscriptionID), query: .init(limit: 200, include: [.subscriptionPricePoint, .territory])
        ).ok.body.json
      }
    }
    var prices: [String: String] = [:]
    for case .subscriptionPricePoints(let point) in pages.flatMap({ $0.included ?? [] }) {
      prices[point.id] = point.attributes?.customerPrice
    }
    return pages.flatMap(\.data).map { offer in
      let attributes = offer.attributes
      let mode = attributes?.offerMode ?? ""
      return IntroductoryOffer(
        id: offer.id, territoryID: offer.relationships?.territory?.data?.id ?? "", mode: mode,
        duration: attributes?.duration ?? "", periods: attributes?.numberOfPeriods ?? 1,
        startDate: attributes?.startDate, endDate: attributes?.endDate,
        customerPrice: mode == "FREE_TRIAL" ? nil : offer.relationships?.subscriptionPricePoint?.data.flatMap { prices[$0.id] })
    }
  }

  /// The territories of `territoryIDs` where an offer from `start` to `end` can't go: one of
  /// theirs overlaps it, or it starts later and they already have an offer starting later.
  public static func introductoryOfferConflicts(
    _ territoryIDs: [String], existing: [IntroductoryOffer], start: String?, end: String?, today: String
  ) -> Set<String> {
    let isFuture = (start ?? today) > today
    return Set(territoryIDs.filter { territoryID in
      existing.contains { offer in
        offer.territoryID == territoryID
          && (offer.overlaps(start: start, end: end, today: today) || (isFuture && (offer.startDate ?? today) > today))
      }
    })
  }

  /// Creates one offer per territory in a single request: `prices` gives each territory's price
  /// point (from the subscription's tiers), and is ignored for a free trial. Nil dates: from
  /// today, without an end.
  public static func createIntroductoryOffers(
    subscriptionID: String, mode: String, duration: String, periods: Int, startDate: String?, endDate: String?,
    territoryIDs: [String], prices: [String: String] = [:], client: ASCClient
  ) async throws {
    let free = mode == "FREE_TRIAL"
    let localIDs = territoryIDs.indices.map { "${offer\($0)}" }
    let included: [Components.Schemas.SubscriptionUpdateRequest.IncludedPayloadPayload] = zip(localIDs, territoryIDs).map { localID, territoryID in
      .SubscriptionIntroductoryOfferInlineCreate(.init(
        attributes: .init(
          duration: duration, endDate: endDate, numberOfPeriods: periods, offerMode: mode, startDate: startDate),
        id: localID,
        relationships: .init(
          subscriptionPricePoint: free ? nil : prices[territoryID].map { .init(data: .init(id: $0, _type: "subscriptionPricePoints")) },
          territory: .init(data: .init(id: territoryID, _type: "territories"))),
        _type: "subscriptionIntroductoryOffers"))
    }
    _ = try await client.subscriptionsUpdateInstance(
      path: .init(id: subscriptionID),
      body: .json(.init(
        data: .init(
          id: subscriptionID,
          relationships: .init(introductoryOffers: .init(data: localIDs.map { .init(id: $0, _type: "subscriptionIntroductoryOffers") })),
          _type: "subscriptions"),
        included: included))
    ).ok
  }

  /// Sets when an offer ends (nil: never, sent as null).
  public static func setIntroductoryOfferEnd(id: String, endDate: String?, client: ASCClient) async throws {
    _ = try await ASCNulls.sending(endDate == nil ? [["data", "attributes", "endDate"]] : []) {
      try await client.subscriptionIntroductoryOffersUpdateInstance(
        path: .init(id: id),
        body: .json(.init(data: .init(attributes: .init(endDate: endDate), id: id, _type: "subscriptionIntroductoryOffers")))
      ).ok
    }
  }

  public static func deleteIntroductoryOffer(id: String, client: ASCClient) async throws {
    _ = try await withTransientRetry {
      try await client.subscriptionIntroductoryOffersDeleteInstance(path: .init(id: id)).noContent
    }
  }
}
