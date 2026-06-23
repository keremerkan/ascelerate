import Foundation

struct Config: Codable {
  let keyId: String
  let issuerId: String
  let privateKeyPath: String
  /// Vendor number for Sales and Finance report downloads (App Store Connect →
  /// Payments and Financial Reports). Optional — only the `reports` commands need it.
  var vendorNumber: String?

  static let configDirectory = FileManager.default
    .homeDirectoryForCurrentUser
    .appendingPathComponent(".ascelerate")

  static let configFile = configDirectory.appendingPathComponent("config.json")

  static func load() throws -> Config {
    guard FileManager.default.fileExists(atPath: configFile.path) else {
      throw ConfigError.missingConfigFile(configFile.path)
    }

    let data = try Data(contentsOf: configFile)
    let config = try JSONDecoder().decode(Config.self, from: data)
    return config
  }
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
