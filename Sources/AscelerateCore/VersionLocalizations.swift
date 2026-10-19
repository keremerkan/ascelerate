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

/// Updating and creating the localizations of an App Store version.
public enum VersionLocalizations {
  /// The version states in which every field can change. In any other state only promotional text
  /// can be updated.
  public static let editableStates: Set<String> = ["PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW"]

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
