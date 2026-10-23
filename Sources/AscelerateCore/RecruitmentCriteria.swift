import ASCKit
import Foundation

/// Who can join an external group through its public link: device families with an OS range
/// each (`betaRecruitmentCriteria`, one per group, with the group's ID). A legacy setting: groups
/// that have criteria keep them, but no new ones can be added (see `update`).
public enum RecruitmentCriteria {
  /// A device family (`IPHONE`, `IPAD`, `MAC`, `APPLE_TV`, `APPLE_WATCH`, `VISION`) and the OS
  /// versions it takes, inclusive; nil is unbounded.
  public struct Filter: Codable, Hashable, Sendable {
    public var deviceFamily: String
    public var minimumOS: String?
    public var maximumOS: String?

    public init(deviceFamily: String, minimumOS: String? = nil, maximumOS: String? = nil) {
      self.deviceFamily = deviceFamily
      self.minimumOS = minimumOS
      self.maximumOS = maximumOS
    }
  }

  public struct Criteria: Hashable, Sendable {
    public let id: String
    public let filters: [Filter]
  }

  /// A group's criteria; nil when it has none, which Apple answers with HTTP 409 ("does not
  /// exist") as well as 404 or null data.
  public static func criteria(groupID: String, client: ASCClient) async throws -> Criteria? {
    let criterion: Components.Schemas.BetaRecruitmentCriterion
    do {
      criterion = try await client.betaGroupsBetaRecruitmentCriteriaGetToOneRelated(path: .init(id: groupID)).ok.body.json.data
    } catch where ASCError.isMissingRelated(error) || ASCError.from(error)?.statusCode == 409 {
      return nil
    }
    // Unbounded limits come as empty strings.
    func bound(_ value: String?) -> String? { value?.isEmpty == false ? value : nil }
    return Criteria(
      id: criterion.id,
      filters: (criterion.attributes?.deviceFamilyOsVersionFilters ?? []).compactMap { filter in
        filter.deviceFamily.map {
          Filter(deviceFamily: $0, minimumOS: bound(filter.minimumOsInclusive), maximumOS: bound(filter.maximumOsInclusive))
        }
      })
  }

  /// The device families criteria can name, each with the OS versions Apple offers for it.
  public static func options(client: ASCClient) async throws -> [(deviceFamily: String, osVersions: [String])] {
    try await client.betaRecruitmentCriterionOptionsGetCollection(query: .init(limit: 200)).ok.body.json.data
      .flatMap { $0.attributes?.deviceFamilyOsVersions ?? [] }
      .compactMap { entry in entry.deviceFamily.map { ($0, entry.osVersions ?? []) } }
  }

  /// Replaces a group's criteria (`id`, from `criteria`). Existing criteria only: the API can't add
  /// them (seen live 2026-10-23: the spec's POST /v1/betaRecruitmentCriteria answers 404 "not a
  /// valid URL", and a PATCH of the group's ID, which criteria take as theirs, 404 "no resource"),
  /// and App Store Connect no longer shows them; a group's Mac and Vision Pro settings
  /// (`BetaGroups.update`) are what it offers instead.
  public static func update(_ filters: [Filter], id: String, client: ASCClient) async throws {
    let filters = filters.map {
      Components.Schemas.DeviceFamilyOsVersionFilter(
        deviceFamily: $0.deviceFamily, maximumOsInclusive: $0.maximumOS, minimumOsInclusive: $0.minimumOS)
    }
    _ = try await client.betaRecruitmentCriteriaUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(
        attributes: .init(deviceFamilyOsVersionFilters: filters), id: id, _type: "betaRecruitmentCriteria")))
    ).ok
  }

  /// Removes a group's criteria: anyone can join through the link.
  public static func delete(id: String, client: ASCClient) async throws {
    _ = try await client.betaRecruitmentCriteriaDeleteInstance(path: .init(id: id)).noContent
  }
}
