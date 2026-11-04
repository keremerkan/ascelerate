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

  /// A declaration's documentation file: what App Store Connect asks for when an app's encryption
  /// needs export compliance paperwork (an ERN, a French declaration).
  public struct Document: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let fileName: String?
    public let fileSize: Int?
    /// `AWAITING_UPLOAD`, `UPLOAD_COMPLETE`, `COMPLETE` or `FAILED`.
    public let state: String?
    public let downloadURL: String?
  }

  /// A declaration's document, or nil when it has none.
  public static func document(declarationID: String, client: ASCClient) async throws -> Document? {
    guard let document = try await optionalRelated({
      try await client.appEncryptionDeclarationsAppEncryptionDeclarationDocumentGetToOneRelated(path: .init(id: declarationID)).ok.body.json.data
    }) else { return nil }
    let a = document.attributes
    return Document(
      id: document.id, fileName: a?.fileName, fileSize: a?.fileSize, state: a?.assetDeliveryState?.state,
      downloadURL: a?.downloadUrl)
  }

  /// Uploads a file as a declaration's document (reserve, upload, commit); returns its ID.
  public static func uploadDocument(declarationID: String, filePath: String, client: ASCClient) async throws -> String {
    let file = try MediaFile(path: filePath)
    return try await uploadAsset(filePath: filePath) {
      let reserved = try await client.appEncryptionDeclarationDocumentsCreateInstance(body: .json(.init(data: .init(
        attributes: .init(fileName: file.fileName, fileSize: file.fileSize),
        relationships: .init(appEncryptionDeclaration: .init(data: .init(id: declarationID, _type: "appEncryptionDeclarations"))),
        _type: "appEncryptionDeclarationDocuments")))).created.body.json.data
      return (reserved.id, reserved.attributes?.uploadOperations ?? [])
    } commit: { id, md5 in
      _ = try await client.appEncryptionDeclarationDocumentsUpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
        attributes: .init(sourceFileChecksum: md5, uploaded: true), id: id, _type: "appEncryptionDeclarationDocuments")))).ok
    }
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
