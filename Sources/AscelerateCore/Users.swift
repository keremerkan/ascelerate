import ASCKit
import Foundation

/// The team's people (`users`) and pending invitations (`userInvitations`): their roles, the apps
/// they see, and whether they may use Certificates, Identifiers & Profiles.
public enum Users {
  /// An app someone sees.
  public struct AppRef: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let bundleID: String?
  }

  public struct User: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// The Apple Account (an email address).
    public let username: String?
    public let firstName: String?
    public let lastName: String?
    /// `ADMIN`, `APP_MANAGER`, `DEVELOPER`, … (`ASCEnum.UserRole`).
    public let roles: [String]
    public let allAppsVisible: Bool
    /// App Store Connect's "Access to Certificates, Identifiers & Profiles".
    public let provisioningAllowed: Bool
    /// The apps it sees; nil when it sees all apps.
    public let apps: [AppRef]?

    public var name: String { [firstName, lastName].compactMap(\.self).joined(separator: " ") }
  }

  public struct Invitation: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let email: String?
    public let firstName: String?
    public let lastName: String?
    public let roles: [String]
    public let allAppsVisible: Bool
    public let provisioningAllowed: Bool
    /// When the invitation runs out unless accepted.
    public let expirationDate: Date?
    public let apps: [AppRef]?

    public var name: String { [firstName, lastName].compactMap(\.self).joined(separator: " ") }
  }

  public enum LookupError: LocalizedError {
    case notFound(String)

    public var errorDescription: String? {
      switch self {
        case .notFound(let reference): "No one '\(reference)' on the team. Use their email or ID."
      }
    }
  }

  /// The roles App Store Connect offers to give: every role but Account Holder, which is the
  /// team's own.
  public static let assignableRoles = ASCEnum.UserRole.allCases.map(\.rawValue).filter { $0 != "ACCOUNT_HOLDER" }

  // MARK: Users

  /// The team's people, by email, with the apps of those who don't see all apps.
  public static func list(client: ASCClient) async throws -> [User] {
    let users = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.usersGetCollection(query: .init(limit: 200)).ok.body.json
      }
    }.flatMap(\.data)
    return try await boundedConcurrentMap(users) { user in
      try await self.user(user, client: client)
    }
    .sorted { ($0.username ?? "").localizedStandardCompare($1.username ?? "") == .orderedAscending }
  }

  private static func user(_ user: Components.Schemas.User, client: ASCClient) async throws -> User {
    let a = user.attributes
    let allApps = a?.allAppsVisible ?? false
    return User(
      id: user.id, username: a?.username, firstName: a?.firstName, lastName: a?.lastName, roles: a?.roles ?? [],
      allAppsVisible: allApps, provisioningAllowed: a?.provisioningAllowed ?? false,
      apps: allApps ? nil : try await visibleApps(userID: user.id, client: client))
  }

  /// The apps a person sees (read on their own: an include caps them at 50).
  private static func visibleApps(userID: String, client: ASCClient) async throws -> [AppRef] {
    try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.usersVisibleAppsGetToManyRelated(path: .init(id: userID), query: .init(limit: 200)).ok.body.json
      }
    }.flatMap(\.data).map { AppRef(id: $0.id, name: $0.attributes?.name, bundleID: $0.attributes?.bundleId) }
  }

  /// A person by email (case-insensitive) or ID, among `users`.
  public static func find(_ reference: String, in users: [User]) throws -> User {
    guard let user = users.first(where: { $0.id == reference || $0.username?.lowercased() == reference.lowercased() }) else {
      throw LookupError.notFound(reference)
    }
    return user
  }

  /// Changes a person's roles, whether they see all apps (else `appIDs`), or their access to
  /// Certificates, Identifiers & Profiles; nil leaves each as it is. Returns them as saved.
  public static func update(
    id: String, roles: [String]? = nil, allAppsVisible: Bool? = nil, appIDs: [String]? = nil,
    provisioningAllowed: Bool? = nil, client: ASCClient
  ) async throws -> User {
    let saved = try await client.usersUpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
      attributes: .init(allAppsVisible: allAppsVisible, provisioningAllowed: provisioningAllowed, roles: roles),
      id: id,
      relationships: appIDs.map { ids in .init(visibleApps: .init(data: ids.map { .init(id: $0, _type: "apps") })) },
      _type: "users")))).ok.body.json.data
    return try await user(saved, client: client)
  }

  /// Takes a person off the team.
  public static func remove(id: String, client: ASCClient) async throws {
    _ = try await client.usersDeleteInstance(path: .init(id: id)).noContent
  }

  // MARK: Invitations

  /// The invitations not accepted yet, by email.
  public static func invitations(client: ASCClient) async throws -> [Invitation] {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.userInvitationsGetCollection(query: .init(limit: 200)).ok.body.json
      }
    }
    return try await boundedConcurrentMap(pages.flatMap(\.data)) { invitation in
      try await self.invitation(invitation, client: client)
    }
    .sorted { ($0.email ?? "").localizedStandardCompare($1.email ?? "") == .orderedAscending }
  }

  private static func invitation(_ invitation: Components.Schemas.UserInvitation, client: ASCClient) async throws -> Invitation {
    let a = invitation.attributes
    let allApps = a?.allAppsVisible ?? false
    var apps: [AppRef]?
    if !allApps {
      apps = try await withTransientRetry {
        try await ASCPaging.allPages(next: { $0.links.next }) {
          try await client.userInvitationsVisibleAppsGetToManyRelated(path: .init(id: invitation.id), query: .init(limit: 200)).ok.body.json
        }
      }.flatMap(\.data).map { AppRef(id: $0.id, name: $0.attributes?.name, bundleID: $0.attributes?.bundleId) }
    }
    return Invitation(
      id: invitation.id, email: a?.email, firstName: a?.firstName, lastName: a?.lastName, roles: a?.roles ?? [],
      allAppsVisible: allApps, provisioningAllowed: a?.provisioningAllowed ?? false, expirationDate: a?.expirationDate,
      apps: apps)
  }

  /// Invites someone (App Store Connect emails them at once) with roles, and all apps or
  /// `appIDs`; returns the invitation.
  public static func invite(
    email: String, firstName: String, lastName: String, roles: [String], allAppsVisible: Bool, appIDs: [String],
    provisioningAllowed: Bool, client: ASCClient
  ) async throws -> Invitation {
    let created = try await client.userInvitationsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(
        allAppsVisible: allAppsVisible, email: email, firstName: firstName, lastName: lastName,
        provisioningAllowed: provisioningAllowed, roles: roles),
      relationships: allAppsVisible ? nil : .init(visibleApps: .init(data: appIDs.map { .init(id: $0, _type: "apps") })),
      _type: "userInvitations")))).created.body.json.data
    return try await invitation(created, client: client)
  }

  /// Withdraws an invitation; its link stops working.
  public static func cancelInvitation(id: String, client: ASCClient) async throws {
    _ = try await client.userInvitationsDeleteInstance(path: .init(id: id)).noContent
  }
}
