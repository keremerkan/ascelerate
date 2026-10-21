import ASCKit
import Foundation

/// Where an app is on the App Store (`appAvailabilities` v2): per territory whether it's available,
/// why it can't be sold there, and its pre-order and release dates; plus whether new App Store
/// territories get it automatically.
public enum AppAvailability {
  /// The app in one territory.
  public struct Territory: Sendable, Hashable, Identifiable {
    /// The territory availability's ID (what an update or ending a pre-order takes).
    public let id: String
    /// The territory's code (`USA`).
    public let territoryID: String
    public let available: Bool
    /// Apple's statuses for the territory: `AVAILABLE`, `PROCESSING_TO_AVAILABLE`,
    /// `AVAILABLE_FOR_PREORDER`, or why it can't be sold (`CANNOT_SELL_RESTRICTED_RATING`,
    /// `MISSING_GRN`, `TRADER_STATUS_NOT_PROVIDED`, ...).
    public let contentStatuses: [String]
    public let preOrderEnabled: Bool
    /// The day pre-orders opened (yyyy-MM-dd).
    public let preOrderPublishDate: String?
    /// The day the app was or will be released there (yyyy-MM-dd).
    public let releaseDate: String?
  }

  public struct Availability: Sendable, Hashable {
    public let id: String
    public let availableInNewTerritories: Bool
    public let territories: [Territory]
  }

  /// A territory for `create`.
  public struct NewTerritory: Sendable, Hashable {
    public let territoryID: String
    public let available: Bool
    public let preOrderEnabled: Bool
    /// The release date of a pre-order (yyyy-MM-dd).
    public let releaseDate: String?

    public init(territoryID: String, available: Bool, preOrderEnabled: Bool = false, releaseDate: String? = nil) {
      self.territoryID = territoryID
      self.available = available
      self.preOrderEnabled = preOrderEnabled
      self.releaseDate = releaseDate
    }
  }

  /// An app whose availability was never set up.
  public struct NotSetUpError: LocalizedError {
    public let appName: String

    public init(appName: String) {
      self.appName = appName
    }

    public var errorDescription: String? {
      "\(appName) has no availability set up yet. Set it up in App Store Connect first."
    }
  }

  /// The app's availability; nil when it was never set up (App Store Connect's Set Up
  /// Availability).
  public static func availability(appID: String, client: ASCClient) async throws -> Availability? {
    guard let availability = try await optionalRelated({
      try await client.appsAppAvailabilityV2GetToOneRelated(path: .init(id: appID)).ok.body.json.data
    }) else { return nil }
    // Paged through the sub-resource: an include on the availability caps at 50 territories.
    let territories = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.appAvailabilitiesV2TerritoryAvailabilitiesGetToManyRelated(
          path: .init(id: availability.id), query: .init(limit: 200, include: [.territory])
        ).ok.body.json
      }
    }.flatMap(\.data)
    return Availability(
      id: availability.id,
      availableInNewTerritories: availability.attributes?.availableInNewTerritories ?? false,
      territories: territories.compactMap { territory in
        guard let code = territory.relationships?.territory?.data?.id else { return nil }
        let attributes = territory.attributes
        return Territory(
          id: territory.id, territoryID: code, available: attributes?.available ?? false,
          contentStatuses: attributes?.contentStatuses ?? [], preOrderEnabled: attributes?.preOrderEnabled ?? false,
          preOrderPublishDate: attributes?.preOrderPublishDate, releaseDate: attributes?.releaseDate)
      })
  }

  /// Sets up the app's availability: every territory listed, available or not.
  @discardableResult
  public static func create(
    appID: String, availableInNewTerritories: Bool, territories: [NewTerritory], client: ASCClient
  ) async throws -> String {
    let localIDs = territories.indices.map { "${territory\($0)}" }
    let request = Components.Schemas.AppAvailabilityV2CreateRequest(
      data: .init(
        attributes: .init(availableInNewTerritories: availableInNewTerritories),
        relationships: .init(
          app: .init(data: .init(id: appID, _type: "apps")),
          territoryAvailabilities: .init(data: localIDs.map { .init(id: $0, _type: "territoryAvailabilities") })),
        _type: "appAvailabilities"),
      included: zip(localIDs, territories).map { localID, territory in
        .init(
          attributes: .init(
            available: territory.available, preOrderEnabled: territory.preOrderEnabled,
            releaseDate: territory.releaseDate),
          id: localID,
          relationships: .init(territory: .init(data: .init(id: territory.territoryID, _type: "territories"))),
          _type: "territoryAvailabilities")
      })
    return try await client.appAvailabilitiesV2CreateInstance(body: .json(request)).created.body.json.data.id
  }

  /// Changes the app in one territory; nil leaves a value as it is. A release date applies to a
  /// pre-order.
  public static func update(
    id: String, available: Bool? = nil, preOrderEnabled: Bool? = nil, releaseDate: String? = nil,
    client: ASCClient
  ) async throws {
    _ = try await withTransientRetry {
      try await client.territoryAvailabilitiesUpdateInstance(
        path: .init(id: id),
        body: .json(.init(data: .init(
          attributes: .init(available: available, preOrderEnabled: preOrderEnabled, releaseDate: releaseDate),
          id: id, _type: "territoryAvailabilities")))
      ).ok
    }
  }

  /// Ends pre-orders in the territories (territory availability IDs): the app is released there.
  public static func endPreOrders(territoryAvailabilityIDs: [String], client: ASCClient) async throws {
    _ = try await client.endAppAvailabilityPreOrdersCreateInstance(body: .json(.init(data: .init(
      relationships: .init(territoryAvailabilities: .init(
        data: territoryAvailabilityIDs.map { .init(id: $0, _type: "territoryAvailabilities") })),
      _type: "endAppAvailabilityPreOrders")))).created
  }
}
