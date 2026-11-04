import ASCKit
import Foundation

extension GameCenter {
  /// A group of leaderboards shown together.
  public struct LeaderboardSet: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let referenceName: String?
    public let vendorIdentifier: String?
    /// Its leaderboards' Apple IDs, in its order.
    public let leaderboardIDs: [String]
    /// Oldest first.
    public let versions: [Version]

    public var latestVersion: Version? { GameCenter.latest(versions) }
  }

  public struct LeaderboardSetLocalization: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let locale: String
    public let name: String?
    public let image: Image?
  }

  public static func leaderboardSets(detailID: String, client: ASCClient) async throws -> [LeaderboardSet] {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.gameCenterDetailsGameCenterLeaderboardSetsV2GetToManyRelated(
          path: .init(id: detailID), query: .init(limit: 200, include: [.versions], limitVersions: 50)
        ).ok.body.json
      }
    }
    var versions: [String: Version] = [:]
    for page in pages {
      for case .gameCenterLeaderboardSetVersions(let v) in page.included ?? [] {
        versions[v.id] = Version(id: v.id, version: v.attributes?.version, state: v.attributes?.state)
      }
    }
    // A set's leaderboards are read on their own: an include caps them at 50.
    let found = versions
    return try await boundedConcurrentMap(pages.flatMap(\.data)) { set in
      try await leaderboardSet(set, versions: found, client: client)
    }
  }

  public static func leaderboardSet(id: String, client: ASCClient) async throws -> LeaderboardSet {
    let response = try await withTransientRetry {
      try await client.gameCenterLeaderboardSetsV2GetInstance(path: .init(id: id), query: .init(include: [.versions], limitVersions: 50))
        .ok.body.json
    }
    var versions: [String: Version] = [:]
    for case .gameCenterLeaderboardSetVersions(let v) in response.included ?? [] {
      versions[v.id] = Version(id: v.id, version: v.attributes?.version, state: v.attributes?.state)
    }
    return try await leaderboardSet(response.data, versions: versions, client: client)
  }

  private static func leaderboardSet(
    _ set: Components.Schemas.GameCenterLeaderboardSetV2, versions: [String: Version], client: ASCClient
  ) async throws -> LeaderboardSet {
    let members = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.gameCenterLeaderboardSetsV2GameCenterLeaderboardsGetToManyRelationship(
          path: .init(id: set.id), query: .init(limit: 200)).ok.body.json
      }
    }.flatMap(\.data).map(\.id)
    return LeaderboardSet(
      id: set.id, referenceName: set.attributes?.referenceName, vendorIdentifier: set.attributes?.vendorIdentifier,
      leaderboardIDs: members,
      versions: (set.relationships?.versions?.data ?? []).compactMap { versions[$0.id] }.sorted { ($0.version ?? 0) < ($1.version ?? 0) })
  }

  /// Creates a set with its first version, holding `leaderboardIDs` in that order. With
  /// leaderboards, the request names no detail: Apple refuses both, and the set takes the
  /// leaderboards' (seen 2026-11-04).
  public static func createLeaderboardSet(
    detailID: String, vendorIdentifier: String, referenceName: String, leaderboardIDs: [String], client: ASCClient
  ) async throws -> LeaderboardSet {
    let created = try await client.gameCenterLeaderboardSetsV2CreateInstance(body: .json(.init(data: .init(
      attributes: .init(referenceName: referenceName, vendorIdentifier: vendorIdentifier),
      relationships: .init(
        gameCenterDetail: leaderboardIDs.isEmpty ? .init(data: .init(id: detailID, _type: "gameCenterDetails")) : nil,
        gameCenterLeaderboards: leaderboardIDs.isEmpty ? nil : .init(data: leaderboardIDs.map { .init(id: $0, _type: "gameCenterLeaderboards") }),
        versions: .init(data: [.init(id: "${version}", _type: "gameCenterLeaderboardSetVersions")])),
      _type: "gameCenterLeaderboardSets"),
      included: [.init(id: "${version}", _type: "gameCenterLeaderboardSetVersions")]))).created.body.json.data
    return try await leaderboardSet(id: created.id, client: client)
  }

  public static func renameLeaderboardSet(id: String, referenceName: String, client: ASCClient) async throws {
    _ = try await client.gameCenterLeaderboardSetsV2UpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
      attributes: .init(referenceName: referenceName), id: id, _type: "gameCenterLeaderboardSets")))).ok
  }

  public static func deleteLeaderboardSet(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterLeaderboardSetsV2DeleteInstance(path: .init(id: id)).noContent
  }

  /// Sets a set's leaderboards, in this order (replacing them).
  public static func setLeaderboards(setID: String, leaderboardIDs: [String], client: ASCClient) async throws {
    _ = try await client.gameCenterLeaderboardSetsV2GameCenterLeaderboardsReplaceToManyRelationship(
      path: .init(id: setID), body: .json(.init(data: leaderboardIDs.map { .init(id: $0, _type: "gameCenterLeaderboards") }))).noContent
  }

  public static func createLeaderboardSetVersion(setID: String, client: ASCClient) async throws -> Version {
    let v = try await client.gameCenterLeaderboardSetVersionsV2CreateInstance(body: .json(.init(data: .init(
      relationships: .init(leaderboardSet: .init(data: .init(id: setID, _type: "gameCenterLeaderboardSets"))),
      _type: "gameCenterLeaderboardSetVersions")))).created.body.json.data
    return Version(id: v.id, version: v.attributes?.version, state: v.attributes?.state)
  }

  public static func leaderboardSetLocalizations(versionID: String, client: ASCClient) async throws -> [LeaderboardSetLocalization] {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.gameCenterLeaderboardSetVersionsV2LocalizationsGetToManyRelated(
          path: .init(id: versionID), query: .init(limit: 200, include: [.image])
        ).ok.body.json
      }
    }
    var images: [String: Components.Schemas.GameCenterLeaderboardSetImageV2] = [:]
    for page in pages {
      for case .gameCenterLeaderboardSetImages(let image) in page.included ?? [] { images[image.id] = image }
    }
    return pages.flatMap(\.data).map { l in
      let image = l.relationships?.image?.data.flatMap { images[$0.id] }
      return LeaderboardSetLocalization(
        id: l.id, locale: l.attributes?.locale ?? "", name: l.attributes?.name,
        image: image.map { GameCenter.image(id: $0.id, $0.attributes?.fileName, $0.attributes?.fileSize, $0.attributes?.imageAsset, $0.attributes?.assetDeliveryState) })
    }
    .sorted { $0.locale < $1.locale }
  }

  @discardableResult
  public static func saveLeaderboardSetLocalization(
    versionID: String, locale: String, existing: LeaderboardSetLocalization?, fields: LeaderboardSetLocaleFields, client: ASCClient
  ) async throws -> String {
    if let existing {
      _ = try await client.gameCenterLeaderboardSetLocalizationsV2UpdateInstance(path: .init(id: existing.id), body: .json(.init(data: .init(
        attributes: .init(name: fields.name), id: existing.id, _type: "gameCenterLeaderboardSetLocalizations")))).ok
      return existing.id
    }
    return try await client.gameCenterLeaderboardSetLocalizationsV2CreateInstance(body: .json(.init(data: .init(
      attributes: .init(locale: locale, name: fields.name ?? ""),
      relationships: .init(version: .init(data: .init(id: versionID, _type: "gameCenterLeaderboardSetVersions"))),
      _type: "gameCenterLeaderboardSetLocalizations")))).created.body.json.data.id
  }

  public static func deleteLeaderboardSetLocalization(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterLeaderboardSetLocalizationsV2DeleteInstance(path: .init(id: id)).noContent
  }

  @discardableResult
  public static func uploadLeaderboardSetImage(localizationID: String, filePath: String, client: ASCClient) async throws -> String {
    let media = try MediaFile(path: filePath)
    return try await uploadAsset(
      filePath: media.path,
      reserve: {
        let response = try await client.gameCenterLeaderboardSetImagesV2CreateInstance(body: .json(.init(data: .init(
          attributes: .init(fileName: media.fileName, fileSize: media.fileSize),
          relationships: .init(localization: .init(data: .init(id: localizationID, _type: "gameCenterLeaderboardSetLocalizations"))),
          _type: "gameCenterLeaderboardSetImages")))).created.body.json
        return (response.data.id, response.data.attributes?.uploadOperations ?? [])
      },
      commit: { id, _ in
        _ = try await client.gameCenterLeaderboardSetImagesV2UpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
          attributes: .init(uploaded: true), id: id, _type: "gameCenterLeaderboardSetImages")))).ok
      })
  }

  public static func deleteLeaderboardSetImage(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterLeaderboardSetImagesV2DeleteInstance(path: .init(id: id)).noContent
  }

  public static func reorderLeaderboardSets(detailID: String, ids: [String], client: ASCClient) async throws {
    _ = try await client.gameCenterDetailsGameCenterLeaderboardSetsV2ReplaceToManyRelationship(
      path: .init(id: detailID), body: .json(.init(data: ids.map { .init(id: $0, _type: "gameCenterLeaderboardSets") }))).noContent
  }
}
