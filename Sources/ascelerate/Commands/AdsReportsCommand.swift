import AppleAdsClient
import AscelerateAds
import ArgumentParser
import AscelerateCore
import Foundation

extension AdsCommand {
  struct Reports: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Performance reports (spend, impressions, taps, installs).",
      subcommands: [CampaignsReport.self, AdGroupsReport.self, AdsReport.self, KeywordsReport.self, SearchTermsReport.self]
    )

    struct CampaignsReport: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "campaigns",
        abstract: "Performance per campaign, optionally broken down by age, gender, device or location."
      )

      @OptionGroup var options: Ads.ReportOptions

      @Option(
        name: .customLong("by"), parsing: .upToNextOption,
        help: "Break each campaign down by: \(Ads.breakdowns.keys.sorted().joined(separator: ", "))."
      )
      var by: [String] = []

      @OptionGroup var jsonOption: JSONOption

      private struct Row: Ads.ReportRow {
        let campaignId: Int64
        let campaignName: String
        let appId: String?
        let appName: String?
        let displayStatus: String?
        /// Values of the `--by` dimensions, keyed by Apple's field name (ageRange, gender, …).
        let breakdown: [String: String]?
        let metrics: Ads.Metrics
      }

      func run() async throws {
        jsonOption.activate()
        let ads = try Ads.config()
        let (start, end) = try options.range.resolved()
        let dimensions = try Ads.unique(by).map { name in
          guard let field = Ads.breakdowns[name.lowercased()] else {
            throw ValidationError("Invalid --by '\(name)'. Use: \(Ads.breakdowns.keys.sorted().joined(separator: ", ")).")
          }
          return field
        }
        let scope = try await Ads.Scope.resolve(ads, app: options.app, campaign: options.campaign)
        // Apple requires countryCode next to region (adminArea) and city (locality).
        let needsCountry = dimensions.contains { $0 == .adminArea || $0 == .locality }
        let rows = try await Ads.withClient(ads) { client in
          try await Ads.campaignReportRows(
            start: start, end: end, groupBy: dimensions.isEmpty ? [] : dimensions + (needsCountry ? [.countryCode] : []),
            context: Ads.context(ads), client: client)
        }

        let report = Ads.Report(
          start: start, end: end,
          rows: Self.merged(rows.compactMap { row -> Row? in
            guard let meta = row.metadata, scope.contains(meta.id),
              let metrics = options.metrics(row.totalMetrics?.value1)
            else { return nil }
            var breakdown: [String: String] = [:]
            for field in dimensions {
              // Apple sends unknown values both as UNKNOWN and as a missing field.
              breakdown[field.rawValue] = Ads.breakdownValue(field, of: meta) ?? "UNKNOWN"
            }
            return Row(
              campaignId: meta.id ?? 0, campaignName: meta.name ?? "-", appId: meta.promotedObjectId,
              appName: meta.promotedObjectId.flatMap { scope.appNames[$0] }, displayStatus: meta.displayStatus,
              breakdown: dimensions.isEmpty ? nil : breakdown, metrics: metrics
            )
          }).sorted {
            // Broken down: campaigns by spend, each campaign's rows by spend.
            dimensions.isEmpty || $0.campaignId == $1.campaignId
              ? $0.metrics.spendValue > $1.metrics.spendValue
              : $0.campaignName < $1.campaignName
          }
        )

        if jsonOption.json { try printJSON(report); return }
        if dimensions.isEmpty {
          report.print(
            headers: ["Campaign", "App"], groupedBy: nil,
            cells: { [$0.campaignName, $0.appName ?? $0.appId ?? "-"] }
          )
        } else {
          report.print(
            headers: dimensions.map { Ads.breakdownTitles[$0.rawValue] ?? $0.rawValue }, groupedBy: \.campaignName,
            cells: { row in
              // All-caps raw values (UNKNOWN, IPHONE) read as titles; country codes and Apple's
              // mixed-case values stay as they are.
              dimensions.map { field in
                row.breakdown?[field.rawValue].map {
                  $0 == $0.uppercased() && !($0.count == 2 && field == .countryOrRegion) ? formatState($0) : $0
                } ?? "-"
              }
            }
          )
        }
      }

      /// Rows with the same campaign and breakdown values, summed (Apple splits UNKNOWN from missing).
      private static func merged(_ rows: [Row]) -> [Row] {
        var order: [String] = []
        var groups: [String: [Row]] = [:]
        for row in rows {
          let key = "\(row.campaignId)|" + (row.breakdown ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
          if groups[key] == nil { order.append(key) }
          groups[key, default: []].append(row)
        }
        return order.compactMap { key in
          guard let rows = groups[key], let first = rows.first else { return nil }
          guard rows.count > 1, let metrics = Ads.Metrics.total(rows.map(\.metrics)) else { return first }
          return Row(
            campaignId: first.campaignId, campaignName: first.campaignName, appId: first.appId, appName: first.appName,
            displayStatus: first.displayStatus, breakdown: first.breakdown, metrics: metrics
          )
        }
      }
    }

    struct AdGroupsReport: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "adgroups",
        abstract: "Performance per ad group, by campaign (compare ad groups such as age-targeted test groups)."
      )

      @OptionGroup var options: Ads.ReportOptions
      @OptionGroup var jsonOption: JSONOption

      private struct Row: Ads.ReportRow {
        let campaignId: Int64
        let campaignName: String
        let adGroupId: Int64
        let adGroupName: String
        let displayStatus: String?
        let metrics: Ads.Metrics
      }

      func run() async throws {
        jsonOption.activate()
        let ads = try Ads.config()
        let (start, end) = try options.range.resolved()
        let scope = try await Ads.Scope.resolve(ads, app: options.app, campaign: options.campaign)
        let rows = try await Ads.withClient(ads) { client in
          try await Ads.perCampaign(scope) { campaignID in
            try await Ads.reportRows { pagination in
              let json = try await client.appsAdGroupReports(
                headers: .init(xApContext: Ads.context(ads)),
                body: .json(Ads.reportRequest(
                  start: start, end: end, filters: Ads.campaignFilter(campaignID), pagination: pagination
                ))
              ).ok.body.json
              return (json.result?.rows ?? [], json.pagination?.totalCount)
            }
          }
        }

        let report = Ads.Report(
          start: start, end: end,
          rows: rows.compactMap { row -> Row? in
            guard let meta = row.metadata, let metrics = options.metrics(row.totalMetrics?.value1) else { return nil }
            let campaignID = meta.campaignId ?? 0
            return Row(
              campaignId: campaignID, campaignName: scope.campaignName(campaignID), adGroupId: meta.id ?? 0,
              adGroupName: meta.name ?? "-", displayStatus: meta.displayStatus, metrics: metrics
            )
          }.sorted { $0.campaignId == $1.campaignId && $0.metrics.spendValue > $1.metrics.spendValue }
        )

        if jsonOption.json { try printJSON(report); return }
        report.print(headers: ["Ad Group"], groupedBy: \.campaignName, cells: { [$0.adGroupName] })
      }
    }

    struct AdsReport: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "ads",
        abstract: "Performance per ad (per product page), by campaign."
      )

      @OptionGroup var options: Ads.ReportOptions
      @OptionGroup var jsonOption: JSONOption

      private struct Row: Ads.ReportRow {
        let campaignId: Int64
        let campaignName: String
        let adGroupId: Int64?
        let adId: Int64
        let adName: String
        /// DEFAULT_PRODUCT_PAGE or CUSTOM_PRODUCT_PAGE.
        let creativeType: String?
        let displayStatus: String?
        let metrics: Ads.Metrics
      }

      func run() async throws {
        jsonOption.activate()
        let ads = try Ads.config()
        let (start, end) = try options.range.resolved()
        let scope = try await Ads.Scope.resolve(ads, app: options.app, campaign: options.campaign)
        let rows = try await Ads.withClient(ads) { client in
          try await Ads.perCampaign(scope) { campaignID in
            try await Ads.reportRows { pagination in
              let json = try await client.appsAdReports(
                headers: .init(xApContext: Ads.context(ads)),
                body: .json(Ads.reportRequest(
                  start: start, end: end, filters: Ads.campaignFilter(campaignID), pagination: pagination
                ))
              ).ok.body.json
              return (json.result?.rows ?? [], json.pagination?.totalCount)
            }
          }
        }

        let report = Ads.Report(
          start: start, end: end,
          rows: rows.compactMap { row -> Row? in
            guard let meta = row.metadata, let metrics = options.metrics(row.totalMetrics) else { return nil }
            let campaignID = meta.campaignId ?? 0
            return Row(
              campaignId: campaignID, campaignName: scope.campaignName(campaignID), adGroupId: meta.adGroupId,
              adId: meta.id ?? 0, adName: meta.name ?? "-", creativeType: meta.creative?.creativeType?.value1.rawValue,
              displayStatus: meta.displayStatus, metrics: metrics
            )
          }.sorted { $0.campaignId == $1.campaignId && $0.metrics.spendValue > $1.metrics.spendValue }
        )

        if jsonOption.json { try printJSON(report); return }
        report.print(
          headers: ["Ad", "Product Page"], groupedBy: \.campaignName,
          cells: { [$0.adName, $0.creativeType == "CUSTOM_PRODUCT_PAGE" ? "Custom" : "Default"] }
        )
      }
    }

    struct KeywordsReport: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "keywords",
        abstract: "Performance per keyword, by campaign, with Apple's suggested bid."
      )

      @OptionGroup var options: Ads.ReportOptions
      @OptionGroup var jsonOption: JSONOption

      private struct Row: Ads.ReportRow {
        let campaignId: Int64
        let campaignName: String
        let adGroupId: Int64?
        let adGroupName: String?
        let keywordId: Int64?
        let keyword: String
        let matchType: String?
        let displayStatus: String?
        let bid: Ads.Amount?
        let suggestedBid: Double?
        let metrics: Ads.Metrics
      }

      func run() async throws {
        jsonOption.activate()
        let ads = try Ads.config()
        let (start, end) = try options.range.resolved()
        let scope = try await Ads.Scope.resolve(ads, app: options.app, campaign: options.campaign)
        let rows = try await Ads.withClient(ads) { client in
          try await Ads.perCampaign(scope) { campaignID in
            try await Ads.reportRows { pagination in
              let json = try await client.appsKeywordReports(
                headers: .init(xApContext: Ads.context(ads)),
                body: .json(Ads.reportRequest(
                  start: start, end: end, filters: Ads.campaignFilter(campaignID), pagination: pagination
                ))
              ).ok.body.json
              return (json.result?.rows ?? [], json.pagination?.totalCount)
            }
          }
        }

        let report = Ads.Report(
          start: start, end: end,
          rows: rows.compactMap { row -> Row? in
            guard let meta = row.metadata, let metrics = options.metrics(row.totalMetrics) else { return nil }
            let campaignID = meta.campaignId ?? 0
            return Row(
              campaignId: campaignID, campaignName: scope.campaignName(campaignID),
              adGroupId: meta.adGroupId, adGroupName: meta.adGroup?.name,
              keywordId: meta.id, keyword: meta.text ?? "-", matchType: meta.matchType?.rawValue,
              displayStatus: meta.displayStatus, bid: meta.bid.map(Ads.Amount.init),
              suggestedBid: row.insights?.bidRecommendation?.suggestedBidAmount, metrics: metrics
            )
          }.sorted { ($0.campaignId == $1.campaignId) && $0.metrics.spendValue > $1.metrics.spendValue }
        )

        if jsonOption.json { try printJSON(report); return }
        report.print(
          headers: ["Keyword", "Match", "Bid", "Suggested"], groupedBy: \.campaignName,
          cells: { row in
            let suggested: String = row.suggestedBid.map { Ads.number($0, decimals: 2) } ?? "-"
            return [row.keyword, row.matchType.map { formatState($0) } ?? "-", row.bid?.formatted ?? "-", suggested]
          }
        )
      }
    }

    struct SearchTermsReport: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "search-terms",
        abstract: "What people searched for when your ads showed, by campaign, with the keyword that matched."
      )

      @OptionGroup var options: Ads.ReportOptions
      @OptionGroup var jsonOption: JSONOption

      private struct Row: Ads.ReportRow {
        let campaignId: Int64
        let campaignName: String
        let adGroupId: Int64?
        let adGroupName: String?
        /// Nil when Apple withholds a low-volume term.
        let searchTerm: String?
        let source: String?
        let keywordId: Int64?
        let keyword: String?
        let matchType: String?
        let metrics: Ads.Metrics
      }

      func run() async throws {
        jsonOption.activate()
        let ads = try Ads.config()
        let (start, end) = try options.range.resolved()
        let scope = try await Ads.Scope.resolve(ads, app: options.app, campaign: options.campaign)
        let rows = try await Ads.withClient(ads) { client in
          try await Ads.perCampaign(scope) { campaignID in
            try await Ads.reportRows { pagination in
              let json = try await client.appsSearchTermReports(
                headers: .init(xApContext: Ads.context(ads)),
                body: .json(Ads.reportRequest(
                  start: start, end: end, filters: Ads.campaignFilter(campaignID), pagination: pagination
                ))
              ).ok.body.json
              return (json.result?.rows ?? [], json.pagination?.totalCount)
            }
          }
        }

        let report = Ads.Report(
          start: start, end: end,
          rows: rows.compactMap { row -> Row? in
            guard let meta = row.metadata, let metrics = options.metrics(row.totalMetrics) else { return nil }
            let campaignID = meta.campaignId ?? 0
            return Row(
              campaignId: campaignID, campaignName: scope.campaignName(campaignID),
              adGroupId: meta.adGroupId, adGroupName: meta.adGroup?.name,
              searchTerm: meta.searchTermText, source: meta.searchTermSource,
              keywordId: meta.keyword?.id, keyword: meta.keyword?.text, matchType: meta.keyword?.matchType?.rawValue,
              metrics: metrics
            )
          }.sorted { ($0.campaignId == $1.campaignId) && $0.metrics.spendValue > $1.metrics.spendValue }
        )

        if jsonOption.json { try printJSON(report); return }
        report.print(
          headers: ["Search Term", "Keyword", "Match", "Source"], groupedBy: \.campaignName,
          cells: { row in
            [
              row.searchTerm ?? "(low volume)", row.keyword ?? "-", row.matchType.map { formatState($0) } ?? "-",
              row.source.map { formatState($0) } ?? "-",
            ]
          }
        )
      }
    }
  }
}
