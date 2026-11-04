import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

extension GameCenterCommand {
  /// Rule-based matchmaking: the team's rule sets and queues (not one app's).
  struct Matchmaking: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Rule-based matchmaking: rule sets with their rules and teams, queues, and Apple's rule set test.",
      discussion: """
        Matchmaking belongs to the team, not one app: a queue names the rule set it matches with, \
        and games send their match requests to a queue. Rule sets and queues are named by \
        reference name or ID.
        """,
      subcommands: [RuleSets.self, Rules.self, Teams.self, Queues.self, Test.self],
      defaultSubcommand: RuleSets.self
    )

    static func findRuleSet(_ reference: String, in sets: [GameCenter.RuleSet]) throws -> GameCenter.RuleSet {
      guard let found = sets.first(where: { $0.id == reference || $0.referenceName?.lowercased() == reference.lowercased() }) else {
        throw ValidationError("No rule set '\(reference)'. Rule sets: \(sets.compactMap(\.referenceName).joined(separator: ", ")).")
      }
      return found
    }

    static func findQueue(_ reference: String, in queues: [GameCenter.Queue]) throws -> GameCenter.Queue {
      guard let found = queues.first(where: { $0.id == reference || $0.referenceName?.lowercased() == reference.lowercased() }) else {
        throw ValidationError("No queue '\(reference)'. Queues: \(queues.compactMap(\.referenceName).joined(separator: ", ")).")
      }
      return found
    }

    static func players(_ min: Int?, _ max: Int?) -> String {
      "\(min.map(String.init) ?? "?")–\(max.map(String.init) ?? "?")"
    }

    /// Asks, then runs the write; prints `done` unless dry run stopped it.
    static func write(_ question: String, done: String, _ write: () async throws -> Void) async throws {
      guard confirm("\(question) [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      if try await unlessDryRunStopped(write) != nil { print(done) }
    }

    // MARK: Rule sets

    struct RuleSets: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "rule-sets",
        abstract: "Rule sets: player counts, rules and teams.",
        subcommands: [List.self, Info.self, Create.self, Update.self, Delete.self],
        defaultSubcommand: List.self)

      struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "The team's rule sets.")

        @OptionGroup var jsonOption: JSONOption

        func run() async throws {
          jsonOption.activate()
          let client = try ClientFactory.makeClient()
          async let sets = GameCenter.ruleSets(client: client)
          async let queues = GameCenter.queues(client: client)
          let (all, queueList) = try await (sets, queues)
          if jsonOption.json { try printJSON(all); return }
          guard !all.isEmpty else {
            print("No rule sets.")
            return
          }
          let names = Dictionary(queueList.map { ($0.id, $0.referenceName ?? $0.id) }, uniquingKeysWith: { a, _ in a })
          Table.print(
            headers: ["Rule Set", "Players", "Rules", "Teams", "Queues"],
            rows: all.map { s in
              [
                s.referenceName ?? s.id, Matchmaking.players(s.minPlayers, s.maxPlayers), "\(s.rules.count)", "\(s.teams.count)",
                s.queueIDs.isEmpty ? "-" : s.queueIDs.map { names[$0] ?? $0 }.joined(separator: ", "),
              ]
            })
        }
      }

      struct Info: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "A rule set's rules and teams.")

        @Argument(help: "The rule set's reference name or ID.")
        var ruleSet: String

        @OptionGroup var jsonOption: JSONOption

        func run() async throws {
          jsonOption.activate()
          let client = try ClientFactory.makeClient()
          let set = try Matchmaking.findRuleSet(ruleSet, in: try await GameCenter.ruleSets(client: client))
          if jsonOption.json { try printJSON(set); return }
          print(bold(set.referenceName ?? set.id))
          Table.print(headers: ["", ""], rows: [
            ["Players", Matchmaking.players(set.minPlayers, set.maxPlayers)],
            ["Rule language", set.ruleLanguageVersion.map(String.init) ?? "-"],
            ["ID", set.id],
          ])
          print()
          if set.rules.isEmpty {
            print("No rules.")
          } else {
            Table.print(
              headers: ["Rule", "Type", "Expression", "Weight", "Description"],
              rows: set.rules.map { r in
                [
                  r.referenceName ?? r.id, formatState(r.type ?? "-"), r.expression ?? "-", r.weight.map { String(format: "%g", $0) } ?? "-",
                  r.description ?? "-",
                ]
              })
          }
          print()
          if set.teams.isEmpty {
            print("No teams.")
          } else {
            Table.print(
              headers: ["Team", "Players"],
              rows: set.teams.map { [$0.referenceName ?? $0.id, Matchmaking.players($0.minPlayers, $0.maxPlayers)] })
          }
        }
      }

      struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a rule set.")

        @Option(name: .long, help: "Its reference name (can't change later).")
        var name: String

        @Option(name: .long, help: "The fewest players in a match.")
        var min: Int

        @Option(name: .long, help: "The most players in a match.")
        var max: Int

        @Option(name: .long, help: "The rule language version (default 1).")
        var languageVersion = 1

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          guard min >= 1, max >= min else { throw ValidationError("--min must be at least 1 and --max at least --min.") }
          let client = try ClientFactory.makeClient()
          try await Matchmaking.write("Create rule set '\(name)' for \(min)–\(max) players?", done: green("Created") + " rule set '\(name)'.") {
            _ = try await GameCenter.createRuleSet(referenceName: name, minPlayers: min, maxPlayers: max, ruleLanguageVersion: languageVersion, client: client)
          }
        }
      }

      struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Change a rule set's player counts.")

        @Argument(help: "The rule set's reference name or ID.")
        var ruleSet: String

        @Option(name: .long, help: "The fewest players in a match.")
        var min: Int?

        @Option(name: .long, help: "The most players in a match.")
        var max: Int?

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          guard min != nil || max != nil else { throw ValidationError("Give --min or --max.") }
          let client = try ClientFactory.makeClient()
          let set = try Matchmaking.findRuleSet(ruleSet, in: try await GameCenter.ruleSets(client: client))
          let new = Matchmaking.players(min ?? set.minPlayers, max ?? set.maxPlayers)
          try await Matchmaking.write(
            "Players of '\(set.referenceName ?? set.id)': \(Matchmaking.players(set.minPlayers, set.maxPlayers)) → \(new). Save?",
            done: green("Updated") + " '\(set.referenceName ?? set.id)'."
          ) {
            try await GameCenter.updateRuleSet(id: set.id, minPlayers: min, maxPlayers: max, client: client)
          }
        }
      }

      struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a rule set (with its rules and teams).")

        @Argument(help: "The rule set's reference name or ID.")
        var ruleSet: String

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          let client = try ClientFactory.makeClient()
          let set = try Matchmaking.findRuleSet(ruleSet, in: try await GameCenter.ruleSets(client: client))
          try await Matchmaking.write("Delete rule set '\(set.referenceName ?? set.id)'?", done: green("Deleted") + " '\(set.referenceName ?? set.id)'.") {
            try await GameCenter.deleteRuleSet(id: set.id, client: client)
          }
        }
      }
    }

    // MARK: Rules

    struct Rules: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "A rule set's rules (list them with rule-sets info).",
        discussion: "Types: compatible and match rules decide whether requests can match, distance rules rank them by how close they are, team rules place players in teams.",
        subcommands: [Add.self, Update.self, Delete.self])

      static func find(_ reference: String, in set: GameCenter.RuleSet) throws -> GameCenter.Rule {
        guard let found = set.rules.first(where: { $0.id == reference || $0.referenceName?.lowercased() == reference.lowercased() }) else {
          throw ValidationError("No rule '\(reference)' in '\(set.referenceName ?? set.id)'.")
        }
        return found
      }

      struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add a rule to a rule set.")

        @Argument(help: "The rule set's reference name or ID.")
        var ruleSet: String

        @Option(name: .long, help: "Its reference name (can't change later).")
        var name: String

        @Option(name: .long, help: "compatible, distance, match or team.")
        var type: String

        @Option(name: .long, help: "The rule's expression, in Apple's rule language.")
        var expression: String

        @Option(name: .long, help: "What the rule does.")
        var description: String

        @Option(name: .long, help: "A distance rule's weight.")
        var weight: Double?

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          let raw = type.uppercased()
          guard GameCenter.ruleTypes.contains(raw) else { throw ValidationError("--type is compatible, distance, match or team.") }
          let client = try ClientFactory.makeClient()
          let set = try Matchmaking.findRuleSet(ruleSet, in: try await GameCenter.ruleSets(client: client))
          print("\(formatState(raw)) rule '\(name)': \(expression)")
          try await Matchmaking.write("Add it to '\(set.referenceName ?? set.id)'?", done: green("Added") + " rule '\(name)'.") {
            _ = try await GameCenter.createRule(
              ruleSetID: set.id, referenceName: name, type: raw, expression: expression, description: description, weight: weight, client: client)
          }
        }
      }

      struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Change a rule's expression, description or weight.")

        @Argument(help: "The rule set's reference name or ID.")
        var ruleSet: String

        @Argument(help: "The rule's reference name or ID.")
        var rule: String

        @Option(name: .long, help: "A new expression.")
        var expression: String?

        @Option(name: .long, help: "A new description.")
        var description: String?

        @Option(name: .long, help: "A new weight.")
        var weight: Double?

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          guard expression != nil || description != nil || weight != nil else { throw ValidationError("Give --expression, --description or --weight.") }
          let client = try ClientFactory.makeClient()
          let set = try Matchmaking.findRuleSet(ruleSet, in: try await GameCenter.ruleSets(client: client))
          let found = try Rules.find(rule, in: set)
          if let expression { print("Expression: \(found.expression ?? "-") → \(expression)") }
          if let description { print("Description: \(found.description ?? "-") → \(description)") }
          if let weight { print("Weight: \(found.weight.map { String(format: "%g", $0) } ?? "-") → \(String(format: "%g", weight))") }
          try await Matchmaking.write("Save rule '\(found.referenceName ?? found.id)'?", done: green("Updated") + " rule '\(found.referenceName ?? found.id)'.") {
            try await GameCenter.updateRule(id: found.id, expression: expression, description: description, weight: weight, client: client)
          }
        }
      }

      struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a rule.")

        @Argument(help: "The rule set's reference name or ID.")
        var ruleSet: String

        @Argument(help: "The rule's reference name or ID.")
        var rule: String

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          let client = try ClientFactory.makeClient()
          let set = try Matchmaking.findRuleSet(ruleSet, in: try await GameCenter.ruleSets(client: client))
          let found = try Rules.find(rule, in: set)
          try await Matchmaking.write("Delete rule '\(found.referenceName ?? found.id)'?", done: green("Deleted") + " rule '\(found.referenceName ?? found.id)'.") {
            try await GameCenter.deleteRule(id: found.id, client: client)
          }
        }
      }
    }

    // MARK: Teams

    struct Teams: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "A rule set's teams (list them with rule-sets info).",
        subcommands: [Add.self, Update.self, Delete.self])

      static func find(_ reference: String, in set: GameCenter.RuleSet) throws -> GameCenter.Team {
        guard let found = set.teams.first(where: { $0.id == reference || $0.referenceName?.lowercased() == reference.lowercased() }) else {
          throw ValidationError("No team '\(reference)' in '\(set.referenceName ?? set.id)'.")
        }
        return found
      }

      struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add a team to a rule set.")

        @Argument(help: "The rule set's reference name or ID.")
        var ruleSet: String

        @Option(name: .long, help: "Its name, which team rules and the game use (can't change later).")
        var name: String

        @Option(name: .long, help: "The fewest players on the team.")
        var min: Int

        @Option(name: .long, help: "The most players on the team.")
        var max: Int

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          let client = try ClientFactory.makeClient()
          let set = try Matchmaking.findRuleSet(ruleSet, in: try await GameCenter.ruleSets(client: client))
          try await Matchmaking.write("Add team '\(name)' (\(min)–\(max) players) to '\(set.referenceName ?? set.id)'?", done: green("Added") + " team '\(name)'.") {
            _ = try await GameCenter.createTeam(ruleSetID: set.id, referenceName: name, minPlayers: min, maxPlayers: max, client: client)
          }
        }
      }

      struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Change a team's player counts.")

        @Argument(help: "The rule set's reference name or ID.")
        var ruleSet: String

        @Argument(help: "The team's name or ID.")
        var team: String

        @Option(name: .long, help: "The fewest players on the team.")
        var min: Int?

        @Option(name: .long, help: "The most players on the team.")
        var max: Int?

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          guard min != nil || max != nil else { throw ValidationError("Give --min or --max.") }
          let client = try ClientFactory.makeClient()
          let set = try Matchmaking.findRuleSet(ruleSet, in: try await GameCenter.ruleSets(client: client))
          let found = try Teams.find(team, in: set)
          let new = Matchmaking.players(min ?? found.minPlayers, max ?? found.maxPlayers)
          try await Matchmaking.write(
            "Players of team '\(found.referenceName ?? found.id)': \(Matchmaking.players(found.minPlayers, found.maxPlayers)) → \(new). Save?",
            done: green("Updated") + " team '\(found.referenceName ?? found.id)'."
          ) {
            try await GameCenter.updateTeam(id: found.id, minPlayers: min, maxPlayers: max, client: client)
          }
        }
      }

      struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a team.")

        @Argument(help: "The rule set's reference name or ID.")
        var ruleSet: String

        @Argument(help: "The team's name or ID.")
        var team: String

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          let client = try ClientFactory.makeClient()
          let set = try Matchmaking.findRuleSet(ruleSet, in: try await GameCenter.ruleSets(client: client))
          let found = try Teams.find(team, in: set)
          try await Matchmaking.write("Delete team '\(found.referenceName ?? found.id)'?", done: green("Deleted") + " team '\(found.referenceName ?? found.id)'.") {
            try await GameCenter.deleteTeam(id: found.id, client: client)
          }
        }
      }
    }

    // MARK: Queues

    struct Queues: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Queues: where games send match requests, each matched with a rule set.",
        subcommands: [List.self, Create.self, Update.self, Delete.self],
        defaultSubcommand: List.self)

      struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "The team's queues.")

        @OptionGroup var jsonOption: JSONOption

        func run() async throws {
          jsonOption.activate()
          let client = try ClientFactory.makeClient()
          async let queues = GameCenter.queues(client: client)
          async let sets = GameCenter.ruleSets(client: client)
          let (all, setList) = try await (queues, sets)
          if jsonOption.json { try printJSON(all); return }
          guard !all.isEmpty else {
            print("No queues.")
            return
          }
          let names = Dictionary(setList.map { ($0.id, $0.referenceName ?? $0.id) }, uniquingKeysWith: { a, _ in a })
          Table.print(
            headers: ["Queue", "Rule Set", "Experiment", "Classic Matchmaking Apps", "ID"],
            rows: all.map { q in
              [
                q.referenceName ?? q.id, q.ruleSetID.map { names[$0] ?? $0 } ?? "-", q.experimentRuleSetID.map { names[$0] ?? $0 } ?? "-",
                q.classicMatchmakingBundleIDs.isEmpty ? "-" : q.classicMatchmakingBundleIDs.joined(separator: ", "), q.id,
              ]
            })
        }
      }

      struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a queue.")

        @Option(name: .long, help: "Its reference name, which games send requests to (can't change later).")
        var name: String

        @Option(name: .long, help: "The rule set it matches with.")
        var ruleSet: String

        @Option(name: .long, help: "A second rule set to try on part of the requests.")
        var experimentRuleSet: String?

        @Option(name: .long, help: "Bundle IDs whose classic matchmaking requests also go here, comma-separated.")
        var classicApps: String?

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          let client = try ClientFactory.makeClient()
          let sets = try await GameCenter.ruleSets(client: client)
          let set = try Matchmaking.findRuleSet(ruleSet, in: sets)
          let experiment = try experimentRuleSet.map { try Matchmaking.findRuleSet($0, in: sets) }
          let apps = classicApps?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
          try await Matchmaking.write(
            "Create queue '\(name)' with rule set '\(set.referenceName ?? set.id)'\(experiment.map { " (experiment '\($0.referenceName ?? $0.id)')" } ?? "")?",
            done: green("Created") + " queue '\(name)'."
          ) {
            _ = try await GameCenter.createQueue(
              referenceName: name, ruleSetID: set.id, experimentRuleSetID: experiment?.id, classicMatchmakingBundleIDs: apps, client: client)
          }
        }
      }

      struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Change a queue's rule sets or classic matchmaking apps.")

        @Argument(help: "The queue's reference name or ID.")
        var queue: String

        @Option(name: .long, help: "The rule set it matches with.")
        var ruleSet: String?

        @Option(name: .long, help: "A second rule set to try on part of the requests (none removes it).")
        var experimentRuleSet: String?

        @Option(name: .long, help: "Bundle IDs whose classic matchmaking requests also go here, comma-separated (none removes them).")
        var classicApps: String?

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          guard ruleSet != nil || experimentRuleSet != nil || classicApps != nil else {
            throw ValidationError("Give --rule-set, --experiment-rule-set or --classic-apps.")
          }
          let client = try ClientFactory.makeClient()
          async let queueList = GameCenter.queues(client: client)
          async let setList = GameCenter.ruleSets(client: client)
          let (queues, sets) = try await (queueList, setList)
          let found = try Matchmaking.findQueue(queue, in: queues)
          let names = Dictionary(sets.map { ($0.id, $0.referenceName ?? $0.id) }, uniquingKeysWith: { a, _ in a })
          let set = try ruleSet.map { try Matchmaking.findRuleSet($0, in: sets) }
          let experiment = try experimentRuleSet.map { $0.lowercased() == "none" ? nil : try Matchmaking.findRuleSet($0, in: sets) }
          let apps = classicApps.map { $0.lowercased() == "none" ? [] : $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
          if let set { print("Rule set: \(found.ruleSetID.map { names[$0] ?? $0 } ?? "-") → \(set.referenceName ?? set.id)") }
          if let experiment {
            print("Experiment: \(found.experimentRuleSetID.map { names[$0] ?? $0 } ?? "-") → \(experiment.map { $0.referenceName ?? $0.id } ?? "(none)")")
          }
          if let apps {
            print("Classic matchmaking apps: \(found.classicMatchmakingBundleIDs.isEmpty ? "-" : found.classicMatchmakingBundleIDs.joined(separator: ", ")) → \(apps.isEmpty ? "(none)" : apps.joined(separator: ", "))")
          }
          try await Matchmaking.write("Save queue '\(found.referenceName ?? found.id)'?", done: green("Updated") + " queue '\(found.referenceName ?? found.id)'.") {
            try await GameCenter.updateQueue(
              id: found.id, ruleSetID: set?.id, experimentRuleSetID: experiment.map { $0?.id ?? "" }, classicMatchmakingBundleIDs: apps,
              client: client)
          }
        }
      }

      struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a queue.")

        @Argument(help: "The queue's reference name or ID.")
        var queue: String

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          let client = try ClientFactory.makeClient()
          let found = try Matchmaking.findQueue(queue, in: try await GameCenter.queues(client: client))
          try await Matchmaking.write("Delete queue '\(found.referenceName ?? found.id)'?", done: green("Deleted") + " queue '\(found.referenceName ?? found.id)'.") {
            try await GameCenter.deleteQueue(id: found.id, client: client)
          }
        }
      }
    }

    // MARK: Test

    struct Test: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Run sample match requests through a rule set and show the matches Apple would make.",
        discussion: """
          The file is a JSON array of requests: {"requestName", "bundleId", "platform" (IOS, MAC_OS…), \
          "appVersion", "players": [{"playerId", "properties": {"key": "value"}}], and optionally \
          "secondsInQueue", "locale" (EN-US), "latitude", "longitude", "playerCount", "minPlayers", \
          "maxPlayers"}. Nothing is saved.
          """)

      @Argument(help: "The rule set's reference name or ID.")
      var ruleSet: String

      @Option(name: .long, help: "The JSON file of requests.", completion: .file(extensions: ["json"]))
      var file: String

      @OptionGroup var jsonOption: JSONOption

      func run() async throws {
        jsonOption.activate()
        let path = expandPath(file)
        let requests: [GameCenter.TestRequest]
        do {
          requests = try JSONDecoder().decode([GameCenter.TestRequest].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        } catch let error as DecodingError {
          throw ValidationError("The request file doesn't read: \(error)")
        }
        guard !requests.isEmpty else { throw ValidationError("The request file has no requests.") }
        let client = try ClientFactory.makeClient()
        let set = try Matchmaking.findRuleSet(ruleSet, in: try await GameCenter.ruleSets(client: client))
        let matches = try await GameCenter.test(ruleSetID: set.id, requests: requests, client: client)
        if jsonOption.json { try printJSON(matches); return }
        let matched = Set(matches.flatMap { $0.requests.compactMap(\.requestName) })
        print("\(matches.count) match\(matches.count == 1 ? "" : "es") from \(requests.count) request\(requests.count == 1 ? "" : "s") with '\(set.referenceName ?? set.id)':")
        for (i, match) in matches.enumerated() {
          print()
          print(bold("Match \(i + 1)"))
          for request in match.requests {
            let players = request.teamAssignments.map { a in a.team.map { "\(a.playerId ?? "?") (\($0))" } ?? (a.playerId ?? "?") }
            print("  \(request.requestName ?? "?"): \(players.joined(separator: ", "))")
          }
        }
        let unmatched = requests.map(\.requestName).filter { !matched.contains($0) }
        if !unmatched.isEmpty {
          print()
          print(yellow("Not matched: ") + unmatched.joined(separator: ", "))
        }
      }
    }
  }
}
