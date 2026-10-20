import ASCKit
import Foundation

/// An app's custom license agreement (`endUserLicenseAgreements`): its text and the territories it
/// applies to. Apple's standard agreement applies everywhere else, and everywhere when the app has
/// none.
public enum LicenseAgreements {
  /// The app's custom license agreement; nil when Apple's standard one applies.
  public static func agreement(
    appID: String, client: ASCClient
  ) async throws -> Components.Schemas.EndUserLicenseAgreement? {
    try await optionalRelated {
      try await client.appsEndUserLicenseAgreementGetToOneRelated(path: .init(id: appID)).ok.body.json.data
    }
  }

  /// The territory codes a custom license agreement applies to.
  public static func territoryIDs(agreementID: String, client: ASCClient) async throws -> [String] {
    try await client.endUserLicenseAgreementsTerritoriesGetToManyRelated(
      path: .init(id: agreementID), query: .init(limit: 200)
    ).ok.body.json.data.map(\.id)
  }

  /// Every App Store territory's code.
  public static func allTerritoryIDs(client: ASCClient) async throws -> [String] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.territoriesGetCollection(query: .init(limit: 200)).ok.body.json
    }.flatMap { $0.data.map(\.id) }
  }

  /// Gives the app a custom license agreement in the territories (at least one; the text can't be
  /// empty either).
  @discardableResult
  public static func create(
    appID: String, text: String, territoryIDs: [String], client: ASCClient
  ) async throws -> Components.Schemas.EndUserLicenseAgreement {
    try await client.endUserLicenseAgreementsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(agreementText: text),
      relationships: .init(
        app: .init(data: .init(id: appID, _type: "apps")),
        territories: .init(data: territoryIDs.map { .init(id: $0, _type: "territories") })),
      _type: "endUserLicenseAgreements"
    )))).created.body.json.data
  }

  /// Changes a custom license agreement; a nil text or territory list is left as it is. The
  /// territories replace the current ones.
  @discardableResult
  public static func update(
    id: String, text: String? = nil, territoryIDs: [String]? = nil, client: ASCClient
  ) async throws -> Components.Schemas.EndUserLicenseAgreement {
    try await client.endUserLicenseAgreementsUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(
        attributes: .init(agreementText: text), id: id,
        relationships: territoryIDs.map { .init(territories: .init(data: $0.map { .init(id: $0, _type: "territories") })) },
        _type: "endUserLicenseAgreements")))
    ).ok.body.json.data
  }

  /// Removes a custom license agreement, so Apple's standard one applies everywhere.
  public static func delete(id: String, client: ASCClient) async throws {
    _ = try await client.endUserLicenseAgreementsDeleteInstance(path: .init(id: id)).noContent
  }
}
