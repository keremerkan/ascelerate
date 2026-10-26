import ASCKit
import Foundation

/// An app's TestFlight testers.
public enum BetaTesters {
  public struct Tester: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let email: String?
    public let firstName: String?
    public let lastName: String?
    /// EMAIL or PUBLIC_LINK.
    public let inviteType: String?
    /// NOT_INVITED, INVITED, ACCEPTED, INSTALLED or REVOKED.
    public let state: String?
    /// The groups they're in, when read with them (`list` reads them).
    public let groupIDs: [String]

    public init(_ tester: Components.Schemas.BetaTester) {
      let attributes = tester.attributes
      id = tester.id
      email = attributes?.email
      firstName = attributes?.firstName
      lastName = attributes?.lastName
      inviteType = attributes?.inviteType
      state = attributes?.state
      groupIDs = tester.relationships?.betaGroups?.data?.map(\.id) ?? []
    }

    /// The tester's name, or nil without one.
    public var name: String? {
      let name = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " ")
      return name.isEmpty ? nil : name
    }
  }

  /// The app's testers, or a group's (the group already scopes them to its app: the endpoint
  /// refuses both filters together), by email, with their groups; `email` narrows them (Apple
  /// matches it).
  public static func list(
    appID: String? = nil, groupID: String? = nil, email: String? = nil, client: ASCClient
  ) async throws -> [Tester] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.betaTestersGetCollection(query: .init(
        filterEmail: email.map { [$0] }, filterApps: groupID == nil ? appID.map { [$0] } : nil,
        filterBetaGroups: groupID.map { [$0] }, sort: [.email], limit: 200, include: [.betaGroups], limitBetaGroups: 50
      )).ok.body.json
    }.flatMap(\.data).map(Tester.init)
  }

  /// Adds a tester to groups (App Store Connect invites a new one to an external group).
  public static func create(
    email: String, firstName: String? = nil, lastName: String? = nil, groupIDs: [String], client: ASCClient
  ) async throws {
    _ = try await client.betaTestersCreateInstance(body: .json(.init(data: .init(
      attributes: .init(email: email, firstName: firstName, lastName: lastName),
      relationships: .init(betaGroups: .init(data: groupIDs.map { .init(id: $0, _type: "betaGroups") })),
      _type: "betaTesters"
    )))).created
  }

  /// Takes a tester off the app: out of all its groups and builds. Returns false when App Store
  /// Connect took the request to do later (202 Accepted, seen 2026-10-23 for anonymous public link
  /// testers) rather than at once (204).
  @discardableResult
  public static func removeFromApp(testerID: String, appID: String, client: ASCClient) async throws -> Bool {
    let output = try await client.betaTestersAppsDeleteToManyRelationship(
      path: .init(id: testerID), body: .json(.init(data: [.init(id: appID, _type: "apps")])))
    if case .accepted = output { return false }
    _ = try output.noContent
    return true
  }

  /// Sends the tester's invitation email again.
  public static func invite(testerID: String, appID: String, client: ASCClient) async throws {
    _ = try await client.betaTesterInvitationsCreateInstance(body: .json(.init(data: .init(
      relationships: .init(
        app: .init(data: .init(id: appID, _type: "apps")),
        betaTester: .init(data: .init(id: testerID, _type: "betaTesters"))
      ),
      _type: "betaTesterInvitations"
    )))).created
  }

  /// A tester to add, as a CSV line names them.
  public struct NewTester: Equatable, Sendable {
    public let email: String
    public let firstName: String?
    public let lastName: String?

    public init(email: String, firstName: String? = nil, lastName: String? = nil) {
      self.email = email
      self.firstName = firstName
      self.lastName = lastName
    }
  }

  /// The testers of a CSV file, one per line: `email[,first name[,last name]]`, fields quoted
  /// when they hold commas ("Appleseed, Jane"). Blank lines, lines starting with #, and a header row
  /// (a first field without @) are skipped; App Store Connect's own export has this shape.
  public static func parseCSV(_ content: String) -> [NewTester] {
    CSV.rows(content).compactMap { row in
      let fields = row.map { $0.trimmingCharacters(in: .whitespaces) }
      guard let first = fields.first, !first.hasPrefix("#"), first.contains("@") else { return nil }
      return NewTester(
        email: fields[0],
        firstName: fields.count > 1 && !fields[1].isEmpty ? fields[1] : nil,
        lastName: fields.count > 2 && !fields[2].isEmpty ? fields[2] : nil)
    }
  }

  /// What each tester did over a period: sessions, crashes and feedback, by tester ID.
  public struct Usage: Codable, Hashable, Sendable {
    public let sessions: Int
    public let crashes: Int
    public let feedback: Int
  }

  /// The app's testers' usage over the last 7, 30, 90 or 365 days, by tester ID (a tester without
  /// any isn't listed).
  public static func usage(appID: String, days: Int = 30, client: ASCClient) async throws -> [String: Usage] {
    typealias Period = Operations.AppsBetaTesterUsagesGetMetrics.Input.Query.PeriodPayload
    let period = Period(rawValue: "P\(days)D") ?? .p30d
    let rows = try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.appsBetaTesterUsagesGetMetrics(
        path: .init(id: appID), query: .init(period: period, groupBy: [.betaTesters], limit: 200)
      ).ok.body.json
    }.flatMap(\.data)
    var usage: [String: Usage] = [:]
    for row in rows {
      guard let testerID = row.dimensions?.betaTesters?.data?.id else { continue }
      let values = (row.dataPoints ?? []).compactMap { $0.values }
      usage[testerID] = Usage(
        sessions: values.reduce(0) { $0 + ($1.sessionCount ?? 0) },
        crashes: values.reduce(0) { $0 + ($1.crashCount ?? 0) },
        feedback: values.reduce(0) { $0 + ($1.feedbackCount ?? 0) })
    }
    return usage
  }

  /// The app's tester with this email (case-insensitive), or nil.
  public static func find(email: String, appID: String, client: ASCClient) async throws -> Tester? {
    try await client.betaTestersGetCollection(query: .init(filterEmail: [email], filterApps: [appID])).ok.body.json
      .data.first { $0.attributes?.email?.lowercased() == email.lowercased() }
      .map(Tester.init)
  }
}
