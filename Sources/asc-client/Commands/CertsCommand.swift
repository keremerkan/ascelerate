import AppStoreAPI
import AppStoreConnect
import ArgumentParser
import Crypto
import _CryptoExtras
import Foundation
import SwiftASN1
import X509

struct CertsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "certs",
    abstract: "Manage signing certificates.",
    subcommands: [List.self, Info.self, Create.self, Revoke.self]
  )

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List signing certificates."
    )

    @Option(name: .long, help: """
      Filter by certificate type. Valid values: \
      APPLE_PAY, APPLE_PAY_MERCHANT_IDENTITY, APPLE_PAY_PSP_IDENTITY, APPLE_PAY_RSA, \
      DEVELOPER_ID_APPLICATION, DEVELOPER_ID_APPLICATION_G2, DEVELOPER_ID_KEXT, DEVELOPER_ID_KEXT_G2, \
      DEVELOPMENT, DISTRIBUTION, IDENTITY_ACCESS, \
      MAC_INSTALLER_DISTRIBUTION, \
      PASS_TYPE_ID, PASS_TYPE_ID_WITH_NFC.
      """)
    var type: String?

    @Option(name: .long, help: "Filter by display name.")
    var displayName: String?

    func run() async throws {
      let client = try ClientFactory.makeClient()

      let filterType: [Resources.V1.Certificates.FilterCertificateType]? = try parseFilter(type, name: "type")

      var rows: [[String]] = []
      let request = Resources.v1.certificates.get(
        filterDisplayName: displayName.map { [$0] },
        filterCertificateType: filterType,
        limit: 200
      )

      for try await page in client.pages(request) {
        for cert in page.data {
          let attrs = cert.attributes
          rows.append([
            attrs?.displayName ?? "—",
            attrs?.certificateType.map { "\($0)" } ?? "—",
            attrs?.serialNumber ?? "—",
            attrs?.platform.map { "\($0)" } ?? "—",
            attrs?.expirationDate.map { formatDate($0) } ?? "—",
            attrs?.isActivated == true ? "Yes" : "No",
          ])
        }
      }

      if rows.isEmpty {
        print("No certificates found.")
      } else {
        Table.print(
          headers: ["Display Name", "Type", "Serial Number", "Platform", "Expires", "Active"],
          rows: rows
        )
      }
    }
  }

  struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Show details for a certificate."
    )

    @Argument(help: "Certificate serial number or display name.")
    var serialOrName: String?

    func run() async throws {
      let client = try ClientFactory.makeClient()

      let cert: AppStoreAPI.Certificate
      if let serialOrName {
        cert = try await findCertificate(serialOrName: serialOrName, client: client)
      } else {
        cert = try await promptCertificate(client: client)
      }

      let attrs = cert.attributes
      print("Display Name:  \(attrs?.displayName ?? "—")")
      print("Name:          \(attrs?.name ?? "—")")
      print("Type:          \(attrs?.certificateType.map { "\($0)" } ?? "—")")
      print("Serial Number: \(attrs?.serialNumber ?? "—")")
      print("Platform:      \(attrs?.platform.map { "\($0)" } ?? "—")")
      print("Expires:       \(attrs?.expirationDate.map { formatDate($0) } ?? "—")")
      print("Active:        \(attrs?.isActivated == true ? "Yes" : "No")")
    }
  }

  struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Create a signing certificate."
    )

    @Option(name: .long, help: "Path to a CSR file (PEM format). If omitted, a key pair and CSR are generated automatically.")
    var csr: String?

    @Option(name: .long, help: """
      Certificate type. Valid values: \
      DEVELOPER_ID_APPLICATION, DEVELOPER_ID_APPLICATION_G2, DEVELOPER_ID_KEXT, DEVELOPER_ID_KEXT_G2, \
      DEVELOPMENT, DISTRIBUTION, \
      MAC_INSTALLER_DISTRIBUTION, \
      PASS_TYPE_ID, PASS_TYPE_ID_WITH_NFC.
      """)
    var type: String?

    @Option(name: .long, help: "Base path for output files. Auto mode: <base>.pem + <base>.cer. Manual CSR: <base>.cer.")
    var output: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    // Certificate types that can be created via the API
    private static let creatableTypes: [CertificateType] = [
      .development, .distribution,
      .developerIDApplication, .developerIDApplicationG2,
      .developerIDKext, .developerIDKextG2,
      .macInstallerDistribution,
      .passTypeID, .passTypeIDWithNfc,
    ]

    private func promptCertType() throws -> CertificateType {
      return try promptSelection(
        "Certificate types",
        items: Self.creatableTypes,
        display: { $0.rawValue },
        prompt: "Select certificate type"
      )
    }

    func run() async throws {
      if yes { autoConfirm = true }

      if autoConfirm && type == nil {
        throw ValidationError("--type is required when using --yes.")
      }

      let client = try ClientFactory.makeClient()

      let certType: CertificateType
      if let type {
        guard let ct = CertificateType(rawValue: type.uppercased()) else {
          let valid = CertificateType.allCases.map(\.rawValue).joined(separator: ", ")
          throw ValidationError("Invalid type '\(type)'. Valid values: \(valid)")
        }
        certType = ct
      } else {
        certType = try promptCertType()
      }

      let csrContent: String
      let rsaKey: _RSA.Signing.PrivateKey?

      if let csrFile = csr {
        // Manual CSR mode
        let csrPath = expandPath(csrFile)
        guard FileManager.default.fileExists(atPath: csrPath) else {
          throw ValidationError("CSR file not found: \(csrPath)")
        }
        csrContent = try String(contentsOfFile: csrPath, encoding: .utf8)
        rsaKey = nil

        print("Create certificate:")
        print("  Type: \(certType)")
        print("  CSR:  \(csrPath)")
      } else {
        // Auto-generate RSA 2048 key pair + CSR
        let key = try _RSA.Signing.PrivateKey(keySize: .bits2048)
        let subject = try DistinguishedName { CommonName("asc-client") }
        let csrRequest = try CertificateSigningRequest(
          version: .v1,
          subject: subject,
          privateKey: .init(key),
          attributes: CertificateSigningRequest.Attributes(),
          signatureAlgorithm: .sha256WithRSAEncryption
        )
        csrContent = try csrRequest.serializeAsPEM().pemString
        rsaKey = key

        print("Create certificate:")
        print("  Type: \(certType)")
        print("  CSR:  (auto-generated)")
      }

      print()

      guard confirm("Create this certificate? [y/N] ") else {
        print("Cancelled.")
        return
      }

      let response = try await client.send(
        Resources.v1.certificates.post(
          CertificateCreateRequest(data: .init(
            attributes: .init(
              csrContent: csrContent,
              certificateType: certType
            )
          ))
        )
      )

      let attrs = response.data.attributes
      print()
      print("Created certificate.")
      print("  Display Name:  \(attrs?.displayName ?? "—")")
      print("  Serial Number: \(attrs?.serialNumber ?? "—")")
      print("  Expires:       \(attrs?.expirationDate.map { formatDate($0) } ?? "—")")

      // Determine output base name
      let baseName: String?
      if let output {
        baseName = output
      } else if rsaKey != nil {
        // Auto mode without --output: use serial number
        baseName = attrs?.serialNumber
      } else {
        baseName = nil
      }

      // Save certificate
      if let baseName, let content = attrs?.certificateContent {
        guard let certData = Data(base64Encoded: content) else {
          throw ValidationError("Could not decode certificate content from API response.")
        }

        let cerName = rsaKey != nil ? "\(baseName).cer" : baseName
        let cerPath = expandPath(confirmOutputPath(cerName, isDirectory: false))
        try certData.write(to: URL(fileURLWithPath: cerPath))
        print("  Certificate:   \(cerPath)")

        // Save private key (auto mode only)
        if let rsaKey {
          let pemPath = expandPath(confirmOutputPath("\(baseName).pem", isDirectory: false))
          try rsaKey.pemRepresentation.write(toFile: pemPath, atomically: true, encoding: .utf8)
          print("  Private key:   \(pemPath)")

          // Import into macOS Keychain (best-effort)
          let imported = importToKeychain(pemPath: pemPath, cerPath: cerPath)

          // Offer to clean up files if both were imported successfully
          if imported {
            let pemName = URL(fileURLWithPath: pemPath).lastPathComponent
            let cerName = URL(fileURLWithPath: cerPath).lastPathComponent
            print()
            print("The private key and certificate have been imported into your login keychain.")
            print("The local files (\(pemName), \(cerName)) are no longer needed unless you")
            print("want to keep a backup or import them on another machine.")
            print()
            if confirm("Delete the local files? [y/N] ") {
              try? FileManager.default.removeItem(atPath: pemPath)
              try? FileManager.default.removeItem(atPath: cerPath)
              print("Deleted.")
            }
          }
        }
      }
    }

    /// Imports the private key and certificate into the login keychain.
    /// Returns true if both imports succeeded.
    private func importToKeychain(pemPath: String, cerPath: String) -> Bool {
      let securityPath = "/usr/bin/security"
      guard FileManager.default.fileExists(atPath: securityPath) else {
        print()
        print("Import manually into your keychain or credential store:")
        print("  Private key: \(pemPath)")
        print("  Certificate: \(cerPath)")
        return false
      }

      let home = FileManager.default.homeDirectoryForCurrentUser.path
      let keychainPath = "\(home)/Library/Keychains/login.keychain-db"

      var allSucceeded = true
      print()
      for filePath in [pemPath, cerPath] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: securityPath)
        process.arguments = ["import", filePath, "-k", keychainPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
          try process.run()
          process.waitUntilExit()
          if process.terminationStatus == 0 {
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent
            print("Imported \(fileName) into login keychain.")
          } else {
            print("Warning: Could not import \(filePath) into keychain (exit \(process.terminationStatus)).")
            allSucceeded = false
          }
        } catch {
          print("Warning: Could not import \(filePath) into keychain: \(error.localizedDescription)")
          allSucceeded = false
        }
      }
      return allSucceeded
    }
  }

  struct Revoke: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Revoke a signing certificate."
    )

    @Argument(help: "Certificate serial number.")
    var serialNumber: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }

      if autoConfirm && serialNumber == nil {
        throw ValidationError("Serial number argument is required when using --yes.")
      }

      let client = try ClientFactory.makeClient()

      let cert: AppStoreAPI.Certificate
      if let serialNumber {
        let response = try await client.send(
          Resources.v1.certificates.get(filterSerialNumber: [serialNumber], limit: 1)
        )
        guard let found = response.data.first else {
          throw ValidationError("No certificate found with serial number '\(serialNumber)'.")
        }
        cert = found
      } else {
        cert = try await promptCertificate(client: client)
      }

      let attrs = cert.attributes
      print("Certificate:")
      print("  Display Name:  \(attrs?.displayName ?? "—")")
      print("  Type:          \(attrs?.certificateType.map { "\($0)" } ?? "—")")
      print("  Serial Number: \(attrs?.serialNumber ?? "—")")
      print()
      print("WARNING: Revoking a certificate cannot be undone.")
      print()

      guard confirm("Revoke this certificate? [y/N] ") else {
        print("Cancelled.")
        return
      }

      _ = try await client.send(Resources.v1.certificates.id(cert.id).delete)
      print()
      print("Revoked certificate '\(attrs?.displayName ?? serialNumber ?? "—")'.")
    }
  }
}

/// Prompts the user to select a certificate from a numbered list.
func promptCertificate(client: AppStoreConnectClient) async throws -> AppStoreAPI.Certificate {
  var allCerts: [AppStoreAPI.Certificate] = []
  for try await page in client.pages(Resources.v1.certificates.get(limit: 200)) {
    allCerts.append(contentsOf: page.data)
  }
  guard !allCerts.isEmpty else {
    throw ValidationError("No certificates found in your account.")
  }
  allCerts.sort { ($0.attributes?.displayName ?? "") < ($1.attributes?.displayName ?? "") }

  return try promptSelection(
    "Certificates",
    items: allCerts,
    display: { cert in
      let name = cert.attributes?.displayName ?? "—"
      let serial = cert.attributes?.serialNumber ?? "—"
      let type = cert.attributes?.certificateType.map { "\($0)" } ?? "—"
      let expires = cert.attributes?.expirationDate.map { formatDate($0) } ?? "—"
      return "\(name) (\(serial)) — \(type), expires \(expires)"
    },
    prompt: "Select certificate"
  )
}

/// Looks up a certificate by serial number first, then falls back to display name.
func findCertificate(serialOrName: String, client: AppStoreConnectClient) async throws -> AppStoreAPI.Certificate {
  // Try serial number first
  let bySerial = try await client.send(
    Resources.v1.certificates.get(filterSerialNumber: [serialOrName], limit: 1)
  )
  if let cert = bySerial.data.first {
    return cert
  }

  // Fall back to display name
  let byName = try await client.send(
    Resources.v1.certificates.get(filterDisplayName: [serialOrName], limit: 200)
  )
  if let cert = byName.data.first(where: { $0.attributes?.displayName == serialOrName }) {
    return cert
  }
  if byName.data.count == 1 {
    return byName.data[0]
  }

  throw CertLookupError.notFound(serialOrName)
}

enum CertLookupError: LocalizedError {
  case notFound(String)

  var errorDescription: String? {
    switch self {
    case .notFound(let identifier):
      return "No certificate found matching '\(identifier)'. Use serial number or exact display name."
    }
  }
}
