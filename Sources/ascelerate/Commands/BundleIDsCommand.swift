import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

struct BundleIDsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "bundle-ids",
    abstract: "Manage bundle identifiers.",
    subcommands: [List.self, Info.self, Register.self, Update.self, Delete.self, EnableCapability.self, DisableCapability.self]
  )

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List bundle identifiers."
    )

    @Option(name: .long, help: "Filter by platform (IOS, MAC_OS, UNIVERSAL).")
    var platform: String?

    @Option(name: .long, help: "Filter by identifier (prefix match).")
    var identifier: String?

    func run() async throws {
      let client = try ClientFactory.makeClient()

      let filterPlatform: ASCEnum.BundleIdPlatform? = try platform.map { try parseEnum($0, name: "platform") }
      let bundleIDs = try await BundleIDs.list(platform: filterPlatform?.rawValue, identifierPrefix: identifier, client: client)

      let rows = bundleIDs.map { bundleID in
        [
          bundleID.identifier.isEmpty ? "—" : bundleID.identifier,
          bundleID.name.isEmpty ? "—" : bundleID.name,
          bundleID.platform.map { formatState($0) } ?? "—",
          bundleID.seedID ?? "—",
        ]
      }

      if rows.isEmpty {
        print("No bundle identifiers found.")
      } else {
        Table.print(
          headers: ["Identifier", "Name", "Platform", "Seed ID"],
          rows: rows
        )
      }
    }
  }

  struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Show details for a bundle identifier."
    )

    @Argument(help: "The bundle identifier (e.g. com.example.MyApp).")
    var identifier: String?

    func run() async throws {
      let client = try ClientFactory.makeClient()

      let bundleID: BundleIDs.BundleID
      if let identifier {
        bundleID = try await BundleIDs.find(identifier: identifier, client: client)
      } else {
        bundleID = try await promptBundleID(client: client)
      }

      print("Identifier: \(bundleID.identifier.isEmpty ? "—" : bundleID.identifier)")
      print("Name:       \(bundleID.name.isEmpty ? "—" : bundleID.name)")
      print("Platform:   \(bundleID.platform.map { formatState($0) } ?? "—")")
      print("Seed ID:    \(bundleID.seedID ?? "—")")

      let capabilities = try await fetchCapabilities(bundleID: bundleID, client: client)
      if !capabilities.isEmpty {
        print()
        print("Capabilities:")
        for cap in capabilities {
          print("  \(cap.type.isEmpty ? "—" : formatState(cap.type))")
        }
      }
    }
  }

  struct Register: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Register a new bundle identifier."
    )

    @Option(name: .long, help: "Display name for the bundle ID.")
    var name: String?

    @Option(name: .long, help: "The bundle identifier (e.g. com.example.MyApp).")
    var identifier: String?

    @Option(name: .long, help: "Platform (IOS, MAC_OS, UNIVERSAL).")
    var platform: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }

      if autoConfirm {
        if name == nil { throw ValidationError("--name is required when using --yes.") }
        if identifier == nil { throw ValidationError("--identifier is required when using --yes.") }
        if platform == nil { throw ValidationError("--platform is required when using --yes.") }
      }

      let client = try ClientFactory.makeClient()

      let bundleIDName = try name ?? promptText("Display name: ")
      let bundleIDIdentifier = try identifier ?? promptText("Bundle identifier (e.g. com.example.MyApp): ")

      let platformValue: ASCEnum.BundleIdPlatform
      if let platform {
        platformValue = try parseEnum(platform, name: "platform")
      } else {
        platformValue = try promptPlatform()
      }

      print("Register bundle identifier:")
      print("  Identifier: \(bundleIDIdentifier)")
      print("  Name:       \(bundleIDName)")
      print("  Platform:   \(formatState(platformValue.rawValue))")
      print()

      guard confirm("Register this bundle identifier? [y/N] ") else {
        cancelled()
        return
      }

      let registered = try await BundleIDs.register(
        identifier: bundleIDIdentifier, name: bundleIDName, platform: platformValue.rawValue, client: client)

      print()
      success("Registered", "bundle identifier '\(registered.identifier.isEmpty ? bundleIDIdentifier : registered.identifier)'.")
      print("  Name:     \(registered.name.isEmpty ? bundleIDName : registered.name)")
      print("  Seed ID:  \(registered.seedID ?? "—")")
    }
  }

  struct Delete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Delete a bundle identifier."
    )

    @Argument(help: "The bundle identifier (e.g. com.example.MyApp).")
    var identifier: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }

      if autoConfirm && identifier == nil {
        throw ValidationError("Bundle identifier argument is required when using --yes.")
      }

      let client = try ClientFactory.makeClient()

      let bundleID: BundleIDs.BundleID
      if let identifier {
        bundleID = try await BundleIDs.find(identifier: identifier, client: client)
      } else {
        bundleID = try await promptBundleID(client: client)
      }

      print("Bundle identifier:")
      print("  Identifier: \(bundleID.identifier.isEmpty ? "—" : bundleID.identifier)")
      print("  Name:       \(bundleID.name.isEmpty ? "—" : bundleID.name)")
      print("  Platform:   \(bundleID.platform.map { formatState($0) } ?? "—")")
      print()
      print("WARNING: Deleting a bundle identifier cannot be undone.")
      print()

      guard confirm("Delete this bundle identifier? [y/N] ") else {
        cancelled()
        return
      }

      try await BundleIDs.delete(id: bundleID.id, client: client)
      print()
      success("Deleted", "bundle identifier '\(bundleID.identifier)'.")
    }
  }
  struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Update a bundle identifier's display name."
    )

    @Argument(help: "The bundle identifier (e.g. com.example.MyApp).")
    var identifier: String?

    @Option(name: .long, help: "New display name.")
    var name: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }

      if autoConfirm {
        if identifier == nil { throw ValidationError("Bundle identifier argument is required when using --yes.") }
        if name == nil { throw ValidationError("--name is required when using --yes.") }
      }

      let client = try ClientFactory.makeClient()

      let bundleID: BundleIDs.BundleID
      if let identifier {
        bundleID = try await BundleIDs.find(identifier: identifier, client: client)
      } else {
        bundleID = try await promptBundleID(client: client)
      }

      let currentName = bundleID.name.isEmpty ? "—" : bundleID.name
      let newName = try name ?? promptText("New display name [\(currentName)]: ")

      let bidIdentifier = bundleID.identifier
      print("Update bundle identifier:")
      print("  Identifier: \(bidIdentifier)")
      print("  Name:       \(currentName) → \(newName)")
      print()

      guard confirm("Update this bundle identifier? [y/N] ") else {
        cancelled()
        return
      }

      let updated = try await BundleIDs.rename(id: bundleID.id, to: newName, client: client)

      print()
      success("Updated", "bundle identifier '\(updated.identifier.isEmpty ? bidIdentifier : updated.identifier)'.")
      print("  Name: \(updated.name.isEmpty ? newName : updated.name)")
    }
  }

  struct EnableCapability: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "enable-capability",
      abstract: "Enable a capability on a bundle identifier."
    )

    @Argument(help: "The bundle identifier (e.g. com.example.MyApp).")
    var identifier: String?

    @Option(name: .long, help: """
      Capability type. Examples: \
      PUSH_NOTIFICATIONS, APP_GROUPS, APPLE_ID_AUTH, ICLOUD, \
      GAME_CENTER, IN_APP_PURCHASE, HEALTHKIT, ASSOCIATED_DOMAINS, etc.
      """)
    var type: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    private func promptCapabilityType(excluding enabled: Set<String>) throws -> ASCEnum.CapabilityType {
      let available = ASCEnum.CapabilityType.allCases.filter { !enabled.contains($0.rawValue) }
      guard !available.isEmpty else {
        throw ValidationError("All capabilities are already enabled on this bundle identifier.")
      }

      print()
      print("NOTE: Some capabilities (e.g. App Groups, iCloud, Associated Domains)")
      print("require additional configuration in the Apple Developer portal after enabling.")

      return try promptSelection(
        "Available capability types",
        items: available,
        display: { $0.rawValue },
        prompt: "Select capability type"
      )
    }

    func run() async throws {
      if yes { autoConfirm = true }

      if autoConfirm {
        if identifier == nil { throw ValidationError("Bundle identifier argument is required when using --yes.") }
        if type == nil { throw ValidationError("--type is required when using --yes.") }
      }

      let client = try ClientFactory.makeClient()

      let bundleID: BundleIDs.BundleID
      if let identifier {
        bundleID = try await BundleIDs.find(identifier: identifier, client: client)
      } else {
        bundleID = try await promptBundleID(client: client)
      }

      // Fetch current capabilities to check for duplicates
      let enabledTypes = Set(try await fetchCapabilities(bundleID: bundleID, client: client).map(\.type))

      let capabilityType: ASCEnum.CapabilityType
      if let type {
        let ct: ASCEnum.CapabilityType = try parseEnum(type, name: "capability type")
        if enabledTypes.contains(ct.rawValue) {
          print("\(ct.rawValue) is already enabled on this bundle identifier.")
          return
        }
        capabilityType = ct
      } else {
        capabilityType = try promptCapabilityType(excluding: enabledTypes)
      }

      let bidIdentifier = bundleID.identifier
      print("Enable capability:")
      print("  Bundle ID:  \(bidIdentifier)")
      print("  Capability: \(formatState(capabilityType.rawValue))")
      print()

      guard confirm("Enable this capability? [y/N] ") else {
        cancelled()
        return
      }

      let enabled = try await BundleIDs.enable(capabilityType.rawValue, bundleID: bundleID.id, client: client)

      print()
      success("Enabled", "\(formatState(enabled.type.isEmpty ? capabilityType.rawValue : enabled.type)) on '\(bidIdentifier)'.")

      if Self.requiresPortalConfiguration.contains(capabilityType) {
        print()
        print("NOTE: This capability requires additional configuration in the Apple Developer portal")
        print("(e.g. container IDs, domains, or entitlements) before it can be used.")
      }

      try await regenerateProfilesIfNeeded(bundleID: bundleID, client: client)
    }

    /// Capabilities that need extra configuration in the Apple Developer portal after enabling.
    private static let requiresPortalConfiguration: Set<ASCEnum.CapabilityType> = [
      .appGroups, .icloud, .associatedDomains, .applePay, .pushNotifications,
      .wallet, .personalVpn, .networkExtensions,
    ]
  }

  struct DisableCapability: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "disable-capability",
      abstract: "Disable a capability on a bundle identifier."
    )

    @Argument(help: "The bundle identifier (e.g. com.example.MyApp).")
    var identifier: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    private func promptCapability(
      bundleID: BundleIDs.BundleID, client: ASCClient
    ) async throws -> BundleIDs.Capability {
      let caps = try await fetchCapabilities(bundleID: bundleID, client: client)
      guard !caps.isEmpty else {
        throw ValidationError("No capabilities enabled on this bundle identifier.")
      }

      return try promptSelection(
        "Enabled capabilities",
        items: caps,
        display: { $0.type.isEmpty ? "—" : formatState($0.type) },
        prompt: "Select capability to disable"
      )
    }

    func run() async throws {
      if yes { autoConfirm = true }

      if autoConfirm && identifier == nil {
        throw ValidationError("Bundle identifier argument is required when using --yes.")
      }

      let client = try ClientFactory.makeClient()

      let bundleID: BundleIDs.BundleID
      if let identifier {
        bundleID = try await BundleIDs.find(identifier: identifier, client: client)
      } else {
        bundleID = try await promptBundleID(client: client)
      }

      let capability = try await promptCapability(bundleID: bundleID, client: client)
      let capType = capability.type.isEmpty ? "—" : formatState(capability.type)
      let bidIdentifier = bundleID.identifier

      print()
      print("Disable capability:")
      print("  Bundle ID:  \(bidIdentifier)")
      print("  Capability: \(capType)")
      print()

      guard confirm("Disable this capability? [y/N] ") else {
        cancelled()
        return
      }

      try await BundleIDs.disable(capabilityID: capability.id, client: client)
      print()
      success("Disabled", "\(capType) on '\(bidIdentifier)'.")

      try await regenerateProfilesIfNeeded(bundleID: bundleID, client: client)
    }
  }
}

/// The capabilities enabled on a bundle ID, sorted by display name (the API returns them in
/// no stable order). The endpoint rejects `limit` and returns them all.
private func fetchCapabilities(
  bundleID: BundleIDs.BundleID, client: ASCClient
) async throws -> [BundleIDs.Capability] {
  try await BundleIDs.capabilities(bundleID: bundleID.id, client: client)
    .sorted { formatState($0.type).localizedCaseInsensitiveCompare(formatState($1.type)) == .orderedAscending }
}

/// After a capability change, checks for provisioning profiles referencing this bundle ID
/// and offers to regenerate them (delete + recreate with the same settings).
private func regenerateProfilesIfNeeded(bundleID: BundleIDs.BundleID, client: ASCClient) async throws {
  let bidIdentifier = bundleID.identifier

  // Fetch all profiles that reference this bundle ID
  let matchingProfiles = try await Profiles.list(client: client)
    .filter { $0.bundleIDResourceID == bundleID.id }
    .sorted { $0.name < $1.name }

  guard !matchingProfiles.isEmpty else { return }

  let certsByFamily = try await Profiles.certificatesByFamily(client: client)

  print()
  print("Capability changes require provisioning profile regeneration.")
  print("Found \(matchingProfiles.count) profile(s) for \(bidIdentifier):")
  for profile in matchingProfiles {
    let name = profile.name.isEmpty ? "—" : profile.name
    let type = profile.type.map { formatState($0) } ?? "—"
    print("  \(name) (\(type))")
  }
  print()

  guard confirm("Regenerate \(matchingProfiles.count) profile(s)? This will delete and recreate each profile. [y/N] ") else {
    print("Skipped profile regeneration.")
    return
  }
  print()

  var succeeded = 0
  var failed = 0

  for profile in matchingProfiles {
    let neededFamily = Profiles.certificateFamily(forProfileType: profile.type ?? "")
    let certs = certsByFamily[neededFamily] ?? []
    guard !certs.isEmpty else {
      print("  SKIP \(profile.name.isEmpty ? "—" : profile.name) — no \(neededFamily.lowercased()) certificate found")
      failed += 1
      continue
    }

    if await reissueProfile(
      profile,
      bundleIDIdentifier: bidIdentifier,
      certs: certs,
      verb: "regenerated",
      client: client
    ) {
      succeeded += 1
    } else {
      failed += 1
    }
  }

  print()
  print("Done. \(succeeded) regenerated, \(failed) failed.")
}

/// Prompts the user to select a bundle identifier from a numbered list.
func promptBundleID(client: ASCClient) async throws -> BundleIDs.BundleID {
  let bundleIDs = try await BundleIDs.list(client: client)
  guard !bundleIDs.isEmpty else { throw ValidationError("No bundle identifiers found in your account.") }
  return try promptSelection(
    "Bundle identifiers", items: bundleIDs.sorted { $0.identifier < $1.identifier },
    display: { "\($0.identifier) (\($0.name), \($0.platform.map { formatState($0) } ?? "—"))" },
    prompt: "Select bundle identifier"
  )
}

/// Prompts the user to select a platform from a numbered list.
func promptPlatform<Platform: RawRepresentable & CaseIterable>() throws -> Platform where Platform.RawValue == String {
  return try promptSelection(
    "Platforms",
    items: Array(Platform.allCases),
    display: { $0.rawValue },
    prompt: "Select platform"
  )
}
