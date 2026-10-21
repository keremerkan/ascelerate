import Foundation

struct Config: Codable {
  let keyId: String
  let issuerId: String
  let privateKeyPath: String
  /// Vendor number for Sales and Finance report downloads (App Store Connect →
  /// Payments and Financial Reports). Optional — only the `reports` commands need it.
  var vendorNumber: String?
  /// Apple Ads Platform API credentials. Optional — only the `ads` commands need them.
  var ads: AdsConfig?

  static let configDirectory = homeDirectory.appendingPathComponent(".ascelerate")

  static let configFile = configDirectory.appendingPathComponent("config.json")

  static func load() throws -> Config {
    guard FileManager.default.fileExists(atPath: configFile.path) else {
      throw ConfigError.missingConfigFile(configFile.path)
    }

    let data = try Data(contentsOf: configFile)
    let config = try JSONDecoder().decode(Config.self, from: data)
    return config
  }

  /// Creates the config directory owner-only from the start: keys must never be readable by
  /// other users, even transiently or after a mid-run failure.
  static func createDirectory() throws {
    let fm = FileManager.default
    if !fm.fileExists(atPath: configDirectory.path) {
      try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    } else {
      try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: configDirectory.path)
    }
  }

  func save() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(self).write(to: Config.configFile, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Config.configFile.path)
  }
}

/// Apple Ads API user credentials (Apple Ads → Account Settings → API) and the ad account to work in.
struct AdsConfig: Codable {
  var clientId: String
  var teamId: String
  var keyId: String
  var privateKeyPath: String
  var adAccountId: Int64?
}

enum ConfigError: LocalizedError {
  case missingConfigFile(String)
  case missingPrivateKey(String)

  var errorDescription: String? {
    switch self {
    case .missingConfigFile(let path):
      return """
        No configuration found at \(path).
        Run 'ascelerate configure' to set up your API credentials.
        """
    case .missingPrivateKey(let path):
      return "Private key file not found at \(path)"
    }
  }
}
