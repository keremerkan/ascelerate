import Crypto
import Foundation
import SwiftASN1
import Testing
import X509
@testable import AscelerateCore

/// Reading a certificate file: names, the serial number as App Store Connect shows it, expiry.
@Suite struct CertificatesTests {
  @Test func summary() throws {
    let key = P256.Signing.PrivateKey()
    let name = try DistinguishedName {
      CommonName("Apple Development: Test (ABCDE12345)")
      OrganizationalUnitName("TEAM123456")
    }
    let expiry = Date(timeIntervalSince1970: 1_900_000_000)
    // A leading zero byte, which App Store Connect leaves out of the serial number it shows.
    let certificate = try Certificate(
      version: .v3, serialNumber: .init(bytes: [0x0A, 0xFB, 0xCD]), publicKey: .init(key.publicKey),
      notValidBefore: Date(timeIntervalSince1970: 1_800_000_000), notValidAfter: expiry,
      issuer: name, subject: name, signatureAlgorithm: .ecdsaWithSHA256, extensions: Certificate.Extensions(),
      issuerPrivateKey: .init(key))
    var serializer = DER.Serializer()
    try serializer.serialize(certificate)

    let summary = try Certificates.summary(of: Data(serializer.serializedBytes))
    #expect(summary.commonName == "Apple Development: Test (ABCDE12345)")
    #expect(summary.organizationalUnit == "TEAM123456")
    #expect(summary.serialNumber == "AFBCD")
    #expect(summary.expirationDate == expiry)
  }
}
