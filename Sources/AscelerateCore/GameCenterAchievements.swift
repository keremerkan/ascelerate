import ASCKit
import Foundation

extension GameCenter {
  public struct Achievement: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let referenceName: String?
    /// The ID the game reports it with.
    public let vendorIdentifier: String?
    public let points: Int?
    /// Shown to players before they earn it (else hidden until then).
    public let showBeforeEarned: Bool
    public let repeatable: Bool
    public let archived: Bool
    /// Oldest first.
    public let versions: [Version]

    public var latestVersion: Version? { GameCenter.latest(versions) }
  }

  public struct AchievementLocalization: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let locale: String
    public let name: String?
    public let beforeEarnedDescription: String?
    public let afterEarnedDescription: String?
    public let image: Image?
  }

  /// The app's achievements in the order Game Center shows them.
  public static func achievements(owner: Owner, client: ASCClient) async throws -> [Achievement] {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        switch owner {
          case .detail(let id):
            try await client.gameCenterDetailsGameCenterAchievementsV2GetToManyRelated(path: .init(id: id), query: .init(limit: 200, include: [.versions], limitVersions: 50)).ok.body.json
          case .group(let id):
            try await client.gameCenterGroupsGameCenterAchievementsV2GetToManyRelated(path: .init(id: id), query: .init(limit: 200, include: [.versions], limitVersions: 50)).ok.body.json
          }
      }
    }
    var versions: [String: Version] = [:]
    for page in pages {
      for case .gameCenterAchievementVersions(let v) in page.included ?? [] {
        versions[v.id] = Version(id: v.id, version: v.attributes?.version, state: v.attributes?.state)
      }
    }
    return pages.flatMap(\.data).map { achievement($0, versions: versions) }
  }

  public static func achievement(id: String, client: ASCClient) async throws -> Achievement {
    let response = try await withTransientRetry {
      try await client.gameCenterAchievementsV2GetInstance(
        path: .init(id: id), query: .init(include: [.versions], limitVersions: 50)
      ).ok.body.json
    }
    var versions: [String: Version] = [:]
    for case .gameCenterAchievementVersions(let v) in response.included ?? [] {
      versions[v.id] = Version(id: v.id, version: v.attributes?.version, state: v.attributes?.state)
    }
    return achievement(response.data, versions: versions)
  }

  private static func achievement(_ a: Components.Schemas.GameCenterAchievementV2, versions: [String: Version]) -> Achievement {
    let attributes = a.attributes
    return Achievement(
      id: a.id, referenceName: attributes?.referenceName, vendorIdentifier: attributes?.vendorIdentifier, points: attributes?.points,
      showBeforeEarned: attributes?.showBeforeEarned ?? false, repeatable: attributes?.repeatable ?? false,
      archived: attributes?.archived ?? false,
      versions: (a.relationships?.versions?.data ?? []).compactMap { versions[$0.id] }.sorted { ($0.version ?? 0) < ($1.version ?? 0) })
  }

  /// A version's languages, with their images.
  public static func achievementLocalizations(versionID: String, client: ASCClient) async throws -> [AchievementLocalization] {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.gameCenterAchievementVersionsV2LocalizationsGetToManyRelated(
          path: .init(id: versionID), query: .init(limit: 200, include: [.image])
        ).ok.body.json
      }
    }
    var images: [String: Components.Schemas.GameCenterAchievementImageV2] = [:]
    for page in pages {
      for case .gameCenterAchievementImages(let image) in page.included ?? [] { images[image.id] = image }
    }
    return pages.flatMap(\.data).map { l in
      let a = l.attributes
      return AchievementLocalization(
        id: l.id, locale: a?.locale ?? "", name: a?.name, beforeEarnedDescription: a?.beforeEarnedDescription,
        afterEarnedDescription: a?.afterEarnedDescription,
        image: l.relationships?.image?.data.flatMap { images[$0.id] }.map {
          GameCenter.image(id: $0.id, $0.attributes?.fileName, $0.attributes?.fileSize, $0.attributes?.imageAsset, $0.attributes?.assetDeliveryState)
        })
    }
    .sorted { $0.locale < $1.locale }
  }
}

extension GameCenter {
  /// Creates an achievement with its first version, which holds its languages and images.
  public static func createAchievement(
    owner: Owner, vendorIdentifier: String, referenceName: String, points: Int, showBeforeEarned: Bool, repeatable: Bool,
    client: ASCClient
  ) async throws -> Achievement {
    let created = try await client.gameCenterAchievementsV2CreateInstance(body: .json(.init(data: .init(
      attributes: .init(
        points: points, referenceName: referenceName, repeatable: repeatable, showBeforeEarned: showBeforeEarned,
        vendorIdentifier: vendorIdentifier),
      relationships: .init(
        gameCenterDetail: owner.detailID.map { .init(data: .init(id: $0, _type: "gameCenterDetails")) },
        gameCenterGroup: owner.groupID.map { .init(data: .init(id: $0, _type: "gameCenterGroups")) },
        versions: .init(data: [.init(id: "${version}", _type: "gameCenterAchievementVersions")])),
      _type: "gameCenterAchievements"),
      included: [.init(id: "${version}", _type: "gameCenterAchievementVersions")]))).created.body.json.data
    return try await achievement(id: created.id, client: client)
  }

  /// Changes an achievement; nil leaves a value as it is.
  public static func updateAchievement(
    id: String, referenceName: String? = nil, points: Int? = nil, showBeforeEarned: Bool? = nil, repeatable: Bool? = nil,
    archived: Bool? = nil, client: ASCClient
  ) async throws {
    _ = try await client.gameCenterAchievementsV2UpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
      attributes: .init(
        archived: archived, points: points, referenceName: referenceName, repeatable: repeatable, showBeforeEarned: showBeforeEarned),
      id: id, _type: "gameCenterAchievements")))).ok
  }

  public static func deleteAchievement(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterAchievementsV2DeleteInstance(path: .init(id: id)).noContent
  }

  /// A new version of an achievement whose latest one is live or in review, to change its text
  /// or images.
  public static func createAchievementVersion(achievementID: String, client: ASCClient) async throws -> Version {
    let v = try await client.gameCenterAchievementVersionsV2CreateInstance(body: .json(.init(data: .init(
      relationships: .init(achievement: .init(data: .init(id: achievementID, _type: "gameCenterAchievements"))),
      _type: "gameCenterAchievementVersions")))).created.body.json.data
    return Version(id: v.id, version: v.attributes?.version, state: v.attributes?.state)
  }

  /// Creates a language on a version, or changes it when `existing` is given (its nil fields
  /// are left as they are).
  @discardableResult
  public static func saveAchievementLocalization(
    versionID: String, locale: String, existing: AchievementLocalization?, fields: AchievementLocaleFields, client: ASCClient
  ) async throws -> String {
    if let existing {
      _ = try await client.gameCenterAchievementLocalizationsV2UpdateInstance(path: .init(id: existing.id), body: .json(.init(data: .init(
        attributes: .init(
          afterEarnedDescription: fields.afterEarnedDescription, beforeEarnedDescription: fields.beforeEarnedDescription, name: fields.name),
        id: existing.id, _type: "gameCenterAchievementLocalizations")))).ok
      return existing.id
    }
    return try await client.gameCenterAchievementLocalizationsV2CreateInstance(body: .json(.init(data: .init(
      attributes: .init(
        afterEarnedDescription: fields.afterEarnedDescription ?? "", beforeEarnedDescription: fields.beforeEarnedDescription ?? "",
        locale: locale, name: fields.name ?? ""),
      relationships: .init(version: .init(data: .init(id: versionID, _type: "gameCenterAchievementVersions"))),
      _type: "gameCenterAchievementLocalizations")))).created.body.json.data.id
  }

  public static func deleteAchievementLocalization(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterAchievementLocalizationsV2DeleteInstance(path: .init(id: id)).noContent
  }

  /// Uploads a language's image (one per language; delete the old one first).
  @discardableResult
  public static func uploadAchievementImage(localizationID: String, filePath: String, client: ASCClient) async throws -> String {
    let media = try MediaFile(path: filePath)
    return try await uploadAsset(
      filePath: media.path,
      reserve: {
        let response = try await client.gameCenterAchievementImagesV2CreateInstance(body: .json(.init(data: .init(
          attributes: .init(fileName: media.fileName, fileSize: media.fileSize),
          relationships: .init(localization: .init(data: .init(id: localizationID, _type: "gameCenterAchievementLocalizations"))),
          _type: "gameCenterAchievementImages")))).created.body.json
        return (response.data.id, response.data.attributes?.uploadOperations ?? [])
      },
      commit: { id, _ in
        _ = try await client.gameCenterAchievementImagesV2UpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
          attributes: .init(uploaded: true), id: id, _type: "gameCenterAchievementImages")))).ok
      })
  }

  public static func deleteAchievementImage(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterAchievementImagesV2DeleteInstance(path: .init(id: id)).noContent
  }

  /// Puts the app's achievements in this order (every achievement, by Apple ID).
  public static func reorderAchievements(owner: Owner, ids: [String], client: ASCClient) async throws {
    let data = ids.map { (id: String) in (id: id, type: "gameCenterAchievements") }
    switch owner {
      case .detail(let id):
        _ = try await client.gameCenterDetailsGameCenterAchievementsV2ReplaceToManyRelationship(path: .init(id: id), body: .json(.init(data: data.map { .init(id: $0.id, _type: $0.type) }))).noContent
      case .group(let id):
        _ = try await client.gameCenterGroupsGameCenterAchievementsV2ReplaceToManyRelationship(path: .init(id: id), body: .json(.init(data: data.map { .init(id: $0.id, _type: $0.type) }))).noContent
    }
  }

}
