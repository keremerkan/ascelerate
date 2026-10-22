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
    case unknown(kind: String, value: String)

    public var errorDescription: String? {
      switch self {
        case .notFound(let identifier): "No device found matching '\(identifier)'. Use UDID or exact device name."
        case .unknown(let kind, let value): "Unknown \(kind) '\(value)'."
      }
    }
  }

  /// Whether a UDID has one of Apple's forms: 40 hex digits (older iPhones and iPads), 8 and 16
  /// hex digits joined by a hyphen (newer devices and Apple silicon Macs), or a UUID (Intel Macs).
  public static func isValidUDID(_ udid: String) -> Bool {
    udid.wholeMatch(of: /[0-9a-fA-F]{40}|[0-9a-fA-F]{8}-[0-9a-fA-F]{16}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/) != nil
  }

  /// The team's devices, optionally by name (Apple's filter can match partially), platforms
  /// (`IOS`, `MAC_OS`, `UNIVERSAL`) or statuses (`ENABLED`, `DISABLED`).
  public static func list(
    name: String? = nil, platforms: [String]? = nil, statuses: [String]? = nil, client: ASCClient
  ) async throws -> [Device] {
    typealias Query = Operations.DevicesGetCollection.Input.Query
    let platformFilter = try platforms?.map { raw in
      guard let value = Query.FilterPlatformPayloadPayload(rawValue: raw) else { throw LookupError.unknown(kind: "platform", value: raw) }
      return value
    }
    let statusFilter = try statuses?.map { raw in
      guard let value = Query.FilterStatusPayloadPayload(rawValue: raw) else { throw LookupError.unknown(kind: "status", value: raw) }
      return value
    }
    return try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.devicesGetCollection(query: .init(
          filterName: name.map { [$0] }, filterPlatform: platformFilter, filterStatus: statusFilter, limit: 200
        )).ok.body.json
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

  /// Registers a device. It counts toward the membership year's limit for its kind even if it's
  /// disabled later.
  public static func register(name: String, udid: String, platform: String, client: ASCClient) async throws -> Device {
    Device(try await client.devicesCreateInstance(body: .json(.init(data: .init(
      attributes: .init(name: name, platform: platform, udid: udid), _type: "devices"
    )))).created.body.json.data)
  }

  /// Renames a device, or enables or disables it (`ENABLED`, `DISABLED`); Apple has no delete.
  public static func update(id: String, name: String? = nil, status: String? = nil, client: ASCClient) async throws -> Device {
    Device(try await client.devicesUpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
      attributes: .init(name: name, status: status), id: id, _type: "devices"
    )))).ok.body.json.data)
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
