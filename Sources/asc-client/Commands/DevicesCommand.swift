import AppStoreAPI
import AppStoreConnect
import ArgumentParser
import Foundation

struct DevicesCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "devices",
    abstract: "Manage registered devices.",
    subcommands: [List.self, Info.self, Register.self, Update.self]
  )

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List registered devices."
    )

    @Option(name: .long, help: "Filter by device name.")
    var name: String?

    @Option(name: .long, help: "Filter by platform (IOS, MAC_OS, UNIVERSAL).")
    var platform: String?

    @Option(name: .long, help: "Filter by status (ENABLED, DISABLED).")
    var status: String?

    func run() async throws {
      let client = try ClientFactory.makeClient()

      let filterPlatform: [Resources.V1.Devices.FilterPlatform]?
      if let platform {
        guard let val = Resources.V1.Devices.FilterPlatform(rawValue: platform.uppercased()) else {
          let valid = Resources.V1.Devices.FilterPlatform.allCases.map(\.rawValue).joined(separator: ", ")
          throw ValidationError("Invalid platform '\(platform)'. Valid values: \(valid)")
        }
        filterPlatform = [val]
      } else {
        filterPlatform = nil
      }

      let filterStatus: [Resources.V1.Devices.FilterStatus]?
      if let status {
        guard let val = Resources.V1.Devices.FilterStatus(rawValue: status.uppercased()) else {
          let valid = Resources.V1.Devices.FilterStatus.allCases.map(\.rawValue).joined(separator: ", ")
          throw ValidationError("Invalid status '\(status)'. Valid values: \(valid)")
        }
        filterStatus = [val]
      } else {
        filterStatus = nil
      }

      var rows: [[String]] = []
      let request = Resources.v1.devices.get(
        filterName: name.map { [$0] },
        filterPlatform: filterPlatform,
        filterStatus: filterStatus,
        limit: 200
      )

      for try await page in client.pages(request) {
        for device in page.data {
          let attrs = device.attributes
          rows.append([
            attrs?.name ?? "—",
            attrs?.udid ?? "—",
            attrs?.platform.map { "\($0)" } ?? "—",
            attrs?.deviceClass.map { "\($0)" } ?? "—",
            attrs?.status.map { "\($0)" } ?? "—",
            attrs?.model ?? "—",
            attrs?.addedDate.map { formatDate($0) } ?? "—",
          ])
        }
      }

      if rows.isEmpty {
        print("No devices found.")
      } else {
        Table.print(
          headers: ["Name", "UDID", "Platform", "Class", "Status", "Model", "Added"],
          rows: rows
        )
      }
    }
  }

  struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Show details for a device."
    )

    @Argument(help: "Device name or UDID.")
    var nameOrUDID: String?

    func run() async throws {
      let client = try ClientFactory.makeClient()

      let device: Device
      if let nameOrUDID {
        device = try await findDevice(nameOrUDID: nameOrUDID, client: client)
      } else {
        device = try await promptDevice(client: client)
      }

      let attrs = device.attributes
      print("Name:     \(attrs?.name ?? "—")")
      print("UDID:     \(attrs?.udid ?? "—")")
      print("Platform: \(attrs?.platform.map { "\($0)" } ?? "—")")
      print("Class:    \(attrs?.deviceClass.map { "\($0)" } ?? "—")")
      print("Status:   \(attrs?.status.map { "\($0)" } ?? "—")")
      print("Model:    \(attrs?.model ?? "—")")
      print("Added:    \(attrs?.addedDate.map { formatDate($0) } ?? "—")")
    }
  }

  struct Register: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Register a new device."
    )

    @Option(name: .long, help: "Device name.")
    var name: String?

    @Option(name: .long, help: "Device UDID.")
    var udid: String?

    @Option(name: .long, help: "Platform (IOS, MAC_OS).")
    var platform: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }

      if autoConfirm {
        if name == nil { throw ValidationError("--name is required when using --yes.") }
        if udid == nil { throw ValidationError("--udid is required when using --yes.") }
        if platform == nil { throw ValidationError("--platform is required when using --yes.") }
      }

      let client = try ClientFactory.makeClient()

      let deviceName = name ?? promptText("Device name: ")
      let deviceUDID = udid ?? promptText("Device UDID: ")

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

      print("Register device:")
      print("  Name:     \(deviceName)")
      print("  UDID:     \(deviceUDID)")
      print("  Platform: \(platformValue)")
      print()

      guard confirm("Register this device? [y/N] ") else {
        print("Cancelled.")
        return
      }

      let response = try await client.send(
        Resources.v1.devices.post(
          DeviceCreateRequest(data: .init(
            attributes: .init(
              name: deviceName,
              platform: platformValue,
              udid: deviceUDID
            )
          ))
        )
      )

      let attrs = response.data.attributes
      print()
      print("Registered device '\(attrs?.name ?? deviceName)'.")
      print("  UDID:   \(attrs?.udid ?? deviceUDID)")
      print("  Status: \(attrs?.status.map { "\($0)" } ?? "—")")
    }
  }

  struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Update a device name or status."
    )

    @Argument(help: "Device name or UDID.")
    var nameOrUDID: String?

    @Option(name: .long, help: "New device name.")
    var name: String?

    @Option(name: .long, help: "New status (ENABLED, DISABLED).")
    var status: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func validate() throws {
      if nameOrUDID != nil && name == nil && status == nil {
        throw ValidationError("Provide at least --name or --status to update.")
      }
    }

    private func promptUpdates(currentName: String, currentStatus: String) throws -> (newName: String?, newStatus: DeviceUpdateRequest.Data.Attributes.Status?) {
      let statusTypes = DeviceUpdateRequest.Data.Attributes.Status.allCases
      print("What would you like to update?")
      print("  [1] Name")
      print("  [2] Status")
      print("  [3] Both")
      print()
      print("Select (1-3): ", terminator: "")
      guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
            let choice = Int(input),
            choice >= 1, choice <= 3 else {
        throw ValidationError("Invalid selection.")
      }

      var newName: String?
      var newStatus: DeviceUpdateRequest.Data.Attributes.Status?

      if choice == 1 || choice == 3 {
        print("New name [\(currentName)]: ", terminator: "")
        if let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
          newName = line
        } else {
          throw ValidationError("Name cannot be empty.")
        }
      }

      if choice == 2 || choice == 3 {
        print("Status:")
        for (i, s) in statusTypes.enumerated() {
          print("  [\(i + 1)] \(s.rawValue)")
        }
        print()
        print("Select status (1-\(statusTypes.count)): ", terminator: "")
        guard let sInput = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              let sChoice = Int(sInput),
              sChoice >= 1, sChoice <= statusTypes.count else {
          throw ValidationError("Invalid selection.")
        }
        newStatus = statusTypes[sChoice - 1]
      }

      return (newName, newStatus)
    }

    func run() async throws {
      if yes { autoConfirm = true }

      if autoConfirm && nameOrUDID == nil {
        throw ValidationError("Device name or UDID argument is required when using --yes.")
      }

      let client = try ClientFactory.makeClient()

      let device: Device
      if let nameOrUDID {
        device = try await findDevice(nameOrUDID: nameOrUDID, client: client)
      } else {
        device = try await promptDevice(client: client)
      }

      let newName: String?
      let statusValue: DeviceUpdateRequest.Data.Attributes.Status?

      if name != nil || status != nil {
        // Flags provided explicitly
        newName = name
        if let status {
          guard let val = DeviceUpdateRequest.Data.Attributes.Status(rawValue: status.uppercased()) else {
            let valid = DeviceUpdateRequest.Data.Attributes.Status.allCases.map(\.rawValue).joined(separator: ", ")
            throw ValidationError("Invalid status '\(status)'. Valid values: \(valid)")
          }
          statusValue = val
        } else {
          statusValue = nil
        }
      } else {
        // Interactive: ask what to update
        let currentName = device.attributes?.name ?? "—"
        let currentStatus = device.attributes?.status.map { "\($0)" } ?? "—"
        let updates = try promptUpdates(currentName: currentName, currentStatus: currentStatus)
        newName = updates.newName
        statusValue = updates.newStatus
      }

      let currentName = device.attributes?.name ?? "—"
      print("Device: \(currentName) (\(device.attributes?.udid ?? "—"))")
      if let newName { print("  Name:   \(currentName) → \(newName)") }
      if let statusValue { print("  Status: \(device.attributes?.status.map { "\($0)" } ?? "—") → \(statusValue)") }
      print()

      guard confirm("Update this device? [y/N] ") else {
        print("Cancelled.")
        return
      }

      let response = try await client.send(
        Resources.v1.devices.id(device.id).patch(
          DeviceUpdateRequest(data: .init(
            id: device.id,
            attributes: .init(
              name: newName,
              status: statusValue
            )
          ))
        )
      )

      let attrs = response.data.attributes
      print()
      print("Updated device '\(attrs?.name ?? currentName)'.")
    }
  }
}

/// Prompts the user to select a device from a numbered list.
func promptDevice(client: AppStoreConnectClient) async throws -> Device {
  var allDevices: [Device] = []
  for try await page in client.pages(Resources.v1.devices.get(limit: 200)) {
    allDevices.append(contentsOf: page.data)
  }
  guard !allDevices.isEmpty else {
    throw ValidationError("No devices found in your account.")
  }
  allDevices.sort { ($0.attributes?.name ?? "") < ($1.attributes?.name ?? "") }

  print("Devices:")
  for (i, device) in allDevices.enumerated() {
    let name = device.attributes?.name ?? "—"
    let udid = device.attributes?.udid ?? "—"
    let status = device.attributes?.status.map { "\($0)" } ?? "—"
    print("  [\(i + 1)] \(name) (\(udid)) — \(status)")
  }
  print()
  print("Select device (1-\(allDevices.count)): ", terminator: "")
  guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
        let choice = Int(input),
        choice >= 1, choice <= allDevices.count else {
    throw ValidationError("Invalid selection.")
  }
  return allDevices[choice - 1]
}

/// Looks up a device by UDID first, then falls back to name.
func findDevice(nameOrUDID: String, client: AppStoreConnectClient) async throws -> Device {
  // Try UDID first
  let byUDID = try await client.send(
    Resources.v1.devices.get(filterUdid: [nameOrUDID], limit: 1)
  )
  if let device = byUDID.data.first {
    return device
  }

  // Fall back to name
  let byName = try await client.send(
    Resources.v1.devices.get(filterName: [nameOrUDID], limit: 200)
  )
  // Name filter may return partial matches, find exact match
  if let device = byName.data.first(where: { $0.attributes?.name == nameOrUDID }) {
    return device
  }
  // If only one result, use it even if not exact (fuzzy match by API)
  if byName.data.count == 1 {
    return byName.data[0]
  }

  throw DeviceLookupError.notFound(nameOrUDID)
}

enum DeviceLookupError: LocalizedError {
  case notFound(String)

  var errorDescription: String? {
    switch self {
    case .notFound(let identifier):
      return "No device found matching '\(identifier)'. Use UDID or exact device name."
    }
  }
}
