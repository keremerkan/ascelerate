import ASCKit
import Foundation

/// Provisioning profiles (`profiles`): an App ID with the certificates that may sign it and, for
/// development and ad hoc profiles, the devices it installs on. A profile can't be edited: a new
/// certificate or device, or a capability change on its App ID, takes a new profile (reissuing
/// is delete and create with the same name). Revoking a certificate in it or changing the App
/// ID's capabilities makes it INVALID; the API doesn't list expired ones.
public enum Profiles {
  public struct Profile: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// `ASCEnum.ProfileCreateRequestProfileType` raw value (`IOS_APP_DEVELOPMENT`, `MAC_APP_STORE`, ...).
    public let type: String?
    /// `ACTIVE` or `INVALID`.
    public let state: String?
    /// `IOS`, `MAC_OS`, ...
    public let platform: String?
    public let uuid: String?
    public let createdDate: Date?
    public let expirationDate: Date?
    /// The profile itself (a .mobileprovision or .provisionprofile file).
    public let content: Data?
    /// The bundle ID's resource ID.
    public let bundleIDResourceID: String?
    /// The bundle ID, when the list was read with it.
    public let bundleIdentifier: String?

    public var isActive: Bool { state == "ACTIVE" }
    /// Development and ad hoc profiles list the devices they install on.
    public var needsDevices: Bool { type.map(Profiles.needsDevices) ?? false }
  }

  /// A profile's certificates and devices.
  public struct Contents: Sendable {
    public let certificates: [Certificates.Certificate]
    public let devices: [Devices.Device]
  }

  public enum LookupError: LocalizedError {
    case notFound(String)
    case unknown(kind: String, value: String)

    public var errorDescription: String? {
      switch self {
        case .notFound(let name):
          "No provisioning profile found matching '\(name)'.\nInfo: Expired profiles are not visible to the API — delete them from the Apple Developer website first, then recreate."
        case .unknown(let kind, let value): "Unknown \(kind) '\(value)'."
      }
    }
  }

  /// Why reissuing a profile stopped: before anything changed, or after the old one was deleted
  /// (then the profile is gone until it's created again).
  public enum ReissueError: LocalizedError {
    case unknownType(String)
    case noBundleID
    case devicesUnreadable(any Error)
    case deleteFailed(any Error)
    /// The old profile was deleted, but the new one couldn't be created.
    case createFailed(any Error, deviceUDIDs: [String])

    public var errorDescription: String? {
      switch self {
        case .unknownType(let type): "unknown profile type '\(type)'"
        case .noBundleID: "could not resolve its bundle ID"
        case .devicesUnreadable(let error): "could not fetch its devices: \(error.localizedDescription)"
        case .deleteFailed(let error): "delete failed: \(error.localizedDescription)"
        case .createFailed(let error, _): "recreate failed: \(error.localizedDescription)"
      }
    }
  }

  // MARK: Certificate families

  /// Groups certificate types that serve the same profiles: Apple replaced the platform types
  /// (IOS_DISTRIBUTION, MAC_APP_DISTRIBUTION) with universal ones (DISTRIBUTION), but older
  /// certificates keep theirs.
  public static func certificateFamily(_ certificateType: String) -> String {
    switch ASCEnum.CertificateType(rawValue: certificateType) {
      case .distribution, .iosDistribution, .macAppDistribution, .macInstallerDistribution: "Distribution"
      case .development, .iosDevelopment, .macAppDevelopment: "Development"
      case .developerIdApplication, .developerIdApplicationG2: "Developer ID Application"
      case .developerIdKext, .developerIdKextG2: "Developer ID Kext"
      default: certificateType
    }
  }

  /// The certificate family a profile type is made with.
  public static func certificateFamily(forProfileType profileType: String) -> String {
    if profileType.contains("DIRECT") { return "Developer ID Application" }
    if profileType.contains("STORE") || profileType.contains("ADHOC") || profileType.contains("INHOUSE") { return "Distribution" }
    return "Development"
  }

  public static func needsDevices(_ profileType: String) -> Bool {
    profileType.contains("DEVELOPMENT") || profileType.contains("ADHOC")
  }

  /// The team's certificates by family.
  public static func certificatesByFamily(client: ASCClient) async throws -> [String: [Certificates.Certificate]] {
    Dictionary(grouping: try await Certificates.list(client: client).filter { $0.type != nil }) { certificateFamily($0.type!) }
  }

  // MARK: Reading

  /// The team's profiles with their bundle IDs, optionally by name, types or states.
  public static func list(
    name: String? = nil, types: [String]? = nil, states: [String]? = nil, client: ASCClient
  ) async throws -> [Profile] {
    typealias Query = Operations.ProfilesGetCollection.Input.Query
    let typeFilter = try types?.map { raw in
      guard let value = Query.FilterProfileTypePayloadPayload(rawValue: raw) else { throw LookupError.unknown(kind: "type", value: raw) }
      return value
    }
    let stateFilter = try states?.map { raw in
      guard let value = Query.FilterProfileStatePayloadPayload(rawValue: raw) else { throw LookupError.unknown(kind: "state", value: raw) }
      return value
    }
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.profilesGetCollection(query: .init(
          filterName: name.map { [$0] }, filterProfileType: typeFilter, filterProfileState: stateFilter,
          limit: 200, include: [.bundleId]
        )).ok.body.json
      }
    }
    var identifiers: [String: String] = [:]
    for case .bundleIds(let bundleID) in pages.flatMap({ $0.included ?? [] }) {
      identifiers[bundleID.id] = bundleID.attributes?.identifier
    }
    return pages.flatMap(\.data).map { profile in
      Profile(profile, bundleIdentifier: (profile.relationships?.bundleId?.data?.id).flatMap { identifiers[$0] })
    }
  }

  /// A profile by exact name (or the only partial match): Apple's name filter can match partially.
  public static func find(name: String, client: ASCClient) async throws -> Profile {
    let profiles = try await client.profilesGetCollection(query: .init(filterName: [name], limit: 200)).ok.body.json.data
    if let profile = profiles.first(where: { $0.attributes?.name == name }) {
      return Profile(profile, bundleIdentifier: nil)
    }
    if profiles.count == 1 {
      return Profile(profiles[0], bundleIdentifier: nil)
    }
    throw LookupError.notFound(name)
  }

  /// A profile's bundle ID.
  public static func bundleID(profileID: String, client: ASCClient) async throws -> BundleIDs.BundleID {
    BundleIDs.BundleID(try await client.profilesBundleIdGetToOneRelated(path: .init(id: profileID)).ok.body.json.data, capabilityTypes: nil)
  }

  /// A profile's certificates.
  public static func certificates(profileID: String, client: ASCClient) async throws -> [Certificates.Certificate] {
    try await client.profilesCertificatesGetToManyRelated(path: .init(id: profileID), query: .init(limit: 200)).ok.body.json.data
      .map(Certificates.Certificate.init)
  }

  /// A profile's devices, every page of them (the list's included linkages stop at 50).
  public static func devices(profileID: String, client: ASCClient) async throws -> [Devices.Device] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.profilesDevicesGetToManyRelated(path: .init(id: profileID), query: .init(limit: 200)).ok.body.json
    }.flatMap(\.data).map(Devices.Device.init)
  }

  // MARK: Writing

  /// Creates a profile; devices are sent only when there are any.
  public static func create(
    name: String, type: String, bundleIDResourceID: String, certificateIDs: [String], deviceIDs: [String] = [],
    client: ASCClient
  ) async throws -> Profile {
    typealias Relationships = Components.Schemas.ProfileCreateRequest.DataPayload.RelationshipsPayload
    let request = Components.Schemas.ProfileCreateRequest(data: .init(
      attributes: .init(name: name, profileType: type),
      relationships: Relationships(
        bundleId: .init(data: .init(id: bundleIDResourceID, _type: "bundleIds")),
        certificates: .init(data: certificateIDs.map { .init(id: $0, _type: "certificates") }),
        devices: deviceIDs.isEmpty ? nil : .init(data: deviceIDs.map { .init(id: $0, _type: "devices") })
      ),
      _type: "profiles"
    ))
    return Profile(try await client.profilesCreateInstance(body: .json(request)).created.body.json.data, bundleIdentifier: nil)
  }

  public static func delete(id: String, client: ASCClient) async throws {
    _ = try await client.profilesDeleteInstance(path: .init(id: id)).noContent
  }

  /// Makes a profile again with these certificates: deletes it and creates it with the same
  /// name, type and bundle ID, and its devices (read before the delete) unless `deviceIDs` is
  /// given.
  public static func reissue(
    _ profile: Profile, certificateIDs: [String], deviceIDs: [String]? = nil, client: ASCClient
  ) async throws(ReissueError) -> Profile {
    guard let type = profile.type, ASCEnum.ProfileCreateRequestProfileType(rawValue: type) != nil else {
      throw .unknownType(profile.type ?? "")
    }
    guard let bundleIDResourceID = profile.bundleIDResourceID else { throw .noBundleID }
    var devices: [String] = []
    var udids: [String] = []
    if needsDevices(type) {
      if let deviceIDs {
        devices = deviceIDs
      } else {
        do {
          let read = try await self.devices(profileID: profile.id, client: client)
          devices = read.map(\.id)
          udids = read.map(\.udid)
        } catch {
          throw .devicesUnreadable(error)
        }
      }
    }
    do {
      try await delete(id: profile.id, client: client)
    } catch {
      throw .deleteFailed(error)
    }
    do {
      return try await create(
        name: profile.name, type: type, bundleIDResourceID: bundleIDResourceID, certificateIDs: certificateIDs,
        deviceIDs: devices, client: client)
    } catch {
      throw .createFailed(error, deviceUDIDs: udids)
    }
  }
}

extension Profiles.Profile {
  init(_ profile: Components.Schemas.Profile, bundleIdentifier: String?) {
    let attributes = profile.attributes
    self.init(
      id: profile.id, name: attributes?.name ?? "", type: attributes?.profileType, state: attributes?.profileState,
      platform: attributes?.platform, uuid: attributes?.uuid, createdDate: attributes?.createdDate,
      expirationDate: attributes?.expirationDate, content: attributes?.profileContent.flatMap { Data(base64Encoded: $0) },
      bundleIDResourceID: profile.relationships?.bundleId?.data?.id, bundleIdentifier: bundleIdentifier)
  }
}
