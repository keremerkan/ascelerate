import AppleAdsClient
import AscelerateAds
import ArgumentParser
import AscelerateCore
import Crypto
import Foundation

struct AdsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "ads",
    abstract: "Manage Apple Ads campaigns (Apple Ads Platform API).",
    subcommands: [Configure.self, Accounts.self, Campaigns.self, AdGroups.self, Keywords.self, Negatives.self, Reports.self, Opportunities.self, Insights.self, Recommendations.self, History.self, ProductPages.self, Ads_.self]
  )

  // MARK: - Configure

  struct Configure: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Set up Apple Ads API credentials (creates the key pair for you)."
    )

    @Flag(name: .long, help: "Create a new key pair even if one exists.")
    var newKey = false

    func run() async throws {
      var config = try Config.load()
      try Config.createDirectory()

      let keyURL = Config.configDirectory.appendingPathComponent("ads-private-key.pem")
      let privateKey: P256.Signing.PrivateKey
      if !newKey, FileManager.default.fileExists(atPath: keyURL.path) {
        privateKey = try P256.Signing.PrivateKey(pemRepresentation: String(contentsOf: keyURL, encoding: .utf8))
        print("Using the existing key at \(keyURL.path).")
      } else {
        privateKey = P256.Signing.PrivateKey()
        try Data(privateKey.pemRepresentation.utf8).write(to: keyURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        print("Created a new key at \(keyURL.path).")
      }

      print("""

        In Apple Ads, sign in as a user with an API role, choose Account Settings → API,
        paste this public key into the Public Key field and click Save:

        \(privateKey.publicKey.pemRepresentation)

        Apple Ads then shows clientId, teamId and keyId above the field.

        """)

      var ads = AdsConfig(
        clientId: try promptText("clientId: "),
        teamId: try promptText("teamId: "),
        keyId: try promptText("keyId: "),
        privateKeyPath: keyURL.path
      )

      let accounts = try await Ads.withClient(ads) { client in
        try await client.getUserAcls().ok.body.json.result?.acls ?? []
      }.compactMap(\.adAccount)
      guard !accounts.isEmpty else {
        throw ValidationError("The credentials work, but this user has no ad accounts.")
      }
      let account = accounts.count == 1
        ? accounts[0]
        : try promptSelection("Ad accounts", items: accounts, display: { "\($0.name ?? "-") (\($0.id ?? 0))" })
      ads.adAccountId = account.id
      config.ads = ads
      try config.save()

      print()
      print(green("Saved") + " Apple Ads credentials; ad account \(account.name ?? "-") (\(account.id ?? 0)).")
    }
  }

  // MARK: - Accounts

  struct Accounts: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List the ad accounts and roles the API user can access."
    )

    func run() async throws {
      let ads = try Ads.config()
      let acls = try await Ads.withClient(ads) { client in
        try await client.getUserAcls().ok.body.json.result?.acls ?? []
      }
      Table.print(
        headers: ["ID", "Name", "Roles", ""],
        rows: acls.map { acl in
          let id = acl.adAccount?.id
          return [
            id.map(String.init) ?? "-", acl.adAccount?.name ?? "-", (acl.roles ?? []).joined(separator: ", "),
            id == ads.adAccountId ? "(selected)" : "",
          ]
        }
      )
    }
  }

  // MARK: - Campaigns

  struct Campaigns: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Manage campaigns.",
      subcommands: [List.self, Create.self, Pause.self, Resume.self, Budget.self, Bid.self, TargetCPA.self]
    )

    struct Pause: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Pause campaigns.")

      @Argument(help: "Campaign names or IDs.")
      var campaigns: [String]

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        try await setStatus(.paused, campaigns: campaigns, yes: yes)
      }
    }

    struct Resume: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Resume (enable) paused campaigns.")

      @Argument(help: "Campaign names or IDs.")
      var campaigns: [String]

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        try await setStatus(.enabled, campaigns: campaigns, yes: yes)
      }
    }

    private static func setStatus(_ status: Components.Schemas.CampaignStatus, campaigns refs: [String], yes: Bool) async throws {
      if yes { autoConfirm = true }
      let ads = try Ads.config()
      let verb = status == .paused ? "Pause" : "Resume"
      try await Ads.withClient(ads) { client in
        let all = try await Ads.campaigns(ads, client: client)
        let targets = try refs.map { try Ads.find(campaign: $0, in: all) }
        let changing = targets.filter { $0.status?.value1 != status }
        for campaign in targets where campaign.status?.value1 == status {
          print("\(campaign.name ?? "-") is already \(formatState(status.rawValue).lowercased()).")
        }
        guard !changing.isEmpty else { return }
        let names = changing.map { $0.name ?? "-" }.joined(separator: ", ")
        guard confirm("\(verb) \(names)? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        for campaign in changing {
          // Under dry run every request is shown, not only the first.
          guard try await unlessDryRunStopped({
            try await Ads.setStatus(status, campaignID: campaign.id ?? 0, context: Ads.context(ads), client: client)
          }) != nil else { continue }
          print(green(verb == "Pause" ? "Paused" : "Resumed") + " \(campaign.name ?? "-").")
        }
      }
    }

    struct Create: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Create a Search Results campaign with its ad group (created paused).",
        discussion: """
          Max Conversions (--max-conversions --bid X): Apple bids for installs under the X ceiling per \
          auction; the campaign gets the automated ad group it requires (Search Match, no keywords).
          Manual CPT (default, --default-bid X): one ad group with Search Match on (or --search-match off); \
          add keywords with 'ads keywords add'.

          --like copies an existing campaign's placement, billing event and regulation answers (some \
          storefronts, like France, require them), and for manual campaigns its ad group's device \
          targeting and Search Match setting.

          A new campaign for an app competes with that app's other campaigns in the same storefront: \
          Apple lets one of them into each auction.
          """
      )

      @Option(name: .long, help: "The app (bundle ID or alias); default: the --like campaign's app.")
      var app: String?

      @Option(name: .long, help: "Campaign name.")
      var name: String

      @Option(name: .customLong("country"), parsing: .upToNextOption, help: "Storefronts (e.g. US); default: the --like campaign's.")
      var countries: [String] = []

      @Option(name: .long, help: "Daily budget in the ad account's currency.")
      var daily: String

      @Flag(name: .long, help: "Maximize Conversions bidding (needs --bid, the per-auction ceiling).")
      var maxConversions = false

      @Option(name: .long, help: "Max Conversions: the per-auction bid ceiling.")
      var bid: String?

      @Option(name: .long, help: "Manual CPT: the ad group's default bid (max CPT).")
      var defaultBid: String?

      @Option(name: .long, help: "Manual CPT: Search Match on (default) or off.")
      var searchMatch: String?

      @Option(name: .long, help: "Existing campaign to copy placement, billing and regulation answers from.")
      var like: String?

      @Flag(name: .long, help: "Start it right away instead of paused.")
      var enabled = false

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func validate() throws {
        if maxConversions {
          guard bid != nil else { throw ValidationError("--max-conversions needs --bid (the per-auction ceiling).") }
          guard defaultBid == nil, searchMatch == nil else {
            throw ValidationError("--default-bid and --search-match are for manual campaigns.")
          }
        } else {
          guard defaultBid != nil else { throw ValidationError("A manual campaign needs --default-bid (or pass --max-conversions).") }
          guard bid == nil else { throw ValidationError("--bid is the Max Conversions ceiling; use --default-bid for manual campaigns.") }
        }
        if let searchMatch, !["on", "off"].contains(searchMatch.lowercased()) {
          throw ValidationError("--search-match takes on or off.")
        }
        if app == nil && like == nil { throw ValidationError("Pass --app or --like.") }
      }

      func run() async throws {
        if yes { autoConfirm = true }
        let ads = try Ads.config()
        guard let adAccountID = ads.adAccountId else {
          throw ValidationError("No ad account selected. Run 'ascelerate ads configure'.")
        }
        let appID = try await appStoreAppID(bundleID: app)
        try await Ads.withClient(ads) { client in
          let campaigns = try await Ads.campaigns(ads, client: client)
          if campaigns.contains(where: { $0.name?.caseInsensitiveCompare(name) == .orderedSame }) {
            throw ValidationError("A campaign named '\(name)' already exists.")
          }
          let source = try like.map { try Ads.find(campaign: $0, in: campaigns) }
          guard let promotedObjectID = appID ?? source?.promotedObjectId else { throw ValidationError("Pass --app.") }
          let currency = try source.map(Ads.currency(of:)) ?? Ads.currencyOfAccount(campaigns)

          // Placement and billing from --like (Search Results and taps otherwise); storefronts from --country.
          var targeting = try source?.targeting.map { try Ads.convert($0.value1, to: Components.Schemas.CampaignTargetingCreate.self) }
            ?? .init(supplyPlacement: .init(value1: .init(include: ["APPSTORE_SEARCH_RESULTS"])))
          let storefronts = countries.isEmpty ? (targeting.countryOrRegion?.value1.include ?? []) : countries.map { $0.uppercased() }
          guard !storefronts.isEmpty else { throw ValidationError("Pass --country.") }
          targeting.countryOrRegion = .init(value1: .init(include: storefronts))
          let billingEvent = source?.billingEvent?.value1 ?? .taps
          let regulations = try source?.regulationResponses.map {
            try Ads.convert($0, to: [Components.Schemas.RegulationResponseCreate].self)
          }

          let budget = try Ads.money(daily, currency: currency)
          let strategy: Components.Schemas.BidStrategyCreate = maxConversions
            ? .init(bidStrategyType: .init(value1: .maxConversions), bidStrategyGoal: .init(value1: .install), bid: try Ads.money(bid ?? "", currency: currency))
            : .init(bidStrategyType: .init(value1: .manualCpt), bidStrategyGoal: .init(value1: .tap))

          let kind = maxConversions ? "Max Conversions, bid ceiling \(Ads.Amount(try Ads.money(bid ?? "", currency: currency)).formatted)" : "Manual CPT, default bid \(Ads.Amount(try Ads.money(defaultBid ?? "", currency: currency)).formatted)"
          print("Creating campaign '\(name)' (\(storefronts.joined(separator: ", "))), \(kind), daily budget \(Ads.Amount(budget).formatted)"
            + (source.map { ", settings from \($0.name ?? "-")" } ?? "") + (enabled ? "." : ", paused."))
          guard confirm("Create it? [y/N] ") else {
            print(yellow("Cancelled."))
            return
          }

          // Under dry run the campaign request is shown and a placeholder ID lets the ad group request show too.
          let created = try await unlessDryRunStopped {
            try await client.postCampaigns(
              headers: .init(xApContext: Ads.context(ads)),
              body: .json(.init(
                adAccountId: adAccountID, name: name, billingEvent: .init(value1: billingEvent),
                promotedObjectType: .init(value1: .appstoreApp), promotedObjectId: promotedObjectID,
                status: .init(value1: enabled ? .enabled : .paused), dailyBudget: .init(value1: .init(value: budget)),
                targeting: .init(value1: targeting), bidStrategy: .init(value1: strategy),
                regulationResponses: regulations
              ))
            ).ok.body.json.result
          }
          let campaignID = created??.id ?? 0
          if created != nil { print(green("Created") + " campaign '\(name)' (ID \(campaignID)).") }

          let group: Components.Schemas.AdGroupCreate
          if maxConversions {
            group = Ads.automatedAdGroup(campaignID: campaignID)
          } else {
            var sourceGroup: Components.Schemas.AdGroup?
            if let sourceID = source?.id { sourceGroup = try await Ads.adGroups(campaignID: sourceID, ads, client: client).first }
            let deviceTargeting = try sourceGroup?.targeting?.value1.deviceClass.map {
              Components.Schemas.AdGroupTargetingCreate(deviceClass: .init(value1: try Ads.convert($0.value1, to: Components.Schemas.TargetingDataCreate.self)))
            }
            group = .init(
              name: "\(name) Ad Group", campaignId: campaignID, startTime: Date(), pricingModel: .init(value1: .cpt),
              automatedKeywordsOptIn: searchMatch.map { $0.lowercased() == "on" } ?? sourceGroup?.automatedKeywordsOptIn ?? true,
              status: .init(value1: .enabled),
              bidStrategy: .init(value1: .init(
                bidStrategyType: .init(value1: .manualCpt), bidStrategyGoal: .init(value1: .tap),
                bid: try Ads.money(defaultBid ?? "", currency: currency)
              )),
              targeting: deviceTargeting.map { .init(value1: $0) }
            )
          }
          do {
            guard let adGroup = try await unlessDryRunStopped({
              try await client.postAdgroups(headers: .init(xApContext: Ads.context(ads)), body: .json(group)).ok.body.json.result
            }) else { return }
            print(green("Created") + " ad group '\(adGroup?.name ?? "-")' (ID \(adGroup?.id.map(String.init) ?? "-")).")
          } catch {
            print(red("The campaign exists, but its ad group couldn't be created.") + " Create it with 'ascelerate ads adgroups create' or in Apple Ads.")
            throw error
          }
          if !enabled { print("Resume it with 'ascelerate ads campaigns resume \"\(name)\"'.") }
        }
      }
    }

    struct TargetCPA: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "target-cpa",
        abstract: "Apple's suggested target CPA for a new Max Conversions campaign.",
        discussion: """
          Apple's suggestion is the highest tap-install CPI across the given storefronts that had at \
          least 10 installs in the last 28 days; storefronts without that volume give no suggestion.
          """
      )

      @Option(name: .long, help: "The app (bundle ID or alias).")
      var app: String

      @Option(name: .customLong("country"), parsing: .upToNextOption, help: "Storefronts (e.g. US); default: all with enough installs.")
      var countries: [String] = []

      @OptionGroup var jsonOption: JSONOption

      private struct Result: Encodable {
        let appId: String
        let countries: [String]?
        let suggestedTargetCPA: Ads.Amount?
        let appCategory: String?
      }

      func run() async throws {
        jsonOption.activate()
        let ads = try Ads.config()
        let app = try await appStoreApp(bundleID: self.app)
        let suggestion = try await Ads.withClient(ads) { client in
          var filters = Ads.recommendationFilters(app: app.id)
          if !countries.isEmpty {
            filters.append(.init(field: "countryOrRegion", _operator: ._in, value: countries.map { $0.uppercased() }))
          }
          return try await client.queryTargetCpaSuggestion(
            headers: .init(xApContext: Ads.context(ads)), body: .json(.init(filters: filters))
          ).ok.body.json.value2.result
        }
        let result = Result(
          appId: app.id, countries: suggestion?.countryOrRegion,
          suggestedTargetCPA: suggestion?.suggestedTargetCPA.map(Ads.Amount.init), appCategory: suggestion?.appCategory
        )
        if jsonOption.json { try printJSON(result); return }
        guard let cpa = result.suggestedTargetCPA else {
          print("No suggestion: Apple needs at least 10 installs in the last 28 days in a storefront.")
          return
        }
        let scope = result.countries.map { " (\($0.joined(separator: ", ")))" } ?? ""
        print("Suggested target CPA for \(app.name)\(scope): \(cpa.formatted)")
      }
    }

    struct Bid: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Change a campaign's bid: for Max Conversions, the per-auction ceiling Apple's bidding stays under."
      )

      @Argument(help: "Campaign name or ID.")
      var campaign: String

      @Option(name: .long, help: "New bid in the ad account's currency (e.g. 0.80).")
      var amount: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let ads = try Ads.config()
        try await Ads.withClient(ads) { client in
          let campaign = try await Ads.campaign(self.campaign, ads, client: client)
          guard let strategy = campaign.bidStrategy?.value1, let type = strategy.bidStrategyType?.value1,
            let goal = strategy.bidStrategyGoal?.value1
          else { throw ValidationError("\(campaign.name ?? "-") has no campaign-level bid strategy.") }
          let bid = try Ads.money(amount, currency: Ads.currency(of: campaign))
          let current = strategy.bid.map { Ads.Amount($0).formatted } ?? "none"
          guard confirm("Change the \(formatState(type.rawValue)) bid of \(campaign.name ?? "-") from \(current) to \(Ads.Amount(bid).formatted)? [y/N] ") else {
            print(yellow("Cancelled."))
            return
          }
          // Apple requires the type and goal with every bid strategy update.
          _ = try await client.putCampaignsId(
            path: .init(id: String(campaign.id ?? 0)),
            headers: .init(xApContext: Ads.context(ads)),
            body: .json(.init(bidStrategy: .init(value1: .init(
              bidStrategyType: .init(value1: type), bidStrategyGoal: .init(value1: goal), bid: bid
            ))))
          ).ok
          print(green("Updated") + " the bid of \(campaign.name ?? "-") to \(Ads.Amount(bid).formatted).")
        }
      }
    }

    struct Budget: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Change a campaign's daily budget.")

      @Argument(help: "Campaign name or ID.")
      var campaign: String

      @Option(name: .long, help: "New daily budget in the ad account's currency (e.g. 120).")
      var daily: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let ads = try Ads.config()
        try await Ads.withClient(ads) { client in
          let campaign = try await Ads.campaign(self.campaign, ads, client: client)
          let currency = try Ads.currency(of: campaign)
          let budget = try Ads.money(daily, currency: currency)
          let current = campaign.dailyBudget?.value1.value.map(Ads.Amount.init)?.formatted ?? "none"
          let new = Ads.Amount(budget).formatted
          guard confirm("Change the daily budget of \(campaign.name ?? "-") from \(current) to \(new)? [y/N] ") else {
            print(yellow("Cancelled."))
            return
          }
          try await Ads.setDailyBudget(budget, campaignID: campaign.id ?? 0, context: Ads.context(ads), client: client)
          print(green("Updated") + " the daily budget of \(campaign.name ?? "-") to \(new).")
        }
      }
    }

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "List the ad account's campaigns.")

      @Option(name: .long, help: "Only campaigns for this app (bundle ID or alias).")
      var app: String?

      @OptionGroup var jsonOption: JSONOption

      private struct Entry: Encodable {
        let id: Int64
        let name: String
        let appId: String?
        let appName: String?
        let status: String?
        let displayStatus: String?
        let countries: [String]?
        let dailyBudget: Ads.Amount?
        let bidStrategy: String?
        /// The campaign-level bid; for Max Conversions, the per-auction ceiling.
        let bid: Ads.Amount?
        let startTime: Date?
        let endTime: Date?

        var cells: [String] {
          let app: String = appName ?? appId ?? "-"
          let status: String = displayStatus.map(Ads.formatStatus) ?? "-"
          let bidding: String = (bidStrategy.map { formatState($0) } ?? "-") + (bid.map { " (bid \($0.formatted))" } ?? "")
          return [
            String(id), name, app, countries?.joined(separator: ", ") ?? "-", status,
            dailyBudget?.formatted ?? "-", bidding,
          ]
        }
      }

      func run() async throws {
        jsonOption.activate()
        let ads = try Ads.config()
        let scope = try await Ads.Scope.resolve(ads, app: app, campaign: nil)

        let entries = scope.campaigns.map { c in
          Entry(
            id: c.id ?? 0,
            name: c.name ?? "-",
            appId: c.promotedObjectId,
            appName: scope.appName(of: c),
            status: c.status?.value1.rawValue,
            displayStatus: c.displayStatus?.value1.rawValue,
            countries: c.targeting?.value1.countryOrRegion?.value1.include,
            dailyBudget: c.dailyBudget?.value1.value.map(Ads.Amount.init),
            bidStrategy: c.bidStrategy?.value1.bidStrategyType?.value1.rawValue,
            bid: c.bidStrategy?.value1.bid.map(Ads.Amount.init),
            startTime: c.startTime,
            endTime: c.endTime
          )
        }

        if jsonOption.json { try printJSON(entries); return }
        Table.print(
          headers: ["ID", "Campaign", "App", "Countries", "Status", "Daily Budget", "Bidding"],
          rows: entries.map(\.cells)
        )
      }
    }
  }
}
