import ASCKit
import Foundation

/// Offer codes of in-app purchases and subscriptions: offers customers redeem with a code. An
/// offer has its eligibility and prices (and for a subscription its type and length); its codes
/// are batches of one-time-use codes, which Apple generates after the request, and custom codes
/// redeemable a number of times. Offers and codes are turned off rather than deleted.
public enum OfferCodes {
  public enum Product: Sendable {
    case inAppPurchase, subscription
  }

  public struct OfferCode: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let isActive: Bool?
    /// In-app purchases: NON_SPENDER, ACTIVE_SPENDER, CHURNED_SPENDER. Subscriptions: NEW,
    /// EXISTING, EXPIRED.
    public let customerEligibilities: [String]
    /// Subscriptions: STACK_WITH_INTRO_OFFERS or REPLACE_INTRO_OFFERS.
    public let offerEligibility: String?
    /// Subscriptions: FREE_TRIAL, PAY_AS_YOU_GO or PAY_UP_FRONT.
    public let mode: String?
    public let duration: String?
    public let periods: Int?
    public let autoRenew: Bool?
    public let productionCodeCount: Int?
    public let sandboxCodeCount: Int?
  }

  /// A batch of one-time-use codes.
  public struct Batch: Hashable, Identifiable, Sendable {
    public let id: String
    public let numberOfCodes: Int?
    /// `yyyy-MM-dd`.
    public let expirationDate: String?
    /// PRODUCTION or SANDBOX.
    public let environment: String?
    public let isActive: Bool?
    public let createdDate: Date?
  }

  /// A code customers type, redeemable `numberOfCodes` times.
  public struct CustomCode: Hashable, Identifiable, Sendable {
    public let id: String
    public let code: String?
    public let numberOfCodes: Int?
    public let expirationDate: String?
    public let isActive: Bool?
    public let createdDate: Date?
  }

  /// An offer with how many territories it's priced in and how many batches and custom codes it
  /// has (up to 50 of each counted).
  public struct Detail: Sendable {
    public let offer: OfferCode
    public let priceCount: Int
    public let batchCount: Int
    public let customCodeCount: Int
  }

  /// The product's offer codes.
  public static func list(_ product: Product, productRecordID: String, client: ASCClient) async throws -> [OfferCode] {
    switch product {
      case .inAppPurchase:
        try await ASCPaging.allPages(next: { $0.links.next }) {
          try await client.inAppPurchasesV2OfferCodesGetToManyRelated(path: .init(id: productRecordID), query: .init(limit: 200))
            .ok.body.json
        }.flatMap(\.data).map(offerCode)
      case .subscription:
        try await ASCPaging.allPages(next: { $0.links.next }) {
          try await client.subscriptionsOfferCodesGetToManyRelated(path: .init(id: productRecordID), query: .init(limit: 200))
            .ok.body.json
        }.flatMap(\.data).map(offerCode)
    }
  }

  /// One offer with its counts. Included prices are capped at 50 (a higher limit is refused), so
  /// the price count is the relationship's total.
  public static func detail(_ product: Product, id: String, client: ASCClient) async throws -> Detail {
    switch product {
      case .inAppPurchase:
        let data = try await client.inAppPurchaseOfferCodesGetInstance(
          path: .init(id: id),
          query: .init(include: [.prices, .oneTimeUseCodes, .customCodes], limitCustomCodes: 50, limitOneTimeUseCodes: 50, limitPrices: 50)
        ).ok.body.json.data
        let r = data.relationships
        return Detail(
          offer: offerCode(data), priceCount: r?.prices?.meta?.paging.total ?? r?.prices?.data?.count ?? 0,
          batchCount: r?.oneTimeUseCodes?.data?.count ?? 0, customCodeCount: r?.customCodes?.data?.count ?? 0)
      case .subscription:
        let data = try await client.subscriptionOfferCodesGetInstance(
          path: .init(id: id),
          query: .init(include: [.prices, .oneTimeUseCodes, .customCodes], limitCustomCodes: 50, limitOneTimeUseCodes: 50, limitPrices: 50)
        ).ok.body.json.data
        let r = data.relationships
        return Detail(
          offer: offerCode(data), priceCount: r?.prices?.meta?.paging.total ?? r?.prices?.data?.count ?? 0,
          batchCount: r?.oneTimeUseCodes?.data?.count ?? 0, customCodeCount: r?.customCodes?.data?.count ?? 0)
    }
  }

  /// An offer's batches of one-time-use codes, newest first.
  public static func batches(_ product: Product, offerCodeID: String, client: ASCClient) async throws -> [Batch] {
    let batches: [Batch] =
      switch product {
        case .inAppPurchase:
          try await ASCPaging.allPages(next: { $0.links.next }) {
            try await client.inAppPurchaseOfferCodesOneTimeUseCodesGetToManyRelated(
              path: .init(id: offerCodeID), query: .init(limit: 200)
            ).ok.body.json
          }.flatMap(\.data).map {
            let a = $0.attributes
            return Batch(
              id: $0.id, numberOfCodes: a?.numberOfCodes, expirationDate: a?.expirationDate, environment: a?.environment,
              isActive: a?.active, createdDate: a?.createdDate)
          }
        case .subscription:
          try await ASCPaging.allPages(next: { $0.links.next }) {
            try await client.subscriptionOfferCodesOneTimeUseCodesGetToManyRelated(
              path: .init(id: offerCodeID), query: .init(limit: 200)
            ).ok.body.json
          }.flatMap(\.data).map {
            let a = $0.attributes
            return Batch(
              id: $0.id, numberOfCodes: a?.numberOfCodes, expirationDate: a?.expirationDate, environment: a?.environment,
              isActive: a?.active, createdDate: a?.createdDate)
          }
      }
    return batches.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
  }

  /// An offer's custom codes, newest first.
  public static func customCodes(_ product: Product, offerCodeID: String, client: ASCClient) async throws -> [CustomCode] {
    let codes: [CustomCode] =
      switch product {
        case .inAppPurchase:
          try await ASCPaging.allPages(next: { $0.links.next }) {
            try await client.inAppPurchaseOfferCodesCustomCodesGetToManyRelated(
              path: .init(id: offerCodeID), query: .init(limit: 200)
            ).ok.body.json
          }.flatMap(\.data).map {
            let a = $0.attributes
            return CustomCode(
              id: $0.id, code: a?.customCode, numberOfCodes: a?.numberOfCodes, expirationDate: a?.expirationDate,
              isActive: a?.active, createdDate: a?.createdDate)
          }
        case .subscription:
          try await ASCPaging.allPages(next: { $0.links.next }) {
            try await client.subscriptionOfferCodesCustomCodesGetToManyRelated(
              path: .init(id: offerCodeID), query: .init(limit: 200)
            ).ok.body.json
          }.flatMap(\.data).map {
            let a = $0.attributes
            return CustomCode(
              id: $0.id, code: a?.customCode, numberOfCodes: a?.numberOfCodes, expirationDate: a?.expirationDate,
              isActive: a?.active, createdDate: a?.createdDate)
          }
      }
    return codes.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
  }

  /// Creates an in-app purchase's offer code with its prices (each with a tier) in one request.
  public static func createForInAppPurchase(
    purchaseID: String, name: String, eligibilities: [String], prices: [Subscriptions.OfferPrice], client: ASCClient
  ) async throws -> OfferCode {
    let localIDs = prices.indices.map { "${price\($0)}" }
    let inlines = zip(localIDs, prices).map { localID, price in
      Components.Schemas.InAppPurchaseOfferPriceInlineCreate(
        id: localID,
        relationships: .init(
          pricePoint: price.pricePointID.map { .init(data: .init(id: $0, _type: "inAppPurchasePricePoints")) },
          territory: .init(data: .init(id: price.territoryID, _type: "territories"))
        ),
        _type: "inAppPurchaseOfferPrices"
      )
    }
    return offerCode(try await client.inAppPurchaseOfferCodesCreateInstance(body: .json(.init(
      data: .init(
        attributes: .init(customerEligibilities: eligibilities, name: name),
        relationships: .init(
          inAppPurchase: .init(data: .init(id: purchaseID, _type: "inAppPurchases")),
          prices: .init(data: localIDs.map { .init(id: $0, _type: "inAppPurchaseOfferPrices") })
        ),
        _type: "inAppPurchaseOfferCodes"
      ),
      included: inlines
    ))).created.body.json.data)
  }

  /// Creates a subscription's offer code with its prices in one request; a free offer's prices
  /// have no tier. A nil `autoRenew` leaves Apple's default.
  public static func createForSubscription(
    subscriptionID: String, name: String, eligibilities: [String], offerEligibility: String, mode: String,
    duration: String, periods: Int, autoRenew: Bool?, prices: [Subscriptions.OfferPrice], client: ASCClient
  ) async throws -> OfferCode {
    let localIDs = prices.indices.map { "${price\($0)}" }
    let inlines = zip(localIDs, prices).map { localID, price in
      Components.Schemas.SubscriptionOfferCodePriceInlineCreate(
        id: localID,
        relationships: .init(
          subscriptionPricePoint: price.pricePointID.map { .init(data: .init(id: $0, _type: "subscriptionPricePoints")) },
          territory: .init(data: .init(id: price.territoryID, _type: "territories"))
        ),
        _type: "subscriptionOfferCodePrices"
      )
    }
    return offerCode(try await client.subscriptionOfferCodesCreateInstance(body: .json(.init(
      data: .init(
        attributes: .init(
          autoRenewEnabled: autoRenew,
          customerEligibilities: eligibilities,
          duration: duration,
          name: name,
          numberOfPeriods: periods,
          offerEligibility: offerEligibility,
          offerMode: mode
        ),
        relationships: .init(
          prices: .init(data: localIDs.map { .init(id: $0, _type: "subscriptionOfferCodePrices") }),
          subscription: .init(data: .init(id: subscriptionID, _type: "subscriptions"))
        ),
        _type: "subscriptionOfferCodes"
      ),
      included: inlines
    ))).created.body.json.data)
  }

  /// Turns an offer on or off.
  public static func setActive(_ product: Product, id: String, active: Bool, client: ASCClient) async throws {
    switch product {
      case .inAppPurchase:
        _ = try await client.inAppPurchaseOfferCodesUpdateInstance(
          path: .init(id: id),
          body: .json(.init(data: .init(attributes: .init(active: active), id: id, _type: "inAppPurchaseOfferCodes")))
        ).ok
      case .subscription:
        _ = try await client.subscriptionOfferCodesUpdateInstance(
          path: .init(id: id),
          body: .json(.init(data: .init(attributes: .init(active: active), id: id, _type: "subscriptionOfferCodes")))
        ).ok
    }
  }

  /// Requests a batch of one-time-use codes (`expirationDate` `yyyy-MM-dd`; nil environment:
  /// Apple's default, production). Apple generates the codes afterwards. Returns the batch's ID.
  public static func generateCodes(
    _ product: Product, offerCodeID: String, count: Int, expirationDate: String, environment: String?, client: ASCClient
  ) async throws -> String {
    switch product {
      case .inAppPurchase:
        try await client.inAppPurchaseOfferCodeOneTimeUseCodesCreateInstance(body: .json(.init(data: .init(
          attributes: .init(environment: environment, expirationDate: expirationDate, numberOfCodes: count),
          relationships: .init(offerCode: .init(data: .init(id: offerCodeID, _type: "inAppPurchaseOfferCodes"))),
          _type: "inAppPurchaseOfferCodeOneTimeUseCodes"
        )))).created.body.json.data.id
      case .subscription:
        try await client.subscriptionOfferCodeOneTimeUseCodesCreateInstance(body: .json(.init(data: .init(
          attributes: .init(environment: environment, expirationDate: expirationDate, numberOfCodes: count),
          relationships: .init(offerCode: .init(data: .init(id: offerCodeID, _type: "subscriptionOfferCodes"))),
          _type: "subscriptionOfferCodeOneTimeUseCodes"
        )))).created.body.json.data.id
    }
  }

  /// Adds a custom code redeemable `count` times. Returns its ID.
  public static func addCustomCode(
    _ product: Product, offerCodeID: String, code: String, count: Int, expirationDate: String?, client: ASCClient
  ) async throws -> String {
    switch product {
      case .inAppPurchase:
        try await client.inAppPurchaseOfferCodeCustomCodesCreateInstance(body: .json(.init(data: .init(
          attributes: .init(customCode: code, expirationDate: expirationDate, numberOfCodes: count),
          relationships: .init(offerCode: .init(data: .init(id: offerCodeID, _type: "inAppPurchaseOfferCodes"))),
          _type: "inAppPurchaseOfferCodeCustomCodes"
        )))).created.body.json.data.id
      case .subscription:
        try await client.subscriptionOfferCodeCustomCodesCreateInstance(body: .json(.init(data: .init(
          attributes: .init(customCode: code, expirationDate: expirationDate, numberOfCodes: count),
          relationships: .init(offerCode: .init(data: .init(id: offerCodeID, _type: "subscriptionOfferCodes"))),
          _type: "subscriptionOfferCodeCustomCodes"
        )))).created.body.json.data.id
    }
  }

  /// A batch's codes as Apple sends them (CSV text); empty while Apple is still generating them.
  public static func codeValues(_ product: Product, batchID: String, client: ASCClient) async throws -> String {
    switch product {
      case .inAppPurchase:
        try await String(
          collecting: client.inAppPurchaseOfferCodeOneTimeUseCodesValuesGetToOneRelated(path: .init(id: batchID)).ok.body.csv,
          upTo: 50 << 20)
      case .subscription:
        try await String(
          collecting: client.subscriptionOfferCodeOneTimeUseCodesValuesGetToOneRelated(path: .init(id: batchID)).ok.body.csv,
          upTo: 50 << 20)
    }
  }

  private static func offerCode(_ data: Components.Schemas.InAppPurchaseOfferCode) -> OfferCode {
    let a = data.attributes
    return OfferCode(
      id: data.id, name: a?.name, isActive: a?.active, customerEligibilities: a?.customerEligibilities ?? [],
      offerEligibility: nil, mode: nil, duration: nil, periods: nil, autoRenew: nil,
      productionCodeCount: a?.productionCodeCount, sandboxCodeCount: a?.sandboxCodeCount)
  }

  private static func offerCode(_ data: Components.Schemas.SubscriptionOfferCode) -> OfferCode {
    let a = data.attributes
    return OfferCode(
      id: data.id, name: a?.name, isActive: a?.active, customerEligibilities: a?.customerEligibilities ?? [],
      offerEligibility: a?.offerEligibility, mode: a?.offerMode, duration: a?.duration, periods: a?.numberOfPeriods,
      autoRenew: a?.autoRenewEnabled, productionCodeCount: a?.productionCodeCount, sandboxCodeCount: a?.sandboxCodeCount)
  }
}
