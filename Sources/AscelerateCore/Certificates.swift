import ASCKit
import Foundation
#if canImport(Security)
import Security
#endif
import X509

/// Signing certificates (`certificates`): the team's development, distribution, Developer ID and
/// other certificates. Apple signs a certificate from a certificate signing request (CSR) made
/// with a private key that stays with whoever made it; the API never has the private key.
public enum Certificates {
  public struct Certificate: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// The certificate's common name ("Apple Development: Created via API (N4F99NADPY)").
    public let name: String?
    /// The person or team it's for ("AKE Software GmbH").
    public let displayName: String?
    /// `ASCEnum.CertificateType` raw value (`DEVELOPMENT`, `DISTRIBUTION`, ...).
    public let type: String?
    /// `IOS`, `MAC_OS` or nil (Apple Development and Apple Distribution are for every platform).
    public let platform: String?
    public let serialNumber: String?
    public let expirationDate: Date?
    public let activated: Bool?
    /// The certificate itself (DER).
    public let content: Data?
  }

  /// The types the API creates, in the order a picker shows them: the rest need a pass type or
  /// merchant ID, or are older types Apple replaced (iOS/Mac App Development and Distribution).
  public static let creatableTypes = [
    "DEVELOPMENT", "DISTRIBUTION", "MAC_INSTALLER_DISTRIBUTION", "DEVELOPER_ID_APPLICATION_G2",
    "DEVELOPER_ID_KEXT_G2",
  ]

  public enum LookupError: LocalizedError {
    case notFound(String)
    case unknownType(String)

    public var errorDescription: String? {
      switch self {
        case .notFound(let identifier):
          "No certificate found matching '\(identifier)'. Use serial number or exact display name."
        case .unknownType(let type): "Unknown certificate type '\(type)'."
      }
    }
  }

  /// The team's certificates, optionally of some types or with a display name.
  public static func list(types: [String]? = nil, displayName: String? = nil, client: ASCClient) async throws -> [Certificate] {
    typealias TypeFilter = Operations.CertificatesGetCollection.Input.Query.FilterCertificateTypePayloadPayload
    let typeFilter = try types?.map { raw in
      guard let type = TypeFilter(rawValue: raw) else { throw LookupError.unknownType(raw) }
      return type
    }
    return try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.certificatesGetCollection(query: .init(
          filterDisplayName: displayName.map { [$0] }, filterCertificateType: typeFilter, limit: 200
        )).ok.body.json
      }
    }.flatMap(\.data).map(Certificate.init)
  }

  /// A certificate by serial number, else by exact display name (or the only partial match):
  /// Apple's filters can match partially.
  public static func find(serialOrName: String, client: ASCClient) async throws -> Certificate {
    let bySerial = try await client.certificatesGetCollection(query: .init(filterSerialNumber: [serialOrName], limit: 200)).ok.body.json.data
    if let certificate = bySerial.first(where: { $0.attributes?.serialNumber == serialOrName }) {
      return Certificate(certificate)
    }
    let byName = try await client.certificatesGetCollection(query: .init(filterDisplayName: [serialOrName], limit: 200)).ok.body.json.data
    if let certificate = byName.first(where: { $0.attributes?.displayName == serialOrName }) {
      return Certificate(certificate)
    }
    if byName.count == 1 {
      return Certificate(byName[0])
    }
    throw LookupError.notFound(serialOrName)
  }

  /// A certificate with exactly this serial number, or nil.
  public static func find(serialNumber: String, client: ASCClient) async throws -> Certificate? {
    try await client.certificatesGetCollection(query: .init(filterSerialNumber: [serialNumber], limit: 200)).ok.body.json.data
      .first { $0.attributes?.serialNumber == serialNumber }
      .map(Certificate.init)
  }

  /// Asks Apple for a certificate of a type from a PEM certificate signing request.
  public static func create(type: String, csr: String, client: ASCClient) async throws -> Certificate {
    let response = try await client.certificatesCreateInstance(body: .json(.init(data: .init(
      attributes: .init(certificateType: type, csrContent: csr),
      _type: "certificates"
    )))).created.body.json
    return Certificate(response.data)
  }

  /// Revokes a certificate: anything signed with it keeps working, but nothing new can be signed,
  /// and profiles with it become invalid. It can't be undone.
  public static func revoke(id: String, client: ASCClient) async throws {
    _ = try await client.certificatesDeleteInstance(path: .init(id: id)).noContent
  }

  /// A PEM certificate signing request for a private key. Apple sets the certificate's names
  /// itself, so the common name only shows in the request.
  public static func signingRequest(privateKey: X509.Certificate.PrivateKey, commonName: String = "asc") throws -> String {
    let request = try CertificateSigningRequest(
      version: .v1,
      subject: try DistinguishedName { CommonName(commonName) },
      privateKey: privateKey,
      attributes: CertificateSigningRequest.Attributes(),
      signatureAlgorithm: .sha256WithRSAEncryption
    )
    return try request.serializeAsPEM().pemString
  }

  #if canImport(Security)
  /// A PEM certificate signing request for an RSA private key in the keychain.
  public static func signingRequest(key: SecKey, commonName: String = "asc") throws -> String {
    try signingRequest(privateKey: X509.Certificate.PrivateKey(key), commonName: commonName)
  }
  #endif
}

extension Certificates.Certificate {
  init(_ certificate: Components.Schemas.Certificate) {
    let attributes = certificate.attributes
    self.init(
      id: certificate.id, name: attributes?.name, displayName: attributes?.displayName,
      type: attributes?.certificateType, platform: attributes?.platform, serialNumber: attributes?.serialNumber,
      expirationDate: attributes?.expirationDate, activated: attributes?.activated,
      content: attributes?.certificateContent.flatMap { Data(base64Encoded: $0) })
  }
}
