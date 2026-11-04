import ArgumentParser
import AscelerateCore
import Foundation

extension AppsCommand {
  /// The tags Apple shows for an app on the App Store; it chooses them, the developer hides or
  /// shows each.
  struct TagsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "tags",
      abstract: "The App Store tags Apple gave the app, and hiding or showing them.",
      subcommands: [View.self, Hide.self, Show.self],
      defaultSubcommand: View.self
    )

    struct View: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "List the app's tags with where they're shown.")

      @Argument(help: "Bundle identifier of the app.", completion: appAliasCompletion)
      var bundleID: String

      @OptionGroup var jsonOption: JSONOption

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let tags = try await AppTags.list(appID: app.id, client: client)
        if jsonOption.json { try printJSON(tags); return }
        guard !tags.isEmpty else {
          print("No tags. Apple gives an app its tags; none are assigned yet.")
          return
        }
        Table.print(
          headers: ["Tag", "On the App Store", "Territories"],
          rows: tags.map { tag in
            [
              tag.name ?? tag.id, tag.visibleInAppStore ? "Shown" : yellow("Hidden"),
              tag.territories.count >= 170 ? "All (\(tag.territories.count))" : tag.territories.joined(separator: ", "),
            ]
          })
      }
    }

    struct Hide: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Hide a tag from the app's App Store page.")

      @Argument(help: "Bundle identifier of the app.", completion: appAliasCompletion)
      var bundleID: String

      @Argument(help: "The tag's name or ID.")
      var tag: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws { try await TagsCommand.set(false, tag: tag, bundleID: bundleID, yes: yes) }
    }

    struct Show: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Show a hidden tag on the app's App Store page again.")

      @Argument(help: "Bundle identifier of the app.", completion: appAliasCompletion)
      var bundleID: String

      @Argument(help: "The tag's name or ID.")
      var tag: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws { try await TagsCommand.set(true, tag: tag, bundleID: bundleID, yes: yes) }
    }

    static func set(_ visible: Bool, tag reference: String, bundleID: String, yes: Bool) async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let tags = try await AppTags.list(appID: app.id, client: client)
      guard let tag = tags.first(where: { $0.id == reference || $0.name?.lowercased() == reference.lowercased() }) else {
        throw ValidationError("No tag '\(reference)'. Tags: \(tags.compactMap(\.name).joined(separator: ", ")).")
      }
      guard tag.visibleInAppStore != visible else {
        print("'\(tag.name ?? tag.id)' is already \(visible ? "shown" : "hidden").")
        return
      }
      guard confirm("\(visible ? "Show" : "Hide") '\(tag.name ?? tag.id)' on the App Store? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      try await AppTags.setVisible(visible, tagID: tag.id, client: client)
      print(green(visible ? "Shown" : "Hidden") + ": '\(tag.name ?? tag.id)'.")
    }
  }
}
