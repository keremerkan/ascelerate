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

    public var spendValue: Double { spend?.value ?? 0 }
  }
}
