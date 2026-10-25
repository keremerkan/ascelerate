import ASCKit
import Foundation

/// An app's encryption declarations (`appEncryptionDeclarations`, App Store Connect's App
/// Encryption Documentation): list and create. Listed through the top-level endpoint filtered by
/// app, since `apps/{id}/appEncryptionDeclarations` answers 404 for some apps.
public enum EncryptionDeclarations {
  public struct Declaration: Hashable, Sendable, Identifiable {
    public let id: String
    public let appDescription: String?
    /// The raw state: CREATED, IN_REVIEW, APPROVED, REJECTED, INVALID, EXPIRED.
    public let state: String?
    /// The value of a build's `ITSEncryptionExportComplianceCode` that uses this declaration.
    public let codeValue: String?
    public let containsProprietaryCryptography: Bool?
    public let containsThirdPartyCryptography: Bool?
    public let availableOnFrenchStore: Bool?
    public let exempt: Bool?
    /// Raw platform; deprecated by Apple, and lowercase (`ios`) on some legacy declarations.
    public let platform: String?
    public let createdDate: Date?
  }

  public static func list(appID: String, client: ASCClient) async throws -> [Declaration] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.appEncryptionDeclarationsGetCollection(query: .init(filterApp: [appID])).ok.body.json
    }.flatMap(\.data).map(declaration)
  }

  /// Creates a declaration from App Store Connect's questions.
  public static func create(
    appID: String, appDescription: String, containsProprietaryCryptography: Bool,
    containsThirdPartyCryptography: Bool, availableOnFrenchStore: Bool, client: ASCClient
  ) async throws -> Declaration {
    declaration(try await client.appEncryptionDeclarationsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(
        appDescription: appDescription,
        availableOnFrenchStore: availableOnFrenchStore,
        containsProprietaryCryptography: containsProprietaryCryptography,
        containsThirdPartyCryptography: containsThirdPartyCryptography
      ),
      relationships: .init(app: .init(data: .init(id: appID, _type: "apps"))),
      _type: "appEncryptionDeclarations"
    )))).created.body.json.data)
  }

  private static func declaration(_ data: Components.Schemas.AppEncryptionDeclaration) -> Declaration {
    let a = data.attributes
    return Declaration(
      id: data.id, appDescription: a?.appDescription, state: a?.appEncryptionDeclarationState, codeValue: a?.codeValue,
      containsProprietaryCryptography: a?.containsProprietaryCryptography,
      containsThirdPartyCryptography: a?.containsThirdPartyCryptography,
      availableOnFrenchStore: a?.availableOnFrenchStore, exempt: a?.exempt, platform: a?.platform,
      createdDate: a?.createdDate)
  }
}
