import ASCKit
import Foundation

/// An app's App Review submissions (`reviewSubmissions`): what went to App Review, its state, who
/// submitted and last changed it, and each item's review state. App Review's messages (rejection
/// reasons, replies) are only in App Store Connect; the API has no endpoint for them.
public enum ReviewSubmissions {
  /// Who submitted or last changed a submission.
  public struct Actor: Codable, Hashable, Sendable {
    /// `USER`, `API_KEY` or `APPLE`.
    public let type: String
    /// A user's first and last name.
    public let name: String?
    public let email: String?
    public let apiKeyID: String?
  }

  public struct Item: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// `READY_FOR_REVIEW`, `ACCEPTED`, `APPROVED`, `REJECTED` or `REMOVED`.
    public let state: String?
    /// What the item is, as its relationship is named: `appStoreVersion`, `inAppPurchaseVersion`,
    /// `subscriptionVersion`, `subscriptionGroupVersion`, `appEvent`, `appCustomProductPageVersion`,
    /// `appStoreVersionExperimentV2`, `appAssetLibraryImage`, `gameCenterAchievementVersion`…
    public let kind: String
    /// The app version string, or the product's or event's name, where the API gives one.
    public let name: String?
    /// An app version's platform (raw value).
    public let platform: String?
    /// An app version's build: version and build number ("2026.17 (20137)").
    public let build: String?
  }

  public struct Submission: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// Raw platform of the submission (`IOS`, `MAC_OS`…).
    public let platform: String?
    /// `READY_FOR_REVIEW` (a draft), `WAITING_FOR_REVIEW`, `IN_REVIEW`, `UNRESOLVED_ISSUES`,
    /// `CANCELING`, `COMPLETING` or `COMPLETE`.
    public let state: String?
    public let submittedDate: Date?
    public let submittedBy: Actor?
    public let lastUpdatedBy: Actor?
    public let items: [Item]
  }

  /// The app's submissions, newest first, with their items resolved (App Store Connect keeps the
  /// last ten completed ones from the past 180 days, plus any in progress). One request for the
  /// list, then one per submission for its items and one per app version item for its build.
  public static func list(appID: String, client: ASCClient) async throws -> [Submission] {
    let response = try await client.appsReviewSubmissionsGetToManyRelated(
      path: .init(id: appID),
      query: .init(limit: 50, include: [.submittedByActor, .lastUpdatedByActor])
    ).ok.body.json
    var actors: [String: Actor] = [:]
    for case .actors(let actor) in response.included ?? [] {
      actors[actor.id] = Actor(actor)
    }
    let actorsByID = actors
    let submissions = try await boundedConcurrentMap(response.data, maxConcurrent: 4) { submission in
      Submission(
        id: submission.id, platform: submission.attributes?.platform, state: submission.attributes?.state,
        submittedDate: submission.attributes?.submittedDate,
        submittedBy: submission.relationships?.submittedByActor?.data.flatMap { actorsByID[$0.id] },
        lastUpdatedBy: submission.relationships?.lastUpdatedByActor?.data.flatMap { actorsByID[$0.id] },
        items: try await items(submissionID: submission.id, client: client))
    }
    return submissions.sorted { ($0.submittedDate ?? .distantFuture) > ($1.submittedDate ?? .distantFuture) }
  }

  /// A submission's items, resolved to what they are. Product names cost one request per product
  /// item, an app version's build one per version.
  public static func items(submissionID: String, client: ASCClient) async throws -> [Item] {
    let response = try await client.reviewSubmissionsItemsGetToManyRelated(
      path: .init(id: submissionID),
      // An item's relationship is only filled in when its kind is included (naming it in
      // fields[reviewSubmissionItems] isn't enough), so every kind is.
      query: .init(
        fieldsAppStoreVersions: [.versionString, .platform], fieldsAppEvents: [.referenceName],
        fieldsInAppPurchaseVersions: [.version], fieldsSubscriptionVersions: [.version],
        fieldsSubscriptionGroupVersions: [.version],
        include: [
          .appStoreVersion, .appEvent, .inAppPurchaseVersion, .subscriptionVersion, .subscriptionGroupVersion,
          // Not the deprecated appStoreVersionExperiment too: the API refuses both at once.
          .appCustomProductPageVersion, .appStoreVersionExperimentV2,
          .appAssetLibraryImage, .appAssetLibraryVideo, .backgroundAssetVersion, .gameCenterAchievementVersion,
          .gameCenterActivityVersion, .gameCenterChallengeVersion, .gameCenterLeaderboardSetVersion,
          .gameCenterLeaderboardVersion,
        ])
    ).ok.body.json
    var versions: [String: Components.Schemas.AppStoreVersion] = [:]
    var events: [String: String] = [:]
    for included in response.included ?? [] {
      switch included {
        case .appStoreVersions(let version): versions[version.id] = version
        case .appEvents(let event): events[event.id] = event.attributes?.referenceName
        default: break
      }
    }
    // Product names: the existing per-product lookups (which read the items again), only when
    // there are product items.
    let hasProducts = response.data.contains { item in
      let relationships = item.relationships
      return relationships?.inAppPurchaseVersion?.data != nil || relationships?.subscriptionVersion?.data != nil
        || relationships?.subscriptionGroupVersion?.data != nil
    }
    let products = hasProducts ? try await ProductVersions.reviewItems(submissionID: submissionID, client: client) : [:]
    let (versionsByID, eventNames) = (versions, events)
    return try await boundedConcurrentMap(response.data, maxConcurrent: 4) { item in
      let relationships = item.relationships
      let state = item.attributes?.state
      if let id = relationships?.appStoreVersion?.data?.id {
        let version = versionsByID[id]
        let build = try await attachedBuild(versionID: id, client: client)
        return Item(
          id: item.id, state: state, kind: "appStoreVersion", name: version?.attributes?.versionString,
          platform: version?.attributes?.platform,
          build: build.flatMap { build in
            build.attributes?.version.map { "\(version?.attributes?.versionString ?? "") (\($0))" }
          })
      }
      if let id = relationships?.appEvent?.data?.id {
        return Item(id: item.id, state: state, kind: "appEvent", name: eventNames[id], platform: nil, build: nil)
      }
      if let product = products[item.id] {
        let kinds = ["IN_APP_PURCHASE": "inAppPurchaseVersion", "SUBSCRIPTION": "subscriptionVersion",
                     "SUBSCRIPTION_GROUP": "subscriptionGroupVersion"]
        return Item(
          id: item.id, state: state, kind: kinds[product.kind] ?? product.kind, name: product.name, platform: nil,
          build: nil)
      }
      return Item(id: item.id, state: state, kind: kind(of: relationships), name: nil, platform: nil, build: nil)
    }
  }

  /// The relationship an item refers through, for the kinds shown without a name.
  private static func kind(of relationships: Components.Schemas.ReviewSubmissionItem.RelationshipsPayload?) -> String {
    guard let relationships else { return "unknown" }
    let kinds: [(String, Bool)] = [
      ("appCustomProductPageVersion", relationships.appCustomProductPageVersion?.data != nil),
      ("appStoreVersionExperimentV2", relationships.appStoreVersionExperimentV2?.data != nil),
      ("appStoreVersionExperiment", relationships.appStoreVersionExperiment?.data != nil),
      ("appAssetLibraryImage", relationships.appAssetLibraryImage?.data != nil),
      ("appAssetLibraryVideo", relationships.appAssetLibraryVideo?.data != nil),
      ("backgroundAssetVersion", relationships.backgroundAssetVersion?.data != nil),
      ("gameCenterAchievementVersion", relationships.gameCenterAchievementVersion?.data != nil),
      ("gameCenterActivityVersion", relationships.gameCenterActivityVersion?.data != nil),
      ("gameCenterChallengeVersion", relationships.gameCenterChallengeVersion?.data != nil),
      ("gameCenterLeaderboardSetVersion", relationships.gameCenterLeaderboardSetVersion?.data != nil),
      ("gameCenterLeaderboardVersion", relationships.gameCenterLeaderboardVersion?.data != nil),
    ]
    return kinds.first(where: \.1)?.0 ?? "unknown"
  }

  /// Sends a draft submission (`READY_FOR_REVIEW`) to App Review.
  public static func submit(id: String, client: ASCClient) async throws {
    _ = try await client.reviewSubmissionsUpdateInstance(
      path: .init(id: id), body: .json(.init(data: .init(attributes: .init(submitted: true), id: id, _type: "reviewSubmissions")))
    ).ok
  }

  /// Takes a submission back from App Review (waiting or in review); it goes through `CANCELING`.
  public static func cancel(id: String, client: ASCClient) async throws {
    _ = try await client.reviewSubmissionsUpdateInstance(
      path: .init(id: id), body: .json(.init(data: .init(attributes: .init(canceled: true), id: id, _type: "reviewSubmissions")))
    ).ok
  }

  /// Takes an item out of a draft submission. A draft's item is deleted: `PATCH removed: true`
  /// answers 409 "Cannot remove item because of state of reviewSubmission" there (seen live
  /// 2026-10-21). An event taken out goes back to Draft.
  public static func removeItem(id: String, client: ASCClient) async throws {
    _ = try await client.reviewSubmissionItemsDeleteInstance(path: .init(id: id)).noContent
  }

  /// Adds an in-app event to the app's draft submission (`READY_FOR_REVIEW`) for `platform`,
  /// creating the draft when there's none, as App Store Connect's Add for Review does. It goes to
  /// App Review when the draft is submitted. Returns the draft's ID.
  @discardableResult
  public static func addEvent(_ eventID: String, appID: String, platform: String, client: ASCClient) async throws -> String {
    typealias Query = Operations.AppsReviewSubmissionsGetToManyRelated.Input.Query
    let drafts = try await client.appsReviewSubmissionsGetToManyRelated(
      path: .init(id: appID),
      query: .init(
        filterPlatform: Query.FilterPlatformPayloadPayload(rawValue: platform).map { [$0] },
        filterState: [.readyForReview], limit: 10)
    ).ok.body.json.data
    let draftID: String
    if let draft = drafts.first {
      draftID = draft.id
    } else {
      draftID = try await client.reviewSubmissionsCreateInstance(body: .json(.init(data: .init(
        attributes: .init(platform: platform),
        relationships: .init(app: .init(data: .init(id: appID, _type: "apps"))),
        _type: "reviewSubmissions"
      )))).created.body.json.data.id
    }
    _ = try await client.reviewSubmissionItemsCreateInstance(body: .json(.init(data: .init(
      relationships: .init(
        appEvent: .init(data: .init(id: eventID, _type: "appEvents")),
        reviewSubmission: .init(data: .init(id: draftID, _type: "reviewSubmissions"))
      ),
      _type: "reviewSubmissionItems"
    )))).created
    return draftID
  }

  /// Marks a rejected item's issues as resolved, after fixing them (and replying to App Review in
  /// App Store Connect).
  public static func resolveItem(id: String, client: ASCClient) async throws {
    _ = try await client.reviewSubmissionItemsUpdateInstance(
      path: .init(id: id), body: .json(.init(data: .init(attributes: .init(resolved: true), id: id, _type: "reviewSubmissionItems")))
    ).ok
  }
}
