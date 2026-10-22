import ASCKit
import Foundation

/// An app's in-app purchases (v2): consumables, non-consumables and non-renewing subscriptions,
/// with their localizations, price schedule, availability, promotional image and App Review
/// screenshot.
public enum InAppPurchases {
  public struct Purchase: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let productID: String
    /// The reference name (shown in App Store Connect, not on the App Store).
    public let name: String
    /// CONSUMABLE, NON_CONSUMABLE or NON_RENEWING_SUBSCRIPTION.
    public let type: String
    /// MISSING_METADATA, READY_TO_SUBMIT, WAITING_FOR_REVIEW, IN_REVIEW, APPROVED,
    /// DEVELOPER_ACTION_NEEDED, REJECTED, REMOVED_FROM_SALE, ...
    public let state: String
    public let familySharable: Bool
    /// Nil when Apple doesn't say (it often leaves it out).
    public let contentHosting: Bool?
    public let reviewNote: String?

    init(_ purchase: Components.Schemas.InAppPurchaseV2) {
      let attributes = purchase.attributes
      id = purchase.id
      productID = attributes?.productId ?? ""
      name = attributes?.name ?? ""
      type = attributes?.inAppPurchaseType ?? ""
      state = attributes?.state ?? ""
      familySharable = attributes?.familySharable ?? false
      contentHosting = attributes?.contentHosting
      reviewNote = attributes?.reviewNote
    }
  }

  /// The name and description customers see in one language.
  public struct Localization: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let locale: String
    public let name: String
    public let description: String
    public let state: String?

    init(_ localization: Components.Schemas.InAppPurchaseLocalization) {
      id = localization.id
      locale = localization.attributes?.locale ?? ""
      name = localization.attributes?.name ?? ""
      description = localization.attributes?.description ?? ""
      state = localization.attributes?.state
    }
  }

  /// The promotional image or the App Review screenshot.
  public struct Image: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let fileName: String
    public let fileSize: Int
    /// An image URL template (`{w}x{h}bb.{f}`), once Apple has processed the file (it sends an
    /// empty one before).
    public let templateURL: String?
    public let width: Int?
    public let height: Int?
    /// Delivery state: AWAITING_UPLOAD, UPLOAD_COMPLETE, COMPLETE or FAILED; or, for a promotional
    /// image, its review state.
    public let state: String?
  }

  /// Where the purchase is sold; nil when it follows the app's territories.
  public struct Availability: Codable, Hashable, Sendable {
    public let availableInNewTerritories: Bool
    public let territories: [String]
  }

  public enum LookupError: LocalizedError {
    case notFound(String)

    public var errorDescription: String? {
      switch self {
        case .notFound(let productID): "No in-app purchase found with product ID '\(productID)'."
      }
    }
  }

  // MARK: Purchases

  /// The app's in-app purchases, optionally of some types and states.
  public static func list(
    appID: String, types: [String]? = nil, states: [String]? = nil, client: ASCClient
  ) async throws -> [Purchase] {
    typealias Query = Operations.AppsInAppPurchasesV2GetToManyRelated.Input.Query
    let filterType = types?.compactMap(Query.FilterInAppPurchaseTypePayloadPayload.init(rawValue:))
    let filterState = states?.compactMap(Query.FilterStatePayloadPayload.init(rawValue:))
    return try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.appsInAppPurchasesV2GetToManyRelated(
          path: .init(id: appID), query: .init(filterState: filterState, filterInAppPurchaseType: filterType, limit: 200)
        ).ok.body.json
      }
    }.flatMap(\.data).map(Purchase.init)
  }

  /// The purchase with that product ID.
  public static func find(productID: String, appID: String, client: ASCClient) async throws -> Purchase {
    let response = try await client.appsInAppPurchasesV2GetToManyRelated(
      path: .init(id: appID), query: .init(filterProductId: [productID])
    ).ok.body.json
    guard let purchase = response.data.first(where: { $0.attributes?.productId == productID }) ?? response.data.first else {
      throw LookupError.notFound(productID)
    }
    return Purchase(purchase)
  }

  public static func get(id: String, client: ASCClient) async throws -> Purchase {
    Purchase(try await client.inAppPurchasesV2GetInstance(path: .init(id: id)).ok.body.json.data)
  }

  @discardableResult
  public static func create(
    appID: String, type: String, productID: String, name: String, reviewNote: String? = nil,
    familySharable: Bool = false, client: ASCClient
  ) async throws -> Purchase {
    Purchase(try await client.inAppPurchasesV2CreateInstance(body: .json(.init(data: .init(
      attributes: .init(
        familySharable: familySharable ? true : nil, inAppPurchaseType: type, name: name, productId: productID,
        reviewNote: reviewNote),
      relationships: .init(app: .init(data: .init(id: appID, _type: "apps"))),
      _type: "inAppPurchases"
    )))).created.body.json.data)
  }

  /// Changes the purchase; nil leaves a value as it is.
  @discardableResult
  public static func update(
    id: String, name: String? = nil, reviewNote: String? = nil, familySharable: Bool? = nil, client: ASCClient
  ) async throws -> Purchase {
    Purchase(try await client.inAppPurchasesV2UpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(
        attributes: .init(familySharable: familySharable, name: name, reviewNote: reviewNote), id: id,
        _type: "inAppPurchases")))
    ).ok.body.json.data)
  }

  public static func delete(id: String, client: ASCClient) async throws {
    _ = try await client.inAppPurchasesV2DeleteInstance(path: .init(id: id)).noContent
  }

  /// Submits the purchase's pending version for review (it's reviewed with an app version).
  public static func submit(id: String, client: ASCClient) async throws {
    _ = try await client.inAppPurchaseSubmissionsCreateInstance(body: .json(.init(data: .init(
      relationships: .init(inAppPurchaseV2: .init(data: .init(id: id, _type: "inAppPurchases"))),
      _type: "inAppPurchaseSubmissions"
    )))).created
  }

  // MARK: Localizations

  public static func localizations(purchaseID: String, client: ASCClient) async throws -> [Localization] {
    try await client.inAppPurchasesV2InAppPurchaseLocalizationsGetToManyRelated(
      path: .init(id: purchaseID), query: .init(limit: 50)
    ).ok.body.json.data.map(Localization.init)
  }

  @discardableResult
  public static func createLocalization(
    purchaseID: String, locale: String, name: String, description: String?, client: ASCClient
  ) async throws -> Localization {
    Localization(try await client.inAppPurchaseLocalizationsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(description: description, locale: locale, name: name),
      relationships: .init(inAppPurchaseV2: .init(data: .init(id: purchaseID, _type: "inAppPurchases"))),
      _type: "inAppPurchaseLocalizations"
    )))).created.body.json.data)
  }

  /// Changes a localization; nil leaves a value as it is.
  @discardableResult
  public static func updateLocalization(
    id: String, name: String? = nil, description: String? = nil, client: ASCClient
  ) async throws -> Localization {
    Localization(try await client.inAppPurchaseLocalizationsUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(
        attributes: .init(description: description, name: name), id: id, _type: "inAppPurchaseLocalizations")))
    ).ok.body.json.data)
  }

  public static func deleteLocalization(id: String, client: ASCClient) async throws {
    _ = try await client.inAppPurchaseLocalizationsDeleteInstance(path: .init(id: id)).noContent
  }

  // MARK: Price schedule

  /// The purchase's price schedule, in `AppPricing`'s types (an in-app purchase's schedule has the
  /// same shape as an app's); nil when it has no price yet.
  public static func schedule(purchaseID: String, client: ASCClient) async throws -> AppPricing.Schedule? {
    let schedule = try await optionalRelated {
      try await withTransientRetry {
        try await client.inAppPurchasesV2IapPriceScheduleGetToOneRelated(
          path: .init(id: purchaseID),
          query: .init(fieldsInAppPurchasePriceSchedules: [.baseTerritory], include: [.baseTerritory])
        ).ok.body.json.data
      }
    }
    guard let schedule, let base = schedule.relationships?.baseTerritory?.data?.id else { return nil }
    async let manual = optionalRelated { try await prices(scheduleID: schedule.id, automatic: false, client: client) }
    async let automatic = optionalRelated { try await prices(scheduleID: schedule.id, automatic: true, client: client) }
    guard let (manualPrices, manualCurrencies) = try await manual, !manualPrices.isEmpty else { return nil }
    let (automaticPrices, automaticCurrencies) = try await automatic ?? ([], [:])
    return AppPricing.Schedule(
      baseTerritoryID: base, manualPrices: manualPrices, automaticPrices: automaticPrices,
      currencies: manualCurrencies.merging(automaticCurrencies) { first, _ in first })
  }

  private static func prices(
    scheduleID: String, automatic: Bool, client: ASCClient
  ) async throws -> ([AppPricing.Price], [String: String]) {
    let pages = try await withTransientRetry {
      if automatic {
        try await ASCPaging.allPages(next: { $0.links.next }) {
          try await client.inAppPurchasePriceSchedulesAutomaticPricesGetToManyRelated(
            path: .init(id: scheduleID),
            query: .init(
              fieldsInAppPurchasePricePoints: [.customerPrice, .proceeds, .territory], limit: 200,
              include: [.inAppPurchasePricePoint, .territory])
          ).ok.body.json
        }.map { ($0.data, $0.included ?? []) }
      } else {
        try await ASCPaging.allPages(next: { $0.links.next }) {
          try await client.inAppPurchasePriceSchedulesManualPricesGetToManyRelated(
            path: .init(id: scheduleID),
            query: .init(
              fieldsInAppPurchasePricePoints: [.customerPrice, .proceeds, .territory], limit: 200,
              include: [.inAppPurchasePricePoint, .territory])
          ).ok.body.json
        }.map { ($0.data, $0.included ?? []) }
      }
    }
    var points: [String: Components.Schemas.InAppPurchasePricePoint] = [:]
    var currencies: [String: String] = [:]
    for included in pages.flatMap(\.1) {
      switch included {
        case .inAppPurchasePricePoints(let point): points[point.id] = point
        case .territories(let territory): currencies[territory.id] = territory.attributes?.currency
      }
    }
    let prices = pages.flatMap(\.0).compactMap { price -> AppPricing.Price? in
      guard let territoryID = price.relationships?.territory?.data?.id,
        let pointID = price.relationships?.inAppPurchasePricePoint?.data?.id, let point = points[pointID]
      else { return nil }
      return AppPricing.Price(
        id: price.id, point: pricePoint(point, territoryID: territoryID), manual: price.attributes?.manual ?? !automatic,
        startDate: price.attributes?.startDate, endDate: price.attributes?.endDate)
    }
    return (prices, currencies)
  }

  private static func pricePoint(_ point: Components.Schemas.InAppPurchasePricePoint, territoryID: String) -> AppPricing.PricePoint {
    AppPricing.PricePoint(
      id: point.id, territoryID: territoryID, customerPrice: point.attributes?.customerPrice ?? "",
      proceeds: point.attributes?.proceeds ?? "")
  }

  /// A territory's price tiers for the purchase, cheapest first.
  public static func pricePoints(purchaseID: String, territoryID: String, client: ASCClient) async throws -> [AppPricing.PricePoint] {
    try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.inAppPurchasesV2PricePointsGetToManyRelated(
          path: .init(id: purchaseID),
          query: .init(filterTerritory: [territoryID], fieldsInAppPurchasePricePoints: [.customerPrice, .proceeds], limit: 200)
        ).ok.body.json
      }
    }.flatMap(\.data).map { pricePoint($0, territoryID: territoryID) }
      .sorted { (Decimal(string: $0.customerPrice) ?? 0) < (Decimal(string: $1.customerPrice) ?? 0) }
  }

  /// What a tier comes to in every other territory, with each territory's currency.
  public static func equalizations(
    of pricePointID: String, client: ASCClient
  ) async throws -> (points: [AppPricing.PricePoint], currencies: [String: String]) {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.inAppPurchasePricePointsEqualizationsGetToManyRelated(
          path: .init(id: pricePointID),
          query: .init(fieldsInAppPurchasePricePoints: [.customerPrice, .proceeds, .territory], limit: 200, include: [.territory])
        ).ok.body.json
      }
    }
    var currencies: [String: String] = [:]
    for page in pages {
      for territory in page.included ?? [] {
        currencies[territory.id] = territory.attributes?.currency
      }
    }
    let points = pages.flatMap(\.data).compactMap { point -> AppPricing.PricePoint? in
      guard let territoryID = point.relationships?.territory?.data?.id else { return nil }
      return pricePoint(point, territoryID: territoryID)
    }
    return (points, currencies)
  }

  /// Replaces the purchase's price schedule: the base territory and every manual price.
  public static func setSchedule(
    purchaseID: String, baseTerritoryID: String, manualPrices: [AppPricing.NewPrice], client: ASCClient
  ) async throws {
    let localIDs = manualPrices.indices.map { "${price\($0)}" }
    let request = Components.Schemas.InAppPurchasePriceScheduleCreateRequest(
      data: .init(
        relationships: .init(
          baseTerritory: .init(data: .init(id: baseTerritoryID, _type: "territories")),
          inAppPurchase: .init(data: .init(id: purchaseID, _type: "inAppPurchases")),
          manualPrices: .init(data: localIDs.map { .init(id: $0, _type: "inAppPurchasePrices") })),
        _type: "inAppPurchasePriceSchedules"),
      included: zip(localIDs, manualPrices).map { localID, price in
        .InAppPurchasePriceInlineCreate(.init(
          attributes: .init(endDate: price.endDate, startDate: price.startDate),
          id: localID,
          relationships: .init(
            inAppPurchasePricePoint: .init(data: .init(id: price.pricePointID, _type: "inAppPurchasePricePoints")),
            inAppPurchaseV2: .init(data: .init(id: purchaseID, _type: "inAppPurchases"))),
          _type: "inAppPurchasePrices"))
      })
    _ = try await withTransientRetry {
      try await client.inAppPurchasePriceSchedulesCreateInstance(body: .json(request)).created
    }
  }

  // MARK: Availability

  /// Where the purchase is sold; nil when it has none of its own (it follows the app's).
  public static func availability(purchaseID: String, client: ASCClient) async throws -> Availability? {
    guard let availability = try await optionalRelated({
      try await client.inAppPurchasesV2InAppPurchaseAvailabilityGetToOneRelated(path: .init(id: purchaseID)).ok.body.json.data
    }) else { return nil }
    let territories = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.inAppPurchaseAvailabilitiesAvailableTerritoriesGetToManyRelated(
          path: .init(id: availability.id), query: .init(limit: 200)
        ).ok.body.json
      }
    }.flatMap { $0.data.map(\.id) }
    return Availability(
      availableInNewTerritories: availability.attributes?.availableInNewTerritories ?? false, territories: territories)
  }

  /// Replaces the purchase's availability (at least one territory).
  public static func setAvailability(
    purchaseID: String, availableInNewTerritories: Bool, territories: [String], client: ASCClient
  ) async throws {
    _ = try await client.inAppPurchaseAvailabilitiesCreateInstance(body: .json(.init(data: .init(
      attributes: .init(availableInNewTerritories: availableInNewTerritories),
      relationships: .init(
        availableTerritories: .init(data: territories.map { .init(id: $0, _type: "territories") }),
        inAppPurchase: .init(data: .init(id: purchaseID, _type: "inAppPurchases"))),
      _type: "inAppPurchaseAvailabilities"
    )))).created
  }

  // MARK: Images

  /// The promotional images (App Store Connect shows one).
  public static func images(purchaseID: String, client: ASCClient) async throws -> [Image] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.inAppPurchasesV2ImagesGetToManyRelated(path: .init(id: purchaseID), query: .init(limit: 50)).ok.body.json
    }.flatMap(\.data).map { image in
        let attributes = image.attributes
        return Image(
          id: image.id, fileName: attributes?.fileName ?? "", fileSize: attributes?.fileSize ?? 0,
          templateURL: attributes?.imageAsset?.templateUrl.flatMap { $0.isEmpty ? nil : $0 }, width: attributes?.imageAsset?.width,
          height: attributes?.imageAsset?.height, state: attributes?.state)
      }
  }

  /// Uploads a promotional image (1024×1024).
  @discardableResult
  public static func uploadImage(purchaseID: String, filePath: String, client: ASCClient) async throws -> String {
    let media = try MediaFile(path: filePath)
    return try await uploadAsset(
      filePath: media.path,
      reserve: {
        let response = try await client.inAppPurchaseImagesCreateInstance(body: .json(.init(data: .init(
          attributes: .init(fileName: media.fileName, fileSize: media.fileSize),
          relationships: .init(inAppPurchase: .init(data: .init(id: purchaseID, _type: "inAppPurchases"))),
          _type: "inAppPurchaseImages"
        )))).created.body.json
        return (response.data.id, response.data.attributes?.uploadOperations ?? [])
      },
      commit: { id, md5 in
        _ = try await client.inAppPurchaseImagesUpdateInstance(
          path: .init(id: id),
          body: .json(.init(data: .init(
            attributes: .init(sourceFileChecksum: md5, uploaded: true), id: id, _type: "inAppPurchaseImages")))
        ).ok
      })
  }

  public static func deleteImage(id: String, client: ASCClient) async throws {
    _ = try await client.inAppPurchaseImagesDeleteInstance(path: .init(id: id)).noContent
  }

  /// The screenshot App Review sees; nil when there's none.
  public static func reviewScreenshot(purchaseID: String, client: ASCClient) async throws -> Image? {
    guard let screenshot = try await optionalRelated({
      try await client.inAppPurchasesV2AppStoreReviewScreenshotGetToOneRelated(path: .init(id: purchaseID)).ok.body.json.data
    }) else { return nil }
    let attributes = screenshot.attributes
    return Image(
      id: screenshot.id, fileName: attributes?.fileName ?? "", fileSize: attributes?.fileSize ?? 0,
      templateURL: attributes?.imageAsset?.templateUrl.flatMap { $0.isEmpty ? nil : $0 }, width: attributes?.imageAsset?.width,
      height: attributes?.imageAsset?.height, state: attributes?.assetDeliveryState?.state)
  }

  /// Uploads the App Review screenshot (a purchase has one; delete the old one first).
  @discardableResult
  public static func uploadReviewScreenshot(purchaseID: String, filePath: String, client: ASCClient) async throws -> String {
    let media = try MediaFile(path: filePath)
    return try await uploadAsset(
      filePath: media.path,
      reserve: {
        let response = try await client.inAppPurchaseAppStoreReviewScreenshotsCreateInstance(body: .json(.init(data: .init(
          attributes: .init(fileName: media.fileName, fileSize: media.fileSize),
          relationships: .init(inAppPurchaseV2: .init(data: .init(id: purchaseID, _type: "inAppPurchases"))),
          _type: "inAppPurchaseAppStoreReviewScreenshots"
        )))).created.body.json
        return (response.data.id, response.data.attributes?.uploadOperations ?? [])
      },
      commit: { id, md5 in
        _ = try await client.inAppPurchaseAppStoreReviewScreenshotsUpdateInstance(
          path: .init(id: id),
          body: .json(.init(data: .init(
            attributes: .init(sourceFileChecksum: md5, uploaded: true), id: id,
            _type: "inAppPurchaseAppStoreReviewScreenshots")))
        ).ok
      })
  }

  public static func deleteReviewScreenshot(id: String, client: ASCClient) async throws {
    _ = try await client.inAppPurchaseAppStoreReviewScreenshotsDeleteInstance(path: .init(id: id)).noContent
  }
}
