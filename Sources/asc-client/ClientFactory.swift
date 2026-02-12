import AppStoreConnect
import Foundation

enum ClientFactory {
  static func makeClient() throws -> AppStoreConnectClient {
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
