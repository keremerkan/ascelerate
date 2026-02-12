import Foundation

struct Config: Codable {
  let keyId: String
  let issuerId: String
  let privateKeyPath: String

  static let configDirectory = FileManager.default
    .homeDirectoryForCurrentUser
    .appendingPathComponent(".asc-client")

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
        Run 'asc-client configure' to set up your API credentials.
        """
    case .missingPrivateKey(let path):
      return "Private key file not found at \(path)"
    }
  }
}
