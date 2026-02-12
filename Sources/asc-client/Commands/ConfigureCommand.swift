import ArgumentParser
import Foundation

struct ConfigureCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "configure",
    abstract: "Set up API credentials."
  )

  func run() throws {
    print("====================================")
    print("App Store Connect API Configuration")
    print("====================================")
    print()
    print("You can find your API key at:")
    print("https://appstoreconnect.apple.com/access/integrations/api")
    print()

    let keyId = prompt("Key ID: ")
    let issuerId = prompt("Issuer ID: ")
    let sourceKeyPath = prompt("Private key (.p8) path: ")

    let fm = FileManager.default

    let expandedSource = expandPath(sourceKeyPath)

    guard fm.fileExists(atPath: expandedSource) else {
      throw ValidationError("File not found at '\(expandedSource)'.")
    }

    // Create config directory if needed
    if !fm.fileExists(atPath: Config.configDirectory.path) {
      try fm.createDirectory(at: Config.configDirectory, withIntermediateDirectories: true)
    }

    // Copy the .p8 file into ~/.asc-client/
    let keyFilename = URL(fileURLWithPath: expandedSource).lastPathComponent
    let destinationURL = Config.configDirectory.appendingPathComponent(keyFilename)

    if fm.fileExists(atPath: destinationURL.path) {
      try fm.removeItem(at: destinationURL)
    }
    try fm.copyItem(atPath: expandedSource, toPath: destinationURL.path)

    let config = Config(
      keyId: keyId,
      issuerId: issuerId,
      privateKeyPath: destinationURL.path
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(config)
    try data.write(to: Config.configFile)

    // Set strict permissions: owner-only read/write (700 for dir, 600 for files)
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Config.configDirectory.path)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Config.configFile.path)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)

    print()
    print("Private key copied to \(destinationURL.path)")
    print("Config saved to \(Config.configFile.path)")
    print("Permissions set to owner-only access.")
  }

  private func prompt(_ message: String) -> String {
    print(message, terminator: "")
    guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
          !line.isEmpty else {
      print("Value cannot be empty. Try again.")
      return prompt(message)
    }
    return line
  }
}
