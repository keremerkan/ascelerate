import AppleAdsClient
import ArgumentParser
import AscelerateCore
import Foundation
import OpenAPIRuntime

extension AdsCommand.Keywords {
  // MARK: - Suggestions

  struct Suggest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Apple's keyword suggestions for an app, by popularity, marking the ones you already target."
    )

    @Option(name: .long, help: "The app (bundle ID or alias).")
    var app: String

    @Option(name: .customLong("country"), parsing: .upToNextOption, help: "Storefronts (e.g. US GB); default: all.")
    var countries: [String] = []

    @Option(name: .customLong("seed"), parsing: .upToNextOption, help: "Search terms to base the suggestions on.")
    var seeds: [String] = []

    @Option(name: .long, help: "Number of suggestions (default: 50).")
    var limit = 50

    @OptionGroup var jsonOption: JSONOption

    private struct Entry: Encodable {
      let text: String
      /// Apple's popularity score, 0–100.
      let popularity: Int?
      /// Campaigns of the app that already have this keyword (any match type).
      let targetedIn: [String]
    }

    func run() async throws {
      jsonOption.activate()
      let ads = try Ads.config()
      let app = try await appStoreApp(bundleID: self.app)
      let (suggestions, targeted) = try await Ads.withClient(ads) { client in
        var filters = Ads.recommendationFilters(app: app.id)
        if !countries.isEmpty {
          filters.append(.init(field: "countriesOrRegions", _operator: ._in, value: countries.map { $0.uppercased() }))
        }
        if !seeds.isEmpty { filters.append(.init(field: "terms", _operator: ._in, value: seeds)) }
        let suggestions = try await client.queryKeywordSuggestions(
          headers: .init(xApContext: Ads.context(ads)),
          body: .json(.init(
            // Apple's docs suggest sorting by popularity, but the API rejects it ("not queryable").
            pagination: .init(offset: 0, pageSize: Int32(limit)),
            filters: filters
          ))
        ).ok.body.json.value2.result ?? []
        return (suggestions, try await Ads.targetedKeywords(app: app.id, ads, client: client))
      }

      let entries = suggestions.compactMap { s -> Entry? in
        guard let text = s.text else { return nil }
        return Entry(text: text, popularity: s.popularity.map(Int.init), targetedIn: targeted[text.lowercased()] ?? [])
      }.sorted { ($0.popularity ?? -1) > ($1.popularity ?? -1) }
      if jsonOption.json { try printJSON(entries); return }
      print("Keyword suggestions for \(app.name)" + (countries.isEmpty ? "" : " (\(countries.joined(separator: ", ")))"))
      print()
      Table.print(
        headers: ["Keyword", "Popularity", "Already Targeted In"],
        rows: entries.map { [$0.text, $0.popularity.map(String.init) ?? "-", $0.targetedIn.joined(separator: ", ")] }
      )
    }
  }

  // MARK: - Popularity

  struct Popularity: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "The most searched terms in a storefront and genre, or the popularity of given terms."
    )

    @Option(name: .customLong("country"), parsing: .upToNextOption, help: "Storefronts (e.g. US).")
    var countries: [String]

    @Option(name: .long, help: "Genre: \(Ads.genres.joined(separator: ", ")).")
    var genre: String?

    @Option(name: .long, help: "Use this app's genre (bundle ID or alias) instead of --genre.")
    var app: String?

    @Option(name: .customLong("term"), parsing: .upToNextOption, help: "Only these search terms.")
    var terms: [String] = []

    @Option(name: .long, help: "Only search terms containing this text.")
    var contains: String?

    @Flag(name: .long, help: "Last full month instead of the last full week (Sunday to Saturday).")
    var monthly = false

    @Option(name: .long, help: "Number of rows (default: 100).")
    var limit = 100

    @OptionGroup var jsonOption: JSONOption

    private struct Report: Encodable {
      let start: String
      let end: String
      let genre: String
      let rows: [Row]
      /// `--term`s Apple didn't return: not in this genre's ranked list (less popular there, or ranked under another genre).
      let unranked: [String]
    }

    private struct Row: Encodable {
      let searchTerm: String
      let countryOrRegion: String?
      let rankInGenre: Int?
      /// 1–100 within the genre.
      let popularityInGenre: Int?
      /// 1–100 across all genres of the storefront.
      let popularity: Int?
      /// 1–5, as Apple Ads shows popularity.
      let popularityTier: Int?
    }

    func run() async throws {
      jsonOption.activate()
      guard !countries.isEmpty else { throw ValidationError("Pass at least one --country.") }
      let genre = try await resolveGenre()
      let (start, end) = monthly ? Ads.lastFullMonth() : Ads.lastFullWeek()
      let ads = try Ads.config()

      var filters: [Components.Schemas.Filter] = [
        try .init(field: "countryOrRegion", _operator: ._in, value: .init(unvalidatedValue: countries.map { $0.uppercased() })),
        try .init(field: "genre", _operator: .equals, value: .init(unvalidatedValue: genre)),
      ]
      if !terms.isEmpty {
        filters.append(try .init(field: "searchTerm", _operator: ._in, value: .init(unvalidatedValue: terms)))
      }
      if let contains {
        filters.append(try .init(field: "searchTerm", _operator: .contains, value: .init(unvalidatedValue: contains)))
      }
      let rows = try await Ads.withClient(ads) { client in
        try await client.searchTermPopularityQuery(
          headers: .init(xApContext: Ads.context(ads)),
          body: .json(.init(
            filters: filters,
            sorting: [.init(field: "rankInGenre", order: .asc)],
            timeRange: .init(start: start, end: end, timeZone: .utc, granularity: monthly ? .monthly : .weeklySunSat),
            pagination: .init(offset: 0, pageSize: limit)
          ))
        ).ok.body.json.result?.rows ?? []
      }

      let returned = Set(rows.compactMap { $0.searchTerm?.lowercased() })
      let report = Report(
        start: start, end: end, genre: genre,
        rows: rows.compactMap { r in
          r.searchTerm.map {
            Row(
              searchTerm: $0, countryOrRegion: r.countryOrRegion, rankInGenre: r.rankInGenre,
              popularityInGenre: r.searchPopularityInGenre, popularity: r.searchPopularity1to100,
              popularityTier: r.searchPopularity1to5
            )
          }
        },
        unranked: Ads.unique(terms).filter { !returned.contains($0.lowercased()) }
      )
      if jsonOption.json { try printJSON(report); return }
      defer {
        if !report.unranked.isEmpty {
          print("\nNot in this genre's ranked list: \(report.unranked.joined(separator: ", "))")
        }
      }
      print("\(formatState(genre)), \(countries.joined(separator: ", ")): \(start) – \(end)")
      print()
      let multiple = countries.count > 1
      Table.print(
        headers: ["Rank", "Search Term"] + (multiple ? ["Country"] : []) + ["Popularity", "In Genre", "Tier (1–5)"],
        rows: report.rows.map { r in
          [r.rankInGenre.map(String.init) ?? "-", r.searchTerm] + (multiple ? [r.countryOrRegion ?? "-"] : [])
            + [r.popularity.map(String.init) ?? "-", r.popularityInGenre.map(String.init) ?? "-", r.popularityTier.map(String.init) ?? "-"]
        }
      )
    }

    private func resolveGenre() async throws -> String {
      if let genre {
        guard Ads.genres.contains(genre.uppercased()) else {
          throw ValidationError("Invalid genre '\(genre)'. Valid genres: \(Ads.genres.joined(separator: ", ")).")
        }
        return genre.uppercased()
      }
      guard let app else { throw ValidationError("Pass --genre or --app.") }
      let info = try await appStoreApp(bundleID: app)
      guard let category = info.primaryCategory, let genre = Ads.genre(forCategory: category) else {
        throw ValidationError(
          "No Apple Ads genre for \(info.name)'s category (\(info.primaryCategory ?? "none")). Pass --genre: \(Ads.genres.joined(separator: ", "))."
        )
      }
      return genre
    }
  }
}

extension AdsCommand {
  // MARK: - Impression share

  struct Insights: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Market insights: your share of ad impressions per search term.",
      subcommands: [ImpressionShare.self]
    )

    struct ImpressionShare: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "impression-share",
        abstract: "How often your ad showed per search term, your rank among advertisers and the term's popularity."
      )

      @Option(name: .long, help: "The app (bundle ID or alias).")
      var app: String

      @Option(name: .customLong("country"), parsing: .upToNextOption, help: "Storefronts (e.g. US); default: all.")
      var countries: [String] = []

      @Option(name: .customLong("term"), parsing: .upToNextOption, help: "Only these search terms.")
      var terms: [String] = []

      @Option(name: .long, help: "Full weeks (Sunday to Saturday) to cover, 1–4 (default: 1).")
      var weeks = 1

      @Flag(name: .long, help: "The first ad position only, instead of all positions.")
      var firstSlot = false

      @Option(name: .long, help: "Number of rows (default: 200).")
      var limit = 200

      @OptionGroup var jsonOption: JSONOption

      private struct Row: Encodable {
        let searchTerm: String
        let countryOrRegion: String?
        let week: String?
        /// The share as Apple gives it: a range, equal ends below 90%, 0.91–1.0 above.
        let lowImpressionShare: Double?
        let highImpressionShare: Double?
        /// Your position among advertisers by impression share (1 = highest).
        let rank: Int?
        let popularityTier: Int?
      }

      func run() async throws {
        jsonOption.activate()
        guard (1...4).contains(weeks) else { throw ValidationError("--weeks must be 1 to 4.") }
        let ads = try Ads.config()
        let app = try await appStoreApp(bundleID: self.app)
        let (start, end) = Ads.lastFullWeek(weeks: weeks)

        var filters: [Components.Schemas.Filter] = [
          try .init(field: "promotedObjectId", _operator: ._in, value: .init(unvalidatedValue: [app.id]))
        ]
        if !countries.isEmpty {
          filters.append(try .init(field: "countryOrRegion", _operator: ._in, value: .init(unvalidatedValue: countries.map { $0.uppercased() })))
        }
        if !terms.isEmpty {
          filters.append(try .init(field: "searchTerm", _operator: ._in, value: .init(unvalidatedValue: terms)))
        }
        // Decoded here: Apple sends `promotedObjectId` as a number where its spec says string.
        struct Response: Decodable {
          struct Result: Decodable { let rows: [RawRow]? }
          let result: Result?
        }
        struct RawRow: Decodable {
          let week: String?
          let countryOrRegion: String?
          let searchTerm: String?
          let lowImpressionShare: Double?
          let highImpressionShare: Double?
          let rank: Int?
          let searchPopularity1to5: Int?
        }
        let rows = try await Ads.withClient(ads) { client in
          try await Ads.decodeRaw(Response.self) {
            _ = try await client.impressionShareQuery(
              headers: .init(xApContext: Ads.context(ads)),
              body: .json(.init(
                filters: filters,
                sorting: [.init(field: "searchPopularity1to5", order: .desc), .init(field: "highImpressionShare", order: .desc)],
                timeRange: .init(start: start, end: end, timeZone: .utc, granularity: .weeklySunSat),
                pagination: .init(offset: 0, pageSize: limit),
                options: .init(impressionShareReportType: firstSlot ? .firstSlot : .allSlots)
              ))
            )
          }.result?.rows ?? []
        }.compactMap { r in
          r.searchTerm.map {
            Row(
              searchTerm: $0, countryOrRegion: r.countryOrRegion, week: r.week,
              lowImpressionShare: r.lowImpressionShare, highImpressionShare: r.highImpressionShare,
              rank: r.rank, popularityTier: r.searchPopularity1to5
            )
          }
        }

        if jsonOption.json { try printJSON(rows); return }
        print("\(app.name), \(firstSlot ? "first position" : "all positions"): \(start) – \(end)")
        print()
        func percent(_ v: Double?) -> String { v.map { String(Int(($0 * 100).rounded())) } ?? "?" }
        Table.print(
          headers: ["Search Term", "Country"] + (weeks > 1 ? ["Week"] : []) + ["Impression Share", "Rank", "Popularity (1–5)"],
          rows: rows.map { r in
            let share = r.lowImpressionShare == r.highImpressionShare
              ? percent(r.lowImpressionShare) + "%"
              : percent(r.lowImpressionShare) + "–" + percent(r.highImpressionShare) + "%"
            return [r.searchTerm, r.countryOrRegion ?? "-"] + (weeks > 1 ? [r.week ?? "-"] : [])
              + [share, r.rank.map(String.init) ?? "-", r.popularityTier.map(String.init) ?? "-"]
          }
        )
      }
    }
  }

  // MARK: - Recommendations

  struct Recommendations: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Apple's recommendations: daily budget increases and target CPA changes (list, apply, dismiss).",
      subcommands: [List.self, Apply.self, Dismiss.self],
      defaultSubcommand: List.self
    )

    struct Entry: Encodable {
      let id: String
      /// DAILY_BUDGET or TARGET_CPA.
      let kind: String
      let appId: String
      let campaignId: Int64?
      let campaignName: String?
      let current: Ads.Amount?
      let recommended: Ads.Amount?
      /// Last period's results and what Apple expects with the recommendation.
      let installs: Int64?
      let expectedInstalls: Int64?
      let spend: Ads.Amount?
      let expectedSpend: Ads.Amount?
      let averageCPA: Ads.Amount?
      let expectedCPA: Ads.Amount?
      let expirationTime: Date?

      var label: String {
        let what = kind == "DAILY_BUDGET" ? "daily budget" : "target CPA"
        return "\(campaignName ?? "-"): \(what) \(current?.formatted ?? "-") → \(recommended?.formatted ?? "-")"
      }
    }

    /// Apple sends 0 for an expectation it has no estimate for.
    private static func expected(_ value: Int64?) -> Int64? { value == 0 ? nil : value }
    private static func expected(_ money: Components.Schemas.RecommendationMoney?) -> Ads.Amount? {
      money.map(Ads.Amount.init).flatMap { $0.value == 0 ? nil : $0 }
    }

    /// The open (AVAILABLE) recommendations of the scope's apps, for its campaigns.
    static func open(_ ads: AdsConfig, scope: Ads.Scope, client: Client) async throws -> [Entry] {
      var entries: [Entry] = []
      for appID in Set(scope.campaigns.compactMap(\.promotedObjectId)).sorted() {
        let body = Components.Schemas.RecommendationQueryRequest(
          pagination: .init(offset: 0, pageSize: 1000),
          filters: Ads.recommendationFilters(app: appID) + [.init(field: "state", _operator: .equals, value: ["AVAILABLE"])]
        )
        let budgets = try await client.queryDailyBudgetRecommendations(
          headers: .init(xApContext: Ads.context(ads)), body: .json(body)
        ).ok.body.json.value2.result ?? []
        let cpas = try await client.queryTargetCpaRecommendations(
          headers: .init(xApContext: Ads.context(ads)), body: .json(body)
        ).ok.body.json.value2.result ?? []
        entries += budgets.map { r in
          Entry(
            id: r.id ?? "-", kind: "DAILY_BUDGET", appId: appID, campaignId: r.campaignId, campaignName: r.campaignName,
            current: r.dailyBudget.map(Ads.Amount.init), recommended: r.suggestedDailyBudgetAmount.map(Ads.Amount.init),
            installs: r.installs, expectedInstalls: expected(r.expectedInstalls), spend: r.spend.map(Ads.Amount.init),
            expectedSpend: expected(r.expectedSpend), averageCPA: r.averageCPA.map(Ads.Amount.init),
            expectedCPA: expected(r.expectedCpa), expirationTime: r.expirationTime
          )
        }
        entries += cpas.map { r in
          Entry(
            id: r.id ?? "-", kind: "TARGET_CPA", appId: appID, campaignId: r.campaignId, campaignName: r.campaignName,
            current: r.bidStrategy?.bidAmount.map(Ads.Amount.init), recommended: r.recommendedTargetCPA.map(Ads.Amount.init),
            installs: r.installs, expectedInstalls: expected(r.expectedInstalls), spend: r.spend.map(Ads.Amount.init),
            expectedSpend: expected(r.expectedSpend), averageCPA: r.averageCPA.map(Ads.Amount.init),
            expectedCPA: expected(r.expectedCPA), expirationTime: r.expirationTime
          )
        }
      }
      return entries.filter { scope.contains($0.campaignId) }
    }

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "List Apple's open recommendations with the expected outcome.")

      @Option(name: .long, help: "Only campaigns for this app (bundle ID or alias).")
      var app: String?

      @OptionGroup var jsonOption: JSONOption

      func run() async throws {
        jsonOption.activate()
        let ads = try Ads.config()
        let scope = try await Ads.Scope.resolve(ads, app: app, campaign: nil)
        let entries = try await Ads.withClient(ads) { try await Recommendations.open(ads, scope: scope, client: $0) }

        if jsonOption.json { try printJSON(entries); return }
        guard !entries.isEmpty else {
          print("No open recommendations.")
          return
        }
        Table.print(
          headers: ["ID", "Campaign", "Recommendation", "Current", "Recommended", "Installs → Expected", "Spend → Expected", "CPA → Expected"],
          rows: entries.map { e in
            let installs = "\(e.installs.map { Ads.number(Double($0)) } ?? "-") → \(e.expectedInstalls.map { Ads.number(Double($0)) } ?? "-")"
            let spend = "\(e.spend?.formatted ?? "-") → \(e.expectedSpend?.formatted ?? "-")"
            let cpa = "\(e.averageCPA?.formatted ?? "-") → \(e.expectedCPA?.formatted ?? "-")"
            return [
              e.id, e.campaignName ?? "-", e.kind == "DAILY_BUDGET" ? "Daily budget" : "Target CPA",
              e.current?.formatted ?? "-", e.recommended?.formatted ?? "-", installs, spend, cpa,
            ]
          }
        )
      }
    }

    struct Apply: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Apply recommendations (Apple changes the campaign's budget or target CPA).")
      @Argument(help: "Recommendation IDs (from 'ads recommendations').") var ids: [String]
      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.") var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        try await act(ids: ids, verb: "Apply", done: "Applied", apply: true)
      }
    }

    struct Dismiss: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Dismiss recommendations (no change; Apple stops offering them).")
      @Argument(help: "Recommendation IDs (from 'ads recommendations').") var ids: [String]
      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.") var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        try await act(ids: ids, verb: "Dismiss", done: "Dismissed", apply: false)
      }
    }

    private static func act(ids: [String], verb: String, done: String, apply: Bool) async throws {
      let ads = try Ads.config()
      let scope = try await Ads.Scope.resolve(ads, app: nil, campaign: nil)
      try await Ads.withClient(ads) { client in
        let open = try await Recommendations.open(ads, scope: scope, client: client)
        let targets = try Ads.unique(ids).map { id in
          guard let entry = open.first(where: { $0.id == id }) else {
            throw ValidationError("No open recommendation \(id). See 'ascelerate ads recommendations'.")
          }
          return entry
        }
        print("\(verb) \(targets.count) recommendation(s):")
        for e in targets { print("  \(e.label)") }
        guard confirm("\(verb)? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        for e in targets {
          let context = try Ads.context(ads)
          // Under dry run every request is shown, not only the first.
          guard try await unlessDryRunStopped({
            switch (e.kind == "DAILY_BUDGET", apply) {
            case (true, true):
              _ = try await client.applyDailyBudgetRecommendations(
                headers: .init(xApContext: context), body: .json([.init(id: e.id, promotedObjectId: e.appId, promotedObjectType: "APPSTORE_APP")])
              ).ok
            case (true, false):
              _ = try await client.dismissDailyBudgetRecommendations(
                headers: .init(xApContext: context), body: .json([.init(id: e.id, promotedObjectId: e.appId, promotedObjectType: "APPSTORE_APP")])
              ).ok
            case (false, true):
              _ = try await client.applyTargetCpaRecommendations(
                headers: .init(xApContext: context), body: .json([.init(id: e.id, promotedObjectId: e.appId, promotedObjectType: "APPSTORE_APP")])
              ).ok
            case (false, false):
              _ = try await client.dismissTargetCpaRecommendations(
                headers: .init(xApContext: context), body: .json([.init(id: e.id, promotedObjectId: e.appId, promotedObjectType: "APPSTORE_APP")])
              ).ok
            }
          }) != nil else { continue }
          print(green(done) + " \(e.label).")
        }
      }
    }
  }
}

extension Ads {
  /// Apple Ads search term genres (search term popularity).
  static let genres = [
    "BUSINESS", "EDUCATION", "ENTERTAINMENT", "FINANCE", "FOOD_DRINK", "GAMES", "HEALTH_FITNESS", "LIFESTYLE",
    "NEW_PUBLICATION", "PHOTO_VIDEO", "PRODUCTIVITY_UTILITIES", "SHOPPING", "SOCIAL_NETWORKING", "SPORTS", "TRAVEL",
  ]

  /// The Apple Ads genre of an App Store category ID, where one clearly corresponds.
  static func genre(forCategory category: String) -> String? {
    if category.hasPrefix("GAMES") { return "GAMES" }
    switch category {
    case "BUSINESS", "EDUCATION", "ENTERTAINMENT", "FINANCE", "LIFESTYLE", "SHOPPING", "SOCIAL_NETWORKING", "SPORTS", "TRAVEL":
      return category
    case "FOOD_AND_DRINK": return "FOOD_DRINK"
    case "HEALTH_AND_FITNESS": return "HEALTH_FITNESS"
    case "PHOTO_AND_VIDEO": return "PHOTO_VIDEO"
    case "PRODUCTIVITY", "UTILITIES": return "PRODUCTIVITY_UTILITIES"
    default: return nil
    }
  }

  /// The filters every recommendation and suggestion query needs: the app as promoted object.
  static func recommendationFilters(app: String) -> [Components.Schemas.RecommendationFilterCondition] {
    [
      .init(field: "promotedObjectId", _operator: .equals, value: [app]),
      .init(field: "promotedObjectType", _operator: .equals, value: ["APPSTORE_APP"]),
    ]
  }

  /// The app's keywords across its campaigns: lowercased text → campaign names.
  static func targetedKeywords(app: String, _ ads: AdsConfig, client: Client) async throws -> [String: [String]] {
    let campaigns = try await Ads.campaigns(ads, client: client).filter { $0.promotedObjectId == app }
    let scope = Scope(campaigns: campaigns, appNames: [:], isNarrowed: true)
    let keywords = try await perCampaign(scope) { try await Ads.keywords(campaignID: $0, ads, client: client) }
    var targeted: [String: [String]] = [:]
    for keyword in keywords {
      guard let text = keyword.text?.lowercased() else { continue }
      let name = scope.campaignName(keyword.campaignId ?? 0)
      if !(targeted[text]?.contains(name) ?? false) { targeted[text, default: []].append(name) }
    }
    return targeted
  }

  /// The last full week, Sunday to Saturday (ending before today), or `weeks` of them, as yyyy-MM-dd.
  static func lastFullWeek(weeks: Int = 1) -> (start: String, end: String) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let today = calendar.startOfDay(for: Date())
    // weekday: 1 = Sunday … 7 = Saturday; days back to the last Saturday before today.
    let back = (calendar.component(.weekday, from: today) % 7) + (calendar.component(.weekday, from: today) == 7 ? 7 : 0)
    let end = calendar.date(byAdding: .day, value: -back, to: today)!
    let start = calendar.date(byAdding: .day, value: -(7 * weeks - 1), to: end)!
    return (utcDay(start), utcDay(end))
  }

  /// The last full calendar month, as yyyy-MM-dd.
  static func lastFullMonth() -> (start: String, end: String) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
    let start = calendar.date(byAdding: .month, value: -1, to: thisMonth)!
    let end = calendar.date(byAdding: .day, value: -1, to: thisMonth)!
    return (utcDay(start), utcDay(end))
  }

  private static func utcDay(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: date)
  }
}
