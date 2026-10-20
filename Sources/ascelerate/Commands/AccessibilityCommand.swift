import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

extension AppsCommand {
  /// The App Store's accessibility labels: what the app supports, declared per device family.
  struct AccessibilityCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "accessibility",
      abstract: "View or set the App Store accessibility declarations (per device family).",
      subcommands: [View.self, Set.self, Publish.self],
      defaultSubcommand: View.self
    )

    /// The declarable features: CLI name, API attribute, App Store label.
    static let features = AccessibilityDeclarations.features

    struct View: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Show the accessibility declarations per device family.")

      @Argument(help: "Bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Flag(name: .long, help: "Include declarations replaced by newer ones.")
      var all = false

      @OptionGroup var jsonOption: JSONOption

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let order = ASCEnum.DeviceFamily.allCases.map(\.rawValue)
        let declarations = try await AccessibilityDeclarations.list(appID: app.id, client: client)
          .filter { all || $0.state != "REPLACED" }
          .sorted { (order.firstIndex(of: $0.deviceFamily ?? "") ?? 99) < (order.firstIndex(of: $1.deviceFamily ?? "") ?? 99) }
        if jsonOption.json { try printJSON(declarations); return }
        guard !declarations.isEmpty else {
          print("No accessibility declarations yet. Set one with 'ascelerate apps accessibility set'.")
          return
        }
        let families = declarations.map { formatState($0.deviceFamily ?? "-") }
        Table.print(
          headers: ["Feature"] + families,
          rows: AccessibilityCommand.features.map { f in
            [f.label] + declarations.map { d in d.supports[f.name].map { $0 ? green("Yes") : "No" } ?? "-" }
          } + [Array(repeating: "", count: families.count + 1), ["State"] + declarations.map { formatState($0.state ?? "-") }]
        )
      }
    }

    struct Publish: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Publish the app's draft accessibility declarations as they are.")

      @Argument(help: "Bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let drafts = try await AccessibilityDeclarations.list(appID: app.id, client: client).filter { $0.state == "DRAFT" }
        guard !drafts.isEmpty else {
          print("No draft declarations to publish.")
          return
        }
        let families = drafts.map { formatState($0.deviceFamily ?? "-") }.joined(separator: ", ")
        guard confirm("Publish the \(families) declaration(s) of \(app.attributes?.name ?? bundleID)? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        for draft in drafts {
          // Under dry run every request is shown, not only the first.
          guard try await unlessDryRunStopped({
            try await AccessibilityDeclarations.publish(id: draft.id, client: client)
          }) != nil else { continue }
          print(green("Published") + " the \(formatState(draft.deviceFamily ?? "-")) declaration.")
        }
      }
    }

    struct Set: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Declare which accessibility features the app supports on a device family (every unlisted one: not supported).",
        discussion: "Features: \(AccessibilityCommand.features.map(\.name).joined(separator: ", ")). Declare only what users can rely on across the app's common tasks."
      )

      @Argument(help: "Bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Device family: iphone, ipad, mac, apple-tv, apple-watch, vision.")
      var device: String

      @Option(name: .long, help: "Supported features, comma-separated (e.g. voiceover,larger-text,dark-interface); 'none' for none.")
      var supports: String

      @Flag(name: .long, help: "Publish the declaration to the App Store (otherwise it stays a draft).")
      var publish = false

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let family: ASCEnum.DeviceFamily = try parseEnum(device.uppercased().replacingOccurrences(of: "-", with: "_"), name: "device")
        let names = supports.lowercased() == "none"
          ? [] : supports.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let known = Swift.Set(AccessibilityCommand.features.map(\.name))
        if let unknown = names.first(where: { !known.contains($0) }) {
          throw ValidationError("Unknown feature '\(unknown)'. Features: \(AccessibilityCommand.features.map(\.name).joined(separator: ", ")).")
        }
        let applicable = AccessibilityDeclarations.features(for: family.rawValue)
        if let other = names.first(where: { name in !applicable.contains { $0.name == name } }) {
          throw ValidationError("'\(other)' doesn't apply to \(formatState(family.rawValue)).")
        }
        let on = Swift.Set(names)
        let has = { (name: String) in on.contains(name) }

        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let existing = try await AccessibilityDeclarations.list(appID: app.id, client: client)
          .first { $0.deviceFamily == family.rawValue && $0.state != "REPLACED" }

        print("\(app.attributes?.name ?? bundleID), \(formatState(family.rawValue)):")
        for f in applicable {
          let before = existing?.supports[f.name].map { $0 ? "yes" : "no" } ?? "-"
          print("  \(f.label): \(has(f.name) ? green("yes") : "no")" + (existing == nil ? "" : " (now \(before))"))
        }
        guard confirm("\(existing == nil ? "Create" : "Update") this declaration\(publish ? " and publish it" : "")? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }

        if let existing {
          try await AccessibilityDeclarations.update(
            id: existing.id, deviceFamily: family.rawValue, supported: on, publish: publish, client: client)
          print(green("Updated") + " the \(formatState(family.rawValue)) declaration" + (publish ? " and published it." : "."))
        } else {
          let created = try await AccessibilityDeclarations.create(
            appID: app.id, deviceFamily: family.rawValue, supported: on, client: client)
          print(green("Created") + " the \(formatState(family.rawValue)) declaration.")
          if publish {
            try await AccessibilityDeclarations.publish(id: created.id, client: client)
            print(green("Published") + " it.")
          }
        }
      }
    }
  }
}
