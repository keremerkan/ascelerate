import AppleAdsClient
import ArgumentParser
import AscelerateCore
import Foundation

extension AdsCommand {
  // MARK: - Keywords

  struct Keywords: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Keywords: list, add, pause, resume, bid; Apple's suggestions and search popularity.",
      subcommands: [List.self, Add.self, Copy.self, Pause.self, Resume.self, Bid.self, Suggest.self, Popularity.self]
    )

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "List keywords by campaign.")

      @OptionGroup var scope: Ads.ScopeOptions
      @OptionGroup var jsonOption: JSONOption

      private struct Entry: Encodable {
        let id: Int64
        let text: String
        let matchType: String?
        let campaignId: Int64
        let campaignName: String
        let adGroupId: Int64?
        let adGroupName: String?
        let status: String?
        let displayStatus: String?
        let bid: Ads.Amount?
      }

      func run() async throws {
        jsonOption.activate()
        let ads = try Ads.config()
        let scope = try await self.scope.resolve(ads)
        let entries = try await Ads.withClient(ads) { client in
          try await Ads.perCampaign(scope) { campaignID in
            async let groups = Ads.adGroups(campaignID: campaignID, ads, client: client)
            async let keywords = Ads.keywords(campaignID: campaignID, ads, client: client)
            let names = Dictionary(try await groups.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            return try await keywords.map { ($0, names[$0.adGroupId] ?? nil) }
          }
        }.map { keyword, adGroupName in
          Entry(
            id: keyword.id ?? 0, text: keyword.text ?? "-", matchType: keyword.matchType?.value1.rawValue,
            campaignId: keyword.campaignId ?? 0, campaignName: scope.campaignName(keyword.campaignId ?? 0),
            adGroupId: keyword.adGroupId, adGroupName: adGroupName, status: keyword.status?.value1.rawValue,
            displayStatus: keyword.displayStatus?.value1.rawValue, bid: keyword.bid.map(Ads.Amount.init)
          )
        }

        if jsonOption.json { try printJSON(entries); return }
        var rows: [[String]] = []
        for (campaign, keywords) in Ads.grouped(entries, by: \.campaignName) {
          if !rows.isEmpty { rows.append(["", "", "", "", ""]) }
          rows.append([bold(campaign), "", "", "", ""])
          for k in keywords.sorted(by: { $0.text < $1.text }) {
            let status: String = k.displayStatus.map(Ads.formatStatus) ?? "-"
            let match: String = k.matchType.map { formatState($0) } ?? "-"
            rows.append(["  " + k.text, match, k.adGroupName ?? "-", status, k.bid?.formatted ?? "-"])
          }
        }
        Table.print(headers: ["Keyword", "Match", "Ad Group", "Status", "Bid"], rows: rows)
      }
    }

    struct Add: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Add keywords to an ad group (keywords it already has are skipped)."
      )

      @Option(name: .long, help: "Campaign name or ID.")
      var campaign: String

      @Option(name: .long, help: "Ad group name or ID (needed when the campaign has more than one).")
      var adGroup: String?

      @Option(name: .long, help: "Match type: exact or broad.")
      var match: String

      @Option(name: .long, help: "Bid (max CPT) in the ad account's currency; default: the ad group's bid.")
      var bid: String?

      @Argument(help: "Keywords to add.")
      var keywords: [String]

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let ads = try Ads.config()
        let matchType = try Ads.matchType(match)
        try await Ads.withClient(ads) { client in
          let campaign = try await Ads.campaign(self.campaign, ads, client: client)
          let campaignID = campaign.id ?? 0
          if bid != nil, Ads.isAutomaticBidding(campaign) {
            throw ValidationError("\(campaign.name ?? "-") uses Maximize Conversions, which sets bids itself. Leave out --bid.")
          }
          let money = try bid.map { try Ads.money($0, currency: Ads.currency(of: campaign)) }
          let group = try Ads.adGroup(adGroup, in: await Ads.adGroups(campaignID: campaignID, ads, client: client))
          let existing = Set(
            try await Ads.keywords(campaignID: campaignID, ads, client: client)
              .filter { $0.adGroupId == group.id && $0.matchType?.value1 == matchType }
              .compactMap { $0.text?.lowercased() }
          )
          let texts = Ads.unique(keywords)
          for text in texts where existing.contains(text.lowercased()) {
            print("Skipping '\(text)': already in \(group.name ?? "-") as \(formatState(matchType.rawValue).lowercased()).")
          }
          let new = texts.filter { !existing.contains($0.lowercased()) }
          guard !new.isEmpty else { return }

          let bidText = money.map { " at \(Ads.Amount($0).formatted)" } ?? ""
          print("Adding \(new.count) \(formatState(matchType.rawValue).lowercased()) keyword(s)\(bidText) to \(campaign.name ?? "-") › \(group.name ?? "-"):")
          for text in new { print("  \(text)") }
          guard confirm("Add them? [y/N] ") else {
            print(yellow("Cancelled."))
            return
          }
          let items = new.enumerated().map { i, text in
            Components.Schemas.KeywordCreateBulkRequestItem(
              correlationId: Int64(i + 1),
              data: .init(
                adGroupId: group.id ?? 0, text: text, matchType: .init(value1: matchType),
                bid: money.map { .init(value1: $0) }, status: .init(value1: .enabled)
              )
            )
          }
          let results = try await Ads.bulk(Components.Schemas.Keyword.self) {
            _ = try await client.postKeywordsBulkCreate(
              headers: .init(xApContext: Ads.context(ads)),
              body: .json(.init(value1: Ads.bulkBase, value2: .init(items: items)))
            )
          }
          try Ads.report(results, labels: new, verb: "Added")
        }
      }
    }

    struct Copy: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Copy an ad group's keywords (text, match type, bid, status) to another ad group of the campaign."
      )

      @Option(name: .long, help: "Campaign name or ID.")
      var campaign: String

      @Option(name: .long, help: "Ad group to copy from (name or ID).")
      var from: String

      @Option(name: .long, help: "Ad group to copy to (name or ID).")
      var to: String

      @Option(name: .long, help: "Only this match type: exact or broad.")
      var match: String?

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let ads = try Ads.config()
        let matchType = try match.map(Ads.matchType)
        try await Ads.withClient(ads) { client in
          let campaign = try await Ads.campaign(self.campaign, ads, client: client)
          let campaignID = campaign.id ?? 0
          let groups = try await Ads.adGroups(campaignID: campaignID, ads, client: client)
          let source = try Ads.adGroup(from, in: groups)
          let target = try Ads.adGroup(to, in: groups)
          guard source.id != target.id else { throw ValidationError("--from and --to are the same ad group.") }
          let keywords = try await Ads.keywords(campaignID: campaignID, ads, client: client)
          func key(_ k: Components.Schemas.Keyword) -> String {
            "\(k.text?.lowercased() ?? "")|\(k.matchType?.value1.rawValue ?? "")"
          }
          let existing = Set(keywords.filter { $0.adGroupId == target.id }.map(key))
          let candidates = keywords.filter {
            $0.adGroupId == source.id && (matchType == nil || $0.matchType?.value1 == matchType)
          }
          let copies = candidates.filter { !existing.contains(key($0)) }
          if candidates.count > copies.count {
            print("Skipping \(candidates.count - copies.count) keyword(s) \(target.name ?? "-") already has.")
          }
          guard !copies.isEmpty else { return }

          print("Copying \(copies.count) keyword(s) from \(source.name ?? "-") to \(target.name ?? "-") in \(campaign.name ?? "-"), with their bids.")
          guard confirm("Copy them? [y/N] ") else {
            print(yellow("Cancelled."))
            return
          }
          let labels = copies.map { k in
            "\(k.text ?? "-") (\(formatState(k.matchType?.value1.rawValue ?? "").lowercased()), \(k.bid.map { Ads.Amount($0).formatted } ?? "ad group bid"))"
          }
          let items = copies.enumerated().map { i, k in
            Components.Schemas.KeywordCreateBulkRequestItem(
              correlationId: Int64(i + 1),
              data: .init(
                adGroupId: target.id ?? 0, text: k.text ?? "", matchType: k.matchType.map { .init(value1: $0.value1) },
                bid: k.bid.map { .init(value1: $0) }, status: k.status.map { .init(value1: $0.value1) }
              )
            )
          }
          let results = try await Ads.bulk(Components.Schemas.Keyword.self) {
            _ = try await client.postKeywordsBulkCreate(
              headers: .init(xApContext: Ads.context(ads)),
              body: .json(.init(value1: Ads.bulkBase, value2: .init(items: items)))
            )
          }
          try Ads.report(results, labels: labels, verb: "Copied")
        }
      }
    }

    struct Pause: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Pause keywords.")
      @OptionGroup var target: KeywordTarget
      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.") var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        try await target.update(verb: "Pause", done: "Paused") { id, _ in .init(id: id, status: .init(value1: .paused)) }
      }
    }

    struct Resume: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Resume (enable) paused keywords.")
      @OptionGroup var target: KeywordTarget
      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.") var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        try await target.update(verb: "Resume", done: "Resumed") { id, _ in .init(id: id, status: .init(value1: .enabled)) }
      }
    }

    struct Bid: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Set the bid (max CPT) of keywords.")
      @OptionGroup var target: KeywordTarget

      @Option(name: .long, help: "New bid in the ad account's currency (e.g. 1.25).")
      var bid: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.") var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        try await target.update(verb: "Set the bid of", done: "Updated", bid: bid) { id, money in
          .init(id: id, bid: money.map { .init(value1: $0) })
        }
      }
    }

    /// The keywords a pause/resume/bid works on: texts in a campaign, optionally one ad group
    /// and one match type. Every keyword matching a text is changed (listed before confirming).
    struct KeywordTarget: ParsableArguments {
      @Option(name: .long, help: "Campaign name or ID.")
      var campaign: String

      @Option(name: .long, help: "Only keywords in this ad group (name or ID).")
      var adGroup: String?

      @Option(name: .long, help: "Only this match type: exact or broad.")
      var match: String?

      @Argument(help: "Keyword texts.")
      var keywords: [String]

      func update(
        verb: String, done: String, bid: String? = nil,
        _ data: (Int64, Components.Schemas.Money?) -> Components.Schemas.BulkKeywordUpdate
      ) async throws {
        let ads = try Ads.config()
        let matchType = try match.map(Ads.matchType)
        try await Ads.withClient(ads) { client in
          let campaign = try await Ads.campaign(self.campaign, ads, client: client)
          let campaignID = campaign.id ?? 0
          var money: Components.Schemas.Money?
          if let bid {
            if Ads.isAutomaticBidding(campaign) {
              throw ValidationError("\(campaign.name ?? "-") uses Maximize Conversions, which sets bids itself.")
            }
            money = try Ads.money(bid, currency: Ads.currency(of: campaign))
          }
          let groups = try await Ads.adGroups(campaignID: campaignID, ads, client: client)
          let groupID = try adGroup.map { try Ads.adGroup($0, in: groups).id }
          let groupNames = Dictionary(groups.map { ($0.id, $0.name ?? "-") }, uniquingKeysWith: { a, _ in a })
          let all = try await Ads.keywords(campaignID: campaignID, ads, client: client).filter {
            (groupID == nil || $0.adGroupId == groupID) && (matchType == nil || $0.matchType?.value1 == matchType)
          }
          var targets: [Components.Schemas.Keyword] = []
          for text in Ads.unique(keywords) {
            let matches = all.filter { $0.text?.caseInsensitiveCompare(text) == .orderedSame }
            if matches.isEmpty { throw ValidationError("No keyword '\(text)' in \(campaign.name ?? "-").") }
            targets += matches
          }

          let labels = targets.map { k in
            "\(k.text ?? "-") (\(formatState(k.matchType?.value1.rawValue ?? "").lowercased()), \(groupNames[k.adGroupId] ?? "-"))"
          }
          let newBid = money.map { " to \(Ads.Amount($0).formatted)" } ?? ""
          print("\(verb) \(targets.count) keyword(s) in \(campaign.name ?? "-")\(newBid):")
          for (k, label) in zip(targets, labels) {
            print("  \(label)" + (money != nil ? ", now \(k.bid.map(Ads.Amount.init)?.formatted ?? "ad group bid")" : ""))
          }
          guard confirm("Apply? [y/N] ") else {
            print(yellow("Cancelled."))
            return
          }
          let items = targets.enumerated().map { i, k in
            Components.Schemas.KeywordUpdateBulkRequestItem(correlationId: Int64(i + 1), data: data(k.id ?? 0, money))
          }
          let results = try await Ads.bulk(Components.Schemas.Keyword.self) {
            _ = try await client.postKeywordsBulkUpdate(
              headers: .init(xApContext: Ads.context(ads)),
              body: .json(.init(value1: Ads.bulkBase, value2: .init(items: items)))
            )
          }
          try Ads.report(results, labels: labels, verb: done)
        }
      }
    }
  }

  // MARK: - Negative keywords

  struct Negatives: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List, add and remove negative keywords (searches your ads must not show for).",
      subcommands: [List.self, Add.self, Remove.self]
    )

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "List negative keywords by campaign.")

      @OptionGroup var scope: Ads.ScopeOptions
      @OptionGroup var jsonOption: JSONOption

      private struct Entry: Encodable {
        let id: Int64
        let text: String
        let matchType: String?
        let campaignId: Int64
        let campaignName: String
        /// Nil for a campaign-level negative keyword.
        let adGroupId: Int64?
        let adGroupName: String?
        let status: String?
      }

      func run() async throws {
        jsonOption.activate()
        let ads = try Ads.config()
        let scope = try await self.scope.resolve(ads)
        let entries = try await Ads.withClient(ads) { client in
          try await Ads.perCampaign(scope) { campaignID in
            let groups = try await Ads.adGroups(campaignID: campaignID, ads, client: client)
            let names = Dictionary(groups.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            return try await Ads.negativeKeywords(
              campaignID: campaignID, adGroupIDs: groups.compactMap(\.id), ads, client: client
            ).map { ($0, $0.adGroupId.flatMap { names[$0] ?? nil }) }
          }
        }.map { negative, adGroupName in
          Entry(
            id: negative.id ?? 0, text: negative.text ?? "-", matchType: negative.matchType?.value1.rawValue,
            campaignId: negative.campaignId ?? 0, campaignName: scope.campaignName(negative.campaignId ?? 0),
            adGroupId: negative.adGroupId, adGroupName: adGroupName, status: negative.status?.value1.rawValue
          )
        }

        if jsonOption.json { try printJSON(entries); return }
        var rows: [[String]] = []
        for (campaign, negatives) in Ads.grouped(entries, by: \.campaignName) {
          if !rows.isEmpty { rows.append(["", "", "", ""]) }
          rows.append([bold(campaign), "", "", ""])
          for n in negatives.sorted(by: { $0.text < $1.text }) {
            let match: String = n.matchType.map { formatState($0) } ?? "-"
            let status: String = n.status.map(Ads.formatStatus) ?? "-"
            rows.append(["  " + n.text, match, n.adGroupName ?? "Campaign", status])
          }
        }
        Table.print(headers: ["Negative Keyword", "Match", "Applies To", "Status"], rows: rows)
      }
    }

    struct Add: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Add negative keywords to a campaign, or to one ad group with --ad-group."
      )

      @Option(name: .long, help: "Campaign name or ID.")
      var campaign: String

      @Option(name: .long, help: "Only this ad group (name or ID); default: the whole campaign.")
      var adGroup: String?

      @Option(name: .long, help: "Match type: exact (default) or broad.")
      var match = "exact"

      @Argument(help: "Search terms to exclude.")
      var terms: [String]

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let ads = try Ads.config()
        let matchType = try Ads.matchType(match)
        try await Ads.withClient(ads) { client in
          let campaign = try await Ads.campaign(self.campaign, ads, client: client)
          let campaignID = campaign.id ?? 0
          var group: Components.Schemas.AdGroup?
          if let adGroup {
            group = try Ads.adGroup(adGroup, in: await Ads.adGroups(campaignID: campaignID, ads, client: client))
          }
          // A broad negative keyword already excludes the exact search too.
          let existing = Set(
            try await Ads.negativeKeywords(
              campaignID: campaignID, adGroupIDs: group?.id.map { [$0] } ?? [], ads, client: client
            )
            .filter { $0.adGroupId == group?.id && ($0.matchType?.value1 == matchType || $0.matchType?.value1 == .broad) }
            .compactMap { $0.text?.lowercased() }
          )
          let level = group.map { "\(campaign.name ?? "-") › \($0.name ?? "-")" } ?? (campaign.name ?? "-")
          let texts = Ads.unique(terms)
          for text in texts where existing.contains(text.lowercased()) {
            print("Skipping '\(text)': already a negative keyword of \(level).")
          }
          let new = texts.filter { !existing.contains($0.lowercased()) }
          guard !new.isEmpty else { return }

          print("Adding \(new.count) \(formatState(matchType.rawValue).lowercased()) negative keyword(s) to \(level):")
          for text in new { print("  \(text)") }
          guard confirm("Add them? [y/N] ") else {
            print(yellow("Cancelled."))
            return
          }
          // Campaign level: campaignId only; ad group level: adGroupId only.
          let items = new.enumerated().map { i, text in
            Components.Schemas.NegativeKeywordCreateBulkRequestItem(
              correlationId: Int64(i + 1),
              data: .init(
                campaignId: group == nil ? campaignID : nil, adGroupId: group?.id, text: text,
                matchType: .init(value1: matchType), status: .init(value1: .enabled)
              )
            )
          }
          let results = try await Ads.bulk(Components.Schemas.NegativeKeyword.self) {
            _ = try await client.postNegativeKeywordsBulkCreate(
              headers: .init(xApContext: Ads.context(ads)),
              body: .json(.init(value1: Ads.bulkBase, value2: .init(items: items)))
            )
          }
          try Ads.report(results, labels: new, verb: "Added")
        }
      }
    }

    struct Remove: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Remove negative keywords from a campaign.")

      @Option(name: .long, help: "Campaign name or ID.")
      var campaign: String

      @Option(name: .long, help: "Only this match type: exact or broad.")
      var match: String?

      @Argument(help: "Negative keyword texts.")
      var terms: [String]

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let ads = try Ads.config()
        let matchType = try match.map(Ads.matchType)
        try await Ads.withClient(ads) { client in
          let campaign = try await Ads.campaign(self.campaign, ads, client: client)
          let campaignID = campaign.id ?? 0
          let groups = try await Ads.adGroups(campaignID: campaignID, ads, client: client)
          let all = try await Ads.negativeKeywords(
            campaignID: campaignID, adGroupIDs: groups.compactMap(\.id), ads, client: client
          ).filter { matchType == nil || $0.matchType?.value1 == matchType }
          var targets: [Components.Schemas.NegativeKeyword] = []
          for text in Ads.unique(terms) {
            let matches = all.filter { $0.text?.caseInsensitiveCompare(text) == .orderedSame }
            if matches.isEmpty { throw ValidationError("No negative keyword '\(text)' in \(campaign.name ?? "-").") }
            targets += matches
          }
          print("Removing \(targets.count) negative keyword(s) from \(campaign.name ?? "-"):")
          for n in targets {
            print("  \(n.text ?? "-") (\(formatState(n.matchType?.value1.rawValue ?? "").lowercased()))")
          }
          guard confirm("Remove them? [y/N] ") else {
            print(yellow("Cancelled."))
            return
          }
          for n in targets {
            // Under dry run every request is shown, not only the first.
            guard try await unlessDryRunStopped({
              try await client.deleteNegativeKeywordsId(
                path: .init(id: String(n.id ?? 0)), headers: .init(xApContext: Ads.context(ads))
              ).ok
            }) != nil else { continue }
            print(green("Removed") + " \(n.text ?? "-").")
          }
        }
      }
    }
  }
}

extension Ads {
  /// `--app`/`--campaign` for list commands (all campaigns without either).
  struct ScopeOptions: ParsableArguments {
    @Option(name: .long, help: "Only campaigns for this app (bundle ID or alias).")
    var app: String?

    @Option(name: .long, help: "Only this campaign (name or ID).")
    var campaign: String?

    func resolve(_ ads: AdsConfig) async throws -> Scope {
      try await Scope.resolve(ads, app: app, campaign: campaign)
    }
  }

  /// A bulk request's own fields: apply the items that succeed even when others fail.
  static let bulkBase = Components.Schemas.BulkOperationRequest(value1: .init(allowPartialSuccess: true), value2: .init())

  /// Prints each bulk item's outcome (labels in request order, matched by `correlationId`) and
  /// fails the command if any item failed.
  static func report<T>(_ results: [BulkItem<T>], labels: [String], verb: String) throws {
    var failed = 0
    for (i, label) in labels.enumerated() {
      let item = results.first { $0.correlationId == Int64(i + 1) }
      if item?.success == true {
        print(green(verb) + " \(label).")
      } else {
        failed += 1
        print(red("Failed") + " \(label): \(item?.error?.text ?? "no result")")
      }
    }
    if failed > 0 { throw ExitCode.failure }
  }

  /// Rows grouped by a key, in first-seen order.
  static func grouped<T>(_ items: [T], by key: KeyPath<T, String>) -> [(String, [T])] {
    var order: [String] = []
    var groups: [String: [T]] = [:]
    for item in items {
      let k = item[keyPath: key]
      if groups[k] == nil { order.append(k) }
      groups[k, default: []].append(item)
    }
    return order.map { ($0, groups[$0]!) }
  }

  /// Arguments without blanks and case-insensitive repeats, in order.
  static func unique(_ texts: [String]) -> [String] {
    var seen = Set<String>()
    return texts.map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
  }
}
