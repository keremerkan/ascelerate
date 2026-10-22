import ASCKit
import Foundation

/// Bundle identifiers (`bundleIds`, the developer portal's App IDs) and their capabilities.
public enum BundleIDs {
  public struct BundleID: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// `com.example.MyApp`, or a wildcard such as `com.example.*`.
    public let identifier: String
    public let name: String
    /// `IOS`, `MAC_OS` or `UNIVERSAL`.
    public let platform: String?
    /// The App ID prefix: the team ID, or an older ID's own prefix.
    public let seedID: String?
    /// The enabled capabilities' types, when the list was read with them (`list(withCapabilities:)`).
    public let capabilityTypes: [String]?

    public var isWildcard: Bool { identifier.hasSuffix("*") }
  }

  /// A capability enabled on a bundle ID, with its settings (key → chosen option keys).
  public struct Capability: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// `ASCEnum.CapabilityType` raw value; Apple also sends types the spec doesn't list
    /// (`ENHANCED_SECURITY`).
    public let type: String
    public let settings: [Setting]
  }

  public struct Setting: Codable, Hashable, Sendable {
    /// `DATA_PROTECTION_PERMISSION_LEVEL`, `ICLOUD_VERSION`, `APPLE_ID_AUTH_APP_CONSENT`.
    public let key: String
    /// The chosen options' keys (`COMPLETE_PROTECTION`, `XCODE_6`, `PRIMARY_APP_CONSENT`).
    public let options: [String]

    public init(key: String, options: [String]) {
      self.key = key
      self.options = options
    }
  }

  /// The developer portal's limits (read from its Register an App ID form, 2026-10-22): a
  /// description of ASCII letters, digits, spaces, hyphens, periods and apostrophes, at most 50
  /// characters; a bundle ID of ASCII letters, digits, hyphens and periods, at most 155, which a
  /// wildcard App ID ends with `*`.
  public static let maxNameLength = 50
  public static let maxIdentifierLength = 155

  public static func isValidName(_ name: String) -> Bool {
    !name.isEmpty && name.count <= maxNameLength
      && name.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || $0.properties.numericType != nil || " .'-".unicodeScalars.contains($0)) }
  }

  public static func isValidIdentifier(_ identifier: String, wildcard: Bool) -> Bool {
    let stem = wildcard ? identifier.dropLast() : Substring(identifier)
    guard !stem.isEmpty || !wildcard, identifier.count <= maxIdentifierLength, !identifier.isEmpty else { return false }
    if wildcard, identifier.last != "*" { return false }
    return stem.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || $0.properties.numericType != nil || ".-".unicodeScalars.contains($0)) }
  }

  public enum LookupError: LocalizedError {
    case notFound(String)
    case unknownPlatform(String)

    public var errorDescription: String? {
      switch self {
        case .notFound(let identifier): "No bundle identifier found matching '\(identifier)'."
        case .unknownPlatform(let platform): "Unknown platform '\(platform)'."
      }
    }
  }

  /// The team's bundle IDs, optionally on a platform or starting with an identifier, with their
  /// capabilities' types when asked (in the same request; settings come with `capabilities`).
  public static func list(
    platform: String? = nil, identifierPrefix: String? = nil, withCapabilities: Bool = false, client: ASCClient
  ) async throws -> [BundleID] {
    typealias PlatformFilter = Operations.BundleIdsGetCollection.Input.Query.FilterPlatformPayloadPayload
    let platformFilter = try platform.map { raw in
      guard let value = PlatformFilter(rawValue: raw) else { throw LookupError.unknownPlatform(raw) }
      return [value]
    }
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.bundleIdsGetCollection(query: .init(
          filterPlatform: platformFilter, filterIdentifier: identifierPrefix.map { [$0] }, limit: 200,
          include: withCapabilities ? [.bundleIdCapabilities] : nil, limitBundleIdCapabilities: withCapabilities ? 50 : nil
        )).ok.body.json
      }
    }
    var types: [String: String] = [:]
    for case .bundleIdCapabilities(let capability) in pages.flatMap({ $0.included ?? [] }) {
      types[capability.id] = capability.attributes?.capabilityType
    }
    return pages.flatMap(\.data).map { bundleID in
      BundleID(
        bundleID,
        capabilityTypes: withCapabilities
          ? (bundleID.relationships?.bundleIdCapabilities?.data ?? []).compactMap { types[$0.id] } : nil)
    }
  }

  /// The bundle ID with exactly this identifier (`filter[identifier]` matches prefixes).
  public static func find(identifier: String, client: ASCClient) async throws -> BundleID {
    guard let bundleID = try await list(identifierPrefix: identifier, client: client).first(where: { $0.identifier == identifier }) else {
      throw LookupError.notFound(identifier)
    }
    return bundleID
  }

  public static func register(identifier: String, name: String, platform: String, client: ASCClient) async throws -> BundleID {
    let response = try await client.bundleIdsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(identifier: identifier, name: name, platform: platform),
      _type: "bundleIds"
    )))).created.body.json
    return BundleID(response.data, capabilityTypes: nil)
  }

  public static func rename(id: String, to name: String, client: ASCClient) async throws -> BundleID {
    let response = try await client.bundleIdsUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(attributes: .init(name: name), id: id, _type: "bundleIds")))
    ).ok.body.json
    return BundleID(response.data, capabilityTypes: nil)
  }

  public static func delete(id: String, client: ASCClient) async throws {
    _ = try await client.bundleIdsDeleteInstance(path: .init(id: id)).noContent
  }

  // MARK: Capabilities

  /// A bundle ID's capabilities with their settings, in no particular order (the endpoint
  /// rejects `limit` and returns them all).
  public static func capabilities(bundleID: String, client: ASCClient) async throws -> [Capability] {
    try await client.bundleIdsBundleIdCapabilitiesGetToManyRelated(path: .init(id: bundleID)).ok.body.json.data
      .map(Capability.init)
  }

  public static func enable(
    _ type: String, settings: [Setting] = [], bundleID: String, client: ASCClient
  ) async throws -> Capability {
    let response = try await client.bundleIdCapabilitiesCreateInstance(body: .json(.init(data: .init(
      attributes: .init(capabilityType: type, settings: settings.isEmpty ? nil : settings.map(\.schema)),
      relationships: .init(bundleId: .init(data: .init(id: bundleID, _type: "bundleIds"))),
      _type: "bundleIdCapabilities"
    )))).created.body.json
    return Capability(response.data)
  }

  /// Replaces a capability's settings.
  public static func update(_ capability: Capability, settings: [Setting], client: ASCClient) async throws -> Capability {
    let response = try await client.bundleIdCapabilitiesUpdateInstance(
      path: .init(id: capability.id),
      body: .json(.init(data: .init(
        attributes: .init(capabilityType: capability.type, settings: settings.map(\.schema)),
        id: capability.id, _type: "bundleIdCapabilities")))
    ).ok.body.json
    return Capability(response.data)
  }

  public static func disable(capabilityID: String, client: ASCClient) async throws {
    _ = try await client.bundleIdCapabilitiesDeleteInstance(path: .init(id: capabilityID)).noContent
  }
}

extension BundleIDs.BundleID {
  init(_ bundleID: Components.Schemas.BundleId, capabilityTypes: [String]?) {
    let attributes = bundleID.attributes
    self.init(
      id: bundleID.id, identifier: attributes?.identifier ?? "", name: attributes?.name ?? "",
      platform: attributes?.platform, seedID: attributes?.seedId, capabilityTypes: capabilityTypes)
  }
}

extension BundleIDs.Capability {
  init(_ capability: Components.Schemas.BundleIdCapability) {
    self.init(
      id: capability.id, type: capability.attributes?.capabilityType ?? "",
      settings: (capability.attributes?.settings ?? []).compactMap { setting in
        setting.key.map { key in
          BundleIDs.Setting(key: key, options: (setting.options ?? []).compactMap(\.key))
        }
      })
  }
}

extension BundleIDs.Setting {
  var schema: Components.Schemas.CapabilitySetting {
    .init(key: key, options: options.map { .init(key: $0) })
  }
}
