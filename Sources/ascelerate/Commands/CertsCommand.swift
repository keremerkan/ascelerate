import ArgumentParser
import ASCKit
import AscelerateCore
import Crypto
import _CryptoExtras
import Foundation
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

      let filterType: [ASCEnum.CertificateType]? = try parseFilter(type, name: "type")
      let certificates = try await Certificates.list(
        types: filterType?.map(\.rawValue), displayName: displayName, client: client)

      let rows = certificates.map { cert in
        [
          cert.displayName ?? "—",
          cert.type.map { formatState($0) } ?? "—",
          cert.serialNumber ?? "—",
          cert.platform.map { formatState($0) } ?? "—",
          cert.expirationDate.map { formatDate($0) } ?? "—",
          cert.activated == true ? "Yes" : "No",
        ]
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

      let cert: Certificates.Certificate
      if let serialOrName {
        cert = try await Certificates.find(serialOrName: serialOrName, client: client)
      } else {
        cert = try await promptCertificate(client: client)
      }

      print("Display Name:  \(cert.displayName ?? "—")")
      print("Name:          \(cert.name ?? "—")")
      print("Type:          \(cert.type.map { formatState($0) } ?? "—")")
      print("Serial Number: \(cert.serialNumber ?? "—")")
      print("Platform:      \(cert.platform.map { formatState($0) } ?? "—")")
      print("Expires:       \(cert.expirationDate.map { formatDate($0) } ?? "—")")
      print("Active:        \(cert.activated == true ? "Yes" : "No")")
    }
  }

  struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Create a signing certificate."
    )

    @Option(name: .long, help: "Path to a CSR file (PEM format). If omitted, a key pair and CSR are generated automatically.",
            completion: .file(extensions: ["pem"]))
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
    private static let creatableTypes: [ASCEnum.CertificateType] = [
      .development, .distribution,
      .developerIdApplication, .developerIdApplicationG2,
      .developerIdKext, .developerIdKextG2,
      .macInstallerDistribution,
      .passTypeId, .passTypeIdWithNfc,
    ]

    private func promptCertType() throws -> ASCEnum.CertificateType {
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

      let certType: ASCEnum.CertificateType
      if let type {
        certType = try parseEnum(type, name: "type")
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
        print("  Type: \(formatState(certType.rawValue))")
        print("  CSR:  \(csrPath)")
      } else {
        // Auto-generate RSA 2048 key pair + CSR
        let key = try _RSA.Signing.PrivateKey(keySize: .bits2048)
        csrContent = try Certificates.signingRequest(privateKey: .init(key))
        rsaKey = key

        print("Create certificate:")
        print("  Type: \(formatState(certType.rawValue))")
        print("  CSR:  (auto-generated)")
      }

      print()

      guard confirm("Create this certificate? [y/N] ") else {
        cancelled()
        return
      }

      let created = try await Certificates.create(type: certType.rawValue, csr: csrContent, client: client)

      print()
      success("Created", "certificate.")
      print("  Display Name:  \(created.displayName ?? "—")")
      print("  Serial Number: \(created.serialNumber ?? "—")")
      print("  Expires:       \(created.expirationDate.map { formatDate($0) } ?? "—")")

      // Determine output base name
      let baseName: String?
      if let output {
        baseName = output
      } else if rsaKey != nil {
        // Auto mode without --output: use serial number
        baseName = created.serialNumber
      } else {
        baseName = nil
      }

      // Save certificate
      if let baseName, let certData = created.content {
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
          print("Warning: Could not import \(filePath) into keychain: \(describeError(error))")
          allSucceeded = false
        }
      }
      return allSucceeded
    }
  }

  struct Revoke: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Revoke one or more signing certificates."
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

      let certs: [Certificates.Certificate]
      if let serialNumber {
        // Exact-match guard: revoking a partial-filter match would destroy the wrong cert
        guard let found = try await Certificates.find(serialNumber: serialNumber, client: client) else {
          throw ValidationError("No certificate found with serial number '\(serialNumber)'.")
        }
        certs = [found]
      } else {
        certs = try promptMultiSelection(
          "Certificates", items: try await allCertificates(client: client),
          display: certificateChoice, prompt: "Select certificate"
        )
      }

      print()
      print("Certificates to revoke (\(certs.count)):")
      print()
      Table.print(
        headers: ["Display Name", "Type", "Serial Number", "Expires"],
        rows: certs.map { c in
          [
            c.displayName ?? "—",
            c.type.map { formatState($0) } ?? "—",
            c.serialNumber ?? "—",
            c.expirationDate.map { formatDate($0) } ?? "—",
          ]
        }
      )
      print()
      print("WARNING: Revoking a certificate cannot be undone.")
      print()

      guard confirm("Revoke \(certs.count) certificate(s)? [y/N] ") else {
        cancelled()
        return
      }
      print()

      var succeeded = 0
      var failed = 0
      for cert in certs {
        let label = cert.displayName ?? cert.serialNumber ?? "—"
        do {
          try await Certificates.revoke(id: cert.id, client: client)
          print("  OK   \(label)")
          succeeded += 1
        } catch {
          print("  FAIL \(label) — \(describeError(error))")
          failed += 1
        }
      }

      print()
      print("Done. \(succeeded) revoked, \(failed) failed.")
    }
  }
}

/// Prompts the user to select a certificate from a numbered list.
func promptCertificate(client: ASCClient) async throws -> Certificates.Certificate {
  try promptSelection(
    "Certificates", items: try await allCertificates(client: client),
    display: certificateChoice, prompt: "Select certificate"
  )
}

/// The account's certificates by display name, for a picker.
private func allCertificates(client: ASCClient) async throws -> [Certificates.Certificate] {
  let certs = try await Certificates.list(client: client)
  guard !certs.isEmpty else { throw ValidationError("No certificates found in your account.") }
  return certs.sorted { ($0.displayName ?? "") < ($1.displayName ?? "") }
}

/// A certificate in a picker: name, serial number, type and expiry.
private func certificateChoice(_ cert: Certificates.Certificate) -> String {
  "\(cert.displayName ?? "—") (\(cert.serialNumber ?? "—")) — \(cert.type.map { formatState($0) } ?? "—"), expires \(cert.expirationDate.map { formatDate($0) } ?? "—")"
}
