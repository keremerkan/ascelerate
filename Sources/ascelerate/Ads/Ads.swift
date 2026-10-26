import AppleAdsClient
import ArgumentParser
import AscelerateAds
import AscelerateCore
import Foundation

/// Apple Ads plumbing for the `ads` commands: the config's credentials, prompts and the dry-run
/// gate around AscelerateAds' `Ads`.
extension Ads {
  /// The `ads` section of the config, or an error pointing at `ads configure`.
  static func config() throws -> AdsConfig {
    guard let ads = try Config.load().ads else {
      throw ValidationError("No Apple Ads credentials. Run 'ascelerate ads configure' first.")
    }
    return ads
  }

  /// The `X-AP-Context` header value every ad account request needs.
  static func context(_ ads: AdsConfig) throws -> String {
    guard let id = ads.adAccountId else {
      throw ValidationError("No ad account selected. Run 'ascelerate ads configure'.")
    }
    return context(adAccountID: id)
  }

  /// Runs `body` with a client signed in with the config's credentials. Writes stop at the
  /// dry-run gate (`--dry-run`, `ASCELERATE_DRY_RUN=1`), which prints them; rate limit waits are
  /// announced on stderr.
  /// The ad account's time zone, which Apple Ads reports days in; this Mac's if it can't be read.
  static func accountTimeZone(_ ads: AdsConfig) async throws -> TimeZone {
    guard let id = ads.adAccountId else { return .current }
    let identifier = try await withClient(ads) { client in try await adAccount(id: id, client: client)?.timezone }
    return identifier.flatMap(TimeZone.init(identifier:)) ?? .current
  }

  static func withClient<T>(_ ads: AdsConfig, _ body: (Client) async throws -> T) async throws -> T {
    let pem = try String(contentsOfFile: expandPath(ads.privateKeyPath), encoding: .utf8)
    let credentials = Credentials(
      clientID: ads.clientId, teamID: ads.teamId, keyID: ads.keyId, privateKeyPEM: pem, adAccountID: ads.adAccountId)
    let options = Options(
      gateWrite: { method, path, body in
        guard ClientFactory.isDryRun else { return }
        var report = "[dry-run] \(method) \(path)"
        if let body, let json = try? JSONSerialization.jsonObject(with: body),
          let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
          report += "\n" + String(decoding: pretty, as: UTF8.self)
        }
        FileHandle.standardError.write(Data((report + "\n").utf8))
        throw adsDryRunStop(method: method, path: path)
      },
      onRateLimitWait: { wait in
        FileHandle.standardError.write(Data("Apple Ads rate limit reached; waiting \(wait) s.\n".utf8))
      }
    )
    do {
      return try await withClient(credentials, options: options, body)
    } catch var error as AdsError {
      error.credentialsHint = "Check your Apple Ads credentials (run 'ascelerate ads configure')."
      throw error
    }
  }

  static func campaigns(_ ads: AdsConfig, client: Client) async throws -> [Components.Schemas.Campaign] {
    try await campaigns(context: context(ads), client: client)
  }

  static func adGroups(campaignID: Int64, _ ads: AdsConfig, client: Client) async throws -> [Components.Schemas.AdGroup] {
    try await adGroups(campaignID: campaignID, context: context(ads), client: client)
  }

  static func keywords(campaignID: Int64, _ ads: AdsConfig, client: Client) async throws -> [Components.Schemas.Keyword] {
    try await keywords(campaignID: campaignID, context: context(ads), client: client)
  }

  static func negativeKeywords(
    campaignID: Int64, adGroupIDs: [Int64], _ ads: AdsConfig, client: Client
  ) async throws -> [Components.Schemas.NegativeKeyword] {
    try await negativeKeywords(campaignID: campaignID, adGroupIDs: adGroupIDs, context: context(ads), client: client)
  }

  /// The campaign named `ref` (case-insensitive) or with that ID; the error lists the names.
  static func find(
    campaign ref: String, in campaigns: [Components.Schemas.Campaign]
  ) throws -> Components.Schemas.Campaign {
    if let match = campaigns.first(where: { $0.id.map(String.init) == ref || $0.name?.caseInsensitiveCompare(ref) == .orderedSame }) {
      return match
    }
    let names = campaigns.compactMap(\.name).sorted().map { "  - \($0)" }.joined(separator: "\n")
    throw ValidationError("No campaign named '\(ref)'. Campaigns:\n\(names)")
  }

  /// One campaign by name or ID.
  static func campaign(_ ref: String, _ ads: AdsConfig, client: Client) async throws -> Components.Schemas.Campaign {
    try find(campaign: ref, in: await campaigns(ads, client: client))
  }

  /// The ad account's currency, read from the campaign's daily budget (Apple wants it with every amount).
  static func currency(of campaign: Components.Schemas.Campaign) throws -> String {
    guard let currency = campaign.dailyBudget?.value1.value?.currency else {
      throw ValidationError("Can't tell the currency of '\(campaign.name ?? "")'.")
    }
    return currency
  }

  /// The ad account's currency, from any of its campaigns' budgets.
  static func currencyOfAccount(_ campaigns: [Components.Schemas.Campaign]) throws -> String {
    guard let currency = campaigns.lazy.compactMap({ $0.dailyBudget?.value1.value?.currency }).first else {
      throw ValidationError("Can't tell the ad account's currency; pass --like with an existing campaign.")
    }
    return currency
  }

  /// The ad group named `ref` or with that ID; without `ref`, the only one or a picked one.
  static func adGroup(
    _ ref: String?, in groups: [Components.Schemas.AdGroup], option: String = "--ad-group"
  ) throws -> Components.Schemas.AdGroup {
    if let ref {
      if let match = groups.first(where: { $0.id.map(String.init) == ref || $0.name?.caseInsensitiveCompare(ref) == .orderedSame }) {
        return match
      }
      let names = groups.compactMap(\.name).sorted().map { "  - \($0)" }.joined(separator: "\n")
      throw ValidationError("No ad group named '\(ref)'. Ad groups:\n\(names)")
    }
    guard groups.count != 1 else { return groups[0] }
    guard !groups.isEmpty else { throw ValidationError("The campaign has no ad groups.") }
    return try promptSelection(
      "Ad groups", items: groups, display: { $0.name ?? String($0.id ?? 0) }, nonInteractiveHint: "Pass \(option)."
    )
  }

  /// `exact` or `broad` (App Store search results take only these two).
  static func matchType(_ value: String) throws -> Components.Schemas.KeywordMatchType {
    switch value.uppercased() {
    case "EXACT": .exact
    case "BROAD": .broad
    default: throw ValidationError("Invalid match type '\(value)'. Use exact or broad.")
    }
  }

  /// A positive amount as Apple takes it: a decimal string and the currency.
  static func money(_ value: String, currency: String) throws -> Components.Schemas.Money {
    let value = value.trimmingCharacters(in: .whitespaces)
    guard let amount = Double(value), amount > 0, amount.isFinite else {
      throw ValidationError("Invalid amount '\(value)'. Use a positive number like 1.25.")
    }
    return .init(amount: value, currency: currency)
  }

  /// Runs `fetch` for each campaign, four at a time (keyword and search term reports take one
  /// campaign per request), keeping the scope's campaign order.
  static func perCampaign<Row: Sendable>(
    _ scope: Scope, _ fetch: @escaping @Sendable (Int64) async throws -> [Row]
  ) async throws -> [Row] {
    try await boundedConcurrentMap(scope.campaigns.compactMap(\.id), maxConcurrent: 4, fetch).flatMap { $0 }
  }

  /// The campaigns a command works on (`--app`, `--campaign`, or all), with names for display.
  struct Scope: Sendable {
    let campaigns: [Components.Schemas.Campaign]
    /// App names by App Store app ID, from App Store Connect.
    let appNames: [String: String]
    /// Whether `--app` or `--campaign` narrowed the campaigns.
    let isNarrowed: Bool

    static func resolve(_ ads: AdsConfig, app: String?, campaign: String?) async throws -> Scope {
      let appID = try await appStoreAppID(bundleID: app)
      var campaigns = try await withClient(ads) { try await Ads.campaigns(ads, client: $0) }
      if let appID {
        campaigns = campaigns.filter { $0.promotedObjectId == appID }
        if campaigns.isEmpty { throw ValidationError("No campaigns for \(app ?? appID).") }
      }
      if let campaign {
        campaigns = [try Ads.find(campaign: campaign, in: campaigns)]
      }
      let appNames = try await appStoreAppNames()
      let key = { (c: Components.Schemas.Campaign) in (c.promotedObjectId.flatMap { appNames[$0] } ?? "", c.name ?? "") }
      return Scope(
        campaigns: campaigns.sorted { key($0) < key($1) },
        appNames: appNames,
        isNarrowed: appID != nil || campaign != nil
      )
    }

    func appName(of campaign: Components.Schemas.Campaign) -> String? {
      campaign.promotedObjectId.flatMap { appNames[$0] }
    }

    func campaignName(_ id: Int64) -> String {
      campaigns.first { $0.id == id }?.name ?? String(id)
    }

    /// Whether a report row's campaign belongs in this scope (any campaign when not narrowed).
    func contains(_ id: Int64?) -> Bool {
      !isNarrowed || campaigns.contains { $0.id == id }
    }
  }
}
