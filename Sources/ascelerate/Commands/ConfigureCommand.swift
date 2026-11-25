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
    let existing = try Self.existingConfig()
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
    let saved = existing?.vendorNumber
    let vendorPrompt = saved.map { "Vendor Number (press Enter to keep \($0), or type - to remove it): " }
      ?? "Vendor Number (press Enter to skip): "
    let vendorNumberInput = readAnswer(vendorPrompt, optional: true)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let vendorNumber = vendorNumberInput == "-" ? nil : vendorNumberInput.isEmpty ? saved : vendorNumberInput

    let fm = FileManager.default

    let expandedSource = expandPath(sourceKeyPath)

    guard fm.fileExists(atPath: expandedSource) else {
      throw ValidationError("File not found at '\(expandedSource)'.")
    }

    try Config.createDirectory()

    // Copy the .p8 file into the config directory, unless it's the copy already there (the path
    // the first run printed, a symlink to it, a relative path into the folder): removing the
    // destination first would remove the key itself, and Apple lets a key be downloaded once. The
    // copy goes to a temporary name and is renamed over the old one, so a failed copy leaves the
    // old key in place. copyItem preserves the source's permissions (a downloaded key is
    // typically 644), so tighten them.
    let keyFilename = URL(fileURLWithPath: expandedSource).lastPathComponent
    let destinationURL = Config.configDirectory.appendingPathComponent(keyFilename)
    let source = URL(fileURLWithPath: expandedSource).resolvingSymlinksInPath().standardizedFileURL
    if source != destinationURL.resolvingSymlinksInPath().standardizedFileURL {
      let staging = Config.configDirectory.appendingPathComponent(".\(keyFilename).\(UUID().uuidString)")
      try fm.copyItem(at: source, to: staging)
      try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
      try Self.rename(staging, over: destinationURL)
    }
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)

    let config = Config(
      keyId: keyId,
      issuerId: issuerId,
      privateKeyPath: destinationURL.path,
      vendorNumber: vendorNumber,
      ads: existing?.ads
    )
    try config.save()

    print()
    print("Private key copied to \(destinationURL.path)")
    print("Config saved to \(Config.configFile.path)")
    print("Permissions set to owner-only access.")
  }

  /// The saved configuration, to keep what this run doesn't ask for (the vendor number, Apple
  /// Ads); nil when there's none yet. A file that's there but can't be read is an error: saving
  /// over it would drop what it holds.
  static func existingConfig() throws -> Config? {
    guard FileManager.default.fileExists(atPath: Config.configFile.path) else { return nil }
    do {
      return try Config.load()
    } catch {
      throw ValidationError(
        "Couldn't read \(Config.configFile.path) (\(error.localizedDescription)). Fix or move it, then run configure again.")
    }
  }

  /// Puts `source` in place of `destination` in one step (POSIX rename), so the destination is
  /// never missing.
  static func rename(_ source: URL, over destination: URL) throws {
    guard Foundation.rename(source.path, destination.path) == 0 else {
      let reason = String(cString: strerror(errno))
      try? FileManager.default.removeItem(at: source)
      throw ValidationError("Couldn't save \(destination.path): \(reason).")
    }
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

    let existing = try Self.existingConfig()
    try Config.createDirectory()
    let keyURL = Config.configDirectory.appendingPathComponent("AuthKey_\(credentials.keyId).p8")
    let fm = FileManager.default
    // Created owner-only under a temporary name, so the key is never readable by others even for a
    // moment, and renamed over the old one, which stays until the new one is written.
    let staging = Config.configDirectory.appendingPathComponent(".AuthKey_\(credentials.keyId).p8.\(UUID().uuidString)")
    guard fm.createFile(atPath: staging.path, contents: Data(credentials.privateKey.utf8), attributes: [.posixPermissions: 0o600]) else {
      throw ValidationError("Couldn't write \(keyURL.path).")
    }
    try Self.rename(staging, over: keyURL)

    try Config(
      keyId: credentials.keyId, issuerId: credentials.issuerId, privateKeyPath: keyURL.path,
      vendorNumber: existing?.vendorNumber, ads: existing?.ads
    ).save()
    print("Configured key \(credentials.keyId).")
    print("Private key saved to \(keyURL.path)")
    print("Config saved to \(Config.configFile.path)")
  }
}
