import AppStoreAPI
import AppStoreConnect
import ArgumentParser
import Foundation

struct AliasCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "alias",
    abstract: "Manage app aliases for bundle IDs.",
    subcommands: [Add.self, Remove.self, List.self]
  )

  struct Add: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Add or update an alias for an app."
    )

    @Argument(help: "The alias name (alphanumeric, dash, underscore).")
    var name: String?

    func run() async throws {
      let client = try ClientFactory.makeClient()

      // Fetch all apps and show picker
      var apps: [(id: String, bundleID: String, name: String)] = []
      for try await page in client.pages(Resources.v1.apps.get()) {
        for app in page.data {
          apps.append((
            id: app.id,
            bundleID: app.attributes?.bundleID ?? "—",
            name: app.attributes?.name ?? "—"
          ))
        }
      }

      guard !apps.isEmpty else {
        print("No apps found in your App Store Connect account.")
        return
      }

      apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

      let selected = try promptSelection(
        "Select an app",
        items: apps,
        display: { "\($0.name) (\($0.bundleID))" }
      )

      let name = self.name ?? promptText("Alias name: ")

      guard Aliases.isValidAliasName(name) else {
        throw ValidationError(
          "Invalid alias name '\(name)'. Use only letters, numbers, dashes, and underscores.")
      }

      var aliases = Aliases.load()
      if let existing = aliases[name], existing != selected.bundleID {
        guard confirm("Alias '\(name)' already points to \(existing). Update? [y/N] ") else { return }
      }
      aliases[name] = selected.bundleID
      try Aliases.save(aliases)

      print(green("Alias") + " '\(name)' → \(selected.bundleID)")
    }
  }

  struct Remove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Remove one or more aliases."
    )

    @Argument(help: "The alias name to remove.")
    var name: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() throws {
      if yes { autoConfirm = true }

      var aliases = Aliases.load()

      guard !aliases.isEmpty else {
        print("No aliases configured.")
        return
      }

      let names: [String]
      if let provided = self.name {
        guard aliases[provided] != nil else {
          throw ValidationError("Alias '\(provided)' not found.")
        }
        names = [provided]
      } else {
        let sorted = aliases.sorted { $0.key < $1.key }
        let entries = try promptMultiSelection(
          "Aliases",
          items: sorted,
          display: { "\($0.key) → \($0.value)" },
          prompt: "Select alias to remove"
        )
        names = entries.map(\.key)
      }

      let label = names.count == 1 ? "alias '\(names[0])'" : "\(names.count) aliases"
      guard confirm("Remove \(label)? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

      for name in names {
        aliases.removeValue(forKey: name)
      }
      try Aliases.save(aliases)
      print(green("Removed") + " \(label).")
    }
  }

  struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List all aliases."
    )

    func run() {
      let aliases = Aliases.load()

      guard !aliases.isEmpty else {
        print("No aliases configured. Use 'ascelerate alias add' to create one.")
        return
      }

      let sorted = aliases.sorted { $0.key < $1.key }
      Table.print(
        headers: ["Alias", "Bundle ID"],
        rows: sorted.map { [$0.key, $0.value] }
      )
    }
  }
}
