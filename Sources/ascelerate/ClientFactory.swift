import AppStoreConnect
import ASCKit
import Foundation

enum ClientFactory {
  /// The ASCKit client (generated from Apple's spec) that migrated commands use.
  /// `checkUpdates: false` for commands that also create an asc-swift client, which already checks.
  static func makeASCClient(checkUpdates: Bool = true) throws -> ASCClient {
    if checkUpdates && !autoConfirm {
      checkForUpdates()
    }
    let config = try Config.load()
    let keyPath = expandPath(config.privateKeyPath)

    guard FileManager.default.fileExists(atPath: keyPath) else {
      throw ConfigError.missingPrivateKey(keyPath)
    }

    // ASCELERATE_DRY_RUN=1: reads go out, every write is printed instead of sent (testing aid).
    return try .appStoreConnect(
      credentials: ASCCredentials(
        keyID: config.keyId,
        issuerID: config.issuerId,
        privateKeyPEM: String(contentsOfFile: keyPath, encoding: .utf8)
      ),
      dryRun: ProcessInfo.processInfo.environment["ASCELERATE_DRY_RUN"] == "1"
    )
  }

  static func makeClient() throws -> AppStoreConnectClient {
    if !autoConfirm {
      checkForUpdates()
    }
    let config = try Config.load()
    let keyPath = expandPath(config.privateKeyPath)

    guard FileManager.default.fileExists(atPath: keyPath) else {
      throw ConfigError.missingPrivateKey(keyPath)
    }

    let privateKey = try JWT.PrivateKey(contentsOf: URL(fileURLWithPath: keyPath))

    return AppStoreConnectClient(
      authenticator: JWT(
        keyID: config.keyId,
        issuerID: config.issuerId,
        expiryDuration: 20 * 60,
        privateKey: privateKey
      )
    )
  }
}
