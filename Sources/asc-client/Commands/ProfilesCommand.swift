import AppStoreAPI
import AppStoreConnect
import ArgumentParser
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
      let client = try ClientFactory.makeClient()

      let filterType: [Resources.V1.Profiles.FilterProfileType]? = try parseFilter(type, name: "type")
      let filterState: [Resources.V1.Profiles.FilterProfileState]? = try parseFilter(state, name: "state")

      var rows: [[String]] = []
      let request = Resources.v1.profiles.get(
        filterName: name.map { [$0] },
        filterProfileType: filterType,
        filterProfileState: filterState,
        limit: 200,
        include: [.bundleID]
      )

      for try await page in client.pages(request) {
        // Build bundle ID lookup from included
        var bundleIDInfo: [String: String] = [:]
        for item in page.included ?? [] {
          if case .bundleID(let bid) = item {
            bundleIDInfo[bid.id] = bid.attributes?.identifier ?? "—"
          }
        }

        for profile in page.data {
          let attrs = profile.attributes
          let bundleIDIdentifier: String
          if let bidID = profile.relationships?.bundleID?.data?.id {
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
      let client = try ClientFactory.makeClient()

      let profile: Profile
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
      if let _ = profile.relationships?.bundleID?.data?.id {
        do {
          let bidResponse = try await client.send(
            Resources.v1.profiles.id(profile.id).bundleID.get()
          )
          let bid = bidResponse.data
          print("Bundle ID: \(bid.attributes?.identifier ?? "—") (\(bid.attributes?.name ?? "—"))")
        } catch {
          print("Warning: Could not fetch bundle ID: \(error.localizedDescription)")
        }
      }

      // Fetch certificates
      let certsResponse = try await client.send(
        Resources.v1.profiles.id(profile.id).certificates.get(limit: 200)
      )
      if !certsResponse.data.isEmpty {
        print()
        print("Certificates:")
        for cert in certsResponse.data {
          let certAttrs = cert.attributes
          print("  \(certAttrs?.displayName ?? "—") (\(certAttrs?.serialNumber ?? "—")) — \(certAttrs?.certificateType.map { formatState($0) } ?? "—")")
        }
      }

      // Fetch devices
      let devicesResponse = try await client.send(
        Resources.v1.profiles.id(profile.id).devices.get(limit: 200)
      )
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
      let client = try ClientFactory.makeClient()

      let profile: Profile
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
      print(green("Downloaded") + " profile to \(outputPath)")
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

    private func promptProfileType() throws -> ProfileCreateRequest.Data.Attributes.ProfileType {
      return try promptSelection(
        "Profile types",
        items: Array(ProfileCreateRequest.Data.Attributes.ProfileType.allCases),
        display: { $0.rawValue },
        prompt: "Select profile type"
      )
    }

    private func promptCertificates(profileType: ProfileCreateRequest.Data.Attributes.ProfileType, client: AppStoreConnectClient) async throws -> [String] {
      let neededFamily = certFamilyForProfileType(profileType.rawValue)

      var allCerts: [AppStoreAPI.Certificate] = []
      for try await page in client.pages(Resources.v1.certificates.get(limit: 200)) {
        allCerts.append(contentsOf: page.data)
      }

      let filtered = allCerts.filter { cert in
        guard let ct = cert.attributes?.certificateType else { return false }
        return certFamily(ct) == neededFamily
      }.sorted {
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

    private func promptDevices(client: AppStoreConnectClient) async throws -> [String] {
      var allDevices: [Device] = []
      for try await page in client.pages(Resources.v1.devices.get(filterStatus: [.enabled], limit: 200)) {
        allDevices.append(contentsOf: page.data)
      }
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

      let client = try ClientFactory.makeClient()

      // 1. Resolve name
      let profileName: String
      if let name {
        profileName = name
      } else {
        profileName = promptText("Profile name: ")
      }

      // 2. Resolve type
      let profileType: ProfileCreateRequest.Data.Attributes.ProfileType
      if let type {
        profileType = try parseEnum(type, name: "type")
      } else {
        profileType = try promptProfileType()
      }

      // 3. Resolve bundle ID
      let bundleID: BundleID
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
          var allCerts: [AppStoreAPI.Certificate] = []
          for try await page in client.pages(Resources.v1.certificates.get(limit: 200)) {
            allCerts.append(contentsOf: page.data)
          }
          let filtered = allCerts.filter { cert in
            guard let ct = cert.attributes?.certificateType else { return false }
            return certFamily(ct) == neededFamily
          }
          guard !filtered.isEmpty else {
            throw ValidationError("No \(neededFamily.lowercased()) certificates found in your account.")
          }
          certIDs = filtered.map(\.id)
          print("Using all \(certIDs.count) \(neededFamily.lowercased()) certificate(s).")
        } else {
          let serials = certificates.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
          var resolved: [String] = []
          for serial in serials {
            let response = try await client.send(
              Resources.v1.certificates.get(filterSerialNumber: [serial], limit: 1)
            )
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
      let needsDevices = profileType.rawValue.contains("DEVELOPMENT") || profileType.rawValue.contains("ADHOC")
      if let devices {
        if devices.lowercased() == "all" {
          var allDevices: [Device] = []
          for try await page in client.pages(Resources.v1.devices.get(filterStatus: [.enabled], limit: 200)) {
            allDevices.append(contentsOf: page.data)
          }
          guard !allDevices.isEmpty else {
            throw ValidationError("No enabled devices found in your account.")
          }
          deviceIDs = allDevices.map(\.id)
          print("Using all \(deviceIDs!.count) enabled device(s).")
        } else {
          let identifiers = devices.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
          var resolved: [String] = []
          for identifier in identifiers {
            let device = try await findDevice(nameOrUDID: identifier, client: client)
            resolved.append(device.id)
          }
          deviceIDs = resolved
        }
      } else if needsDevices {
        deviceIDs = try await promptDevices(client: client)
      } else {
        deviceIDs = nil
      }

      print()
      print("Create provisioning profile:")
      print("  Name:         \(profileName)")
      print("  Type:         \(profileType)")
      print("  Bundle ID:    \(bundleIDLabel)")
      print("  Certificates: \(certIDs.count)")
      if let deviceIDs {
        print("  Devices:      \(deviceIDs.count)")
      }
      print()

      guard confirm("Create this profile? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

      let devicesRelationship: ProfileCreateRequest.Data.Relationships.Devices?
      if let deviceIDs {
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

      let attrs = response.data.attributes
      print()
      print(green("Created") + " profile '\(attrs?.name ?? profileName)'.")
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

      let client = try ClientFactory.makeClient()

      // Fetch all profiles with relationships
      var allProfiles: [Profile] = []
      var includedCerts: [String: AppStoreAPI.Certificate] = [:]
      var includedDevices: [String: Device] = [:]
      var includedBundleIDs: [String: BundleID] = [:]

      let profileRequest = Resources.v1.profiles.get(
        limit: 200,
        include: [.certificates, .bundleID, .devices],
        limitCertificates: 50,
        limitDevices: 50
      )

      for try await page in client.pages(profileRequest) {
        allProfiles.append(contentsOf: page.data)
        for item in page.included ?? [] {
          switch item {
          case .certificate(let cert): includedCerts[cert.id] = cert
          case .device(let dev): includedDevices[dev.id] = dev
          case .bundleID(let bid): includedBundleIDs[bid.id] = bid
          }
        }
      }

      // Determine which profiles to reissue
      let targets: [Profile]
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
        let invalid = allProfiles.filter { $0.attributes?.profileState?.rawValue == "INVALID" }
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

        print("Profiles:")
        for (i, profile) in sorted.enumerated() {
          let pName = profile.attributes?.name ?? "—"
          let pType = profile.attributes?.profileType.map { formatState($0) } ?? "—"
          let pState = profile.attributes?.profileState?.rawValue ?? "—"
          let bidID = profile.relationships?.bundleID?.data?.id ?? ""
          let bidIdentifier = includedBundleIDs[bidID]?.attributes?.identifier ?? "—"
          print("  [\(i + 1)] \(pName) (\(pType)) — \(bidIdentifier) [\(pState)]")
        }
        print()
        print("Select profile (1-\(sorted.count), or 'all'): ", terminator: "")
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !input.isEmpty else {
          throw ValidationError("No selection made.")
        }

        if input.lowercased() == "all" {
          targets = sorted
        } else {
          guard let choice = Int(input), choice >= 1, choice <= sorted.count else {
            throw ValidationError("Invalid selection.")
          }
          targets = [sorted[choice - 1]]
        }
      }

      // Resolve certificates
      var explicitCertIDs: [String]?
      var certsByFamily: [String: [String]] = [:]

      if let toCerts {
        // Explicit certificates specified
        let identifiers = toCerts.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var resolved: [String] = []
        for identifier in identifiers {
          let cert = try await findCertificate(serialOrName: identifier, client: client)
          resolved.append(cert.id)
        }
        explicitCertIDs = resolved
        print("Using \(resolved.count) specified certificate(s).")
      } else {
        // Auto-detect: group all certificates by family
        var allCerts: [AppStoreAPI.Certificate] = []
        for try await page in client.pages(Resources.v1.certificates.get(limit: 200)) {
          allCerts.append(contentsOf: page.data)
        }
        for cert in allCerts {
          guard let ct = cert.attributes?.certificateType else { continue }
          certsByFamily[certFamily(ct), default: []].append(cert.id)
        }
      }

      // Fetch all enabled devices upfront if --all-devices
      var allEnabledDeviceIDs: [String]?
      if allDevices {
        let needsDevices = targets.contains { profile in
          let typeRaw = profile.attributes?.profileType?.rawValue ?? ""
          return typeRaw.contains("DEVELOPMENT") || typeRaw.contains("ADHOC")
        }
        if needsDevices {
          var devices: [Device] = []
          for try await page in client.pages(Resources.v1.devices.get(filterStatus: [.enabled], limit: 200)) {
            devices.append(contentsOf: page.data)
          }
          allEnabledDeviceIDs = devices.map(\.id)
        }
      }

      // Display summary
      print()
      print("Profiles to reissue (\(targets.count)):")
      print()
      Table.print(
        headers: ["Name", "Type", "Bundle ID", "Certificates"],
        rows: targets.map { profile in
          let profileName = profile.attributes?.name ?? "—"
          let profileTypeRaw = profile.attributes?.profileType?.rawValue ?? "—"
          let bidID = profile.relationships?.bundleID?.data?.id ?? ""
          let bidIdentifier = includedBundleIDs[bidID]?.attributes?.identifier ?? "—"
          let certInfo: String
          if let explicitCertIDs {
            certInfo = "\(explicitCertIDs.count) specified"
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
        print(yellow("Cancelled."))
        return
      }
      print()

      // Reissue each profile
      var succeeded = 0
      var failed = 0

      for profile in targets {
        let profileName = profile.attributes?.name ?? "—"
        let profileTypeRaw = profile.attributes?.profileType?.rawValue ?? ""
        let profileType = ProfileCreateRequest.Data.Attributes.ProfileType(rawValue: profileTypeRaw)
        guard let profileType else {
          print("  SKIP \(profileName) — unknown profile type '\(profileTypeRaw)'")
          failed += 1
          continue
        }

        let certIDs: [String]
        if let explicitCertIDs {
          certIDs = explicitCertIDs
        } else {
          let neededFamily = certFamilyForProfileType(profileTypeRaw)
          let familyCertIDs = certsByFamily[neededFamily] ?? []
          guard !familyCertIDs.isEmpty else {
            print("  SKIP \(profileName) — no \(neededFamily.lowercased()) certificate found")
            failed += 1
            continue
          }
          certIDs = familyCertIDs
        }

        let bundleIDResourceID = profile.relationships?.bundleID?.data?.id ?? ""
        let bundleIDIdentifier = includedBundleIDs[bundleIDResourceID]?.attributes?.identifier ?? "—"
        let needsDevices = profileTypeRaw.contains("DEVELOPMENT") || profileTypeRaw.contains("ADHOC")
        let existingDeviceIDs = profile.relationships?.devices?.data?.map(\.id) ?? []

        // Delete old profile
        do {
          _ = try await client.send(Resources.v1.profiles.id(profile.id).delete)
        } catch {
          print("  FAIL \(profileName) — delete failed: \(error.localizedDescription)")
          failed += 1
          continue
        }

        // Recreate
        do {
          let deviceIDs: [String]?
          if needsDevices {
            deviceIDs = allEnabledDeviceIDs ?? existingDeviceIDs
          } else {
            deviceIDs = nil
          }

          let devicesRelationship: ProfileCreateRequest.Data.Relationships.Devices?
          if let deviceIDs, !deviceIDs.isEmpty {
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
                  bundleID: .init(data: .init(id: bundleIDResourceID)),
                  devices: devicesRelationship,
                  certificates: .init(data: certIDs.map { .init(id: $0) })
                )
              ))
            )
          )
          let newExpiry = response.data.attributes?.expirationDate.map { formatDate($0) } ?? "—"
          print("  OK   \(profileName) — reissued with \(certIDs.count) cert(s) (expires \(newExpiry))")
          succeeded += 1
        } catch {
          let devicesArg = (needsDevices && !existingDeviceIDs.isEmpty) ? " --devices \(existingDeviceIDs.joined(separator: ","))" : ""
          print("  FAIL \(profileName) — recreate failed: \(error.localizedDescription)")
          print("         Recovery: asc-client profiles create --name \"\(profileName)\" --type \(profileTypeRaw) --bundle-id \(bundleIDIdentifier) --certificates \(certIDs.joined(separator: ","))\(devicesArg)")
          failed += 1
        }
      }

      print()
      print("Done. \(succeeded) reissued, \(failed) failed.")
    }
  }

  struct Delete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Delete a provisioning profile."
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

      let client = try ClientFactory.makeClient()

      let profile: Profile
      if let name {
        profile = try await findProfile(name: name, client: client)
      } else {
        profile = try await promptProfile(client: client)
      }

      let attrs = profile.attributes
      print("Profile:")
      print("  Name:  \(attrs?.name ?? "—")")
      print("  Type:  \(attrs?.profileType.map { formatState($0) } ?? "—")")
      print("  State: \(attrs?.profileState.map { formatState($0) } ?? "—")")
      print()
      print("WARNING: Deleting a profile cannot be undone.")
      print()

      guard confirm("Delete this profile? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

      _ = try await client.send(Resources.v1.profiles.id(profile.id).delete)
      print()
      print(green("Deleted") + " profile '\(attrs?.name ?? name ?? "—")'.")
    }
  }
}

/// Prompts the user to select a provisioning profile from a numbered list.
func promptProfile(client: AppStoreConnectClient) async throws -> Profile {
  let profiles = try await fetchAll(
    client.pages(Resources.v1.profiles.get(limit: 200)),
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

/// Looks up a profile by name. Fetches profile content for download.
func findProfile(name: String, client: AppStoreConnectClient) async throws -> Profile {
  let response = try await client.send(
    Resources.v1.profiles.get(filterName: [name], limit: 200)
  )
  // Name filter may return partial matches
  if let profile = response.data.first(where: { $0.attributes?.name == name }) {
    return profile
  }
  if response.data.count == 1 {
    return response.data[0]
  }

  throw ProfileLookupError.notFound(name)
}

/// Maps certificate types to a family name so equivalent types are grouped together.
/// Apple replaced platform-specific types (IOS_DISTRIBUTION, MAC_APP_DISTRIBUTION)
/// with universal ones (DISTRIBUTION), but old certs keep their original type.
func certFamily(_ type: CertificateType) -> String {
  switch type {
  case .distribution, .iOSDistribution, .macAppDistribution, .macInstallerDistribution:
    return "Distribution"
  case .development, .iOSDevelopment, .macAppDevelopment:
    return "Development"
  case .developerIDApplication, .developerIDApplicationG2:
    return "Developer ID Application"
  case .developerIDKext, .developerIDKextG2:
    return "Developer ID Kext"
  default:
    return type.rawValue
  }
}

/// Formats a certificate as "DisplayName (Serial)" for clear identification.
func certLabel(_ cert: AppStoreAPI.Certificate) -> String {
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

enum ProfileLookupError: LocalizedError {
  case notFound(String)

  var errorDescription: String? {
    switch self {
    case .notFound(let name):
      return "No provisioning profile found matching '\(name)'.\nInfo: Expired profiles are not visible to the API — delete them from the Apple Developer website first, then recreate."
    }
  }
}
