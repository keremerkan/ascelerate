import ASCKit
import Foundation

/// The product page text of one locale of an App Store version, as `apps localizations`
/// exports and imports it. A nil field is left as it is.
public struct LocaleFields: Codable, Equatable, Sendable {
  public var description: String?
  public var whatsNew: String?
  public var keywords: String?
  public var promotionalText: String?
  public var marketingURL: String?
  public var supportURL: String?

  public init(
    description: String? = nil, whatsNew: String? = nil, keywords: String? = nil, promotionalText: String? = nil,
    marketingURL: String? = nil, supportURL: String? = nil
  ) {
    self.description = description
    self.whatsNew = whatsNew
    self.keywords = keywords
    self.promotionalText = promotionalText
    self.marketingURL = marketingURL
    self.supportURL = supportURL
  }
}

/// A URL option as the API's string, dropping values that don't parse as a URL.
public func validURL(_ value: String?) -> String? {
  value.flatMap { URL(string: $0)?.absoluteString }
}

/// Why a language (or a test's treatment) can't be removed, found before anything (its media
/// first) is deleted.
public enum LanguageDeleteError: LocalizedError, Equatable, Sendable {
  /// What is being removed.
  public enum Removing: String, Equatable, Sendable {
    case language, treatment
  }

  /// What it belongs to, as App Store Connect names it.
  public enum Owner: String, Equatable, Sendable {
    case appStoreVersion = "App Store version"
    case customProductPage = "custom product page"
    case inAppEvent = "in-app event"
    case productPageTest = "product page optimization test"
  }

  /// What holds it can't be edited in this state (a version in review, a test that's running).
  case notEditable(removing: Removing, owner: Owner, state: String)
  case primaryLanguage(String)
  case lastLanguage

  public var errorDescription: String? {
    switch self {
      case .notEditable(let removing, let owner, let state):
        "The \(removing.rawValue) can't be removed while the \(owner.rawValue) is \(formatState(state))."
      case .primaryLanguage(let locale): "\(locale) is the primary language; it can't be removed."
      case .lastLanguage: "It's the only language left; it can't be removed."
    }
  }
}

/// Updating and creating the localizations of an App Store version.
public enum VersionLocalizations {
  /// The version states in which every field can change: being prepared, in a draft submission
  /// (Ready for Review), submitted and not yet in review, or back from review: taken back
  /// (Developer Rejected; App Store Connect edits it in full, seen 2026-11-25) or rejected by App
  /// Review (Rejected, Metadata Rejected, Invalid Binary; taken to work the same way, not seen). In
  /// any other state only promotional text can be updated.
  public static let editableStates: Set<String> = [
    "PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "WAITING_FOR_REVIEW",
    "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY",
  ]

  /// Sends the non-nil fields of `fields` to an existing localization.
  public static func update(
    localizationID: String, fields: LocaleFields, client: ASCClient
  ) async throws -> Components.Schemas.AppStoreVersionLocalization {
    try await client.appStoreVersionLocalizationsUpdateInstance(
      path: .init(id: localizationID),
      body: .json(.init(data: .init(
        attributes: .init(
          description: fields.description,
          keywords: fields.keywords,
          marketingUrl: validURL(fields.marketingURL),
          promotionalText: fields.promotionalText,
          supportUrl: validURL(fields.supportURL),
          whatsNew: fields.whatsNew
        ),
        id: localizationID,
        _type: "appStoreVersionLocalizations"
      )))
    ).ok.body.json.data
  }

  /// Removes a locale from a version, with its screenshots and previews: the asset library
  /// placements go first, which deleting the locale would otherwise leave behind for good. Checked
  /// first, so the media aren't removed from a language that can't go: the version must be
  /// editable, and the language not the app's primary one nor the version's last.
  public static func delete(id: String, client: ASCClient) async throws {
    let localization = try await client.appStoreVersionLocalizationsGetInstance(
      path: .init(id: id), query: .init(include: [.appStoreVersion])
    ).ok.body.json.data
    if let versionID = localization.relationships?.appStoreVersion?.data?.id {
      let version = try await client.appStoreVersionsGetInstance(path: .init(id: versionID), query: .init(include: [.app])).ok.body.json.data
      let state = version.attributes?.appVersionState ?? ""
      guard editableStates.contains(state) else { throw LanguageDeleteError.notEditable(removing: .language, owner: .appStoreVersion, state: state) }
      if let appID = version.relationships?.app?.data?.id,
        let primary = try await client.appsGetInstance(path: .init(id: appID), query: .init(fieldsApps: [.primaryLocale]))
          .ok.body.json.data.attributes?.primaryLocale,
        primary == localization.attributes?.locale {
        throw LanguageDeleteError.primaryLanguage(primary)
      }
      let count = try await client.appStoreVersionsAppStoreVersionLocalizationsGetToManyRelated(
        path: .init(id: versionID), query: .init(limit: 200)
      ).ok.body.json.data.count
      guard count > 1 else { throw LanguageDeleteError.lastLanguage }
    }
    try await AssetLibrary.clearPlacements(on: .versionLocalization(id), client: client)
    _ = try await client.appStoreVersionLocalizationsDeleteInstance(path: .init(id: id)).noContent
  }

  /// Adds a locale to a version, with `fields` as its text.
  public static func create(
    versionID: String, locale: String, fields: LocaleFields, client: ASCClient
  ) async throws -> Components.Schemas.AppStoreVersionLocalization {
    try await client.appStoreVersionLocalizationsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(
        description: fields.description,
        keywords: fields.keywords,
        locale: locale,
        marketingUrl: validURL(fields.marketingURL),
        promotionalText: fields.promotionalText,
        supportUrl: validURL(fields.supportURL),
        whatsNew: fields.whatsNew
      ),
      relationships: .init(
        appStoreVersion: .init(data: .init(id: versionID, _type: "appStoreVersions"))),
      _type: "appStoreVersionLocalizations"
    )))).created.body.json.data
  }
}
