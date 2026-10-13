import AppleAdsClient
import ArgumentParser
import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// Apple Ads Platform API plumbing for the `ads` commands, on Apple's `AppleAdsClient`.
enum Ads {
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
    return XApContext(adAccountID: id).rawValue
  }

  /// Runs `body` with an authenticated client. Failures come out as `AdsError`, not wrapped in
  /// the runtime's `ClientError` (whose description dumps the whole request).
  static func withClient<T>(_ ads: AdsConfig, _ body: (Client) async throws -> T) async throws -> T {
    let pem = try String(contentsOfFile: expandPath(ads.privateKeyPath), encoding: .utf8)
    do {
      return try await AppleAdsClient.withClient(
        configuration: .init(
          clientId: ads.clientId,
          authMode: .key(teamId: ads.teamId, keyId: ads.keyId, privateKeyPEM: pem),
          // The SDK's 5 s default timed out against appleid.apple.com in normal use.
          authTimeout: .seconds(30),
          middleware: [Middleware()]
        ),
        transport: URLSessionTransport(),
        body: body
      )
    } catch {
      let underlying = (error as? ClientError)?.underlyingError ?? error
      if let auth = underlying as? AppleAdsAuthError {
        throw AdsError(status: nil, code: nil, message: auth.description, details: [])
      }
      if underlying is DecodingError {
        throw AdsError(status: nil, code: "UNEXPECTED_RESPONSE", message: "\(underlying)", details: [])
      }
      throw underlying
    }
  }

  /// All campaigns of the ad account (deleted ones left out).
  static func campaigns(_ ads: AdsConfig, client: Client) async throws -> [Components.Schemas.Campaign] {
    try await query(Components.Schemas.Campaign.self) { pagination in
      try await client.postCampaignsQuery(
        headers: .init(xApContext: context(ads)),
        body: .json(.init(pagination: pagination))
      ).ok.body.json.value1
    }.filter { $0.deleted != true }
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

  /// The automated ad group a Max Conversions campaign requires: Search Match, no keywords. The API
  /// rejects a bid strategy ("AdGroup cannot have a bid strategy") and a start time on it, although a
  /// web-created one reads back with both.
  static func automatedAdGroup(campaignID: Int64) -> Components.Schemas.AdGroupCreate {
    .init(
      name: "Automated", campaignId: campaignID, pricingModel: .init(value1: .cpt),
      automatedKeywordsOptIn: true, status: .init(value1: .enabled), automatedKeywordsRequired: true
    )
  }

  /// Whether Apple sets the campaign's bids itself (Maximize Conversions), so keyword bids don't apply.
  static func isAutomaticBidding(_ campaign: Components.Schemas.Campaign) -> Bool {
    campaign.bidStrategy?.value1.bidStrategyType?.value1.rawValue == "MAX_CONVERSIONS"
  }

  /// A `/query` filter for `field` equal to an ID.
  static func filter(_ field: String, equals id: Int64) throws -> Components.Schemas.QueryFilter {
    .init(field: field, _operator: .equals, value: try OpenAPIValueContainer(unvalidatedValue: Int(id)))
  }

  /// The campaign's ad groups (deleted ones left out).
  static func adGroups(campaignID: Int64, _ ads: AdsConfig, client: Client) async throws -> [Components.Schemas.AdGroup] {
    try await query(Components.Schemas.AdGroup.self) { pagination in
      try await client.postAdgroupsQuery(
        headers: .init(xApContext: context(ads)),
        body: .json(.init(filters: [filter("campaignId", equals: campaignID)], pagination: pagination))
      ).ok.body.json.value1
    }.filter { $0.deleted != true }
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

  /// The campaign's keywords (deleted ones left out).
  static func keywords(campaignID: Int64, _ ads: AdsConfig, client: Client) async throws -> [Components.Schemas.Keyword] {
    try await query(Components.Schemas.Keyword.self) { pagination in
      try await client.postKeywordsQuery(
        headers: .init(xApContext: context(ads)),
        body: .json(.init(filters: [filter("campaignId", equals: campaignID)], pagination: pagination))
      ).ok.body.json.value1
    }.filter { $0.deleted != true }
  }

  /// The campaign's negative keywords, campaign-level and ad group-level (deleted ones left out).
  /// The query needs an `adGroupId` condition: IS_NULL for the campaign's own, EQUALS per ad group.
  static func negativeKeywords(
    campaignID: Int64, adGroupIDs: [Int64], _ ads: AdsConfig, client: Client
  ) async throws -> [Components.Schemas.NegativeKeyword] {
    var conditions: [Components.Schemas.QueryFilter] = [.init(field: "adGroupId", _operator: .isNull)]
    conditions += try adGroupIDs.map { try filter("adGroupId", equals: $0) }
    var negatives: [Components.Schemas.NegativeKeyword] = []
    for condition in conditions {
      negatives += try await query(Components.Schemas.NegativeKeyword.self) { pagination in
        try await client.postNegativeKeywordsQuery(
          headers: .init(xApContext: context(ads)),
          body: .json(.init(filters: [filter("campaignId", equals: campaignID), condition], pagination: pagination))
        ).ok.body.json.value1
      }
    }
    return negatives.filter { $0.deleted != true }
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

  /// Runs a `/query` request page by page and decodes its results. Apple's spec types every
  /// query result as a free-form object, so they're decoded here into the entity's own model.
  static func query<T: Decodable>(
    _ type: T.Type,
    pageSize: Int32 = 1000,
    _ fetch: (Components.Schemas.QueryPagination) async throws -> Components.Schemas.QueryResponse
  ) async throws -> [T] {
    var items: [T] = []
    while true {
      let page = try await fetch(.init(pageSize: pageSize, offset: Int32(items.count)))
      let results = page.result ?? []
      items += try decoder.decode([T].self, from: JSONEncoder().encode(results))
      let total = page.pagination?.totalCount.map(Int.init) ?? 0
      if results.count < pageSize || items.count >= total { return items }
    }
  }

  /// The API's timestamps: UTC without a zone designator, with milliseconds.
  static let decoder: JSONDecoder = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .formatted(formatter)
    return decoder
  }()

  /// Runs `fetch` for each campaign, four at a time (keyword and search term reports take one
  /// campaign per request), keeping the scope's campaign order.
  static func perCampaign<Row: Sendable>(
    _ scope: Scope, _ fetch: @escaping @Sendable (Int64) async throws -> [Row]
  ) async throws -> [Row] {
    let ids = scope.campaigns.compactMap(\.id)
    var results: [Int: [Row]] = [:]
    try await withThrowingTaskGroup(of: (Int, [Row]).self) { group in
      var next = 0
      func addNext() {
        guard next < ids.count else { return }
        let index = next, id = ids[index]
        group.addTask { (index, try await fetch(id)) }
        next += 1
      }
      for _ in 0..<4 { addNext() }
      for try await (index, rows) in group {
        results[index] = rows
        addNext()
      }
    }
    return ids.indices.flatMap { results[$0] ?? [] }
  }

  /// The filter for one campaign (`campaignId` takes only EQUALS for API users).
  static func campaignFilter(_ id: Int64) throws -> [Components.Schemas.Filter] {
    [.init(field: "campaignId", _operator: .equals, value: try OpenAPIValueContainer(unvalidatedValue: Int(id)))]
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

  /// The raw body of the last successful response, for `bulk` (see there).
  private final class CapturedBody: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    var value: Data? {
      get { lock.withLock { data } }
      set { lock.withLock { data = newValue } }
    }
  }

  @TaskLocal private static var capturedBody: CapturedBody?

  /// Runs a request and decodes its raw response body as `T`, for responses the generated
  /// client can't decode because Apple's spec doesn't match what the API sends. The generated
  /// operation's decoding error is dropped; the request itself went through.
  static func decodeRaw<T: Decodable>(_ type: T.Type, _ send: () async throws -> Void) async throws -> T {
    let box = CapturedBody()
    do {
      try await $capturedBody.withValue(box) { try await send() }
    } catch {
      guard box.value != nil, (error as? ClientError)?.underlyingError is DecodingError else { throw error }
    }
    return try decoder.decode(T.self, from: box.value ?? Data("{}".utf8))
  }

  /// Runs a bulk create/update and returns its per-item results. Apple's spec types a bulk
  /// response's `result` as an object while it is an array, so the generated operation fails to
  /// decode a response whose writes went through.
  static func bulk<T: Decodable>(_ type: T.Type, _ send: () async throws -> Void) async throws -> [BulkItem<T>] {
    let response = try await decodeRaw(BulkResponse<T>.self, send)
    if let error = response.error {
      throw AdsError(status: nil, code: error.code, message: error.message, details: error.details ?? [])
    }
    return response.result ?? []
  }

  private struct BulkResponse<T: Decodable>: Decodable {
    let result: [BulkItem<T>]?
    let error: ItemError?
  }

  struct ItemError: Decodable {
    let code: String?
    let message: String?
    let details: [AdsError.Detail]?

    var text: String {
      ([message ?? code ?? "Failed"] + (details ?? []).compactMap(\.message)).joined(separator: " ")
    }
  }

  /// One item of a bulk response, matched to its request item by `correlationId`.
  struct BulkItem<T: Decodable>: Decodable {
    let correlationId: Int64?
    let success: Bool?
    let result: T?
    let error: ItemError?
  }

  /// The dry-run gate (`--dry-run`, `ASCELERATE_DRY_RUN=1`): reads (GETs and `/query` POSTs) go
  /// out; writes are printed and stopped. Turns Apple's error responses into `AdsError` and
  /// waits out rate limits (429): Apple's `Retry-After`, else `RateLimit-Reset`, else 2, 4, 8,
  /// 16 seconds; four attempts in all. Reads also get two more tries after a timeout or a
  /// dropped connection.
  struct Middleware: ClientMiddleware {
    private static let maxAttempts = 4
    private static let retriedNetworkErrors: Set<URLError.Code> = [.timedOut, .networkConnectionLost, .cannotConnectToHost]

    func intercept(
      _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
      next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
      // Collected so a request that hit the rate limit can be sent again.
      var requestData: Data?
      if let body { requestData = try await Data(collecting: body, upTo: .max) }
      let path = request.path ?? "?"
      let isRead = request.method == .get || path.hasSuffix("/query") || path.hasPrefix("/search/")
      if ClientFactory.isDryRun, !isRead {
        var report = "[dry-run] \(request.method.rawValue) \(path)"
        if let requestData, let json = try? JSONSerialization.jsonObject(with: requestData),
          let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
          report += "\n" + String(decoding: pretty, as: UTF8.self)
        }
        FileHandle.standardError.write(Data((report + "\n").utf8))
        throw adsDryRunStop(method: request.method.rawValue, path: path)
      }
      var attempt = 1
      while true {
        let response: HTTPResponse, responseBody: HTTPBody?
        do {
          (response, responseBody) = try await next(request, requestData.map { HTTPBody($0) }, baseURL)
        } catch let error as URLError where isRead && attempt < 3 && Self.retriedNetworkErrors.contains(error.code) {
          // Reads are safe to repeat; a write is never sent twice.
          attempt += 1
          try await Task.sleep(for: .seconds(2))
          continue
        }
        let status = response.status.code
        if status < 400 {
          guard let box = Ads.capturedBody else { return (response, responseBody) }
          var data = Data()
          if let responseBody { data = try await Data(collecting: responseBody, upTo: .max) }
          box.value = data
          return (response, HTTPBody(data))
        }
        if status == 429, attempt < Self.maxAttempts {
          let wait = [HTTPField.Name("Retry-After"), HTTPField.Name("RateLimit-Reset")]
            .compactMap { $0.flatMap { response.headerFields[$0] }.flatMap(Int.init) }.first
            ?? (1 << attempt)
          FileHandle.standardError.write(Data("Apple Ads rate limit reached; waiting \(wait) s.\n".utf8))
          try await Task.sleep(for: .seconds(wait))
          attempt += 1
          continue
        }
        var data = Data()
        if let responseBody { data = try await Data(collecting: responseBody, upTo: 1_000_000) }
        throw AdsError(status: status, data: data)
      }
    }
  }
}

/// An Apple Ads API failure with Apple's own code, message and per-field details.
struct AdsError: LocalizedError {
  struct Detail: Decodable {
    struct Info: Decodable { let field: String? }
    let code: String?
    let message: String?
    let info: Info?
  }

  let status: Int?
  let code: String?
  let message: String?
  let details: [Detail]

  init(status: Int?, code: String?, message: String?, details: [Detail]) {
    self.status = status
    self.code = code
    self.message = message
    self.details = details
  }

  /// From an error response body: `{"error": {"code", "message", "details": [...]}}`.
  init(status: Int, data: Data) {
    struct Body: Decodable {
      struct Inner: Decodable {
        let code: String?
        let message: String?
        let details: [Detail]?
      }
      let error: Inner?
    }
    // Apple's error body; anything else is shown as it came.
    if let inner = (try? JSONDecoder().decode(Body.self, from: data))?.error {
      self.init(status: status, code: inner.code, message: inner.message, details: inner.details ?? [])
    } else {
      let text = String(decoding: data.prefix(500), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
      self.init(status: status, code: nil, message: text.isEmpty ? nil : text, details: [])
    }
  }

  var errorDescription: String? {
    if code == "UNEXPECTED_RESPONSE" {
      return "Unexpected response from the Apple Ads API: \(message ?? "")"
    }
    var lines = [
      "Apple Ads API"
        + (status.map { " returned HTTP \($0)" } ?? " sign-in failed")
        + (code.map { " (\($0))" } ?? "")
        + (message.map { ": \($0)" } ?? ".")
    ]
    for detail in details {
      let field = detail.info?.field.map { " [\($0)]" } ?? ""
      lines.append("  - " + (detail.message ?? detail.code ?? "") + field)
    }
    switch status {
    case nil where message?.contains("Network error") == true:
      lines.append("  Couldn't reach Apple's sign-in server. Check your connection and try again.")
    case nil, 401: lines.append("  Check your Apple Ads credentials (run 'ascelerate ads configure').")
    case 403: lines.append("  The Apple Ads API user's role may not allow this.")
    case let s? where s >= 500: lines.append("  This is a server-side issue. Try again later.")
    default: break
    }
    return lines.joined(separator: "\n")
  }
}
