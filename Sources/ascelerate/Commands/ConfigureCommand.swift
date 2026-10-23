import ArgumentParser
import Foundation

struct ConfigureCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "configure",
    abstract: "Set up API credentials."
  )

  @Flag(name: .long, help: ArgumentHelp(
    "Read the credentials as JSON from standard input instead of asking.",
    discussion: #"{"keyId": "…", "issuerId": "…", "privateKey": "-----BEGIN PRIVATE KEY-----…"}. The key is saved in ~/.ascelerate; the vendor number and Apple Ads settings are kept."#))
  var stdin = false

  @Flag(name: .long, help: "Print the key ID and issuer ID in use.")
  var show = false

  /// The credentials `--stdin` reads.
  private struct Credentials: Decodable {
    let keyId: String
    let issuerId: String
    let privateKey: String
  }

  func run() throws {
    if show {
      let key = try APICredentials.current()
      print("Key ID:    \(key.keyID)")
      print("Issuer ID: \(key.issuerID)")
      if key.isFromEnvironment {
        print("Source:    environment (ASCELERATE_KEY_ID, ASCELERATE_ISSUER_ID, ASCELERATE_PRIVATE_KEY_PATH)")
      }
      return
    }
    if stdin {
      try configureFromInput()
      return
    }
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

    try Config.createDirectory()

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
      vendorNumber: vendorNumber,
      ads: try? Config.load().ads
    )
    try config.save()

    print()
    print("Private key copied to \(destinationURL.path)")
    print("Config saved to \(Config.configFile.path)")
    print("Permissions set to owner-only access.")
  }

  /// Saves credentials read from standard input, keeping the rest of the configuration.
  private func configureFromInput() throws {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let credentials: Credentials
    do {
      credentials = try JSONDecoder().decode(Credentials.self, from: input)
    } catch {
      throw ValidationError("Standard input isn't the expected JSON (keyId, issuerId, privateKey).")
    }
    // The key ID names the key file, so it can't hold a path.
    guard !credentials.keyId.isEmpty, credentials.keyId.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
      throw ValidationError("'\(credentials.keyId)' isn't a key ID.")
    }
    guard credentials.privateKey.contains("-----BEGIN PRIVATE KEY-----") else {
      throw ValidationError("The private key isn't a .p8 key in PEM format.")
    }

    try Config.createDirectory()
    let keyURL = Config.configDirectory.appendingPathComponent("AuthKey_\(credentials.keyId).p8")
    let fm = FileManager.default
    if fm.fileExists(atPath: keyURL.path) {
      try fm.removeItem(at: keyURL)
    }
    // Created owner-only, so the key is never readable by others, even for a moment.
    guard fm.createFile(atPath: keyURL.path, contents: Data(credentials.privateKey.utf8), attributes: [.posixPermissions: 0o600]) else {
      throw ValidationError("Couldn't write \(keyURL.path).")
    }

    let existing = try? Config.load()
    try Config(
      keyId: credentials.keyId, issuerId: credentials.issuerId, privateKeyPath: keyURL.path,
      vendorNumber: existing?.vendorNumber, ads: existing?.ads
    ).save()
    print("Configured key \(credentials.keyId).")
    print("Private key saved to \(keyURL.path)")
    print("Config saved to \(Config.configFile.path)")
  }
}
