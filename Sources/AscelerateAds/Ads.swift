import AppleAdsClient
import AscelerateCore
import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// Apple's Apple Ads client, by a name that doesn't collide with ASCKit's `Client` in a module
/// that imports both.
public typealias AdsClient = Client

/// Apple Ads Platform API logic on Apple's `AppleAdsClient`, without terminal I/O: the
/// authenticated client, its middleware (errors, rate limits, a gate for writes), paged queries
/// and the account's campaigns, ad groups and keywords.
public enum Ads {
  /// What the client signs in with: an API user's IDs and its private key, and the ad account
  /// requests act on.
  public struct Credentials: Sendable {
    public var clientID: String
    public var teamID: String
    public var keyID: String
    public var privateKeyPEM: String
    public var adAccountID: Int64?

    public init(clientID: String, teamID: String, keyID: String, privateKeyPEM: String, adAccountID: Int64? = nil) {
      self.clientID = clientID
      self.teamID = teamID
      self.keyID = keyID
      self.privateKeyPEM = privateKeyPEM
      self.adAccountID = adAccountID
    }
  }

  /// How the client treats writes and rate limits.
  public struct Options: Sendable {
    /// Called before a write (any request but a GET, a `/query` or a `/search/` POST) is sent,
    /// with its method, path and body; an error it throws stops the write.
    public var gateWrite: (@Sendable (_ method: String, _ path: String, _ body: Data?) async throws -> Void)?
    /// Called before waiting out a rate limit (429), with the seconds to wait.
    public var onRateLimitWait: (@Sendable (_ seconds: Int) -> Void)?

    public init(
      gateWrite: (@Sendable (String, String, Data?) async throws -> Void)? = nil,
      onRateLimitWait: (@Sendable (Int) -> Void)? = nil
    ) {
      self.gateWrite = gateWrite
      self.onRateLimitWait = onRateLimitWait
    }
  }

  /// The `X-AP-Context` header value every ad account request needs.
  public static func context(adAccountID: Int64) -> String {
    XApContext(adAccountID: adAccountID).rawValue
  }

  /// Runs `body` with an authenticated client. The access token comes from `TokenStore`, shared
  /// by every client of these credentials until it nearly expires. Failures come out as
  /// `AdsError`, not wrapped in the runtime's `ClientError` (whose description dumps the whole
  /// request).
  public static func withClient<T>(
    _ credentials: Credentials, options: Options = Options(), _ body: (Client) async throws -> T
  ) async throws -> T {
    do {
      return try await AppleAdsClient.withClient(
        configuration: .init(
          clientId: credentials.clientID,
          authMode: .tokenProvider(SharedTokenProvider(credentials: credentials)),
          middleware: [Middleware(options: options)]
        ),
        transport: URLSessionTransport(),
        body: body
      )
    } catch {
      let underlying = (error as? ClientError)?.underlyingError ?? error
      // A refused token (revoked, say) is fetched again next time.
      if (underlying as? AdsError)?.status == 401 { await TokenStore.shared.invalidate(credentials) }
      if let auth = underlying as? AppleAdsAuthError {
        throw AdsError(status: nil, code: nil, message: auth.description, details: [])
      }
      if underlying is DecodingError {
        throw AdsError(status: nil, code: "UNEXPECTED_RESPONSE", message: "\(underlying)", details: [])
      }
      throw underlying
    }
  }

  /// The ad accounts the API user can act on, with its roles in each.
  public static func accessControlList(client: Client) async throws -> [Components.Schemas.UserAcl] {
    try await client.getUserAcls().ok.body.json.result?.acls ?? []
  }

  /// The ad account: its name, currency and time zone (an IANA identifier such as Europe/Istanbul).
  public static func adAccount(id: Int64, client: Client) async throws -> Components.Schemas.AdAccount? {
    try await client.getAdAccountsId(path: .init(id: String(id)), headers: .init(xApContext: context(adAccountID: id)))
      .ok.body.json.result
  }

  /// All campaigns of the ad account (deleted ones left out).
  public static func campaigns(context: String, client: Client) async throws -> [Components.Schemas.Campaign] {
    try await query(Components.Schemas.Campaign.self) { pagination in
      try await client.postCampaignsQuery(
        headers: .init(xApContext: context),
        body: .json(.init(pagination: pagination))
      ).ok.body.json.value1
    }.filter { $0.deleted != true }
  }

  /// The campaign's ad groups (deleted ones left out).
  public static func adGroups(campaignID: Int64, context: String, client: Client) async throws -> [Components.Schemas.AdGroup] {
    try await query(Components.Schemas.AdGroup.self) { pagination in
      try await client.postAdgroupsQuery(
        headers: .init(xApContext: context),
        body: .json(.init(filters: [filter("campaignId", equals: campaignID)], pagination: pagination))
      ).ok.body.json.value1
    }.filter { $0.deleted != true }
  }

  /// The campaign's keywords (deleted ones left out).
  public static func keywords(campaignID: Int64, context: String, client: Client) async throws -> [Components.Schemas.Keyword] {
    try await query(Components.Schemas.Keyword.self) { pagination in
      try await client.postKeywordsQuery(
        headers: .init(xApContext: context),
        body: .json(.init(filters: [filter("campaignId", equals: campaignID)], pagination: pagination))
      ).ok.body.json.value1
    }.filter { $0.deleted != true }
  }

  /// The campaign's negative keywords, campaign-level and ad group-level (deleted ones left out).
  /// The query needs an `adGroupId` condition: IS_NULL for the campaign's own, EQUALS per ad group.
  public static func negativeKeywords(
    campaignID: Int64, adGroupIDs: [Int64], context: String, client: Client
  ) async throws -> [Components.Schemas.NegativeKeyword] {
    var conditions: [Components.Schemas.QueryFilter] = [.init(field: "adGroupId", _operator: .isNull)]
    conditions += try adGroupIDs.map { try filter("adGroupId", equals: $0) }
    let campaign = try filter("campaignId", equals: campaignID)
    // Four queries at a time, the campaign's own first and then the ad groups' in their order.
    return try await boundedConcurrentMap(conditions, maxConcurrent: 4) { condition in
      try await query(Components.Schemas.NegativeKeyword.self) { pagination in
        try await client.postNegativeKeywordsQuery(
          headers: .init(xApContext: context),
          body: .json(.init(filters: [campaign, condition], pagination: pagination))
        ).ok.body.json.value1
      }
    }.joined().filter { $0.deleted != true }
  }

  /// Whether Apple sets the campaign's bids itself (Maximize Conversions), so keyword bids don't apply.
  public static func isAutomaticBidding(_ campaign: Components.Schemas.Campaign) -> Bool {
    campaign.bidStrategy?.value1.bidStrategyType?.value1.rawValue == "MAX_CONVERSIONS"
  }

  /// The automated ad group a Max Conversions campaign requires: Search Match, no keywords. The API
  /// rejects a bid strategy ("AdGroup cannot have a bid strategy") and a start time on it, although a
  /// web-created one reads back with both.
  public static func automatedAdGroup(campaignID: Int64) -> Components.Schemas.AdGroupCreate {
    .init(
      name: "Automated", campaignId: campaignID, pricingModel: .init(value1: .cpt),
      automatedKeywordsOptIn: true, status: .init(value1: .enabled), automatedKeywordsRequired: true
    )
  }

  /// A `/query` filter for `field` equal to an ID.
  public static func filter(_ field: String, equals id: Int64) throws -> Components.Schemas.QueryFilter {
    .init(field: field, _operator: .equals, value: try OpenAPIValueContainer(unvalidatedValue: Int(id)))
  }

  /// The report filter for one campaign (`campaignId` takes only EQUALS for API users).
  public static func campaignFilter(_ id: Int64) throws -> [Components.Schemas.Filter] {
    [.init(field: "campaignId", _operator: .equals, value: try OpenAPIValueContainer(unvalidatedValue: Int(id)))]
  }

  /// Runs a `/query` request page by page and decodes its results. Apple's spec types every
  /// query result as a free-form object, so they're decoded here into the entity's own model.
  public static func query<T: Decodable>(
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
  public static let decoder: JSONDecoder = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .formatted(formatter)
    return decoder
  }()

  /// A report request for the range (yyyy-MM-dd), its days in the ad account's time zone (ORTZ)
  /// or UTC (which search term reports don't take). Rows without impressions or spend come only
  /// with `includesEmptyRows`: without it, a paused campaign's ad groups and keywords have none.
  public static func reportRequest(
    start: String, end: String, timeZone: Components.Schemas.TimeRange.TimeZonePayload = .ortz,
    includesEmptyRows: Bool = false, filters: [Components.Schemas.Filter]? = nil,
    pagination: Components.Schemas.RequestPagination
  ) -> Components.Schemas.AppsReportingRequest {
    .init(
      pagination: pagination, filters: filters, timeRange: .init(start: start, end: end, timeZone: timeZone),
      options: includesEmptyRows ? .init(includeRows: [.emptyMetrics]) : nil)
  }

  /// The campaign report's rows for the range, every campaign's (`campaignId` filters take only
  /// EQUALS for API users), optionally broken down by `groupBy` dimensions.
  public static func campaignReportRows(
    start: String, end: String, timeZone: Components.Schemas.TimeRange.TimeZonePayload = .ortz,
    includesEmptyRows: Bool = false, groupBy: [Components.Schemas.AppsReportingRequest.GroupByPayloadPayload] = [],
    context: String, client: Client
  ) async throws -> [Components.Schemas.AppsCampaignReportRow] {
    try await reportRows { pagination in
      var request = reportRequest(
        start: start, end: end, timeZone: timeZone, includesEmptyRows: includesEmptyRows, pagination: pagination)
      if !groupBy.isEmpty { request.groupBy = groupBy }
      let json = try await client.appsCampaignReports(headers: .init(xApContext: context), body: .json(request)).ok.body.json
      return (json.result?.rows ?? [], json.pagination?.totalCount)
    }
  }

  /// Fetches every page of a report (5,000 rows per page).
  public static func reportRows<Row>(
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

  /// A report's steps: each row then also has its numbers per day or hour (`granularMetrics`).
  /// Apple takes it as `timeRange.granularity`, which its published spec leaves out (seen live
  /// 2026-10-26: DAILY and HOURLY accepted; HOURLY needs a range starting in the last 7 days).
  public enum Granularity: String, Sendable {
    case hourly = "HOURLY"
    case daily = "DAILY"
  }

  /// The steps the middleware adds to report requests made under it.
  @TaskLocal static var granularity: Granularity?

  /// The raw body of the last successful response, for `bulk` (see there).
  final class CapturedBody: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    var value: Data? {
      get { lock.withLock { data } }
      set { lock.withLock { data = newValue } }
    }
  }

  @TaskLocal static var capturedBody: CapturedBody?

  /// Runs a request and decodes its raw response body as `T`, for responses the generated
  /// client can't decode because Apple's spec doesn't match what the API sends. The generated
  /// operation's decoding error is dropped; the request itself went through.
  public static func decodeRaw<T: Decodable>(_ type: T.Type, _ send: () async throws -> Void) async throws -> T {
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
  public static func bulk<T: Decodable & Sendable>(_ type: T.Type, _ send: () async throws -> Void) async throws -> [BulkItem<T>] {
    let response = try await decodeRaw(BulkResponse<T>.self, send)
    if let error = response.error {
      throw AdsError(status: nil, code: error.code, message: error.message, details: error.details ?? [])
    }
    return response.result ?? []
  }

  private struct BulkResponse<T: Decodable & Sendable>: Decodable {
    let result: [BulkItem<T>]?
    let error: ItemError?
  }

  public struct ItemError: Decodable, Sendable {
    public let code: String?
    public let message: String?
    public let details: [AdsError.Detail]?

    public var text: String {
      ([message ?? code ?? "Failed"] + (details ?? []).compactMap(\.message)).joined(separator: " ")
    }
  }

  /// One item of a bulk response, matched to its request item by `correlationId`.
  public struct BulkItem<T: Decodable & Sendable>: Decodable, Sendable {
    public let correlationId: Int64?
    public let success: Bool?
    public let result: T?
    public let error: ItemError?
  }

  /// Turns Apple's error responses into `AdsError`, passes writes through `gateWrite` first, and
  /// waits out rate limits (429): Apple's `Retry-After`, else `RateLimit-Reset`, else 2, 4, 8, 16
  /// seconds; four attempts in all. Reads also get two more tries after a timeout or a dropped
  /// connection.
  struct Middleware: ClientMiddleware {
    let options: Options
    private static let maxAttempts = 4
    private static let retriedNetworkErrors: Set<URLError.Code> = [.timedOut, .networkConnectionLost, .cannotConnectToHost]

    func intercept(
      _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
      next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
      var request = request
      // Collected so a request that hit the rate limit can be sent again.
      var requestData: Data?
      if let body { requestData = try await Data(collecting: body, upTo: .max) }
      let path = request.path ?? "?"
      if let granularity = Ads.granularity, path.contains("/reports/"), let data = requestData,
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        var range = json["timeRange"] as? [String: Any]
      {
        range["granularity"] = granularity.rawValue
        json["timeRange"] = range
        let patched = try JSONSerialization.data(withJSONObject: json)
        requestData = patched
        // The longer body needs its own length: with the old one, Apple's front end answers 400.
        request.headerFields[.contentLength] = String(patched.count)
      }
      let isRead = request.method == .get || path.hasSuffix("/query") || path.hasPrefix("/search/")
      if !isRead { try await options.gateWrite?(request.method.rawValue, path, requestData) }
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
          options.onRateLimitWait?(wait)
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
public struct AdsError: LocalizedError, Sendable {
  public struct Detail: Decodable, Sendable {
    public struct Info: Decodable, Sendable { public let field: String? }
    public let code: String?
    public let message: String?
    public let info: Info?
  }

  public let status: Int?
  public let code: String?
  public let message: String?
  public let details: [Detail]
  /// The line added to a sign-in failure or a 401.
  public var credentialsHint = "Check your Apple Ads credentials."

  public init(status: Int?, code: String?, message: String?, details: [Detail]) {
    self.status = status
    self.code = code
    self.message = message
    self.details = details
  }

  /// From an error response body: `{"error": {"code", "message", "details": [...]}}`.
  public init(status: Int, data: Data) {
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

  public var errorDescription: String? {
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
    case nil, 401: lines.append("  " + credentialsHint)
    case 403: lines.append("  The Apple Ads API user's role may not allow this.")
    case let s? where s >= 500: lines.append("  This is a server-side issue. Try again later.")
    default: break
    }
    return lines.joined(separator: "\n")
  }
}
