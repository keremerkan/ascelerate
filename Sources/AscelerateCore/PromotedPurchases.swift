import ASCKit
import Foundation

/// An app's promoted purchases (`promotedPurchases`): the in-app purchases and subscriptions the
/// App Store shows on the product page, in their display order. Add, remove, switch on or off,
/// reorder.
public enum PromotedPurchases {
  public struct Promoted: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
      case inAppPurchase, subscription
    }

    public let id: String
    /// Nil when the product couldn't be read along with it.
    public let kind: Kind?
    /// The in-app purchase's or subscription's ID.
    public let productRecordID: String?
    public let productID: String?
    public let name: String?
    /// The raw state: APPROVED, IN_REVIEW, PREPARE_FOR_SUBMISSION, REJECTED.
    public let state: String?
    public let isVisibleForAllUsers: Bool
    public let isEnabled: Bool
  }

  /// The app's promoted purchases in display order, with their products.
  public static func list(appID: String, client: ASCClient) async throws -> [Promoted] {
    let pages = try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.appsPromotedPurchasesGetToManyRelated(
        path: .init(id: appID), query: .init(limit: 200, include: [.inAppPurchaseV2, .subscription])
      ).ok.body.json
    }
    var result: [Promoted] = []
    for page in pages {
      var purchases: [String: (productID: String?, name: String?)] = [:]
      var subscriptions: [String: (productID: String?, name: String?)] = [:]
      for item in page.included ?? [] {
        switch item {
          case .inAppPurchases(let purchase):
            purchases[purchase.id] = (purchase.attributes?.productId, purchase.attributes?.name)
          case .subscriptions(let subscription):
            subscriptions[subscription.id] = (subscription.attributes?.productId, subscription.attributes?.name)
        }
      }
      for promoted in page.data {
        var kind: Promoted.Kind?
        var recordID: String?
        var info: (productID: String?, name: String?)?
        if let id = promoted.relationships?.inAppPurchaseV2?.data?.id, let found = purchases[id] {
          (kind, recordID, info) = (.inAppPurchase, id, found)
        } else if let id = promoted.relationships?.subscription?.data?.id, let found = subscriptions[id] {
          (kind, recordID, info) = (.subscription, id, found)
        }
        let a = promoted.attributes
        result.append(Promoted(
          id: promoted.id, kind: kind, productRecordID: recordID, productID: info?.productID, name: info?.name,
          state: a?.state, isVisibleForAllUsers: a?.visibleForAllUsers == true, isEnabled: a?.enabled == true))
      }
    }
    return result
  }

  /// Promotes an in-app purchase or a subscription (by its ID); it goes last. Returns the promoted
  /// purchase's ID.
  @discardableResult
  public static func add(
    _ kind: Promoted.Kind, productRecordID: String, appID: String, enabled: Bool = true, visibleForAllUsers: Bool = true,
    client: ASCClient
  ) async throws -> String {
    let app = Components.Schemas.PromotedPurchaseCreateRequest.DataPayload.RelationshipsPayload.AppPayload(
      data: .init(id: appID, _type: "apps"))
    let relationships: Components.Schemas.PromotedPurchaseCreateRequest.DataPayload.RelationshipsPayload =
      switch kind {
        case .inAppPurchase:
          .init(app: app, inAppPurchaseV2: .init(data: .init(id: productRecordID, _type: "inAppPurchases")))
        case .subscription:
          .init(app: app, subscription: .init(data: .init(id: productRecordID, _type: "subscriptions")))
      }
    return try await client.promotedPurchasesCreateInstance(body: .json(.init(data: .init(
      attributes: .init(enabled: enabled, visibleForAllUsers: visibleForAllUsers),
      relationships: relationships,
      _type: "promotedPurchases"
    )))).created.body.json.data.id
  }

  /// Stops promoting.
  public static func delete(id: String, client: ASCClient) async throws {
    _ = try await client.promotedPurchasesDeleteInstance(path: .init(id: id)).noContent
  }

  /// Changes whether a promotion shows, and to whom; nil leaves a setting as it is.
  public static func update(id: String, enabled: Bool? = nil, visibleForAllUsers: Bool? = nil, client: ASCClient) async throws {
    _ = try await client.promotedPurchasesUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(
        attributes: .init(enabled: enabled, visibleForAllUsers: visibleForAllUsers), id: id, _type: "promotedPurchases")))
    ).ok
  }

  /// Sets the display order: every promoted purchase's ID, in order.
  public static func reorder(appID: String, ids: [String], client: ASCClient) async throws {
    _ = try await client.appsPromotedPurchasesReplaceToManyRelationship(
      path: .init(id: appID),
      body: .json(.init(data: ids.map { .init(id: $0, _type: "promotedPurchases") }))
    ).noContent
  }
}
