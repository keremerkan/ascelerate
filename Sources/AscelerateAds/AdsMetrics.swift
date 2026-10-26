import AppleAdsClient
import Foundation

extension Ads {
  /// A money amount as Apple sends it (decimal string + currency).
  public struct Amount: Encodable, Sendable {
    public let amount: String
    public let currency: String?

    public init(_ money: Components.Schemas.Money) {
      amount = money.amount
      currency = money.currency
    }

    public init(_ money: Components.Schemas.RecommendationMoney) {
      amount = money.amount
      currency = money.currency
    }

    public init(value: Double, currency: String?) {
      amount = String(format: "%.4f", value)
      self.currency = currency
    }

    public var value: Double { Double(amount) ?? 0 }
  }

  /// A report row's metrics, from Apple's App Store metrics.
  public struct Metrics: Encodable, Sendable {
    public let spend: Amount?
    public let impressions: Int64
    public let taps: Int64
    /// Installs after a tap or after only seeing the ad (view-through).
    public let installs: Int64
    /// Installs after a tap.
    public let tapInstalls: Int64
    public let ttr: Double?
    /// Tap installs per tap.
    public let tapConversionRate: Double?
    /// All installs (tap and view-through) per tap; can exceed 100%.
    public let totalConversionRate: Double?
    public let averageCPT: Amount?
    /// Spend per install (tap and view-through).
    public let averageCPI: Amount?
    /// Installs after only seeing the ad.
    public let viewInstalls: Int64
    public let newDownloads: Int64
    public let redownloads: Int64
    public let preOrders: Int64
    /// Spend per 1,000 impressions.
    public let averageCPM: Amount?
    /// Spend per tap install.
    public let tapInstallCPI: Amount?

    public init(_ m: Components.Schemas.AppsMetrics) {
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
      viewInstalls = m.viewInstalls ?? 0
      newDownloads = m.totalNewDownloads ?? 0
      redownloads = m.totalRedownloads ?? 0
      preOrders = m.totalPreOrdersPlaced ?? 0
      averageCPM = impressions > 0 ? m.cpm.map(Amount.init) : nil
      tapInstallCPI = tapInstalls > 0 ? m.tapInstallCPI.map(Amount.init) : nil
    }

    /// The sum of `rows`, with rates and averages computed the way Apple computes them.
    public static func total(_ rows: [Metrics]) -> Metrics? {
      guard !rows.isEmpty else { return nil }
      return Metrics(
        spend: rows.map(\.spendValue).reduce(0, +),
        currency: rows.lazy.compactMap { $0.spend?.currency }.first,
        impressions: rows.map(\.impressions).reduce(0, +),
        taps: rows.map(\.taps).reduce(0, +),
        installs: rows.map(\.installs).reduce(0, +),
        tapInstalls: rows.map(\.tapInstalls).reduce(0, +),
        viewInstalls: rows.map(\.viewInstalls).reduce(0, +),
        newDownloads: rows.map(\.newDownloads).reduce(0, +),
        redownloads: rows.map(\.redownloads).reduce(0, +),
        preOrders: rows.map(\.preOrders).reduce(0, +)
      )
    }

    private init(
      spend: Double, currency: String?, impressions: Int64, taps: Int64, installs: Int64, tapInstalls: Int64,
      viewInstalls: Int64, newDownloads: Int64, redownloads: Int64, preOrders: Int64
    ) {
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
      self.viewInstalls = viewInstalls
      self.newDownloads = newDownloads
      self.redownloads = redownloads
      self.preOrders = preOrders
      averageCPM = ratio(spend * 1000, impressions).map { Amount(value: $0, currency: currency) }
      tapInstallCPI = ratio(spend, tapInstalls).map { Amount(value: $0, currency: currency) }
    }

    public var spendValue: Double { spend?.value ?? 0 }
  }

  /// The first and last day (yyyy-MM-dd) of the `count` days ending today, or yesterday with
  /// `endingYesterday` (complete days only), in `timeZone`.
  public static func days(count: Int, endingYesterday: Bool = false, in timeZone: TimeZone) -> (start: String, end: String) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let now = Date()
    let end = endingYesterday ? calendar.date(byAdding: .day, value: -1, to: now) ?? now : now
    let start = calendar.date(byAdding: .day, value: -(count - 1), to: end) ?? end
    let format = Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day().dateSeparator(.dash)
    return (start.formatted(format), end.formatted(format))
  }
}

extension Components.Schemas.Money {
  /// An amount as Apple takes it: a plain decimal ("0.6", "150"), whatever the user's locale.
  public init(_ amount: Double, currency: String) {
    self.init(
      amount: amount.formatted(.number.grouping(.never).precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX"))),
      currency: currency)
  }
}
