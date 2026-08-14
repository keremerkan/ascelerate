import AppStoreAPI
import AppStoreConnect
import ArgumentParser
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

  /// A build paired with its pre-release train description (e.g. "iOS 5.3").
  struct ResolvedBuild {
    let build: Build
    let platform: String?  // raw API value, e.g. "IOS"
    let version: String?   // train version, e.g. "5.0"

    var train: String {
      "\(platform.map { formatState($0) } ?? "?") \(version ?? "?")"
    }

    var label: String {
      "\(train) (\(build.attributes?.version ?? "?"))"
    }
  }

  /// Resolves a beta group by name (case-insensitive), or prompts with a picker when omitted.
  static func findBetaGroup(
    name: String?, appID: String, client: AppStoreConnectClient
  ) async throws -> BetaGroup {
    let groups = try await fetchAll(
      client.pages(Resources.v1.betaGroups.get(filterApp: [appID], sort: [.name], limit: 200)),
      data: { $0.data },
      emptyMessage: "No beta groups found for this app.")
    if let name {
      if let match = groups.first(where: {
        $0.attributes?.name?.lowercased() == name.lowercased()
      }) {
        return match
      }
      let available = groups.compactMap { $0.attributes?.name }.joined(separator: ", ")
      throw ValidationError("No beta group named '\(name)'. Available: \(available)")
    }
    return try promptSelection(
      "Select a beta group", items: groups, display: describeGroup,
      nonInteractiveHint: "Pass the group name to disambiguate.")
  }

  static func describeGroup(_ group: BetaGroup) -> String {
    let a = group.attributes
    var traits = [a?.isInternalGroup == true ? "Internal" : "External"]
    if a?.isPublicLinkEnabled == true { traits.append("public link") }
    return "\(a?.name ?? "?") (\(traits.joined(separator: ", ")))"
  }

  /// Resolves a build by number, or the latest non-expired build when omitted.
  /// A universal-purchase app can share build numbers across platforms, so an
  /// ambiguous match prompts (or `--platform` disambiguates).
  static func findBuild(
    appID: String, buildVersion: String?, platform: Platform?, client: AppStoreConnectClient
  ) async throws -> ResolvedBuild {
    let response = try await client.send(
      Resources.v1.builds.get(
        filterVersion: buildVersion.map { [$0] },
        // Only skip expired builds when defaulting to the latest — an explicit
        // build number should still resolve after expiry (e.g. for status).
        filterExpired: buildVersion == nil ? ["false"] : nil,
        filterPreReleaseVersionPlatform: platformFilter(platform),
        filterApp: [appID],
        sort: [.minusUploadedDate],
        limit: 10,
        include: [.preReleaseVersion]
      ))

    var trains: [String: (platform: String?, version: String?)] = [:]
    for item in response.included ?? [] {
      if case .prereleaseVersion(let v) = item {
        trains[v.id] = (v.attributes?.platform?.rawValue, v.attributes?.version)
      }
    }
    func resolved(_ build: Build) -> ResolvedBuild {
      let train = build.relationships?.preReleaseVersion?.data.flatMap { trains[$0.id] }
      return ResolvedBuild(build: build, platform: train?.platform, version: train?.version)
    }

    let builds = response.data
    guard !builds.isEmpty else {
      if let buildVersion {
        throw ValidationError("No build '\(buildVersion)' found for this app.")
      }
      throw ValidationError("No builds found for this app. Upload a build first.")
    }

    // An explicit build number can match one build per platform.
    if buildVersion != nil, builds.count > 1 {
      let pick = try promptSelection(
        "Multiple builds numbered \(buildVersion ?? "?") found", items: builds,
        display: { b in
          let r = resolved(b)
          let uploaded = b.attributes?.uploadedDate.map { formatDate($0) } ?? "?"
          return "\(r.label) — uploaded \(uploaded)"
        },
        nonInteractiveHint: "Pass --platform to disambiguate.")
      return resolved(pick)
    }
    return resolved(builds[0])
  }

  /// Shared `--build` / `--platform` options for build-scoped TestFlight commands.
  struct BuildOptions: ParsableArguments {
    @Option(name: .long, help: "Build number. Defaults to the latest non-expired build.")
    var build: String?

    @OptionGroup var platformOption: PlatformOption

    func resolve(appID: String, client: AppStoreConnectClient) async throws -> ResolvedBuild {
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

        var groups: [BetaGroup] = []
        for try await page in client.pages(
          Resources.v1.betaGroups.get(filterApp: [app.id], sort: [.name], limit: 200)
        ) {
          groups.append(contentsOf: page.data)
        }

        if groups.isEmpty {
          print("No beta groups found.")
          return
        }

        var rows: [[String]] = []
        for group in groups {
          let a = group.attributes
          let link = a?.isPublicLinkEnabled == true ? (a?.publicLink ?? "—") : "—"
          let limit = a?.isPublicLinkLimitEnabled == true
            ? a?.publicLinkLimit.map(String.init) ?? "—" : "—"
          rows.append([
            a?.name ?? "—",
            a?.isInternalGroup == true ? "Internal" : "External",
            link,
            limit,
            a?.isFeedbackEnabled == true ? "Yes" : "No",
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
        print("Feedback:      \(a?.isFeedbackEnabled == true ? "Enabled" : "Disabled")")
        if a?.isPublicLinkEnabled == true {
          print("Public Link:   \(a?.publicLink ?? "—")")
          if a?.isPublicLinkLimitEnabled == true {
            print("Link Limit:    \(a?.publicLinkLimit.map(String.init) ?? "—")")
          }
        } else {
          print("Public Link:   Disabled")
        }
        print("Created:       \(a?.createdDate.map { formatDate($0) } ?? "—")")
        print("Group ID:      \(betaGroup.id)")

        var testers: [BetaTester] = []
        for try await page in client.pages(
          Resources.v1.betaTesters.get(
            filterBetaGroups: [betaGroup.id], sort: [.email], limit: 200)
        ) {
          testers.append(contentsOf: page.data)
        }
        print()
        if testers.isEmpty {
          print("No testers in this group.")
        } else {
          print("Testers (\(testers.count)):")
          var rows: [[String]] = []
          for tester in testers {
            let ta = tester.attributes
            let name = [ta?.firstName, ta?.lastName].compactMap { $0 }.joined(separator: " ")
            rows.append([
              ta?.email ?? "—",
              name.isEmpty ? "—" : name,
              ta?.state.map { formatState($0) } ?? "—",
            ])
          }
          Table.print(headers: ["Email", "Name", "State"], rows: rows)
        }

        // Internal groups with access to all builds have no explicit build list.
        guard a?.hasAccessToAllBuilds != true else { return }

        let builds = try await client.send(
          Resources.v1.builds.get(
            filterApp: [app.id],
            filterBetaGroups: [betaGroup.id],
            sort: [.minusUploadedDate],
            limit: 50,
            include: [.preReleaseVersion]
          ))
        var trains: [String: String] = [:]
        for item in builds.included ?? [] {
          if case .prereleaseVersion(let v) = item {
            let p = v.attributes?.platform.map { formatState($0) } ?? "?"
            trains[v.id] = "\(p) \(v.attributes?.version ?? "?")"
          }
        }
        print()
        if builds.data.isEmpty {
          print("No builds assigned to this group.")
        } else {
          print("Builds (\(builds.data.count)):")
          var rows: [[String]] = []
          for build in builds.data {
            let ba = build.attributes
            let train = build.relationships?.preReleaseVersion?.data.flatMap { trains[$0.id] } ?? "—"
            rows.append([
              ba?.version ?? "—",
              train,
              ba?.uploadedDate.map { formatDate($0) } ?? "—",
              ba?.isExpired == true ? red("Expired") : ba?.expirationDate.map { formatDate($0) } ?? "—",
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

        let response = try await client.send(
          Resources.v1.betaGroups.post(
            BetaGroupCreateRequest(
              data: .init(
                attributes: .init(
                  name: name,
                  isInternalGroup: `internal` ? true : nil,
                  hasAccessToAllBuilds: allBuilds ? true : nil,
                  isPublicLinkEnabled: linkEnabled ? true : nil,
                  isPublicLinkLimitEnabled: publicLinkLimit != nil ? true : nil,
                  publicLinkLimit: publicLinkLimit,
                  isFeedbackEnabled: feedback
                ),
                relationships: .init(app: .init(data: .init(id: app.id)))
              )
            )
          ))

        print()
        success("Created", "beta group '\(name)'.")
        if let link = response.data.attributes?.publicLink {
          print("  Public link: \(link)")
        }
      }
    }

    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Update a beta group's name, public link, or feedback settings."
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

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        guard name != nil || publicLink != nil || publicLinkLimit != nil || feedback != nil else {
          throw ValidationError(
            "No updates specified. Use --name, --public-link, --public-link-limit, or --feedback.")
        }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let betaGroup = try await TestFlightCommand.findBetaGroup(
          name: group, appID: app.id, client: client)
        let groupName = betaGroup.attributes?.name ?? "?"

        let limitEnabled: Bool? = publicLinkLimit.map { $0 > 0 }
        var changes: [String] = []
        if let v = name { changes.append("Name: \(v)") }
        if let v = publicLink { changes.append("Public Link: \(v ? "Enabled" : "Disabled")") }
        if let v = publicLinkLimit {
          changes.append(v > 0 ? "Link Limit: \(v)" : "Link Limit: removed")
        }
        if let v = feedback { changes.append("Feedback: \(v ? "Enabled" : "Disabled")") }
        print("Updates for group '\(groupName)':")
        for c in changes { print("  \(c)") }
        print()

        guard confirm("Apply updates? [y/N] ") else {
          cancelled()
          return
        }

        _ = try await client.send(
          Resources.v1.betaGroups.id(betaGroup.id).patch(
            BetaGroupUpdateRequest(
              data: .init(
                id: betaGroup.id,
                attributes: .init(
                  name: name,
                  isPublicLinkEnabled: publicLink,
                  isPublicLinkLimitEnabled: limitEnabled,
                  publicLinkLimit: (publicLinkLimit ?? 0) > 0 ? publicLinkLimit : nil,
                  isFeedbackEnabled: feedback
                )
              )
            )
          ))

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

        _ = try await client.send(Resources.v1.betaGroups.id(betaGroup.id).delete)
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

        try await client.send(
          Resources.v1.betaGroups.id(betaGroup.id).relationships.builds.post(
            BetaGroupBuildsLinkagesRequest(data: [.init(id: resolved.build.id)])
          ))
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

        try await client.send(
          Resources.v1.betaGroups.id(betaGroup.id).relationships.builds.delete(
            BetaGroupBuildsLinkagesRequest(data: [.init(id: resolved.build.id)])
          ))
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

      /// Fetches a group's recruitment criterion, mapping "none exists" to nil.
      /// The API answers a criteria-less group with HTTP 409 ("BetaRecruitmentCriteria
      /// with id '…' does not exist") rather than 404 or a null data payload.
      static func fetch(
        groupID: String, client: AppStoreConnectClient
      ) async throws -> BetaRecruitmentCriterion? {
        do {
          return try await client.send(
            Resources.v1.betaGroups.id(groupID).betaRecruitmentCriteria.get()
          ).data
        } catch is DecodingError {
          return nil
        } catch let error as ResponseError {
          if case .requestFailure(_, let status, _) = error, status == 404 || status == 409 {
            return nil
          }
          throw error
        }
      }

      static func printFilters(_ criterion: BetaRecruitmentCriterion) {
        // The API returns unbounded limits as empty strings, not nil.
        func bound(_ value: String?) -> String {
          value.flatMap { $0.isEmpty ? nil : $0 } ?? "any"
        }
        for filter in criterion.attributes?.deviceFamilyOsVersionFilters ?? [] {
          let family = filter.deviceFamily.map { formatState($0) } ?? "?"
          print("  \(family): \(bound(filter.minimumOsInclusive)) – \(bound(filter.maximumOsInclusive))")
        }
      }

      /// Parses a `FAMILY[:MIN[:MAX]]` filter spec (e.g. `IPHONE:18.0` or `IPAD:17.0:18.5`).
      static func parseFilterSpec(_ spec: String) throws -> DeviceFamilyOsVersionFilter {
        let parts = spec.split(separator: ":", omittingEmptySubsequences: false)
          .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count <= 3 else {
          throw ValidationError("Invalid filter '\(spec)'. Use FAMILY[:MIN[:MAX]], e.g. IPHONE:18.0.")
        }
        let family: DeviceFamily = try parseEnum(parts[0], name: "device family")
        let min = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
        let max = parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil
        return DeviceFamilyOsVersionFilter(
          deviceFamily: family, minimumOsInclusive: min, maximumOsInclusive: max)
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

          if let criterion = try await Criteria.fetch(groupID: betaGroup.id, client: client) {
            print("Recruitment criteria for '\(betaGroup.attributes?.name ?? "?")':")
            Criteria.printFilters(criterion)
          } else {
            print("No recruitment criteria set for '\(betaGroup.attributes?.name ?? "?")'.")
          }

          if options {
            let opts = try await client.send(
              Resources.v1.betaRecruitmentCriterionOptions.get(limit: 200))
            print()
            print("Available criteria options:")
            for option in opts.data {
              for entry in option.attributes?.deviceFamilyOsVersions ?? [] {
                let family = entry.deviceFamily.map { formatState($0) } ?? "?"
                print("  \(family): \(entry.osVersions?.joined(separator: ", ") ?? "—")")
              }
            }
          }
        }
      }

      struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Set recruitment criteria, replacing any existing filters.",
          discussion: """
            Each --filter takes FAMILY[:MIN[:MAX]] with inclusive OS bounds, e.g.
            --filter IPHONE:18.0 --filter IPAD:17.0:18.5. Valid families: IPHONE, IPAD,
            MAC, APPLE_TV, APPLE_WATCH, VISION. Use `criteria view --options` to see
            selectable OS versions. Criteria apply to groups with a public link enabled.
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

          print("Recruitment criteria for '\(groupName)':")
          for f in filters {
            let family = f.deviceFamily.map { formatState($0) } ?? "?"
            print("  \(family): \(f.minimumOsInclusive ?? "any") – \(f.maximumOsInclusive ?? "any")")
          }
          print()
          guard confirm("Apply these criteria? [y/N] ") else {
            cancelled()
            return
          }

          if let existing = try await Criteria.fetch(groupID: betaGroup.id, client: client) {
            _ = try await client.send(
              Resources.v1.betaRecruitmentCriteria.id(existing.id).patch(
                BetaRecruitmentCriterionUpdateRequest(
                  data: .init(
                    id: existing.id,
                    attributes: .init(deviceFamilyOsVersionFilters: filters)
                  )
                )))
          } else {
            _ = try await client.send(
              Resources.v1.betaRecruitmentCriteria.post(
                BetaRecruitmentCriterionCreateRequest(
                  data: .init(
                    attributes: .init(deviceFamilyOsVersionFilters: filters),
                    relationships: .init(betaGroup: .init(data: .init(id: betaGroup.id)))
                  )
                )))
          }

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

          guard let existing = try await Criteria.fetch(groupID: betaGroup.id, client: client) else {
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

          _ = try await client.send(Resources.v1.betaRecruitmentCriteria.id(existing.id).delete)
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
      email: String, appID: String, client: AppStoreConnectClient
    ) async throws -> BetaTester {
      let response = try await client.send(
        Resources.v1.betaTesters.get(filterEmail: [email], filterApps: [appID]))
      guard let tester = response.data.first(where: {
        $0.attributes?.email?.lowercased() == email.lowercased()
      }) else {
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

        var groupFilter: [String]?
        var appsFilter: [String]? = [app.id]
        if let group {
          let betaGroup = try await TestFlightCommand.findBetaGroup(
            name: group, appID: app.id, client: client)
          groupFilter = [betaGroup.id]
          // filterApps and filterBetaGroups are mutually exclusive on this endpoint;
          // the group already scopes to the app.
          appsFilter = nil
        }

        var testers: [BetaTester] = []
        for try await page in client.pages(
          Resources.v1.betaTesters.get(
            filterEmail: email.map { [$0] },
            filterApps: appsFilter,
            filterBetaGroups: groupFilter,
            sort: [.email],
            limit: 200)
        ) {
          testers.append(contentsOf: page.data)
        }

        if testers.isEmpty {
          print("No beta testers found.")
          return
        }

        var rows: [[String]] = []
        for tester in testers {
          let a = tester.attributes
          let name = [a?.firstName, a?.lastName].compactMap { $0 }.joined(separator: " ")
          rows.append([
            a?.email ?? "—",
            name.isEmpty ? "—" : name,
            a?.state.map { formatState($0) } ?? "—",
            a?.inviteType.map { formatState($0) } ?? "—",
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

        var groups: [BetaGroup] = []
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

        _ = try await client.send(
          Resources.v1.betaTesters.post(
            BetaTesterCreateRequest(
              data: .init(
                attributes: .init(firstName: firstName, lastName: lastName, email: email),
                relationships: .init(
                  betaGroups: .init(data: groups.map { .init(id: $0.id) })
                )
              )
            )
          ))

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
          try await client.send(
            Resources.v1.betaGroups.id(betaGroup.id).relationships.betaTesters.delete(
              BetaGroupBetaTestersLinkagesRequest(data: [.init(id: tester.id)])
            ))
          print()
          success("Removed", "tester '\(email)' from group '\(groupName)'.")
        } else {
          guard confirm(
            "Remove '\(email)' from ALL groups and builds of this app? [y/N] ") else {
            cancelled()
            return
          }
          try await client.send(
            Resources.v1.betaTesters.id(tester.id).relationships.apps.delete(
              BetaTesterAppsLinkagesRequest(data: [.init(id: app.id)])
            ))
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

        let state = tester.attributes?.state.map { formatState($0) } ?? "?"
        print("Tester: \(email) (\(state))")
        print()
        guard confirm("Re-send the invitation email? [y/N] ") else {
          cancelled()
          return
        }

        _ = try await client.send(
          Resources.v1.betaTesterInvitations.post(
            BetaTesterInvitationCreateRequest(
              data: .init(
                relationships: .init(
                  betaTester: .init(data: .init(id: tester.id)),
                  app: .init(data: .init(id: app.id))
                )
              )
            )
          ))
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

        var groups: [BetaGroup] = []
        for name in group.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
          groups.append(
            try await TestFlightCommand.findBetaGroup(name: name, appID: app.id, client: client))
        }
        let groupNames = groups.compactMap { $0.attributes?.name }.joined(separator: ", ")

        let filePath = try resolveFile(file, extension: "csv", prompt: "Select a CSV file")
        let content = try String(contentsOf: URL(fileURLWithPath: filePath), encoding: .utf8)

        var testers: [(email: String, firstName: String?, lastName: String?)] = []
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
          let trimmed = line.trimmingCharacters(in: .whitespaces)
          if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
          let fields = trimmed.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
          guard fields[0].contains("@") else { continue }  // skips a header row
          testers.append((
            email: fields[0],
            firstName: fields.count > 1 && !fields[1].isEmpty ? fields[1] : nil,
            lastName: fields.count > 2 && !fields[2].isEmpty ? fields[2] : nil
          ))
        }

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
            _ = try await client.send(
              Resources.v1.betaTesters.post(
                BetaTesterCreateRequest(
                  data: .init(
                    attributes: .init(firstName: t.firstName, lastName: t.lastName, email: t.email),
                    relationships: .init(
                      betaGroups: .init(data: groups.map { .init(id: $0.id) })
                    )
                  )
                )
              ))
            print("  \(t.email) \(green("Added."))")
          } catch {
            failed.append(t.email)
            print("  \(t.email) \(red("Failed:")) \(error.localizedDescription)")
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

      let response = try await client.send(
        Resources.v1.builds.get(
          filterPreReleaseVersionPlatform: platformFilter(try platformOption.parsed()),
          filterApp: [app.id],
          sort: [.minusUploadedDate],
          limit: min(limit, 200),
          include: [.preReleaseVersion, .buildBetaDetail]
        ))

      var trains: [String: (platform: String?, version: String?)] = [:]
      var details: [String: BuildBetaDetail] = [:]
      for item in response.included ?? [] {
        switch item {
          case .prereleaseVersion(let v):
            trains[v.id] = (v.attributes?.platform?.rawValue, v.attributes?.version)
          case .buildBetaDetail(let d):
            details[d.id] = d
          default:
            break
        }
      }

      let entries = response.data.map { build -> Entry in
        let a = build.attributes
        let train = build.relationships?.preReleaseVersion?.data.flatMap { trains[$0.id] }
        let detail = build.relationships?.buildBetaDetail?.data.flatMap { details[$0.id] }
        return Entry(
          id: build.id,
          buildNumber: a?.version,
          version: train?.version,
          platform: train?.platform,
          uploadedDate: a?.uploadedDate,
          expirationDate: a?.expirationDate,
          isExpired: a?.isExpired,
          processingState: a?.processingState?.rawValue,
          internalBuildState: detail?.attributes?.internalBuildState?.rawValue,
          externalBuildState: detail?.attributes?.externalBuildState?.rawValue
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

      let response = try await client.send(
        Resources.v1.preReleaseVersions.get(
          filterPlatform: platformFilter(try platformOption.parsed()),
          filterApp: [app.id],
          sort: [.minusVersion],
          limit: min(limit, 200)
        ))

      if response.data.isEmpty {
        print("No pre-release versions found.")
        return
      }

      var rows: [[String]] = []
      for version in response.data {
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

      if resolved.build.attributes?.isExpired == true {
        print("Build \(resolved.label) is already expired.")
        return
      }

      print("Build: \(resolved.label), uploaded \(resolved.build.attributes?.uploadedDate.map { formatDate($0) } ?? "?")")
      print()
      guard confirm("Expire this build? Testers can no longer install it. [y/N] ") else {
        cancelled()
        return
      }

      _ = try await client.send(
        Resources.v1.builds.id(resolved.build.id).patch(
          BuildUpdateRequest(
            data: .init(id: resolved.build.id, attributes: .init(isExpired: true))
          )
        ))
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

      _ = try await client.send(
        Resources.v1.buildBetaNotifications.post(
          BuildBetaNotificationCreateRequest(
            data: .init(relationships: .init(build: .init(data: .init(id: resolved.build.id))))
          )
        ))
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

      guard let detail = try await client.send(
        Resources.v1.buildBetaDetails.get(filterBuild: [resolved.build.id])
      ).data.first else {
        throw ValidationError("No build beta detail found for build \(resolved.label).")
      }

      if detail.attributes?.isAutoNotifyEnabled == enabled {
        print("Auto-notify is already \(enabled ? "enabled" : "disabled") for build \(resolved.label).")
        return
      }

      guard confirm("\(enabled ? "Enable" : "Disable") auto-notify for build \(resolved.label)? [y/N] ") else {
        cancelled()
        return
      }

      _ = try await client.send(
        Resources.v1.buildBetaDetails.id(detail.id).patch(
          BuildBetaDetailUpdateRequest(
            data: .init(id: detail.id, attributes: .init(isAutoNotifyEnabled: enabled))
          )
        ))
      print()
      success("Updated", "auto-notify \(enabled ? "enabled" : "disabled") for build \(resolved.label).")
    }
  }

  // MARK: - What to Test

  /// JSON schema for beta build localizations (What to Test).
  struct WhatsNewFields: Codable {
    var whatsNew: String?
  }

  struct WhatsNew: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "whats-new",
      abstract: "View, set, export, and import a build's test notes (What to Test).",
      subcommands: [View.self, Set.self, Export.self, Import.self]
    )

    /// Fetches a build's beta localizations keyed by locale.
    static func fetchLocalizations(
      buildID: String, client: AppStoreConnectClient
    ) async throws -> [BetaBuildLocalization] {
      try await client.send(
        Resources.v1.betaBuildLocalizations.get(filterBuild: [buildID], limit: 50)
      ).data.sorted { ($0.attributes?.locale ?? "") < ($1.attributes?.locale ?? "") }
    }

    /// Applies What to Test text per locale — patching existing localizations,
    /// creating missing ones.
    static func apply(
      updates: [(locale: String, text: String)],
      buildID: String,
      client: AppStoreConnectClient
    ) async throws {
      let existing = try await fetchLocalizations(buildID: buildID, client: client)
      let byLocale = Dictionary(
        existing.compactMap { loc in loc.attributes?.locale.map { ($0, loc) } },
        uniquingKeysWith: { first, _ in first })

      for (locale, text) in updates {
        if let loc = byLocale[locale] {
          _ = try await client.send(
            Resources.v1.betaBuildLocalizations.id(loc.id).patch(
              BetaBuildLocalizationUpdateRequest(
                data: .init(id: loc.id, attributes: .init(whatsNew: text))
              )
            ))
          print("  [\(localeName(locale))] Updated.")
        } else {
          _ = try await client.send(
            Resources.v1.betaBuildLocalizations.post(
              BetaBuildLocalizationCreateRequest(
                data: .init(
                  attributes: .init(whatsNew: text, locale: locale),
                  relationships: .init(build: .init(data: .init(id: buildID)))
                )
              )
            ))
          print("  [\(localeName(locale))] \(green("Created."))")
        }
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

        let locs = try await WhatsNew.fetchLocalizations(
          buildID: resolved.build.id, client: client)
        print("What to Test for build \(resolved.label):")
        print()
        if locs.isEmpty {
          print("No test notes set.")
          return
        }
        for loc in locs {
          print("[\(localeName(loc.attributes?.locale ?? "?"))]")
          let text = loc.attributes?.whatsNew ?? ""
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
          let existing = try await WhatsNew.fetchLocalizations(
            buildID: resolved.build.id, client: client)
          targets = existing.compactMap { $0.attributes?.locale }
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
          updates: targets.map { ($0, text) }, buildID: resolved.build.id, client: client)
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

        let locs = try await WhatsNew.fetchLocalizations(
          buildID: resolved.build.id, client: client)
        var result: [String: WhatsNewFields] = [:]
        for loc in locs {
          guard let locale = loc.attributes?.locale else { continue }
          result[locale] = WhatsNewFields(whatsNew: loc.attributes?.whatsNew)
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

        try await WhatsNew.apply(updates: updates, buildID: resolved.build.id, client: client)
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

      print("Build: \(resolved.label), uploaded \(resolved.build.attributes?.uploadedDate.map { formatDate($0) } ?? "?")")
      print()
      guard confirm("Submit this build for beta review? [y/N] ") else {
        cancelled()
        return
      }

      let response = try await client.send(
        Resources.v1.betaAppReviewSubmissions.post(
          BetaAppReviewSubmissionCreateRequest(
            data: .init(relationships: .init(build: .init(data: .init(id: resolved.build.id))))
          )
        ))

      print()
      success("Submitted", "build \(resolved.label) for beta review.")
      if let state = response.data.attributes?.betaReviewState {
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
      let a = resolved.build.attributes

      let detail = try await client.send(
        Resources.v1.buildBetaDetails.get(filterBuild: [resolved.build.id])
      ).data.first
      let submission = try await client.send(
        Resources.v1.betaAppReviewSubmissions.get(filterBuild: [resolved.build.id])
      ).data.first

      let d = detail?.attributes
      let status = Detail(
        id: resolved.build.id,
        buildNumber: a?.version,
        version: resolved.version,
        platform: resolved.platform,
        uploadedDate: a?.uploadedDate,
        expirationDate: a?.expirationDate,
        isExpired: a?.isExpired,
        processingState: a?.processingState?.rawValue,
        internalBuildState: d?.internalBuildState?.rawValue,
        externalBuildState: d?.externalBuildState?.rawValue,
        autoNotifyEnabled: d?.isAutoNotifyEnabled,
        betaReviewState: submission?.attributes?.betaReviewState?.rawValue
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

  /// JSON schema for TestFlight beta app localizations.
  struct BetaAppLocaleFields: Codable {
    var description: String?
    var feedbackEmail: String?
    var marketingURL: String?
    var privacyPolicyURL: String?
    var tvOsPrivacyPolicy: String?
  }

  struct AppInfo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "app-info",
      abstract: "View, update, export, and import TestFlight beta app information.",
      subcommands: [View.self, Update.self, Export.self, Import.self]
    )

    static func fetchLocalizations(
      appID: String, client: AppStoreConnectClient
    ) async throws -> [BetaAppLocalization] {
      try await client.send(
        Resources.v1.betaAppLocalizations.get(filterApp: [appID], limit: 50)
      ).data.sorted { ($0.attributes?.locale ?? "") < ($1.attributes?.locale ?? "") }
    }

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
        let locs = try await AppInfo.fetchLocalizations(appID: app.id, client: client)

        if locs.isEmpty {
          print("No beta app information found.")
          return
        }
        print("Beta app information for \(app.attributes?.name ?? bundleID):")
        print()
        for loc in locs {
          let a = loc.attributes
          print("[\(localeName(a?.locale ?? "?"))]")
          print("  Feedback Email:  \(a?.feedbackEmail ?? "—")")
          print("  Marketing URL:   \(a?.marketingURL ?? "—")")
          print("  Privacy Policy:  \(a?.privacyPolicyURL ?? "—")")
          if let tvOs = a?.tvOsPrivacyPolicy, !tvOs.isEmpty {
            print("  tvOS Privacy:    \(tvOs)")
          }
          if let desc = a?.description, !desc.isEmpty {
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
        let locs = try await AppInfo.fetchLocalizations(appID: app.id, client: client)

        let target: BetaAppLocalization?
        var targetLocale: String
        if let locale {
          target = locs.first { $0.attributes?.locale == locale }
          targetLocale = locale
        } else if locs.count == 1 {
          target = locs[0]
          targetLocale = locs[0].attributes?.locale ?? "?"
        } else {
          let pick = try promptSelection(
            "Select a locale", items: locs,
            display: { localeName($0.attributes?.locale ?? "?") },
            nonInteractiveHint: "Pass --locale to disambiguate.")
          target = pick
          targetLocale = pick.attributes?.locale ?? "?"
        }

        guard confirm("Update beta app information for \(localeName(targetLocale))? [y/N] ") else {
          cancelled()
          return
        }

        if let target {
          _ = try await client.send(
            Resources.v1.betaAppLocalizations.id(target.id).patch(
              BetaAppLocalizationUpdateRequest(
                data: .init(
                  id: target.id,
                  attributes: .init(
                    feedbackEmail: feedbackEmail, marketingURL: marketingURL,
                    privacyPolicyURL: privacyPolicyURL, description: description
                  )
                )
              )))
        } else {
          _ = try await client.send(
            Resources.v1.betaAppLocalizations.post(
              BetaAppLocalizationCreateRequest(
                data: .init(
                  attributes: .init(
                    feedbackEmail: feedbackEmail, marketingURL: marketingURL,
                    privacyPolicyURL: privacyPolicyURL, description: description,
                    locale: targetLocale
                  ),
                  relationships: .init(app: .init(data: .init(id: app.id)))
                )
              )))
        }

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
        let locs = try await AppInfo.fetchLocalizations(appID: app.id, client: client)

        var result: [String: BetaAppLocaleFields] = [:]
        for loc in locs {
          guard let locale = loc.attributes?.locale else { continue }
          let a = loc.attributes
          result[locale] = BetaAppLocaleFields(
            description: a?.description,
            feedbackEmail: a?.feedbackEmail,
            marketingURL: a?.marketingURL,
            privacyPolicyURL: a?.privacyPolicyURL,
            tvOsPrivacyPolicy: a?.tvOsPrivacyPolicy
          )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)

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

        let existing = try await AppInfo.fetchLocalizations(appID: app.id, client: client)
        let byLocale = Dictionary(
          existing.compactMap { loc in loc.attributes?.locale.map { ($0, loc) } },
          uniquingKeysWith: { first, _ in first })

        for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
          if let loc = byLocale[locale] {
            _ = try await client.send(
              Resources.v1.betaAppLocalizations.id(loc.id).patch(
                BetaAppLocalizationUpdateRequest(
                  data: .init(
                    id: loc.id,
                    attributes: .init(
                      feedbackEmail: fields.feedbackEmail, marketingURL: fields.marketingURL,
                      privacyPolicyURL: fields.privacyPolicyURL,
                      tvOsPrivacyPolicy: fields.tvOsPrivacyPolicy,
                      description: fields.description
                    )
                  )
                )))
            print("  [\(localeName(locale))] Updated.")
          } else {
            _ = try await client.send(
              Resources.v1.betaAppLocalizations.post(
                BetaAppLocalizationCreateRequest(
                  data: .init(
                    attributes: .init(
                      feedbackEmail: fields.feedbackEmail, marketingURL: fields.marketingURL,
                      privacyPolicyURL: fields.privacyPolicyURL,
                      tvOsPrivacyPolicy: fields.tvOsPrivacyPolicy,
                      description: fields.description,
                      locale: locale
                    ),
                    relationships: .init(app: .init(data: .init(id: app.id)))
                  )
                )))
            print("  [\(localeName(locale))] \(green("Created."))")
          }
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

      let detail = try await client.send(
        Resources.v1.betaAppReviewDetails.get(filterApp: [app.id])
      ).data.first

      let hasUpdates =
        contactFirstName != nil || contactLastName != nil || contactPhone != nil
        || contactEmail != nil || demoAccountName != nil || demoAccountPassword != nil
        || demoAccountRequired != nil || notes != nil

      if !hasUpdates {
        guard let detail, let a = detail.attributes else {
          print("No beta review information set.")
          return
        }
        let name = [a.contactFirstName, a.contactLastName].compactMap { $0 }.joined(separator: " ")
        print("Beta review information for \(app.attributes?.name ?? bundleID):")
        print("  Contact:       \(name.isEmpty ? "—" : name)")
        print("  Phone:         \(a.contactPhone ?? "—")")
        print("  Email:         \(a.contactEmail ?? "—")")
        print("  Demo Required: \(a.isDemoAccountRequired == true ? "Yes" : "No")")
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

      _ = try await client.send(
        Resources.v1.betaAppReviewDetails.id(detail.id).patch(
          BetaAppReviewDetailUpdateRequest(
            data: .init(
              id: detail.id,
              attributes: .init(
                contactFirstName: contactFirstName, contactLastName: contactLastName,
                contactPhone: contactPhone, contactEmail: contactEmail,
                demoAccountName: demoAccountName, demoAccountPassword: demoAccountPassword,
                isDemoAccountRequired: demoAccountRequired, notes: notes
              )
            )
          )))

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

      guard let agreement = try await client.send(
        Resources.v1.betaLicenseAgreements.get(filterApp: [app.id])
      ).data.first else {
        throw ValidationError("No beta license agreement record found for this app.")
      }

      var newText = text
      if let file {
        newText = try String(contentsOf: URL(fileURLWithPath: expandPath(file)), encoding: .utf8)
      }

      guard let newText else {
        let current = agreement.attributes?.agreementText ?? ""
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

      _ = try await client.send(
        Resources.v1.betaLicenseAgreements.id(agreement.id).patch(
          BetaLicenseAgreementUpdateRequest(
            data: .init(id: agreement.id, attributes: .init(agreementText: newText))
          )
        ))
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
    static func deviceDetailsText(
      createdDate: Date?, email: String?, comment: String?, deviceModel: String?,
      osVersion: String?, locale: String?, timeZone: String?, architecture: String?,
      connectionType: DeviceConnectionType?, batteryPercentage: Int?,
      diskBytesAvailable: Int64?, diskBytesTotal: Int64?,
      appUptimeInMilliseconds: Int64?, appPlatform: Platform?, buildBundleID: String?
    ) -> String {
      var lines: [String] = []
      lines.append("Received:     \(createdDate.map { formatDate($0) } ?? "—")")
      lines.append("Tester:       \(email ?? "—")")
      lines.append("Device:       \(deviceModel ?? "—")")
      lines.append("OS Version:   \(osVersion ?? "—")")
      lines.append("Platform:     \(appPlatform.map { formatState($0) } ?? "—")")
      lines.append("Locale:       \(locale.map { localeName($0) } ?? "—")")
      lines.append("Time Zone:    \(timeZone ?? "—")")
      lines.append("Architecture: \(architecture ?? "—")")
      lines.append("Connection:   \(connectionType.map { formatState($0) } ?? "—")")
      lines.append("Battery:      \(batteryPercentage.map { "\($0)%" } ?? "—")")
      if let available = diskBytesAvailable, let total = diskBytesTotal {
        lines.append("Disk Free:    \(formatBytes(Int(available))) of \(formatBytes(Int(total)))")
      }
      if let uptime = appUptimeInMilliseconds {
        lines.append("App Uptime:   \(uptime / 1000)s")
      }
      lines.append("Bundle ID:    \(buildBundleID ?? "—")")
      if let comment, !comment.isEmpty {
        lines.append("")
        lines.append("Comment:")
        lines.append(comment.split(separator: "\n", omittingEmptySubsequences: false)
          .map { "  \($0)" }.joined(separator: "\n"))
      }
      return lines.joined(separator: "\n")
    }

    /// Pages through an app's screenshot feedback and lets the user pick one.
    /// Loads more pages on demand ('m') so large feedback lists stay browsable.
    static func pickScreenshotSubmission(
      appID: String, client: AppStoreConnectClient
    ) async throws -> String {
      if autoConfirm {
        throw ValidationError(
          "Cannot pick a submission interactively with --yes. Pass the submission ID.")
      }

      var iterator = client.pages(
        Resources.v1.apps.id(appID).betaFeedbackScreenshotSubmissions.get(
          sort: [.minusCreatedDate], limit: 20, include: [.build])
      ).makeAsyncIterator()

      var items: [(id: String, line: String)] = []
      var exhausted = false

      func loadNextPage() async throws -> Int {
        guard !exhausted, let page = try await iterator.next() else {
          exhausted = true
          return 0
        }
        let numbers = buildNumbers(from: page.included)
        for submission in page.data {
          let a = submission.attributes
          let build = submission.relationships?.build?.data.flatMap { numbers[$0.id] } ?? "—"
          let comment = (a?.comment ?? "—").replacingOccurrences(of: "\n", with: " ").truncated(40)
          items.append((
            submission.id,
            "\(a?.createdDate.map { formatDate($0) } ?? "—")  build \(build)  \(a?.deviceModel ?? "—")  \(comment)"
          ))
        }
        return page.data.count
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

    /// Builds a build-ID → build-number map from a feedback response's included builds.
    static func buildNumbers(from included: [BetaFeedbackCrashSubmissionsResponse.IncludedItem]?) -> [String: String] {
      var numbers: [String: String] = [:]
      for item in included ?? [] {
        if case .build(let b) = item { numbers[b.id] = b.attributes?.version ?? "?" }
      }
      return numbers
    }

    static func buildNumbers(from included: [BetaFeedbackScreenshotSubmissionsResponse.IncludedItem]?) -> [String: String] {
      var numbers: [String: String] = [:]
      for item in included ?? [] {
        if case .build(let b) = item { numbers[b.id] = b.attributes?.version ?? "?" }
      }
      return numbers
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

          let response = try await client.send(
            Resources.v1.apps.id(app.id).betaFeedbackCrashSubmissions.get(
              filterAppPlatform: platformFilter(try buildFilter.platformOption.parsed()),
              filterBuild: buildIDs,
              sort: [.minusCreatedDate],
              limit: min(limit, 200),
              include: [.build]
            ))

          if response.data.isEmpty {
            print("No crash feedback found.")
            return
          }

          let numbers = Feedback.buildNumbers(from: response.included)
          var rows: [[String]] = []
          for submission in response.data {
            let a = submission.attributes
            let build = submission.relationships?.build?.data.flatMap { numbers[$0.id] } ?? "—"
            rows.append([
              a?.createdDate.map { formatDate($0) } ?? "—",
              build,
              a?.deviceModel ?? "—",
              a?.osVersion ?? "—",
              (a?.comment ?? "—").replacingOccurrences(of: "\n", with: " ").truncated(40),
              submission.id,
            ])
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
          let submission = try await client.send(
            Resources.v1.betaFeedbackCrashSubmissions.id(submissionID).get()
          ).data
          let a = submission.attributes
          print(Feedback.deviceDetailsText(
            createdDate: a?.createdDate, email: a?.email, comment: a?.comment,
            deviceModel: a?.deviceModel, osVersion: a?.osVersion, locale: a?.locale,
            timeZone: a?.timeZone, architecture: a?.architecture,
            connectionType: a?.connectionType, batteryPercentage: a?.batteryPercentage,
            diskBytesAvailable: a?.diskBytesAvailable, diskBytesTotal: a?.diskBytesTotal,
            appUptimeInMilliseconds: a?.appUptimeInMilliseconds, appPlatform: a?.appPlatform,
            buildBundleID: a?.buildBundleID))
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
          let response = try await client.send(
            Resources.v1.betaFeedbackCrashSubmissions.id(submissionID).crashLog.get())
          guard let logText = response.data.attributes?.logText, !logText.isEmpty else {
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
          _ = try await client.send(
            Resources.v1.betaFeedbackCrashSubmissions.id(submissionID).delete)
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

          let response = try await client.send(
            Resources.v1.apps.id(app.id).betaFeedbackScreenshotSubmissions.get(
              filterAppPlatform: platformFilter(try buildFilter.platformOption.parsed()),
              filterBuild: buildIDs,
              sort: [.minusCreatedDate],
              limit: min(limit, 200),
              include: [.build]
            ))

          if response.data.isEmpty {
            print("No screenshot feedback found.")
            return
          }

          let numbers = Feedback.buildNumbers(from: response.included)
          var rows: [[String]] = []
          for submission in response.data {
            let a = submission.attributes
            let build = submission.relationships?.build?.data.flatMap { numbers[$0.id] } ?? "—"
            rows.append([
              a?.createdDate.map { formatDate($0) } ?? "—",
              build,
              a?.deviceModel ?? "—",
              a?.osVersion ?? "—",
              "\(a?.screenshots?.count ?? 0)",
              (a?.comment ?? "—").replacingOccurrences(of: "\n", with: " ").truncated(40),
              submission.id,
            ])
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
          let submission = try await client.send(
            Resources.v1.betaFeedbackScreenshotSubmissions.id(submissionID).get()
          ).data
          let a = submission.attributes
          print(Feedback.deviceDetailsText(
            createdDate: a?.createdDate, email: a?.email, comment: a?.comment,
            deviceModel: a?.deviceModel, osVersion: a?.osVersion, locale: a?.locale,
            timeZone: a?.timeZone, architecture: a?.architecture,
            connectionType: a?.connectionType, batteryPercentage: a?.batteryPercentage,
            diskBytesAvailable: a?.diskBytesAvailable, diskBytesTotal: a?.diskBytesTotal,
            appUptimeInMilliseconds: a?.appUptimeInMilliseconds, appPlatform: a?.appPlatform,
            buildBundleID: a?.buildBundleID))
          if let screenshots = a?.screenshots, !screenshots.isEmpty {
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

          let submission = try await client.send(
            Resources.v1.betaFeedbackScreenshotSubmissions.id(id).get()
          ).data
          let a = submission.attributes
          let screenshots = a?.screenshots ?? []
          let hasComment = !(a?.comment ?? "").isEmpty
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
          let details = "Submission:   \(id)\n" + Feedback.deviceDetailsText(
            createdDate: a?.createdDate, email: a?.email, comment: a?.comment,
            deviceModel: a?.deviceModel, osVersion: a?.osVersion, locale: a?.locale,
            timeZone: a?.timeZone, architecture: a?.architecture,
            connectionType: a?.connectionType, batteryPercentage: a?.batteryPercentage,
            diskBytesAvailable: a?.diskBytesAvailable, diskBytesTotal: a?.diskBytesTotal,
            appUptimeInMilliseconds: a?.appUptimeInMilliseconds, appPlatform: a?.appPlatform,
            buildBundleID: a?.buildBundleID) + "\n"
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
          _ = try await client.send(
            Resources.v1.betaFeedbackScreenshotSubmissions.id(submissionID).delete)
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

    func resolveBuildIDs(appID: String, client: AppStoreConnectClient) async throws -> [String]? {
      guard let build else { return nil }
      let resolved = try await TestFlightCommand.findBuild(
        appID: appID, buildVersion: build, platform: try platformOption.parsed(), client: client)
      return [resolved.build.id]
    }
  }
}

private extension String {
  func truncated(_ maxLength: Int) -> String {
    count > maxLength ? "\(prefix(maxLength))…" : self
  }
}
