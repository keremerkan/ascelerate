import Foundation

enum Aliases {
  static let aliasFile = Config.configDirectory.appendingPathComponent("aliases.json")

  static func load() -> [String: String] {
    guard FileManager.default.fileExists(atPath: aliasFile.path),
      let data = try? Data(contentsOf: aliasFile),
      let aliases = try? JSONDecoder().decode([String: String].self, from: data)
    else {
      return [:]
    }
    return aliases
  }

  static func save(_ aliases: [String: String]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(aliases)
    try data.write(to: aliasFile, options: .atomic)

    // Set file permissions to owner-only (0600)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: aliasFile.path)
  }

  static func isValidAliasName(_ name: String) -> Bool {
    let pattern = #"^[a-zA-Z0-9_-]+$"#
    return name.range(of: pattern, options: .regularExpression) != nil
  }
}

/// If the input contains no dots, look it up in aliases.
/// Returns the resolved bundle ID or the original input unchanged.
func resolveAlias(_ input: String) -> String {
  guard !input.contains(".") else { return input }
  let aliases = Aliases.load()
  return aliases[input] ?? input
}
