import ASCKit
import Foundation

/// An app's customer reviews and the developer's responses to them. App Store Connect's ratings
/// (stars without a review, its average and star breakdown) have no API; `ratingCounts` counts the
/// written reviews instead.
public enum CustomerReviews {
  public struct Response: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let body: String?
    public let lastModifiedDate: Date?
    /// `PUBLISHED` or `PENDING_PUBLISH`.
    public let state: String?
  }

  public struct Review: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let rating: Int?
    public let title: String?
    public let body: String?
    public let reviewerNickname: String?
    /// The App Store's territory code (`USA`).
    public let territory: String?
    public let createdDate: Date?
    public var response: Response?
  }

  public enum Sort: String, CaseIterable, Sendable {
    case recent = "-createdDate"
    case oldest = "createdDate"
    /// Lowest rating first.
    case critical = "rating"
    /// Highest rating first.
    case favorable = "-rating"
  }

  /// Which reviews to list; nil leaves a criterion out.
  public struct Filter: Hashable, Sendable {
    /// Reviews of one App Store version (a review doesn't say its version otherwise).
    public var versionID: String?
    public var rating: Int?
    /// The App Store's territory code (`USA`).
    public var territory: String?
    /// Reviews with (true) or without (false) a published response.
    public var hasResponse: Bool?

    public init(versionID: String? = nil, rating: Int? = nil, territory: String? = nil, hasResponse: Bool? = nil) {
      self.versionID = versionID
      self.rating = rating
      self.territory = territory
      self.hasResponse = hasResponse
    }
  }

  public struct Page: Sendable {
    public let reviews: [Review]
    /// The number of reviews the filter matches.
    public let total: Int?
    /// The next page's link, for `page(…, after:)`; nil on the last page.
    public let next: String?
  }

  /// A page of reviews (up to 200) with their responses: the first one, or the one `after` links to.
  public static func page(
    appID: String, filter: Filter = Filter(), sort: Sort = .recent, limit: Int = 50, after link: String? = nil,
    client: ASCClient
  ) async throws -> Page {
    let response = try await ASCPaging.page(link) { try await fetch(appID: appID, filter: filter, sort: sort, limit: limit, client: client) }
    return Page(reviews: reviews(in: response), total: response.meta?.paging.total, next: response.links.next)
  }

  /// The number of reviews with each rating (1 to 5) among those `filter` matches, its rating left
  /// out: one request per rating.
  public static func ratingCounts(appID: String, filter: Filter = Filter(), client: ASCClient) async throws -> [Int: Int] {
    try await withThrowingTaskGroup(of: (Int, Int).self) { group in
      for rating in 1...5 {
        var filter = filter
        filter.rating = rating
        group.addTask {
          let response = try await fetch(appID: appID, filter: filter, sort: .recent, limit: 1, client: client)
          return (rating, response.meta?.paging.total ?? response.data.count)
        }
      }
      return try await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }
  }

  /// One review with its response.
  public static func review(id: String, client: ASCClient) async throws -> Review {
    let response = try await client.customerReviewsGetInstance(path: .init(id: id), query: .init(include: [.response]))
      .ok.body.json
    let responses = response.included?.compactMap { item -> Components.Schemas.CustomerReviewResponseV1? in
      if case .customerReviewResponses(let r) = item { return r }
      return nil
    } ?? []
    return review(response.data, response: responses.first)
  }

  /// Publishes a response to a review. A review takes one response: replace one by deleting it first.
  @discardableResult
  public static func respond(reviewID: String, body: String, client: ASCClient) async throws -> Response {
    let created = try await client.customerReviewResponsesCreateInstance(body: .json(.init(data: .init(
      attributes: .init(responseBody: body),
      relationships: .init(review: .init(data: .init(id: reviewID, _type: "customerReviews"))),
      _type: "customerReviewResponses"
    )))).created.body.json.data
    return response(created)
  }

  public static func deleteResponse(id: String, client: ASCClient) async throws {
    _ = try await client.customerReviewResponsesDeleteInstance(path: .init(id: id)).noContent
  }

  public struct Summary: Hashable, Identifiable, Sendable {
    public let id: String
    public let text: String
    public let locale: String?
    public let createdDate: Date?
  }

  /// Apple's summaries of the app's reviews on a platform (`IOS`, `MAC_OS`…), optionally in one
  /// territory. Apple writes them only for some apps; most get none.
  public static func summaries(appID: String, platform: String, territory: String? = nil, client: ASCClient) async throws -> [Summary] {
    guard let platform = Operations.AppsCustomerReviewSummarizationsGetToManyRelated.Input.Query.FilterPlatformPayloadPayload(rawValue: platform)
    else { return [] }
    return try await client.appsCustomerReviewSummarizationsGetToManyRelated(
      path: .init(id: appID),
      query: .init(filterPlatform: [platform], filterTerritory: territory.map { [$0] }, limit: 50)
    ).ok.body.json.data.compactMap { summary in
      guard let text = summary.attributes?.text, !text.isEmpty else { return nil }
      return Summary(id: summary.id, text: text, locale: summary.attributes?.locale, createdDate: summary.attributes?.createdDate)
    }
  }

  // MARK: Decoding

  private static func fetch(
    appID: String, filter: Filter, sort: Sort, limit: Int, client: ASCClient
  ) async throws -> Components.Schemas.CustomerReviewsResponse {
    let rating = filter.rating.map { ["\($0)"] }
    let territory = filter.territory.map { [$0] }
    let limit = min(max(limit, 1), 200)
    if let versionID = filter.versionID {
      typealias Query = Operations.AppStoreVersionsCustomerReviewsGetToManyRelated.Input.Query
      return try await client.appStoreVersionsCustomerReviewsGetToManyRelated(
        path: .init(id: versionID),
        query: .init(
          filterRating: rating, filterReviewTerritory: territory, existsPublishedResponse: filter.hasResponse,
          sort: Query.SortPayloadPayload(rawValue: sort.rawValue).map { [$0] }, limit: limit, include: [.response])
      ).ok.body.json
    }
    typealias Query = Operations.AppsCustomerReviewsGetToManyRelated.Input.Query
    return try await client.appsCustomerReviewsGetToManyRelated(
      path: .init(id: appID),
      query: .init(
        filterRating: rating, filterReviewTerritory: territory, existsPublishedResponse: filter.hasResponse,
        sort: Query.SortPayloadPayload(rawValue: sort.rawValue).map { [$0] }, limit: limit, include: [.response])
    ).ok.body.json
  }

  private static func reviews(in response: Components.Schemas.CustomerReviewsResponse) -> [Review] {
    let responses = Dictionary(
      (response.included ?? []).compactMap { item -> (String, Components.Schemas.CustomerReviewResponseV1)? in
        if case .customerReviewResponses(let r) = item { return (r.id, r) }
        return nil
      }, uniquingKeysWith: { first, _ in first })
    return response.data.map { review($0, response: $0.relationships?.response?.data.flatMap { responses[$0.id] }) }
  }

  private static func review(_ review: Components.Schemas.CustomerReview, response: Components.Schemas.CustomerReviewResponseV1?) -> Review {
    let a = review.attributes
    return Review(
      id: review.id, rating: a?.rating, title: a?.title, body: a?.body, reviewerNickname: a?.reviewerNickname,
      territory: a?.territory, createdDate: a?.createdDate, response: response.map(Self.response))
  }

  private static func response(_ response: Components.Schemas.CustomerReviewResponseV1) -> Response {
    Response(
      id: response.id, body: response.attributes?.responseBody, lastModifiedDate: response.attributes?.lastModifiedDate,
      state: response.attributes?.state)
  }
}
