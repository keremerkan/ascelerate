import ASCKit
import Foundation

extension GameCenter {
  /// An activity: a part of the game (a level, a mode) that players can be invited straight into,
  /// with the achievements and leaderboards that belong to it.
  public struct Activity: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let referenceName: String?
    /// The ID the game starts it with.
    public let vendorIdentifier: String?
    /// ASYNCHRONOUS or SYNCHRONOUS.
    public let playStyle: String?
    public let minimumPlayersCount: Int?
    public let maximumPlayersCount: Int?
    public let supportsPartyCode: Bool
    public let archived: Bool
    /// The game's own key-value properties for it.
    public let properties: [String: String]
    public let achievementIDs: [String]
    public let leaderboardIDs: [String]
    /// Oldest first.
    public let versions: [Version]
    /// The latest version's web page for players without the game.
    public let fallbackURL: String?
  }

  public struct ActivityLocalization: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let locale: String
    public let name: String?
    public let description: String?
    public let image: Image?
  }

  /// An activity's settings for create and update; nil leaves a value as it is.
  public struct ActivitySettings: Sendable {
    public var referenceName: String?
    public var playStyle: String?
    public var minimumPlayersCount: Int?
    public var maximumPlayersCount: Int?
    public var supportsPartyCode: Bool?
    public var properties: [String: String]?
    public var archived: Bool?

    public init(
      referenceName: String? = nil, playStyle: String? = nil, minimumPlayersCount: Int? = nil, maximumPlayersCount: Int? = nil,
      supportsPartyCode: Bool? = nil, properties: [String: String]? = nil, archived: Bool? = nil
    ) {
      self.referenceName = referenceName
      self.playStyle = playStyle
      self.minimumPlayersCount = minimumPlayersCount
      self.maximumPlayersCount = maximumPlayersCount
      self.supportsPartyCode = supportsPartyCode
      self.properties = properties
      self.archived = archived
    }
  }

  public static func activities(owner: Owner, client: ASCClient) async throws -> [Activity] {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        switch owner {
          case .detail(let id):
            try await client.gameCenterDetailsGameCenterActivitiesGetToManyRelated(path: .init(id: id), query: .init(limit: 200, include: [.versions, .achievementsV2, .leaderboardsV2], limitAchievements: 50, limitLeaderboards: 50, limitVersions: 50)).ok.body.json
          case .group(let id):
            try await client.gameCenterGroupsGameCenterActivitiesGetToManyRelated(path: .init(id: id), query: .init(limit: 200, include: [.versions, .achievementsV2, .leaderboardsV2], limitAchievements: 50, limitLeaderboards: 50, limitVersions: 50)).ok.body.json
          }
      }
    }
    var versions: [String: (Version, String?)] = [:]
    for page in pages {
      for case .gameCenterActivityVersions(let v) in page.included ?? [] {
        versions[v.id] = (Version(id: v.id, version: v.attributes?.version, state: v.attributes?.state), v.attributes?.fallbackUrl)
      }
    }
    return pages.flatMap(\.data).map { activity($0, versions: versions) }
  }

  private static func activity(_ a: Components.Schemas.GameCenterActivity, versions: [String: (Version, String?)]) -> Activity {
    let attributes = a.attributes
    let found = (a.relationships?.versions?.data ?? []).compactMap { versions[$0.id] }.sorted { ($0.0.version ?? 0) < ($1.0.version ?? 0) }
    return Activity(
      id: a.id, referenceName: attributes?.referenceName, vendorIdentifier: attributes?.vendorIdentifier, playStyle: attributes?.playStyle,
      minimumPlayersCount: attributes?.minimumPlayersCount, maximumPlayersCount: attributes?.maximumPlayersCount,
      supportsPartyCode: attributes?.supportsPartyCode ?? false, archived: attributes?.archived ?? false,
      properties: attributes?.properties?.additionalProperties ?? [:],
      achievementIDs: (a.relationships?.achievementsV2?.data ?? []).map(\.id), leaderboardIDs: (a.relationships?.leaderboardsV2?.data ?? []).map(\.id),
      versions: found.map(\.0), fallbackURL: found.last?.1)
  }

  /// Creates an activity with its first version.
  public static func createActivity(
    owner: Owner, vendorIdentifier: String, settings s: ActivitySettings, fallbackURL: String?, client: ASCClient
  ) async throws -> String {
    try await client.gameCenterActivitiesCreateInstance(body: .json(.init(
      data: .init(
        attributes: .init(
          maximumPlayersCount: s.maximumPlayersCount, minimumPlayersCount: s.minimumPlayersCount, playStyle: s.playStyle,
          properties: s.properties.map { .init(additionalProperties: $0) }, referenceName: s.referenceName ?? "",
          supportsPartyCode: s.supportsPartyCode, vendorIdentifier: vendorIdentifier),
        relationships: .init(
          gameCenterDetail: owner.detailID.map { .init(data: .init(id: $0, _type: "gameCenterDetails")) },
        gameCenterGroup: owner.groupID.map { .init(data: .init(id: $0, _type: "gameCenterGroups")) },
          versions: .init(data: [.init(id: "${version}", _type: "gameCenterActivityVersions")])),
        _type: "gameCenterActivities"),
      included: [.init(attributes: fallbackURL.map { .init(fallbackUrl: $0) }, id: "${version}", _type: "gameCenterActivityVersions")]
    ))).created.body.json.data.id
  }

  public static func updateActivity(id: String, settings s: ActivitySettings, client: ASCClient) async throws {
    _ = try await client.gameCenterActivitiesUpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
      attributes: .init(
        archived: s.archived, maximumPlayersCount: s.maximumPlayersCount, minimumPlayersCount: s.minimumPlayersCount, playStyle: s.playStyle,
        properties: s.properties.map { .init(additionalProperties: $0) }, referenceName: s.referenceName, supportsPartyCode: s.supportsPartyCode),
      id: id, _type: "gameCenterActivities")))).ok
  }

  /// Sets a version's web page for players without the game (an empty string clears it).
  public static func setActivityFallbackURL(versionID: String, url: String, client: ASCClient) async throws {
    _ = try await ASCNulls.sending(url.isEmpty ? [["data", "attributes", "fallbackUrl"]] : []) {
      try await client.gameCenterActivityVersionsUpdateInstance(path: .init(id: versionID), body: .json(.init(data: .init(
        attributes: .init(fallbackUrl: url.isEmpty ? nil : url), id: versionID, _type: "gameCenterActivityVersions")))).ok
    }
  }

  /// Adds achievements and leaderboards to an activity, or takes them out.
  public static func linkToActivity(
    activityID: String, achievementIDs: [String], leaderboardIDs: [String], remove: Bool, client: ASCClient
  ) async throws {
    if !achievementIDs.isEmpty {
      let body = Components.Schemas.GameCenterActivityAchievementsV2LinkagesRequest(
        data: achievementIDs.map { .init(id: $0, _type: "gameCenterAchievements") })
      if remove {
        _ = try await client.gameCenterActivitiesAchievementsV2DeleteToManyRelationship(path: .init(id: activityID), body: .json(body)).noContent
      } else {
        _ = try await client.gameCenterActivitiesAchievementsV2CreateToManyRelationship(path: .init(id: activityID), body: .json(body)).noContent
      }
    }
    if !leaderboardIDs.isEmpty {
      let body = Components.Schemas.GameCenterActivityLeaderboardsV2LinkagesRequest(
        data: leaderboardIDs.map { .init(id: $0, _type: "gameCenterLeaderboards") })
      if remove {
        _ = try await client.gameCenterActivitiesLeaderboardsV2DeleteToManyRelationship(path: .init(id: activityID), body: .json(body)).noContent
      } else {
        _ = try await client.gameCenterActivitiesLeaderboardsV2CreateToManyRelationship(path: .init(id: activityID), body: .json(body)).noContent
      }
    }
  }
}

extension GameCenter.Activity: GameCenterItem {
  public static let imageSize = GameCenterImageSize.exactly(width: 3840, height: 2160)
  public static let noun = "activity"
  public static func list(owner: GameCenter.Owner, client: ASCClient) async throws -> [Self] {
    try await GameCenter.activities(owner: owner, client: client)
  }
  public static func delete(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterActivitiesDeleteInstance(path: .init(id: id)).noContent
  }
  public static func createVersion(itemID: String, client: ASCClient) async throws -> GameCenter.Version {
    let v = try await client.gameCenterActivityVersionsCreateInstance(body: .json(.init(data: .init(
      relationships: .init(activity: .init(data: .init(id: itemID, _type: "gameCenterActivities"))),
      _type: "gameCenterActivityVersions")))).created.body.json.data
    return .init(id: v.id, version: v.attributes?.version, state: v.attributes?.state)
  }
  public static func localizations(versionID: String, client: ASCClient) async throws -> [GameCenter.ActivityLocalization] {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.gameCenterActivityVersionsLocalizationsGetToManyRelated(
          path: .init(id: versionID), query: .init(limit: 200, include: [.image])).ok.body.json
      }
    }
    var images: [String: Components.Schemas.GameCenterActivityImage] = [:]
    for page in pages {
      for case .gameCenterActivityImages(let image) in page.included ?? [] { images[image.id] = image }
    }
    return pages.flatMap(\.data).map { l in
      let image = l.relationships?.image?.data.flatMap { images[$0.id] }
      return GameCenter.ActivityLocalization(
        id: l.id, locale: l.attributes?.locale ?? "", name: l.attributes?.name, description: l.attributes?.description,
        image: image.map { GameCenter.image(id: $0.id, $0.attributes?.fileName, $0.attributes?.fileSize, $0.attributes?.imageAsset, $0.attributes?.assetDeliveryState) })
    }
    .sorted { $0.locale < $1.locale }
  }
  public static func saveLocalization(
    versionID: String, locale: String, existing: GameCenter.ActivityLocalization?, fields: ProductLocaleFields, client: ASCClient
  ) async throws -> String {
    if let existing {
      _ = try await client.gameCenterActivityLocalizationsUpdateInstance(path: .init(id: existing.id), body: .json(.init(data: .init(
        attributes: .init(description: fields.description, name: fields.name), id: existing.id, _type: "gameCenterActivityLocalizations")))).ok
      return existing.id
    }
    return try await client.gameCenterActivityLocalizationsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(description: fields.description, locale: locale, name: fields.name ?? ""),
      relationships: .init(version: .init(data: .init(id: versionID, _type: "gameCenterActivityVersions"))),
      _type: "gameCenterActivityLocalizations")))).created.body.json.data.id
  }
  public static func deleteLocalization(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterActivityLocalizationsDeleteInstance(path: .init(id: id)).noContent
  }
  public static func uploadImage(localizationID: String, filePath: String, client: ASCClient) async throws -> String {
    try await upload(filePath: filePath, owner: .init(localization: .init(data: .init(id: localizationID, _type: "gameCenterActivityLocalizations"))), client: client)
  }
  public static func deleteImage(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterActivityImagesDeleteInstance(path: .init(id: id)).noContent
  }
  public static func reviewItem(versionID: String) -> ReviewSubmissions.DraftItem { .gameCenterActivityVersion(versionID) }

  private static func upload(
    filePath: String, owner: Components.Schemas.GameCenterActivityImageCreateRequest.DataPayload.RelationshipsPayload, client: ASCClient
  ) async throws -> String {
    let media = try MediaFile(path: filePath)
    return try await uploadAsset(
      filePath: media.path,
      reserve: {
        let response = try await client.gameCenterActivityImagesCreateInstance(body: .json(.init(data: .init(
          attributes: .init(fileName: media.fileName, fileSize: media.fileSize), relationships: owner, _type: "gameCenterActivityImages")))
        ).created.body.json
        return (response.data.id, response.data.attributes?.uploadOperations ?? [])
      },
      commit: { id, _ in
        _ = try await client.gameCenterActivityImagesUpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
          attributes: .init(uploaded: true), id: id, _type: "gameCenterActivityImages")))).ok
      })
  }
}

extension GameCenter.Activity: GameCenterDefaultImageItem {
  public static func defaultImage(versionID: String, client: ASCClient) async throws -> GameCenter.Image? {
    try await optionalRelated {
      try await client.gameCenterActivityVersionsDefaultImageGetToOneRelated(path: .init(id: versionID)).ok.body.json.data
    }.map { GameCenter.image(id: $0.id, $0.attributes?.fileName, $0.attributes?.fileSize, $0.attributes?.imageAsset, $0.attributes?.assetDeliveryState) }
  }
  public static func uploadDefaultImage(versionID: String, filePath: String, client: ASCClient) async throws -> String {
    try await upload(filePath: filePath, owner: .init(version: .init(data: .init(id: versionID, _type: "gameCenterActivityVersions"))), client: client)
  }
}

extension GameCenter.ActivityLocalization: GameCenterLocalization {
  public var fields: ProductLocaleFields { .init(name: name, description: description) }
}
