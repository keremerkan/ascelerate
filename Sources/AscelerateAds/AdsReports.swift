import AppleAdsClient
import Foundation

extension Ads {
  /// A campaign's ad groups with their numbers for the range (those without impressions or spend
  /// only with `includesEmptyRows`), and with `granularity`, per day or hour too.
  public static func adGroupReportRows(
    campaignID: Int64, start: String, end: String, timeZone: Components.Schemas.TimeRange.TimeZonePayload = .ortz,
    includesEmptyRows: Bool = false, granularity: Granularity? = nil, context: String, client: Client
  ) async throws -> [Components.Schemas.AppsAdGroupReportRow] {
    try await $granularity.withValue(granularity) {
      try await adGroupReportPages(
        campaignID: campaignID, start: start, end: end, timeZone: timeZone, includesEmptyRows: includesEmptyRows,
        context: context, client: client)
    }
  }

  private static func adGroupReportPages(
    campaignID: Int64, start: String, end: String, timeZone: Components.Schemas.TimeRange.TimeZonePayload,
    includesEmptyRows: Bool, context: String, client: Client
  ) async throws -> [Components.Schemas.AppsAdGroupReportRow] {
    try await reportRows { pagination in
      let json = try await client.appsAdGroupReports(
        headers: .init(xApContext: context),
        body: .json(reportRequest(
          start: start, end: end, timeZone: timeZone, includesEmptyRows: includesEmptyRows, filters: campaignFilter(campaignID),
          pagination: pagination))
      ).ok.body.json
      return (json.result?.rows ?? [], json.pagination?.totalCount)
    }
  }

  /// A campaign's keywords with their numbers for the range, and Apple's suggested bid for each
  /// (those without impressions or spend only with `includesEmptyRows`).
  public static func keywordReportRows(
    campaignID: Int64, start: String, end: String, timeZone: Components.Schemas.TimeRange.TimeZonePayload = .ortz,
    includesEmptyRows: Bool = false, context: String, client: Client
  ) async throws -> [Components.Schemas.AppsKeywordReportRow] {
    try await reportRows { pagination in
      let json = try await client.appsKeywordReports(
        headers: .init(xApContext: context),
        body: .json(reportRequest(
          start: start, end: end, timeZone: timeZone, includesEmptyRows: includesEmptyRows, filters: campaignFilter(campaignID),
          pagination: pagination))
      ).ok.body.json
      return (json.result?.rows ?? [], json.pagination?.totalCount)
    }
  }

  /// What people searched for when a campaign's ads showed, with the keyword (or Search Match)
  /// that matched. Always in the ad account's time zone: Apple refuses UTC for search terms.
  public static func searchTermReportRows(
    campaignID: Int64, start: String, end: String, context: String, client: Client
  ) async throws -> [Components.Schemas.AppsSearchTermReportRow] {
    try await reportRows { pagination in
      let json = try await client.appsSearchTermReports(
        headers: .init(xApContext: context),
        body: .json(reportRequest(start: start, end: end, filters: campaignFilter(campaignID), pagination: pagination))
      ).ok.body.json
      return (json.result?.rows ?? [], json.pagination?.totalCount)
    }
  }
}
