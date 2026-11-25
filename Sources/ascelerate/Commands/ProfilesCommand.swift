import ArgumentParser
import ASCKit
import AscelerateCore
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

      typealias Query = Operations.ProfilesGetCollection.Input.Query
      let filterType: [Query.FilterProfileTypePayloadPayload]? = try parseFilter(type, name: "type")
      let filterState: [Query.FilterProfileStatePayloadPayload]? = try parseFilter(state, name: "state")
      let profiles = try await Profiles.list(
        name: name, types: filterType?.map(\.rawValue), states: filterState?.map(\.rawValue), client: client)

      let rows = profiles.map { profile in
        [
          profile.name.isEmpty ? "—" : profile.name,
          profile.type.map { formatState($0) } ?? "—",
          profile.state.map { formatState($0) } ?? "—",
          profile.platform.map { formatState($0) } ?? "—",
          profile.bundleIdentifier ?? "—",
          profile.expirationDate.map { formatDate($0) } ?? "—",
        ]
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

      let profile: Profiles.Profile
      if let name {
        profile = try await Profiles.find(name: name, client: client)
      } else {
        profile = try await promptProfile(client: client)
      }

      print("Name:     \(profile.name.isEmpty ? "—" : profile.name)")
      print("Type:     \(profile.type.map { formatState($0) } ?? "—")")
      print("State:    \(profile.state.map { formatState($0) } ?? "—")")
      print("Platform: \(profile.platform.map { formatState($0) } ?? "—")")
      print("UUID:     \(profile.uuid ?? "—")")
      print("Created:  \(profile.createdDate.map { formatDate($0) } ?? "—")")
      print("Expires:  \(profile.expirationDate.map { formatDate($0) } ?? "—")")

      if profile.bundleIDResourceID != nil {
        do {
          let bid = try await Profiles.bundleID(profileID: profile.id, client: client)
          print("Bundle ID: \(bid.identifier.isEmpty ? "—" : bid.identifier) (\(bid.name.isEmpty ? "—" : bid.name))")
        } catch {
          print("Warning: Could not fetch bundle ID: \(describeError(error))")
        }
      }

      let certificates = try await Profiles.certificates(profileID: profile.id, client: client)
      if !certificates.isEmpty {
        print()
        print("Certificates:")
        for cert in certificates {
          print("  \(cert.displayName ?? "—") (\(cert.serialNumber ?? "—")) — \(cert.type.map { formatState($0) } ?? "—")")
        }
      }

      let devices = try await Profiles.devices(profileID: profile.id, client: client)
      if !devices.isEmpty {
        print()
        print("Devices (\(devices.count)):")
        for device in devices {
          print("  \(device.name.isEmpty ? "—" : device.name) (\(device.udid.isEmpty ? "—" : device.udid))")
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

      let profile: Profiles.Profile
      if let name {
        profile = try await Profiles.find(name: name, client: client)
      } else {
        profile = try await promptProfile(client: client)
      }

      guard let profileData = profile.content else {
        throw ValidationError("Profile has no content to download.")
      }

      let profileName = profile.name.isEmpty ? (name ?? "profile") : profile.name
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
      let neededFamily = Profiles.certificateFamily(forProfileType: profileType.rawValue)

      let filtered = try await fetchCertificates(fitting: profileType.rawValue, client: client).sorted {
        ($0.expirationDate ?? .distantPast) > ($1.expirationDate ?? .distantPast)
      }

      guard !filtered.isEmpty else {
        throw ValidationError("No \(neededFamily.lowercased()) certificates found. Create one first with 'certs create'.")
      }

      let selected = try promptMultiSelection(
        "\(neededFamily) certificates",
        items: filtered,
        display: { cert in
          let expires = cert.expirationDate.map { formatDate($0) } ?? "—"
          return "\(certLabel(cert)) — expires \(expires)"
        },
        prompt: "Select certificates"
      )
      return selected.map(\.id)
    }

    private func promptDevices(client: ASCClient) async throws -> [String] {
      let allDevices = try await Devices.list(statuses: ["ENABLED"], client: client)
      guard !allDevices.isEmpty else {
        throw ValidationError("No enabled devices found. Register one first with 'devices register'.")
      }

      let selected = try promptMultiSelection(
        "Enabled devices",
        items: allDevices,
        display: { device in
          "\(device.name.isEmpty ? "—" : device.name) (\(device.udid.isEmpty ? "—" : device.udid))"
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
      let bundleID: BundleIDs.BundleID
      let bundleIDLabel: String
      if let bundleIdentifier {
        bundleID = try await BundleIDs.find(identifier: bundleIdentifier, client: client)
        bundleIDLabel = bundleIdentifier
      } else {
        bundleID = try await promptBundleID(client: client)
        bundleIDLabel = bundleID.identifier
      }

      // 4. Resolve certificates
      let certIDs: [String]
      if let certificates {
        if certificates.lowercased() == "all" {
          let neededFamily = Profiles.certificateFamily(forProfileType: profileType.rawValue)
          let filtered = try await fetchCertificates(fitting: profileType.rawValue, client: client)
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
          let allDevices = try await Devices.list(statuses: ["ENABLED"], client: client)
          guard !allDevices.isEmpty else {
            throw ValidationError("No enabled devices found in your account.")
          }
          deviceIDs = allDevices.map(\.id)
          print("Using all \(allDevices.count) enabled device(s).")
        } else {
          let identifiers = devices.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
          var resolved: [String] = []
          for identifier in identifiers {
            let device = try await Devices.find(nameOrUDID: identifier, client: client)
            resolved.append(device.id)
          }
          deviceIDs = resolved
        }
      } else if Profiles.needsDevices(profileType.rawValue) {
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

      let created = try await Profiles.create(
        name: profileName, type: profileType.rawValue, bundleIDResourceID: bundleID.id,
        certificateIDs: certIDs, deviceIDs: deviceIDs ?? [], client: client
      )

      print()
      success("Created", "profile '\(created.name.isEmpty ? profileName : created.name)'.")
      print("  UUID:    \(created.uuid ?? "—")")
      print("  State:   \(created.state.map { formatState($0) } ?? "—")")
      print("  Expires: \(created.expirationDate.map { formatDate($0) } ?? "—")")

      if let output, let profileData = created.content {
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
        Deletes and recreates profiles. Without --to-certs, each profile gets every \
        certificate that fits its type (not only the ones it had), so any team member \
        can sign with it. --to-certs names exact certificates by serial number or name \
        (a name must be one certificate); every profile must be able to hold them. \
        Development and ad hoc profiles keep their own enabled devices, or get every \
        enabled device with --all-devices, as far as each fits the profile's platform. \
        All of this is checked before any profile is deleted.

        Without arguments, shows a list of profiles to select from. \
        Use --all-invalid to reissue every invalid profile, or --all to \
        reissue every profile regardless of state.
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

    /// A certificate named by serial number (exact) or by name, which must be one certificate:
    /// a team's distribution certificates share one name.
    static func certificate(_ identifier: String, in certificates: [Certificates.Certificate]) throws -> Certificates.Certificate {
      if let bySerial = certificates.first(where: { $0.serialNumber == identifier }) { return bySerial }
      let byName = certificates.filter { $0.displayName == identifier || $0.name == identifier }
      guard let first = byName.first else { throw ValidationError("No certificate with serial number or name '\(identifier)'.") }
      guard byName.count == 1 else {
        throw ValidationError(
          "\(byName.count) certificates are named '\(identifier)': \(byName.map(certLabel).joined(separator: ", ")). Name it by serial number.")
      }
      return first
    }

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }

      if autoConfirm && name == nil && !all && !allInvalid {
        throw ValidationError("Profile name, --all, or --all-invalid is required when using --yes.")
      }

      let client = try ClientFactory.makeClient()

      let allProfiles = try await Profiles.list(client: client)

      // Determine which profiles to reissue
      let targets: [Profiles.Profile]
      if let name {
        let named = allProfiles.filter { $0.name == name }
        guard let profile = named.first else {
          throw ValidationError("No profile found with name '\(name)'.")
        }
        guard named.count == 1 else {
          throw ValidationError(
            "\(named.count) profiles are named '\(name)' (\(named.map { $0.type ?? "?" }.joined(separator: ", "))); reissue them with --all or interactively.")
        }
        targets = [profile]
      } else if all {
        guard !allProfiles.isEmpty else {
          print("No profiles found.")
          return
        }
        targets = allProfiles
      } else if allInvalid {
        let invalid = allProfiles.filter { $0.state == "INVALID" }
        guard !invalid.isEmpty else {
          print("No invalid profiles found.")
          return
        }
        targets = invalid
      } else {
        // Interactive: show all profiles with status
        let sorted = allProfiles.sorted { $0.name < $1.name }
        guard !sorted.isEmpty else {
          print("No profiles found.")
          return
        }

        targets = try promptMultiSelection(
          "Profiles",
          items: sorted,
          display: { profile in
            let pName = profile.name.isEmpty ? "—" : profile.name
            let pType = profile.type.map { formatState($0) } ?? "—"
            let pState = profile.state ?? "—"
            return "\(pName) (\(pType)) — \(profile.bundleIdentifier ?? "—") [\(pState)]"
          },
          prompt: "Select profile"
        )
      }

      // Certificates: the ones named (each one certificate, and fitting every profile), or each
      // profile's fitting ones. Devices: each profile's own enabled ones, or every enabled device,
      // as far as they fit its type. All of it is settled before any profile is deleted.
      let allCerts = try await Certificates.list(client: client)
      var explicitCerts: [Certificates.Certificate]?
      if let toCerts {
        let identifiers = toCerts.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        explicitCerts = try identifiers.map { try Self.certificate($0, in: allCerts) }
      }
      let enabledDevices = allDevices && targets.contains(where: \.needsDevices)
        ? try await Devices.list(statuses: ["ENABLED"], client: client) : []

      struct Plan {
        let profile: Profiles.Profile
        let certs: [Certificates.Certificate]
        /// Nil for a profile without devices.
        let devices: [Devices.Device]?
      }
      var plans: [Plan] = []
      var unfit: [String] = []
      var skipped: [String] = []
      for profile in targets {
        let type = profile.type ?? ""
        let certs: [Certificates.Certificate]
        if let explicitCerts {
          let wrong = explicitCerts.filter { !Profiles.certificateFits($0.type ?? "", profileType: type) }
          if !wrong.isEmpty {
            unfit.append("\(profile.name.isEmpty ? "—" : profile.name) (\(type)) can't hold \(wrong.map(certLabel).joined(separator: ", "))")
            continue
          }
          certs = explicitCerts
        } else {
          certs = Profiles.certificates(allCerts, fitting: type)
          guard !certs.isEmpty else {
            skipped.append("\(profile.name.isEmpty ? "—" : profile.name) — no \(Profiles.certificateFamily(forProfileType: type).lowercased()) certificate found")
            continue
          }
        }
        var devices: [Devices.Device]?
        if profile.needsDevices {
          let pool = allDevices ? enabledDevices : try await Profiles.devices(profileID: profile.id, client: client)
          let fitting = pool.filter { ($0.status ?? "ENABLED") == "ENABLED" && Profiles.fits($0, profileType: type) }
          // A development or ad hoc profile needs a device: without one the create would fail
          // after the delete.
          guard !fitting.isEmpty else {
            skipped.append("\(profile.name.isEmpty ? "—" : profile.name) — no enabled device fits a \(type) profile")
            continue
          }
          devices = fitting
        }
        plans.append(Plan(profile: profile, certs: certs, devices: devices))
      }
      guard unfit.isEmpty else {
        throw ValidationError(
          "These profiles can't take the certificates named, so nothing was reissued:\n" + unfit.map { "  \($0)" }.joined(separator: "\n"))
      }

      // Display summary
      print()
      print("Profiles to reissue (\(plans.count)):")
      print()
      Table.print(
        headers: ["Name", "Type", "Bundle ID", "Certificates", "Devices"],
        rows: plans.map { plan in
          [plan.profile.name.isEmpty ? "—" : plan.profile.name, plan.profile.type ?? "—", plan.profile.bundleIdentifier ?? "—",
           "\(plan.certs.count)", plan.devices.map { "\($0.count)" } ?? "—"]
        }
      )
      let usedCerts = Swift.Set(plans.flatMap { $0.certs.map(\.id) })
      let certList = allCerts.filter { usedCerts.contains($0.id) }
      if !certList.isEmpty {
        print()
        print("Certificates:")
        for cert in certList {
          print("  \(certLabel(cert)) — \(cert.type.map { formatState($0) } ?? "?")")
        }
      }
      for line in skipped { print("  SKIP \(line)") }
      print()
      guard !plans.isEmpty else {
        print("Done. 0 reissued, \(skipped.count) failed.")
        return
      }

      guard confirm("Reissue \(plans.count) profile(s)? This will delete and recreate each profile. [y/N] ") else {
        cancelled()
        return
      }
      print()

      // Reissue each profile
      var succeeded = 0
      var failed = skipped.count
      for plan in plans {
        if await reissueProfile(
          plan.profile,
          bundleIDIdentifier: plan.profile.bundleIdentifier ?? "—",
          certs: plan.certs,
          overrideDeviceIDs: plan.devices?.map(\.id),
          deviceUDIDs: plan.devices?.map(\.udid),
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

      let client = try ClientFactory.makeClient()

      let profiles: [Profiles.Profile]
      if let name {
        profiles = [try await Profiles.find(name: name, client: client)]
      } else {
        profiles = try promptMultiSelection(
          "Provisioning profiles", items: try await allProfiles(client: client),
          display: profileChoice, prompt: "Select profile"
        )
      }

      print()
      print("Profiles to delete (\(profiles.count)):")
      print()
      Table.print(
        headers: ["Name", "Type", "State"],
        rows: profiles.map { p in
          [
            p.name.isEmpty ? "—" : p.name,
            p.type.map { formatState($0) } ?? "—",
            p.state.map { formatState($0) } ?? "—",
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
        let pName = profile.name.isEmpty ? "—" : profile.name
        do {
          try await Profiles.delete(id: profile.id, client: client)
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
func promptProfile(client: ASCClient) async throws -> Profiles.Profile {
  try promptSelection(
    "Provisioning profiles", items: try await allProfiles(client: client),
    display: profileChoice, prompt: "Select profile"
  )
}

/// The account's profiles by name, for a picker.
private func allProfiles(client: ASCClient) async throws -> [Profiles.Profile] {
  let profiles = try await Profiles.list(client: client)
  guard !profiles.isEmpty else { throw ValidationError("No provisioning profiles found in your account.") }
  return profiles.sorted { $0.name < $1.name }
}

/// A profile in a picker: name, type and state.
private func profileChoice(_ profile: Profiles.Profile) -> String {
  "\(profile.name.isEmpty ? "—" : profile.name) (\(profile.type.map { formatState($0) } ?? "—"), \(profile.state.map { formatState($0) } ?? "—"))"
}

/// Fetches all signing certificates in the account; with `profileType`, the ones that can go in a
/// profile of that type (`Profiles.certificateFits`).
func fetchCertificates(fitting profileType: String? = nil, client: ASCClient) async throws -> [Certificates.Certificate] {
  let allCerts = try await Certificates.list(client: client)
  guard let profileType else { return allCerts }
  return Profiles.certificates(allCerts, fitting: profileType)
}

/// Reissues `profile` (`Profiles.reissue`) and prints an OK/FAIL/SKIP line, plus a recovery
/// command when the old profile was deleted but the new one couldn't be created. Returns true on
/// success.
func reissueProfile(
  _ profile: Profiles.Profile,
  bundleIDIdentifier: String,
  certs: [Certificates.Certificate],
  overrideDeviceIDs: [String]? = nil,
  deviceUDIDs: [String]? = nil,
  verb: String,
  client: ASCClient
) async -> Bool {
  let profileName = profile.name.isEmpty ? "—" : profile.name
  do {
    let created = try await Profiles.reissue(
      profile, certificateIDs: certs.map(\.id), deviceIDs: overrideDeviceIDs, client: client)
    let newExpiry = created.expirationDate.map { formatDate($0) } ?? "—"
    print("  OK   \(profileName) — \(verb) with \(certs.count) cert(s) (expires \(newExpiry))")
    return true
  } catch {
    switch error {
      case .unknownType, .noBundleID:
        print("  SKIP \(profileName) — \(error.localizedDescription)")
      case .devicesUnreadable(let underlying):
        print("  FAIL \(profileName) — could not fetch its devices: \(describeError(underlying))")
      case .deleteFailed(let underlying) where ASCDryRunStop.from(underlying) != nil:
        print("  DRY  \(profileName) — not sent (dry run): the delete and the create with \(certs.count) cert(s)")
      case .deleteFailed(let underlying):
        print("  FAIL \(profileName) — delete failed: \(describeError(underlying))")
      case .createFailed(let underlying, let readUDIDs):
        let certSpec = certs.compactMap(\.serialNumber).joined(separator: ",")
        let udids = deviceUDIDs ?? readUDIDs
        let devicesArg = udids.isEmpty ? "" : " --devices \(udids.joined(separator: ","))"
        print("  FAIL \(profileName) — recreate failed: \(describeError(underlying))")
        print("         Recovery: ascelerate profiles create --name \"\(profileName)\" --type \(profile.type ?? "") --bundle-id \(bundleIDIdentifier) --certificates \(certSpec)\(devicesArg)")
    }
    return false
  }
}

/// Formats a certificate as "DisplayName (Serial)" for clear identification.
func certLabel(_ cert: Certificates.Certificate) -> String {
  let name = cert.displayName ?? "—"
  let serial = cert.serialNumber ?? cert.id
  return "\(name) (\(serial))"
}
