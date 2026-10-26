import AppleAdsClient
import AscelerateAds
import ArgumentParser
import AscelerateCore
import Foundation

extension AdsCommand {
  struct Opportunities: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Search terms to add as exact keywords, to give their own bid, or to exclude, per campaign.",
      discussion: """
        Compares each campaign's search terms with its keywords and negative keywords, against the \
        campaign's own averages over the range (default: the last 30 complete days). A term needs \
        --min-taps taps (or 1,000 impressions for the click-through rule) to be judged; low-volume \
        terms Apple hides can't be judged.

          add-exact  converting, no exact keyword of its own, cost per install ≤ 1.25× the campaign's
          own-bid    no exact keyword of its own, cost per install > 1.25× the campaign's: served by
                     another keyword's (higher) bid
          negative   no installs, tap conversion under half the campaign's, click-through under a third
                     of the campaign's on 1,000+ impressions, or cost per install over 2× the campaign's;
                     never a term that is one of the campaign's keywords

        Brand searches (containing the app's name from App Store Connect, the part before ":" \
        or " - ", or a --brand spelling) are left out of the averages, since their very low cost \
        per install would make every other term look expensive, and are never negative candidates.

        Max Conversions campaigns pick their own searches, so only negatives are suggested there.

        Suggestions, not decisions: check relevance before acting.
        """
    )

    @OptionGroup var range: Ads.DateRangeOptions
    @OptionGroup var scope: Ads.ScopeOptions

    @Option(name: .long, help: "Taps a search term needs before it is judged (default: 10).")
    var minTaps = 10

    @Option(
      name: .long, parsing: .upToNextOption,
      help: "Other spellings of the brand (e.g. \"be gone\"); the app's name is always one."
    )
    var brand: [String] = []

    @OptionGroup var jsonOption: JSONOption

    private struct Entry: Encodable {
      /// add-exact, own-bid or negative.
      let kind: String
      let reason: String
      let campaignId: Int64
      let campaignName: String
      let searchTerm: String
      let metrics: Ads.Metrics
      /// The keywords that served the term (none: Search Match).
      let servedBy: [ServingKeyword]
    }

    private struct ServingKeyword: Encodable {
      let keyword: String
      let matchType: String?
      let bid: Ads.Amount?
    }

    /// One campaign's search term rows with what it already has.
    private struct CampaignData: Sendable {
      let campaignID: Int64
      let rows: [Components.Schemas.AppsSearchTermReportRow]
      let keywords: [Components.Schemas.Keyword]
      let negatives: [Components.Schemas.NegativeKeyword]
    }

    func run() async throws {
      jsonOption.activate()
      let ads = try Ads.config()
      let (start, end) = try await range.resolved(ads, defaultDays: 30, endingYesterday: true)
      let scope = try await self.scope.resolve(ads)
      let data = try await Ads.withClient(ads) { client in
        try await Ads.perCampaign(scope) { campaignID in
          let rows = try await Ads.reportRows { pagination in
            let json = try await client.appsSearchTermReports(
              headers: .init(xApContext: Ads.context(ads)),
              body: .json(Ads.reportRequest(
                start: start, end: end, filters: Ads.campaignFilter(campaignID), pagination: pagination
              ))
            ).ok.body.json
            return (json.result?.rows ?? [], json.pagination?.totalCount)
          }
          let keywords = try await Ads.keywords(campaignID: campaignID, ads, client: client)
          let groups = try await Ads.adGroups(campaignID: campaignID, ads, client: client)
          let negatives = try await Ads.negativeKeywords(
            campaignID: campaignID, adGroupIDs: groups.compactMap(\.id), ads, client: client
          )
          return [CampaignData(campaignID: campaignID, rows: rows, keywords: keywords, negatives: negatives)]
        }
      }
      let entries = data.flatMap { campaignData in
        let campaign = scope.campaigns.first { $0.id == campaignData.campaignID }
        return analyze(
          campaignData, campaignName: scope.campaignName(campaignData.campaignID), brands: brands(for: campaign, scope),
          // Max Conversions picks its own searches: keyword suggestions don't apply, negatives do.
          negativesOnly: campaign.map(Ads.isAutomaticBidding) ?? false
        )
      }

      if jsonOption.json { try printJSON(entries); return }
      print("\(start) – \(end), terms with \(minTaps)+ taps")
      for (kind, title) in [
        ("add-exact", "Add as exact keywords (converting, no exact keyword of their own)"),
        ("own-bid", "Give their own exact keyword and bid (expensive, served by another keyword's bid)"),
        ("negative", "Negative keyword candidates"),
      ] {
        let items = entries.filter { $0.kind == kind }
        print()
        print(bold(title))
        guard !items.isEmpty else {
          print("  None.")
          continue
        }
        Table.print(
          headers: ["Campaign", "Search Term", "Spend", "Taps", "Installs", "Avg CPI", "Served By", "Why"],
          rows: items.map { e in
            let servedBy = e.servedBy.isEmpty
              ? "Search Match"
              : e.servedBy.map { k in "\(k.keyword) (\(formatState(k.matchType ?? "").lowercased())\(k.bid.map { ", \(Ads.number($0.value, decimals: 2))" } ?? ""))" }
                .joined(separator: "; ")
            return [
              e.campaignName, e.searchTerm, e.metrics.spend?.formatted ?? "-", Ads.number(Double(e.metrics.taps)),
              Ads.number(Double(e.metrics.installs)), e.metrics.averageCPI?.formatted ?? "-", servedBy, e.reason,
            ]
          }
        )
      }
    }

    /// The brand spellings for a campaign: its app's name up to ":" or " - ", plus --brand.
    private func brands(for campaign: Components.Schemas.Campaign?, _ scope: Ads.Scope) -> [String] {
      let appName = campaign.flatMap { scope.appName(of: $0) }?
        .components(separatedBy: ":").first?.components(separatedBy: " - ").first?
        .trimmingCharacters(in: .whitespaces).lowercased()
      return ([appName].compactMap { $0 } + brand.map { $0.lowercased() }).filter { !$0.isEmpty }
    }

    private func analyze(_ data: CampaignData, campaignName: String, brands: [String], negativesOnly: Bool) -> [Entry] {
      func isBrand(_ term: String?) -> Bool {
        guard let term = term?.lowercased() else { return false }
        return brands.contains { term.contains($0) }
      }
      // The campaign's averages without brand searches (falling back to all rows if that leaves none).
      let nonBrand = data.rows.filter { !isBrand($0.metadata?.searchTermText) }
      guard let campaign = Ads.Metrics.total((nonBrand.isEmpty ? data.rows : nonBrand).compactMap { $0.totalMetrics.map(Ads.Metrics.init) }),
        let campaignCPI = campaign.averageCPI?.value, let campaignTapCR = campaign.tapConversionRate,
        let campaignTTR = campaign.ttr
      else { return [] }

      let keywordTexts = Set(data.keywords.compactMap { $0.text?.lowercased() })
      let exactTexts = Set(data.keywords.filter { $0.matchType?.value1 == .exact }.compactMap { $0.text?.lowercased() })
      let negativeTexts = Set(data.negatives.compactMap { $0.text?.lowercased() })
      let keywordsByID = Dictionary(data.keywords.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

      // The same search term shows up once per keyword (and ad group) that served it.
      var byTerm: [String: [Components.Schemas.AppsSearchTermReportRow]] = [:]
      for row in data.rows {
        guard let term = row.metadata?.searchTermText?.lowercased() else { continue }
        byTerm[term, default: []].append(row)
      }

      var entries: [Entry] = []
      for (term, rows) in byTerm where !negativeTexts.contains(term) {
        guard let m = Ads.Metrics.total(rows.compactMap { $0.totalMetrics.map(Ads.Metrics.init) }) else { continue }
        let enoughTaps = m.taps >= minTaps
        let cpi = m.averageCPI?.value
        let tapCR = m.tapConversionRate ?? 0
        let ttr = m.ttr ?? 0

        var kind: String?
        var reason = ""
        if !keywordTexts.contains(term), !isBrand(term) {
          if enoughTaps, m.installs == 0 {
            kind = "negative"
            reason = "no installs from \(m.taps) taps"
          } else if enoughTaps, tapCR < campaignTapCR / 2 {
            kind = "negative"
            reason = "tap conversion \(percent(tapCR)) vs \(percent(campaignTapCR))"
          } else if m.impressions >= 1000, ttr < campaignTTR / 3 {
            kind = "negative"
            reason = "click-through \(percent(ttr)) vs \(percent(campaignTTR)) on \(Ads.number(Double(m.impressions))) impressions"
          } else if enoughTaps, let cpi, cpi > campaignCPI * 2 {
            kind = "negative"
            reason = "\(money(cpi)) per install vs \(money(campaignCPI))"
          }
        }
        if kind == nil, !negativesOnly, enoughTaps, m.installs > 0, !exactTexts.contains(term), let cpi {
          if cpi <= campaignCPI * 1.25 {
            kind = "add-exact"
            reason = "\(money(cpi)) per install vs \(money(campaignCPI))"
          } else {
            kind = "own-bid"
            reason = "\(money(cpi)) per install vs \(money(campaignCPI)), at a tap cost of \(money(m.averageCPT?.value ?? 0))"
          }
        }
        guard let kind else { continue }

        var serving: [Int64: ServingKeyword] = [:]
        for row in rows {
          guard let id = row.metadata?.keyword?.id, serving[id] == nil else { continue }
          let keyword = keywordsByID[id]
          serving[id] = ServingKeyword(
            keyword: row.metadata?.keyword?.text ?? keyword?.text ?? "-",
            matchType: row.metadata?.keyword?.matchType?.rawValue ?? keyword?.matchType?.value1.rawValue,
            bid: keyword?.bid.map(Ads.Amount.init)
          )
        }
        entries.append(Entry(
          kind: kind, reason: reason, campaignId: data.campaignID, campaignName: campaignName,
          searchTerm: rows.first?.metadata?.searchTermText ?? term, metrics: m,
          servedBy: serving.values.sorted { ($0.keyword, $0.matchType ?? "") < ($1.keyword, $1.matchType ?? "") }
        ))
      }
      return entries.sorted { $0.metrics.spendValue > $1.metrics.spendValue }
    }

    private func percent(_ value: Double) -> String { Ads.number(value * 100, decimals: 1) + "%" }
    private func money(_ value: Double) -> String { Ads.number(value, decimals: 2) }
  }
}
