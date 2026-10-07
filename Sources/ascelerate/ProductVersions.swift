import ASCKit
import Foundation

/// Pending-version detection for in-app purchases, subscriptions, and subscription groups.
///
/// Since App Store Connect OpenAPI 4.4.1 every product carries a version history. A product has
/// edits awaiting submission when one of its versions is in a `pendingStates` state — this
/// mirrors the app-version convention (PREPARE_FOR_SUBMISSION = being edited, READY_FOR_REVIEW =
/// attached to a submission, REJECTED/DEVELOPER_REJECTED = resubmittable after fixes). App Store
/// Connect can also keep an unchanged PREPARE_FOR_SUBMISSION draft open (seen live on a
/// subscription group, invisible in the web UI, and the version API has no DELETE), so
/// `pendingGroup` compares a draft against the approved version; IAP and subscription drafts are
/// still taken at face value, since their edits can be image or screenshot changes.
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

  static func pendingIAP(_ iapID: String, client: ASCClient) async throws -> Pending? {
    let response = try await client.inAppPurchasesV2VersionsGetToManyRelated(
      path: .init(id: iapID),
      query: .init(filterState: [.prepareForSubmission, .readyForReview, .rejected, .developerRejected])
    ).ok.body.json
    return response.data.first.map { Pending(id: $0.id, version: $0.attributes?.version, state: $0.attributes?.state ?? "UNKNOWN") }
  }

  static func pendingSubscription(_ subID: String, client: ASCClient) async throws -> Pending? {
    let response = try await client.subscriptionsVersionsGetToManyRelated(
      path: .init(id: subID),
      query: .init(filterState: [.prepareForSubmission, .readyForReview, .rejected, .developerRejected])
    ).ok.body.json
    return response.data.first.map { Pending(id: $0.id, version: $0.attributes?.version, state: $0.attributes?.state ?? "UNKNOWN") }
  }

  /// A group's pending version. A PREPARE_FOR_SUBMISSION draft only counts when its
  /// localizations (all a group version holds) differ from the latest APPROVED version:
  /// App Store Connect keeps unchanged drafts open (seen live 2026-10-07: a v2 draft identical
  /// to the approved v1, invisible in the web UI), and the version API has no DELETE to clear them.
  static func pendingGroup(_ groupID: String, client: ASCClient) async throws -> Pending? {
    let versions = try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.subscriptionGroupsVersionsGetToManyRelated(path: .init(id: groupID)).ok.body.json
    }.flatMap(\.data)
    let newestFirst = versions.sorted { ($0.attributes?.version ?? 0) > ($1.attributes?.version ?? 0) }
    guard let pending = newestFirst.first(where: { pendingStates.contains($0.attributes?.state ?? "") }) else {
      return nil
    }
    if pending.attributes?.state == "PREPARE_FOR_SUBMISSION",
      let approved = newestFirst.first(where: { $0.attributes?.state == "APPROVED" }),
      try await groupLocalizations(pending.id, client: client) == groupLocalizations(approved.id, client: client) {
      return nil
    }
    return Pending(id: pending.id, version: pending.attributes?.version, state: pending.attributes?.state ?? "UNKNOWN")
  }

  private struct GroupLocalization: Hashable {
    let locale: String
    let name: String
    let customAppName: String
  }

  private static func groupLocalizations(_ versionID: String, client: ASCClient) async throws -> Set<GroupLocalization> {
    let localizations = try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.subscriptionGroupVersionsLocalizationsGetToManyRelated(
        path: .init(id: versionID), query: .init(limit: 50)
      ).ok.body.json
    }.flatMap(\.data)
    return Set(localizations.map {
      GroupLocalization(
        locale: $0.attributes?.locale ?? "", name: $0.attributes?.name ?? "",
        customAppName: $0.attributes?.customAppName ?? "")
    })
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
  static func reviewItems(submissionID: String, client: ASCClient) async throws -> [String: ReviewItemInfo] {
    let response = try await client.reviewSubmissionsItemsGetToManyRelated(
      path: .init(id: submissionID),
      query: .init(
        fieldsAppStoreVersions: [.versionString],
        fieldsInAppPurchaseVersions: [.version, .state],
        fieldsSubscriptionVersions: [.version, .state],
        fieldsSubscriptionGroupVersions: [.version, .state],
        include: [.appStoreVersion, .inAppPurchaseVersion, .subscriptionVersion, .subscriptionGroupVersion]
      )
    ).ok.body.json

    var appVersions: [String: String] = [:]
    var productVersions: [String: (version: Int?, state: String?)] = [:]
    for included in response.included ?? [] {
      switch included {
        case .appStoreVersions(let v): appVersions[v.id] = v.attributes?.versionString
        case .inAppPurchaseVersions(let v): productVersions[v.id] = (v.attributes?.version, v.attributes?.state)
        case .subscriptionVersions(let v): productVersions[v.id] = (v.attributes?.version, v.attributes?.state)
        case .subscriptionGroupVersions(let v): productVersions[v.id] = (v.attributes?.version, v.attributes?.state)
        default: break
      }
    }

    var result: [String: ReviewItemInfo] = [:]
    for item in response.data {
      let rels = item.relationships
      func product(_ kind: String, _ id: String, name: String?) -> ReviewItemInfo {
        ReviewItemInfo(kind: kind, name: name, version: productVersions[id]?.version, versionState: productVersions[id]?.state)
      }
      if let id = rels?.appStoreVersion?.data?.id {
        result[item.id] = ReviewItemInfo(kind: "APP_STORE_VERSION", name: appVersions[id], version: nil, versionState: nil)
      } else if let id = rels?.inAppPurchaseVersion?.data?.id {
        let included = try await client.inAppPurchaseVersionsGetInstance(
          path: .init(id: id), query: .init(fieldsInAppPurchases: [.name], include: [.inAppPurchase])
        ).ok.body.json.included ?? []
        let name = included.lazy.compactMap { if case .inAppPurchases(let iap) = $0 { return iap.attributes?.name } else { return nil } }.first
        result[item.id] = product("IN_APP_PURCHASE", id, name: name)
      } else if let id = rels?.subscriptionVersion?.data?.id {
        let included = try await client.subscriptionVersionsGetInstance(
          path: .init(id: id), query: .init(fieldsSubscriptions: [.name], include: [.subscription])
        ).ok.body.json.included ?? []
        let name = included.lazy.compactMap { if case .subscriptions(let sub) = $0 { return sub.attributes?.name } else { return nil } }.first
        result[item.id] = product("SUBSCRIPTION", id, name: name)
      } else if let id = rels?.subscriptionGroupVersion?.data?.id {
        let included = try await client.subscriptionGroupVersionsGetInstance(
          path: .init(id: id), query: .init(fieldsSubscriptionGroups: [.referenceName], include: [.subscriptionGroup])
        ).ok.body.json.included ?? []
        let name = included.lazy.compactMap { if case .subscriptionGroups(let group) = $0 { return group.attributes?.referenceName } else { return nil } }.first
        result[item.id] = product("SUBSCRIPTION_GROUP", id, name: name)
      }
    }
    return result
  }
}
