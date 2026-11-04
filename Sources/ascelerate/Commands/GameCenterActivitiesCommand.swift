import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

/// `localizations set` for kinds whose languages are a name and a description.
struct GameCenterNameDescriptionSet<Item: GameCenterItem>: AsyncParsableCommand where Item.Localization.Fields == ProductLocaleFields {
  static var configuration: CommandConfiguration {
    CommandConfiguration(commandName: "set", abstract: "Add or change one language.", discussion: "A new language needs its name.")
  }

  @OptionGroup var arguments: GameCenterItemArguments

  @Option(name: .long, help: "The language's locale code (en-US).")
  var locale: String

  @Option(name: .long, help: "The name players see.")
  var name: String?

  @Option(name: .long, help: "A description.")
  var description: String?

  @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
  var yes = false

  func run() async throws {
    guard name != nil || description != nil else { throw ValidationError("Give --name or --description.") }
    try await saveGameCenterLocale(Item.self, arguments: arguments, locale: locale, yes: yes) { current in
      var fields = current ?? .init()
      if let name { fields.name = name }
      if let description { fields.description = description }
      return fields
    }
  }
}

/// A kind's languages commands with a name-and-description `set`.
struct GameCenterNameDescriptionLocalizations<Item: GameCenterItem>: AsyncParsableCommand where Item.Localization.Fields == ProductLocaleFields {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "localizations",
      abstract: "\(GameCenterCommand.article(Item.noun).prefix(1).uppercased() + GameCenterCommand.article(Item.noun).dropFirst())'s languages (of its latest version).",
      subcommands: [
        GameCenterLocalizations<Item>.View.self, GameCenterNameDescriptionSet<Item>.self, GameCenterLocalizations<Item>.Export.self,
        GameCenterLocalizations<Item>.Import.self, GameCenterLocalizations<Item>.Delete.self,
      ],
      defaultSubcommand: GameCenterLocalizations<Item>.View.self)
  }
}

// MARK: - Activities

extension GameCenterCommand {
  struct Activities: AsyncParsableCommand {
    typealias Item = GameCenter.Activity

    static let configuration = CommandConfiguration(
      abstract: "Activities: parts of the game players can be invited straight into.",
      discussion: "An activity's achievements and leaderboards are the ones that belong to it (link).",
      subcommands: [
        List.self, Info.self, Create.self, Update.self, Link.self, GameCenterDelete<Item>.self,
        GameCenterNameDescriptionLocalizations<Item>.self, GameCenterImage<Item>.self, GameCenterSubmit<Item>.self,
      ],
      defaultSubcommand: List.self
    )

    /// The settings the create and update options give.
    struct SettingsOptions: ParsableArguments {
      @Option(name: .long, help: "sync (players play together) or async (in turns).")
      var playStyle: String?

      @Option(name: .long, help: "The fewest players.")
      var minPlayers: Int?

      @Option(name: .long, help: "The most players.")
      var maxPlayers: Int?

      @Option(name: .long, help: "Players can join with a party code: true or false.")
      var partyCode: Bool?

      @Option(name: .long, help: "The game's properties for it: key=value, comma-separated (replacing them).")
      var properties: String?

      func settings(referenceName: String?, archived: Bool? = nil) throws -> GameCenter.ActivitySettings {
        GameCenter.ActivitySettings(
          referenceName: referenceName,
          playStyle: try playStyle.map {
            switch $0.lowercased() {
              case "sync", "synchronous": "SYNCHRONOUS"
              case "async", "asynchronous": "ASYNCHRONOUS"
              default: throw ValidationError("--play-style is sync or async.")
            }
          },
          minimumPlayersCount: minPlayers, maximumPlayersCount: maxPlayers, supportsPartyCode: partyCode,
          properties: try properties.map { list in
            try Dictionary(list.split(separator: ",").map { pair in
              let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
              guard parts.count == 2, !parts[0].isEmpty else { throw ValidationError("--properties takes key=value pairs.") }
              return (parts[0], parts[1])
            }, uniquingKeysWith: { _, b in b })
          },
          archived: archived)
      }
    }

    static func styleText(_ raw: String?) -> String { raw == "SYNCHRONOUS" ? "Together" : raw == "ASYNCHRONOUS" ? "In turns" : "-" }

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "The app's activities.")

      @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
      var app: String

      @OptionGroup var jsonOption: JSONOption

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: app, client: client)
        let activities = try await GameCenter.activities(owner: detail.owner, client: client)
        if jsonOption.json { try printJSON(activities); return }
        guard !activities.isEmpty else {
          print("No activities.")
          return
        }
        Table.print(
          headers: ["ID", "Reference Name", "Play", "Players", "Achievements", "Leaderboards", "Version"],
          rows: activities.map { a -> [String] in
            [
              a.vendorIdentifier ?? a.id, (a.referenceName ?? "-") + (a.archived ? yellow(" (archived)") : ""), Activities.styleText(a.playStyle),
              GameCenterCommand.Matchmaking.players(a.minimumPlayersCount, a.maximumPlayersCount), "\(a.achievementIDs.count)",
              "\(a.leaderboardIDs.count)", GameCenterCommand.versionText(a.latestVersion),
            ]
          })
      }
    }

    struct Info: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "An activity with its achievements, leaderboards and languages.")

      @OptionGroup var arguments: GameCenterItemArguments

      @OptionGroup var jsonOption: JSONOption

      struct Result: Encodable {
        let activity: Item
        let localizations: [GameCenter.ActivityLocalization]
        let defaultImage: GameCenter.Image?
      }

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
        async let activityList = GameCenter.activities(owner: detail.owner, client: client)
        async let achievementList = GameCenter.achievements(owner: detail.owner, client: client)
        async let leaderboardList = GameCenter.leaderboards(owner: detail.owner, client: client)
        let a = try GameCenterCommand.find(arguments.item, in: try await activityList)
        var localizations: [GameCenter.ActivityLocalization] = []
        var defaultImage: GameCenter.Image?
        if let version = a.latestVersion {
          localizations = try await Item.localizations(versionID: version.id, client: client)
          defaultImage = try await Item.defaultImage(versionID: version.id, client: client)
        }
        if jsonOption.json { try printJSON(Result(activity: a, localizations: localizations, defaultImage: defaultImage)); return }
        let achievements = Dictionary(try await achievementList.map { ($0.id, $0.displayName) }, uniquingKeysWith: { x, _ in x })
        let leaderboards = Dictionary(try await leaderboardList.map { ($0.id, $0.displayName) }, uniquingKeysWith: { x, _ in x })
        print(bold(a.referenceName ?? a.id))
        Table.print(headers: ["", ""], rows: [
          ["ID", a.vendorIdentifier ?? "-"],
          ["Play", Activities.styleText(a.playStyle)],
          ["Players", GameCenterCommand.Matchmaking.players(a.minimumPlayersCount, a.maximumPlayersCount)],
          ["Party code", a.supportsPartyCode ? "Yes" : "No"],
          ["Properties", a.properties.isEmpty ? "-" : a.properties.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")],
          ["Achievements", a.achievementIDs.isEmpty ? "-" : a.achievementIDs.map { achievements[$0] ?? $0 }.joined(separator: ", ")],
          ["Leaderboards", a.leaderboardIDs.isEmpty ? "-" : a.leaderboardIDs.map { leaderboards[$0] ?? $0 }.joined(separator: ", ")],
          ["Fallback URL", a.fallbackURL ?? "-"],
          ["Default image", defaultImage.map { "\($0.fileName) (\(formatState($0.state ?? "-")))" } ?? "-"],
          ["Archived", a.archived ? "Yes" : "No"],
          ["Versions", a.versions.map { GameCenterCommand.versionText($0) }.joined(separator: ", ")],
          ["Apple ID", a.id],
        ])
        guard !localizations.isEmpty else {
          print("No languages yet.")
          return
        }
        print()
        Table.print(
          headers: ["Language", "Name", "Description", "Image"],
          rows: localizations.map { l -> [String] in
            [localeName(l.locale), l.name ?? "-", l.description ?? "-", l.image.map { "\($0.fileName) (\(formatState($0.state ?? "-")))" } ?? "-"]
          })
      }
    }

    struct Create: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Create an activity.")

      @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
      var app: String

      @Option(name: .long, help: "Its ID, which the game starts it with (can't change later).")
      var id: String

      @Option(name: .long, help: "Its reference name, seen only in App Store Connect.")
      var name: String

      @OptionGroup var options: SettingsOptions

      @Option(name: .long, help: "A web page for players without the game.")
      var fallbackUrl: String?

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let settings = try options.settings(referenceName: name)
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: app, client: client)
        guard confirm("Create activity \(id) '\(name)'? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        _ = try await GameCenter.createActivity(owner: detail.owner, vendorIdentifier: id, settings: settings, fallbackURL: fallbackUrl, client: client)
        print(green("Created") + " activity '\(id)'.")
      }
    }

    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Change an activity's settings or fallback URL.")

      @OptionGroup var arguments: GameCenterItemArguments

      @Option(name: .long, help: "A new reference name.")
      var name: String?

      @OptionGroup var options: SettingsOptions

      @Option(name: .long, help: "A web page for players without the game (\"\" clears it; on the latest version).")
      var fallbackUrl: String?

      @Option(name: .long, help: "Archived: true or false.")
      var archived: Bool?

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let settings = try options.settings(referenceName: name, archived: archived)
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
        let a = try GameCenterCommand.find(arguments.item, in: try await GameCenter.activities(owner: detail.owner, client: client))
        var lines: [String] = []
        func change(_ label: String, _ old: String?, _ new: String?) {
          if let new, new != old { lines.append("\(label): \(old ?? "-") → \(new.isEmpty ? "(none)" : new)") }
        }
        change("Reference name", a.referenceName, settings.referenceName)
        change("Play", Activities.styleText(a.playStyle), settings.playStyle.map(Activities.styleText))
        change("Fewest players", a.minimumPlayersCount.map(String.init), settings.minimumPlayersCount.map(String.init))
        change("Most players", a.maximumPlayersCount.map(String.init), settings.maximumPlayersCount.map(String.init))
        change("Party code", a.supportsPartyCode ? "Yes" : "No", settings.supportsPartyCode.map { $0 ? "Yes" : "No" })
        let text = { (p: [String: String]) in p.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ") }
        change("Properties", a.properties.isEmpty ? nil : text(a.properties), settings.properties.map(text))
        change("Archived", a.archived ? "Yes" : "No", archived.map { $0 ? "Yes" : "No" })
        change("Fallback URL", a.fallbackURL, fallbackUrl)
        guard !lines.isEmpty else {
          print("Nothing to change.")
          return
        }
        print("'\(a.displayName)':")
        for line in lines { print("  \(line)") }
        let settingsChange = name != nil || options.playStyle != nil || options.minPlayers != nil || options.maxPlayers != nil
          || options.partyCode != nil || options.properties != nil || archived != nil
        var version: GameCenter.Version?
        if let fallbackUrl, fallbackUrl != (a.fallbackURL ?? "") {
          guard let editable = try await GameCenterCommand.editableVersion(of: a, client: client) else { return }
          version = editable
        }
        guard confirm("Save? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        if settingsChange { try await GameCenter.updateActivity(id: a.id, settings: settings, client: client) }
        if let version, let fallbackUrl, !version.id.hasPrefix("DRY-RUN") {
          try await GameCenter.setActivityFallbackURL(versionID: version.id, url: fallbackUrl, client: client)
        }
        print(green("Updated") + " '\(a.displayName)'.")
      }
    }

    struct Link: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Add achievements and leaderboards to an activity, or take them out (--remove).")

      @OptionGroup var arguments: GameCenterItemArguments

      @Option(name: .long, help: "Achievements: IDs, reference names or Apple IDs, comma-separated.")
      var achievements: String?

      @Option(name: .long, help: "Leaderboards: IDs, reference names or Apple IDs, comma-separated.")
      var leaderboards: String?

      @Flag(name: .long, help: "Take them out of the activity.")
      var remove = false

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        guard achievements != nil || leaderboards != nil else { throw ValidationError("Give --achievements or --leaderboards.") }
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
        let a = try GameCenterCommand.find(arguments.item, in: try await GameCenter.activities(owner: detail.owner, client: client))
        var achievementIDs: [String] = [], leaderboardIDs: [String] = []
        if let achievements {
          achievementIDs = try GameCenterCommand.ids(achievements, in: try await GameCenter.achievements(owner: detail.owner, client: client))
        }
        if let leaderboards {
          leaderboardIDs = try GameCenterCommand.ids(leaderboards, in: try await GameCenter.leaderboards(owner: detail.owner, client: client))
        }
        let what = [achievementIDs.isEmpty ? nil : "\(achievementIDs.count) achievement\(achievementIDs.count == 1 ? "" : "s")",
                    leaderboardIDs.isEmpty ? nil : "\(leaderboardIDs.count) leaderboard\(leaderboardIDs.count == 1 ? "" : "s")"]
          .compactMap(\.self).joined(separator: " and ")
        guard confirm("\(remove ? "Take" : "Add") \(what) \(remove ? "out of" : "to") '\(a.displayName)'? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        try await GameCenter.linkToActivity(
          activityID: a.id, achievementIDs: achievementIDs, leaderboardIDs: leaderboardIDs, remove: remove, client: client)
        print(green(remove ? "Removed" : "Added") + " \(what).")
      }
    }
  }
}

// MARK: - Challenges

extension GameCenterCommand {
  struct Challenges: AsyncParsableCommand {
    typealias Item = GameCenter.Challenge

    static let configuration = CommandConfiguration(
      abstract: "Challenges: players challenge friends to beat a score on a leaderboard.",
      subcommands: [
        List.self, Info.self, Create.self, Update.self, GameCenterDelete<Item>.self, GameCenterNameDescriptionLocalizations<Item>.self,
        GameCenterImage<Item>.self, GameCenterSubmit<Item>.self,
      ],
      defaultSubcommand: List.self
    )

    /// Apple's rules for a challenge's leaderboard (seen 2026-11-04): it has one challenge at most,
    /// counts each player's best score, and a challenge that isn't repeatable needs a recurring one.
    static func check(leaderboard: GameCenter.Leaderboard, repeatable: Bool, challenges: [Item], except: String? = nil) throws {
      if let other = challenges.first(where: { $0.leaderboardID == leaderboard.id && $0.id != except }) {
        throw ValidationError("'\(leaderboard.displayName)' already has a challenge ('\(other.displayName)'); a leaderboard takes one.")
      }
      if leaderboard.submissionType == "MOST_RECENT_SCORE" {
        throw ValidationError("'\(leaderboard.displayName)' counts the most recent score; a challenge needs a leaderboard that counts each player's best.")
      }
      if !repeatable, leaderboard.recurrenceRule == nil {
        throw ValidationError("A challenge that isn't repeatable needs a recurring leaderboard; '\(leaderboard.displayName)' doesn't recur. Pass --repeatable.")
      }
    }

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "The app's challenges.")

      @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
      var app: String

      @OptionGroup var jsonOption: JSONOption

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: app, client: client)
        async let challengeList = GameCenter.challenges(owner: detail.owner, client: client)
        async let leaderboardList = GameCenter.leaderboards(owner: detail.owner, client: client)
        let (challenges, leaderboards) = try await (challengeList, leaderboardList)
        if jsonOption.json { try printJSON(challenges); return }
        guard !challenges.isEmpty else {
          print("No challenges.")
          return
        }
        let names = Dictionary(leaderboards.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        Table.print(
          headers: ["ID", "Reference Name", "Leaderboard", "Repeatable", "Version"],
          rows: challenges.map { c -> [String] in
            [
              c.vendorIdentifier ?? c.id, (c.referenceName ?? "-") + (c.archived ? yellow(" (archived)") : ""),
              c.leaderboardID.map { names[$0] ?? $0 } ?? "-", c.repeatable ? "Yes" : "No", GameCenterCommand.versionText(c.latestVersion),
            ]
          })
      }
    }

    struct Info: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "A challenge with its languages.")

      @OptionGroup var arguments: GameCenterItemArguments

      @OptionGroup var jsonOption: JSONOption

      struct Result: Encodable {
        let challenge: Item
        let localizations: [GameCenter.ChallengeLocalization]
        let defaultImage: GameCenter.Image?
      }

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
        async let challengeList = GameCenter.challenges(owner: detail.owner, client: client)
        async let leaderboardList = GameCenter.leaderboards(owner: detail.owner, client: client)
        let c = try GameCenterCommand.find(arguments.item, in: try await challengeList)
        var localizations: [GameCenter.ChallengeLocalization] = []
        var defaultImage: GameCenter.Image?
        if let version = c.latestVersion {
          localizations = try await Item.localizations(versionID: version.id, client: client)
          defaultImage = try await Item.defaultImage(versionID: version.id, client: client)
        }
        if jsonOption.json { try printJSON(Result(challenge: c, localizations: localizations, defaultImage: defaultImage)); return }
        let leaderboard = try await leaderboardList.first { $0.id == c.leaderboardID }
        print(bold(c.referenceName ?? c.id))
        Table.print(headers: ["", ""], rows: [
          ["ID", c.vendorIdentifier ?? "-"],
          ["Leaderboard", leaderboard?.displayName ?? c.leaderboardID ?? "-"],
          ["Repeatable", c.repeatable ? "Yes" : "No"],
          ["Default image", defaultImage.map { "\($0.fileName) (\(formatState($0.state ?? "-")))" } ?? "-"],
          ["Archived", c.archived ? "Yes" : "No"],
          ["Versions", c.versions.map { GameCenterCommand.versionText($0) }.joined(separator: ", ")],
          ["Apple ID", c.id],
        ])
        guard !localizations.isEmpty else {
          print("No languages yet.")
          return
        }
        print()
        Table.print(
          headers: ["Language", "Name", "Description", "Image"],
          rows: localizations.map { l -> [String] in
            [localeName(l.locale), l.name ?? "-", l.description ?? "-", l.image.map { "\($0.fileName) (\(formatState($0.state ?? "-")))" } ?? "-"]
          })
      }
    }

    struct Create: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Create a leaderboard challenge.")

      @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
      var app: String

      @Option(name: .long, help: "Its ID (can't change later).")
      var id: String

      @Option(name: .long, help: "Its reference name, seen only in App Store Connect.")
      var name: String

      @Option(name: .long, help: "The leaderboard whose scores it uses.")
      var leaderboard: String

      @Flag(name: .long, help: "Players can take it on more than once (required unless the leaderboard recurs).")
      var repeatable = false

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: app, client: client)
        async let leaderboardList = GameCenter.leaderboards(owner: detail.owner, client: client)
        async let challengeList = GameCenter.challenges(owner: detail.owner, client: client)
        let board = try GameCenterCommand.find(leaderboard, in: try await leaderboardList)
        try Challenges.check(leaderboard: board, repeatable: repeatable, challenges: try await challengeList)
        guard confirm("Create challenge \(id) '\(name)' on leaderboard '\(board.displayName)'? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        _ = try await GameCenter.createChallenge(
          owner: detail.owner, vendorIdentifier: id, referenceName: name, leaderboardID: board.id, repeatable: repeatable, client: client)
        print(green("Created") + " challenge '\(id)'.")
      }
    }

    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Change a challenge's reference name, leaderboard or flags.")

      @OptionGroup var arguments: GameCenterItemArguments

      @Option(name: .long, help: "A new reference name.")
      var name: String?

      @Option(name: .long, help: "The leaderboard whose scores it uses.")
      var leaderboard: String?

      @Option(name: .long, help: "Can be taken on more than once: true or false.")
      var repeatable: Bool?

      @Option(name: .long, help: "Archived: true or false.")
      var archived: Bool?

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        guard name != nil || leaderboard != nil || repeatable != nil || archived != nil else {
          throw ValidationError("Give --name, --leaderboard, --repeatable or --archived.")
        }
        let client = try ClientFactory.makeClient()
        let (_, detail) = try await GameCenterCommand.context(app: arguments.app, client: client)
        async let challengeList = GameCenter.challenges(owner: detail.owner, client: client)
        async let leaderboardList = GameCenter.leaderboards(owner: detail.owner, client: client)
        let (challenges, leaderboards) = try await (challengeList, leaderboardList)
        let c = try GameCenterCommand.find(arguments.item, in: challenges)
        let board = try leaderboard.map { try GameCenterCommand.find($0, in: leaderboards) }
        if let resulting = board ?? leaderboards.first(where: { $0.id == c.leaderboardID }) {
          try Challenges.check(leaderboard: resulting, repeatable: repeatable ?? c.repeatable, challenges: challenges, except: c.id)
        }
        var lines: [String] = []
        if let name, name != c.referenceName { lines.append("Reference name: \(c.referenceName ?? "-") → \(name)") }
        if let board, board.id != c.leaderboardID {
          lines.append("Leaderboard: \(leaderboards.first { $0.id == c.leaderboardID }?.displayName ?? "-") → \(board.displayName)")
        }
        if let repeatable, repeatable != c.repeatable { lines.append("Repeatable: \(c.repeatable ? "Yes" : "No") → \(repeatable ? "Yes" : "No")") }
        if let archived, archived != c.archived { lines.append("Archived: \(c.archived ? "Yes" : "No") → \(archived ? "Yes" : "No")") }
        guard !lines.isEmpty else {
          print("Nothing to change.")
          return
        }
        print("'\(c.displayName)':")
        for line in lines { print("  \(line)") }
        guard confirm("Save? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        try await GameCenter.updateChallenge(
          id: c.id, referenceName: name, repeatable: repeatable, archived: archived,
          leaderboardID: board?.id == c.leaderboardID ? nil : board?.id, client: client)
        print(green("Updated") + " '\(c.displayName)'.")
      }
    }
  }
}
