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
    config.tightenKeys()
    return config
  }

  /// Makes the keys in the config directory owner-only. `configure` does as it copies a key in, but
  /// a key put there by hand or by an early version kept its download's 644. Keys elsewhere are
  /// the user's own files and stay as they are.
  private func tightenKeys() {
    let fm = FileManager.default
    for path in [privateKeyPath, ads?.privateKeyPath].compactMap({ $0 }).map(expandPath) {
      guard path.hasPrefix(Config.configDirectory.path + "/"),
        let mode = (try? fm.attributesOfItem(atPath: path))?[.posixPermissions] as? Int, mode & 0o077 != 0
      else { continue }
      // Best effort: a key that stays readable still works, as before.
      try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
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

/// The App Store Connect key a run uses: the one in `ASCELERATE_KEY_ID`, `ASCELERATE_ISSUER_ID` and
/// `ASCELERATE_PRIVATE_KEY_PATH` when all three are set (a key for this run only, as in CI or for a
/// second team), else the configured one. The file stays as it is either way.
struct APICredentials {
  let keyID: String
  let issuerID: String
  let privateKeyPath: String
  /// Whether the key came from the environment.
  let isFromEnvironment: Bool

  static let environmentNames = ["ASCELERATE_KEY_ID", "ASCELERATE_ISSUER_ID", "ASCELERATE_PRIVATE_KEY_PATH"]

  /// The variables as the process started with them, read once (`removeFromEnvironment`).
  private static let environmentValues: [String?] = environmentNames.map { name in
    ProcessInfo.processInfo.environment[name].flatMap { $0.isEmpty ? nil : $0 }
  }

  /// Keeps the key's variables for this run, then removes them from the environment, so the tools
  /// the CLI starts don't inherit them: `builds archive` runs the project's build phases, package
  /// plugins and test runners, which have no business reading the key's location. Where a tool
  /// needs the key, the CLI passes it itself (`xcodebuildArguments`). Called first thing in `main`.
  static func removeFromEnvironment() {
    _ = environmentValues
    for name in environmentNames { unsetenv(name) }
  }

  static func current() throws -> APICredentials {
    if let key = try fromEnvironment() { return key }
    let config = try Config.load()
    return APICredentials(
      keyID: config.keyId, issuerID: config.issuerId, privateKeyPath: expandPath(config.privateKeyPath),
      isFromEnvironment: false)
  }

  /// The key in the environment; nil when none of its variables is set.
  static func fromEnvironment() throws -> APICredentials? {
    let values = environmentValues
    guard values.contains(where: { $0 != nil }) else { return nil }
    let missing = zip(environmentNames, values).filter { $0.1 == nil }.map(\.0)
    guard missing.isEmpty, let keyID = values[0], let issuerID = values[1], let path = values[2] else {
      throw ConfigError.incompleteEnvironment(missing)
    }
    return APICredentials(keyID: keyID, issuerID: issuerID, privateKeyPath: expandPath(path), isFromEnvironment: true)
  }

  /// The private key's PEM text.
  func privateKey() throws -> String {
    guard FileManager.default.fileExists(atPath: privateKeyPath) else {
      throw ConfigError.missingPrivateKey(privateKeyPath)
    }
    return try String(contentsOfFile: privateKeyPath, encoding: .utf8)
  }

  /// `xcodebuild`'s arguments for provisioning with this key rather than the Apple ID accounts in
  /// Xcode's settings. Archiving and exporting pass the environment's key (the team's key the run
  /// is for); the configured key is left out, to keep provisioning as it always was.
  var xcodebuildArguments: [String] {
    [
      "-authenticationKeyPath", privateKeyPath, "-authenticationKeyID", keyID, "-authenticationKeyIssuerID", issuerID,
    ]
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
  case incompleteEnvironment([String])

  var errorDescription: String? {
    switch self {
    case .missingConfigFile(let path):
      return """
        No configuration found at \(path).
        Run 'ascelerate configure' to set up your API credentials.
        """
    case .missingPrivateKey(let path):
      return "Private key file not found at \(path)"
    case .incompleteEnvironment(let missing):
      return "A key in the environment needs all of \(APICredentials.environmentNames.joined(separator: ", ")); \(missing.joined(separator: ", ")) \(missing.count == 1 ? "is" : "are") missing."
    }
  }
}
