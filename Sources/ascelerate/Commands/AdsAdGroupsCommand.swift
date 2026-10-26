import AppleAdsClient
import AscelerateAds
import ArgumentParser
import AscelerateCore
import Foundation

extension AdsCommand {
  struct AdGroups: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "adgroups",
      abstract: "List, create and update ad groups.",
      subcommands: [List.self, Create.self, Update.self, Pause.self, Resume.self],
      defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "List the ad groups of campaigns.")

      @OptionGroup var scope: Ads.ScopeOptions
      @OptionGroup var jsonOption: JSONOption

      private struct Entry: Encodable {
        let id: Int64
        let name: String
        let campaignId: Int64
        let campaignName: String
        let status: String?
        let displayStatus: String?
        let defaultBid: Ads.Amount?
        /// The ad group's legacy cost-per-acquisition goal (`cpaCap`, deprecated by Apple).
        let cpaGoal: Ads.Amount?
        let searchMatch: Bool?
        let deviceClasses: [String]?
        let minAge: Int?
        let maxAge: Int?
      }

      func run() async throws {
        jsonOption.activate()
        let ads = try Ads.config()
        let scope = try await self.scope.resolve(ads)
        let entries = try await Ads.withClient(ads) { client in
          try await Ads.perCampaign(scope) { campaignID in
            try await Ads.adGroups(campaignID: campaignID, ads, client: client)
          }
        }.map { group in
          Entry(
            id: group.id ?? 0, name: group.name ?? "-", campaignId: group.campaignId ?? 0,
            campaignName: scope.campaignName(group.campaignId ?? 0), status: group.status?.value1.rawValue,
            displayStatus: group.displayStatus?.value1.rawValue,
            defaultBid: group.bidStrategy?.value1.bid.map(Ads.Amount.init),
            cpaGoal: group.cpaCap?.value1.value.map(Ads.Amount.init),
            searchMatch: group.automatedKeywordsOptIn,
            deviceClasses: group.targeting?.value1.deviceClass?.value1.include,
            minAge: group.targeting?.value1.minAge?.value1.include?.first.flatMap(Int.init),
            maxAge: group.targeting?.value1.maxAge?.value1.include?.first.flatMap(Int.init)
          )
        }

        if jsonOption.json { try printJSON(entries); return }
        Table.print(
          headers: ["ID", "Ad Group", "Campaign", "Status", "Default Bid", "CPA Goal", "Search Match", "Ages"],
          rows: entries.map { e in
            let status: String = e.displayStatus.map(Ads.formatStatus) ?? "-"
            let searchMatch: String = e.searchMatch.map { $0 ? "On" : "Off" } ?? "-"
            let ages: String = e.minAge == nil && e.maxAge == nil
              ? "All" : "\(e.minAge ?? 18)–\(e.maxAge.map(String.init) ?? "65+")"
            return [
              String(e.id), e.name, e.campaignName, status, e.defaultBid?.formatted ?? "-",
              e.cpaGoal?.formatted ?? "-", searchMatch, ages,
            ]
          }
        )
      }
    }

    /// The settings `create` and `update` can change.
    struct Settings: ParsableArguments {
      @Option(name: .long, help: "Default bid (max CPT) for keywords without their own bid.")
      var defaultBid: String?

      @Option(name: .long, help: "Search Match (Apple matches searches to the app itself): on or off.")
      var searchMatch: String?

      @Option(name: .long, help: "Legacy cost-per-acquisition goal (deprecated by Apple in favour of Max Conversions bidding).")
      var cpaGoal: String?

      func searchMatchValue() throws -> Bool? {
        switch searchMatch?.lowercased() {
        case nil: nil
        case "on": true
        case "off": false
        default: throw ValidationError("--search-match takes on or off.")
        }
      }

      /// "default bid 1.00 USD, Search Match off" for the confirmation prompt.
      func summary(currency: String) -> [String] {
        [
          defaultBid.map { "default bid \(Ads.number(Double($0) ?? 0, decimals: 2)) \(currency)" },
          searchMatch.map { "Search Match \($0.lowercased())" },
          cpaGoal.map { "CPA goal \(Ads.number(Double($0) ?? 0, decimals: 2)) \(currency)" },
        ].compactMap { $0 }
      }
    }

    struct Create: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Create an ad group as a copy of an existing one's settings and targeting (created paused)."
      )

      @Option(name: .long, help: "Campaign name or ID.")
      var campaign: String

      @Option(name: .long, help: "Name of the new ad group (default with --automated: Automated).")
      var name: String?

      @Flag(name: .long, help: "The automated ad group a Max Conversions campaign requires (Search Match, no keywords).")
      var automated = false

      @Option(name: .long, help: "Ad group to copy pricing, bidding, CPA goal and targeting from (default: the campaign's only one).")
      var like: String?

      @OptionGroup var settings: Settings

      @Option(name: .long, help: "Only users at least this old (18–64). Age targeting reaches only users who allowed Personalized Ads, and Apple doesn't attribute its installs (AdServices).")
      var minAge: Int?

      @Option(name: .long, help: "Only users at most this old (18–64); without it, no upper limit.")
      var maxAge: Int?

      @Flag(name: .long, help: "Start it right away instead of paused.")
      var enabled = false

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func validate() throws {
        if automated {
          guard like == nil, minAge == nil, maxAge == nil, settings.defaultBid == nil, settings.searchMatch == nil,
            settings.cpaGoal == nil
          else { throw ValidationError("--automated takes no other settings: Max Conversions sets them.") }
        } else if name == nil {
          throw ValidationError("Pass --name.")
        }
      }

      func run() async throws {
        if yes { autoConfirm = true }
        let ads = try Ads.config()
        if automated {
          try await Ads.withClient(ads) { client in
            let campaign = try await Ads.campaign(self.campaign, ads, client: client)
            guard Ads.isAutomaticBidding(campaign) else {
              throw ValidationError("\(campaign.name ?? "-") isn't a Max Conversions campaign.")
            }
            guard try await Ads.adGroups(campaignID: campaign.id ?? 0, ads, client: client).isEmpty else {
              throw ValidationError("\(campaign.name ?? "-") already has an ad group.")
            }
            guard confirm("Create the automated ad group of \(campaign.name ?? "-")? [y/N] ") else {
              print(yellow("Cancelled."))
              return
            }
            guard let created = try await unlessDryRunStopped({
              try await client.postAdgroups(
                headers: .init(xApContext: Ads.context(ads)), body: .json(Ads.automatedAdGroup(campaignID: campaign.id ?? 0))
              ).ok.body.json.result
            }) else { return }
            print(green("Created") + " ad group 'Automated' (ID \(created?.id.map(String.init) ?? "-")).")
          }
          return
        }
        let name = self.name ?? ""
        let searchMatch = try settings.searchMatchValue()
        for age in [minAge, maxAge].compactMap({ $0 }) where !(18...64).contains(age) {
          throw ValidationError("Ages must be 18 to 64 (Apple's limits); leave out --max-age for no upper limit.")
        }
        if let minAge, let maxAge, minAge > maxAge { throw ValidationError("--min-age is above --max-age.") }
        try await Ads.withClient(ads) { client in
          let campaign = try await Ads.campaign(self.campaign, ads, client: client)
          let campaignID = campaign.id ?? 0
          let currency = try Ads.currency(of: campaign)
          let groups = try await Ads.adGroups(campaignID: campaignID, ads, client: client)
          if groups.contains(where: { $0.name?.caseInsensitiveCompare(name) == .orderedSame }) {
            throw ValidationError("\(campaign.name ?? "-") already has an ad group named '\(name)'.")
          }
          let source = try Ads.adGroup(like, in: groups, option: "--like")
          guard let pricingModel = source.pricingModel?.value1 else {
            throw ValidationError("Can't read the pricing model of '\(source.name ?? "-")'.")
          }

          // Copied as JSON: the create types mirror the read types field for field.
          var bidStrategy = try source.bidStrategy.map { try Ads.convert($0.value1, to: Components.Schemas.BidStrategyCreate.self) }
          if let bid = settings.defaultBid { bidStrategy?.bid = try Ads.money(bid, currency: currency) }
          var cpaGoal = try source.cpaCap.map { try Ads.convert($0.value1, to: Components.Schemas.CPAGoalCreate.self) }
          if let goal = settings.cpaGoal { cpaGoal = .init(value: try Ads.money(goal, currency: currency)) }
          var targeting = try source.targeting.map { try Ads.convert($0.value1, to: Components.Schemas.AdGroupTargetingCreate.self) }
          if minAge != nil || maxAge != nil {
            var t = targeting ?? .init()
            if let minAge { t.minAge = .init(value1: .init(include: [String(minAge)])) }
            if let maxAge { t.maxAge = .init(value1: .init(include: [String(maxAge)])) }
            targeting = t
          }

          var changed = settings.summary(currency: currency)
          if minAge != nil || maxAge != nil { changed.append("ages \(minAge ?? 18)–\(maxAge.map(String.init) ?? "65+")") }
          print("Creating ad group '\(name)' in \(campaign.name ?? "-"), a copy of \(source.name ?? "-")"
            + (changed.isEmpty ? "" : " with \(changed.joined(separator: ", "))") + (enabled ? "." : ", paused."))
          guard confirm("Create it? [y/N] ") else {
            print(yellow("Cancelled."))
            return
          }
          let created = try await client.postAdgroups(
            headers: .init(xApContext: Ads.context(ads)),
            body: .json(.init(
              // Required by the API though the spec marks it optional; a paused group still waits for resume.
              name: name, campaignId: campaignID, startTime: Date(), pricingModel: .init(value1: pricingModel),
              automatedKeywordsOptIn: searchMatch ?? source.automatedKeywordsOptIn,
              status: .init(value1: enabled ? .enabled : .paused),
              bidStrategy: bidStrategy.map { .init(value1: $0) },
              cpaCap: cpaGoal.map { .init(value1: $0) },
              targeting: targeting.map { .init(value1: $0) }
            ))
          ).ok.body.json.result
          print(green("Created") + " ad group '\(name)' (ID \(created?.id.map(String.init) ?? "-")).")
          if !enabled {
            print("Add keywords ('ascelerate ads keywords copy --campaign … --from \"\(source.name ?? "")\" --to \"\(name)\"' or 'keywords add --ad-group \"\(name)\"'), then 'ascelerate ads adgroups resume'.")
          }
        }
      }
    }

    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Change an ad group's name, default bid, Search Match or CPA goal.")

      @Argument(help: "Ad group name or ID.")
      var adGroup: String

      @Option(name: .long, help: "Campaign name or ID.")
      var campaign: String

      @Option(name: .long, help: "New name.")
      var name: String?

      @OptionGroup var settings: Settings

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        guard name != nil || settings.defaultBid != nil || settings.searchMatch != nil || settings.cpaGoal != nil else {
          throw ValidationError("Nothing to change: pass --name, --default-bid, --search-match or --cpa-goal.")
        }
        let ads = try Ads.config()
        let searchMatch = try settings.searchMatchValue()
        try await Ads.withClient(ads) { client in
          let campaign = try await Ads.campaign(self.campaign, ads, client: client)
          let currency = try Ads.currency(of: campaign)
          let group = try Ads.adGroup(adGroup, in: await Ads.adGroups(campaignID: campaign.id ?? 0, ads, client: client))
          // Apple requires the type and goal with every bid strategy update.
          let bidStrategy: Components.Schemas.BidStrategyUpdate? = try settings.defaultBid.map {
            let current = group.bidStrategy?.value1
            return .init(
              bidStrategyType: current?.bidStrategyType.map { .init(value1: $0.value1) },
              bidStrategyGoal: current?.bidStrategyGoal.map { .init(value1: $0.value1) },
              bid: try Ads.money($0, currency: currency)
            )
          }
          let cpaGoal: Components.Schemas.CPAGoalUpdate? = try settings.cpaGoal.map {
            .init(value: try Ads.money($0, currency: currency))
          }

          var changes = settings.summary(currency: currency)
          if let name { changes.insert("name '\(name)'", at: 0) }
          let current = [
            group.bidStrategy?.value1.bid.map { "default bid \(Ads.Amount($0).formatted)" },
            group.automatedKeywordsOptIn.map { "Search Match \($0 ? "on" : "off")" },
            group.cpaCap?.value1.value.map { "CPA goal \(Ads.Amount($0).formatted)" },
          ].compactMap { $0 }
          print("\(campaign.name ?? "-") › \(group.name ?? "-") now: \(current.joined(separator: ", ")).")
          guard confirm("Change to \(changes.joined(separator: ", "))? [y/N] ") else {
            print(yellow("Cancelled."))
            return
          }
          _ = try await client.putAdgroupsId(
            path: .init(id: String(group.id ?? 0)),
            headers: .init(xApContext: Ads.context(ads)),
            body: .json(.init(
              name: name, automatedKeywordsOptIn: searchMatch,
              bidStrategy: bidStrategy.map { .init(value1: $0) }, cpaCap: cpaGoal.map { .init(value1: $0) }
            ))
          ).ok
          print(green("Updated") + " \(group.name ?? "-").")
        }
      }
    }

    struct Pause: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Pause ad groups.")
      @Option(name: .long, help: "Campaign name or ID.") var campaign: String
      @Argument(help: "Ad group names or IDs.") var adGroups: [String]
      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.") var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        try await setStatus(.paused, campaign: campaign, adGroups: adGroups)
      }
    }

    struct Resume: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Resume (enable) ad groups.")
      @Option(name: .long, help: "Campaign name or ID.") var campaign: String
      @Argument(help: "Ad group names or IDs.") var adGroups: [String]
      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.") var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        try await setStatus(.enabled, campaign: campaign, adGroups: adGroups)
      }
    }

    private static func setStatus(_ status: Components.Schemas.AdGroupStatus, campaign ref: String, adGroups refs: [String]) async throws {
      let ads = try Ads.config()
      let verb = status == .paused ? "Pause" : "Resume"
      try await Ads.withClient(ads) { client in
        let campaign = try await Ads.campaign(ref, ads, client: client)
        let groups = try await Ads.adGroups(campaignID: campaign.id ?? 0, ads, client: client)
        let targets = try refs.map { try Ads.adGroup($0, in: groups) }
        for group in targets where group.status?.value1 == status {
          print("\(group.name ?? "-") is already \(formatState(status.rawValue).lowercased()).")
        }
        let changing = targets.filter { $0.status?.value1 != status }
        guard !changing.isEmpty else { return }
        guard confirm("\(verb) \(changing.map { $0.name ?? "-" }.joined(separator: ", ")) in \(campaign.name ?? "-")? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        for group in changing {
          // Under dry run every request is shown, not only the first.
          guard try await unlessDryRunStopped({
            try await client.putAdgroupsId(
              path: .init(id: String(group.id ?? 0)),
              headers: .init(xApContext: Ads.context(ads)),
              body: .json(.init(status: .init(value1: status)))
            ).ok
          }) != nil else { continue }
          print(green(verb == "Pause" ? "Paused" : "Resumed") + " \(group.name ?? "-").")
        }
      }
    }
  }
}

extension Ads {
  /// Re-encodes a value as another type with the same JSON shape (an API read type as its create type).
  static func convert<T: Encodable, U: Decodable>(_ value: T, to type: U.Type) throws -> U {
    try JSONDecoder().decode(U.self, from: JSONEncoder().encode(value))
  }
}
