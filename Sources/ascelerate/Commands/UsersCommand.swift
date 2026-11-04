import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

struct UsersCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "users",
    abstract: "The team's people and invitations: roles, app access, Certificates, Identifiers & Profiles.",
    discussion: """
      People are named by their email or ID; apps by bundle ID or alias. Roles: \
      \(Users.assignableRoles.map(UsersCommand.roleName).joined(separator: ", ")). Changing \
      roles or removing someone needs an Admin key.
      """,
    subcommands: [List.self, Info.self, Update.self, Remove.self, Invitations.self, Invite.self, CancelInvitation.self],
    defaultSubcommand: List.self
  )

  /// A role as the CLI takes it: `APP_MANAGER` → `app-manager`.
  static func roleName(_ raw: String) -> String {
    raw.lowercased().replacingOccurrences(of: "_", with: "-")
  }

  /// Roles from a comma-separated list of names (`app-manager`) or raw values (`APP_MANAGER`).
  static func roles(_ value: String) throws -> [String] {
    try value.split(separator: ",").map { item in
      let raw = item.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: "-", with: "_")
      guard Users.assignableRoles.contains(raw) else {
        throw ValidationError("No role '\(item)'. Roles: \(Users.assignableRoles.map(roleName).joined(separator: ", ")).")
      }
      return raw
    }
  }

  /// Apps' IDs from bundle IDs or aliases.
  static func appIDs(_ value: String, client: ASCClient) async throws -> [String] {
    var ids: [String] = []
    for item in value.split(separator: ",") {
      ids.append(try await findApp(bundleID: item.trimmingCharacters(in: .whitespaces), client: client).id)
    }
    return ids
  }

  static func rolesText(_ roles: [String]) -> String {
    roles.isEmpty ? "-" : roles.map { formatState($0) }.joined(separator: ", ")
  }

  static func appsText(_ apps: [Users.AppRef]?) -> String {
    guard let apps else { return "All apps" }
    return apps.isEmpty ? "None" : apps.map { $0.name ?? $0.bundleID ?? $0.id }.joined(separator: ", ")
  }

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "The team's people with their roles and apps.")

    @OptionGroup var jsonOption: JSONOption

    func run() async throws {
      jsonOption.activate()
      let users = try await Users.list(client: ClientFactory.makeClient())
      if jsonOption.json { try printJSON(users); return }
      Table.print(
        headers: ["Email", "Name", "Roles", "Apps", "Certificates, IDs & Profiles"],
        rows: users.map { u in
          [
            u.username ?? "-", u.name.isEmpty ? "-" : u.name, UsersCommand.rolesText(u.roles),
            u.apps.map { "\($0.count) app\($0.count == 1 ? "" : "s")" } ?? "All apps", u.provisioningAllowed ? "Yes" : "No",
          ]
        })
    }
  }

  struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "A person's roles, apps and access.")

    @Argument(help: "Their email or ID.")
    var user: String

    @OptionGroup var jsonOption: JSONOption

    func run() async throws {
      jsonOption.activate()
      let user = try Users.find(user, in: try await Users.list(client: ClientFactory.makeClient()))
      if jsonOption.json { try printJSON(user); return }
      print(bold(user.name.isEmpty ? (user.username ?? user.id) : user.name))
      Table.print(headers: ["", ""], rows: [
        ["Email", user.username ?? "-"],
        ["Roles", UsersCommand.rolesText(user.roles)],
        ["Apps", UsersCommand.appsText(user.apps)],
        ["Certificates, IDs & Profiles", user.provisioningAllowed ? "Yes" : "No"],
        ["ID", user.id],
      ])
    }
  }

  struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Change a person's roles, apps or access to Certificates, Identifiers & Profiles.",
      discussion: "--roles replaces their roles; --apps replaces the apps they see (and turns all apps off); --all-apps gives them every app."
    )

    @Argument(help: "Their email or ID.")
    var user: String

    @Option(name: .long, help: "Their roles, comma-separated (developer,marketing).")
    var roles: String?

    @Option(name: .long, help: "The apps they see, by bundle ID or alias, comma-separated.")
    var apps: String?

    @Flag(name: .long, help: "They see every app, now and to come.")
    var allApps = false

    @Option(name: .long, help: "Access to Certificates, Identifiers & Profiles: true or false.")
    var provisioning: Bool?

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      guard roles != nil || apps != nil || allApps || provisioning != nil else {
        throw ValidationError("Give --roles, --apps, --all-apps or --provisioning.")
      }
      guard !(allApps && apps != nil) else { throw ValidationError("Give --apps or --all-apps, not both.") }
      let client = try ClientFactory.makeClient()
      let current = try Users.find(user, in: try await Users.list(client: client))
      let newRoles = try roles.map(UsersCommand.roles)
      var appIDs: [String]?
      if let apps { appIDs = try await UsersCommand.appIDs(apps, client: client) }
      var lines: [String] = []
      if let newRoles, Set(newRoles) != Set(current.roles) {
        lines.append("Roles: \(UsersCommand.rolesText(current.roles)) → \(UsersCommand.rolesText(newRoles))")
      }
      if allApps, !current.allAppsVisible { lines.append("Apps: \(UsersCommand.appsText(current.apps)) → All apps") }
      if let appIDs, current.allAppsVisible || Set(appIDs) != Set(current.apps?.map(\.id) ?? []) {
        lines.append("Apps: \(UsersCommand.appsText(current.apps)) → \(apps ?? "")")
      }
      if let provisioning, provisioning != current.provisioningAllowed {
        lines.append("Certificates, IDs & Profiles: \(current.provisioningAllowed ? "Yes" : "No") → \(provisioning ? "Yes" : "No")")
      }
      guard !lines.isEmpty else {
        print("Nothing to change.")
        return
      }
      print("\(current.username ?? current.id):")
      for line in lines { print("  \(line)") }
      guard confirm("Save? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      _ = try await Users.update(
        id: current.id, roles: newRoles, allAppsVisible: allApps ? true : appIDs != nil ? false : nil, appIDs: appIDs,
        provisioningAllowed: provisioning, client: client)
      print(green("Updated") + " \(current.username ?? current.id).")
    }
  }

  struct Remove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Take someone off the team.")

    @Argument(help: "Their email or ID.")
    var user: String

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let current = try Users.find(user, in: try await Users.list(client: client))
      print("Remove \(current.username ?? current.id) (\(UsersCommand.rolesText(current.roles))) from the team?")
      print("They lose access to App Store Connect for this team at once.")
      guard confirm("Remove? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      try await Users.remove(id: current.id, client: client)
      print(green("Removed") + " \(current.username ?? current.id).")
    }
  }

  struct Invitations: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Invitations not accepted yet.")

    @OptionGroup var jsonOption: JSONOption

    func run() async throws {
      jsonOption.activate()
      let invitations = try await Users.invitations(client: ClientFactory.makeClient())
      if jsonOption.json { try printJSON(invitations); return }
      guard !invitations.isEmpty else {
        print("No pending invitations.")
        return
      }
      Table.print(
        headers: ["Email", "Name", "Roles", "Apps", "Expires"],
        rows: invitations.map { i in
          [
            i.email ?? "-", i.name.isEmpty ? "-" : i.name, UsersCommand.rolesText(i.roles), UsersCommand.appsText(i.apps),
            i.expirationDate.map(formatDate) ?? "-",
          ]
        })
    }
  }

  struct Invite: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Invite someone to the team; App Store Connect emails them at once.",
      discussion: "Without --apps they see every app."
    )

    @Option(name: .long, help: "Their email address.")
    var email: String

    @Option(name: .long, help: "Their first name.")
    var firstName: String

    @Option(name: .long, help: "Their last name.")
    var lastName: String

    @Option(name: .long, help: "Their roles, comma-separated (developer,marketing).")
    var roles: String

    @Option(name: .long, help: "The apps they see, by bundle ID or alias, comma-separated; every app if left out.")
    var apps: String?

    @Flag(name: .long, help: "Access to Certificates, Identifiers & Profiles.")
    var provisioning = false

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let roles = try UsersCommand.roles(roles)
      let client = try ClientFactory.makeClient()
      var appIDs: [String] = []
      if let apps { appIDs = try await UsersCommand.appIDs(apps, client: client) }
      print("Invite \(firstName) \(lastName) <\(email)>:")
      print("  Roles: \(UsersCommand.rolesText(roles))")
      print("  Apps: \(apps ?? "All apps")")
      print("  Certificates, IDs & Profiles: \(provisioning ? "Yes" : "No")")
      print("App Store Connect emails the invitation at once.")
      guard confirm("Invite? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      let invitation = try await Users.invite(
        email: email, firstName: firstName, lastName: lastName, roles: roles, allAppsVisible: apps == nil, appIDs: appIDs,
        provisioningAllowed: provisioning, client: client)
      print(green("Invited") + " \(email)" + (invitation.expirationDate.map { "; the invitation expires \(formatDate($0))." } ?? "."))
    }
  }

  struct CancelInvitation: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "cancel-invitation", abstract: "Withdraw an invitation not accepted yet.")

    @Argument(help: "The invited email or the invitation's ID.")
    var invitation: String

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let all = try await Users.invitations(client: client)
      guard let found = all.first(where: { $0.id == invitation || $0.email?.lowercased() == invitation.lowercased() }) else {
        throw ValidationError("No pending invitation '\(invitation)'.")
      }
      guard confirm("Withdraw the invitation to \(found.email ?? found.id)? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      try await Users.cancelInvitation(id: found.id, client: client)
      print(green("Withdrew") + " the invitation to \(found.email ?? found.id).")
    }
  }
}
