import ArgumentParser
import ASCKit
import AscelerateCore
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

      typealias Query = Operations.DevicesGetCollection.Input.Query
      let filterPlatform: [Query.FilterPlatformPayloadPayload]? = try parseFilter(platform, name: "platform")
      let filterStatus: [Query.FilterStatusPayloadPayload]? = try parseFilter(status, name: "status")

      let devices = try await Devices.list(
        name: name, platforms: filterPlatform?.map(\.rawValue), statuses: filterStatus?.map(\.rawValue), client: client)

      if devices.isEmpty {
        print("No devices found.")
      } else {
        Table.print(
          headers: ["Name", "UDID", "Platform", "Class", "Status", "Model", "Added"],
          rows: devices.map { device in
            [
              dash(device.name),
              dash(device.udid),
              device.platform.map { formatState($0) } ?? "—",
              device.deviceClass.map { formatState($0) } ?? "—",
              device.status.map { formatState($0) } ?? "—",
              device.model ?? "—",
              device.addedDate.map { formatDate($0) } ?? "—",
            ]
          }
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

      let device = if let nameOrUDID {
        try await Devices.find(nameOrUDID: nameOrUDID, client: client)
      } else {
        try await promptDevice(client: client)
      }

      print("Name:     \(dash(device.name))")
      print("UDID:     \(dash(device.udid))")
      print("Platform: \(device.platform.map { formatState($0) } ?? "—")")
      print("Class:    \(device.deviceClass.map { formatState($0) } ?? "—")")
      print("Status:   \(device.status.map { formatState($0) } ?? "—")")
      print("Model:    \(device.model ?? "—")")
      print("Added:    \(device.addedDate.map { formatDate($0) } ?? "—")")
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

      let deviceName = try name ?? promptText("Device name: ")
      let deviceUDID = try udid ?? promptText("Device UDID: ")

      let platformValue: ASCEnum.BundleIdPlatform
      if let platform {
        platformValue = try parseEnum(platform, name: "platform")
      } else {
        platformValue = try promptPlatform()
      }

      print("Register device:")
      print("  Name:     \(deviceName)")
      print("  UDID:     \(deviceUDID)")
      print("  Platform: \(formatState(platformValue.rawValue))")
      print()

      guard confirm("Register this device? [y/N] ") else {
        cancelled()
        return
      }

      let device = try await Devices.register(
        name: deviceName, udid: deviceUDID, platform: platformValue.rawValue, client: client)

      print()
      success("Registered", "device '\(device.name.isEmpty ? deviceName : device.name)'.")
      print("  UDID:   \(device.udid.isEmpty ? deviceUDID : device.udid)")
      print("  Status: \(device.status.map { formatState($0) } ?? "—")")
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

    private func promptUpdates(currentName: String, currentStatus: String) throws -> (newName: String?, newStatus: ASCEnum.DeviceUpdateRequestStatus?) {
      let statusTypes = ASCEnum.DeviceUpdateRequestStatus.allCases
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
      var newStatus: ASCEnum.DeviceUpdateRequestStatus?

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

      let device = if let nameOrUDID {
        try await Devices.find(nameOrUDID: nameOrUDID, client: client)
      } else {
        try await promptDevice(client: client)
      }

      let newName: String?
      let statusValue: ASCEnum.DeviceUpdateRequestStatus?

      if name != nil || status != nil {
        // Flags provided explicitly
        newName = name
        if let status {
          statusValue = try parseEnum(status, name: "status")
        } else {
          statusValue = nil
        }
      } else {
        // Interactive: ask what to update
        let currentName = dash(device.name)
        let currentStatus = device.status.map { formatState($0) } ?? "—"
        let updates = try promptUpdates(currentName: currentName, currentStatus: currentStatus)
        newName = updates.newName
        statusValue = updates.newStatus
      }

      let currentName = dash(device.name)
      print("Device: \(currentName) (\(dash(device.udid)))")
      if let newName { print("  Name:   \(currentName) → \(newName)") }
      if let statusValue { print("  Status: \(device.status.map { formatState($0) } ?? "—") → \(formatState(statusValue.rawValue))") }
      print()

      guard confirm("Update this device? [y/N] ") else {
        cancelled()
        return
      }

      let updated = try await Devices.update(id: device.id, name: newName, status: statusValue?.rawValue, client: client)

      print()
      success("Updated", "device '\(updated.name.isEmpty ? currentName : updated.name)'.")
    }
  }
}

/// Prompts the user to select a device from a numbered list.
func promptDevice(client: ASCClient) async throws -> Devices.Device {
  let devices = try await Devices.list(client: client)
  guard !devices.isEmpty else { throw ValidationError("No devices found in your account.") }
  return try promptSelection(
    "Devices", items: devices.sorted { $0.name < $1.name },
    display: { "\(dash($0.name)) (\(dash($0.udid))) — \($0.status.map { formatState($0) } ?? "—")" },
    prompt: "Select device"
  )
}

/// An attribute Apple left out, as the tables show it.
private func dash(_ value: String) -> String {
  value.isEmpty ? "—" : value
}
