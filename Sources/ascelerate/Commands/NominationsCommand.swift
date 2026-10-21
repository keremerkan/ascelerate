import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

/// Featuring nominations: tell Apple's editorial team about a launch, an update or new content.
struct NominationsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "nominations",
    abstract: "Featuring nominations for Apple's editorial team (launches, updates, new content).",
    subcommands: [List.self, Create.self, Update.self, Submit.self, Archive.self, Delete.self],
    defaultSubcommand: List.self
  )

  /// `launch`, `enhancements`, `new-content` (or the API values).
  static func type(_ value: String) throws -> ASCEnum.NominationCreateRequestType {
    let raw = switch value.lowercased() {
    case "launch": "APP_LAUNCH"
    case "enhancements", "update": "APP_ENHANCEMENTS"
    case "new-content", "content": "NEW_CONTENT"
    default: value.uppercased()
    }
    return try parseEnum(raw, name: "type")
  }

  static func devices(_ value: String?) throws -> [String]? {
    try value.map { list in
      try list.split(separator: ",").map { item in
        let family: ASCEnum.DeviceFamily = try parseEnum(
          item.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: "-", with: "_"), name: "device")
        return family.rawValue
      }
    }
  }

  static func list(_ value: String?) -> [String]? {
    value.map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
  }

  /// One nomination, as `list` prints it and `--json` emits it.
  struct Entry: Encodable {
    let id: String
    let name: String?
    let type: String?
    let state: String?
    let description: String?
    let publishStartDate: Date?
    let publishEndDate: Date?
    let deviceFamilies: [String]?
    let locales: [String]?
    let submittedDate: Date?
    let appIds: [String]?
  }

  /// The fields `create` and `update` share.
  struct Fields: ParsableArguments {
    @Option(name: .long, help: "Nomination name (what it's about, e.g. \"Version 5: offline maps\").")
    var name: String?

    @Option(name: .long, help: "Description for Apple's editors: what's new and why it matters.")
    var description: String?

    @Option(name: .long, help: "Type: launch, enhancements or new-content.")
    var type: String?

    @Option(name: .long, help: "Publish (release) date, yyyy-MM-dd or ISO 8601.")
    var publishStart: String?

    @Option(name: .long, help: "Optional end date (for limited-time content).")
    var publishEnd: String?

    @Option(name: .long, help: "Device families, comma-separated (iphone, ipad, mac, apple-tv, apple-watch, vision).")
    var devices: String?

    @Option(name: .long, help: "Locales the release is localized in, comma-separated (e.g. en-US,tr-TR).")
    var locales: String?

    @Option(name: .long, help: "Notes for Apple.")
    var notes: String?

    @Option(name: .long, help: "Links to supporting material (press kit, video), comma-separated.")
    var materials: String?
  }

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List nominations (drafts, submitted, archived).")

    @Option(name: .long, help: "Only nominations for this app (bundle ID or alias).")
    var app: String?

    @Option(name: .long, help: "Only this state: draft, submitted or archived.")
    var state: String?

    @OptionGroup var jsonOption: JSONOption

    func validate() throws {
      if let state, !["DRAFT", "SUBMITTED", "ARCHIVED"].contains(state.uppercased()) {
        throw ValidationError("Invalid state '\(state)'. Valid values: draft, submitted, archived.")
      }
    }

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      var appID: String?
      if let app { appID = try await findApp(bundleID: app, client: client).id }
      let states = state.map { [$0.uppercased()] } ?? Nominations.states
      let entries = try await Nominations.list(appID: appID, states: states, client: client).map { n in
        Entry(
          id: n.id, name: n.name, type: n.type, state: n.state, description: n.description,
          publishStartDate: n.publishStartDate, publishEndDate: n.publishEndDate,
          deviceFamilies: n.deviceFamilies.isEmpty ? nil : n.deviceFamilies, locales: n.locales.isEmpty ? nil : n.locales,
          submittedDate: n.submittedDate, appIds: n.appIDs.isEmpty ? nil : n.appIDs
        )
      }
      if jsonOption.json { try printJSON(entries); return }
      let rows: [[String]] = entries.map { e in
        let publish = e.publishStartDate.map { formatDate($0) } ?? "-"
        let devices = (e.deviceFamilies ?? []).map { formatState($0) }.joined(separator: ", ")
        return [e.id, e.name ?? "-", formatState(e.type ?? "-"), formatState(e.state ?? "-"), publish, devices]
      }
      Table.print(headers: ["ID", "Name", "Type", "State", "Publish", "Devices"], rows: rows)
    }
  }

  struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Create a nomination (a draft unless --submit).",
      discussion: "Featuring is up to Apple's editors; nominate well ahead of the release date."
    )

    @Option(name: .customLong("app"), parsing: .upToNextOption, help: "App(s) the nomination is about (bundle IDs or aliases).")
    var apps: [String]

    @OptionGroup var fields: Fields

    @Option(name: .long, help: "Territories it's available in first, comma-separated (e.g. USA,TUR); default: all.")
    var territories: String?

    @Flag(name: .long, help: "It's available for pre-order.")
    var preOrder = false

    @Flag(name: .long, help: "Submit to Apple now instead of saving a draft.")
    var submit = false

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func validate() throws {
      guard !apps.isEmpty else { throw ValidationError("Pass --app.") }
      guard fields.name != nil, fields.description != nil, fields.type != nil, fields.publishStart != nil else {
        throw ValidationError("--name, --description, --type and --publish-start are required.")
      }
    }

    func run() async throws {
      if yes { autoConfirm = true }
      let type = try NominationsCommand.type(fields.type ?? "")
      let start = try AppEventsCommand.parseEventDate(fields.publishStart ?? "", field: "publish-start")
      let end = try fields.publishEnd.map { try AppEventsCommand.parseEventDate($0, field: "publish-end") }
      let devices = try NominationsCommand.devices(fields.devices)
      let client = try ClientFactory.makeClient()
      var appIDs: [String] = []
      for app in apps { appIDs.append(try await findApp(bundleID: app, client: client).id) }
      let territories = NominationsCommand.list(territories)?.map { $0.uppercased() }

      print("\(submit ? "Submitting" : "Saving a draft of") the \(formatState(type.rawValue).lowercased()) nomination '\(fields.name ?? "")' for \(apps.joined(separator: ", ")), publishing \(fields.publishStart ?? "").")
      guard confirm("\(submit ? "Submit" : "Create") it? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      let created = try await Nominations.create(
        name: fields.name ?? "", type: type.rawValue, description: fields.description ?? "", publishStartDate: start,
        publishEndDate: end, appIDs: appIDs, deviceFamilies: devices, locales: NominationsCommand.list(fields.locales),
        territories: territories, launchInSelectMarketsFirst: territories == nil ? nil : true,
        preOrderEnabled: preOrder ? true : nil, notes: fields.notes,
        supplementalMaterials: NominationsCommand.list(fields.materials), submit: submit, client: client)
      print(green(submit ? "Submitted" : "Created") + " nomination \(created.id)" + (submit ? "." : " (draft; submit it with 'ascelerate nominations submit \(created.id)')."))
    }
  }

  struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Change a draft nomination.")

    @Argument(help: "Nomination ID (from 'nominations list').")
    var id: String

    @OptionGroup var fields: Fields

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let start = try fields.publishStart.map { try AppEventsCommand.parseEventDate($0, field: "publish-start") }
      let end = try fields.publishEnd.map { try AppEventsCommand.parseEventDate($0, field: "publish-end") }
      let type = try fields.type.map { try NominationsCommand.type($0).rawValue }
      guard confirm("Update nomination \(id)? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      try await Nominations.update(
        id: id, name: fields.name, type: type, description: fields.description, publishStartDate: start,
        publishEndDate: end.map { .some($0) }, deviceFamilies: try NominationsCommand.devices(fields.devices),
        locales: NominationsCommand.list(fields.locales), notes: fields.notes,
        supplementalMaterials: NominationsCommand.list(fields.materials), client: ClientFactory.makeClient())
      print(green("Updated") + " nomination \(id).")
    }
  }

  struct Submit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Submit a draft nomination to Apple.")
    @Argument(help: "Nomination ID.") var id: String
    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.") var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      try await NominationsCommand.confirmed(id, verb: "Submit", done: "Submitted") { try await Nominations.submit(id: id, client: $0) }
    }
  }

  struct Archive: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Archive a nomination.")
    @Argument(help: "Nomination ID.") var id: String
    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.") var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      try await NominationsCommand.confirmed(id, verb: "Archive", done: "Archived") { try await Nominations.archive(id: id, client: $0) }
    }
  }

  struct Delete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Delete a draft nomination.")
    @Argument(help: "Nomination ID.") var id: String
    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.") var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      try await NominationsCommand.confirmed(id, verb: "Delete", done: "Deleted") { try await Nominations.delete(id: id, client: $0) }
    }
  }

  private static func confirmed(
    _ id: String, verb: String, done: String, _ action: (ASCClient) async throws -> some Any
  ) async throws {
    guard confirm("\(verb) nomination \(id)? [y/N] ") else {
      print(yellow("Cancelled."))
      return
    }
    _ = try await action(ClientFactory.makeClient())
    print(green(done) + " nomination \(id).")
  }
}
