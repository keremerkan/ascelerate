import ASCKit
import Foundation

extension GameCenter {
  public struct Leaderboard: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let referenceName: String?
    /// The ID the game submits scores with.
    public let vendorIdentifier: String?
    /// How scores read: INTEGER, DECIMAL_POINT_1_PLACE…, ELAPSED_TIME_SECOND…, MONEY_DOLLAR….
    public let defaultFormatter: String?
    /// BEST_SCORE or MOST_RECENT_SCORE.
    public let submissionType: String?
    /// DESC (high scores first) or ASC (low first).
    public let scoreSortType: String?
    public let scoreRangeStart: String?
    public let scoreRangeEnd: String?
    /// A recurring leaderboard's first start, how long each occurrence lasts (ISO 8601 with time
    /// parts only: `PT168H`; Apple refuses `P7D`) and how often it restarts
    /// (`FREQ=MINUTELY|HOURLY|DAILY;INTERVAL=n`, the only rules Apple takes; seen 2026-11-04).
    public let recurrenceStartDate: Date?
    public let recurrenceDuration: String?
    public let recurrenceRule: String?
    /// SHOW_FOR_ALL or HIDE_FOR_ALL.
    public let visibility: String?
    public let archived: Bool
    /// Oldest first.
    public let versions: [Version]

    public var latestVersion: Version? { GameCenter.latest(versions) }
  }

  /// A leaderboard's settings for create and update. On update, nil leaves a value as it is and
  /// an empty string clears it (score range, recurrence).
  public struct LeaderboardSettings: Sendable {
    public var referenceName: String?
    public var defaultFormatter: String?
    public var submissionType: String?
    public var scoreSortType: String?
    public var scoreRangeStart: String?
    public var scoreRangeEnd: String?
    public var recurrenceStartDate: Date?
    public var recurrenceDuration: String?
    public var recurrenceRule: String?
    public var visibility: String?
    public var archived: Bool?

    public init(
      referenceName: String? = nil, defaultFormatter: String? = nil, submissionType: String? = nil, scoreSortType: String? = nil,
      scoreRangeStart: String? = nil, scoreRangeEnd: String? = nil, recurrenceStartDate: Date? = nil,
      recurrenceDuration: String? = nil, recurrenceRule: String? = nil, visibility: String? = nil, archived: Bool? = nil
    ) {
      self.referenceName = referenceName
      self.defaultFormatter = defaultFormatter
      self.submissionType = submissionType
      self.scoreSortType = scoreSortType
      self.scoreRangeStart = scoreRangeStart
      self.scoreRangeEnd = scoreRangeEnd
      self.recurrenceStartDate = recurrenceStartDate
      self.recurrenceDuration = recurrenceDuration
      self.recurrenceRule = recurrenceRule
      self.visibility = visibility
      self.archived = archived
    }

    /// The fields given as empty strings, which an update sends as null.
    var cleared: [[String]] {
      [("scoreRangeStart", scoreRangeStart), ("scoreRangeEnd", scoreRangeEnd), ("recurrenceDuration", recurrenceDuration),
       ("recurrenceRule", recurrenceRule)]
        .filter { $0.1 == "" }.map { ["data", "attributes", $0.0] }
    }

    func value(_ value: String?) -> String? { value == "" ? nil : value }
  }

  /// The formatter values (`defaultFormatter`, a localization's `formatterOverride`).
  public static let formatters = [
    "INTEGER", "DECIMAL_POINT_1_PLACE", "DECIMAL_POINT_2_PLACE", "DECIMAL_POINT_3_PLACE", "ELAPSED_TIME_CENTISECOND",
    "ELAPSED_TIME_MINUTE", "ELAPSED_TIME_SECOND", "MONEY_POUND_DECIMAL", "MONEY_POUND", "MONEY_DOLLAR_DECIMAL", "MONEY_DOLLAR",
    "MONEY_EURO_DECIMAL", "MONEY_EURO", "MONEY_FRANC_DECIMAL", "MONEY_FRANC", "MONEY_KRONER_DECIMAL", "MONEY_KRONER", "MONEY_YEN",
  ]

  public struct LeaderboardLocalization: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let locale: String
    public let name: String?
    public let description: String?
    /// A formatter of its own for this language (nil: the leaderboard's).
    public let formatterOverride: String?
    /// The unit after a score (" points"), and after a score of one (" point").
    public let formatterSuffix: String?
    public let formatterSuffixSingular: String?
    public let image: Image?
  }

  /// The app's leaderboards in the order Game Center shows them.
  public static func leaderboards(detailID: String, client: ASCClient) async throws -> [Leaderboard] {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.gameCenterDetailsGameCenterLeaderboardsV2GetToManyRelated(
          path: .init(id: detailID), query: .init(limit: 200, include: [.versions], limitVersions: 50)
        ).ok.body.json
      }
    }
    var versions: [String: Version] = [:]
    for page in pages {
      for case .gameCenterLeaderboardVersions(let v) in page.included ?? [] {
        versions[v.id] = Version(id: v.id, version: v.attributes?.version, state: v.attributes?.state)
      }
    }
    return pages.flatMap(\.data).map { leaderboard($0, versions: versions) }
  }

  public static func leaderboard(id: String, client: ASCClient) async throws -> Leaderboard {
    let response = try await withTransientRetry {
      try await client.gameCenterLeaderboardsV2GetInstance(path: .init(id: id), query: .init(include: [.versions], limitVersions: 50))
        .ok.body.json
    }
    var versions: [String: Version] = [:]
    for case .gameCenterLeaderboardVersions(let v) in response.included ?? [] {
      versions[v.id] = Version(id: v.id, version: v.attributes?.version, state: v.attributes?.state)
    }
    return leaderboard(response.data, versions: versions)
  }

  private static func leaderboard(_ l: Components.Schemas.GameCenterLeaderboardV2, versions: [String: Version]) -> Leaderboard {
    let a = l.attributes
    return Leaderboard(
      id: l.id, referenceName: a?.referenceName, vendorIdentifier: a?.vendorIdentifier, defaultFormatter: a?.defaultFormatter,
      submissionType: a?.submissionType, scoreSortType: a?.scoreSortType, scoreRangeStart: a?.scoreRangeStart,
      scoreRangeEnd: a?.scoreRangeEnd, recurrenceStartDate: a?.recurrenceStartDate, recurrenceDuration: a?.recurrenceDuration,
      recurrenceRule: a?.recurrenceRule, visibility: a?.visibility, archived: a?.archived ?? false,
      versions: (l.relationships?.versions?.data ?? []).compactMap { versions[$0.id] }.sorted { ($0.version ?? 0) < ($1.version ?? 0) })
  }

  /// Creates a leaderboard with its first version. `settings` needs the formatter, the
  /// submission and sort types and the reference name.
  public static func createLeaderboard(
    detailID: String, vendorIdentifier: String, settings s: LeaderboardSettings, client: ASCClient
  ) async throws -> Leaderboard {
    let created = try await client.gameCenterLeaderboardsV2CreateInstance(body: .json(.init(data: .init(
      attributes: .init(
        defaultFormatter: s.defaultFormatter ?? "INTEGER", recurrenceDuration: s.value(s.recurrenceDuration),
        recurrenceRule: s.value(s.recurrenceRule), recurrenceStartDate: s.recurrenceStartDate, referenceName: s.referenceName ?? "",
        scoreRangeEnd: s.value(s.scoreRangeEnd), scoreRangeStart: s.value(s.scoreRangeStart), scoreSortType: s.scoreSortType ?? "DESC",
        submissionType: s.submissionType ?? "BEST_SCORE", vendorIdentifier: vendorIdentifier, visibility: s.visibility),
      relationships: .init(
        gameCenterDetail: .init(data: .init(id: detailID, _type: "gameCenterDetails")),
        versions: .init(data: [.init(id: "${version}", _type: "gameCenterLeaderboardVersions")])),
      _type: "gameCenterLeaderboards"),
      included: [.init(id: "${version}", _type: "gameCenterLeaderboardVersions")]))).created.body.json.data
    return try await leaderboard(id: created.id, client: client)
  }

  public static func updateLeaderboard(id: String, settings s: LeaderboardSettings, client: ASCClient) async throws {
    _ = try await ASCNulls.sending(s.cleared) {
      try await client.gameCenterLeaderboardsV2UpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
        attributes: .init(
          archived: s.archived, defaultFormatter: s.defaultFormatter, recurrenceDuration: s.value(s.recurrenceDuration),
          recurrenceRule: s.value(s.recurrenceRule), recurrenceStartDate: s.recurrenceStartDate, referenceName: s.referenceName,
          scoreRangeEnd: s.value(s.scoreRangeEnd), scoreRangeStart: s.value(s.scoreRangeStart), scoreSortType: s.scoreSortType,
          submissionType: s.submissionType, visibility: s.visibility),
        id: id, _type: "gameCenterLeaderboards")))).ok
    }
  }

  public static func deleteLeaderboard(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterLeaderboardsV2DeleteInstance(path: .init(id: id)).noContent
  }

  public static func createLeaderboardVersion(leaderboardID: String, client: ASCClient) async throws -> Version {
    let v = try await client.gameCenterLeaderboardVersionsV2CreateInstance(body: .json(.init(data: .init(
      relationships: .init(leaderboard: .init(data: .init(id: leaderboardID, _type: "gameCenterLeaderboards"))),
      _type: "gameCenterLeaderboardVersions")))).created.body.json.data
    return Version(id: v.id, version: v.attributes?.version, state: v.attributes?.state)
  }

  public static func leaderboardLocalizations(versionID: String, client: ASCClient) async throws -> [LeaderboardLocalization] {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.gameCenterLeaderboardVersionsV2LocalizationsGetToManyRelated(
          path: .init(id: versionID), query: .init(limit: 200, include: [.image])
        ).ok.body.json
      }
    }
    var images: [String: Components.Schemas.GameCenterLeaderboardImageV2] = [:]
    for page in pages {
      for case .gameCenterLeaderboardImages(let image) in page.included ?? [] { images[image.id] = image }
    }
    return pages.flatMap(\.data).map { l in
      let a = l.attributes
      let image = l.relationships?.image?.data.flatMap { images[$0.id] }
      return LeaderboardLocalization(
        id: l.id, locale: a?.locale ?? "", name: a?.name, description: a?.description, formatterOverride: a?.formatterOverride,
        formatterSuffix: a?.formatterSuffix, formatterSuffixSingular: a?.formatterSuffixSingular,
        image: image.map { GameCenter.image(id: $0.id, $0.attributes?.fileName, $0.attributes?.fileSize, $0.attributes?.imageAsset, $0.attributes?.assetDeliveryState) })
    }
    .sorted { $0.locale < $1.locale }
  }

  /// Creates a language on a version, or changes `existing` (nil fields are left as they are; an
  /// empty formatter override, suffix or description is cleared).
  @discardableResult
  public static func saveLeaderboardLocalization(
    versionID: String, locale: String, existing: LeaderboardLocalization?, fields f: LeaderboardLocaleFields, client: ASCClient
  ) async throws -> String {
    func value(_ v: String?) -> String? { v == "" ? nil : v }
    if let existing {
      let cleared = [("description", f.description), ("formatterOverride", f.formatterOverride), ("formatterSuffix", f.formatterSuffix),
                     ("formatterSuffixSingular", f.formatterSuffixSingular)]
        .filter { $0.1 == "" }.map { ["data", "attributes", $0.0] }
      _ = try await ASCNulls.sending(cleared) {
        try await client.gameCenterLeaderboardLocalizationsV2UpdateInstance(path: .init(id: existing.id), body: .json(.init(data: .init(
          attributes: .init(
            description: value(f.description), formatterOverride: value(f.formatterOverride), formatterSuffix: value(f.formatterSuffix),
            formatterSuffixSingular: value(f.formatterSuffixSingular), name: f.name),
          id: existing.id, _type: "gameCenterLeaderboardLocalizations")))).ok
      }
      return existing.id
    }
    return try await client.gameCenterLeaderboardLocalizationsV2CreateInstance(body: .json(.init(data: .init(
      attributes: .init(
        description: value(f.description), formatterOverride: value(f.formatterOverride), formatterSuffix: value(f.formatterSuffix),
        formatterSuffixSingular: value(f.formatterSuffixSingular), locale: locale, name: f.name ?? ""),
      relationships: .init(version: .init(data: .init(id: versionID, _type: "gameCenterLeaderboardVersions"))),
      _type: "gameCenterLeaderboardLocalizations")))).created.body.json.data.id
  }

  public static func deleteLeaderboardLocalization(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterLeaderboardLocalizationsV2DeleteInstance(path: .init(id: id)).noContent
  }

  @discardableResult
  public static func uploadLeaderboardImage(localizationID: String, filePath: String, client: ASCClient) async throws -> String {
    let media = try MediaFile(path: filePath)
    return try await uploadAsset(
      filePath: media.path,
      reserve: {
        let response = try await client.gameCenterLeaderboardImagesV2CreateInstance(body: .json(.init(data: .init(
          attributes: .init(fileName: media.fileName, fileSize: media.fileSize),
          relationships: .init(localization: .init(data: .init(id: localizationID, _type: "gameCenterLeaderboardLocalizations"))),
          _type: "gameCenterLeaderboardImages")))).created.body.json
        return (response.data.id, response.data.attributes?.uploadOperations ?? [])
      },
      commit: { id, _ in
        _ = try await client.gameCenterLeaderboardImagesV2UpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
          attributes: .init(uploaded: true), id: id, _type: "gameCenterLeaderboardImages")))).ok
      })
  }

  public static func deleteLeaderboardImage(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterLeaderboardImagesV2DeleteInstance(path: .init(id: id)).noContent
  }

  public static func reorderLeaderboards(detailID: String, ids: [String], client: ASCClient) async throws {
    _ = try await client.gameCenterDetailsGameCenterLeaderboardsV2ReplaceToManyRelationship(
      path: .init(id: detailID), body: .json(.init(data: ids.map { .init(id: $0, _type: "gameCenterLeaderboards") }))).noContent
  }

  /// Makes a leaderboard the one the Game Center dashboard opens on.
  public static func setDefaultLeaderboard(detailID: String, leaderboardID: String, client: ASCClient) async throws {
    _ = try await client.gameCenterDetailsUpdateInstance(path: .init(id: detailID), body: .json(.init(data: .init(
      id: detailID,
      relationships: .init(defaultLeaderboardV2: .init(data: .init(id: leaderboardID, _type: "gameCenterLeaderboards"))),
      _type: "gameCenterDetails")))).ok
  }
}
