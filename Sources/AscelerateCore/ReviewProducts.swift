import ASCKit
import Foundation

/// The in-app purchases, subscriptions and subscription groups with a version waiting for App
/// Review (`ProductVersions`), which go to App Review in a submission with an app version: a first
/// in-app purchase must, and later changes usually do. Read before adding a version for review,
/// they're added to its draft submission along with it.
public enum ReviewProducts {
  public struct Product: Hashable, Identifiable, Sendable {
    public enum Kind: String, Hashable, Sendable {
      case inAppPurchase, subscription, subscriptionGroup
    }

    public let kind: Kind
    /// The product's or group's ID.
    public let id: String
    /// The reference name.
    public let name: String
    /// The product ID; nil for a group.
    public let productID: String?
    /// The product's state (READY_TO_SUBMIT, MISSING_METADATA, APPROVED…); nil for a group.
    public let state: String?
    /// The version waiting for App Review.
    public let pending: ProductVersions.Pending
    /// It can go to App Review: a product ready to submit (or approved, with changes), a group with
    /// a subscription that can.
    public let isReady: Bool

    /// Its version is in a draft submission already (added for review), so nothing adds it again.
    public var isInDraft: Bool { pending.state == "READY_FOR_REVIEW" }

    /// What a draft submission takes for it.
    public var draftItem: ReviewSubmissions.DraftItem {
      switch kind {
        case .inAppPurchase: .inAppPurchaseVersion(pending.id)
        case .subscription: .subscriptionVersion(pending.id)
        case .subscriptionGroup: .subscriptionGroupVersion(pending.id)
      }
    }
  }

  /// Product states that can go to App Review: ready, or approved with a changed version.
  public static let readyStates: Set<String> = ["READY_TO_SUBMIT", "APPROVED"]

  /// The app's products and groups with a version waiting for App Review: in-app purchases, then
  /// each group followed by its subscriptions. Products already with App Review, or taken off
  /// sale, have none.
  public static func pending(appID: String, client: ASCClient) async throws -> [Product] {
    async let purchases = InAppPurchases.list(appID: appID, client: client)
    async let groups = Subscriptions.groups(appID: appID, client: client)
    let (allPurchases, allGroups) = try await (purchases, groups)

    let purchaseVersions = try await boundedConcurrentMap(allPurchases, maxConcurrent: 4) { purchase in
      try await ProductVersions.pendingIAP(purchase.id, client: client)
    }
    var products: [Product] = zip(allPurchases, purchaseVersions).compactMap { purchase, pending in
      pending.map {
        Product(
          kind: .inAppPurchase, id: purchase.id, name: purchase.name, productID: purchase.productID,
          state: purchase.state, pending: $0, isReady: readyStates.contains(purchase.state))
      }
    }

    for group in allGroups {
      let subscriptionVersions = try await boundedConcurrentMap(group.subscriptions, maxConcurrent: 4) { subscription in
        try await ProductVersions.pendingSubscription(subscription.id, client: client)
      }
      let subscriptions: [Product] = zip(group.subscriptions, subscriptionVersions).compactMap { subscription, pending in
        pending.map {
          Product(
            kind: .subscription, id: subscription.id, name: subscription.name, productID: subscription.productID,
            state: subscription.state, pending: $0, isReady: readyStates.contains(subscription.state))
        }
      }
      if let pending = try await ProductVersions.pendingGroup(group.id, client: client) {
        // A group goes with a subscription that can, or on its own once one of its subscriptions
        // is on the App Store (a change to the group alone).
        let isReady = subscriptions.contains(where: \.isReady) || group.subscriptions.contains { $0.state == "APPROVED" }
        products.append(Product(
          kind: .subscriptionGroup, id: group.id, name: group.referenceName, productID: nil, state: nil,
          pending: pending, isReady: isReady))
      }
      products += subscriptions
    }
    return products
  }

  /// Adds an app version for review with the products waiting to go with it: the version to the
  /// platform's draft submission (made when there's none), then each ready product that isn't in
  /// a draft yet (`pending`, read after the version is added). One that isn't ready stays out.
  /// Returns the draft's ID.
  @discardableResult
  public static func addVersion(_ versionID: String, appID: String, platform: String, client: ASCClient) async throws -> String {
    let draftID = try await ReviewSubmissions.add(.appStoreVersion(versionID), appID: appID, platform: platform, client: client)
    try await addReady(pending(appID: appID, client: client), appID: appID, platform: platform, draftID: draftID, client: client)
    return draftID
  }

  /// Adds the ready products that aren't in a draft yet to the draft `draftID`, groups before
  /// their subscriptions; returns those added.
  @discardableResult
  public static func addReady(
    _ products: [Product], appID: String, platform: String, draftID: String, client: ASCClient
  ) async throws -> [Product] {
    var added: [Product] = []
    for product in products where product.isReady && !product.isInDraft {
      _ = try await ReviewSubmissions.add(
        product.draftItem, appID: appID, platform: platform, draftID: draftID, client: client)
      added.append(product)
    }
    return added
  }
}
