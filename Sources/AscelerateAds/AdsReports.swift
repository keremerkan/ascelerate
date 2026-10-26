import AppleAdsClient
import Foundation

extension Ads {
  /// A campaign's ad groups with their numbers for the range. Rows come for every ad group,
  /// active or not.
  public static func adGroupReportRows(
    campaignID: Int64, start: String, end: String, timeZone: Components.Schemas.TimeRange.TimeZonePayload = .ortz,
    context: String, client: Client
  ) async throws -> [Components.Schemas.AppsAdGroupReportRow] {
    try await reportRows { pagination in
      let json = try await client.appsAdGroupReports(
        headers: .init(xApContext: context),
        body: .json(reportRequest(
          start: start, end: end, timeZone: timeZone, filters: campaignFilter(campaignID), pagination: pagination))
      ).ok.body.json
      return (json.result?.rows ?? [], json.pagination?.totalCount)
    }
  }

  /// A campaign's keywords with their numbers for the range, and Apple's suggested bid for each.
  public static func keywordReportRows(
    campaignID: Int64, start: String, end: String, timeZone: Components.Schemas.TimeRange.TimeZonePayload = .ortz,
    context: String, client: Client
  ) async throws -> [Components.Schemas.AppsKeywordReportRow] {
    try await reportRows { pagination in
      let json = try await client.appsKeywordReports(
        headers: .init(xApContext: context),
        body: .json(reportRequest(
          start: start, end: end, timeZone: timeZone, filters: campaignFilter(campaignID), pagination: pagination))
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
