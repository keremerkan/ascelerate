import AppleAdsClient
import ArgumentParser
import AscelerateCore
import Foundation

// Report plumbing shared by `ads reports campaigns|keywords|search-terms`.
extension Ads {
  /// A report request for the range, in the ad account's time zone.
  static func reportRequest(
    start: String, end: String, filters: [Components.Schemas.Filter]? = nil,
    pagination: Components.Schemas.RequestPagination
  ) -> Components.Schemas.AppsReportingRequest {
    .init(pagination: pagination, filters: filters, timeRange: .init(start: start, end: end, timeZone: .ortz))
  }

  /// Fetches every page of a report (5,000 rows per page).
  static func reportRows<Row>(
    _ fetch: (Components.Schemas.RequestPagination) async throws -> (rows: [Row], count: Int?)
  ) async throws -> [Row] {
    let pageSize = 5000
    var rows: [Row] = []
    while true {
      let page = try await fetch(.init(offset: rows.count, pageSize: pageSize))
      rows += page.rows
      if page.rows.count < pageSize || rows.count >= (page.count ?? 0) { return rows }
    }
  }

  /// `--by` names and the report dimension each one asks Apple for.
  static let breakdowns: [String: Components.Schemas.AppsReportingRequest.GroupByPayloadPayload] = [
    "age": .ageRange, "gender": .gender, "device": .deviceClass,
    "country": .countryOrRegion, "region": .adminArea, "city": .locality,
  ]

  static let breakdownTitles = [
    "ageRange": "Age", "gender": "Gender", "deviceClass": "Device",
    "countryOrRegion": "Country", "adminArea": "Region", "locality": "City",
  ]

  /// A report row's value for a breakdown dimension.
  static func breakdownValue(
    _ field: Components.Schemas.AppsReportingRequest.GroupByPayloadPayload, of meta: Components.Schemas.AppsReportingCampaign
  ) -> String? {
    switch field {
    case .ageRange: meta.ageRange
    case .gender: meta.gender
    case .deviceClass: meta.deviceClass
    case .countryOrRegion: meta.countryOrRegion
    case .adminArea: meta.adminArea
    case .locality: meta.locality
    default: nil
    }
  }

  /// Options every report takes.
  struct ReportOptions: ParsableArguments {
    @OptionGroup var range: DateRangeOptions

    @Option(name: .long, help: "Only campaigns for this app (bundle ID or alias).")
    var app: String?

    @Option(name: .long, help: "Only this campaign (name or ID).")
    var campaign: String?

    @Flag(name: .long, help: "Include rows without impressions or spend in the range.")
    var all = false

    /// The row's metrics, or nil for a row without activity (unless `--all`).
    func metrics(_ m: Components.Schemas.AppsMetrics?) -> Metrics? {
      guard let m else { return nil }
      let metrics = Metrics(m)
      return all || metrics.impressions > 0 || metrics.spendValue > 0 ? metrics : nil
    }
  }

  /// A report row: its own columns plus the shared metrics.
  protocol ReportRow: Encodable {
    var metrics: Metrics { get }
  }

  /// A report as `--json` prints it, and its table. The total is summed from the rows, so it
  /// covers exactly what the report shows.
  struct Report<Row: ReportRow>: Encodable {
    let start: String
    let end: String
    let rows: [Row]
    let total: Metrics?

    init(start: String, end: String, rows: [Row]) {
      self.start = start
      self.end = end
      self.rows = rows
      total = Metrics.total(rows.map(\.metrics))
    }

    /// One table: leading columns from `cells`, then the metrics. With `groupedBy`, rows sit under
    /// a bold header per group. The total closes it.
    func print(headers: [String], groupedBy group: KeyPath<Row, String>?, cells: (Row) -> [String]) {
      Swift.print("\(start) – \(end)")
      Swift.print()
      guard !rows.isEmpty else {
        Swift.print("No activity in this range.")
        return
      }
      let blank = Array(repeating: "", count: headers.count + Metrics.headers.count)
      var table: [[String]] = []
      var current: String?
      for row in rows {
        let leading = cells(row)
        if let group {
          let name = row[keyPath: group]
          if name != current {
            if current != nil { table.append(blank) }
            table.append([bold(name)] + Array(repeating: "", count: blank.count - 1))
            current = name
          }
          table.append(["  " + leading[0]] + leading.dropFirst() + row.metrics.cells)
        } else {
          table.append(leading + row.metrics.cells)
        }
      }
      if let total, rows.count > 1 {
        table.append(blank)
        table.append([bold("Total")] + Array(repeating: "", count: headers.count - 1) + total.cells)
      }
      Table.print(headers: headers + Metrics.headers, rows: table)
    }
  }

  /// Numbers in the tables: grouped, English style like the rest of the output (not the user's locale).
  static func number(_ value: Double, decimals: Int = 0) -> String {
    value.formatted(.number.precision(.fractionLength(decimals)).locale(Locale(identifier: "en_US")))
  }

  /// RUNNING in green, PAUSED and the like in yellow, ON_HOLD and others in red.
  static func formatStatus(_ raw: String) -> String {
    switch raw {
    case "RUNNING", "ENABLED", "ACTIVE": green(formatState(raw))
    case "PAUSED", "NOT_RUNNING": yellow(formatState(raw))
    default: red(formatState(raw))
    }
  }

  /// A money amount as Apple sends it (decimal string + currency).
  struct Amount: Encodable {
    let amount: String
    let currency: String?

    init(_ money: Components.Schemas.Money) {
      amount = money.amount
      currency = money.currency
    }

    init(_ money: Components.Schemas.RecommendationMoney) {
      amount = money.amount
      currency = money.currency
    }

    init(value: Double, currency: String?) {
      amount = String(format: "%.4f", value)
      self.currency = currency
    }

    var value: Double { Double(amount) ?? 0 }
    var formatted: String {
      Ads.number(value, decimals: 2) + (currency.map { " \($0)" } ?? "")
    }
  }

  /// The metrics the report tables show, from Apple's App Store metrics.
  struct Metrics: Encodable {
    let spend: Amount?
    let impressions: Int64
    let taps: Int64
    /// Installs after a tap or after only seeing the ad (view-through).
    let installs: Int64
    /// Installs after a tap.
    let tapInstalls: Int64
    let ttr: Double?
    /// Tap installs per tap.
    let tapConversionRate: Double?
    /// All installs (tap and view-through) per tap; can exceed 100%.
    let totalConversionRate: Double?
    let averageCPT: Amount?
    /// Spend per install (tap and view-through).
    let averageCPI: Amount?

    init(_ m: Components.Schemas.AppsMetrics) {
      spend = m.localSpend.map(Amount.init)
      impressions = m.impressions ?? 0
      taps = m.taps ?? 0
      installs = m.totalInstalls ?? 0
      tapInstalls = m.tapInstalls ?? 0
      ttr = m.ttr
      tapConversionRate = m.tapInstallRate
      totalConversionRate = m.totalInstallRate
      // Apple sends 0 for an average with nothing to divide by.
      averageCPT = taps > 0 ? m.cpt.map(Amount.init) : nil
      averageCPI = installs > 0 ? m.totalAvgCPI.map(Amount.init) : nil
    }

    /// The sum of `rows`, with rates and averages computed the way Apple computes them.
    static func total(_ rows: [Metrics]) -> Metrics? {
      guard !rows.isEmpty else { return nil }
      return Metrics(
        spend: rows.map(\.spendValue).reduce(0, +),
        currency: rows.lazy.compactMap { $0.spend?.currency }.first,
        impressions: rows.map(\.impressions).reduce(0, +),
        taps: rows.map(\.taps).reduce(0, +),
        installs: rows.map(\.installs).reduce(0, +),
        tapInstalls: rows.map(\.tapInstalls).reduce(0, +)
      )
    }

    private init(spend: Double, currency: String?, impressions: Int64, taps: Int64, installs: Int64, tapInstalls: Int64) {
      // Four decimals, as Apple reports rates and averages.
      func ratio(_ a: Double, _ b: Int64) -> Double? { b > 0 ? (a / Double(b) * 10_000).rounded() / 10_000 : nil }
      self.spend = Amount(value: spend, currency: currency)
      self.impressions = impressions
      self.taps = taps
      self.installs = installs
      self.tapInstalls = tapInstalls
      ttr = ratio(Double(taps), impressions)
      tapConversionRate = ratio(Double(tapInstalls), taps)
      totalConversionRate = ratio(Double(installs), taps)
      averageCPT = ratio(spend, taps).map { Amount(value: $0, currency: currency) }
      averageCPI = ratio(spend, installs).map { Amount(value: $0, currency: currency) }
    }

    var spendValue: Double { spend?.value ?? 0 }

    static let headers = ["Spend", "Impressions", "Taps", "TTR", "Installs", "CR (Tap)", "CR (Total)", "Avg CPT", "Avg CPI"]

    var cells: [String] {
      func percent(_ v: Double?) -> String { v.map { Ads.number($0 * 100, decimals: 2) + "%" } ?? "-" }
      return [
        spend?.formatted ?? "-", Ads.number(Double(impressions)), Ads.number(Double(taps)), percent(ttr),
        Ads.number(Double(installs)), percent(tapConversionRate), percent(totalConversionRate),
        averageCPT?.formatted ?? "-", averageCPI?.formatted ?? "-",
      ]
    }
  }

  /// `--days N` (ending today) or `--from`/`--to`, as the API's yyyy-MM-dd dates.
  struct DateRangeOptions: ParsableArguments {
    @Option(name: .long, help: "The last N days (reports: default 7, including today; opportunities: default 30, ending yesterday).")
    var days: Int?

    @Option(name: .long, help: "Start date (YYYY-MM-DD).")
    var from: String?

    @Option(name: .long, help: "End date (YYYY-MM-DD, default: today).")
    var to: String?

    /// `defaultDays` and `endingYesterday` apply only without --from/--to (yesterday: complete days only).
    func resolved(defaultDays: Int = 7, endingYesterday: Bool = false) throws -> (start: String, end: String) {
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd"
      formatter.locale = Locale(identifier: "en_US_POSIX")
      if from != nil, days != nil {
        throw ValidationError("Use either --days or --from/--to.")
      }
      for date in [from, to].compactMap({ $0 }) where formatter.date(from: date) == nil {
        throw ValidationError("Invalid date '\(date)'. Use YYYY-MM-DD.")
      }
      let today = endingYesterday && to == nil && from == nil
        ? Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        : Date()
      let end = to ?? formatter.string(from: today)
      if let from { return (from, end) }
      let days = days ?? defaultDays
      guard days >= 1 else { throw ValidationError("--days must be at least 1.") }
      let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: formatter.date(from: end) ?? today) ?? today
      return (formatter.string(from: start), end)
    }
  }
}
