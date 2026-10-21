import ASCKit
import Foundation

/// An app's custom product pages: a page (name, URL, whether its link works), its versions (state,
/// deep link) and, per version, a localization per language with its promotional text. Media hang
/// off localizations like a version's (`AssetLibrary.Owner.productPageLocalization`).
public enum CustomProductPages {
  /// How many pages an app can have (App Store Connect: "Custom Product Pages (0 of 70)").
  public static let limit = 70

  public struct Page: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let url: String?
    /// Whether the page's link works (App Store Connect: Disable Link / Enable Link).
    public let visible: Bool
    public let versions: [Version]

    /// The version App Store Connect shows and edits: the one being prepared, else one not replaced.
    public var currentVersion: Version? {
      CustomProductPages.current(versions)
    }
  }

  public struct Version: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let version: String?
    /// `PREPARE_FOR_SUBMISSION`, `READY_FOR_REVIEW`, `WAITING_FOR_REVIEW`, `IN_REVIEW`, `ACCEPTED`,
    /// `APPROVED`, `REPLACED_WITH_NEW_VERSION`, `REJECTED`…
    public let state: String?
    public let deepLink: String?
  }

  public struct Localization: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let locale: String
    public let promotionalText: String?
  }

  /// What a new page copies its localizations and media from.
  public enum Template: Sendable {
    case appStoreVersion(String)
    case customProductPage(String)
  }

  public enum LookupError: LocalizedError {
    case notFound(String)
    case noVersions

    public var errorDescription: String? {
      switch self {
        case .notFound(let ref): "No custom product page '\(ref)' found for this app."
        case .noVersions: "This custom product page has no versions."
      }
    }
  }

  // MARK: Pages

  /// An app's pages with their versions.
  public static func list(appID: String, client: ASCClient) async throws -> [Page] {
    var pages: [Page] = []
    for response in try await ASCPaging.allPages(next: { $0.links.next }, {
      try await client.appsAppCustomProductPagesGetToManyRelated(
        path: .init(id: appID),
        query: .init(limit: 200, include: [.appCustomProductPageVersions], limitAppCustomProductPageVersions: 50)
      ).ok.body.json
    }) {
      var versions: [String: Version] = [:]
      for case .appCustomProductPageVersions(let version) in response.included ?? [] {
        versions[version.id] = self.version(version)
      }
      pages += response.data.map { page in
        self.page(page, versions: (page.relationships?.appCustomProductPageVersions?.data ?? []).compactMap { versions[$0.id] })
      }
    }
    return pages
  }

  /// An app's page by name or ID (without its versions).
  public static func find(_ ref: String, appID: String, client: ASCClient) async throws -> Page {
    let pages = try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.appsAppCustomProductPagesGetToManyRelated(path: .init(id: appID), query: .init(limit: 200)).ok.body.json
    }.flatMap(\.data)
    guard let match = pages.first(where: { $0.attributes?.name == ref || $0.id == ref }) else {
      throw LookupError.notFound(ref)
    }
    return page(match, versions: [])
  }

  public static func get(id: String, client: ASCClient) async throws -> Page {
    let page = try await client.appCustomProductPagesGetInstance(path: .init(id: id)).ok.body.json.data
    return self.page(page, versions: try await versions(pageID: id, client: client))
  }

  /// A new page with a first version in `locales` (at least one; `promotionalText` goes to each),
  /// optionally copied from a `template`: an App Store version's product page or another custom
  /// page with an approved version. The API requires the version and a localization even then,
  /// and creates only the localizations sent. A copy of a live version can outlast the request:
  /// Apple answered 500 and created the page anyway (seen live 2026-10-21), so after a server
  /// error a page by the new name is looked for and returned.
  @discardableResult
  public static func create(
    appID: String, name: String, locales: [String], promotionalText: String? = nil, template: Template? = nil,
    client: ASCClient
  ) async throws -> Page {
    // Compound create: the page references an inline version, which references inline
    // localizations. Local IDs (the API requires the `${local-id}` format) link them within the
    // single request.
    let versionLID = "${ascelerate-version}"
    let localizationLIDs = locales.indices.map { "${ascelerate-localization-\($0)}" }
    var relationships = Components.Schemas.AppCustomProductPageCreateRequest.DataPayload.RelationshipsPayload(
      app: .init(data: .init(id: appID, _type: "apps")),
      appCustomProductPageVersions: .init(data: [.init(id: versionLID, _type: "appCustomProductPageVersions")]))
    switch template {
      case .appStoreVersion(let id):
        relationships.appStoreVersionTemplate = .init(data: .init(id: id, _type: "appStoreVersions"))
      case .customProductPage(let id):
        relationships.customProductPageTemplate = .init(data: .init(id: id, _type: "appCustomProductPages"))
      case nil:
        break
    }
    let body = Components.Schemas.AppCustomProductPageCreateRequest(
      data: .init(attributes: .init(name: name), relationships: relationships, _type: "appCustomProductPages"),
      included: [
        .AppCustomProductPageVersionInlineCreate(.init(
          id: versionLID,
          relationships: .init(
            appCustomProductPageLocalizations: .init(
              data: localizationLIDs.map { .init(id: $0, _type: "appCustomProductPageLocalizations") })
          ),
          _type: "appCustomProductPageVersions"
        )),
      ] + zip(locales, localizationLIDs).map { locale, id in
        .AppCustomProductPageLocalizationInlineCreate(.init(
          attributes: .init(locale: locale, promotionalText: promotionalText), id: id,
          _type: "appCustomProductPageLocalizations"))
      }
    )
    let response: Components.Schemas.AppCustomProductPageResponse
    do {
      response = try await client.appCustomProductPagesCreateInstance(body: .json(body)).created.body.json
    } catch where (ASCError.from(error)?.statusCode ?? 0) >= 500 {
      guard let created = try await list(appID: appID, client: client).first(where: { $0.name == name }) else {
        throw error
      }
      return created
    }
    return page(response.data, versions: try await versions(pageID: response.data.id, client: client))
  }

  /// Renames a page or turns its link on or off; nil values are left as they are.
  public static func update(id: String, name: String? = nil, visible: Bool? = nil, client: ASCClient) async throws {
    _ = try await client.appCustomProductPagesUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(attributes: .init(name: name, visible: visible), id: id, _type: "appCustomProductPages")))
    ).ok
  }

  public static func delete(id: String, client: ASCClient) async throws {
    _ = try await client.appCustomProductPagesDeleteInstance(path: .init(id: id)).noContent
  }

  // MARK: Versions

  public static func versions(pageID: String, client: ASCClient) async throws -> [Version] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.appCustomProductPagesAppCustomProductPageVersionsGetToManyRelated(
        path: .init(id: pageID), query: .init(limit: 50)
      ).ok.body.json
    }.flatMap(\.data).map(version)
  }

  /// The version being prepared, else the first one not replaced, else the first.
  public static func current(_ versions: [Version]) -> Version? {
    versions.first { $0.state == "PREPARE_FOR_SUBMISSION" }
      ?? versions.first { $0.state != "REPLACED_WITH_NEW_VERSION" }
      ?? versions.first
  }

  /// The current version of a page (see `current(_:)`).
  public static func currentVersion(pageID: String, client: ASCClient) async throws -> Version {
    guard let version = current(try await versions(pageID: pageID, client: client)) else { throw LookupError.noVersions }
    return version
  }

  /// A new version of a page, to change one whose current version was approved.
  @discardableResult
  public static func createVersion(pageID: String, client: ASCClient) async throws -> Version {
    version(try await client.appCustomProductPageVersionsCreateInstance(body: .json(.init(data: .init(
      relationships: .init(appCustomProductPage: .init(data: .init(id: pageID, _type: "appCustomProductPages"))),
      _type: "appCustomProductPageVersions"
    )))).created.body.json.data)
  }

  /// Sets a version's deep link; nil removes it (sent as null).
  public static func updateVersion(id: String, deepLink: String?, client: ASCClient) async throws {
    try await ASCNulls.sending(deepLink == nil ? [["data", "attributes", "deepLink"]] : []) {
      _ = try await client.appCustomProductPageVersionsUpdateInstance(
        path: .init(id: id),
        body: .json(.init(data: .init(attributes: .init(deepLink: deepLink), id: id, _type: "appCustomProductPageVersions")))
      ).ok
    }
  }

  // MARK: Localizations

  public static func localizations(versionID: String, client: ASCClient) async throws -> [Localization] {
    try await client.appCustomProductPageVersionsAppCustomProductPageLocalizationsGetToManyRelated(
      path: .init(id: versionID), query: .init(limit: 50)
    ).ok.body.json.data.map(localization)
  }

  /// A page version's localization in a language.
  public static func localization(locale: String, versionID: String, client: ASCClient) async throws -> Localization? {
    try await localizations(versionID: versionID, client: client).first { $0.locale == locale }
  }

  @discardableResult
  public static func createLocalization(
    versionID: String, locale: String, promotionalText: String? = nil, client: ASCClient
  ) async throws -> Localization {
    localization(try await client.appCustomProductPageLocalizationsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(locale: locale, promotionalText: promotionalText),
      relationships: .init(
        appCustomProductPageVersion: .init(data: .init(id: versionID, _type: "appCustomProductPageVersions"))),
      _type: "appCustomProductPageLocalizations"
    )))).created.body.json.data)
  }

  /// Sets a localization's promotional text; nil removes it (sent as null).
  @discardableResult
  public static func updateLocalization(id: String, promotionalText: String?, client: ASCClient) async throws -> Localization {
    try await ASCNulls.sending(promotionalText == nil ? [["data", "attributes", "promotionalText"]] : []) {
      localization(try await client.appCustomProductPageLocalizationsUpdateInstance(
        path: .init(id: id),
        body: .json(.init(data: .init(
          attributes: .init(promotionalText: promotionalText), id: id, _type: "appCustomProductPageLocalizations")))
      ).ok.body.json.data)
    }
  }

  public static func deleteLocalization(id: String, client: ASCClient) async throws {
    _ = try await client.appCustomProductPageLocalizationsDeleteInstance(path: .init(id: id)).noContent
  }

  // MARK: Mapping

  private static func page(_ page: Components.Schemas.AppCustomProductPage, versions: [Version]) -> Page {
    Page(
      id: page.id, name: page.attributes?.name ?? "", url: page.attributes?.url.map { "\($0)" },
      visible: page.attributes?.visible ?? false, versions: versions)
  }

  private static func version(_ version: Components.Schemas.AppCustomProductPageVersion) -> Version {
    Version(
      id: version.id, version: version.attributes?.version, state: version.attributes?.state,
      deepLink: version.attributes?.deepLink.map { "\($0)" })
  }

  private static func localization(_ localization: Components.Schemas.AppCustomProductPageLocalization) -> Localization {
    Localization(
      id: localization.id, locale: localization.attributes?.locale ?? "",
      promotionalText: localization.attributes?.promotionalText)
  }
}
