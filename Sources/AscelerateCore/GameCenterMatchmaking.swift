import ASCKit
import Foundation

/// Game Center rule-based matchmaking, which belongs to the team rather than one app: rule sets
/// (player counts, rules, teams), the queues games send match requests to, and Apple's test that
/// runs sample requests through a rule set.
extension GameCenter {
  public struct Queue: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let referenceName: String?
    public let ruleSetID: String?
    /// A second rule set tried on part of the requests.
    public let experimentRuleSetID: String?
    /// Apps whose classic (non-rule-based) matchmaking requests also go to this queue.
    public let classicMatchmakingBundleIDs: [String]
  }

  public struct RuleSet: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let referenceName: String?
    public let ruleLanguageVersion: Int?
    public let minPlayers: Int?
    public let maxPlayers: Int?
    public let rules: [Rule]
    public let teams: [Team]
    /// The queues that use it.
    public let queueIDs: [String]
  }

  public struct Rule: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let referenceName: String?
    public let description: String?
    /// COMPATIBLE, DISTANCE, MATCH or TEAM.
    public let type: String?
    public let expression: String?
    public let weight: Double?
  }

  public struct Team: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let referenceName: String?
    public let minPlayers: Int?
    public let maxPlayers: Int?
  }

  public static let ruleTypes = ["COMPATIBLE", "DISTANCE", "MATCH", "TEAM"]

  // MARK: Queues

  public static func queues(client: ASCClient) async throws -> [Queue] {
    try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        // The rule set relationships carry their IDs only when included.
        try await client.gameCenterMatchmakingQueuesGetCollection(
          query: .init(fieldsGameCenterMatchmakingRuleSets: [.referenceName], limit: 200, include: [.ruleSet, .experimentRuleSet])
        ).ok.body.json
      }
    }.flatMap(\.data).map(queue)
  }

  private static func queue(_ q: Components.Schemas.GameCenterMatchmakingQueue) -> Queue {
    Queue(
      id: q.id, referenceName: q.attributes?.referenceName, ruleSetID: q.relationships?.ruleSet?.data?.id,
      experimentRuleSetID: q.relationships?.experimentRuleSet?.data?.id,
      classicMatchmakingBundleIDs: q.attributes?.classicMatchmakingBundleIds ?? [])
  }

  public static func createQueue(
    referenceName: String, ruleSetID: String, experimentRuleSetID: String?, classicMatchmakingBundleIDs: [String], client: ASCClient
  ) async throws -> Queue {
    let created = try await client.gameCenterMatchmakingQueuesCreateInstance(body: .json(.init(data: .init(
      attributes: .init(
        classicMatchmakingBundleIds: classicMatchmakingBundleIDs.isEmpty ? nil : classicMatchmakingBundleIDs, referenceName: referenceName),
      relationships: .init(
        experimentRuleSet: experimentRuleSetID.map { .init(data: .init(id: $0, _type: "gameCenterMatchmakingRuleSets")) },
        ruleSet: .init(data: .init(id: ruleSetID, _type: "gameCenterMatchmakingRuleSets"))),
      _type: "gameCenterMatchmakingQueues")))).created.body.json.data
    return queue(created)
  }

  /// Changes a queue; nil leaves a value as it is, an empty experiment rule set ID removes it.
  public static func updateQueue(
    id: String, ruleSetID: String? = nil, experimentRuleSetID: String? = nil, classicMatchmakingBundleIDs: [String]? = nil,
    client: ASCClient
  ) async throws {
    let removesExperiment = experimentRuleSetID == ""
    let experiment = experimentRuleSetID.flatMap { $0.isEmpty ? nil : $0 }
    _ = try await ASCNulls.sending(removesExperiment ? [["data", "relationships", "experimentRuleSet", "data"]] : []) {
      try await client.gameCenterMatchmakingQueuesUpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
        attributes: classicMatchmakingBundleIDs.map { .init(classicMatchmakingBundleIds: $0) },
        id: id,
        relationships: .init(
          experimentRuleSet: experiment.map { .init(data: .init(id: $0, _type: "gameCenterMatchmakingRuleSets")) },
          ruleSet: ruleSetID.map { .init(data: .init(id: $0, _type: "gameCenterMatchmakingRuleSets")) }),
        _type: "gameCenterMatchmakingQueues")))).ok
    }
  }

  public static func deleteQueue(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterMatchmakingQueuesDeleteInstance(path: .init(id: id)).noContent
  }

  // MARK: Rule sets

  /// The team's rule sets with their rules, teams and queues (each read on its own: an include
  /// caps them at 50).
  public static func ruleSets(client: ASCClient) async throws -> [RuleSet] {
    let sets = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.gameCenterMatchmakingRuleSetsGetCollection(query: .init(limit: 200)).ok.body.json
      }
    }.flatMap(\.data)
    return try await boundedConcurrentMap(sets) { try await ruleSet($0, client: client) }
  }

  public static func ruleSet(id: String, client: ASCClient) async throws -> RuleSet {
    let set = try await withTransientRetry {
      try await client.gameCenterMatchmakingRuleSetsGetInstance(path: .init(id: id), query: .init()).ok.body.json.data
    }
    return try await ruleSet(set, client: client)
  }

  private static func ruleSet(_ set: Components.Schemas.GameCenterMatchmakingRuleSet, client: ASCClient) async throws -> RuleSet {
    async let rules = withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.gameCenterMatchmakingRuleSetsRulesGetToManyRelated(path: .init(id: set.id), query: .init(limit: 200)).ok.body.json
      }
    }
    async let teams = withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.gameCenterMatchmakingRuleSetsTeamsGetToManyRelated(path: .init(id: set.id), query: .init(limit: 200)).ok.body.json
      }
    }
    async let queues = withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.gameCenterMatchmakingRuleSetsMatchmakingQueuesGetToManyRelated(path: .init(id: set.id), query: .init(limit: 200))
          .ok.body.json
      }
    }
    let a = set.attributes
    return RuleSet(
      id: set.id, referenceName: a?.referenceName, ruleLanguageVersion: a?.ruleLanguageVersion, minPlayers: a?.minPlayers,
      maxPlayers: a?.maxPlayers,
      rules: try await rules.flatMap(\.data).map(rule),
      teams: try await teams.flatMap(\.data).map(team),
      queueIDs: try await queues.flatMap(\.data).map(\.id))
  }

  private static func rule(_ r: Components.Schemas.GameCenterMatchmakingRule) -> Rule {
    let a = r.attributes
    return Rule(id: r.id, referenceName: a?.referenceName, description: a?.description, type: a?._type, expression: a?.expression, weight: a?.weight)
  }

  private static func team(_ t: Components.Schemas.GameCenterMatchmakingTeam) -> Team {
    Team(id: t.id, referenceName: t.attributes?.referenceName, minPlayers: t.attributes?.minPlayers, maxPlayers: t.attributes?.maxPlayers)
  }

  public static func createRuleSet(
    referenceName: String, minPlayers: Int, maxPlayers: Int, ruleLanguageVersion: Int = 1, client: ASCClient
  ) async throws -> RuleSet {
    let created = try await client.gameCenterMatchmakingRuleSetsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(maxPlayers: maxPlayers, minPlayers: minPlayers, referenceName: referenceName, ruleLanguageVersion: ruleLanguageVersion),
      _type: "gameCenterMatchmakingRuleSets")))).created.body.json.data
    return try await ruleSet(created, client: client)
  }

  public static func updateRuleSet(id: String, minPlayers: Int?, maxPlayers: Int?, client: ASCClient) async throws {
    _ = try await client.gameCenterMatchmakingRuleSetsUpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
      attributes: .init(maxPlayers: maxPlayers, minPlayers: minPlayers), id: id, _type: "gameCenterMatchmakingRuleSets")))).ok
  }

  public static func deleteRuleSet(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterMatchmakingRuleSetsDeleteInstance(path: .init(id: id)).noContent
  }

  // MARK: Rules and teams

  public static func createRule(
    ruleSetID: String, referenceName: String, type: String, expression: String, description: String, weight: Double?, client: ASCClient
  ) async throws -> Rule {
    let created = try await client.gameCenterMatchmakingRulesCreateInstance(body: .json(.init(data: .init(
      attributes: .init(description: description, expression: expression, referenceName: referenceName, _type: type, weight: weight),
      relationships: .init(ruleSet: .init(data: .init(id: ruleSetID, _type: "gameCenterMatchmakingRuleSets"))),
      _type: "gameCenterMatchmakingRules")))).created.body.json.data
    return rule(created)
  }

  public static func updateRule(id: String, expression: String?, description: String?, weight: Double?, client: ASCClient) async throws {
    _ = try await client.gameCenterMatchmakingRulesUpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
      attributes: .init(description: description, expression: expression, weight: weight), id: id, _type: "gameCenterMatchmakingRules")))).ok
  }

  public static func deleteRule(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterMatchmakingRulesDeleteInstance(path: .init(id: id)).noContent
  }

  public static func createTeam(
    ruleSetID: String, referenceName: String, minPlayers: Int, maxPlayers: Int, client: ASCClient
  ) async throws -> Team {
    let created = try await client.gameCenterMatchmakingTeamsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(maxPlayers: maxPlayers, minPlayers: minPlayers, referenceName: referenceName),
      relationships: .init(ruleSet: .init(data: .init(id: ruleSetID, _type: "gameCenterMatchmakingRuleSets"))),
      _type: "gameCenterMatchmakingTeams")))).created.body.json.data
    return team(created)
  }

  public static func updateTeam(id: String, minPlayers: Int?, maxPlayers: Int?, client: ASCClient) async throws {
    _ = try await client.gameCenterMatchmakingTeamsUpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
      attributes: .init(maxPlayers: maxPlayers, minPlayers: minPlayers), id: id, _type: "gameCenterMatchmakingTeams")))).ok
  }

  public static func deleteTeam(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterMatchmakingTeamsDeleteInstance(path: .init(id: id)).noContent
  }

  // MARK: Rule set test

  /// A sample match request, as a test file holds it (`game-center matchmaking test --file`).
  public struct TestRequest: Codable, Hashable, Sendable {
    public var requestName: String
    public var secondsInQueue: Int?
    /// Apple's uppercase locale codes (`EN-US`, `TR-TR`).
    public var locale: String?
    public var latitude: Double?
    public var longitude: Double?
    public var minPlayers: Int?
    public var maxPlayers: Int?
    public var playerCount: Int?
    public var bundleId: String
    /// IOS, MAC_OS, TV_OS or VISION_OS.
    public var platform: String
    public var appVersion: String
    public var players: [TestPlayer]

    public struct TestPlayer: Codable, Hashable, Sendable {
      public var playerId: String
      /// The player's properties the rules read (`properties.skill`).
      public var properties: [String: String]?
    }
  }

  /// One match the test made: the requests it put together, each player with its team.
  public struct TestMatch: Codable, Hashable, Sendable {
    public let requests: [TestMatchRequest]

    public struct TestMatchRequest: Codable, Hashable, Sendable {
      public let requestName: String?
      public let teamAssignments: [Assignment]
    }

    public struct Assignment: Codable, Hashable, Sendable {
      public let playerId: String?
      public let team: String?
    }
  }

  /// Runs sample requests through a rule set and returns the matches Apple would make.
  public static func test(ruleSetID: String, requests: [TestRequest], client: ASCClient) async throws -> [TestMatch] {
    var included: [Components.Schemas.GameCenterMatchmakingRuleSetTestCreateRequest.IncludedPayloadPayload] = []
    var requestRefs: [Components.Schemas.GameCenterMatchmakingRuleSetTestCreateRequest.DataPayload.RelationshipsPayload.MatchmakingRequestsPayload.DataPayloadPayload] = []
    for (r, request) in requests.enumerated() {
      var playerRefs: [Components.Schemas.GameCenterMatchmakingTestRequestInlineCreate.RelationshipsPayload.MatchmakingPlayerPropertiesPayload.DataPayloadPayload] = []
      for (p, player) in request.players.enumerated() {
        let id = "${player-\(r)-\(p)}"
        playerRefs.append(.init(id: id, _type: "gameCenterMatchmakingTestPlayerProperties"))
        included.append(.GameCenterMatchmakingTestPlayerPropertyInlineCreate(.init(
          attributes: .init(
            playerId: player.playerId,
            properties: player.properties.map { $0.sorted { $0.key < $1.key }.map { .init(key: $0.key, value: $0.value) } }),
          id: id, _type: "gameCenterMatchmakingTestPlayerProperties")))
      }
      let id = "${request-\(r)}"
      requestRefs.append(.init(id: id, _type: "gameCenterMatchmakingTestRequests"))
      let location: Components.Schemas.Location? = request.latitude.flatMap { lat in request.longitude.map { .init(latitude: lat, longitude: $0) } }
      included.append(.GameCenterMatchmakingTestRequestInlineCreate(.init(
        attributes: .init(
          appVersion: request.appVersion, bundleId: request.bundleId, locale: request.locale, location: location,
          maxPlayers: request.maxPlayers, minPlayers: request.minPlayers, platform: request.platform, playerCount: request.playerCount,
          requestName: request.requestName, secondsInQueue: request.secondsInQueue ?? 0),
        id: id,
        relationships: .init(matchmakingPlayerProperties: .init(data: playerRefs)),
        _type: "gameCenterMatchmakingTestRequests")))
    }
    let result = try await client.gameCenterMatchmakingRuleSetTestsCreateInstance(body: .json(.init(
      data: .init(
        relationships: .init(
          matchmakingRequests: .init(data: requestRefs),
          matchmakingRuleSet: .init(data: .init(id: ruleSetID, _type: "gameCenterMatchmakingRuleSets"))),
        _type: "gameCenterMatchmakingRuleSetTests"),
      included: included))).created.body.json.data
    return (result.attributes?.matchmakingResults ?? []).map { match in
      TestMatch(requests: match.map { r in
        .init(
          requestName: r.requestName,
          teamAssignments: (r.teamAssignments ?? []).map { .init(playerId: $0.playerId, team: $0.team) })
      })
    }
  }
}
