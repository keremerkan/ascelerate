import ASCKit
import Foundation

/// An app's auto-renewable subscriptions: subscription groups with their localizations, and each
/// group's subscriptions (their level in the group, duration, localizations, prices per territory,
/// availability, promotional image and App Review screenshot).
public enum Subscriptions {
  public struct Group: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let referenceName: String
    /// In the order Apple lists them; `level` orders them (1 is the highest service level).
    public let subscriptions: [Subscription]
  }

  public struct Subscription: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let productID: String
    /// The reference name.
    public let name: String
    /// ONE_WEEK, ONE_MONTH, TWO_MONTHS, THREE_MONTHS, SIX_MONTHS or ONE_YEAR.
    public let period: String?
    public let state: String
    /// The service level in its group: 1 is the highest; subscriptions on one level are
    /// crossgrades of each other.
    public let level: Int?
    public let familySharable: Bool?
    public let reviewNote: String?

    init(_ subscription: Components.Schemas.Subscription) {
      let attributes = subscription.attributes
      id = subscription.id
      productID = attributes?.productId ?? ""
      name = attributes?.name ?? ""
      period = attributes?.subscriptionPeriod
      state = attributes?.state ?? ""
      level = attributes?.groupLevel
      familySharable = attributes?.familySharable
      reviewNote = attributes?.reviewNote
    }
  }

  /// A group's name customers see in one language (and the app name shown with it).
  public struct GroupLocalization: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let locale: String
    public let name: String
    public let customAppName: String?
    public let state: String?

    init(_ localization: Components.Schemas.SubscriptionGroupLocalization) {
      id = localization.id
      locale = localization.attributes?.locale ?? ""
      name = localization.attributes?.name ?? ""
      customAppName = localization.attributes?.customAppName
      state = localization.attributes?.state
    }
  }

  /// A subscription's display name and description in one language.
  public struct Localization: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let locale: String
    public let name: String
    public let description: String
    public let state: String?

    init(_ localization: Components.Schemas.SubscriptionLocalization) {
      id = localization.id
      locale = localization.attributes?.locale ?? ""
      name = localization.attributes?.name ?? ""
      description = localization.attributes?.description ?? ""
      state = localization.attributes?.state
    }
  }

  /// A subscription price in one territory: from its start date (nil: from the start) until the
  /// territory's next price. A preserved price is what existing subscribers keep paying.
  public struct Price: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let territoryID: String
    public let pricePointID: String
    public let customerPrice: String
    public let proceeds: String
    public let startDate: String?
    public let preserved: Bool
  }

  /// A subscription's prices (its upfront billing plan's), with each territory's currency.
  public struct Prices: Codable, Hashable, Sendable {
    public let prices: [Price]
    public let currencies: [String: String]

    /// What new subscribers pay today in each territory: the latest price that started. A raise
    /// that keeps existing subscribers on their price marks the price before it preserved, which
    /// new subscribers still pay until the raise starts; on the same start date the raise wins.
    public var current: [String: Price] {
      let today = AppPricing.today
      return Dictionary(grouping: prices.filter { ($0.startDate ?? "") <= today }, by: \.territoryID)
        .compactMapValues { $0.max { ($0.startDate ?? "", $0.preserved ? 0 : 1) < ($1.startDate ?? "", $1.preserved ? 0 : 1) } }
    }

    /// Prices that start later, by date.
    public var planned: [Price] {
      let today = AppPricing.today
      return prices.filter { ($0.startDate ?? "") > today }.sorted { ($0.startDate ?? "", $0.territoryID) < ($1.startDate ?? "", $1.territoryID) }
    }
  }

  /// Where a subscription is sold, for one billing plan.
  public struct Availability: Codable, Hashable, Sendable {
    public let id: String
    public let availableInNewTerritories: Bool
    public let territories: [String]
  }

  public enum LookupError: LocalizedError {
    case notFound(String)

    public var errorDescription: String? {
      switch self {
        case .notFound(let productID): "No subscription found with product ID '\(productID)'."
      }
    }
  }

  // MARK: Groups

  /// The app's subscription groups with their subscriptions.
  public static func groups(appID: String, client: ASCClient) async throws -> [Group] {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.appsSubscriptionGroupsGetToManyRelated(
          path: .init(id: appID), query: .init(include: [.subscriptions], limitSubscriptions: 50)
        ).ok.body.json
      }
    }
    var groups: [Group] = []
    for page in pages {
      var byID: [String: Components.Schemas.Subscription] = [:]
      for case .subscriptions(let subscription) in page.included ?? [] {
        byID[subscription.id] = subscription
      }
      for group in page.data {
        let ids = group.relationships?.subscriptions?.data?.map(\.id) ?? []
        var subscriptions = ids.compactMap { byID[$0] }
        if ids.count >= 50 {
          // The include is capped at 50: a group at the cap may have more.
          subscriptions = try await ASCPaging.allPages(next: { $0.links.next }) {
            try await client.subscriptionGroupsSubscriptionsGetToManyRelated(path: .init(id: group.id), query: .init(limit: 50))
              .ok.body.json
          }.flatMap(\.data)
        }
        groups.append(Group(
          id: group.id, referenceName: group.attributes?.referenceName ?? "",
          subscriptions: subscriptions.map(Subscription.init)))
      }
    }
    return groups
  }

  /// The subscription with that product ID, and its group.
  public static func find(productID: String, appID: String, client: ASCClient) async throws -> (subscription: Subscription, group: Group) {
    for group in try await groups(appID: appID, client: client) {
      if let match = group.subscriptions.first(where: { $0.productID == productID }) {
        return (match, group)
      }
    }
    throw LookupError.notFound(productID)
  }

  public static func get(id: String, client: ASCClient) async throws -> Subscription {
    Subscription(try await client.subscriptionsGetInstance(path: .init(id: id)).ok.body.json.data)
  }

  @discardableResult
  public static func createGroup(appID: String, referenceName: String, client: ASCClient) async throws -> Group {
    let group = try await client.subscriptionGroupsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(referenceName: referenceName),
      relationships: .init(app: .init(data: .init(id: appID, _type: "apps"))),
      _type: "subscriptionGroups"
    )))).created.body.json.data
    return Group(id: group.id, referenceName: group.attributes?.referenceName ?? referenceName, subscriptions: [])
  }

  public static func updateGroup(id: String, referenceName: String, client: ASCClient) async throws {
    _ = try await client.subscriptionGroupsUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(attributes: .init(referenceName: referenceName), id: id, _type: "subscriptionGroups")))
    ).ok
  }

  public static func deleteGroup(id: String, client: ASCClient) async throws {
    _ = try await client.subscriptionGroupsDeleteInstance(path: .init(id: id)).noContent
  }

  /// Submits the group's pending version (its localizations) for review with the app.
  public static func submitGroup(id: String, client: ASCClient) async throws {
    _ = try await client.subscriptionGroupSubmissionsCreateInstance(body: .json(.init(data: .init(
      relationships: .init(subscriptionGroup: .init(data: .init(id: id, _type: "subscriptionGroups"))),
      _type: "subscriptionGroupSubmissions"
    )))).created
  }

  public static func groupLocalizations(groupID: String, client: ASCClient) async throws -> [GroupLocalization] {
    try await client.subscriptionGroupsSubscriptionGroupLocalizationsGetToManyRelated(
      path: .init(id: groupID), query: .init(limit: 50)
    ).ok.body.json.data.map(GroupLocalization.init)
  }

  @discardableResult
  public static func createGroupLocalization(
    groupID: String, locale: String, name: String, customAppName: String?, client: ASCClient
  ) async throws -> GroupLocalization {
    GroupLocalization(try await client.subscriptionGroupLocalizationsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(customAppName: customAppName, locale: locale, name: name),
      relationships: .init(subscriptionGroup: .init(data: .init(id: groupID, _type: "subscriptionGroups"))),
      _type: "subscriptionGroupLocalizations"
    )))).created.body.json.data)
  }

  /// Changes a group localization; nil leaves a value as it is.
  @discardableResult
  public static func updateGroupLocalization(
    id: String, name: String? = nil, customAppName: String? = nil, client: ASCClient
  ) async throws -> GroupLocalization {
    GroupLocalization(try await client.subscriptionGroupLocalizationsUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(
        attributes: .init(customAppName: customAppName, name: name), id: id, _type: "subscriptionGroupLocalizations")))
    ).ok.body.json.data)
  }

  public static func deleteGroupLocalization(id: String, client: ASCClient) async throws {
    _ = try await client.subscriptionGroupLocalizationsDeleteInstance(path: .init(id: id)).noContent
  }

  // MARK: Subscriptions

  @discardableResult
  public static func create(
    groupID: String, productID: String, name: String, period: String? = nil, level: Int? = nil,
    reviewNote: String? = nil, familySharable: Bool = false, client: ASCClient
  ) async throws -> Subscription {
    Subscription(try await client.subscriptionsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(
        familySharable: familySharable ? true : nil, groupLevel: level, name: name, productId: productID,
        reviewNote: reviewNote, subscriptionPeriod: period),
      relationships: .init(group: .init(data: .init(id: groupID, _type: "subscriptionGroups"))),
      _type: "subscriptions"
    )))).created.body.json.data)
  }

  /// Changes a subscription; nil leaves a value as it is.
  @discardableResult
  public static func update(
    id: String, name: String? = nil, period: String? = nil, level: Int? = nil, reviewNote: String? = nil,
    familySharable: Bool? = nil, client: ASCClient
  ) async throws -> Subscription {
    Subscription(try await client.subscriptionsUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(
        attributes: .init(
          familySharable: familySharable, groupLevel: level, name: name, reviewNote: reviewNote,
          subscriptionPeriod: period),
        id: id, _type: "subscriptions")))
    ).ok.body.json.data)
  }

  public static func delete(id: String, client: ASCClient) async throws {
    _ = try await client.subscriptionsDeleteInstance(path: .init(id: id)).noContent
  }

  /// Submits the subscription's pending version for review (it's reviewed with an app version).
  public static func submit(id: String, client: ASCClient) async throws {
    _ = try await client.subscriptionSubmissionsCreateInstance(body: .json(.init(data: .init(
      relationships: .init(subscription: .init(data: .init(id: id, _type: "subscriptions"))),
      _type: "subscriptionSubmissions"
    )))).created
  }

  public static func localizations(subscriptionID: String, client: ASCClient) async throws -> [Localization] {
    try await client.subscriptionsSubscriptionLocalizationsGetToManyRelated(
      path: .init(id: subscriptionID), query: .init(limit: 50)
    ).ok.body.json.data.map(Localization.init)
  }

  @discardableResult
  public static func createLocalization(
    subscriptionID: String, locale: String, name: String, description: String?, client: ASCClient
  ) async throws -> Localization {
    Localization(try await client.subscriptionLocalizationsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(description: description, locale: locale, name: name),
      relationships: .init(subscription: .init(data: .init(id: subscriptionID, _type: "subscriptions"))),
      _type: "subscriptionLocalizations"
    )))).created.body.json.data)
  }

  /// Changes a localization; nil leaves a value as it is.
  @discardableResult
  public static func updateLocalization(
    id: String, name: String? = nil, description: String? = nil, client: ASCClient
  ) async throws -> Localization {
    Localization(try await client.subscriptionLocalizationsUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(
        attributes: .init(description: description, name: name), id: id, _type: "subscriptionLocalizations")))
    ).ok.body.json.data)
  }

  public static func deleteLocalization(id: String, client: ASCClient) async throws {
    _ = try await client.subscriptionLocalizationsDeleteInstance(path: .init(id: id)).noContent
  }

  // MARK: Prices

  /// The subscription's prices on its upfront billing plan, current, planned and preserved.
  public static func prices(subscriptionID: String, client: ASCClient) async throws -> Prices {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.subscriptionsPricesGetToManyRelated(
          path: .init(id: subscriptionID), query: .init(limit: 200, include: [.subscriptionPricePoint, .territory])
        ).ok.body.json
      }
    }
    var points: [String: Components.Schemas.SubscriptionPricePoint] = [:]
    var currencies: [String: String] = [:]
    for included in pages.flatMap({ $0.included ?? [] }) {
      switch included {
        case .subscriptionPricePoints(let point): points[point.id] = point
        case .territories(let territory): currencies[territory.id] = territory.attributes?.currency
      }
    }
    let prices = pages.flatMap(\.data).compactMap { price -> Price? in
      // The monthly plan (12-month commitment) has its own prices.
      guard price.attributes?.planType.map({ $0 == "UPFRONT" }) ?? true,
        let territoryID = price.relationships?.territory?.data?.id,
        let pointID = price.relationships?.subscriptionPricePoint?.data?.id, let point = points[pointID]
      else { return nil }
      return Price(
        id: price.id, territoryID: territoryID, pricePointID: pointID,
        customerPrice: point.attributes?.customerPrice ?? "", proceeds: point.attributes?.proceeds ?? "",
        startDate: price.attributes?.startDate, preserved: price.attributes?.preserved ?? false)
    }
    return Prices(prices: prices, currencies: currencies)
  }

  private static func pricePoint(_ point: Components.Schemas.SubscriptionPricePoint, territoryID: String) -> AppPricing.PricePoint {
    AppPricing.PricePoint(
      id: point.id, territoryID: territoryID, customerPrice: point.attributes?.customerPrice ?? "",
      proceeds: point.attributes?.proceeds ?? "")
  }

  /// A territory's price tiers for the subscription, cheapest first.
  public static func pricePoints(subscriptionID: String, territoryID: String, client: ASCClient) async throws -> [AppPricing.PricePoint] {
    try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.subscriptionsPricePointsGetToManyRelated(
          path: .init(id: subscriptionID),
          query: .init(filterTerritory: [territoryID], fieldsSubscriptionPricePoints: [.customerPrice, .proceeds], limit: 200)
        ).ok.body.json
      }
    }.flatMap(\.data).map { pricePoint($0, territoryID: territoryID) }
      .sorted { (Decimal(string: $0.customerPrice) ?? 0) < (Decimal(string: $1.customerPrice) ?? 0) }
  }

  /// Several territories' price tiers for the subscription, cheapest first: one request for up to
  /// nine territories (about 800 tiers each; `limit` takes 8000), where one territory alone pages
  /// at 200.
  public static func pricePoints(subscriptionID: String, territoryIDs: [String], client: ASCClient) async throws -> [String: [AppPricing.PricePoint]] {
    let points = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.subscriptionsPricePointsGetToManyRelated(
          path: .init(id: subscriptionID),
          query: .init(
            filterTerritory: territoryIDs, fieldsSubscriptionPricePoints: [.customerPrice, .proceeds, .territory], limit: 8000,
            include: [.territory])
        ).ok.body.json
      }
    }.flatMap(\.data)
    var tiers: [String: [AppPricing.PricePoint]] = [:]
    for point in points {
      guard let territoryID = point.relationships?.territory?.data?.id else { continue }
      tiers[territoryID, default: []].append(pricePoint(point, territoryID: territoryID))
    }
    return tiers.mapValues { $0.sorted { (Decimal(string: $0.customerPrice) ?? 0) < (Decimal(string: $1.customerPrice) ?? 0) } }
  }

  /// What a tier comes to in every other territory, with each territory's currency.
  public static func equalizations(
    of pricePointID: String, client: ASCClient
  ) async throws -> (points: [AppPricing.PricePoint], currencies: [String: String]) {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.subscriptionPricePointsEqualizationsGetToManyRelated(
          path: .init(id: pricePointID), query: .init(limit: 200, include: [.territory])
        ).ok.body.json
      }
    }
    var currencies: [String: String] = [:]
    for page in pages {
      for territory in page.included ?? [] { currencies[territory.id] = territory.attributes?.currency }
    }
    let points = pages.flatMap(\.data).compactMap { point -> AppPricing.PricePoint? in
      guard let territoryID = point.relationships?.territory?.data?.id else { return nil }
      return pricePoint(point, territoryID: territoryID)
    }
    return (points, currencies)
  }

  /// Sets a territory's price from a day (nil: as soon as Apple can). For a raise,
  /// `preserveCurrent` keeps existing subscribers on their price; a cut reaches them anyway.
  public static func setPrice(
    subscriptionID: String, territoryID: String, pricePointID: String, startDate: String? = nil,
    preserveCurrent: Bool? = nil, client: ASCClient
  ) async throws {
    let request = Components.Schemas.SubscriptionPriceCreateRequest(data: .init(
      attributes: .init(preserveCurrentPrice: preserveCurrent, startDate: startDate),
      relationships: .init(
        subscription: .init(data: .init(id: subscriptionID, _type: "subscriptions")),
        subscriptionPricePoint: .init(data: .init(id: pricePointID, _type: "subscriptionPricePoints")),
        territory: .init(data: .init(id: territoryID, _type: "territories"))),
      _type: "subscriptionPrices"))
    _ = try await withTransientRetry {
      try await client.subscriptionPricesCreateInstance(body: .json(request)).created
    }
  }

  /// Removes a planned price (one that hasn't started).
  public static func deletePrice(id: String, client: ASCClient) async throws {
    _ = try await client.subscriptionPricesDeleteInstance(path: .init(id: id)).noContent
  }

  // MARK: Availability

  /// Where the subscription is sold on a billing plan (UPFRONT, or MONTHLY with a 12-month
  /// commitment); nil when it has none of its own.
  public static func availability(subscriptionID: String, plan: String = "UPFRONT", client: ASCClient) async throws -> Availability? {
    let plans = try await client.subscriptionsPlanAvailabilitiesGetToManyRelated(path: .init(id: subscriptionID)).ok.body.json.data
    guard let availability = plans.first(where: { $0.attributes?.planType == plan }) else { return nil }
    let territories = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.subscriptionPlanAvailabilitiesAvailableTerritoriesGetToManyRelated(
          path: .init(id: availability.id), query: .init(limit: 200)
        ).ok.body.json
      }
    }.flatMap { $0.data.map(\.id) }
    return Availability(
      id: availability.id, availableInNewTerritories: availability.attributes?.availableInNewTerritories ?? false,
      territories: territories)
  }

  /// Replaces a billing plan's availability, creating it when the subscription has none
  /// (`existingID` nil).
  public static func setAvailability(
    subscriptionID: String, plan: String = "UPFRONT", existingID: String?, availableInNewTerritories: Bool,
    territories: [String], client: ASCClient
  ) async throws {
    let linkage = territories.map { Components.Schemas.SubscriptionPlanAvailabilityUpdateRequest.DataPayload.RelationshipsPayload.AvailableTerritoriesPayload.DataPayloadPayload(id: $0, _type: "territories") }
    if let existingID {
      _ = try await client.subscriptionPlanAvailabilitiesUpdateInstance(
        path: .init(id: existingID),
        body: .json(.init(data: .init(
          attributes: .init(availableInNewTerritories: availableInNewTerritories), id: existingID,
          relationships: .init(availableTerritories: .init(data: linkage)), _type: "subscriptionPlanAvailabilities")))
      ).ok
    } else {
      _ = try await client.subscriptionPlanAvailabilitiesCreateInstance(body: .json(.init(data: .init(
        attributes: .init(availableInNewTerritories: availableInNewTerritories, planType: plan),
        relationships: .init(
          availableTerritories: .init(data: territories.map { .init(id: $0, _type: "territories") }),
          subscription: .init(data: .init(id: subscriptionID, _type: "subscriptions"))),
        _type: "subscriptionPlanAvailabilities"
      )))).created
    }
  }

  // MARK: Images

  public static func images(subscriptionID: String, client: ASCClient) async throws -> [InAppPurchases.Image] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.subscriptionsImagesGetToManyRelated(path: .init(id: subscriptionID), query: .init(limit: 50)).ok.body.json
    }.flatMap(\.data).map { image in
      let attributes = image.attributes
      return InAppPurchases.Image(
        id: image.id, fileName: attributes?.fileName ?? "", fileSize: attributes?.fileSize ?? 0,
        templateURL: attributes?.imageAsset?.templateUrl.flatMap { $0.isEmpty ? nil : $0 }, width: attributes?.imageAsset?.width,
        height: attributes?.imageAsset?.height, state: attributes?.state)
    }
  }

  /// Uploads a promotional image (1024×1024).
  @discardableResult
  public static func uploadImage(subscriptionID: String, filePath: String, client: ASCClient) async throws -> String {
    let media = try MediaFile(path: filePath)
    return try await uploadAsset(
      filePath: media.path,
      reserve: {
        let response = try await client.subscriptionImagesCreateInstance(body: .json(.init(data: .init(
          attributes: .init(fileName: media.fileName, fileSize: media.fileSize),
          relationships: .init(subscription: .init(data: .init(id: subscriptionID, _type: "subscriptions"))),
          _type: "subscriptionImages"
        )))).created.body.json
        return (response.data.id, response.data.attributes?.uploadOperations ?? [])
      },
      commit: { id, md5 in
        _ = try await client.subscriptionImagesUpdateInstance(
          path: .init(id: id),
          body: .json(.init(data: .init(
            attributes: .init(sourceFileChecksum: md5, uploaded: true), id: id, _type: "subscriptionImages")))
        ).ok
      })
  }

  public static func deleteImage(id: String, client: ASCClient) async throws {
    _ = try await client.subscriptionImagesDeleteInstance(path: .init(id: id)).noContent
  }

  /// The screenshot App Review sees; nil when there's none.
  public static func reviewScreenshot(subscriptionID: String, client: ASCClient) async throws -> InAppPurchases.Image? {
    guard let screenshot = try await optionalRelated({
      try await client.subscriptionsAppStoreReviewScreenshotGetToOneRelated(path: .init(id: subscriptionID)).ok.body.json.data
    }) else { return nil }
    let attributes = screenshot.attributes
    return InAppPurchases.Image(
      id: screenshot.id, fileName: attributes?.fileName ?? "", fileSize: attributes?.fileSize ?? 0,
      templateURL: attributes?.imageAsset?.templateUrl.flatMap { $0.isEmpty ? nil : $0 }, width: attributes?.imageAsset?.width,
      height: attributes?.imageAsset?.height, state: attributes?.assetDeliveryState?.state)
  }

  @discardableResult
  public static func uploadReviewScreenshot(subscriptionID: String, filePath: String, client: ASCClient) async throws -> String {
    let media = try MediaFile(path: filePath)
    return try await uploadAsset(
      filePath: media.path,
      reserve: {
        let response = try await client.subscriptionAppStoreReviewScreenshotsCreateInstance(body: .json(.init(data: .init(
          attributes: .init(fileName: media.fileName, fileSize: media.fileSize),
          relationships: .init(subscription: .init(data: .init(id: subscriptionID, _type: "subscriptions"))),
          _type: "subscriptionAppStoreReviewScreenshots"
        )))).created.body.json
        return (response.data.id, response.data.attributes?.uploadOperations ?? [])
      },
      commit: { id, md5 in
        _ = try await client.subscriptionAppStoreReviewScreenshotsUpdateInstance(
          path: .init(id: id),
          body: .json(.init(data: .init(
            attributes: .init(sourceFileChecksum: md5, uploaded: true), id: id,
            _type: "subscriptionAppStoreReviewScreenshots")))
        ).ok
      })
  }

  public static func deleteReviewScreenshot(id: String, client: ASCClient) async throws {
    _ = try await client.subscriptionAppStoreReviewScreenshotsDeleteInstance(path: .init(id: id)).noContent
  }
}
