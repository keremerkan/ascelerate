import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

struct TestFlightCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "testflight",
    abstract: "Manage TestFlight beta testing.",
    subcommands: [Groups.self, Testers.self, Builds.self, Versions.self, Feedback.self],
    groupedSubcommands: [
      CommandGroup(name: "Build Management", subcommands: [Expire.self, Notify.self, AutoNotify.self]),
      CommandGroup(name: "Metadata", subcommands: [WhatsNew.self, AppInfo.self, ReviewInfo.self, Eula.self]),
      CommandGroup(name: "Review", subcommands: [Submit.self, Status.self]),
    ]
  )

  // MARK: - Shared helpers

  /// Resolves a beta group by name (case-insensitive), or prompts with a picker when omitted.
  static func findBetaGroup(name: String?, appID: String, client: ASCClient) async throws -> Components.Schemas.BetaGroup {
    let groups = try fetchAll(
      await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.betaGroupsGetCollection(query: .init(filterApp: [appID], sort: [.name], limit: 200)).ok.body.json
      },
      data: \.data,
      emptyMessage: "No beta groups found for this app.")
    if let name {
      if let match = groups.first(where: { $0.attributes?.name?.lowercased() == name.lowercased() }) {
        return match
      }
      let available = groups.compactMap { $0.attributes?.name }.joined(separator: ", ")
      throw ValidationError("No beta group named '\(name)'. Available: \(available)")
    }
    return try promptSelection(
      "Select a beta group", items: groups, display: describeGroup,
      nonInteractiveHint: "Pass the group name to disambiguate.")
  }

  static func describeGroup(_ group: Components.Schemas.BetaGroup) -> String {
    let a = group.attributes
    var traits = [a?.isInternalGroup == true ? "Internal" : "External"]
    if a?.publicLinkEnabled == true { traits.append("public link") }
    return "\(a?.name ?? "?") (\(traits.joined(separator: ", ")))"
  }

  /// Resolves a build by number, or the latest non-expired build when omitted, prompting when a
  /// build number matches on several platforms.
  static func findBuild(
    appID: String, buildVersion: String?, platform: Platform?, client: ASCClient
  ) async throws -> AscelerateCore.Builds.Build {
    do {
      return try await AscelerateCore.Builds.find(appID: appID, number: buildVersion, platform: platform, client: client) {
        try promptSelection($0, items: $1, display: $2, nonInteractiveHint: "Pass --platform to disambiguate.")
      }
    } catch let error as AscelerateCore.Builds.LookupError {
      throw ValidationError(error.localizedDescription)
    }
  }

  /// Shared `--build` / `--platform` options for build-scoped TestFlight commands.
  struct BuildOptions: ParsableArguments {
    @Option(name: .long, help: "Build number. Defaults to the latest non-expired build.")
    var build: String?

    @OptionGroup var platformOption: PlatformOption

    func resolve(appID: String, client: ASCClient) async throws -> AscelerateCore.Builds.Build {
      try await TestFlightCommand.findBuild(
        appID: appID, buildVersion: build, platform: try platformOption.parsed(), client: client)
    }
  }

  // MARK: - Groups

  struct Groups: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "groups",
      abstract: "Manage beta groups.",
      subcommands: [
        List.self, Info.self, Create.self, Update.self, Delete.self,
        AddBuild.self, RemoveBuild.self, Criteria.self,
      ]
    )

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "List beta groups for an app."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)

        let groups = try await ASCPaging.allPages(next: { $0.links.next }) {
          try await client.betaGroupsGetCollection(query: .init(filterApp: [app.id], sort: [.name], limit: 200)).ok.body.json
        }.flatMap(\.data)

        if groups.isEmpty {
          print("No beta groups found.")
          return
        }

        var rows: [[String]] = []
        for group in groups {
          let a = group.attributes
          let link = a?.publicLinkEnabled == true ? (a?.publicLink ?? "—") : "—"
          let limit = a?.publicLinkLimitEnabled == true
            ? a?.publicLinkLimit.map(String.init) ?? "—" : "—"
          rows.append([
            a?.name ?? "—",
            a?.isInternalGroup == true ? "Internal" : "External",
            link,
            limit,
            a?.feedbackEnabled == true ? "Yes" : "No",
            a?.createdDate.map { formatDate($0) } ?? "—",
          ])
        }

        Table.print(
          headers: ["Name", "Type", "Public Link", "Limit", "Feedback", "Created"],
          rows: rows
        )
      }
    }

    struct Info: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Show a beta group's details, testers, and builds."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The beta group name (interactive picker if omitted).")
      var group: String?

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let betaGroup = try await TestFlightCommand.findBetaGroup(
          name: group, appID: app.id, client: client)
        let a = betaGroup.attributes

        print("Name:          \(a?.name ?? "—")")
        print("Type:          \(a?.isInternalGroup == true ? "Internal" : "External")")
        if a?.isInternalGroup == true {
          print("All Builds:    \(a?.hasAccessToAllBuilds == true ? "Yes" : "No")")
        }
        print("Feedback:      \(a?.feedbackEnabled == true ? "Enabled" : "Disabled")")
        if a?.publicLinkEnabled == true {
          print("Public Link:   \(a?.publicLink ?? "—")")
          if a?.publicLinkLimitEnabled == true {
            print("Link Limit:    \(a?.publicLinkLimit.map(String.init) ?? "—")")
          }
        } else {
          print("Public Link:   Disabled")
        }
        // Whether testers can run the group's iPhone and iPad builds there.
        if let mac = a?.iosBuildsAvailableForAppleSiliconMac {
          print("On Macs:       \(mac ? "Available" : "Not Available")")
        }
        if let vision = a?.iosBuildsAvailableForAppleVision {
          print("On Vision Pro: \(vision ? "Available" : "Not Available")")
        }
        print("Created:       \(a?.createdDate.map { formatDate($0) } ?? "—")")
        print("Group ID:      \(betaGroup.id)")

        let testers = try await BetaGroups.testers(groupID: betaGroup.id, client: client)
        print()
        if testers.isEmpty {
          print("No testers in this group.")
        } else {
          print("Testers (\(testers.count)):")
          var rows: [[String]] = []
          for tester in testers {
            let name = [tester.firstName, tester.lastName].compactMap { $0 }.joined(separator: " ")
            rows.append([
              tester.email ?? "—",
              name.isEmpty ? "—" : name,
              tester.state.map { formatState($0) } ?? "—",
            ])
          }
          Table.print(headers: ["Email", "Name", "State"], rows: rows)
        }

        // Internal groups with access to all builds have no explicit build list.
        guard a?.hasAccessToAllBuilds != true else { return }

        let builds = try await AscelerateCore.Builds.list(appID: app.id, groupID: betaGroup.id, limit: 50, client: client)
        print()
        if builds.isEmpty {
          print("No builds assigned to this group.")
        } else {
          print("Builds (\(builds.count)):")
          var rows: [[String]] = []
          for build in builds {
            rows.append([
              build.number ?? "—",
              build.version == nil ? "—" : build.train,
              build.uploadedDate.map { formatDate($0) } ?? "—",
              build.expired ? red("Expired") : build.expirationDate.map { formatDate($0) } ?? "—",
            ])
          }
          Table.print(headers: ["Build", "Version", "Uploaded", "Expires"], rows: rows)
        }
      }
    }

    struct Create: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Create a beta group."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Group name (required).")
      var name: String

      @Flag(name: .long, help: "Create an internal group (team members) instead of an external one.")
      var `internal` = false

      @Flag(name: .long, help: "Give the group access to all builds automatically (internal groups only).")
      var allBuilds = false

      @Flag(name: .long, help: "Enable a public invite link.")
      var publicLink = false

      @Option(name: .long, help: "Maximum number of testers who can join via the public link (implies --public-link).")
      var publicLinkLimit: Int?

      @Option(name: .long, help: "Enable or disable tester feedback (true/false, default true).")
      var feedback: Bool?

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        if allBuilds && !`internal` {
          throw ValidationError("--all-builds is only valid with --internal.")
        }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)

        let linkEnabled = publicLink || publicLinkLimit != nil
        print("Create beta group:")
        print("  Name:        \(name)")
        print("  Type:        \(`internal` ? "Internal" : "External")")
        if `internal` { print("  All Builds:  \(allBuilds ? "Yes" : "No")") }
        if linkEnabled {
          print("  Public Link: Enabled\(publicLinkLimit.map { " (limit \($0))" } ?? "")")
        }
        print()

        guard confirm("Create this group? [y/N] ") else {
          cancelled()
          return
        }

        let created = try await BetaGroups.create(
          appID: app.id, name: name, isInternal: `internal`, allBuilds: allBuilds, publicLink: publicLink,
          publicLinkLimit: publicLinkLimit, feedback: feedback, client: client)

        print()
        success("Created", "beta group '\(name)'.")
        if let link = created.publicLink {
          print("  Public link: \(link)")
        }
      }
    }

    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Update a beta group's name, public link, feedback, or where its iOS builds can be tested."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The beta group name (interactive picker if omitted).")
      var group: String?

      @Option(name: .long, help: "New group name.")
      var name: String?

      @Option(name: .long, help: "Enable or disable the public invite link (true/false).")
      var publicLink: Bool?

      @Option(name: .long, help: "Public link tester limit. Pass 0 to remove the limit.")
      var publicLinkLimit: Int?

      @Option(name: .long, help: "Enable or disable tester feedback (true/false).")
      var feedback: Bool?

      @Option(name: .long, help: "Let testers run the group's iPhone and iPad builds on Apple silicon Macs (true/false).")
      var mac: Bool?

      @Option(name: .long, help: "Let testers run the group's iPhone and iPad builds on Apple Vision Pro (true/false).")
      var visionPro: Bool?

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        guard name != nil || publicLink != nil || publicLinkLimit != nil || feedback != nil || mac != nil
          || visionPro != nil
        else {
          throw ValidationError(
            "No updates specified. Use --name, --public-link, --public-link-limit, --feedback, --mac, or --vision-pro.")
        }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let betaGroup = try await TestFlightCommand.findBetaGroup(
          name: group, appID: app.id, client: client)
        let groupName = betaGroup.attributes?.name ?? "?"

        var changes: [String] = []
        if let v = name { changes.append("Name: \(v)") }
        if let v = publicLink { changes.append("Public Link: \(v ? "Enabled" : "Disabled")") }
        if let v = publicLinkLimit {
          changes.append(v > 0 ? "Link Limit: \(v)" : "Link Limit: removed")
        }
        if let v = feedback { changes.append("Feedback: \(v ? "Enabled" : "Disabled")") }
        if let v = mac { changes.append("On Macs: \(v ? "Available" : "Not Available")") }
        if let v = visionPro { changes.append("On Vision Pro: \(v ? "Available" : "Not Available")") }
        print("Updates for group '\(groupName)':")
        for c in changes { print("  \(c)") }
        print()

        guard confirm("Apply updates? [y/N] ") else {
          cancelled()
          return
        }

        try await BetaGroups.update(
          groupID: betaGroup.id, name: name, publicLink: publicLink, publicLinkLimit: publicLinkLimit, feedback: feedback,
          iOSBuildsOnMac: mac, iOSBuildsOnVision: visionPro, client: client)

        print()
        success("Updated", "beta group '\(name ?? groupName)'.")
      }
    }

    struct Delete: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Delete a beta group (testers lose access; accounts are not deleted)."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The beta group name (interactive picker if omitted).")
      var group: String?

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let betaGroup = try await TestFlightCommand.findBetaGroup(
          name: group, appID: app.id, client: client)
        let groupName = betaGroup.attributes?.name ?? "?"

        print("Beta group: \(TestFlightCommand.describeGroup(betaGroup))")
        print()
        guard confirm("Delete this group? Its testers lose access to builds. [y/N] ") else {
          cancelled()
          return
        }

        try await BetaGroups.delete(groupID: betaGroup.id, client: client)
        print()
        success("Deleted", "beta group '\(groupName)'.")
      }
    }

    struct AddBuild: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "add-build",
        abstract: "Give a beta group access to a build."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The beta group name (interactive picker if omitted).")
      var group: String?

      @OptionGroup var buildOptions: BuildOptions

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let betaGroup = try await TestFlightCommand.findBetaGroup(
          name: group, appID: app.id, client: client)
        let resolved = try await buildOptions.resolve(appID: app.id, client: client)
        let groupName = betaGroup.attributes?.name ?? "?"

        print("Add build \(resolved.label) to group '\(groupName)'.")
        guard confirm("Continue? [y/N] ") else {
          cancelled()
          return
        }

        try await BetaGroups.addBuild(resolved.id, toGroup: betaGroup.id, client: client)
        print()
        success("Added", "build \(resolved.label) to group '\(groupName)'.")
      }
    }

    struct RemoveBuild: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "remove-build",
        abstract: "Remove a build from a beta group."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The beta group name (interactive picker if omitted).")
      var group: String?

      @OptionGroup var buildOptions: BuildOptions

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let betaGroup = try await TestFlightCommand.findBetaGroup(
          name: group, appID: app.id, client: client)
        let resolved = try await buildOptions.resolve(appID: app.id, client: client)
        let groupName = betaGroup.attributes?.name ?? "?"

        print("Remove build \(resolved.label) from group '\(groupName)'.")
        guard confirm("Continue? [y/N] ") else {
          cancelled()
          return
        }

        try await BetaGroups.removeBuild(resolved.id, fromGroup: betaGroup.id, client: client)
        print()
        success("Removed", "build \(resolved.label) from group '\(groupName)'.")
      }
    }

    struct Criteria: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "criteria",
        abstract: "Manage public-link recruitment criteria (device/OS filters).",
        subcommands: [View.self, Set.self, Clear.self]
      )

      static func printFilters(_ criteria: RecruitmentCriteria.Criteria) {
        for filter in criteria.filters {
          print("  \(formatState(filter.deviceFamily)): \(filter.minimumOS ?? "any") – \(filter.maximumOS ?? "any")")
        }
      }

      /// Parses a `FAMILY[:MIN[:MAX]]` filter spec (e.g. `IPHONE:18.0` or `IPAD:17.0:18.5`).
      static func parseFilterSpec(_ spec: String) throws -> RecruitmentCriteria.Filter {
        let parts = spec.split(separator: ":", omittingEmptySubsequences: false)
          .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count <= 3 else {
          throw ValidationError("Invalid filter '\(spec)'. Use FAMILY[:MIN[:MAX]], e.g. IPHONE:18.0.")
        }
        let family: ASCEnum.DeviceFamily = try parseEnum(parts[0], name: "device family")
        let min = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
        let max = parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil
        return .init(deviceFamily: family.rawValue, minimumOS: min, maximumOS: max)
      }

      struct View: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "View a group's recruitment criteria."
        )

        @Argument(help: "The bundle identifier of the app.",
                  completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
        var bundleID: String

        @Argument(help: "The beta group name (interactive picker if omitted).")
        var group: String?

        @Flag(name: .long, help: "Also list the device families and OS versions available for criteria.")
        var options = false

        func run() async throws {
          let client = try ClientFactory.makeClient()
          let app = try await findApp(bundleID: bundleID, client: client)
          let betaGroup = try await TestFlightCommand.findBetaGroup(
            name: group, appID: app.id, client: client)

          if let criterion = try await RecruitmentCriteria.criteria(groupID: betaGroup.id, client: client) {
            print("Recruitment criteria for '\(betaGroup.attributes?.name ?? "?")':")
            Criteria.printFilters(criterion)
          } else {
            print("No recruitment criteria set for '\(betaGroup.attributes?.name ?? "?")'.")
          }

          if options {
            let options = try await RecruitmentCriteria.options(client: client)
            print()
            print("Available criteria options:")
            for option in options {
              print("  \(formatState(option.deviceFamily)): \(option.osVersions.joined(separator: ", "))")
            }
          }
        }
      }

      struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Replace a group's existing recruitment criteria.",
          discussion: """
            Each --filter takes FAMILY[:MIN[:MAX]] with inclusive OS bounds, e.g.
            --filter IPHONE:18.0 --filter IPAD:17.0:18.5. Valid families: IPHONE, IPAD,
            MAC, APPLE_TV, APPLE_WATCH, VISION. Use `criteria view --options` to see
            selectable OS versions. Criteria apply to groups with a public link enabled.
            New criteria can no longer be added; only a group's existing ones change.
            """
        )

        @Argument(help: "The bundle identifier of the app.",
                  completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
        var bundleID: String

        @Argument(help: "The beta group name (interactive picker if omitted).")
        var group: String?

        @Option(name: .long, help: "Device/OS filter as FAMILY[:MIN[:MAX]] (repeatable).")
        var filter: [String]

        @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          guard !filter.isEmpty else {
            throw ValidationError("Pass at least one --filter.")
          }
          let filters = try filter.map { try Criteria.parseFilterSpec($0) }

          let client = try ClientFactory.makeClient()
          let app = try await findApp(bundleID: bundleID, client: client)
          let betaGroup = try await TestFlightCommand.findBetaGroup(
            name: group, appID: app.id, client: client)
          let groupName = betaGroup.attributes?.name ?? "?"
          guard let existing = try await RecruitmentCriteria.criteria(groupID: betaGroup.id, client: client) else {
            throw ValidationError(
              "'\(groupName)' has no recruitment criteria, and they can no longer be added (neither through the API nor in App Store Connect). Groups that have them can still change or clear them.")
          }

          print("Recruitment criteria for '\(groupName)':")
          for f in filters {
            print("  \(formatState(f.deviceFamily)): \(f.minimumOS ?? "any") – \(f.maximumOS ?? "any")")
          }
          print()
          guard confirm("Apply these criteria? [y/N] ") else {
            cancelled()
            return
          }

          try await RecruitmentCriteria.update(filters, id: existing.id, client: client)

          print()
          success("Updated", "recruitment criteria for '\(groupName)'.")
        }
      }

      struct Clear: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Remove a group's recruitment criteria."
        )

        @Argument(help: "The bundle identifier of the app.",
                  completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
        var bundleID: String

        @Argument(help: "The beta group name (interactive picker if omitted).")
        var group: String?

        @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          let client = try ClientFactory.makeClient()
          let app = try await findApp(bundleID: bundleID, client: client)
          let betaGroup = try await TestFlightCommand.findBetaGroup(
            name: group, appID: app.id, client: client)
          let groupName = betaGroup.attributes?.name ?? "?"

          guard let existing = try await RecruitmentCriteria.criteria(groupID: betaGroup.id, client: client) else {
            print("No recruitment criteria set for '\(groupName)'.")
            return
          }

          print("Current criteria for '\(groupName)':")
          Criteria.printFilters(existing)
          print()
          guard confirm("Remove these criteria? [y/N] ") else {
            cancelled()
            return
          }

          try await RecruitmentCriteria.delete(id: existing.id, client: client)
          print()
          success("Removed", "recruitment criteria for '\(groupName)'.")
        }
      }
    }
  }

  // MARK: - Testers

  struct Testers: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "testers",
      abstract: "Manage beta testers.",
      subcommands: [List.self, Add.self, Remove.self, Invite.self, Import.self]
    )

    /// Finds a tester by email within the app's testers.
    static func findTester(
      email: String, appID: String, client: ASCClient
    ) async throws -> BetaTesters.Tester {
      guard let tester = try await BetaTesters.find(email: email, appID: appID, client: client) else {
        throw ValidationError("No beta tester '\(email)' found for this app.")
      }
      return tester
    }

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "List beta testers for an app."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Only testers in this beta group.")
      var group: String?

      @Option(name: .long, help: "Filter by email (substring matching is done by the API).")
      var email: String?

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)

        var groupID: String?
        if let group {
          groupID = try await TestFlightCommand.findBetaGroup(name: group, appID: app.id, client: client).id
        }

        let testers = try await BetaTesters.list(appID: app.id, groupID: groupID, email: email, client: client)

        if testers.isEmpty {
          print("No beta testers found.")
          return
        }

        var rows: [[String]] = []
        for tester in testers {
          let name = [tester.firstName, tester.lastName].compactMap { $0 }.joined(separator: " ")
          rows.append([
            tester.email ?? "—",
            name.isEmpty ? "—" : name,
            tester.state.map { formatState($0) } ?? "—",
            tester.inviteType.map { formatState($0) } ?? "—",
          ])
        }

        Table.print(headers: ["Email", "Name", "State", "Invite Type"], rows: rows)
        print()
        print("\(testers.count) tester(s).")
      }
    }

    struct Add: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Add a beta tester to one or more groups (sends an invite for external groups)."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Tester email (required).")
      var email: String

      @Option(name: .long, help: "Tester first name.")
      var firstName: String?

      @Option(name: .long, help: "Tester last name.")
      var lastName: String?

      @Option(name: .long, help: "Comma-separated beta group name(s) to add the tester to (required).")
      var group: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)

        var groups: [Components.Schemas.BetaGroup] = []
        for name in group.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
          groups.append(
            try await TestFlightCommand.findBetaGroup(name: name, appID: app.id, client: client))
        }
        let groupNames = groups.compactMap { $0.attributes?.name }.joined(separator: ", ")

        print("Add beta tester:")
        print("  Email:  \(email)")
        if firstName != nil || lastName != nil {
          print("  Name:   \([firstName, lastName].compactMap { $0 }.joined(separator: " "))")
        }
        print("  Groups: \(groupNames)")
        print()

        guard confirm("Add this tester? [y/N] ") else {
          cancelled()
          return
        }

        try await BetaTesters.create(
          email: email, firstName: firstName, lastName: lastName, groupIDs: groups.map(\.id), client: client)

        print()
        success("Added", "tester '\(email)' to \(groupNames).")
      }
    }

    struct Remove: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Remove a beta tester from a group, or from the app entirely."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The tester's email.")
      var email: String

      @Option(name: .long, help: "Only remove from this beta group (otherwise removes app access entirely).")
      var group: String?

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let tester = try await Testers.findTester(email: email, appID: app.id, client: client)

        if let group {
          let betaGroup = try await TestFlightCommand.findBetaGroup(
            name: group, appID: app.id, client: client)
          let groupName = betaGroup.attributes?.name ?? "?"
          guard confirm("Remove '\(email)' from group '\(groupName)'? [y/N] ") else {
            cancelled()
            return
          }
          try await BetaGroups.removeTester(tester.id, fromGroup: betaGroup.id, client: client)
          print()
          success("Removed", "tester '\(email)' from group '\(groupName)'.")
        } else {
          guard confirm(
            "Remove '\(email)' from ALL groups and builds of this app? [y/N] ") else {
            cancelled()
            return
          }
          try await BetaTesters.removeFromApp(testerID: tester.id, appID: app.id, client: client)
          print()
          success("Removed", "tester '\(email)' from the app.")
        }
      }
    }

    struct Invite: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Re-send the TestFlight invitation email to a tester."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The tester's email.")
      var email: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let tester = try await Testers.findTester(email: email, appID: app.id, client: client)

        let state = tester.state.map { formatState($0) } ?? "?"
        print("Tester: \(email) (\(state))")
        print()
        guard confirm("Re-send the invitation email? [y/N] ") else {
          cancelled()
          return
        }

        try await BetaTesters.invite(testerID: tester.id, appID: app.id, client: client)
        print()
        success("Sent", "invitation to '\(email)'.")
      }
    }

    struct Import: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Bulk-add testers from a CSV file.",
        discussion: """
          The file has one tester per line: email[,first name[,last name]]. Blank lines,
          lines starting with #, and a leading header row are skipped. Matches the CSV
          format App Store Connect's web UI exports.
          """
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Path to the CSV file.",
              completion: .file(extensions: ["csv", "txt"]))
      var file: String?

      @Option(name: .long, help: "Comma-separated beta group name(s) to add the testers to (required).")
      var group: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)

        var groups: [Components.Schemas.BetaGroup] = []
        for name in group.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
          groups.append(
            try await TestFlightCommand.findBetaGroup(name: name, appID: app.id, client: client))
        }
        let groupNames = groups.compactMap { $0.attributes?.name }.joined(separator: ", ")

        let filePath = try resolveFile(file, extension: "csv", prompt: "Select a CSV file")
        let content = try String(contentsOf: URL(fileURLWithPath: filePath), encoding: .utf8)

        let testers = BetaTesters.parseCSV(content)

        guard !testers.isEmpty else {
          throw ValidationError("No testers found in \(filePath).")
        }

        print("Importing \(testers.count) tester(s) into: \(groupNames)")
        for t in testers.prefix(10) {
          let name = [t.firstName, t.lastName].compactMap { $0 }.joined(separator: " ")
          print("  \(t.email)\(name.isEmpty ? "" : " (\(name))")")
        }
        if testers.count > 10 { print("  … and \(testers.count - 10) more") }
        print()
        guard confirm("Add \(testers.count) tester(s)? [y/N] ") else {
          cancelled()
          return
        }
        print()

        var failed: [String] = []
        for t in testers {
          do {
            try await BetaTesters.create(
              email: t.email, firstName: t.firstName, lastName: t.lastName, groupIDs: groups.map(\.id), client: client)
            print("  \(t.email) \(green("Added."))")
          } catch {
            failed.append(t.email)
            print("  \(t.email) \(red("Failed:")) \(describeError(error))")
          }
        }

        print()
        if failed.isEmpty {
          success("Added", "\(testers.count) tester(s) to \(groupNames).")
        } else {
          print(red("\(failed.count) of \(testers.count) tester(s) failed:") + " \(failed.joined(separator: ", "))")
          throw ExitCode.failure
        }
      }
    }
  }

  // MARK: - Builds

  struct Builds: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "builds",
      abstract: "List builds with their TestFlight states."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @OptionGroup var platformOption: PlatformOption

    @Option(name: .long, help: "Maximum number of builds to show (default 20).")
    var limit: Int = 20

    @OptionGroup var jsonOption: JSONOption

    private struct Entry: Encodable {
      let id: String
      let buildNumber: String?
      let version: String?
      let platform: String?
      let uploadedDate: Date?
      let expirationDate: Date?
      let isExpired: Bool?
      let processingState: String?
      let internalBuildState: String?
      let externalBuildState: String?
    }

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let builds = try await AscelerateCore.Builds.list(
        appID: app.id, platform: try platformOption.parsed(), limit: min(limit, 200), client: client)

      let entries = builds.map { build in
        Entry(
          id: build.id,
          buildNumber: build.number,
          version: build.version,
          platform: build.platform,
          uploadedDate: build.uploadedDate,
          expirationDate: build.expirationDate,
          isExpired: build.expired,
          processingState: build.processingState,
          internalBuildState: build.internalState,
          externalBuildState: build.externalState
        )
      }

      if jsonOption.json {
        try printJSON(entries)
        return
      }

      if entries.isEmpty {
        print("No builds found.")
        return
      }

      let rows = entries.map { e -> [String] in
        let train = e.version.map { v in "\(e.platform.map { formatState($0) } ?? "?") \(v)" } ?? "—"
        return [
          e.buildNumber ?? "—",
          train,
          e.uploadedDate.map { formatDate($0) } ?? "—",
          e.processingState.map { formatState($0) } ?? "—",
          e.internalBuildState.map { formatState($0) } ?? "—",
          e.externalBuildState.map { formatState($0) } ?? "—",
          e.isExpired == true ? red("Expired") : e.expirationDate.map { formatDate($0) } ?? "—",
        ]
      }

      Table.print(
        headers: ["Build", "Version", "Uploaded", "Processing", "Internal", "External", "Expires"],
        rows: rows
      )
    }
  }

  // MARK: - Versions

  struct Versions: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "versions",
      abstract: "List pre-release version trains."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @OptionGroup var platformOption: PlatformOption

    @Option(name: .long, help: "Maximum number of versions to show (default 20).")
    var limit: Int = 20

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let versions = try await AscelerateCore.Builds.preReleaseVersions(
        appID: app.id, platform: try platformOption.parsed(), limit: limit, client: client)

      if versions.isEmpty {
        print("No pre-release versions found.")
        return
      }

      var rows: [[String]] = []
      for version in versions {
        rows.append([
          version.attributes?.version ?? "—",
          version.attributes?.platform.map { formatState($0) } ?? "—",
        ])
      }
      Table.print(headers: ["Version", "Platform"], rows: rows)
    }
  }

  // MARK: - Expire

  struct Expire: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Expire a build so testers can no longer install it."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @OptionGroup var buildOptions: BuildOptions

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let resolved = try await buildOptions.resolve(appID: app.id, client: client)

      if resolved.expired {
        print("Build \(resolved.label) is already expired.")
        return
      }

      print("Build: \(resolved.label), uploaded \(resolved.uploadedDate.map { formatDate($0) } ?? "?")")
      print()
      guard confirm("Expire this build? Testers can no longer install it. [y/N] ") else {
        cancelled()
        return
      }

      try await AscelerateCore.Builds.expire(id: resolved.id, client: client)
      print()
      success("Expired", "build \(resolved.label).")
    }
  }

  // MARK: - Notify

  struct Notify: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Notify testers that a build is available."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @OptionGroup var buildOptions: BuildOptions

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let resolved = try await buildOptions.resolve(appID: app.id, client: client)

      guard confirm("Notify testers about build \(resolved.label)? [y/N] ") else {
        cancelled()
        return
      }

      try await AscelerateCore.Builds.notifyTesters(buildID: resolved.id, client: client)
      print()
      success("Notified", "testers about build \(resolved.label).")
    }
  }

  // MARK: - Auto-Notify

  struct AutoNotify: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "auto-notify",
      abstract: "Enable or disable automatic tester notification for a build."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .long, help: "Whether testers are notified automatically (true/false).")
    var enabled: Bool

    @OptionGroup var buildOptions: BuildOptions

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let resolved = try await buildOptions.resolve(appID: app.id, client: client)

      guard let detail = try await AscelerateCore.Builds.betaDetail(buildID: resolved.id, client: client) else {
        throw ValidationError("No build beta detail found for build \(resolved.label).")
      }

      if detail.attributes?.autoNotifyEnabled == enabled {
        print("Auto-notify is already \(enabled ? "enabled" : "disabled") for build \(resolved.label).")
        return
      }

      guard confirm("\(enabled ? "Enable" : "Disable") auto-notify for build \(resolved.label)? [y/N] ") else {
        cancelled()
        return
      }

      try await AscelerateCore.Builds.setAutoNotify(enabled, detailID: detail.id, client: client)
      print()
      success("Updated", "auto-notify \(enabled ? "enabled" : "disabled") for build \(resolved.label).")
    }
  }

  // MARK: - What to Test

  struct WhatsNew: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "whats-new",
      abstract: "View, set, export, and import a build's test notes (What to Test).",
      subcommands: [View.self, Set.self, Export.self, Import.self]
    )

    /// Applies What to Test text per locale, patching existing localizations and creating missing
    /// ones, and says which.
    static func apply(updates: [(locale: String, text: String)], buildID: String, client: ASCClient) async throws {
      try await AscelerateCore.Builds.setTestNotes(updates, buildID: buildID, client: client) { locale, created in
        print("  [\(localeName(locale))] " + (created ? green("Created.") : "Updated."))
      }
    }

    struct View: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "View a build's test notes per locale."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @OptionGroup var buildOptions: BuildOptions

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let resolved = try await buildOptions.resolve(appID: app.id, client: client)

        let locs = try await AscelerateCore.Builds.testNotes(buildID: resolved.id, client: client)
        print("What to Test for build \(resolved.label):")
        print()
        if locs.isEmpty {
          print("No test notes set.")
          return
        }
        for loc in locs {
          print("[\(localeName(loc.locale))]")
          let text = loc.text ?? ""
          print(text.isEmpty ? "  —" : text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "  \($0)" }.joined(separator: "\n"))
          print()
        }
      }
    }

    struct Set: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Set a build's test notes for one locale, or all locales at once."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "The test notes text (required).")
      var text: String

      @Option(name: .long, help: "Locale (e.g. en-US). Omit to apply to all existing locales.")
      var locale: String?

      @OptionGroup var buildOptions: BuildOptions

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let resolved = try await buildOptions.resolve(appID: app.id, client: client)

        var targets: [String]
        if let locale {
          targets = [locale]
        } else {
          let existing = try await AscelerateCore.Builds.testNotes(buildID: resolved.id, client: client)
          targets = existing.map(\.locale)
          guard !targets.isEmpty else {
            throw ValidationError(
              "This build has no localizations yet. Pass --locale to create one.")
          }
        }

        print("Set What to Test for build \(resolved.label):")
        print("  Locales: \(targets.joined(separator: ", "))")
        print("  Text:    \(text.count > 120 ? "\(text.prefix(120))…" : text)")
        print()
        guard confirm("Apply to \(targets.count) locale(s)? [y/N] ") else {
          cancelled()
          return
        }
        print()

        try await WhatsNew.apply(
          updates: targets.map { ($0, text) }, buildID: resolved.id, client: client)
        print()
        success("Updated", "test notes for build \(resolved.label).")
      }
    }

    struct Export: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Export a build's test notes to a JSON file."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @OptionGroup var buildOptions: BuildOptions

      @Option(name: .long, help: "Output file path.",
              completion: .file(extensions: ["json"]))
      var output: String?

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let resolved = try await buildOptions.resolve(appID: app.id, client: client)

        let locs = try await AscelerateCore.Builds.testNotes(buildID: resolved.id, client: client)
        var result: [String: WhatsNewFields] = [:]
        for loc in locs {
          result[loc.locale] = WhatsNewFields(whatsNew: loc.text)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)

        let outputPath = expandPath(
          confirmOutputPath(output ?? "whats-new.json", isDirectory: false))
        try data.write(to: URL(fileURLWithPath: outputPath))

        print(green("Exported") + " \(result.count) locale(s) to \(outputPath)")
      }
    }

    struct Import: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Import a build's test notes from a JSON file."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @OptionGroup var buildOptions: BuildOptions

      @Option(name: .long, help: "Path to JSON file.",
              completion: .file(extensions: ["json"]))
      var file: String?

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let resolved = try await buildOptions.resolve(appID: app.id, client: client)

        let filePath = try resolveFile(file, extension: "json", prompt: "Select a JSON file")
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let localeUpdates = try JSONDecoder().decode([String: WhatsNewFields].self, from: data)
        let updates = localeUpdates
          .compactMap { locale, fields in fields.whatsNew.map { (locale: locale, text: $0) } }
          .sorted { $0.locale < $1.locale }

        guard !updates.isEmpty else {
          throw ValidationError("JSON file contains no test notes.")
        }

        print("Importing test notes for build \(resolved.label):")
        for update in updates { print("  [\(localeName(update.locale))]") }
        print()
        guard confirm("Send updates for \(updates.count) locale(s)? [y/N] ") else {
          cancelled()
          return
        }
        print()

        try await WhatsNew.apply(updates: updates, buildID: resolved.id, client: client)
        print()
        print("Done.")
      }
    }
  }

  // MARK: - Submit

  struct Submit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Submit a build for beta review (required for external testing)."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @OptionGroup var buildOptions: BuildOptions

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let resolved = try await buildOptions.resolve(appID: app.id, client: client)

      print("Build: \(resolved.label), uploaded \(resolved.uploadedDate.map { formatDate($0) } ?? "?")")
      print()
      guard confirm("Submit this build for beta review? [y/N] ") else {
        cancelled()
        return
      }

      let reviewState = try await AscelerateCore.Builds.submitForBetaReview(buildID: resolved.id, client: client)

      print()
      success("Submitted", "build \(resolved.label) for beta review.")
      if let state = reviewState {
        print("  State: \(formatState(state))")
      }
    }
  }

  // MARK: - Status

  struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Show a build's TestFlight and beta review status."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @OptionGroup var buildOptions: BuildOptions

    @OptionGroup var jsonOption: JSONOption

    private struct Detail: Encodable {
      let id: String
      let buildNumber: String?
      let version: String?
      let platform: String?
      let uploadedDate: Date?
      let expirationDate: Date?
      let isExpired: Bool?
      let processingState: String?
      let internalBuildState: String?
      let externalBuildState: String?
      let autoNotifyEnabled: Bool?
      let betaReviewState: String?
    }

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let resolved = try await buildOptions.resolve(appID: app.id, client: client)
      let detail = try await AscelerateCore.Builds.betaDetail(buildID: resolved.id, client: client)
      let submission = try await BetaReview.submission(buildID: resolved.id, client: client)

      let d = detail?.attributes
      let status = Detail(
        id: resolved.id,
        buildNumber: resolved.number,
        version: resolved.version,
        platform: resolved.platform,
        uploadedDate: resolved.uploadedDate,
        expirationDate: resolved.expirationDate,
        isExpired: resolved.expired,
        processingState: resolved.processingState,
        internalBuildState: d?.internalBuildState,
        externalBuildState: d?.externalBuildState,
        autoNotifyEnabled: d?.autoNotifyEnabled,
        betaReviewState: submission?.state
      )

      if jsonOption.json {
        try printJSON(status)
        return
      }

      print("Build:            \(resolved.label)")
      print("Uploaded:         \(status.uploadedDate.map { formatDate($0) } ?? "—")")
      print("Expires:          \(status.isExpired == true ? red("Expired") : status.expirationDate.map { formatDate($0) } ?? "—")")
      print("Processing:       \(status.processingState.map { formatState($0) } ?? "—")")
      print("Internal Testing: \(status.internalBuildState.map { formatState($0) } ?? "—")")
      print("External Testing: \(status.externalBuildState.map { formatState($0) } ?? "—")")
      print("Auto-Notify:      \(status.autoNotifyEnabled == true ? "Yes" : "No")")
      print("Beta Review:      \(status.betaReviewState.map { formatState($0) } ?? "Not submitted")")
    }
  }

  // MARK: - Beta App Information

  struct AppInfo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "app-info",
      abstract: "View, update, export, and import TestFlight beta app information.",
      subcommands: [View.self, Update.self, Export.self, Import.self]
    )

    struct View: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "View beta app information per locale."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let locs = try await TestInformation.localizations(appID: app.id, client: client)

        if locs.isEmpty {
          print("No beta app information found.")
          return
        }
        print("Beta app information for \(app.attributes?.name ?? bundleID):")
        print()
        for loc in locs {
          print("[\(localeName(loc.locale))]")
          print("  Feedback Email:  \(loc.feedbackEmail ?? "—")")
          print("  Marketing URL:   \(loc.marketingURL ?? "—")")
          print("  Privacy Policy:  \(loc.privacyPolicyURL ?? "—")")
          if let tvOs = loc.tvOSPrivacyPolicy, !tvOs.isEmpty {
            print("  tvOS Privacy:    \(tvOs)")
          }
          if let desc = loc.description, !desc.isEmpty {
            print("  Description:     \(desc.prefix(200))\(desc.count > 200 ? "…" : "")")
          } else {
            print("  Description:     —")
          }
          print()
        }
      }
    }

    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Update beta app information for a locale."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Locale (e.g. en-US). Defaults to the only existing locale, or prompts.")
      var locale: String?

      @Option(name: .long, help: "Beta app description shown to testers.")
      var description: String?

      @Option(name: .long, help: "Email testers can send feedback to.")
      var feedbackEmail: String?

      @Option(name: .long, help: "Marketing URL.")
      var marketingURL: String?

      @Option(name: .long, help: "Privacy policy URL.")
      var privacyPolicyURL: String?

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        guard description != nil || feedbackEmail != nil || marketingURL != nil
          || privacyPolicyURL != nil
        else {
          throw ValidationError(
            "No updates specified. Use --description, --feedback-email, --marketing-url, or --privacy-policy-url.")
        }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let locs = try await TestInformation.localizations(appID: app.id, client: client)

        let targetLocale: String
        if let locale {
          targetLocale = locale
        } else if locs.count == 1 {
          targetLocale = locs[0].locale
        } else {
          targetLocale = try promptSelection(
            "Select a locale", items: locs,
            display: { localeName($0.locale) },
            nonInteractiveHint: "Pass --locale to disambiguate.").locale
        }

        guard confirm("Update beta app information for \(localeName(targetLocale))? [y/N] ") else {
          cancelled()
          return
        }

        let fields = BetaAppLocaleFields(
          description: description, feedbackEmail: feedbackEmail, marketingURL: marketingURL,
          privacyPolicyURL: privacyPolicyURL)
        try await TestInformation.save([(targetLocale, fields)], appID: app.id, client: client)

        print()
        success("Updated", "beta app information for \(localeName(targetLocale)).")
      }
    }

    struct Export: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Export beta app information to a JSON file."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Output file path.",
              completion: .file(extensions: ["json"]))
      var output: String?

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let locs = try await TestInformation.localizations(appID: app.id, client: client)
        let result = Dictionary(locs.map { ($0.locale, $0.fields) }, uniquingKeysWith: { first, _ in first })
        let data = try LocalizationFile.encode(result)

        let outputPath = expandPath(
          confirmOutputPath(output ?? "beta-app-info.json", isDirectory: false))
        try data.write(to: URL(fileURLWithPath: outputPath))

        print(green("Exported") + " \(result.count) locale(s) to \(outputPath)")
      }
    }

    struct Import: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Import beta app information from a JSON file."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Path to JSON file.",
              completion: .file(extensions: ["json"]))
      var file: String?

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)

        let filePath = try resolveFile(file, extension: "json", prompt: "Select a JSON file")
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let localeUpdates = try JSONDecoder().decode([String: BetaAppLocaleFields].self, from: data)

        guard !localeUpdates.isEmpty else {
          throw ValidationError("JSON file contains no locale data.")
        }

        print("Importing beta app information for \(localeUpdates.count) locale(s):")
        for locale in localeUpdates.keys.sorted() {
          print("  [\(localeName(locale))]")
        }
        print()
        guard confirm("Send updates for \(localeUpdates.count) locale(s)? [y/N] ") else {
          cancelled()
          return
        }
        print()

        try await TestInformation.save(
          localeUpdates.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }, appID: app.id, client: client
        ) { locale, created in
          print("  [\(localeName(locale))] \(created ? green("Created.") : "Updated.")")
        }

        print()
        print("Done.")
      }
    }
  }

  // MARK: - Beta App Review Information

  struct ReviewInfo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "review-info",
      abstract: "View or update beta review information (contact, demo account).",
      discussion: """
        With no update flags, prints the current beta review information. Pass any field flag
        to update it; omitted fields are left unchanged.
        """
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .long, help: "Review contact first name.")
    var contactFirstName: String?

    @Option(name: .long, help: "Review contact last name.")
    var contactLastName: String?

    @Option(name: .long, help: "Review contact phone number.")
    var contactPhone: String?

    @Option(name: .long, help: "Review contact email.")
    var contactEmail: String?

    @Option(name: .long, help: "Demo account username.")
    var demoAccountName: String?

    @Option(name: .long, help: "Demo account password.")
    var demoAccountPassword: String?

    @Option(name: .long, help: "Whether a demo account is required for beta review (true/false).")
    var demoAccountRequired: Bool?

    @Option(name: .long, help: "Notes for the beta review team.")
    var notes: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let detail = try await ReviewInformation.beta(appID: app.id, client: client)

      let hasUpdates =
        contactFirstName != nil || contactLastName != nil || contactPhone != nil
        || contactEmail != nil || demoAccountName != nil || demoAccountPassword != nil
        || demoAccountRequired != nil || notes != nil

      if !hasUpdates {
        guard let a = detail?.information else {
          print("No beta review information set.")
          return
        }
        let name = [a.contactFirstName, a.contactLastName].compactMap { $0 }.joined(separator: " ")
        print("Beta review information for \(app.attributes?.name ?? bundleID):")
        print("  Contact:       \(name.isEmpty ? "—" : name)")
        print("  Phone:         \(a.contactPhone ?? "—")")
        print("  Email:         \(a.contactEmail ?? "—")")
        print("  Demo Required: \(a.demoAccountRequired == true ? "Yes" : "No")")
        print("  Demo Account:  \(a.demoAccountName ?? "—")")
        print("  Demo Password: \(a.demoAccountPassword ?? "—")")
        print("  Notes:         \(a.notes ?? "—")")
        return
      }

      guard let detail else {
        throw ValidationError("No beta review detail record exists for this app yet.")
      }

      guard confirm("Update beta review information? [y/N] ") else {
        cancelled()
        return
      }

      try await ReviewInformation.saveBeta(
        ReviewInformation(
          contactFirstName: contactFirstName, contactLastName: contactLastName, contactPhone: contactPhone,
          contactEmail: contactEmail, demoAccountRequired: demoAccountRequired, demoAccountName: demoAccountName,
          demoAccountPassword: demoAccountPassword, notes: notes),
        from: detail.information, detailID: detail.id, client: client)

      print()
      success("Updated", "beta review information.")
    }
  }

  // MARK: - Beta License Agreement

  struct Eula: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "eula",
      abstract: "View or update the TestFlight beta license agreement.",
      discussion: """
        With no flags, prints the current agreement. Pass --file or --text to replace it;
        an empty --text "" reverts to Apple's standard agreement.
        """
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .long, help: "Path to a text file with the agreement text.",
            completion: .file(extensions: ["txt"]))
    var file: String?

    @Option(name: .long, help: "The agreement text.")
    var text: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      if file != nil && text != nil {
        throw ValidationError("Pass either --file or --text, not both.")
      }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      guard let agreement = try await BetaReview.licenseAgreement(appID: app.id, client: client) else {
        throw ValidationError("No beta license agreement record found for this app.")
      }

      var newText = text
      if let file {
        newText = try String(contentsOf: URL(fileURLWithPath: expandPath(file)), encoding: .utf8)
      }

      guard let newText else {
        let current = agreement.text
        if current.isEmpty {
          print("No custom beta license agreement set (Apple's standard agreement applies).")
        } else {
          print(current)
        }
        return
      }

      if newText.isEmpty {
        print("Reverting to Apple's standard beta license agreement.")
      } else {
        print("New agreement text (\(newText.count) characters):")
        print("  \(newText.prefix(200))\(newText.count > 200 ? "…" : "")")
      }
      print()
      guard confirm("Update the beta license agreement? [y/N] ") else {
        cancelled()
        return
      }

      try await BetaReview.setLicenseAgreement(newText, id: agreement.id, client: client)
      print()
      success("Updated", "beta license agreement.")
    }
  }

  // MARK: - Feedback

  struct Feedback: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "feedback",
      abstract: "Browse and download tester feedback (crashes, screenshots).",
      subcommands: [Crashes.self, Screenshots.self]
    )

    /// Shared device-detail text for crash and screenshot feedback — printed by the
    /// info commands and written into download archives.
    static func deviceDetailsText(_ submission: BetaFeedback.Submission) -> String {
      let s = submission
      var lines: [String] = []
      lines.append("Received:     \(s.createdDate.map { formatDate($0) } ?? "—")")
      lines.append("Tester:       \(s.email ?? "—")")
      lines.append("Device:       \(s.deviceModel ?? "—")")
      lines.append("OS Version:   \(s.osVersion ?? "—")")
      lines.append("Platform:     \(s.appPlatform.map { formatState($0) } ?? "—")")
      lines.append("Locale:       \(s.locale.map { localeName($0) } ?? "—")")
      lines.append("Time Zone:    \(s.timeZone ?? "—")")
      lines.append("Architecture: \(s.architecture ?? "—")")
      lines.append("Connection:   \(s.connectionType.map { formatState($0) } ?? "—")")
      lines.append("Battery:      \(s.batteryPercentage.map { "\($0)%" } ?? "—")")
      if let available = s.diskBytesAvailable, let total = s.diskBytesTotal {
        lines.append("Disk Free:    \(formatBytes(Int(available))) of \(formatBytes(Int(total)))")
      }
      if let uptime = s.appUptimeInMilliseconds {
        lines.append("App Uptime:   \(uptime / 1000)s")
      }
      lines.append("Bundle ID:    \(s.buildBundleID ?? "—")")
      if let comment = s.comment, !comment.isEmpty {
        lines.append("")
        lines.append("Comment:")
        lines.append(comment.split(separator: "\n", omittingEmptySubsequences: false)
          .map { "  \($0)" }.joined(separator: "\n"))
      }
      return lines.joined(separator: "\n")
    }

    /// Pages through an app's screenshot feedback and lets the user pick one.
    /// Loads more pages on demand ('m') so large feedback lists stay browsable.
    static func pickScreenshotSubmission(appID: String, client: ASCClient) async throws -> String {
      if autoConfirm {
        throw ValidationError(
          "Cannot pick a submission interactively with --yes. Pass the submission ID.")
      }

      // Pages load on demand ('m' for more), following each page's links.next.
      var nextLink: String?

      var items: [(id: String, line: String)] = []
      var exhausted = false

      func loadNextPage() async throws -> Int {
        guard !exhausted else { return 0 }
        let page = try await BetaFeedback.page(.screenshot, appID: appID, limit: 20, after: nextLink, client: client)
        nextLink = page.next
        exhausted = nextLink == nil
        for submission in page.submissions {
          let comment = (submission.comment ?? "—").replacingOccurrences(of: "\n", with: " ").truncated(40)
          items.append((
            submission.id,
            "\(submission.createdDate.map { formatDate($0) } ?? "—")  build \(submission.buildNumber ?? "—")  \(submission.deviceModel ?? "—")  \(comment)"
          ))
        }
        return page.submissions.count
      }

      _ = try await loadNextPage()
      guard !items.isEmpty else {
        throw ValidationError("No screenshot feedback found for this app.")
      }

      print("Screenshot feedback submissions:")
      var printed = 0
      while true {
        for (i, item) in items.enumerated() where i >= printed {
          print("  [\(i + 1)] \(item.line)")
        }
        printed = items.count

        let moreHint = exhausted ? "" : ", 'm' for more"
        print("Select (1-\(items.count)\(moreHint)): ", terminator: "")
        guard let line = readLine() else {
          throw ValidationError("No input available (stdin closed).")
        }
        let input = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.lowercased() == "m" {
          if try await loadNextPage() == 0 { print("No more submissions.") }
          continue
        }
        guard let choice = Int(input), choice >= 1, choice <= items.count else {
          throw ValidationError("Invalid selection.")
        }
        return items[choice - 1].id
      }
    }

    struct Crashes: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "crashes",
        abstract: "Manage crash feedback from testers.",
        subcommands: [List.self, Info.self, Log.self, Delete.self]
      )

      struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "List crash feedback submissions."
        )

        @Argument(help: "The bundle identifier of the app.",
                  completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
        var bundleID: String

        @OptionGroup var buildFilter: FeedbackBuildFilter

        @Option(name: .long, help: "Maximum number of submissions to show (default 50).")
        var limit: Int = 50

        func run() async throws {
          let client = try ClientFactory.makeClient()
          let app = try await findApp(bundleID: bundleID, client: client)
          let buildIDs = try await buildFilter.resolveBuildIDs(appID: app.id, client: client)

          let submissions = try await BetaFeedback.page(
            .crash, appID: app.id, platform: try buildFilter.platformOption.parsed(), buildIDs: buildIDs, limit: limit,
            client: client
          ).submissions

          if submissions.isEmpty {
            print("No crash feedback found.")
            return
          }

          let rows = submissions.map { submission in
            [
              submission.createdDate.map { formatDate($0) } ?? "—",
              submission.buildNumber ?? "—",
              submission.deviceModel ?? "—",
              submission.osVersion ?? "—",
              (submission.comment ?? "—").replacingOccurrences(of: "\n", with: " ").truncated(40),
              submission.id,
            ]
          }
          Table.print(
            headers: ["Received", "Build", "Device", "OS", "Comment", "Submission ID"],
            rows: rows)
        }
      }

      struct Info: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Show full details for a crash feedback submission."
        )

        @Argument(help: "The submission ID (from `feedback crashes list`).")
        var submissionID: String

        func run() async throws {
          let client = try ClientFactory.makeClient()
          print(Feedback.deviceDetailsText(try await BetaFeedback.submission(.crash, id: submissionID, client: client)))
          print()
          print("Fetch the crash log with: ascelerate testflight feedback crashes log \(submissionID)")
        }
      }

      struct Log: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Print or save a crash feedback submission's crash log."
        )

        @Argument(help: "The submission ID (from `feedback crashes list`).")
        var submissionID: String

        @Option(name: .long, help: "Write the log to a file instead of printing it.",
                completion: .file())
        var output: String?

        func run() async throws {
          let client = try ClientFactory.makeClient()
          guard let logText = try await BetaFeedback.crashLog(submissionID: submissionID, client: client) else {
            print("No crash log available for this submission.")
            return
          }
          if let output {
            let path = expandPath(confirmOutputPath(output, isDirectory: false))
            try logText.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            print(green("Saved") + " crash log to \(path)")
          } else {
            print(logText)
          }
        }
      }

      struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Delete a crash feedback submission."
        )

        @Argument(help: "The submission ID (from `feedback crashes list`).")
        var submissionID: String

        @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          guard confirm("Delete this crash feedback submission? [y/N] ") else {
            cancelled()
            return
          }
          let client = try ClientFactory.makeClient()
          try await BetaFeedback.delete(.crash, id: submissionID, client: client)
          print()
          success("Deleted", "crash feedback \(submissionID).")
        }
      }
    }

    struct Screenshots: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "screenshots",
        abstract: "Manage screenshot feedback from testers.",
        subcommands: [List.self, Info.self, Download.self, Delete.self]
      )

      struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "List screenshot feedback submissions."
        )

        @Argument(help: "The bundle identifier of the app.",
                  completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
        var bundleID: String

        @OptionGroup var buildFilter: FeedbackBuildFilter

        @Option(name: .long, help: "Maximum number of submissions to show (default 50).")
        var limit: Int = 50

        func run() async throws {
          let client = try ClientFactory.makeClient()
          let app = try await findApp(bundleID: bundleID, client: client)
          let buildIDs = try await buildFilter.resolveBuildIDs(appID: app.id, client: client)

          let submissions = try await BetaFeedback.page(
            .screenshot, appID: app.id, platform: try buildFilter.platformOption.parsed(), buildIDs: buildIDs,
            limit: limit, client: client
          ).submissions

          if submissions.isEmpty {
            print("No screenshot feedback found.")
            return
          }

          let rows = submissions.map { submission in
            [
              submission.createdDate.map { formatDate($0) } ?? "—",
              submission.buildNumber ?? "—",
              submission.deviceModel ?? "—",
              submission.osVersion ?? "—",
              "\(submission.images.count)",
              (submission.comment ?? "—").replacingOccurrences(of: "\n", with: " ").truncated(40),
              submission.id,
            ]
          }
          Table.print(
            headers: ["Received", "Build", "Device", "OS", "Images", "Comment", "Submission ID"],
            rows: rows)
        }
      }

      struct Info: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Show full details for a screenshot feedback submission."
        )

        @Argument(help: "The submission ID (from `feedback screenshots list`).")
        var submissionID: String

        func run() async throws {
          let client = try ClientFactory.makeClient()
          let submission = try await BetaFeedback.submission(.screenshot, id: submissionID, client: client)
          print(Feedback.deviceDetailsText(submission))
          let screenshots = submission.images
          if !screenshots.isEmpty {
            print()
            print("Screenshots (\(screenshots.count)):")
            for (i, shot) in screenshots.enumerated() {
              let size = [shot.width, shot.height].compactMap { $0.map(String.init) }.joined(separator: "×")
              print("  [\(i + 1)] \(size.isEmpty ? "?" : size), expires \(shot.expirationDate.map { formatDate($0) } ?? "?")")
            }
            print()
            print("Download with: ascelerate testflight feedback screenshots download <bundle-id> \(submissionID)")
          }
        }
      }

      struct Download: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Download a submission's screenshots and comment as a zip archive."
        )

        @Argument(help: "The bundle identifier of the app.",
                  completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
        var bundleID: String

        @Argument(help: "The submission ID (interactive picker if omitted).")
        var submissionID: String?

        @Option(name: .long, help: "Output zip file path (default: feedback-<submission-id>.zip).",
                completion: .file(extensions: ["zip"]))
        var output: String?

        func run() async throws {
          let client = try ClientFactory.makeClient()
          let app = try await findApp(bundleID: bundleID, client: client)
          let id: String
          if let submissionID {
            id = submissionID
          } else {
            id = try await Feedback.pickScreenshotSubmission(appID: app.id, client: client)
          }

          let submission = try await BetaFeedback.submission(.screenshot, id: id, client: client)
          let screenshots = submission.images
          let hasComment = !(submission.comment ?? "").isEmpty
          guard !screenshots.isEmpty || hasComment else {
            print("This submission has no screenshots and no comment.")
            return
          }

          let fm = FileManager.default
          let stagingDir = fm.temporaryDirectory
            .appendingPathComponent("ascelerate-feedback-\(UUID().uuidString)")
          try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
          defer { try? fm.removeItem(at: stagingDir) }

          var files: [URL] = []

          let detailsFile = stagingDir.appendingPathComponent("feedback.txt")
          let details = "Submission:   \(id)\n" + Feedback.deviceDetailsText(submission) + "\n"
          try details.write(to: detailsFile, atomically: true, encoding: .utf8)
          files.append(detailsFile)

          for (i, shot) in screenshots.enumerated() {
            guard let urlString = shot.url, let url = URL(string: urlString) else {
              print("  Screenshot \(i + 1): \(red("no URL")) — the download link may have expired.")
              continue
            }
            // Presigned CDN URL — plain URLSession, no App Store Connect auth.
            let (data, _) = try await URLSession.shared.data(from: url)
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
            let file = stagingDir.appendingPathComponent("screenshot-\(i + 1).\(ext)")
            try data.write(to: file)
            files.append(file)
          }

          let zipPath = expandPath(
            confirmOutputPath(output ?? "feedback-\(id).zip", isDirectory: false))
          // `zip` appends into an existing archive, so clear any previous file first.
          if fm.fileExists(atPath: zipPath) { try fm.removeItem(atPath: zipPath) }

          let zip = Process()
          zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
          zip.arguments = ["-j", "-q", zipPath] + files.map(\.path)
          try zip.run()
          zip.waitUntilExit()
          guard zip.terminationStatus == 0 else {
            throw ValidationError("zip failed with exit code \(zip.terminationStatus).")
          }

          print()
          success("Downloaded", "\(files.count - 1) screenshot(s) + comment to \(zipPath)")
        }
      }

      struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Delete a screenshot feedback submission."
        )

        @Argument(help: "The submission ID (from `feedback screenshots list`).")
        var submissionID: String

        @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          guard confirm("Delete this screenshot feedback submission? [y/N] ") else {
            cancelled()
            return
          }
          let client = try ClientFactory.makeClient()
          try await BetaFeedback.delete(.screenshot, id: submissionID, client: client)
          print()
          success("Deleted", "screenshot feedback \(submissionID).")
        }
      }
    }
  }

  /// Shared `--build`/`--platform` filter for feedback list commands. `--build`
  /// resolves to a build ID for the API's filterBuild (with `--platform`
  /// disambiguating shared build numbers); `--platform` alone filters by app platform.
  struct FeedbackBuildFilter: ParsableArguments {
    @Option(name: .long, help: "Only feedback for this build number.")
    var build: String?

    @OptionGroup var platformOption: PlatformOption

    func resolveBuildIDs(appID: String, client: ASCClient) async throws -> [String]? {
      guard let build else { return nil }
      let resolved = try await TestFlightCommand.findBuild(
        appID: appID, buildVersion: build, platform: try platformOption.parsed(), client: client)
      return [resolved.id]
    }
  }
}

private extension String {
  func truncated(_ maxLength: Int) -> String {
    count > maxLength ? "\(prefix(maxLength))…" : self
  }
}

