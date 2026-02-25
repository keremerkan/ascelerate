import AppStoreAPI
import AppStoreConnect
import ArgumentParser
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

      let filterPlatform: [Resources.V1.BundleIDs.FilterPlatform]?
      if let platform {
        guard let val = Resources.V1.BundleIDs.FilterPlatform(rawValue: platform.uppercased()) else {
          let valid = Resources.V1.BundleIDs.FilterPlatform.allCases.map(\.rawValue).joined(separator: ", ")
          throw ValidationError("Invalid platform '\(platform)'. Valid values: \(valid)")
        }
        filterPlatform = [val]
      } else {
        filterPlatform = nil
      }

      var rows: [[String]] = []
      let request = Resources.v1.bundleIDs.get(
        filterPlatform: filterPlatform,
        filterIdentifier: identifier.map { [$0] },
        limit: 200
      )

      for try await page in client.pages(request) {
        for bundleID in page.data {
          let attrs = bundleID.attributes
          rows.append([
            attrs?.identifier ?? "—",
            attrs?.name ?? "—",
            attrs?.platform.map { "\($0)" } ?? "—",
            attrs?.seedID ?? "—",
          ])
        }
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

      let bundleID: BundleID
      if let identifier {
        bundleID = try await findBundleID(identifier: identifier, client: client)
      } else {
        bundleID = try await promptBundleID(client: client)
      }

      let attrs = bundleID.attributes
      print("Identifier: \(attrs?.identifier ?? "—")")
      print("Name:       \(attrs?.name ?? "—")")
      print("Platform:   \(attrs?.platform.map { "\($0)" } ?? "—")")
      print("Seed ID:    \(attrs?.seedID ?? "—")")

      // Fetch capabilities
      let capsResponse = try await client.send(
        Resources.v1.bundleIDs.id(bundleID.id).bundleIDCapabilities.get()
      )

      if !capsResponse.data.isEmpty {
        print()
        print("Capabilities:")
        for cap in capsResponse.data {
          let capType = cap.attributes?.capabilityType.map { "\($0)" } ?? "—"
          print("  \(capType)")
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

      let bundleIDName = name ?? promptText("Display name: ")
      let bundleIDIdentifier = identifier ?? promptText("Bundle identifier (e.g. com.example.MyApp): ")

      let platformValue: BundleIDPlatform
      if let platform {
        guard let pv = BundleIDPlatform(rawValue: platform.uppercased()) else {
          let valid = BundleIDPlatform.allCases.map(\.rawValue).joined(separator: ", ")
          throw ValidationError("Invalid platform '\(platform)'. Valid values: \(valid)")
        }
        platformValue = pv
      } else {
        platformValue = try promptPlatform()
      }

      print("Register bundle identifier:")
      print("  Identifier: \(bundleIDIdentifier)")
      print("  Name:       \(bundleIDName)")
      print("  Platform:   \(platformValue)")
      print()

      guard confirm("Register this bundle identifier? [y/N] ") else {
        print("Cancelled.")
        return
      }

      let response = try await client.send(
        Resources.v1.bundleIDs.post(
          BundleIDCreateRequest(data: .init(
            attributes: .init(
              name: bundleIDName,
              platform: platformValue,
              identifier: bundleIDIdentifier
            )
          ))
        )
      )

      let attrs = response.data.attributes
      print()
      print("Registered bundle identifier '\(attrs?.identifier ?? bundleIDIdentifier)'.")
      print("  Name:     \(attrs?.name ?? bundleIDName)")
      print("  Seed ID:  \(attrs?.seedID ?? "—")")
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

      let bundleID: BundleID
      if let identifier {
        bundleID = try await findBundleID(identifier: identifier, client: client)
      } else {
        bundleID = try await promptBundleID(client: client)
      }

      let attrs = bundleID.attributes
      print("Bundle identifier:")
      print("  Identifier: \(attrs?.identifier ?? "—")")
      print("  Name:       \(attrs?.name ?? "—")")
      print("  Platform:   \(attrs?.platform.map { "\($0)" } ?? "—")")
      print()
      print("WARNING: Deleting a bundle identifier cannot be undone.")
      print()

      guard confirm("Delete this bundle identifier? [y/N] ") else {
        print("Cancelled.")
        return
      }

      _ = try await client.send(Resources.v1.bundleIDs.id(bundleID.id).delete)
      print()
      print("Deleted bundle identifier '\(attrs?.identifier ?? identifier ?? "—")'.")
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

      let bundleID: BundleID
      if let identifier {
        bundleID = try await findBundleID(identifier: identifier, client: client)
      } else {
        bundleID = try await promptBundleID(client: client)
      }

      let currentName = bundleID.attributes?.name ?? "—"
      let newName = name ?? promptText("New display name [\(currentName)]: ")

      let bidIdentifier = bundleID.attributes?.identifier ?? identifier ?? bundleID.id
      print("Update bundle identifier:")
      print("  Identifier: \(bidIdentifier)")
      print("  Name:       \(currentName) → \(newName)")
      print()

      guard confirm("Update this bundle identifier? [y/N] ") else {
        print("Cancelled.")
        return
      }

      let response = try await client.send(
        Resources.v1.bundleIDs.id(bundleID.id).patch(
          BundleIDUpdateRequest(data: .init(
            id: bundleID.id,
            attributes: .init(name: newName)
          ))
        )
      )

      let attrs = response.data.attributes
      print()
      print("Updated bundle identifier '\(attrs?.identifier ?? bidIdentifier)'.")
      print("  Name: \(attrs?.name ?? newName)")
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

    private func promptCapabilityType(excluding enabled: Set<String>) throws -> CapabilityType {
      let available = CapabilityType.allCases.filter { !enabled.contains($0.rawValue) }
      guard !available.isEmpty else {
        throw ValidationError("All capabilities are already enabled on this bundle identifier.")
      }

      print("Available capability types:")
      for (i, ct) in available.enumerated() {
        print("  [\(i + 1)] \(ct.rawValue)")
      }
      print()
      print("NOTE: Some capabilities (e.g. App Groups, iCloud, Associated Domains)")
      print("require additional configuration in the Apple Developer portal after enabling.")
      print()
      print("Select capability type (1-\(available.count)): ", terminator: "")
      guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
            let choice = Int(input),
            choice >= 1, choice <= available.count else {
        throw ValidationError("Invalid selection.")
      }
      return available[choice - 1]
    }

    func run() async throws {
      if yes { autoConfirm = true }

      if autoConfirm {
        if identifier == nil { throw ValidationError("Bundle identifier argument is required when using --yes.") }
        if type == nil { throw ValidationError("--type is required when using --yes.") }
      }

      let client = try ClientFactory.makeClient()

      let bundleID: BundleID
      if let identifier {
        bundleID = try await findBundleID(identifier: identifier, client: client)
      } else {
        bundleID = try await promptBundleID(client: client)
      }

      // Fetch current capabilities to check for duplicates
      let capsResponse = try await client.send(
        Resources.v1.bundleIDs.id(bundleID.id).bundleIDCapabilities.get()
      )
      let enabledTypes = Set(capsResponse.data.compactMap { $0.attributes?.capabilityType?.rawValue })

      let capabilityType: CapabilityType
      if let type {
        guard let ct = CapabilityType(rawValue: type.uppercased()) else {
          let valid = CapabilityType.allCases.map(\.rawValue).joined(separator: ", ")
          throw ValidationError("Invalid capability type '\(type)'. Valid values: \(valid)")
        }
        if enabledTypes.contains(ct.rawValue) {
          print("\(ct.rawValue) is already enabled on this bundle identifier.")
          return
        }
        capabilityType = ct
      } else {
        capabilityType = try promptCapabilityType(excluding: enabledTypes)
      }

      let bidIdentifier = bundleID.attributes?.identifier ?? identifier ?? bundleID.id
      print("Enable capability:")
      print("  Bundle ID:  \(bidIdentifier)")
      print("  Capability: \(capabilityType)")
      print()

      guard confirm("Enable this capability? [y/N] ") else {
        print("Cancelled.")
        return
      }

      let response = try await client.send(
        Resources.v1.bundleIDCapabilities.post(
          BundleIDCapabilityCreateRequest(data: .init(
            attributes: .init(capabilityType: capabilityType),
            relationships: .init(
              bundleID: .init(data: .init(id: bundleID.id))
            )
          ))
        )
      )

      let attrs = response.data.attributes
      print()
      print("Enabled \(attrs?.capabilityType.map { "\($0)" } ?? "\(capabilityType)") on '\(bidIdentifier)'.")

      if Self.requiresPortalConfiguration.contains(capabilityType) {
        print()
        print("NOTE: This capability requires additional configuration in the Apple Developer portal")
        print("(e.g. container IDs, domains, or entitlements) before it can be used.")
      }

      try await regenerateProfilesIfNeeded(bundleID: bundleID, client: client)
    }

    /// Capabilities that need extra configuration in the Apple Developer portal after enabling.
    private static let requiresPortalConfiguration: Set<CapabilityType> = [
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

    private func promptCapability(bundleID: BundleID, client: AppStoreConnectClient) async throws -> BundleIDCapability {
      let capsResponse = try await client.send(
        Resources.v1.bundleIDs.id(bundleID.id).bundleIDCapabilities.get()
      )
      let caps = capsResponse.data
      guard !caps.isEmpty else {
        throw ValidationError("No capabilities enabled on this bundle identifier.")
      }

      print("Enabled capabilities:")
      for (i, cap) in caps.enumerated() {
        let capType = cap.attributes?.capabilityType.map { "\($0)" } ?? "—"
        print("  [\(i + 1)] \(capType)")
      }
      print()
      print("Select capability to disable (1-\(caps.count)): ", terminator: "")
      guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
            let choice = Int(input),
            choice >= 1, choice <= caps.count else {
        throw ValidationError("Invalid selection.")
      }
      return caps[choice - 1]
    }

    func run() async throws {
      if yes { autoConfirm = true }

      if autoConfirm && identifier == nil {
        throw ValidationError("Bundle identifier argument is required when using --yes.")
      }

      let client = try ClientFactory.makeClient()

      let bundleID: BundleID
      if let identifier {
        bundleID = try await findBundleID(identifier: identifier, client: client)
      } else {
        bundleID = try await promptBundleID(client: client)
      }

      let capability = try await promptCapability(bundleID: bundleID, client: client)
      let capType = capability.attributes?.capabilityType.map { "\($0)" } ?? "—"
      let bidIdentifier = bundleID.attributes?.identifier ?? identifier ?? bundleID.id

      print()
      print("Disable capability:")
      print("  Bundle ID:  \(bidIdentifier)")
      print("  Capability: \(capType)")
      print()

      guard confirm("Disable this capability? [y/N] ") else {
        print("Cancelled.")
        return
      }

      _ = try await client.send(Resources.v1.bundleIDCapabilities.id(capability.id).delete)
      print()
      print("Disabled \(capType) on '\(bidIdentifier)'.")

      try await regenerateProfilesIfNeeded(bundleID: bundleID, client: client)
    }
  }
}

/// After a capability change, checks for provisioning profiles referencing this bundle ID
/// and offers to regenerate them (delete + recreate with the same settings).
private func regenerateProfilesIfNeeded(bundleID: BundleID, client: AppStoreConnectClient) async throws {
  let bidIdentifier = bundleID.attributes?.identifier ?? bundleID.id

  // Fetch all profiles that reference this bundle ID
  var matchingProfiles: [Profile] = []
  var includedCerts: [String: AppStoreAPI.Certificate] = [:]
  var includedDevices: [String: Device] = [:]

  let profileRequest = Resources.v1.profiles.get(
    limit: 200,
    include: [.certificates, .bundleID, .devices],
    limitCertificates: 50,
    limitDevices: 50
  )

  for try await page in client.pages(profileRequest) {
    for profile in page.data {
      if profile.relationships?.bundleID?.data?.id == bundleID.id {
        matchingProfiles.append(profile)
      }
    }
    for item in page.included ?? [] {
      switch item {
      case .certificate(let cert): includedCerts[cert.id] = cert
      case .device(let dev): includedDevices[dev.id] = dev
      case .bundleID: break
      }
    }
  }

  guard !matchingProfiles.isEmpty else { return }

  matchingProfiles.sort { ($0.attributes?.name ?? "") < ($1.attributes?.name ?? "") }

  // Fetch all certificates and group by family
  var allCerts: [AppStoreAPI.Certificate] = []
  for try await page in client.pages(Resources.v1.certificates.get(limit: 200)) {
    allCerts.append(contentsOf: page.data)
  }

  var certIDsByFamily: [String: [String]] = [:]
  for cert in allCerts {
    guard let ct = cert.attributes?.certificateType else { continue }
    certIDsByFamily[certFamily(ct), default: []].append(cert.id)
  }

  print()
  print("Capability changes require provisioning profile regeneration.")
  print("Found \(matchingProfiles.count) profile(s) for \(bidIdentifier):")
  for profile in matchingProfiles {
    let name = profile.attributes?.name ?? "—"
    let type = profile.attributes?.profileType.map { "\($0)" } ?? "—"
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
    let profileName = profile.attributes?.name ?? "—"
    let profileTypeRaw = profile.attributes?.profileType?.rawValue ?? ""
    let profileType = ProfileCreateRequest.Data.Attributes.ProfileType(rawValue: profileTypeRaw)
    guard let profileType else {
      print("  SKIP \(profileName) — unknown profile type '\(profileTypeRaw)'")
      failed += 1
      continue
    }

    let neededFamily = certFamilyForProfileType(profileTypeRaw)
    let certIDs = certIDsByFamily[neededFamily] ?? []
    guard !certIDs.isEmpty else {
      print("  SKIP \(profileName) — no \(neededFamily.lowercased()) certificate found")
      failed += 1
      continue
    }
    let deviceIDs = profile.relationships?.devices?.data?.map(\.id) ?? []
    let needsDevices = profileTypeRaw.contains("DEVELOPMENT") || profileTypeRaw.contains("ADHOC")

    // Delete old profile
    do {
      _ = try await client.send(Resources.v1.profiles.id(profile.id).delete)
    } catch {
      print("  FAIL \(profileName) — delete failed: \(error.localizedDescription)")
      failed += 1
      continue
    }

    // Recreate with all certificates of the matching family
    do {
      let devicesRelationship: ProfileCreateRequest.Data.Relationships.Devices?
      if needsDevices && !deviceIDs.isEmpty {
        devicesRelationship = .init(data: deviceIDs.map { .init(id: $0) })
      } else {
        devicesRelationship = nil
      }

      let response = try await client.send(
        Resources.v1.profiles.post(
          ProfileCreateRequest(data: .init(
            attributes: .init(
              name: profileName,
              profileType: profileType
            ),
            relationships: .init(
              bundleID: .init(data: .init(id: bundleID.id)),
              devices: devicesRelationship,
              certificates: .init(data: certIDs.map { .init(id: $0) })
            )
          ))
        )
      )
      let newExpiry = response.data.attributes?.expirationDate.map { formatDate($0) } ?? "—"
      print("  OK   \(profileName) — regenerated with \(certIDs.count) cert(s) (expires \(newExpiry))")
      succeeded += 1
    } catch {
      let bidIdentifier = bundleID.attributes?.identifier ?? bundleID.id
      let devicesArg = (needsDevices && !deviceIDs.isEmpty) ? " --devices \(deviceIDs.joined(separator: ","))" : ""
      print("  FAIL \(profileName) — recreate failed: \(error.localizedDescription)")
      print("         Recovery: asc-client profiles create --name \"\(profileName)\" --type \(profileTypeRaw) --bundle-id \(bidIdentifier) --certificates \(certIDs.joined(separator: ","))\(devicesArg)")
      failed += 1
    }
  }

  print()
  print("Done. \(succeeded) regenerated, \(failed) failed.")
}

/// Prompts the user to select a bundle identifier from a numbered list.
func promptBundleID(client: AppStoreConnectClient) async throws -> BundleID {
  var allBundleIDs: [BundleID] = []
  for try await page in client.pages(Resources.v1.bundleIDs.get(limit: 200)) {
    allBundleIDs.append(contentsOf: page.data)
  }
  guard !allBundleIDs.isEmpty else {
    throw ValidationError("No bundle identifiers found in your account.")
  }
  allBundleIDs.sort { ($0.attributes?.identifier ?? "") < ($1.attributes?.identifier ?? "") }

  print("Bundle identifiers:")
  for (i, bid) in allBundleIDs.enumerated() {
    let identifier = bid.attributes?.identifier ?? "—"
    let name = bid.attributes?.name ?? "—"
    let platform = bid.attributes?.platform.map { "\($0)" } ?? "—"
    print("  [\(i + 1)] \(identifier) (\(name), \(platform))")
  }
  print()
  print("Select bundle identifier (1-\(allBundleIDs.count)): ", terminator: "")
  guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
        let choice = Int(input),
        choice >= 1, choice <= allBundleIDs.count else {
    throw ValidationError("Invalid selection.")
  }
  return allBundleIDs[choice - 1]
}

/// Prompts the user to select a platform from a numbered list.
func promptPlatform() throws -> BundleIDPlatform {
  let platforms = BundleIDPlatform.allCases
  print("Platforms:")
  for (i, p) in platforms.enumerated() {
    print("  [\(i + 1)] \(p.rawValue)")
  }
  print()
  print("Select platform (1-\(platforms.count)): ", terminator: "")
  guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
        let choice = Int(input),
        choice >= 1, choice <= platforms.count else {
    throw ValidationError("Invalid selection.")
  }
  return platforms[choice - 1]
}

/// Looks up a bundle ID by identifier. Guards against prefix matching.
func findBundleID(identifier: String, client: AppStoreConnectClient) async throws -> BundleID {
  let response = try await client.send(
    Resources.v1.bundleIDs.get(filterIdentifier: [identifier], limit: 200)
  )
  // filterIdentifier does prefix matching — find exact match
  guard let bundleID = response.data.first(where: { $0.attributes?.identifier == identifier }) else {
    throw BundleIDLookupError.notFound(identifier)
  }
  return bundleID
}

enum BundleIDLookupError: LocalizedError {
  case notFound(String)

  var errorDescription: String? {
    switch self {
    case .notFound(let identifier):
      return "No bundle identifier found matching '\(identifier)'."
    }
  }
}
