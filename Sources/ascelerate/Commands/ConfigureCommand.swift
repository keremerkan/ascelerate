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

    let keyId = try promptText("Key ID: ")
    let issuerId = try promptText("Issuer ID: ")
    let sourceKeyPath = try promptText("Private key (.p8) path: ")

    print()
    print("Vendor Number — optional, only needed for 'ascelerate reports sales' and 'reports finance'.")
    print("Find it in App Store Connect → Payments and Financial Reports (e.g. 80012345).")
    print("Vendor Number (press Enter to skip): ", terminator: "")
    let vendorNumberInput = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let vendorNumber = vendorNumberInput.isEmpty ? nil : vendorNumberInput

    let fm = FileManager.default

    let expandedSource = expandPath(sourceKeyPath)

    guard fm.fileExists(atPath: expandedSource) else {
      throw ValidationError("File not found at '\(expandedSource)'.")
    }

    // Create the config directory owner-only from the start — the key must never
    // be readable by other users, even transiently or after a mid-run failure.
    if !fm.fileExists(atPath: Config.configDirectory.path) {
      try fm.createDirectory(
        at: Config.configDirectory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
    } else {
      try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Config.configDirectory.path)
    }

    // Copy the .p8 file into the config directory. copyItem preserves the source
    // file's permissions (a downloaded key is typically 644), so tighten immediately.
    let keyFilename = URL(fileURLWithPath: expandedSource).lastPathComponent
    let destinationURL = Config.configDirectory.appendingPathComponent(keyFilename)

    if fm.fileExists(atPath: destinationURL.path) {
      try fm.removeItem(at: destinationURL)
    }
    try fm.copyItem(atPath: expandedSource, toPath: destinationURL.path)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)

    let config = Config(
      keyId: keyId,
      issuerId: issuerId,
      privateKeyPath: destinationURL.path,
      vendorNumber: vendorNumber
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(config)
    try data.write(to: Config.configFile, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Config.configFile.path)

    print()
    print("Private key copied to \(destinationURL.path)")
    print("Config saved to \(Config.configFile.path)")
    print("Permissions set to owner-only access.")
  }
}
