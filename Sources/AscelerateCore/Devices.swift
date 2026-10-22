import ASCKit
import Foundation

/// Registered devices (`devices`): the iPhones, iPads, Macs and others development and ad hoc
/// profiles install on.
public enum Devices {
  public struct Device: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let udid: String
    /// `IOS`, `MAC_OS`, `UNIVERSAL`.
    public let platform: String?
    /// `IPHONE`, `IPAD`, `MAC`, `APPLE_WATCH`, `APPLE_TV`, `APPLE_VISION_PRO`, ...
    public let deviceClass: String?
    public let model: String?
    /// `ENABLED` or `DISABLED`.
    public let status: String?
    public let addedDate: Date?
  }

  public enum LookupError: LocalizedError {
    case notFound(String)

    public var errorDescription: String? {
      switch self {
        case .notFound(let identifier): "No device found matching '\(identifier)'."
      }
    }
  }

  /// The team's devices, optionally only the enabled ones.
  public static func list(enabledOnly: Bool = false, client: ASCClient) async throws -> [Device] {
    try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.devicesGetCollection(query: .init(filterStatus: enabledOnly ? [.enabled] : nil, limit: 200)).ok.body.json
      }
    }.flatMap(\.data).map(Device.init)
  }

  /// A device by UDID, else by exact name (or the only partial match): Apple's name filter can
  /// match partially.
  public static func find(nameOrUDID: String, client: ASCClient) async throws -> Device {
    if let device = try await client.devicesGetCollection(query: .init(filterUdid: [nameOrUDID], limit: 1)).ok.body.json.data.first {
      return Device(device)
    }
    let byName = try await client.devicesGetCollection(query: .init(filterName: [nameOrUDID], limit: 200)).ok.body.json.data
    if let device = byName.first(where: { $0.attributes?.name == nameOrUDID }) {
      return Device(device)
    }
    if byName.count == 1 {
      return Device(byName[0])
    }
    throw LookupError.notFound(nameOrUDID)
  }
}

extension Devices.Device {
  init(_ device: Components.Schemas.Device) {
    let attributes = device.attributes
    self.init(
      id: device.id, name: attributes?.name ?? "", udid: attributes?.udid ?? "", platform: attributes?.platform,
      deviceClass: attributes?.deviceClass, model: attributes?.model, status: attributes?.status,
      addedDate: attributes?.addedDate)
  }
}
