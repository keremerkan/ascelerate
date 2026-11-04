import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation
import ImageIO

struct GameCenterCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "game-center",
    abstract: "Game Center: achievements, leaderboards and leaderboard sets, their languages, images and order.",
    discussion: """
      Achievements, leaderboards and sets are named by their ID (the vendor identifier the game \
      uses), reference name or Apple ID. Their text and images live on a version: a new one \
      starts in Prepare for Submission and goes to App Review with the app (submit adds it to the \
      app's draft submission). Changing one that is live makes its next version first.
      """,
    subcommands: [Status.self, Enable.self, AppVersion.self, Achievements.self, Leaderboards.self, Sets.self, Matchmaking.self],
    defaultSubcommand: Status.self
  )

  /// The app and its Game Center record, or an error saying it's off.
  static func context(app reference: String, client: ASCClient) async throws -> (appID: String, detail: GameCenter.Detail) {
    let app = try await findApp(bundleID: reference, client: client)
    guard let detail = try await GameCenter.detail(appID: app.id, client: client) else {
      throw ValidationError("Game Center is off for this app. Turn it on with: ascelerate game-center enable \(reference)")
    }
    return (app.id, detail)
  }

  /// "an achievement", "a leaderboard".
  static func article(_ noun: String) -> String {
    ("aeiou".contains(noun.first ?? "x") ? "an " : "a ") + noun
  }

  static func versionText(_ version: GameCenter.Version?) -> String {
    guard let version else { return "-" }
    return "\(version.version ?? 0): \(formatState(version.state ?? "-"))"
  }

  /// Vendor identifiers, reference names or Apple IDs as Apple IDs, in that order.
  static func ids<Item: GameCenterItem>(_ list: String, in items: [Item]) throws -> [String] {
    try list.split(separator: ",").map { try find(String($0).trimmingCharacters(in: .whitespaces), in: items).id }
  }

  /// An item by vendor identifier, reference name or Apple ID.
  static func find<Item: GameCenterItem>(_ reference: String, in items: [Item]) throws -> Item {
    let key = reference.lowercased()
    guard let found = items.first(where: {
      $0.id == reference || $0.vendorIdentifier?.lowercased() == key || $0.referenceName?.lowercased() == key
    }) else {
      let known = items.map(\.displayName).joined(separator: ", ")
      throw ValidationError("No \(Item.noun) '\(reference)'.\(known.isEmpty ? "" : " Known: \(known).")")
    }
    return found
  }

  /// The version whose text and images can change: the latest when it's editable, else (after a
  /// confirmation) a new one. One in review can't change.
  static func editableVersion<Item: GameCenterItem>(of item: Item, client: ASCClient) async throws -> GameCenter.Version? {
    if let latest = item.latestVersion, latest.isEditable { return latest }
    if let state = item.latestVersion?.state, ["READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW"].contains(state) {
      throw ValidationError("'\(item.displayName)' is \(formatState(state)); its text and images can't change until App Review is done.")
    }
    let next = (item.latestVersion?.version ?? 0) + 1
    guard confirm("'\(item.displayName)' version \(item.latestVersion?.version ?? 0) is \(formatState(item.latestVersion?.state ?? "-")). Make version \(next) to change it? [y/N] ") else {
      print(yellow("Cancelled."))
      return nil
    }
    return try await unlessDryRunStopped { try await Item.createVersion(itemID: item.id, client: client) }
      ?? GameCenter.Version(id: "DRY-RUN-VERSION", version: next, state: "PREPARE_FOR_SUBMISSION")
  }

  /// A localization file's fields as "Label: value" lines.
  static func fieldLines(_ fields: some Encodable) throws -> [(String, String)] {
    Mirror(reflecting: fields).children.compactMap { child in
      guard let label = child.label else { return nil }
      let value = (child.value as? String?).flatMap(\.self)
      return (formatFieldName(label), value.map { $0.isEmpty ? "-" : $0 } ?? "-")
    }
  }

  // MARK: Status, enable, App Store version

  struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Whether Game Center is on, with its default leaderboard and counts.")

    @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
    var app: String

    @OptionGroup var jsonOption: JSONOption

    struct Result: Encodable {
      let enabled: Bool
      let detail: GameCenter.Detail?
      let achievements: Int?
      let leaderboards: Int?
      let leaderboardSets: Int?
    }

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: app, client: client)
      guard let detail = try await GameCenter.detail(appID: app.id, client: client) else {
        if jsonOption.json { try printJSON(Result(enabled: false, detail: nil, achievements: nil, leaderboards: nil, leaderboardSets: nil)); return }
        print("Game Center is off for this app. Turn it on with: ascelerate game-center enable \(self.app)")
        return
      }
      async let achievements = GameCenter.achievements(detailID: detail.id, client: client)
      async let leaderboards = GameCenter.leaderboards(detailID: detail.id, client: client)
      async let sets = GameCenter.leaderboardSets(detailID: detail.id, client: client)
      let (a, l, s) = try await (achievements, leaderboards, sets)
      if jsonOption.json {
        try printJSON(Result(enabled: true, detail: detail, achievements: a.count, leaderboards: l.count, leaderboardSets: s.count))
        return
      }
      let defaultLeaderboard = detail.defaultLeaderboardID.map { id in l.first { $0.id == id }?.displayName ?? id }
      Table.print(headers: ["", ""], rows: [
        ["Game Center", green("On")],
        ["Achievements", "\(a.count)"],
        ["Leaderboards", "\(l.count)"],
        ["Leaderboard sets", "\(s.count)"],
        ["Default leaderboard", defaultLeaderboard ?? "-"],
        ["Group", detail.groupID ?? "-"],
        ["Apple Arcade", detail.arcadeEnabled ? "Yes" : "No"],
      ])
    }
  }

  struct Enable: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Turn Game Center on for the app.",
      discussion: "The App Store Connect API can't turn it off again. The bundle ID needs the Game Center capability (bundle-ids enable-capability).")

    @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
    var app: String

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let found = try await findApp(bundleID: app, client: client)
      if try await GameCenter.detail(appID: found.id, client: client) != nil {
        print("Game Center is already on for \(found.attributes?.name ?? app).")
        return
      }
      print("Turning Game Center on can't be undone through the API.")
      guard confirm("Turn Game Center on for \(found.attributes?.name ?? app)? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      _ = try await GameCenter.enable(appID: found.id, client: client)
      print(green("Turned on") + " Game Center.")
    }
  }

  struct AppVersion: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "version",
      abstract: "Game Center on an App Store version (the version page's Game Center switch).")

    @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
    var app: String

    @Option(name: .long, help: "Version string. Defaults to the version being prepared.")
    var version: String?

    @OptionGroup var platformOption: PlatformOption

    @Option(name: .long, help: "Turn it on or off: true or false.")
    var enabled: Bool?

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let found = try await findApp(bundleID: app, client: client)
      let appVersion = try await findVersion(appID: found.id, versionString: version, platform: try platformOption.parsed(), client: client)
      let label = "\(appVersion.attributes?.versionString ?? "?") (\(formatState(appVersion.attributes?.platform ?? "-")))"
      let current = try await GameCenter.isEnabled(versionID: appVersion.id, client: client) ?? false
      guard let enabled else {
        print("Game Center on version \(label): \(current ? green("On") : "Off")")
        return
      }
      guard enabled != current else {
        print("Game Center is already \(enabled ? "on" : "off") on version \(label).")
        return
      }
      guard confirm("Turn Game Center \(enabled ? "on" : "off") on version \(label)? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      try await GameCenter.setEnabled(enabled, versionID: appVersion.id, client: client)
      print(green(enabled ? "Turned on" : "Turned off") + " Game Center on version \(label).")
    }
  }
}

// MARK: - Commands every kind shares

/// The app and an item of `Item`'s kind, given on the command line.
struct GameCenterItemArguments: ParsableArguments {
  @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
  var app: String

  @Argument(help: "Its ID (vendor identifier), reference name or Apple ID.")
  var item: String
}

struct GameCenterDelete<Item: GameCenterItem>: AsyncParsableCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "delete",
      abstract: "Delete \(GameCenterCommand.article(Item.noun)).",
      discussion: "One that has been live can't be deleted; archive it instead (update --archived true).")
  }

  @OptionGroup var arguments: GameCenterItemArguments

  @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
  var yes = false

  func run() async throws {
    if yes { autoConfirm = true }
    let client = try ClientFactory.makeClient()
    let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
    let item = try GameCenterCommand.find(arguments.item, in: try await Item.list(detailID: detail.id, client: client))
    guard confirm("Delete the \(Item.noun) '\(item.displayName)'? [y/N] ") else {
      print(yellow("Cancelled."))
      return
    }
    try await Item.delete(id: item.id, client: client)
    print(green("Deleted") + " '\(item.displayName)'.")
  }
}

struct GameCenterReorder<Item: GameCenterItem>: AsyncParsableCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "reorder",
      abstract: "Set the order Game Center shows them in.",
      discussion: "The ones listed come first, in that order; the rest follow in their current order.")
  }

  @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
  var app: String

  @Argument(help: "IDs (vendor identifiers), reference names or Apple IDs, comma-separated.")
  var order: String

  @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
  var yes = false

  func run() async throws {
    if yes { autoConfirm = true }
    let client = try ClientFactory.makeClient()
    let (_, detail) = try await GameCenterCommand.context(app: app, client: client)
    let items = try await Item.list(detailID: detail.id, client: client)
    let first = try GameCenterCommand.ids(order, in: items)
    let ordered = first + items.map(\.id).filter { !first.contains($0) }
    guard ordered != items.map(\.id) else {
      print("Already in this order.")
      return
    }
    let names = Dictionary(items.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
    for (i, id) in ordered.enumerated() { print("  \(i + 1). \(names[id] ?? id)") }
    guard confirm("Save this order? [y/N] ") else {
      print(yellow("Cancelled."))
      return
    }
    try await Item.reorder(detailID: detail.id, ids: ordered, client: client)
    print(green("Reordered") + ".")
  }
}

struct GameCenterSubmit<Item: GameCenterItem>: AsyncParsableCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "submit",
      abstract: "Add \(GameCenterCommand.article(Item.noun))'s new version to the app's draft submission for App Review.",
      discussion: "It's reviewed with the draft: submit that with apps review submit. A draft is made when there's none.")
  }

  @OptionGroup var arguments: GameCenterItemArguments

  @Option(name: .long, help: "The submission's platform: ios, macos, tvos, visionos (default ios).")
  var platform: String?

  @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
  var yes = false

  func run() async throws {
    if yes { autoConfirm = true }
    let client = try ClientFactory.makeClient()
    let (appID, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
    let item = try GameCenterCommand.find(arguments.item, in: try await Item.list(detailID: detail.id, client: client))
    guard let version = item.latestVersion, version.state == "PREPARE_FOR_SUBMISSION" || version.state == "REJECTED"
      || version.state == "DEVELOPER_REJECTED"
    else {
      throw ValidationError("'\(item.displayName)' has no version to submit (latest: \(GameCenterCommand.versionText(item.latestVersion))).")
    }
    let platform = (try platform.map(parsePlatform) ?? .ios).rawValue
    guard confirm("Add '\(item.displayName)' version \(version.version ?? 0) to the \(formatState(platform)) draft submission? [y/N] ") else {
      print(yellow("Cancelled."))
      return
    }
    try await ReviewSubmissions.add(Item.reviewItem(versionID: version.id), appID: appID, platform: platform, client: client)
    guard !ClientFactory.isDryRun else { print("Dry run: nothing was added."); return }
    print(green("Added") + " '\(item.displayName)' to the draft submission. Submit it with: ascelerate apps review submit \(arguments.app)")
  }
}

/// A version's languages: view, export, import, delete.
struct GameCenterLocalizations<Item: GameCenterItem>: AsyncParsableCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "localizations",
      abstract: "\(GameCenterCommand.article(Item.noun).prefix(1).uppercased() + GameCenterCommand.article(Item.noun).dropFirst())'s languages (of its latest version).",
      subcommands: [View.self, Export.self, Import.self, Delete.self],
      defaultSubcommand: View.self)
  }

  struct View: AsyncParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(abstract: "Show the languages.") }

    @OptionGroup var arguments: GameCenterItemArguments

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
      let item = try GameCenterCommand.find(arguments.item, in: try await Item.list(detailID: detail.id, client: client))
      guard let version = item.latestVersion else {
        print("No version.")
        return
      }
      let localizations = try await Item.localizations(versionID: version.id, client: client)
      print("'\(item.displayName)', version \(GameCenterCommand.versionText(version)):")
      guard !localizations.isEmpty else {
        print("No languages yet.")
        return
      }
      for l in localizations {
        print()
        print(bold(localeName(l.locale)))
        let lines = try GameCenterCommand.fieldLines(l.fields)
        let width = max(lines.map(\.0.count).max() ?? 0, "Image".count)
        for (label, value) in lines { print("  \(label.padding(toLength: width, withPad: " ", startingAt: 0))  \(value)") }
        print("  \("Image".padding(toLength: width, withPad: " ", startingAt: 0))  " + (l.image.map { "\($0.fileName) (\(formatState($0.state ?? "-")))" } ?? "-"))
      }
    }
  }

  struct Export: AsyncParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(abstract: "Write the languages to a JSON file.") }

    @OptionGroup var arguments: GameCenterItemArguments

    @Option(name: .long, help: "Output file path.", completion: .file(extensions: ["json"]))
    var output: String?

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
      let item = try GameCenterCommand.find(arguments.item, in: try await Item.list(detailID: detail.id, client: client))
      var localizations: [Item.Localization] = []
      if let version = item.latestVersion { localizations = try await Item.localizations(versionID: version.id, client: client) }
      guard !localizations.isEmpty else { throw ValidationError("'\(item.displayName)' has no languages to export.") }
      let file = Dictionary(localizations.map { ($0.locale, $0.fields) }, uniquingKeysWith: { a, _ in a })
      let path = confirmOutputPath(expandPath(output ?? "\(item.displayName)-localizations.json"), isDirectory: false)
      try LocalizationFile.encode(file).write(to: URL(fileURLWithPath: path))
      print(green("Exported") + " \(file.count) language\(file.count == 1 ? "" : "s") to \(path).")
    }
  }

  struct Import: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
      CommandConfiguration(
        abstract: "Create or change languages from a JSON file (the export format).",
        discussion: "Fields left out of the file stay as they are. A live version gets a new version first.")
    }

    @OptionGroup var arguments: GameCenterItemArguments

    @Option(name: .long, help: "Path to the JSON file.", completion: .file(extensions: ["json"]))
    var file: String?

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let path = try resolveFile(file, extension: "json", prompt: "Select a JSON file")
      let updates = try LocalizationFile.decode(try Data(contentsOf: URL(fileURLWithPath: path)), as: Item.Localization.Fields.self)
      let client = try ClientFactory.makeClient()
      let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
      let item = try GameCenterCommand.find(arguments.item, in: try await Item.list(detailID: detail.id, client: client))
      guard let version = try await GameCenterCommand.editableVersion(of: item, client: client) else { return }
      let existing = version.id.hasPrefix("DRY-RUN") ? [] : try await Item.localizations(versionID: version.id, client: client)
      let byLocale = Dictionary(existing.map { ($0.locale.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
      let changes = updates.keys.sorted().filter { byLocale[$0.lowercased()]?.fields != updates[$0] }
      guard !changes.isEmpty else {
        print("Nothing to change.")
        return
      }
      for locale in changes { print("  \(byLocale[locale.lowercased()] == nil ? "Add" : "Update") \(localeName(locale))") }
      guard confirm("Save \(changes.count) language\(changes.count == 1 ? "" : "s") of '\(item.displayName)'? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      var failed = 0
      for locale in changes {
        do {
          let done = try await unlessDryRunStopped {
            try await Item.saveLocalization(
              versionID: version.id, locale: locale, existing: byLocale[locale.lowercased()], fields: updates[locale]!, client: client)
          }
          if done != nil { print(green("Saved") + " \(localeName(locale)).") }
        } catch {
          failed += 1
          print(red("Failed") + " \(localeName(locale)): \(describeError(error))")
        }
      }
      if failed > 0 { throw ExitCode.failure }
    }
  }

  struct Delete: AsyncParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(abstract: "Delete a language (and its image).") }

    @OptionGroup var arguments: GameCenterItemArguments

    @Option(name: .long, help: "The language's locale code (en-US).")
    var locale: String

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
      let item = try GameCenterCommand.find(arguments.item, in: try await Item.list(detailID: detail.id, client: client))
      guard let version = try await GameCenterCommand.editableVersion(of: item, client: client) else { return }
      let existing = version.id.hasPrefix("DRY-RUN") ? [] : try await Item.localizations(versionID: version.id, client: client)
      guard let localization = existing.first(where: { $0.locale.lowercased() == locale.lowercased() }) else {
        throw ValidationError("'\(item.displayName)' has no \(localeName(locale)).")
      }
      guard confirm("Delete \(localeName(localization.locale)) of '\(item.displayName)'? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      try await Item.deleteLocalization(id: localization.id, client: client)
      print(green("Deleted") + " \(localeName(localization.locale)).")
    }
  }
}

/// A language's image: upload (replacing the current one) or delete.
struct GameCenterImage<Item: GameCenterItem>: AsyncParsableCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "image",
      abstract: "A language's image (one per language).",
      discussion: "Game Center takes a square PNG or JPEG of at least 512×512 (512×512 or 1024×1024).",
      subcommands: [Upload.self, Delete.self])
  }

  /// Game Center takes a square image of at least 512 pixels (seen live 2026-11-04: 600 and 2048
  /// were taken; 100 and 511 failed with IMAGE_BAD_DIMENSION_SM_LESS_MIN, a screenshot with
  /// IMAGE_BAD_ASPECT_RATIO).
  static func checkSize(_ path: String) throws {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { throw ValidationError("'\(path)' isn't an image.") }
    guard width == height, width >= 512 else {
      throw ValidationError("The image is \(width)×\(height); Game Center takes a square one of at least 512×512 (512×512 or 1024×1024).")
    }
  }

  /// The language's localization on an editable version.
  static func localization(
    _ arguments: GameCenterItemArguments, locale: String, client: ASCClient
  ) async throws -> (Item, Item.Localization, GameCenter.Version)? {
    let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
    let item = try GameCenterCommand.find(arguments.item, in: try await Item.list(detailID: detail.id, client: client))
    guard let version = try await GameCenterCommand.editableVersion(of: item, client: client) else { return nil }
    if version.id.hasPrefix("DRY-RUN") {
      throw ValidationError("Dry run: the new version wasn't made, so it has no languages to add an image to yet.")
    }
    guard let localization = try await Item.localizations(versionID: version.id, client: client)
      .first(where: { $0.locale.lowercased() == locale.lowercased() })
    else {
      throw ValidationError("'\(item.displayName)' has no \(localeName(locale)); add it first (localizations import or set).")
    }
    return (item, localization, version)
  }

  struct Upload: AsyncParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(abstract: "Upload a language's image.") }

    @OptionGroup var arguments: GameCenterItemArguments

    @Option(name: .long, help: "The language's locale code (en-US).")
    var locale: String

    @Argument(help: "The image file (PNG or JPEG).", completion: .file(extensions: ["png", "jpg", "jpeg"]))
    var file: String

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let path = expandPath(file)
      guard FileManager.default.fileExists(atPath: path) else { throw ValidationError("File not found at '\(path)'.") }
      try GameCenterImage.checkSize(path)
      let client = try ClientFactory.makeClient()
      guard let (item, localization, version) = try await GameCenterImage.localization(arguments, locale: locale, client: client) else { return }
      let replacing = localization.image.map { " (replacing \($0.fileName))" } ?? ""
      guard confirm("Upload \((path as NSString).lastPathComponent) for \(localeName(localization.locale)) of '\(item.displayName)'\(replacing)? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      if let old = localization.image {
        guard try await unlessDryRunStopped({ try await Item.deleteImage(id: old.id, client: client) }) != nil else { return }
      }
      let imageID = try await Item.uploadImage(localizationID: localization.id, filePath: path, client: client)
      // Apple checks the file in a few seconds; wait for its verdict, up to half a minute.
      for _ in 0..<15 {
        try await Task.sleep(for: .seconds(2))
        let image = try await Item.localizations(versionID: version.id, client: client).first { $0.id == localization.id }?.image
        guard let image, image.id == imageID else { continue }
        if image.state == "COMPLETE" {
          print(green("Uploaded") + " the image.")
          return
        }
        if image.state == "FAILED" {
          print(red("Apple refused the image") + ": \((image.errors ?? []).joined(separator: ", ")).")
          throw ExitCode.failure
        }
      }
      print(green("Uploaded") + " the image; Apple is still processing it (localizations shows its state).")
    }
  }

  struct Delete: AsyncParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(abstract: "Delete a language's image.") }

    @OptionGroup var arguments: GameCenterItemArguments

    @Option(name: .long, help: "The language's locale code (en-US).")
    var locale: String

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      guard let (item, localization, _) = try await GameCenterImage.localization(arguments, locale: locale, client: client) else { return }
      guard let image = localization.image else {
        print("\(localeName(localization.locale)) of '\(item.displayName)' has no image.")
        return
      }
      guard confirm("Delete \(image.fileName) of \(localeName(localization.locale))? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      try await Item.deleteImage(id: image.id, client: client)
      print(green("Deleted") + " the image.")
    }
  }
}

/// Saves one language given by flags (a kind's `localizations set`).
func saveGameCenterLocale<Item: GameCenterItem>(
  _ type: Item.Type, arguments: GameCenterItemArguments, locale: String, yes: Bool,
  fields: (Item.Localization.Fields?) -> Item.Localization.Fields
) async throws {
  if yes { autoConfirm = true }
  let client = try ClientFactory.makeClient()
  let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
  let item = try GameCenterCommand.find(arguments.item, in: try await Item.list(detailID: detail.id, client: client))
  guard let version = try await GameCenterCommand.editableVersion(of: item, client: client) else { return }
  let existing = version.id.hasPrefix("DRY-RUN")
    ? nil : try await Item.localizations(versionID: version.id, client: client).first { $0.locale.lowercased() == locale.lowercased() }
  let new = fields(existing?.fields)
  guard new != existing?.fields else {
    print("Nothing to change.")
    return
  }
  for (label, value) in try GameCenterCommand.fieldLines(new) { print("  \(label): \(value)") }
  guard confirm("\(existing == nil ? "Add" : "Update") \(localeName(locale)) of '\(item.displayName)'? [y/N] ") else {
    print(yellow("Cancelled."))
    return
  }
  try await Item.saveLocalization(versionID: version.id, locale: existing?.locale ?? locale, existing: existing, fields: new, client: client)
  print(green("Saved") + " \(localeName(locale)).")
}

// MARK: - Achievements

extension GameCenterCommand {
  struct Achievements: AsyncParsableCommand {
    typealias Item = GameCenter.Achievement

    static let configuration = CommandConfiguration(
      abstract: "Achievements: list, create, change, languages, images, order, App Review.",
      subcommands: [
        List.self, Info.self, Create.self, Update.self, GameCenterDelete<Item>.self, GameCenterReorder<Item>.self,
        Localizations.self, GameCenterImage<Item>.self, GameCenterSubmit<Item>.self,
      ],
      defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "The app's achievements in Game Center's order.")

      @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
      var app: String

      @OptionGroup var jsonOption: JSONOption

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: app, client: client)
        let achievements = try await GameCenter.achievements(detailID: detail.id, client: client)
        if jsonOption.json { try printJSON(achievements); return }
        guard !achievements.isEmpty else {
          print("No achievements.")
          return
        }
        Table.print(
          headers: ["ID", "Reference Name", "Points", "Before Earned", "Repeatable", "Version"],
          rows: achievements.map { a -> [String] in
            let name = (a.referenceName ?? "-") + (a.archived ? yellow(" (archived)") : "")
            return [
              a.vendorIdentifier ?? a.id, name, a.points.map(String.init) ?? "-", a.showBeforeEarned ? "Shown" : "Hidden",
              a.repeatable ? "Yes" : "No", GameCenterCommand.versionText(a.latestVersion),
            ]
          })
        print("Total points: \(achievements.filter { !$0.archived }.compactMap(\.points).reduce(0, +)) of 1000")
      }
    }

    struct Info: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "An achievement with its versions and languages.")

      @OptionGroup var arguments: GameCenterItemArguments

      @OptionGroup var jsonOption: JSONOption

      struct Result: Encodable {
        let achievement: Item
        let localizations: [GameCenter.AchievementLocalization]
      }

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
        let found = try GameCenterCommand.find(arguments.item, in: try await GameCenter.achievements(detailID: detail.id, client: client))
        var localizations: [GameCenter.AchievementLocalization] = []
        if let version = found.latestVersion {
          localizations = try await GameCenter.achievementLocalizations(versionID: version.id, client: client)
        }
        if jsonOption.json { try printJSON(Result(achievement: found, localizations: localizations)); return }
        print(bold(found.referenceName ?? found.id))
        Table.print(headers: ["", ""], rows: [
          ["ID", found.vendorIdentifier ?? "-"],
          ["Points", found.points.map(String.init) ?? "-"],
          ["Before earned", found.showBeforeEarned ? "Shown" : "Hidden"],
          ["Repeatable", found.repeatable ? "Yes" : "No"],
          ["Archived", found.archived ? "Yes" : "No"],
          ["Versions", found.versions.map { GameCenterCommand.versionText($0) }.joined(separator: ", ")],
          ["Apple ID", found.id],
        ])
        guard !localizations.isEmpty else {
          print("No languages yet.")
          return
        }
        print()
        Table.print(
          headers: ["Language", "Name", "Before Earned", "After Earned", "Image"],
          rows: localizations.map { l -> [String] in
            let image = l.image.map { "\($0.fileName) (\(formatState($0.state ?? "-")))" } ?? "-"
            return [localeName(l.locale), l.name ?? "-", l.beforeEarnedDescription ?? "-", l.afterEarnedDescription ?? "-", image]
          })
      }
    }

    struct Create: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Create an achievement.",
        discussion: "An app's achievements share 1,000 points, and one gives at most 100. Add its languages with localizations set or import.")

      @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
      var app: String

      @Option(name: .long, help: "Its ID, which the game reports it with (can't change later).")
      var id: String

      @Option(name: .long, help: "Its reference name, seen only in App Store Connect.")
      var name: String

      @Option(name: .long, help: "Points it gives (1 to 100).")
      var points: Int

      @Flag(name: .long, help: "Hidden from players until they earn it.")
      var hidden = false

      @Flag(name: .long, help: "It can be earned more than once.")
      var repeatable = false

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        guard (1...100).contains(points) else { throw ValidationError("--points must be from 1 to 100.") }
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: app, client: client)
        let existing = try await GameCenter.achievements(detailID: detail.id, client: client)
        let total = existing.filter { !$0.archived }.compactMap(\.points).reduce(0, +)
        if total + points > 1000 {
          throw ValidationError("The app's achievements already give \(total) points; \(points) more would pass 1,000.")
        }
        print("Achievement \(id) '\(name)': \(points) points, \(hidden ? "hidden" : "shown") before earned\(repeatable ? ", repeatable" : "").")
        guard confirm("Create it? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        let created = try await GameCenter.createAchievement(
          detailID: detail.id, vendorIdentifier: id, referenceName: name, points: points, showBeforeEarned: !hidden,
          repeatable: repeatable, client: client)
        print(green("Created") + " '\(created.displayName)' (version \(GameCenterCommand.versionText(created.latestVersion))).")
      }
    }

    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Change an achievement's reference name, points or flags.")

      @OptionGroup var arguments: GameCenterItemArguments

      @Option(name: .long, help: "A new reference name.")
      var name: String?

      @Option(name: .long, help: "Points it gives (1 to 100).")
      var points: Int?

      @Option(name: .long, help: "Hidden from players until earned: true or false.")
      var hidden: Bool?

      @Option(name: .long, help: "Can be earned more than once: true or false.")
      var repeatable: Bool?

      @Option(name: .long, help: "Archived (no longer shown or earned): true or false.")
      var archived: Bool?

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        guard name != nil || points != nil || hidden != nil || repeatable != nil || archived != nil else {
          throw ValidationError("Give --name, --points, --hidden, --repeatable or --archived.")
        }
        if let points, !(1...100).contains(points) { throw ValidationError("--points must be from 1 to 100.") }
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
        let a = try GameCenterCommand.find(arguments.item, in: try await GameCenter.achievements(detailID: detail.id, client: client))
        var lines: [String] = []
        if let name, name != a.referenceName { lines.append("Reference name: \(a.referenceName ?? "-") → \(name)") }
        if let points, points != a.points { lines.append("Points: \(a.points.map(String.init) ?? "-") → \(points)") }
        if let hidden, hidden == a.showBeforeEarned { lines.append("Before earned: \(a.showBeforeEarned ? "Shown" : "Hidden") → \(hidden ? "Hidden" : "Shown")") }
        if let repeatable, repeatable != a.repeatable { lines.append("Repeatable: \(a.repeatable ? "Yes" : "No") → \(repeatable ? "Yes" : "No")") }
        if let archived, archived != a.archived { lines.append("Archived: \(a.archived ? "Yes" : "No") → \(archived ? "Yes" : "No")") }
        guard !lines.isEmpty else {
          print("Nothing to change.")
          return
        }
        print("'\(a.displayName)':")
        for line in lines { print("  \(line)") }
        guard confirm("Save? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        try await GameCenter.updateAchievement(
          id: a.id, referenceName: name, points: points, showBeforeEarned: hidden.map { !$0 }, repeatable: repeatable,
          archived: archived, client: client)
        print(green("Updated") + " '\(a.displayName)'.")
      }
    }

    struct Localizations: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "An achievement's languages (of its latest version).",
        subcommands: [
          GameCenterLocalizations<Item>.View.self, Set.self, GameCenterLocalizations<Item>.Export.self,
          GameCenterLocalizations<Item>.Import.self, GameCenterLocalizations<Item>.Delete.self,
        ],
        defaultSubcommand: GameCenterLocalizations<Item>.View.self)

      struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Add or change one language.", discussion: "A new language needs all three texts.")

        @OptionGroup var arguments: GameCenterItemArguments

        @Option(name: .long, help: "The language's locale code (en-US).")
        var locale: String

        @Option(name: .long, help: "The name players see.")
        var name: String?

        @Option(name: .long, help: "The description before it's earned.")
        var beforeEarned: String?

        @Option(name: .long, help: "The description once it's earned.")
        var afterEarned: String?

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          guard name != nil || beforeEarned != nil || afterEarned != nil else {
            throw ValidationError("Give --name, --before-earned or --after-earned.")
          }
          try await saveGameCenterLocale(Item.self, arguments: arguments, locale: locale, yes: yes) { current in
            var fields = current ?? .init()
            if let name { fields.name = name }
            if let beforeEarned { fields.beforeEarnedDescription = beforeEarned }
            if let afterEarned { fields.afterEarnedDescription = afterEarned }
            return fields
          }
        }
      }
    }
  }
}

// MARK: - Leaderboards

extension GameCenterCommand {
  struct Leaderboards: AsyncParsableCommand {
    typealias Item = GameCenter.Leaderboard

    static let configuration = CommandConfiguration(
      abstract: "Leaderboards: list, create, change, languages, images, order, the default one, App Review.",
      subcommands: [
        List.self, Info.self, Create.self, Update.self, Default.self, GameCenterDelete<Item>.self, GameCenterReorder<Item>.self,
        Localizations.self, GameCenterImage<Item>.self, GameCenterSubmit<Item>.self,
      ],
      defaultSubcommand: List.self
    )

    /// The settings the create and update options give.
    struct SettingsOptions: ParsableArguments {
      @Option(name: .long, help: "How scores read: \(GameCenter.formatters.map { $0.lowercased().replacingOccurrences(of: "_", with: "-") }.joined(separator: ", ")).")
      var formatter: String?

      @Option(name: .long, help: "high (higher scores rank first) or low.")
      var sort: String?

      @Option(name: .long, help: "best (each player's best score counts) or recent (their latest).")
      var submission: String?

      @Option(name: .long, help: "The lowest score accepted (\"\" clears it).")
      var min: String?

      @Option(name: .long, help: "The highest score accepted (\"\" clears it).")
      var max: String?

      @Option(name: .long, help: "A recurring leaderboard's first start (ISO 8601, 2026-12-01T00:00:00Z).")
      var recurrenceStart: String?

      @Option(name: .long, help: "How long each occurrence lasts, in hours or minutes (ISO 8601: PT24H, PT168H for a week; \"\" clears).")
      var recurrenceDuration: String?

      @Option(name: .long, help: "How often it restarts: FREQ=MINUTELY, HOURLY or DAILY and an INTERVAL (FREQ=DAILY;INTERVAL=7 for weekly; \"\" clears).")
      var recurrenceRule: String?

      @Option(name: .long, help: "Hidden from players: true or false.")
      var hidden: Bool?

      func settings(referenceName: String?, archived: Bool? = nil) throws -> GameCenter.LeaderboardSettings {
        var start: Date?
        if let recurrenceStart {
          guard let date = ISO8601DateFormatter().date(from: recurrenceStart) else {
            throw ValidationError("--recurrence-start must be ISO 8601, like 2026-12-01T00:00:00Z.")
          }
          start = date
        }
        return GameCenter.LeaderboardSettings(
          referenceName: referenceName, defaultFormatter: try formatter.map(Leaderboards.formatter),
          submissionType: try submission.map {
            switch $0.lowercased() {
              case "best": "BEST_SCORE"
              case "recent": "MOST_RECENT_SCORE"
              default: throw ValidationError("--submission is best or recent.")
            }
          },
          scoreSortType: try sort.map {
            switch $0.lowercased() {
              case "high", "desc": "DESC"
              case "low", "asc": "ASC"
              default: throw ValidationError("--sort is high or low.")
            }
          },
          scoreRangeStart: min, scoreRangeEnd: max, recurrenceStartDate: start, recurrenceDuration: recurrenceDuration,
          recurrenceRule: recurrenceRule, visibility: hidden.map { $0 ? "HIDE_FOR_ALL" : "SHOW_FOR_ALL" }, archived: archived)
      }
    }

    /// `money-dollar` → `MONEY_DOLLAR`.
    static func formatter(_ value: String) throws -> String {
      let raw = value.uppercased().replacingOccurrences(of: "-", with: "_")
      guard GameCenter.formatters.contains(raw) else {
        throw ValidationError("No formatter '\(value)'. Formatters: \(GameCenter.formatters.map { $0.lowercased().replacingOccurrences(of: "_", with: "-") }.joined(separator: ", ")).")
      }
      return raw
    }

    static func sortText(_ raw: String?) -> String { raw == "ASC" ? "Low first" : raw == "DESC" ? "High first" : "-" }
    static func submissionText(_ raw: String?) -> String { raw == "BEST_SCORE" ? "Best" : raw == "MOST_RECENT_SCORE" ? "Most recent" : "-" }
    static func rangeText(_ l: Item) -> String {
      l.scoreRangeStart == nil && l.scoreRangeEnd == nil ? "-" : "\(l.scoreRangeStart ?? "…") to \(l.scoreRangeEnd ?? "…")"
    }
    static func recurrenceText(_ l: Item) -> String {
      guard l.recurrenceRule != nil || l.recurrenceDuration != nil else { return "-" }
      return [l.recurrenceStartDate.map { "from \(formatDate($0))" }, l.recurrenceDuration.map { "lasting \($0)" }, l.recurrenceRule]
        .compactMap(\.self).joined(separator: ", ")
    }

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "The app's leaderboards in Game Center's order.")

      @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
      var app: String

      @OptionGroup var jsonOption: JSONOption

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: app, client: client)
        let leaderboards = try await GameCenter.leaderboards(detailID: detail.id, client: client)
        if jsonOption.json { try printJSON(leaderboards); return }
        guard !leaderboards.isEmpty else {
          print("No leaderboards.")
          return
        }
        Table.print(
          headers: ["ID", "Reference Name", "Format", "Sort", "Scores", "Recurring", "Version"],
          rows: leaderboards.map { l -> [String] in
            let name = (l.referenceName ?? "-") + (l.id == detail.defaultLeaderboardID ? " (default)" : "")
              + (l.archived ? yellow(" (archived)") : "") + (l.visibility == "HIDE_FOR_ALL" ? yellow(" (hidden)") : "")
            return [
              l.vendorIdentifier ?? l.id, name, formatState(l.defaultFormatter ?? "-"), Leaderboards.sortText(l.scoreSortType),
              Leaderboards.submissionText(l.submissionType), l.recurrenceRule == nil ? "No" : "Yes",
              GameCenterCommand.versionText(l.latestVersion),
            ]
          })
      }
    }

    struct Info: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "A leaderboard with its versions and languages.")

      @OptionGroup var arguments: GameCenterItemArguments

      @OptionGroup var jsonOption: JSONOption

      struct Result: Encodable {
        let leaderboard: Item
        let localizations: [GameCenter.LeaderboardLocalization]
      }

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
        let l = try GameCenterCommand.find(arguments.item, in: try await GameCenter.leaderboards(detailID: detail.id, client: client))
        var localizations: [GameCenter.LeaderboardLocalization] = []
        if let version = l.latestVersion {
          localizations = try await GameCenter.leaderboardLocalizations(versionID: version.id, client: client)
        }
        if jsonOption.json { try printJSON(Result(leaderboard: l, localizations: localizations)); return }
        print(bold(l.referenceName ?? l.id))
        Table.print(headers: ["", ""], rows: [
          ["ID", l.vendorIdentifier ?? "-"],
          ["Format", formatState(l.defaultFormatter ?? "-")],
          ["Sort", Leaderboards.sortText(l.scoreSortType)],
          ["Scores counted", Leaderboards.submissionText(l.submissionType)],
          ["Score range", Leaderboards.rangeText(l)],
          ["Recurrence", Leaderboards.recurrenceText(l)],
          ["Shown to players", l.visibility == "HIDE_FOR_ALL" ? "No" : "Yes"],
          ["Default", l.id == detail.defaultLeaderboardID ? "Yes" : "No"],
          ["Archived", l.archived ? "Yes" : "No"],
          ["Versions", l.versions.map { GameCenterCommand.versionText($0) }.joined(separator: ", ")],
          ["Apple ID", l.id],
        ])
        guard !localizations.isEmpty else {
          print("No languages yet.")
          return
        }
        print()
        Table.print(
          headers: ["Language", "Name", "Description", "Format", "Suffix", "Image"],
          rows: localizations.map { loc -> [String] in
            let image = loc.image.map { "\($0.fileName) (\(formatState($0.state ?? "-")))" } ?? "-"
            let suffix = [loc.formatterSuffixSingular, loc.formatterSuffix].compactMap(\.self).joined(separator: " / ")
            return [
              localeName(loc.locale), loc.name ?? "-", loc.description ?? "-", loc.formatterOverride.map { formatState($0) } ?? "-",
              suffix.isEmpty ? "-" : suffix, image,
            ]
          })
      }
    }

    struct Create: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Create a leaderboard.",
        discussion: "Defaults: integer scores, high first, each player's best. A recurring one needs --recurrence-start, --recurrence-duration and --recurrence-rule.")

      @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
      var app: String

      @Option(name: .long, help: "Its ID, which the game submits scores with (can't change later).")
      var id: String

      @Option(name: .long, help: "Its reference name, seen only in App Store Connect.")
      var name: String

      @OptionGroup var options: SettingsOptions

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        var settings = try options.settings(referenceName: name)
        settings.defaultFormatter = settings.defaultFormatter ?? "INTEGER"
        settings.scoreSortType = settings.scoreSortType ?? "DESC"
        settings.submissionType = settings.submissionType ?? "BEST_SCORE"
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: app, client: client)
        print("Leaderboard \(id) '\(name)': \(formatState(settings.defaultFormatter!)), \(Leaderboards.sortText(settings.scoreSortType).lowercased()), \(Leaderboards.submissionText(settings.submissionType).lowercased()) score.")
        guard confirm("Create it? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        let created = try await GameCenter.createLeaderboard(detailID: detail.id, vendorIdentifier: id, settings: settings, client: client)
        print(green("Created") + " '\(created.displayName)' (version \(GameCenterCommand.versionText(created.latestVersion))).")
      }
    }

    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Change a leaderboard's settings.")

      @OptionGroup var arguments: GameCenterItemArguments

      @Option(name: .long, help: "A new reference name.")
      var name: String?

      @OptionGroup var options: SettingsOptions

      @Option(name: .long, help: "Archived (no longer shown or scored): true or false.")
      var archived: Bool?

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let settings = try options.settings(referenceName: name, archived: archived)
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
        let l = try GameCenterCommand.find(arguments.item, in: try await GameCenter.leaderboards(detailID: detail.id, client: client))
        // Apple refuses to clear one end of a score range while the other stays (seen 2026-11-04).
        func clearsOnly(_ cleared: String?, keeping other: String?, current: String?) -> Bool {
          cleared == "" && other != "" && (other ?? current) != nil
        }
        if clearsOnly(settings.scoreRangeStart, keeping: settings.scoreRangeEnd, current: l.scoreRangeEnd)
          || clearsOnly(settings.scoreRangeEnd, keeping: settings.scoreRangeStart, current: l.scoreRangeStart)
        {
          throw ValidationError("A score range is cleared as a whole: pass --min \"\" --max \"\".")
        }
        var lines: [String] = []
        func change(_ label: String, _ old: String?, _ new: String?) {
          guard let new else { return }
          let newValue = new.isEmpty ? nil : new
          if newValue != old { lines.append("\(label): \(old ?? "-") → \(newValue ?? "(none)")") }
        }
        change("Reference name", l.referenceName, settings.referenceName)
        change("Format", l.defaultFormatter.map { formatState($0) }, settings.defaultFormatter.map { formatState($0) })
        change("Sort", Leaderboards.sortText(l.scoreSortType), settings.scoreSortType.map(Leaderboards.sortText))
        change("Scores counted", Leaderboards.submissionText(l.submissionType), settings.submissionType.map(Leaderboards.submissionText))
        change("Lowest score", l.scoreRangeStart, settings.scoreRangeStart)
        change("Highest score", l.scoreRangeEnd, settings.scoreRangeEnd)
        change("Recurrence start", l.recurrenceStartDate.map(formatDate), settings.recurrenceStartDate.map(formatDate))
        change("Recurrence duration", l.recurrenceDuration, settings.recurrenceDuration)
        change("Recurrence rule", l.recurrenceRule, settings.recurrenceRule)
        change("Shown to players", l.visibility == "HIDE_FOR_ALL" ? "No" : "Yes", settings.visibility.map { $0 == "HIDE_FOR_ALL" ? "No" : "Yes" })
        change("Archived", l.archived ? "Yes" : "No", settings.archived.map { $0 ? "Yes" : "No" })
        guard !lines.isEmpty else {
          print("Nothing to change.")
          return
        }
        print("'\(l.displayName)':")
        for line in lines { print("  \(line)") }
        guard confirm("Save? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        try await GameCenter.updateLeaderboard(id: l.id, settings: settings, client: client)
        print(green("Updated") + " '\(l.displayName)'.")
      }
    }

    struct Default: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Make a leaderboard the one Game Center opens on.")

      @OptionGroup var arguments: GameCenterItemArguments

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
        let l = try GameCenterCommand.find(arguments.item, in: try await GameCenter.leaderboards(detailID: detail.id, client: client))
        guard l.id != detail.defaultLeaderboardID else {
          print("'\(l.displayName)' is already the default leaderboard.")
          return
        }
        guard confirm("Make '\(l.displayName)' the default leaderboard? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        try await GameCenter.setDefaultLeaderboard(detailID: detail.id, leaderboardID: l.id, client: client)
        print(green("Made") + " '\(l.displayName)' the default leaderboard.")
      }
    }

    struct Localizations: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "A leaderboard's languages (of its latest version).",
        subcommands: [
          GameCenterLocalizations<Item>.View.self, Set.self, GameCenterLocalizations<Item>.Export.self,
          GameCenterLocalizations<Item>.Import.self, GameCenterLocalizations<Item>.Delete.self,
        ],
        defaultSubcommand: GameCenterLocalizations<Item>.View.self)

      struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add or change one language.", discussion: "\"\" clears an optional text.")

        @OptionGroup var arguments: GameCenterItemArguments

        @Option(name: .long, help: "The language's locale code (en-US).")
        var locale: String

        @Option(name: .long, help: "The name players see.")
        var name: String?

        @Option(name: .long, help: "A description.")
        var description: String?

        @Option(name: .long, help: "A format of its own for this language (see create --formatter).")
        var formatter: String?

        @Option(name: .long, help: "The unit after a score (\" points\").")
        var suffix: String?

        @Option(name: .long, help: "The unit after a score of one (\" point\").")
        var suffixSingular: String?

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          guard name != nil || description != nil || formatter != nil || suffix != nil || suffixSingular != nil else {
            throw ValidationError("Give --name, --description, --formatter, --suffix or --suffix-singular.")
          }
          let override = try formatter.map { $0.isEmpty ? "" : try Leaderboards.formatter($0) }
          try await saveGameCenterLocale(Item.self, arguments: arguments, locale: locale, yes: yes) { current in
            var fields = current ?? .init()
            if let name { fields.name = name }
            if let description { fields.description = description }
            if let override { fields.formatterOverride = override }
            if let suffix { fields.formatterSuffix = suffix }
            if let suffixSingular { fields.formatterSuffixSingular = suffixSingular }
            return fields
          }
        }
      }
    }
  }
}

// MARK: - Leaderboard sets

extension GameCenterCommand {
  struct Sets: AsyncParsableCommand {
    typealias Item = GameCenter.LeaderboardSet

    static let configuration = CommandConfiguration(
      commandName: "sets",
      abstract: "Leaderboard sets: leaderboards shown together.",
      subcommands: [
        List.self, Create.self, Update.self, GameCenterDelete<Item>.self, GameCenterReorder<Item>.self, Localizations.self,
        GameCenterImage<Item>.self, GameCenterSubmit<Item>.self,
      ],
      defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "The app's leaderboard sets with their leaderboards.")

      @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
      var app: String

      @OptionGroup var jsonOption: JSONOption

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: app, client: client)
        async let sets = GameCenter.leaderboardSets(detailID: detail.id, client: client)
        async let leaderboards = GameCenter.leaderboards(detailID: detail.id, client: client)
        let (all, boards) = try await (sets, leaderboards)
        if jsonOption.json { try printJSON(all); return }
        guard !all.isEmpty else {
          print("No leaderboard sets.")
          return
        }
        let names = Dictionary(boards.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        Table.print(
          headers: ["ID", "Reference Name", "Leaderboards", "Version"],
          rows: all.map { s in
            [
              s.vendorIdentifier ?? s.id, s.referenceName ?? "-",
              s.leaderboardIDs.isEmpty ? "-" : s.leaderboardIDs.map { names[$0] ?? $0 }.joined(separator: ", "),
              GameCenterCommand.versionText(s.latestVersion),
            ]
          })
      }
    }

    struct Create: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Create a leaderboard set.")

      @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
      var app: String

      @Option(name: .long, help: "Its ID (can't change later).")
      var id: String

      @Option(name: .long, help: "Its reference name, seen only in App Store Connect.")
      var name: String

      @Option(name: .long, help: "Its leaderboards in order: IDs, reference names or Apple IDs, comma-separated.")
      var leaderboards: String?

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: app, client: client)
        let boards = try await GameCenter.leaderboards(detailID: detail.id, client: client)
        let ids = try leaderboards.map { try GameCenterCommand.ids($0, in: boards) } ?? []
        print("Leaderboard set \(id) '\(name)'\(ids.isEmpty ? "" : " with \(ids.count) leaderboard\(ids.count == 1 ? "" : "s")").")
        guard confirm("Create it? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        let created = try await GameCenter.createLeaderboardSet(
          detailID: detail.id, vendorIdentifier: id, referenceName: name, leaderboardIDs: ids, client: client)
        print(green("Created") + " '\(created.displayName)' (version \(GameCenterCommand.versionText(created.latestVersion))).")
      }
    }

    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Rename a set or set its leaderboards.")

      @OptionGroup var arguments: GameCenterItemArguments

      @Option(name: .long, help: "A new reference name.")
      var name: String?

      @Option(name: .long, help: "Its leaderboards in order, replacing the current ones (comma-separated).")
      var leaderboards: String?

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        guard name != nil || leaderboards != nil else { throw ValidationError("Give --name or --leaderboards.") }
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
        async let sets = GameCenter.leaderboardSets(detailID: detail.id, client: client)
        async let leaderboardList = GameCenter.leaderboards(detailID: detail.id, client: client)
        let (all, boards) = try await (sets, leaderboardList)
        let set = try GameCenterCommand.find(arguments.item, in: all)
        let ids = try leaderboards.map { try GameCenterCommand.ids($0, in: boards) }
        let names = Dictionary(boards.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        var lines: [String] = []
        if let name, name != set.referenceName { lines.append("Reference name: \(set.referenceName ?? "-") → \(name)") }
        if let ids, ids != set.leaderboardIDs {
          let text = { (list: [String]) in list.isEmpty ? "(none)" : list.map { names[$0] ?? $0 }.joined(separator: ", ") }
          lines.append("Leaderboards: \(text(set.leaderboardIDs)) → \(text(ids))")
        }
        guard !lines.isEmpty else {
          print("Nothing to change.")
          return
        }
        print("'\(set.displayName)':")
        for line in lines { print("  \(line)") }
        guard confirm("Save? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        if let name, name != set.referenceName { try await GameCenter.renameLeaderboardSet(id: set.id, referenceName: name, client: client) }
        if let ids, ids != set.leaderboardIDs { try await GameCenter.setLeaderboards(setID: set.id, leaderboardIDs: ids, client: client) }
        print(green("Updated") + " '\(set.displayName)'.")
      }
    }

    struct Localizations: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "A set's languages (of its latest version).",
        subcommands: [
          GameCenterLocalizations<Item>.View.self, Set.self, GameCenterLocalizations<Item>.Export.self,
          GameCenterLocalizations<Item>.Import.self, GameCenterLocalizations<Item>.Delete.self,
        ],
        defaultSubcommand: GameCenterLocalizations<Item>.View.self)

      struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add or change one language.")

        @OptionGroup var arguments: GameCenterItemArguments

        @Option(name: .long, help: "The language's locale code (en-US).")
        var locale: String

        @Option(name: .long, help: "The name players see.")
        var name: String

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          try await saveGameCenterLocale(Item.self, arguments: arguments, locale: locale, yes: yes) { _ in .init(name: name) }
        }
      }
    }
  }
}
