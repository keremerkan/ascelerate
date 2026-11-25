import ArgumentParser
import Foundation

enum Aliases {
  static let aliasFile = Config.configDirectory.appendingPathComponent("aliases.json")

  /// The aliases; none when there's no file. A file that can't be read is an error, so a hand
  /// edit gone wrong is reported (and `alias add` doesn't save over it).
  static func load() throws -> [String: String] {
    guard FileManager.default.fileExists(atPath: aliasFile.path) else { return [:] }
    do {
      return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: aliasFile))
    } catch {
      throw ValidationError("Can't read \(aliasFile.path): \(error.localizedDescription) Fix or remove the file (it maps alias names to bundle IDs, as JSON).")
    }
  }

  static func save(_ aliases: [String: String]) throws {
    try Config.createDirectory()
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
func resolveAlias(_ input: String) throws -> String {
  guard !input.contains(".") else { return input }
  let aliases = try Aliases.load()
  return aliases[input] ?? input
}

/// Shell completion for an app argument: the alias names in `~/.ascelerate/aliases.json`.
let appAliasCompletion = CompletionKind.shellCommand(
  "grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'")
