import ASCKit
import Foundation

extension GameCenter {
  /// A challenge: players challenge friends to beat a score on one of the app's leaderboards.
  public struct Challenge: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let referenceName: String?
    public let vendorIdentifier: String?
    /// LEADERBOARD (the only type).
    public let challengeType: String?
    public let repeatable: Bool
    public let archived: Bool
    public let leaderboardID: String?
    /// Oldest first.
    public let versions: [Version]
  }

  public struct ChallengeLocalization: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let locale: String
    public let name: String?
    public let description: String?
    public let image: Image?
  }

  public static func challenges(owner: Owner, client: ASCClient) async throws -> [Challenge] {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        switch owner {
          case .detail(let id):
            try await client.gameCenterDetailsGameCenterChallengesGetToManyRelated(
              path: .init(id: id), query: .init(limit: 200, include: [.versions, .leaderboardV2], limitVersions: 50)).ok.body.json
          case .group(let id):
            try await client.gameCenterGroupsGameCenterChallengesGetToManyRelated(
              path: .init(id: id), query: .init(limit: 200, include: [.versions, .leaderboardV2], limitVersions: 50)).ok.body.json
        }
      }
    }
    var versions: [String: Version] = [:]
    for page in pages {
      for case .gameCenterChallengeVersions(let v) in page.included ?? [] {
        versions[v.id] = Version(id: v.id, version: v.attributes?.version, state: v.attributes?.state)
      }
    }
    return pages.flatMap(\.data).map { c in
      let a = c.attributes
      return Challenge(
        id: c.id, referenceName: a?.referenceName, vendorIdentifier: a?.vendorIdentifier, challengeType: a?.challengeType,
        repeatable: a?.repeatable ?? false, archived: a?.archived ?? false, leaderboardID: c.relationships?.leaderboardV2?.data?.id,
        versions: (c.relationships?.versions?.data ?? []).compactMap { versions[$0.id] }.sorted { ($0.version ?? 0) < ($1.version ?? 0) })
    }
  }

  /// Creates a leaderboard challenge with its first version, then links its leaderboard: the
  /// create request accepts a leaderboard but doesn't keep it (seen 2026-11-04). Apple's rules: the
  /// leaderboard counts each player's best score, and only a recurring one takes a challenge that
  /// isn't repeatable.
  public static func createChallenge(
    owner: Owner, vendorIdentifier: String, referenceName: String, leaderboardID: String, repeatable: Bool, client: ASCClient
  ) async throws -> String {
    let id = try await client.gameCenterChallengesCreateInstance(body: .json(.init(
      data: .init(
        attributes: .init(challengeType: "LEADERBOARD", referenceName: referenceName, repeatable: repeatable, vendorIdentifier: vendorIdentifier),
        relationships: .init(
          gameCenterDetail: owner.detailID.map { .init(data: .init(id: $0, _type: "gameCenterDetails")) },
        gameCenterGroup: owner.groupID.map { .init(data: .init(id: $0, _type: "gameCenterGroups")) },
          versions: .init(data: [.init(id: "${version}", _type: "gameCenterChallengeVersions")])),
        _type: "gameCenterChallenges"),
      included: [.init(id: "${version}", _type: "gameCenterChallengeVersions")]
    ))).created.body.json.data.id
    do {
      try await updateChallenge(id: id, leaderboardID: leaderboardID, client: client)
    } catch {
      // A challenge without its leaderboard is no use; take it back out.
      _ = try? await client.gameCenterChallengesDeleteInstance(path: .init(id: id))
      throw error
    }
    return id
  }

  /// Changes a challenge; nil leaves a value as it is.
  public static func updateChallenge(
    id: String, referenceName: String? = nil, repeatable: Bool? = nil, archived: Bool? = nil, leaderboardID: String? = nil, client: ASCClient
  ) async throws {
    func link() async throws {
      guard let leaderboardID else { return }
      _ = try await client.gameCenterChallengesLeaderboardV2UpdateToOneRelationship(
        path: .init(id: id), body: .json(.init(data: .init(id: leaderboardID, _type: "gameCenterLeaderboards")))).noContent
    }
    func attributes() async throws {
      guard referenceName != nil || repeatable != nil || archived != nil else { return }
      _ = try await client.gameCenterChallengesUpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
        attributes: .init(archived: archived, referenceName: referenceName, repeatable: repeatable), id: id, _type: "gameCenterChallenges")))).ok
    }
    // A challenge that isn't repeatable needs a recurring leaderboard, so turning repeatable on
    // goes before a move to a plain leaderboard, and a move to a recurring one before turning it off.
    if repeatable == true {
      try await attributes()
      try await link()
    } else {
      try await link()
      try await attributes()
    }
  }
}

extension GameCenter.Challenge: GameCenterItem {
  public static let imageSize = GameCenterImageSize.exactly(width: 3840, height: 2160)
  public static let noun = "challenge"
  public static func list(owner: GameCenter.Owner, client: ASCClient) async throws -> [Self] {
    try await GameCenter.challenges(owner: owner, client: client)
  }
  public static func delete(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterChallengesDeleteInstance(path: .init(id: id)).noContent
  }
  public static func createVersion(itemID: String, client: ASCClient) async throws -> GameCenter.Version {
    let v = try await client.gameCenterChallengeVersionsCreateInstance(body: .json(.init(data: .init(
      relationships: .init(challenge: .init(data: .init(id: itemID, _type: "gameCenterChallenges"))),
      _type: "gameCenterChallengeVersions")))).created.body.json.data
    return .init(id: v.id, version: v.attributes?.version, state: v.attributes?.state)
  }
  public static func localizations(versionID: String, client: ASCClient) async throws -> [GameCenter.ChallengeLocalization] {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.gameCenterChallengeVersionsLocalizationsGetToManyRelated(
          path: .init(id: versionID), query: .init(limit: 200, include: [.image])).ok.body.json
      }
    }
    var images: [String: Components.Schemas.GameCenterChallengeImage] = [:]
    for page in pages {
      for case .gameCenterChallengeImages(let image) in page.included ?? [] { images[image.id] = image }
    }
    return pages.flatMap(\.data).map { l in
      let image = l.relationships?.image?.data.flatMap { images[$0.id] }
      return GameCenter.ChallengeLocalization(
        id: l.id, locale: l.attributes?.locale ?? "", name: l.attributes?.name, description: l.attributes?.description,
        image: image.map { GameCenter.image(id: $0.id, $0.attributes?.fileName, $0.attributes?.fileSize, $0.attributes?.imageAsset, $0.attributes?.assetDeliveryState) })
    }
    .sorted { $0.locale < $1.locale }
  }
  public static func saveLocalization(
    versionID: String, locale: String, existing: GameCenter.ChallengeLocalization?, fields: ProductLocaleFields, client: ASCClient
  ) async throws -> String {
    if let existing {
      _ = try await client.gameCenterChallengeLocalizationsUpdateInstance(path: .init(id: existing.id), body: .json(.init(data: .init(
        attributes: .init(description: fields.description, name: fields.name), id: existing.id, _type: "gameCenterChallengeLocalizations")))).ok
      return existing.id
    }
    return try await client.gameCenterChallengeLocalizationsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(description: fields.description, locale: locale, name: fields.name ?? ""),
      relationships: .init(version: .init(data: .init(id: versionID, _type: "gameCenterChallengeVersions"))),
      _type: "gameCenterChallengeLocalizations")))).created.body.json.data.id
  }
  public static func deleteLocalization(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterChallengeLocalizationsDeleteInstance(path: .init(id: id)).noContent
  }
  public static func uploadImage(localizationID: String, filePath: String, client: ASCClient) async throws -> String {
    try await upload(filePath: filePath, owner: .init(localization: .init(data: .init(id: localizationID, _type: "gameCenterChallengeLocalizations"))), client: client)
  }
  public static func deleteImage(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterChallengeImagesDeleteInstance(path: .init(id: id)).noContent
  }
  public static func reviewItem(versionID: String) -> ReviewSubmissions.DraftItem { .gameCenterChallengeVersion(versionID) }

  private static func upload(
    filePath: String, owner: Components.Schemas.GameCenterChallengeImageCreateRequest.DataPayload.RelationshipsPayload, client: ASCClient
  ) async throws -> String {
    let media = try MediaFile(path: filePath)
    return try await uploadAsset(
      filePath: media.path,
      reserve: {
        let response = try await client.gameCenterChallengeImagesCreateInstance(body: .json(.init(data: .init(
          attributes: .init(fileName: media.fileName, fileSize: media.fileSize), relationships: owner, _type: "gameCenterChallengeImages")))
        ).created.body.json
        return (response.data.id, response.data.attributes?.uploadOperations ?? [])
      },
      commit: { id, _ in
        _ = try await client.gameCenterChallengeImagesUpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
          attributes: .init(uploaded: true), id: id, _type: "gameCenterChallengeImages")))).ok
      })
  }
}

extension GameCenter.Challenge: GameCenterDefaultImageItem {
  public static func defaultImage(versionID: String, client: ASCClient) async throws -> GameCenter.Image? {
    try await optionalRelated {
      try await client.gameCenterChallengeVersionsDefaultImageGetToOneRelated(path: .init(id: versionID)).ok.body.json.data
    }.map { GameCenter.image(id: $0.id, $0.attributes?.fileName, $0.attributes?.fileSize, $0.attributes?.imageAsset, $0.attributes?.assetDeliveryState) }
  }
  public static func uploadDefaultImage(versionID: String, filePath: String, client: ASCClient) async throws -> String {
    try await upload(filePath: filePath, owner: .init(version: .init(data: .init(id: versionID, _type: "gameCenterChallengeVersions"))), client: client)
  }
}

extension GameCenter.ChallengeLocalization: GameCenterLocalization {
  public var fields: ProductLocaleFields { .init(name: name, description: description) }
}
