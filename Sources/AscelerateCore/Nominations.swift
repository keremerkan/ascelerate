import ASCKit
import Foundation

/// Featuring nominations (`nominations`): telling Apple's editors about a launch, an update or
/// new content. A nomination is the account's, about one or more apps (`relatedApps`); it's a
/// draft until submitted, and can be archived.
public enum Nominations {
  public typealias Actor = ReviewSubmissions.Actor

  public static let states = ["DRAFT", "SUBMITTED", "ARCHIVED"]

  /// The types in App Store Connect's order.
  public static let types = ["NEW_CONTENT", "APP_ENHANCEMENTS", "APP_LAUNCH"]

  /// The languages App Store Connect offers, as it sends them: the App Store's locale codes in
  /// uppercase (read live 2026-10-21 from a nomination with every language selected).
  public static let locales = [
    "AR-SA", "BN-BD", "CA", "CS", "DA", "DE-DE", "EL", "EN-AU", "EN-CA", "EN-GB", "EN-US", "ES-ES", "ES-MX", "FI",
    "FR-CA", "FR-FR", "GU-IN", "HE", "HI", "HR", "HU", "ID", "IT", "JA", "KN-IN", "KO", "ML-IN", "MR-IN", "MS", "NL-NL",
    "NO", "OR-IN", "PA-IN", "PL", "PT-BR", "PT-PT", "RO", "RU", "SK", "SL-SI", "SV", "TA-IN", "TE-IN", "TH", "TR", "UK",
    "UR-PK", "VI", "ZH-HANS", "ZH-HANT",
  ]

  public struct Nomination: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    /// `NEW_CONTENT`, `APP_ENHANCEMENTS` or `APP_LAUNCH`.
    public let type: String?
    /// `DRAFT`, `SUBMITTED` or `ARCHIVED`.
    public let state: String?
    public let description: String?
    /// App Store Connect's "Helpful Details".
    public let notes: String?
    public let publishStartDate: Date?
    /// Set when the nomination is for a time frame rather than a day.
    public let publishEndDate: Date?
    /// `IPHONE`, `IPAD`, `MAC`, `APPLE_TV`, `APPLE_WATCH`, `VISION`.
    public let deviceFamilies: [String]
    /// Uppercase App Store locale codes (`EN-US`, `TR`).
    public let locales: [String]
    /// The relevant countries or regions (territory codes).
    public let territories: [String]
    public let launchInSelectMarketsFirst: Bool
    public let preOrderEnabled: Bool
    /// "Do you intend to submit a new in-app event for this nomination?"
    public let hasInAppEvents: Bool
    public let supplementalMaterials: [String]
    public let appIDs: [String]
    public let createdDate: Date?
    public let lastModifiedDate: Date?
    public let submittedDate: Date?
    public let lastModifiedBy: Actor?
    public let submittedBy: Actor?
  }

  /// Nominations about an app (or all of them), in the given states (default: all). The list
  /// takes one state per request (`filter[state]` refuses a list).
  public static func list(appID: String? = nil, states: [String] = states, client: ASCClient) async throws -> [Nomination] {
    typealias State = Operations.NominationsGetCollection.Input.Query.FilterStatePayloadPayload
    var nominations: [Nomination] = []
    for state in states {
      guard let filter = State(rawValue: state) else { continue }
      for page in try await ASCPaging.allPages(next: { $0.links.next }, {
        try await client.nominationsGetCollection(query: .init(
          filterState: [filter], filterRelatedApps: appID.map { [$0] }, limit: 200,
          include: [.relatedApps, .lastModifiedByActor, .submittedByActor, .supportedTerritories],
          limitRelatedApps: 50, limitSupportedTerritories: 200
        )).ok.body.json
      }) {
        let actors = actors(in: page.included)
        nominations += page.data.map { nomination($0, actors: actors) }
      }
    }
    return nominations
  }

  public static func get(id: String, client: ASCClient) async throws -> Nomination {
    let response = try await client.nominationsGetInstance(
      path: .init(id: id),
      query: .init(
        include: [.relatedApps, .lastModifiedByActor, .submittedByActor, .supportedTerritories],
        limitRelatedApps: 50, limitSupportedTerritories: 200)
    ).ok.body.json
    return nomination(response.data, actors: actors(in: response.included))
  }

  /// A new nomination, a draft unless `submit`. Optional values left nil aren't sent.
  @discardableResult
  public static func create(
    name: String, type: String, description: String, publishStartDate: Date, publishEndDate: Date? = nil,
    appIDs: [String], deviceFamilies: [String]? = nil, locales: [String]? = nil, territories: [String]? = nil,
    launchInSelectMarketsFirst: Bool? = nil, preOrderEnabled: Bool? = nil, hasInAppEvents: Bool? = nil,
    notes: String? = nil, supplementalMaterials: [String]? = nil, submit: Bool = false, client: ASCClient
  ) async throws -> Nomination {
    let created = try await client.nominationsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(
        description: description, deviceFamilies: deviceFamilies, hasInAppEvents: hasInAppEvents,
        launchInSelectMarketsFirst: launchInSelectMarketsFirst, locales: locales, name: name, notes: notes,
        preOrderEnabled: preOrderEnabled, publishEndDate: publishEndDate, publishStartDate: publishStartDate,
        submitted: submit, supplementalMaterialsUris: supplementalMaterials, _type: type
      ),
      relationships: .init(
        relatedApps: .init(data: appIDs.map { .init(id: $0, _type: "apps") }),
        supportedTerritories: territories.map { .init(data: $0.map { .init(id: $0, _type: "territories") }) }
      ),
      _type: "nominations"
    )))).created.body.json.data
    return try await get(id: created.id, client: client)
  }

  /// Changes a nomination; nil values are left as they are. `publishEndDate` given as `.some(nil)`
  /// makes it a single day again (sent as null). Lists replace the current ones.
  ///
  /// Apple refuses an update without exactly one of `submitted` and `archived` ("At least one of
  /// parameters 'submitted or archived' is required", "Not allowed to provide parameters
  /// 'submitted' and 'archived' together"), and `archived: false` on a draft reads as "[DRAFT]
  /// state to [UNKNOWN] state" (seen live 2026-10-21). So the one matching the current state goes
  /// along: `archived: true` for an archived one, else `submitted` as it is. The state is
  /// `state` (the nomination's current one) or, without it, read first.
  @discardableResult
  public static func update(
    id: String, state: String? = nil, name: String? = nil, type: String? = nil, description: String? = nil, publishStartDate: Date? = nil,
    publishEndDate: Date?? = nil, appIDs: [String]? = nil, deviceFamilies: [String]? = nil, locales: [String]? = nil,
    territories: [String]? = nil, launchInSelectMarketsFirst: Bool? = nil, preOrderEnabled: Bool? = nil,
    hasInAppEvents: Bool? = nil, notes: String? = nil, supplementalMaterials: [String]? = nil, client: ASCClient
  ) async throws -> Nomination {
    var current = state
    if current == nil { current = try await get(id: id, client: client).state }
    let nulls = publishEndDate.map { $0 == nil } == true ? [["data", "attributes", "publishEndDate"]] : []
    let hasRelationships = appIDs != nil || territories != nil
    try await ASCNulls.sending(nulls) {
      _ = try await client.nominationsUpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
        attributes: .init(
          archived: current == "ARCHIVED" ? true : nil, description: description, deviceFamilies: deviceFamilies, hasInAppEvents: hasInAppEvents,
          launchInSelectMarketsFirst: launchInSelectMarketsFirst, locales: locales, name: name,
          notes: notes, preOrderEnabled: preOrderEnabled, publishEndDate: publishEndDate ?? nil,
          publishStartDate: publishStartDate,
          submitted: current == "ARCHIVED" ? nil : current == "SUBMITTED", supplementalMaterialsUris: supplementalMaterials, _type: type
        ),
        id: id,
        relationships: hasRelationships
          ? .init(
            relatedApps: appIDs.map { .init(data: $0.map { .init(id: $0, _type: "apps") }) },
            supportedTerritories: territories.map { .init(data: $0.map { .init(id: $0, _type: "territories") }) })
          : nil,
        _type: "nominations"
      )))).ok
    }
    return try await get(id: id, client: client)
  }

  /// Sends a draft to Apple's editors.
  @discardableResult
  public static func submit(id: String, client: ASCClient) async throws -> Nomination {
    try await patch(id: id, attributes: .init(submitted: true), client: client)
  }

  @discardableResult
  public static func archive(id: String, client: ASCClient) async throws -> Nomination {
    try await patch(id: id, attributes: .init(archived: true), client: client)
  }

  public static func delete(id: String, client: ASCClient) async throws {
    _ = try await client.nominationsDeleteInstance(path: .init(id: id)).noContent
  }

  private static func patch(
    id: String, attributes: Components.Schemas.NominationUpdateRequest.DataPayload.AttributesPayload, client: ASCClient
  ) async throws -> Nomination {
    _ = try await client.nominationsUpdateInstance(
      path: .init(id: id), body: .json(.init(data: .init(attributes: attributes, id: id, _type: "nominations")))
    ).ok
    return try await get(id: id, client: client)
  }

  private static func actors(in included: [Components.Schemas.NominationsResponse.IncludedPayloadPayload]?) -> [String: Actor] {
    var actors: [String: Actor] = [:]
    for case .actors(let actor) in included ?? [] {
      actors[actor.id] = Actor(actor)
    }
    return actors
  }

  private static func actors(in included: [Components.Schemas.NominationResponse.IncludedPayloadPayload]?) -> [String: Actor] {
    var actors: [String: Actor] = [:]
    for case .actors(let actor) in included ?? [] {
      actors[actor.id] = Actor(actor)
    }
    return actors
  }

  private static func nomination(_ n: Components.Schemas.Nomination, actors: [String: Actor]) -> Nomination {
    let a = n.attributes
    let r = n.relationships
    return Nomination(
      id: n.id, name: a?.name, type: a?._type, state: a?.state, description: a?.description, notes: a?.notes,
      publishStartDate: a?.publishStartDate, publishEndDate: a?.publishEndDate, deviceFamilies: a?.deviceFamilies ?? [],
      locales: a?.locales ?? [], territories: r?.supportedTerritories?.data?.map(\.id) ?? [],
      launchInSelectMarketsFirst: a?.launchInSelectMarketsFirst ?? false, preOrderEnabled: a?.preOrderEnabled ?? false,
      hasInAppEvents: a?.hasInAppEvents ?? false, supplementalMaterials: a?.supplementalMaterialsUris ?? [],
      appIDs: r?.relatedApps?.data?.map(\.id) ?? [], createdDate: a?.createdDate, lastModifiedDate: a?.lastModifiedDate,
      submittedDate: a?.submittedDate, lastModifiedBy: r?.lastModifiedByActor?.data.flatMap { actors[$0.id] },
      submittedBy: r?.submittedByActor?.data.flatMap { actors[$0.id] })
  }
}

extension ReviewSubmissions.Actor {
  /// Nominations' actors come without `actorType` (only a user's name or an `apiKeyId`, seen live
  /// 2026-10-21), so a missing type is inferred from those.
  init(_ actor: Components.Schemas.Actor) {
    let attributes = actor.attributes
    let name = [attributes?.userFirstName, attributes?.userLastName].compactMap(\.self).joined(separator: " ")
    let type = attributes?.actorType ?? (attributes?.apiKeyId != nil ? "API_KEY" : name.isEmpty ? "" : "USER")
    self.init(
      type: type, name: name.isEmpty ? nil : name, email: attributes?.userEmail, apiKeyID: attributes?.apiKeyId)
  }
}
