import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

extension GameCenterCommand {
  /// The team's Game Center groups, which share achievements, leaderboards and the rest between apps.
  struct Groups: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Groups: share achievements, leaderboards, sets, activities and challenges between apps.",
      discussion: """
        Groups belong to the team and are named by reference name or ID. Once an app is in a group, \
        the other game-center commands work on the group's items for it. Adding an app to a group \
        can't be undone.
        """,
      subcommands: [List.self, Create.self, Rename.self, Delete.self, AddApp.self],
      defaultSubcommand: List.self
    )

    static func find(_ reference: String, in groups: [GameCenter.Group]) throws -> GameCenter.Group {
      guard let found = groups.first(where: { $0.id == reference || $0.referenceName?.lowercased() == reference.lowercased() }) else {
        throw ValidationError("No group '\(reference)'.\(groups.isEmpty ? " The team has none." : " Groups: \(groups.compactMap(\.referenceName).joined(separator: ", ")).")")
      }
      return found
    }

    static func name(_ group: GameCenter.Group) -> String { group.referenceName ?? group.id }

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "The team's groups with their apps.")

      @OptionGroup var jsonOption: JSONOption

      func run() async throws {
        jsonOption.activate()
        let groups = try await GameCenter.groups(client: ClientFactory.makeClient())
        if jsonOption.json { try printJSON(groups); return }
        guard !groups.isEmpty else {
          print("No groups.")
          return
        }
        Table.print(
          headers: ["Group", "Apps", "ID"],
          rows: groups.map { g in
            [Groups.name(g), g.apps.isEmpty ? "-" : g.apps.map { $0.bundleID ?? $0.name ?? $0.detailID }.joined(separator: ", "), g.id]
          })
      }
    }

    struct Create: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Create an empty group.")

      @Option(name: .long, help: "Its reference name, seen only in App Store Connect.")
      var name: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        try await Matchmaking.write("Create group '\(name)'?", done: green("Created") + " group '\(name)'.") {
          _ = try await GameCenter.createGroup(referenceName: name, client: client)
        }
      }
    }

    struct Rename: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Rename a group.")

      @Argument(help: "The group's reference name or ID.")
      var group: String

      @Option(name: .long, help: "Its new reference name.")
      var name: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let found = try Groups.find(group, in: try await GameCenter.groups(client: client))
        try await Matchmaking.write("Rename group '\(Groups.name(found))' to '\(name)'?", done: green("Renamed") + " the group to '\(name)'.") {
          try await GameCenter.renameGroup(id: found.id, referenceName: name, client: client)
        }
      }
    }

    struct Delete: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Delete a group.")

      @Argument(help: "The group's reference name or ID.")
      var group: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let found = try Groups.find(group, in: try await GameCenter.groups(client: client))
        try await Matchmaking.write("Delete group '\(Groups.name(found))'?", done: green("Deleted") + " group '\(Groups.name(found))'.") {
          try await GameCenter.deleteGroup(id: found.id, client: client)
        }
      }
    }

    struct AddApp: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "add-app",
        abstract: "Put an app in a group. This can't be undone.",
        discussion: """
          Apple documents this as permanent: the app can't leave the group, and its achievements, \
          leaderboards and the rest move into it. Try it with --dry-run first.
          """)

      @Argument(help: "The group's reference name or ID.")
      var group: String

      @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
      var app: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let found = try Groups.find(group, in: try await GameCenter.groups(client: client))
        let (_, detail) = try await GameCenterCommand.context(app: app, client: client)
        if let current = detail.groupID {
          throw ValidationError(current == found.id ? "The app is already in '\(Groups.name(found))'." : "The app is already in another group (\(current)); an app can't move between groups.")
        }
        print(yellow("This can't be undone:") + " the app can't leave the group, and its achievements, leaderboards, sets, activities and challenges move into '\(Groups.name(found))'.")
        try await Matchmaking.write("Add \(app) to group '\(Groups.name(found))'?", done: green("Added") + " \(app) to '\(Groups.name(found))'.") {
          try await GameCenter.addToGroup(detailID: detail.id, groupID: found.id, client: client)
        }
      }
    }
  }
}
