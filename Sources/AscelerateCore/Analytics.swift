import ASCKit
import Foundation

/// App Analytics reports: an app's report requests (ongoing, or a one-time snapshot of its
/// history), their reports per category, each report's instances per granularity and processing
/// date, and an instance's segments, gzipped tab-separated files at presigned URLs.
public enum Analytics {
  public enum AccessType: String, Sendable {
    case ongoing = "ONGOING"
    case oneTimeSnapshot = "ONE_TIME_SNAPSHOT"
  }

  public struct Request: Sendable, Hashable, Identifiable {
    public let id: String
    public let accessType: String?
    /// Apple stops an ongoing request nobody has downloaded from for a while; a stopped one takes
    /// no new days.
    public let isStopped: Bool
  }

  public struct Report: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let category: String?
  }

  public struct Instance: Sendable, Hashable, Identifiable {
    public let id: String
    public let granularity: String?
    /// The day Apple processed it (yyyy-MM-dd).
    public let processingDate: String?
  }

  public struct Segment: Sendable, Hashable, Identifiable {
    public let id: String
    public let url: URL?
    public let checksum: String?
    public let size: Int?
  }

  public enum AnalyticsError: LocalizedError {
    case download(segment: Int, status: Int)

    public var errorDescription: String? {
      switch self {
        case .download(let segment, let status):
          "Segment \(segment) download failed (HTTP \(status)). The presigned URL may have expired — try again."
      }
    }
  }

  /// The app's report requests of an access type.
  public static func requests(appID: String, accessType: AccessType, client: ASCClient) async throws -> [Request] {
    let filter: Operations.AppsAnalyticsReportRequestsGetToManyRelated.Input.Query.FilterAccessTypePayloadPayload =
      accessType == .ongoing ? .ongoing : .oneTimeSnapshot
    return try await client.appsAnalyticsReportRequestsGetToManyRelated(
      path: .init(id: appID), query: .init(filterAccessType: [filter], limit: 50)
    ).ok.body.json.data.map(Request.init)
  }

  /// The app's request of an access type that still takes new days, if any.
  public static func activeRequest(appID: String, accessType: AccessType, client: ASCClient) async throws -> Request? {
    try await requests(appID: appID, accessType: accessType, client: client).first { !$0.isStopped }
  }

  /// Asks Apple for an app's reports: an ongoing request adds each new day, a one-time snapshot
  /// covers the history. Apple takes a day or two to generate the first reports.
  public static func createRequest(appID: String, accessType: AccessType, client: ASCClient) async throws -> Request {
    let type: ASCEnum.AnalyticsReportRequestCreateRequestAccessType = accessType == .ongoing ? .ongoing : .oneTimeSnapshot
    return Request(try await client.analyticsReportRequestsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(accessType: type.rawValue),
      relationships: .init(app: .init(data: .init(id: appID, _type: "apps"))),
      _type: "analyticsReportRequests"
    )))).created.body.json.data)
  }

  /// A request's reports in a category (APP_STORE_ENGAGEMENT, APP_USAGE, COMMERCE,
  /// FRAMEWORK_USAGE, PERFORMANCE); nil category for all.
  public static func reports(
    requestID: String,
    category: Operations.AnalyticsReportRequestsReportsGetToManyRelated.Input.Query.FilterCategoryPayloadPayload?,
    client: ASCClient
  ) async throws -> [Report] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.analyticsReportRequestsReportsGetToManyRelated(
        path: .init(id: requestID), query: .init(filterCategory: category.map { [$0] }, limit: 200)
      ).ok.body.json
    }.flatMap(\.data).map(Report.init)
  }

  /// A report's instances at a granularity (DAILY, WEEKLY, MONTHLY), optionally of one
  /// processing day.
  public static func instances(
    reportID: String,
    granularity: Operations.AnalyticsReportsInstancesGetToManyRelated.Input.Query.FilterGranularityPayloadPayload,
    processingDate: String? = nil, client: ASCClient
  ) async throws -> [Instance] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.analyticsReportsInstancesGetToManyRelated(
        path: .init(id: reportID),
        query: .init(filterGranularity: [granularity], filterProcessingDate: processingDate.map { [$0] }, limit: 200)
      ).ok.body.json
    }.flatMap(\.data).map(Instance.init)
  }

  /// An instance's segments, the parts of its data.
  public static func segments(instanceID: String, client: ASCClient) async throws -> [Segment] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.analyticsReportInstancesSegmentsGetToManyRelated(
        path: .init(id: instanceID), query: .init(limit: 200)
      ).ok.body.json
    }.flatMap(\.data).map(Segment.init)
  }

  /// A segment's data, unzipped: tab-separated text with a header line. `number` names the
  /// segment in an error.
  public static func download(_ segment: Segment, number: Int = 1) async throws -> Data {
    try Gzip.decompress(try await downloadZipped(segment, number: number))
  }

  /// A segment's data as Apple sends it, gzipped (a tenth of its size unzipped), for a client
  /// that reads it more than once.
  public static func downloadZipped(_ segment: Segment, number: Int = 1) async throws -> Data {
    guard let url = segment.url else { return Data() }
    let (data, response) = try await URLSession.shared.data(from: url)
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      throw AnalyticsError.download(segment: number, status: http.statusCode)
    }
    return data
  }
}

extension Analytics.Request {
  init(_ request: Components.Schemas.AnalyticsReportRequest) {
    id = request.id
    accessType = request.attributes?.accessType
    isStopped = request.attributes?.stoppedDueToInactivity == true
  }
}

extension Analytics.Report {
  init(_ report: Components.Schemas.AnalyticsReport) {
    id = report.id
    name = report.attributes?.name ?? report.id
    category = report.attributes?.category
  }
}

extension Analytics.Instance {
  init(_ instance: Components.Schemas.AnalyticsReportInstance) {
    id = instance.id
    granularity = instance.attributes?.granularity
    processingDate = instance.attributes?.processingDate
  }
}

extension Analytics.Segment {
  init(_ segment: Components.Schemas.AnalyticsReportSegment) {
    id = segment.id
    url = segment.attributes?.url.flatMap(URL.init(string:))
    checksum = segment.attributes?.checksum
    size = segment.attributes?.sizeInBytes
  }
}
