import ASCKit
import Foundation

/// An app's Game Center: the per-app record (`gameCenterDetails`) that achievements,
/// leaderboards and leaderboard sets belong to, the per-version switch (`gameCenterAppVersions`)
/// and the display order of each list.
public enum GameCenter {
  public struct Detail: Codable, Hashable, Sendable {
    public let id: String
    public let arcadeEnabled: Bool
    /// The leaderboard the Game Center dashboard opens on.
    public let defaultLeaderboardID: String?
    /// The group whose achievements and leaderboards the app shares with others.
    public let groupID: String?

    /// Where its achievements, leaderboards and the rest live: the group's when the app is in one.
    public var owner: Owner { groupID.map(Owner.group) ?? .detail(id) }
  }

  /// What achievements, leaderboards, sets, activities and challenges belong to: an app's Game
  /// Center record, or the group it shares them through.
  public enum Owner: Hashable, Sendable {
    case detail(String)
    case group(String)

    var detailID: String? { if case .detail(let id) = self { id } else { nil } }
    var groupID: String? { if case .group(let id) = self { id } else { nil } }
  }

  /// The app's Game Center record; nil when Game Center isn't on for the app.
  public static func detail(appID: String, client: ASCClient) async throws -> Detail? {
    guard let detail = try await optionalRelated({
      try await withTransientRetry {
        try await client.appsGameCenterDetailGetToOneRelated(
          path: .init(id: appID),
          query: .init(
            fieldsGameCenterDetails: [.arcadeEnabled, .defaultLeaderboardV2, .defaultGroupLeaderboardV2, .gameCenterGroup],
            include: [.defaultLeaderboardV2, .defaultGroupLeaderboardV2, .gameCenterGroup])
        ).ok.body.json.data
      }
    }) else { return nil }
    return Detail(
      id: detail.id, arcadeEnabled: detail.attributes?.arcadeEnabled ?? false,
      defaultLeaderboardID: detail.relationships?.defaultLeaderboardV2?.data?.id ?? detail.relationships?.defaultGroupLeaderboardV2?.data?.id,
      groupID: detail.relationships?.gameCenterGroup?.data?.id)
  }

  /// Whether an App Store version has Game Center on (App Store Connect's Game Center switch on
  /// the version page); nil when the version has no Game Center record yet (off).
  public static func isEnabled(versionID: String, client: ASCClient) async throws -> Bool? {
    try await optionalRelated {
      try await withTransientRetry {
        try await client.appStoreVersionsGameCenterAppVersionGetToOneRelated(path: .init(id: versionID)).ok.body.json.data
      }
    }.map { $0.attributes?.enabled ?? false }
  }

  /// Turns Game Center on or off for an App Store version, creating its record when it has none.
  public static func setEnabled(_ enabled: Bool, versionID: String, client: ASCClient) async throws {
    var record = try await optionalRelated {
      try await client.appStoreVersionsGameCenterAppVersionGetToOneRelated(path: .init(id: versionID)).ok.body.json.data
    }
    if record == nil {
      guard enabled else { return }
      record = try await client.gameCenterAppVersionsCreateInstance(body: .json(.init(data: .init(
        relationships: .init(appStoreVersion: .init(data: .init(id: versionID, _type: "appStoreVersions"))),
        _type: "gameCenterAppVersions")))).created.body.json.data
      if record?.attributes?.enabled == true { return }
    }
    guard let record else { return }
    _ = try await client.gameCenterAppVersionsUpdateInstance(path: .init(id: record.id), body: .json(.init(data: .init(
      attributes: .init(enabled: enabled), id: record.id, _type: "gameCenterAppVersions")))).ok
  }

  /// Turns Game Center on for the app. The API can't turn it off again.
  public static func enable(appID: String, client: ASCClient) async throws -> Detail {
    let created = try await client.gameCenterDetailsCreateInstance(body: .json(.init(data: .init(
      relationships: .init(app: .init(data: .init(id: appID, _type: "apps"))), _type: "gameCenterDetails")))).created.body.json.data
    return Detail(id: created.id, arcadeEnabled: created.attributes?.arcadeEnabled ?? false, defaultLeaderboardID: nil, groupID: nil)
  }
}

extension GameCenter {
  public typealias Image = InAppPurchases.Image

  /// A version of an achievement, leaderboard or leaderboard set: its text and images live on
  /// one, and a version goes to App Review with the app (`ReviewSubmissions.DraftItem`).
  public struct Version: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let version: Int?
    /// PREPARE_FOR_SUBMISSION, READY_FOR_REVIEW, WAITING_FOR_REVIEW, IN_REVIEW, ACCEPTED,
    /// PENDING_RELEASE, LIVE, REJECTED, DEVELOPER_REJECTED or REPLACED_WITH_NEW_VERSION.
    public let state: String?

    public init(id: String, version: Int?, state: String?) {
      self.id = id
      self.version = version
      self.state = state
    }

    /// Whether its text and images can change.
    public var isEditable: Bool { GameCenter.editableStates.contains(state ?? "") }
  }

  /// The version states whose localizations and images can change.
  public static let editableStates: Set<String> = ["PREPARE_FOR_SUBMISSION", "REJECTED", "DEVELOPER_REJECTED"]

  /// The highest version, the one App Store Connect shows.
  static func latest(_ versions: [Version]) -> Version? {
    versions.max { ($0.version ?? 0) < ($1.version ?? 0) }
  }

  /// An image of any Game Center kind from its attributes.
  static func image(
    id: String, _ fileName: String?, _ fileSize: Int?, _ asset: Components.Schemas.ImageAsset?, _ state: Components.Schemas.AppMediaAssetState?
  ) -> Image {
    Image(
      id: id, fileName: fileName ?? "", fileSize: fileSize ?? 0, templateURL: asset?.templateUrl.flatMap { $0.isEmpty ? nil : $0 },
      width: asset?.width, height: asset?.height, state: state?.state, errors: mediaStateMessages(state?.errors))
  }
}

/// An achievement, leaderboard or leaderboard set: what the three share (versions holding
/// languages with an image each, a display order, App Review), so one set of commands serves all.
public protocol GameCenterItem: Codable, Sendable {
  associatedtype Localization: GameCenterLocalization
  /// "achievement", "leaderboard", "leaderboard set".
  static var noun: String { get }
  var id: String { get }
  var vendorIdentifier: String? { get }
  var referenceName: String? { get }
  /// Oldest first.
  var versions: [GameCenter.Version] { get }

  static func list(owner: GameCenter.Owner, client: ASCClient) async throws -> [Self]
  static func delete(id: String, client: ASCClient) async throws
  static func createVersion(itemID: String, client: ASCClient) async throws -> GameCenter.Version
  static func localizations(versionID: String, client: ASCClient) async throws -> [Localization]
  @discardableResult
  static func saveLocalization(
    versionID: String, locale: String, existing: Localization?, fields: Localization.Fields, client: ASCClient
  ) async throws -> String
  static func deleteLocalization(id: String, client: ASCClient) async throws
  @discardableResult
  static func uploadImage(localizationID: String, filePath: String, client: ASCClient) async throws -> String
  static func deleteImage(id: String, client: ASCClient) async throws
  static func reviewItem(versionID: String) -> ReviewSubmissions.DraftItem
  /// The sizes its images take.
  static var imageSize: GameCenterImageSize { get }
}

/// A kind whose items have a display order (achievements, leaderboards, leaderboard sets).
public protocol GameCenterOrderedItem: GameCenterItem {
  /// Puts the app's items of this kind in this order (every one, by Apple ID).
  static func reorder(owner: GameCenter.Owner, ids: [String], client: ASCClient) async throws
}

/// A kind whose versions have a default image besides each language's (activities, challenges).
public protocol GameCenterDefaultImageItem: GameCenterItem {
  static func defaultImage(versionID: String, client: ASCClient) async throws -> GameCenter.Image?
  @discardableResult
  static func uploadDefaultImage(versionID: String, filePath: String, client: ASCClient) async throws -> String
}

/// A language of a Game Center item's version.
public protocol GameCenterLocalization: Codable, Sendable {
  /// Its text as a localization file holds it.
  associatedtype Fields: Codable, Equatable, Sendable
  var id: String { get }
  var locale: String { get }
  var image: GameCenter.Image? { get }
  var fields: Fields { get }
}

/// The image sizes a kind takes (seen live 2026-11-04).
public enum GameCenterImageSize: Sendable {
  /// Square, at least this many pixels a side (achievements, leaderboards, sets: 600 and 2048
  /// were taken, 511 failed with IMAGE_BAD_DIMENSION_SM_LESS_MIN, a screenshot with
  /// IMAGE_BAD_ASPECT_RATIO).
  case squareAtLeast(Int)
  /// Exactly this size (activities and challenges, language and default images: 3840×2160 taken;
  /// 1920×1080, 2560×1440, 4096×2304 and 1024×1024 failed with IMAGE_INCORRECT_DIMENSIONS).
  case exactly(width: Int, height: Int)

  public func accepts(width: Int, height: Int) -> Bool {
    switch self {
      case .squareAtLeast(let side): width == height && width >= side
      case .exactly(let w, let h): width == w && height == h
    }
  }

  public var description: String {
    switch self {
      case .squareAtLeast(let side): "a square one of at least \(side)×\(side) (512×512 or 1024×1024)"
      case .exactly(let w, let h): "exactly \(w)×\(h)"
    }
  }
}

extension GameCenterItem {
  public static var imageSize: GameCenterImageSize { .squareAtLeast(512) }

  public var latestVersion: GameCenter.Version? { GameCenter.latest(versions) }

  /// How the CLI and lookups name it: its vendor identifier, else its reference name.
  public var displayName: String { vendorIdentifier ?? referenceName ?? id }
}

extension GameCenter.Achievement: GameCenterOrderedItem {
  public static let noun = "achievement"
  public static func list(owner: GameCenter.Owner, client: ASCClient) async throws -> [Self] {
    try await GameCenter.achievements(owner: owner, client: client)
  }
  public static func delete(id: String, client: ASCClient) async throws { try await GameCenter.deleteAchievement(id: id, client: client) }
  public static func createVersion(itemID: String, client: ASCClient) async throws -> GameCenter.Version {
    try await GameCenter.createAchievementVersion(achievementID: itemID, client: client)
  }
  public static func localizations(versionID: String, client: ASCClient) async throws -> [GameCenter.AchievementLocalization] {
    try await GameCenter.achievementLocalizations(versionID: versionID, client: client)
  }
  public static func saveLocalization(
    versionID: String, locale: String, existing: GameCenter.AchievementLocalization?, fields: AchievementLocaleFields, client: ASCClient
  ) async throws -> String {
    try await GameCenter.saveAchievementLocalization(versionID: versionID, locale: locale, existing: existing, fields: fields, client: client)
  }
  public static func deleteLocalization(id: String, client: ASCClient) async throws {
    try await GameCenter.deleteAchievementLocalization(id: id, client: client)
  }
  public static func uploadImage(localizationID: String, filePath: String, client: ASCClient) async throws -> String {
    try await GameCenter.uploadAchievementImage(localizationID: localizationID, filePath: filePath, client: client)
  }
  public static func deleteImage(id: String, client: ASCClient) async throws { try await GameCenter.deleteAchievementImage(id: id, client: client) }
  public static func reorder(owner: GameCenter.Owner, ids: [String], client: ASCClient) async throws {
    try await GameCenter.reorderAchievements(owner: owner, ids: ids, client: client)
  }
  public static func reviewItem(versionID: String) -> ReviewSubmissions.DraftItem { .gameCenterAchievementVersion(versionID) }
}

extension GameCenter.AchievementLocalization: GameCenterLocalization {
  public var fields: AchievementLocaleFields {
    .init(name: name, beforeEarnedDescription: beforeEarnedDescription, afterEarnedDescription: afterEarnedDescription)
  }
}

extension GameCenter.Leaderboard: GameCenterOrderedItem {
  public static let noun = "leaderboard"
  public static func list(owner: GameCenter.Owner, client: ASCClient) async throws -> [Self] {
    try await GameCenter.leaderboards(owner: owner, client: client)
  }
  public static func delete(id: String, client: ASCClient) async throws { try await GameCenter.deleteLeaderboard(id: id, client: client) }
  public static func createVersion(itemID: String, client: ASCClient) async throws -> GameCenter.Version {
    try await GameCenter.createLeaderboardVersion(leaderboardID: itemID, client: client)
  }
  public static func localizations(versionID: String, client: ASCClient) async throws -> [GameCenter.LeaderboardLocalization] {
    try await GameCenter.leaderboardLocalizations(versionID: versionID, client: client)
  }
  public static func saveLocalization(
    versionID: String, locale: String, existing: GameCenter.LeaderboardLocalization?, fields: LeaderboardLocaleFields, client: ASCClient
  ) async throws -> String {
    try await GameCenter.saveLeaderboardLocalization(versionID: versionID, locale: locale, existing: existing, fields: fields, client: client)
  }
  public static func deleteLocalization(id: String, client: ASCClient) async throws {
    try await GameCenter.deleteLeaderboardLocalization(id: id, client: client)
  }
  public static func uploadImage(localizationID: String, filePath: String, client: ASCClient) async throws -> String {
    try await GameCenter.uploadLeaderboardImage(localizationID: localizationID, filePath: filePath, client: client)
  }
  public static func deleteImage(id: String, client: ASCClient) async throws { try await GameCenter.deleteLeaderboardImage(id: id, client: client) }
  public static func reorder(owner: GameCenter.Owner, ids: [String], client: ASCClient) async throws {
    try await GameCenter.reorderLeaderboards(owner: owner, ids: ids, client: client)
  }
  public static func reviewItem(versionID: String) -> ReviewSubmissions.DraftItem { .gameCenterLeaderboardVersion(versionID) }
}

extension GameCenter.LeaderboardLocalization: GameCenterLocalization {
  public var fields: LeaderboardLocaleFields {
    .init(
      name: name, description: description, formatterOverride: formatterOverride, formatterSuffix: formatterSuffix,
      formatterSuffixSingular: formatterSuffixSingular)
  }
}

extension GameCenter.LeaderboardSet: GameCenterOrderedItem {
  public static let noun = "leaderboard set"
  public static func list(owner: GameCenter.Owner, client: ASCClient) async throws -> [Self] {
    try await GameCenter.leaderboardSets(owner: owner, client: client)
  }
  public static func delete(id: String, client: ASCClient) async throws { try await GameCenter.deleteLeaderboardSet(id: id, client: client) }
  public static func createVersion(itemID: String, client: ASCClient) async throws -> GameCenter.Version {
    try await GameCenter.createLeaderboardSetVersion(setID: itemID, client: client)
  }
  public static func localizations(versionID: String, client: ASCClient) async throws -> [GameCenter.LeaderboardSetLocalization] {
    try await GameCenter.leaderboardSetLocalizations(versionID: versionID, client: client)
  }
  public static func saveLocalization(
    versionID: String, locale: String, existing: GameCenter.LeaderboardSetLocalization?, fields: LeaderboardSetLocaleFields, client: ASCClient
  ) async throws -> String {
    try await GameCenter.saveLeaderboardSetLocalization(versionID: versionID, locale: locale, existing: existing, fields: fields, client: client)
  }
  public static func deleteLocalization(id: String, client: ASCClient) async throws {
    try await GameCenter.deleteLeaderboardSetLocalization(id: id, client: client)
  }
  public static func uploadImage(localizationID: String, filePath: String, client: ASCClient) async throws -> String {
    try await GameCenter.uploadLeaderboardSetImage(localizationID: localizationID, filePath: filePath, client: client)
  }
  public static func deleteImage(id: String, client: ASCClient) async throws { try await GameCenter.deleteLeaderboardSetImage(id: id, client: client) }
  public static func reorder(owner: GameCenter.Owner, ids: [String], client: ASCClient) async throws {
    try await GameCenter.reorderLeaderboardSets(owner: owner, ids: ids, client: client)
  }
  public static func reviewItem(versionID: String) -> ReviewSubmissions.DraftItem { .gameCenterLeaderboardSetVersion(versionID) }
}

extension GameCenter.LeaderboardSetLocalization: GameCenterLocalization {
  public var fields: LeaderboardSetLocaleFields { .init(name: name) }
}
