import AppStoreAPI
import AppStoreConnect
import Foundation

/// Pending-version detection for in-app purchases, subscriptions, and subscription groups.
///
/// Since App Store Connect OpenAPI 4.4.1 every product carries a version history. A product has
/// edits awaiting submission when one of its versions is in a `pendingStates` state — this
/// mirrors the app-version convention (PREPARE_FOR_SUBMISSION = being edited, READY_FOR_REVIEW =
/// attached to a submission, REJECTED/DEVELOPER_REJECTED = resubmittable after fixes). The mapping
/// for products is inferred from app versions, not yet observed live (all products were APPROVED
/// with a single version when this was written); adjust `pendingStates` if a real pending edit
/// turns out to use a different state.
///
/// The v1 `inAppPurchaseSubmissions`/`subscriptionSubmissions`/`subscriptionGroupSubmissions`
/// POSTs return HTTP 409 for products without a pending version — checking here first turns that
/// into a clear message and also catches image/screenshot-only edits that the older
/// localization-state heuristic missed.
enum ProductVersions {
  /// A product version awaiting submission.
  struct Pending: Encodable, Sendable {
    let id: String
    let version: Int?
    let state: String

    var label: String { "v\(version.map(String.init) ?? "?") (\(formatState(state)))" }
  }

  static let pendingStates: Set<String> = [
    "PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "REJECTED", "DEVELOPER_REJECTED",
  ]

  static func pendingIAP(_ iapID: String, client: AppStoreConnectClient) async throws -> Pending? {
    let response = try await client.send(
      Resources.v2.inAppPurchases.id(iapID).versions.get(
        filterState: [.prepareForSubmission, .readyForReview, .rejected, .developerRejected]
      )
    )
    return response.data.first.map { Pending(id: $0.id, version: $0.attributes?.version, state: $0.attributes?.state?.rawValue ?? "UNKNOWN") }
  }

  static func pendingSubscription(_ subID: String, client: AppStoreConnectClient) async throws -> Pending? {
    let response = try await client.send(
      Resources.v1.subscriptions.id(subID).versions.get(
        filterState: [.prepareForSubmission, .readyForReview, .rejected, .developerRejected]
      )
    )
    return response.data.first.map { Pending(id: $0.id, version: $0.attributes?.version, state: $0.attributes?.state?.rawValue ?? "UNKNOWN") }
  }

  static func pendingGroup(_ groupID: String, client: AppStoreConnectClient) async throws -> Pending? {
    let response = try await client.send(
      Resources.v1.subscriptionGroups.id(groupID).versions.get(
        filterState: [.prepareForSubmission, .readyForReview, .rejected, .developerRejected]
      )
    )
    return response.data.first.map { Pending(id: $0.id, version: $0.attributes?.version, state: $0.attributes?.state?.rawValue ?? "UNKNOWN") }
  }

  // MARK: - Review submission items

  /// What a review submission item refers to, resolved for display.
  struct ReviewItemInfo: Sendable {
    /// Raw kind: APP_STORE_VERSION, IN_APP_PURCHASE, SUBSCRIPTION, SUBSCRIPTION_GROUP.
    let kind: String
    /// App version string, or the product's name.
    let name: String?
    /// Product version number (nil for app versions).
    let version: Int?
    /// Product version state (nil for app versions).
    let versionState: String?

    var description: String {
      let versionLabel = version.map { " v\($0)" } ?? ""
      let stateLabel = versionState.map { " (\(formatState($0)))" } ?? ""
      return "\(formatState(kind)) \(name ?? "—")\(versionLabel)\(stateLabel)"
    }
  }

  /// Resolves every item of a review submission to its target (app version or product version),
  /// keyed by item ID. Product names cost one extra request per product item.
  static func reviewItems(submissionID: String, client: AppStoreConnectClient) async throws -> [String: ReviewItemInfo] {
    let response = try await client.send(
      Resources.v1.reviewSubmissions.id(submissionID).items.get(
        fieldsAppStoreVersions: [.versionString],
        fieldsInAppPurchaseVersions: [.version, .state],
        fieldsSubscriptionVersions: [.version, .state],
        fieldsSubscriptionGroupVersions: [.version, .state],
        include: [.appStoreVersion, .inAppPurchaseVersion, .subscriptionVersion, .subscriptionGroupVersion]
      )
    )

    var appVersions: [String: String] = [:]
    var iapVersions: [String: InAppPurchaseVersion] = [:]
    var subVersions: [String: SubscriptionVersion] = [:]
    var groupVersions: [String: SubscriptionGroupVersion] = [:]
    for included in response.included ?? [] {
      switch included {
        case .appStoreVersion(let v): appVersions[v.id] = v.attributes?.versionString
        case .inAppPurchaseVersion(let v): iapVersions[v.id] = v
        case .subscriptionVersion(let v): subVersions[v.id] = v
        case .subscriptionGroupVersion(let v): groupVersions[v.id] = v
        default: break
      }
    }

    var result: [String: ReviewItemInfo] = [:]
    for item in response.data {
      let rels = item.relationships
      if let id = rels?.appStoreVersion?.data?.id {
        result[item.id] = ReviewItemInfo(kind: "APP_STORE_VERSION", name: appVersions[id], version: nil, versionState: nil)
      } else if let id = rels?.inAppPurchaseVersion?.data?.id {
        let name = try await iapName(versionID: id, client: client)
        result[item.id] = ReviewItemInfo(kind: "IN_APP_PURCHASE", name: name, version: iapVersions[id]?.attributes?.version, versionState: iapVersions[id]?.attributes?.state?.rawValue)
      } else if let id = rels?.subscriptionVersion?.data?.id {
        let name = try await subscriptionName(versionID: id, client: client)
        result[item.id] = ReviewItemInfo(kind: "SUBSCRIPTION", name: name, version: subVersions[id]?.attributes?.version, versionState: subVersions[id]?.attributes?.state?.rawValue)
      } else if let id = rels?.subscriptionGroupVersion?.data?.id {
        let name = try await groupName(versionID: id, client: client)
        result[item.id] = ReviewItemInfo(kind: "SUBSCRIPTION_GROUP", name: name, version: groupVersions[id]?.attributes?.version, versionState: groupVersions[id]?.attributes?.state?.rawValue)
      }
    }
    return result
  }

  private static func iapName(versionID: String, client: AppStoreConnectClient) async throws -> String? {
    let response = try await client.send(
      Resources.v1.inAppPurchaseVersions.id(versionID).get(fieldsInAppPurchases: [.name], include: [.inAppPurchase])
    )
    for included in response.included ?? [] {
      if case .inAppPurchaseV2(let iap) = included { return iap.attributes?.name }
    }
    return nil
  }

  private static func subscriptionName(versionID: String, client: AppStoreConnectClient) async throws -> String? {
    let response = try await client.send(
      Resources.v1.subscriptionVersions.id(versionID).get(fieldsSubscriptions: [.name], include: [.subscription])
    )
    for included in response.included ?? [] {
      if case .subscription(let sub) = included { return sub.attributes?.name }
    }
    return nil
  }

  private static func groupName(versionID: String, client: AppStoreConnectClient) async throws -> String? {
    let response = try await client.send(
      Resources.v1.subscriptionGroupVersions.id(versionID).get(fieldsSubscriptionGroups: [.referenceName], include: [.subscriptionGroup])
    )
    for included in response.included ?? [] {
      if case .subscriptionGroup(let group) = included { return group.attributes?.referenceName }
    }
    return nil
  }
}
