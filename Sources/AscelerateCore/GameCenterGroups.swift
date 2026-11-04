import ASCKit
import Foundation

/// Game Center groups: a team's groups share achievements, leaderboards and the rest between its
/// apps. Apple documents adding an app to a group as permanent (the app can't leave, and its
/// achievements and leaderboards move into the group), so ascelerate only does it with a warning.
extension GameCenter {
  public struct Group: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let referenceName: String?
    public let apps: [GroupApp]
  }

  public struct GroupApp: Codable, Hashable, Sendable {
    public let detailID: String
    public let appID: String?
    public let bundleID: String?
    public let name: String?
  }

  /// The team's groups with their apps.
  public static func groups(client: ASCClient) async throws -> [Group] {
    let groups = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.gameCenterGroupsGetCollection(query: .init(limit: 200)).ok.body.json
      }
    }.flatMap(\.data)
    return try await boundedConcurrentMap(groups) { group in
      Group(id: group.id, referenceName: group.attributes?.referenceName, apps: try await groupApps(groupID: group.id, client: client))
    }
  }

  private static func groupApps(groupID: String, client: ASCClient) async throws -> [GroupApp] {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.gameCenterGroupsGameCenterDetailsGetToManyRelated(
          path: .init(id: groupID), query: .init(fieldsApps: [.bundleId, .name], limit: 200, include: [.app])
        ).ok.body.json
      }
    }
    var apps: [String: Components.Schemas.App] = [:]
    for page in pages {
      for case .apps(let app) in page.included ?? [] { apps[app.id] = app }
    }
    return pages.flatMap(\.data).map { detail in
      let app = detail.relationships?.app?.data.flatMap { apps[$0.id] }
      return GroupApp(detailID: detail.id, appID: app?.id, bundleID: app?.attributes?.bundleId, name: app?.attributes?.name)
    }
  }

  public static func createGroup(referenceName: String, client: ASCClient) async throws -> Group {
    let created = try await client.gameCenterGroupsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(referenceName: referenceName), _type: "gameCenterGroups")))).created.body.json.data
    return Group(id: created.id, referenceName: created.attributes?.referenceName, apps: [])
  }

  public static func renameGroup(id: String, referenceName: String, client: ASCClient) async throws {
    _ = try await client.gameCenterGroupsUpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
      attributes: .init(referenceName: referenceName), id: id, _type: "gameCenterGroups")))).ok
  }

  public static func deleteGroup(id: String, client: ASCClient) async throws {
    _ = try await client.gameCenterGroupsDeleteInstance(path: .init(id: id)).noContent
  }

  /// Puts an app in a group. Apple documents this as permanent.
  public static func addToGroup(detailID: String, groupID: String, client: ASCClient) async throws {
    _ = try await client.gameCenterDetailsUpdateInstance(path: .init(id: detailID), body: .json(.init(data: .init(
      id: detailID, relationships: .init(gameCenterGroup: .init(data: .init(id: groupID, _type: "gameCenterGroups"))),
      _type: "gameCenterDetails")))).ok
  }
}
