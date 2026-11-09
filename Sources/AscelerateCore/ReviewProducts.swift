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

  /// A product App Store Connect wouldn't add to the draft, with its reply.
  public struct Refusal: Sendable {
    public let product: Product
    public let error: ASCError

    /// Apple's reason, as one text.
    public var reason: String { error.summary }
  }

  /// What adding a version for review did: the draft holding it, and the products that went in
  /// with it and those App Store Connect refused.
  public struct Added: Sendable {
    public let draftID: String
    public let added: [Product]
    public let refused: [Refusal]
  }

  /// Adds an app version for review with the products waiting to go with it: the version to the
  /// platform's draft submission (made when there's none), then each ready product that isn't in
  /// a draft yet (`pending`, read after the version is added). One that isn't ready stays out.
  /// A product App Store Connect refuses doesn't stop the others; it's in `refused`, and the
  /// caller decides whether to submit the draft without it.
  @discardableResult
  public static func addVersion(_ versionID: String, appID: String, platform: String, client: ASCClient) async throws -> Added {
    let draftID = try await ReviewSubmissions.add(.appStoreVersion(versionID), appID: appID, platform: platform, client: client)
    let (added, refused) = try await addReady(
      pending(appID: appID, client: client), appID: appID, platform: platform, draftID: draftID, client: client)
    return Added(draftID: draftID, added: added, refused: refused)
  }

  /// Adds the ready products that aren't in a draft yet to the draft `draftID`, groups before
  /// their subscriptions. A product App Store Connect refuses (400, 404, 409, 422: about the
  /// product itself) is collected and the rest still tried; any other failure (the key, the rate
  /// limit, the server) is thrown.
  public static func addReady(
    _ products: [Product], appID: String, platform: String, draftID: String, client: ASCClient
  ) async throws -> (added: [Product], refused: [Refusal]) {
    var added: [Product] = []
    var refused: [Refusal] = []
    for product in products where product.isReady && !product.isInDraft {
      do {
        _ = try await ReviewSubmissions.add(
          product.draftItem, appID: appID, platform: platform, draftID: draftID, client: client)
        added.append(product)
      } catch {
        guard let reply = ASCError.from(error), [400, 404, 409, 422].contains(reply.statusCode) else { throw error }
        // Another draft took it meanwhile (Send Update adds each platform's version side by side,
        // and each platform has a draft of its own): it's on its way to App Review.
        if await isInDraft(product, client: client) { continue }
        refused.append(Refusal(product: product, error: reply))
      }
    }
    return (added, refused)
  }

  /// Whether the product's pending version is in a draft now. False when it can't be read: the
  /// refusal then stands as Apple gave it.
  private static func isInDraft(_ product: Product, client: ASCClient) async -> Bool {
    let pending: ProductVersions.Pending?
    do {
      switch product.kind {
        case .inAppPurchase: pending = try await ProductVersions.pendingIAP(product.id, client: client)
        case .subscription: pending = try await ProductVersions.pendingSubscription(product.id, client: client)
        case .subscriptionGroup: pending = try await ProductVersions.pendingGroup(product.id, client: client)
      }
    } catch {
      return false
    }
    return pending?.state == "READY_FOR_REVIEW"
  }
}
