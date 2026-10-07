import ASCKit
import Foundation

enum ClientFactory {
  /// An App Store Connect client (ASCKit, generated from Apple's spec).
  static func makeClient() throws -> ASCClient {
    if !autoConfirm {
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
}
