import ArgumentParser
import ASCKit
import Foundation

struct ProfilesCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "profiles",
    abstract: "Manage provisioning profiles.",
    subcommands: [List.self, Info.self, Download.self, Create.self, Delete.self, Reissue.self]
  )

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List provisioning profiles."
    )

    @Option(name: .long, help: "Filter by profile name.")
    var name: String?

    @Option(name: .long, help: """
      Filter by type. Valid values: \
      IOS_APP_DEVELOPMENT, IOS_APP_STORE, IOS_APP_ADHOC, IOS_APP_INHOUSE, \
      MAC_APP_DEVELOPMENT, MAC_APP_STORE, MAC_APP_DIRECT, \
      MAC_CATALYST_APP_DEVELOPMENT, MAC_CATALYST_APP_STORE, MAC_CATALYST_APP_DIRECT, \
      TVOS_APP_DEVELOPMENT, TVOS_APP_STORE, TVOS_APP_ADHOC, TVOS_APP_INHOUSE.
      """)
    var type: String?

    @Option(name: .long, help: "Filter by state (ACTIVE, INVALID).")
    var state: String?

    func run() async throws {
      let client = try ClientFactory.makeASCClient()

      typealias Query = Operations.ProfilesGetCollection.Input.Query
      let filterType: [Query.FilterProfileTypePayloadPayload]? = try parseFilter(type, name: "type")
      let filterState: [Query.FilterProfileStatePayloadPayload]? = try parseFilter(state, name: "state")

      let pages = try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.profilesGetCollection(query: .init(
          filterName: name.map { [$0] }, filterProfileType: filterType, filterProfileState: filterState,
          limit: 200, include: [.bundleId]
        )).ok.body.json
      }

      var rows: [[String]] = []
      for page in pages {
        // Build bundle ID lookup from included
        var bundleIDInfo: [String: String] = [:]
        for item in page.included ?? [] {
          if case .bundleIds(let bid) = item {
            bundleIDInfo[bid.id] = bid.attributes?.identifier ?? "—"
          }
        }

        for profile in page.data {
          let attrs = profile.attributes
          let bundleIDIdentifier: String
          if let bidID = profile.relationships?.bundleId?.data?.id {
            bundleIDIdentifier = bundleIDInfo[bidID] ?? "—"
          } else {
            bundleIDIdentifier = "—"
          }

          rows.append([
            attrs?.name ?? "—",
            attrs?.profileType.map { formatState($0) } ?? "—",
            attrs?.profileState.map { formatState($0) } ?? "—",
            attrs?.platform.map { formatState($0) } ?? "—",
            bundleIDIdentifier,
            attrs?.expirationDate.map { formatDate($0) } ?? "—",
          ])
        }
      }

      if rows.isEmpty {
        print("No provisioning profiles found.")
      } else {
        Table.print(
          headers: ["Name", "Type", "State", "Platform", "Bundle ID", "Expires"],
          rows: rows
        )
      }
    }
  }

  struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Show details for a provisioning profile."
    )

    @Argument(help: "Profile name.")
    var name: String?

    func run() async throws {
      let client = try ClientFactory.makeASCClient()

      let profile: Components.Schemas.Profile
      if let name {
        profile = try await findProfile(name: name, client: client)
      } else {
        profile = try await promptProfile(client: client)
      }

      let attrs = profile.attributes
      print("Name:     \(attrs?.name ?? "—")")
      print("Type:     \(attrs?.profileType.map { formatState($0) } ?? "—")")
      print("State:    \(attrs?.profileState.map { formatState($0) } ?? "—")")
      print("Platform: \(attrs?.platform.map { formatState($0) } ?? "—")")
      print("UUID:     \(attrs?.uuid ?? "—")")
      print("Created:  \(attrs?.createdDate.map { formatDate($0) } ?? "—")")
      print("Expires:  \(attrs?.expirationDate.map { formatDate($0) } ?? "—")")

      // Fetch bundle ID
      if let _ = profile.relationships?.bundleId?.data?.id {
        do {
          let bid = try await client.profilesBundleIdGetToOneRelated(path: .init(id: profile.id)).ok.body.json.data
          print("Bundle ID: \(bid.attributes?.identifier ?? "—") (\(bid.attributes?.name ?? "—"))")
        } catch {
          print("Warning: Could not fetch bundle ID: \(describeError(error))")
        }
      }

      // Fetch certificates
      let certsResponse = try await client.profilesCertificatesGetToManyRelated(
        path: .init(id: profile.id), query: .init(limit: 200)
      ).ok.body.json
      if !certsResponse.data.isEmpty {
        print()
        print("Certificates:")
        for cert in certsResponse.data {
          let certAttrs = cert.attributes
          print("  \(certAttrs?.displayName ?? "—") (\(certAttrs?.serialNumber ?? "—")) — \(certAttrs?.certificateType.map { formatState($0) } ?? "—")")
        }
      }

      // Fetch devices
      let devicesResponse = try await client.profilesDevicesGetToManyRelated(
        path: .init(id: profile.id), query: .init(limit: 200)
      ).ok.body.json
      if !devicesResponse.data.isEmpty {
        print()
        print("Devices (\(devicesResponse.data.count)):")
        for device in devicesResponse.data {
          let devAttrs = device.attributes
          print("  \(devAttrs?.name ?? "—") (\(devAttrs?.udid ?? "—"))")
        }
      }
    }
  }

  struct Download: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Download a provisioning profile."
    )

    @Argument(help: "Profile name.")
    var name: String?

    @Option(name: .long, help: "Output file path (default: <name>.mobileprovision).")
    var output: String?

    func run() async throws {
      let client = try ClientFactory.makeASCClient()

      let profile: Components.Schemas.Profile
      if let name {
        profile = try await findProfile(name: name, client: client)
      } else {
        profile = try await promptProfile(client: client)
      }

      guard let content = profile.attributes?.profileContent else {
        throw ValidationError("Profile has no content to download.")
      }

      guard let profileData = Data(base64Encoded: content) else {
        throw ValidationError("Could not decode profile content.")
      }

      let profileName = profile.attributes?.name ?? name ?? "profile"
      let defaultName = profileName
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "/", with: "_")
      let outputPath = expandPath(
        confirmOutputPath(output ?? "\(defaultName).mobileprovision", isDirectory: false)
      )
      try profileData.write(to: URL(fileURLWithPath: outputPath))
      success("Downloaded", "profile to \(outputPath)")
    }
  }

  struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Create a provisioning profile."
    )

    @Option(name: .long, help: "Profile name.")
    var name: String?

    @Option(name: .long, help: """
      Profile type. Valid values: \
      IOS_APP_DEVELOPMENT, IOS_APP_STORE, IOS_APP_ADHOC, IOS_APP_INHOUSE, \
      MAC_APP_DEVELOPMENT, MAC_APP_STORE, MAC_APP_DIRECT, \
      MAC_CATALYST_APP_DEVELOPMENT, MAC_CATALYST_APP_STORE, MAC_CATALYST_APP_DIRECT, \
      TVOS_APP_DEVELOPMENT, TVOS_APP_STORE, TVOS_APP_ADHOC, TVOS_APP_INHOUSE.
      """)
    var type: String?

    @Option(name: .customLong("bundle-id"), help: "Bundle identifier (e.g. com.example.MyApp).")
    var bundleIdentifier: String?

    @Option(name: .long, help: "Certificate serial numbers (comma-separated, or 'all').")
    var certificates: String?

    @Option(name: .long, help: "Device names or UDIDs (comma-separated, or 'all'). Required for dev/adhoc profiles.")
    var devices: String?

    @Option(name: .long, help: "Save the profile to this path (.mobileprovision).")
    var output: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    // MARK: - Interactive prompts

    private func promptProfileType() throws -> ASCEnum.ProfileCreateRequestProfileType {
      return try promptSelection(
        "Profile types",
        items: ASCEnum.ProfileCreateRequestProfileType.allCases,
        display: { $0.rawValue },
        prompt: "Select profile type"
      )
    }

    private func promptCertificates(profileType: ASCEnum.ProfileCreateRequestProfileType, client: ASCClient) async throws -> [String] {
      let neededFamily = certFamilyForProfileType(profileType.rawValue)

      let filtered = try await fetchCertificates(family: neededFamily, client: client).sorted {
        ($0.attributes?.expirationDate ?? .distantPast) > ($1.attributes?.expirationDate ?? .distantPast)
      }

      guard !filtered.isEmpty else {
        throw ValidationError("No \(neededFamily.lowercased()) certificates found. Create one first with 'certs create'.")
      }

      let selected = try promptMultiSelection(
        "\(neededFamily) certificates",
        items: filtered,
        display: { cert in
          let expires = cert.attributes?.expirationDate.map { formatDate($0) } ?? "—"
          return "\(certLabel(cert)) — expires \(expires)"
        },
        prompt: "Select certificates"
      )
      return selected.map(\.id)
    }

    private func promptDevices(client: ASCClient) async throws -> [String] {
      let allDevices = try await fetchEnabledDevices(client: client)
      guard !allDevices.isEmpty else {
        throw ValidationError("No enabled devices found. Register one first with 'devices register'.")
      }

      let selected = try promptMultiSelection(
        "Enabled devices",
        items: allDevices,
        display: { device in
          let name = device.attributes?.name ?? "—"
          let udid = device.attributes?.udid ?? "—"
          return "\(name) (\(udid))"
        },
        prompt: "Select devices",
        defaultAll: true
      )
      if selected.count == allDevices.count {
        print("Using all \(allDevices.count) enabled device(s).")
      }
      return selected.map(\.id)
    }

    // MARK: - Run

    func run() async throws {
      if yes { autoConfirm = true }

      // Interactive mode doesn't make sense with --yes
      if autoConfirm {
        if name == nil { throw ValidationError("--name is required when using --yes.") }
        if type == nil { throw ValidationError("--type is required when using --yes.") }
        if bundleIdentifier == nil { throw ValidationError("--bundle-id is required when using --yes.") }
        if certificates == nil { throw ValidationError("--certificates is required when using --yes.") }
      }

      let client = try ClientFactory.makeASCClient()

      // 1. Resolve name
      let profileName: String
      if let name {
        profileName = name
      } else {
        profileName = try promptText("Profile name: ")
      }

      // 2. Resolve type
      let profileType: ASCEnum.ProfileCreateRequestProfileType
      if let type {
        profileType = try parseEnum(type, name: "type")
      } else {
        profileType = try promptProfileType()
      }

      // 3. Resolve bundle ID
      let bundleID: Components.Schemas.BundleId
      let bundleIDLabel: String
      if let bundleIdentifier {
        bundleID = try await findBundleID(identifier: bundleIdentifier, client: client)
        bundleIDLabel = bundleIdentifier
      } else {
        bundleID = try await promptBundleID(client: client)
        bundleIDLabel = bundleID.attributes?.identifier ?? bundleID.id
      }

      // 4. Resolve certificates
      let certIDs: [String]
      if let certificates {
        if certificates.lowercased() == "all" {
          let neededFamily = certFamilyForProfileType(profileType.rawValue)
          let filtered = try await fetchCertificates(family: neededFamily, client: client)
          guard !filtered.isEmpty else {
            throw ValidationError("No \(neededFamily.lowercased()) certificates found in your account.")
          }
          certIDs = filtered.map(\.id)
          print("Using all \(certIDs.count) \(neededFamily.lowercased()) certificate(s).")
        } else {
          let serials = certificates.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
          var resolved: [String] = []
          for serial in serials {
            let response = try await client.certificatesGetCollection(
              query: .init(filterSerialNumber: [serial], limit: 1)
            ).ok.body.json
            guard let cert = response.data.first else {
              throw ValidationError("No certificate found with serial number '\(serial)'.")
            }
            resolved.append(cert.id)
          }
          certIDs = resolved
        }
      } else {
        certIDs = try await promptCertificates(profileType: profileType, client: client)
      }

      // 5. Resolve devices (if needed)
      let deviceIDs: [String]?
      if let devices {
        if devices.lowercased() == "all" {
          let allDevices = try await fetchEnabledDevices(client: client)
          guard !allDevices.isEmpty else {
            throw ValidationError("No enabled devices found in your account.")
          }
          deviceIDs = allDevices.map(\.id)
          print("Using all \(allDevices.count) enabled device(s).")
        } else {
          let identifiers = devices.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
          var resolved: [String] = []
          for identifier in identifiers {
            let device = try await findDevice(nameOrUDID: identifier, client: client)
            resolved.append(device.id)
          }
          deviceIDs = resolved
        }
      } else if profileNeedsDevices(profileType.rawValue) {
        deviceIDs = try await promptDevices(client: client)
      } else {
        deviceIDs = nil
      }

      print()
      print("Create provisioning profile:")
      print("  Name:         \(profileName)")
      print("  Type:         \(formatState(profileType.rawValue))")
      print("  Bundle ID:    \(bundleIDLabel)")
      print("  Certificates: \(certIDs.count)")
      if let deviceIDs {
        print("  Devices:      \(deviceIDs.count)")
      }
      print()

      guard confirm("Create this profile? [y/N] ") else {
        cancelled()
        return
      }

      let created = try await createProfile(
        name: profileName, type: profileType, bundleIDResourceID: bundleID.id,
        certificateIDs: certIDs, deviceIDs: deviceIDs ?? [], client: client
      )

      let attrs = created.attributes
      print()
      success("Created", "profile '\(attrs?.name ?? profileName)'.")
      print("  UUID:    \(attrs?.uuid ?? "—")")
      print("  State:   \(attrs?.profileState.map { formatState($0) } ?? "—")")
      print("  Expires: \(attrs?.expirationDate.map { formatDate($0) } ?? "—")")

      if let output, let content = attrs?.profileContent {
        guard let profileData = Data(base64Encoded: content) else {
          print("Warning: Could not decode profile content.")
          return
        }
        let outputPath = expandPath(confirmOutputPath(output, isDirectory: false))
        try profileData.write(to: URL(fileURLWithPath: outputPath))
        print("  Saved to: \(outputPath)")
      }
    }
  }

  struct Reissue: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Reissue provisioning profiles.",
      discussion: """
        Deletes and recreates profiles using all certificates of the matching \
        type. By default, includes every distribution or development certificate \
        so any team member can sign with the profile.

        Without arguments, shows a list of invalid profiles to select from. \
        Use --all-invalid to reissue every invalid profile, or --all to \
        reissue every profile regardless of state.

        Use --to-certs to specify exact certificates instead of auto-detecting.
        """
    )

    @Argument(help: "Profile name to reissue.")
    var name: String?

    @Flag(name: .long, help: "Reissue all profiles regardless of state.")
    var all = false

    @Flag(name: .customLong("all-invalid"), help: "Reissue all invalid profiles.")
    var allInvalid = false

    @Option(name: .customLong("to-certs"), help: "Certificate serial numbers or display names (comma-separated). Overrides auto-detection.")
    var toCerts: String?

    @Flag(name: .customLong("all-devices"), help: "Use all enabled devices for dev/adhoc profiles instead of preserving the original set.")
    var allDevices = false

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }

      if autoConfirm && name == nil && !all && !allInvalid {
        throw ValidationError("Profile name, --all, or --all-invalid is required when using --yes.")
      }

      let client = try ClientFactory.makeASCClient()

      // Fetch all profiles with their bundle ID relationship
      let (allProfiles, includedBundleIDs) = try await fetchProfilesWithBundleIDs(client: client)

      // Determine which profiles to reissue
      let targets: [Components.Schemas.Profile]
      if let name {
        guard let profile = allProfiles.first(where: { $0.attributes?.name == name }) else {
          throw ValidationError("No profile found with name '\(name)'.")
        }
        targets = [profile]
      } else if all {
        guard !allProfiles.isEmpty else {
          print("No profiles found.")
          return
        }
        targets = allProfiles
      } else if allInvalid {
        let invalid = allProfiles.filter { $0.attributes?.profileState == "INVALID" }
        guard !invalid.isEmpty else {
          print("No invalid profiles found.")
          return
        }
        targets = invalid
      } else {
        // Interactive: show all profiles with status
        let sorted = allProfiles.sorted { ($0.attributes?.name ?? "") < ($1.attributes?.name ?? "") }
        guard !sorted.isEmpty else {
          print("No profiles found.")
          return
        }

        targets = try promptMultiSelection(
          "Profiles",
          items: sorted,
          display: { profile in
            let pName = profile.attributes?.name ?? "—"
            let pType = profile.attributes?.profileType.map { formatState($0) } ?? "—"
            let pState = profile.attributes?.profileState ?? "—"
            let bidID = profile.relationships?.bundleId?.data?.id ?? ""
            let bidIdentifier = includedBundleIDs[bidID]?.attributes?.identifier ?? "—"
            return "\(pName) (\(pType)) — \(bidIdentifier) [\(pState)]"
          },
          prompt: "Select profile"
        )
      }

      // Resolve certificates
      var explicitCerts: [Components.Schemas.Certificate]?
      var certsByFamily: [String: [Components.Schemas.Certificate]] = [:]

      if let toCerts {
        // Explicit certificates specified
        let identifiers = toCerts.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var resolved: [Components.Schemas.Certificate] = []
        for identifier in identifiers {
          let cert = try await findCertificate(serialOrName: identifier, client: client)
          resolved.append(cert)
        }
        explicitCerts = resolved
        print("Using \(resolved.count) specified certificate(s).")
      } else {
        // Auto-detect: group all certificates by family
        certsByFamily = try await fetchCertificatesByFamily(client: client)
      }

      // Fetch all enabled devices upfront if --all-devices
      var allEnabledDeviceIDs: [String]?
      if allDevices, targets.contains(where: { profileNeedsDevices($0.attributes?.profileType ?? "") }) {
        allEnabledDeviceIDs = try await fetchEnabledDevices(client: client).map(\.id)
      }

      // Display summary
      print()
      print("Profiles to reissue (\(targets.count)):")
      print()
      Table.print(
        headers: ["Name", "Type", "Bundle ID", "Certificates"],
        rows: targets.map { profile in
          let profileName = profile.attributes?.name ?? "—"
          let profileTypeRaw = profile.attributes?.profileType ?? "—"
          let bidID = profile.relationships?.bundleId?.data?.id ?? ""
          let bidIdentifier = includedBundleIDs[bidID]?.attributes?.identifier ?? "—"
          let certInfo: String
          if let explicitCerts {
            certInfo = "\(explicitCerts.count) specified"
          } else {
            let neededFamily = certFamilyForProfileType(profileTypeRaw)
            let count = certsByFamily[neededFamily]?.count ?? 0
            certInfo = count == 0 ? "—" : "\(count) \(neededFamily.lowercased())"
          }
          return [profileName, profileTypeRaw, bidIdentifier, certInfo]
        }
      )
      print()

      guard confirm("Reissue \(targets.count) profile(s)? This will delete and recreate each profile. [y/N] ") else {
        cancelled()
        return
      }
      print()

      // Reissue each profile
      var succeeded = 0
      var failed = 0

      for profile in targets {
        let certs: [Components.Schemas.Certificate]
        if let explicitCerts {
          certs = explicitCerts
        } else {
          let neededFamily = certFamilyForProfileType(profile.attributes?.profileType ?? "")
          let familyCerts = certsByFamily[neededFamily] ?? []
          guard !familyCerts.isEmpty else {
            print("  SKIP \(profile.attributes?.name ?? "—") — no \(neededFamily.lowercased()) certificate found")
            failed += 1
            continue
          }
          certs = familyCerts
        }

        let bundleIDResourceID = profile.relationships?.bundleId?.data?.id ?? ""
        let bundleIDIdentifier = includedBundleIDs[bundleIDResourceID]?.attributes?.identifier ?? "—"

        if await reissueProfile(
          profile,
          bundleIDIdentifier: bundleIDIdentifier,
          certs: certs,
          overrideDeviceIDs: allEnabledDeviceIDs,
          verb: "reissued",
          client: client
        ) {
          succeeded += 1
        } else {
          failed += 1
        }
      }

      print()
      print("Done. \(succeeded) reissued, \(failed) failed.")
    }
  }

  struct Delete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Delete one or more provisioning profiles."
    )

    @Argument(help: "Profile name.")
    var name: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }

      if autoConfirm && name == nil {
        throw ValidationError("Profile name argument is required when using --yes.")
      }

      let client = try ClientFactory.makeASCClient()

      let profiles: [Components.Schemas.Profile]
      if let name {
        profiles = [try await findProfile(name: name, client: client)]
      } else {
        let allProfiles = try fetchAll(
          await ASCPaging.allPages(next: { $0.links.next }) {
            try await client.profilesGetCollection(query: .init(limit: 200)).ok.body.json
          },
          data: \.data,
          emptyMessage: "No provisioning profiles found in your account.",
          sort: { ($0.attributes?.name ?? "") < ($1.attributes?.name ?? "") }
        )
        profiles = try promptMultiSelection(
          "Provisioning profiles", items: allProfiles,
          display: { "\($0.attributes?.name ?? "—") (\($0.attributes?.profileType.map { formatState($0) } ?? "—"), \($0.attributes?.profileState.map { formatState($0) } ?? "—"))" },
          prompt: "Select profile"
        )
      }

      print()
      print("Profiles to delete (\(profiles.count)):")
      print()
      Table.print(
        headers: ["Name", "Type", "State"],
        rows: profiles.map { p in
          [
            p.attributes?.name ?? "—",
            p.attributes?.profileType.map { formatState($0) } ?? "—",
            p.attributes?.profileState.map { formatState($0) } ?? "—",
          ]
        }
      )
      print()
      print("WARNING: Deleting a profile cannot be undone.")
      print()

      guard confirm("Delete \(profiles.count) profile(s)? [y/N] ") else {
        cancelled()
        return
      }
      print()

      var succeeded = 0
      var failed = 0
      for profile in profiles {
        let pName = profile.attributes?.name ?? "—"
        do {
          _ = try await client.profilesDeleteInstance(path: .init(id: profile.id)).noContent
          print("  OK   \(pName)")
          succeeded += 1
        } catch {
          print("  FAIL \(pName) — \(describeError(error))")
          failed += 1
        }
      }

      print()
      print("Done. \(succeeded) deleted, \(failed) failed.")
    }
  }
}

/// Prompts the user to select a provisioning profile from a numbered list.
func promptProfile(client: ASCClient) async throws -> Components.Schemas.Profile {
  let profiles = try fetchAll(
    await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.profilesGetCollection(query: .init(limit: 200)).ok.body.json
    },
    data: \.data,
    emptyMessage: "No provisioning profiles found in your account.",
    sort: { ($0.attributes?.name ?? "") < ($1.attributes?.name ?? "") }
  )
  return try promptSelection(
    "Provisioning profiles", items: profiles,
    display: { "\($0.attributes?.name ?? "—") (\($0.attributes?.profileType.map { formatState($0) } ?? "—"), \($0.attributes?.profileState.map { formatState($0) } ?? "—"))" },
    prompt: "Select profile"
  )
}

/// Looks up a profile by name. The collection includes each profile's content.
func findProfile(name: String, client: ASCClient) async throws -> Components.Schemas.Profile {
  let profiles = try await client.profilesGetCollection(query: .init(filterName: [name], limit: 200)).ok.body.json.data
  // Name filter may return partial matches
  if let profile = profiles.first(where: { $0.attributes?.name == name }) {
    return profile
  }
  if profiles.count == 1 {
    return profiles[0]
  }
  throw ProfileLookupError.notFound(name)
}

/// Every profile in the account plus the bundle IDs they reference, keyed by resource ID.
/// Relationship IDs are only populated when the bundle ID is included.
func fetchProfilesWithBundleIDs(
  client: ASCClient
) async throws -> (profiles: [Components.Schemas.Profile], bundleIDs: [String: Components.Schemas.BundleId]) {
  let pages = try await ASCPaging.allPages(next: { $0.links.next }) {
    try await client.profilesGetCollection(query: .init(limit: 200, include: [.bundleId])).ok.body.json
  }
  var bundleIDs: [String: Components.Schemas.BundleId] = [:]
  for item in pages.flatMap({ $0.included ?? [] }) {
    if case .bundleIds(let bid) = item { bundleIDs[bid.id] = bid }
  }
  return (pages.flatMap(\.data), bundleIDs)
}

/// All enabled devices in the account.
func fetchEnabledDevices(client: ASCClient) async throws -> [Components.Schemas.Device] {
  try await ASCPaging.allPages(next: { $0.links.next }) {
    try await client.devicesGetCollection(query: .init(filterStatus: [.enabled], limit: 200)).ok.body.json
  }.flatMap(\.data)
}

/// Fetches all signing certificates in the account, filtered to `family` if given.
func fetchCertificates(family: String? = nil, client: ASCClient) async throws -> [Components.Schemas.Certificate] {
  let allCerts = try await ASCPaging.allPages(next: { $0.links.next }) {
    try await client.certificatesGetCollection(query: .init(limit: 200)).ok.body.json
  }.flatMap(\.data)
  guard let family else { return allCerts }
  return allCerts.filter { $0.attributes?.certificateType.map(certFamily) == family }
}

/// All certificates in the account grouped by `certFamily`.
func fetchCertificatesByFamily(client: ASCClient) async throws -> [String: [Components.Schemas.Certificate]] {
  var certsByFamily: [String: [Components.Schemas.Certificate]] = [:]
  for cert in try await fetchCertificates(client: client) {
    guard let type = cert.attributes?.certificateType else { continue }
    certsByFamily[certFamily(type), default: []].append(cert)
  }
  return certsByFamily
}

/// Creates a provisioning profile; `deviceIDs` is only sent when non-empty.
func createProfile(
  name: String,
  type: ASCEnum.ProfileCreateRequestProfileType,
  bundleIDResourceID: String,
  certificateIDs: [String],
  deviceIDs: [String],
  client: ASCClient
) async throws -> Components.Schemas.Profile {
  typealias Relationships = Components.Schemas.ProfileCreateRequest.DataPayload.RelationshipsPayload
  let request = Components.Schemas.ProfileCreateRequest(data: .init(
    attributes: .init(name: name, profileType: type.rawValue),
    relationships: Relationships(
      bundleId: .init(data: .init(id: bundleIDResourceID, _type: "bundleIds")),
      certificates: .init(data: certificateIDs.map { .init(id: $0, _type: "certificates") }),
      devices: deviceIDs.isEmpty ? nil : .init(data: deviceIDs.map { .init(id: $0, _type: "devices") })
    ),
    _type: "profiles"
  ))
  return try await client.profilesCreateInstance(body: .json(request)).created.body.json.data
}

/// Deletes `profile` and recreates it with the given certificates, preserving the
/// profile's device set unless `overrideDeviceIDs` is provided. The device list is
/// fetched with pagination BEFORE the delete — the profiles list endpoint caps
/// included device linkages at 50, which would silently drop devices from large
/// ad-hoc/development profiles. Prints an OK/FAIL/SKIP line (plus a recovery
/// command on recreate failure) and returns true on success.
func reissueProfile(
  _ profile: Components.Schemas.Profile,
  bundleIDIdentifier: String,
  certs: [Components.Schemas.Certificate],
  overrideDeviceIDs: [String]? = nil,
  verb: String,
  client: ASCClient
) async -> Bool {
  let profileName = profile.attributes?.name ?? "—"
  let profileTypeRaw = profile.attributes?.profileType ?? ""
  guard let profileType = ASCEnum.ProfileCreateRequestProfileType(rawValue: profileTypeRaw) else {
    print("  SKIP \(profileName) — unknown profile type '\(profileTypeRaw)'")
    return false
  }
  guard let bundleIDResourceID = profile.relationships?.bundleId?.data?.id else {
    print("  SKIP \(profileName) — could not resolve its bundle ID")
    return false
  }

  var deviceIDs: [String] = []
  var deviceUDIDs: [String] = []
  if profileNeedsDevices(profileTypeRaw) {
    if let overrideDeviceIDs {
      deviceIDs = overrideDeviceIDs
    } else {
      do {
        let devices = try await ASCPaging.allPages(next: { $0.links.next }) {
          try await client.profilesDevicesGetToManyRelated(path: .init(id: profile.id), query: .init(limit: 200)).ok.body.json
        }.flatMap(\.data)
        deviceIDs = devices.map(\.id)
        deviceUDIDs = devices.compactMap { $0.attributes?.udid }
      } catch {
        print("  FAIL \(profileName) — could not fetch its devices: \(describeError(error))")
        return false
      }
    }
  }

  do {
    _ = try await client.profilesDeleteInstance(path: .init(id: profile.id)).noContent
  } catch {
    print("  FAIL \(profileName) — delete failed: \(describeError(error))")
    return false
  }

  do {
    let created = try await createProfile(
      name: profileName, type: profileType, bundleIDResourceID: bundleIDResourceID,
      certificateIDs: certs.map(\.id), deviceIDs: deviceIDs, client: client
    )
    let newExpiry = created.attributes?.expirationDate.map { formatDate($0) } ?? "—"
    print("  OK   \(profileName) — \(verb) with \(certs.count) cert(s) (expires \(newExpiry))")
    return true
  } catch {
    let certSpec = certs.compactMap { $0.attributes?.serialNumber }.joined(separator: ",")
    let devicesArg = deviceUDIDs.isEmpty ? "" : " --devices \(deviceUDIDs.joined(separator: ","))"
    print("  FAIL \(profileName) — recreate failed: \(describeError(error))")
    print("         Recovery: ascelerate profiles create --name \"\(profileName)\" --type \(profileTypeRaw) --bundle-id \(bundleIDIdentifier) --certificates \(certSpec)\(devicesArg)")
    return false
  }
}

/// Maps certificate types to a family name so equivalent types are grouped together.
/// Apple replaced platform-specific types (IOS_DISTRIBUTION, MAC_APP_DISTRIBUTION)
/// with universal ones (DISTRIBUTION), but old certs keep their original type.
func certFamily(_ rawType: String) -> String {
  switch ASCEnum.CertificateType(rawValue: rawType) {
  case .distribution, .iosDistribution, .macAppDistribution, .macInstallerDistribution:
    return "Distribution"
  case .development, .iosDevelopment, .macAppDevelopment:
    return "Development"
  case .developerIdApplication, .developerIdApplicationG2:
    return "Developer ID Application"
  case .developerIdKext, .developerIdKextG2:
    return "Developer ID Kext"
  default:
    return rawType
  }
}

/// Formats a certificate as "DisplayName (Serial)" for clear identification.
func certLabel(_ cert: Components.Schemas.Certificate) -> String {
  let name = cert.attributes?.displayName ?? "—"
  let serial = cert.attributes?.serialNumber ?? cert.id
  return "\(name) (\(serial))"
}

/// Returns the certificate family name needed for a given profile type raw value.
func certFamilyForProfileType(_ rawType: String) -> String {
  if rawType.contains("DIRECT") {
    return "Developer ID Application"
  }
  if rawType.contains("STORE") || rawType.contains("ADHOC") || rawType.contains("INHOUSE") {
    return "Distribution"
  }
  return "Development"
}

/// Development and ad hoc profiles list the devices they install on.
func profileNeedsDevices(_ rawType: String) -> Bool {
  rawType.contains("DEVELOPMENT") || rawType.contains("ADHOC")
}

enum ProfileLookupError: LocalizedError {
  case notFound(String)

  var errorDescription: String? {
    switch self {
    case .notFound(let name):
      return "No provisioning profile found matching '\(name)'.\nInfo: Expired profiles are not visible to the API — delete them from the Apple Developer website first, then recreate."
    }
  }
}
