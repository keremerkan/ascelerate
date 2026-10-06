import AppStoreConnect
import ASCKit
import Foundation

enum ClientFactory {
  /// The ASCKit client (generated from Apple's spec) that migrated commands use.
  static func makeASCClient() throws -> ASCClient {
    if !autoConfirm {
      checkForUpdates()
    }
    let config = try Config.load()
    let keyPath = expandPath(config.privateKeyPath)

    guard FileManager.default.fileExists(atPath: keyPath) else {
      throw ConfigError.missingPrivateKey(keyPath)
    }

    return try .appStoreConnect(credentials: ASCCredentials(
      keyID: config.keyId,
      issuerID: config.issuerId,
      privateKeyPEM: String(contentsOfFile: keyPath, encoding: .utf8)
    ))
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
