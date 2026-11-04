import ASCKit
import Foundation

/// What App Store Connect gathers from users' devices (Xcode's Organizer): a build's diagnostic
/// signatures (the top hangs, slow launches and disk writes, each with its call stacks) and the
/// app's or a build's performance and power metrics across versions, devices and percentiles.
/// Apple's own JSON (`xcode-metrics`, `diagnostic-logs`) is decoded into the plain models below,
/// whose keys are Apple's.
public enum Diagnostics {
  // MARK: Signatures

  /// A hang, slow launch or disk write signature of a build.
  public struct Signature: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// `HANGS`, `LAUNCHES` or `DISK_WRITES`.
    public let type: String?
    /// The frames it's known by.
    public let signature: String?
    /// Its share of the build's issues of its type (0 to 100).
    public let weight: Double?
    /// `UP`, `DOWN` or `UNDEFINED`: how it moved against earlier versions.
    public let trend: String?
    public let referenceVersions: [ReferenceVersion]

    public struct ReferenceVersion: Codable, Hashable, Sendable {
      public let version: String?
      public let value: Double?
    }
  }

  /// The diagnostic types (`DISK_WRITES`, `HANGS`, `LAUNCHES`).
  public static let signatureTypes = ["HANGS", "LAUNCHES", "DISK_WRITES"]

  /// A build's signatures, by type and heaviest first; `types` narrows them. Each type is read on
  /// its own: without a type filter Apple answers with one type only (seen 2026-11-04: a build's
  /// disk writes, while it also had a hang and three launch signatures).
  public static func signatures(buildID: String, types: [String]? = nil, client: ASCClient) async throws -> [Signature] {
    typealias Filter = Operations.BuildsDiagnosticSignaturesGetToManyRelated.Input.Query.FilterDiagnosticTypePayloadPayload
    let lists = try await boundedConcurrentMap((types ?? signatureTypes).compactMap(Filter.init(rawValue:))) { type in
      try await withTransientRetry {
        try await ASCPaging.allPages(next: { $0.links.next }) {
          try await client.buildsDiagnosticSignaturesGetToManyRelated(
            path: .init(id: buildID), query: .init(filterDiagnosticType: [type], limit: 200)
          ).ok.body.json
        }
      }.flatMap(\.data)
    }
    return lists.flatMap { $0 }
    .map { s in
      let a = s.attributes
      return Signature(
        id: s.id, type: a?.diagnosticType, signature: a?.signature, weight: a?.weight, trend: a?.insight?.direction,
        referenceVersions: (a?.insight?.referenceVersions ?? []).map { .init(version: $0.version, value: $0.value) })
    }
    .sorted { a, b in
      let rank = { (s: Signature) in signatureTypes.firstIndex(of: s.type ?? "") ?? signatureTypes.count }
      return rank(a) != rank(b) ? rank(a) < rank(b) : (a.weight ?? 0) > (b.weight ?? 0)
    }
  }

  /// The build of the version on the App Store for the platform (raw, e.g. `IOS`; nil for any),
  /// whose users the diagnostics and metrics come from; nil when nothing is on sale.
  public static func liveBuild(appID: String, platform: String?, client: ASCClient) async throws -> Builds.Build? {
    typealias PlatformFilter = Operations.AppsAppStoreVersionsGetToManyRelated.Input.Query.FilterPlatformPayloadPayload
    let filter: PlatformFilter? = platform.flatMap(PlatformFilter.init(rawValue:))
    let live = try await withTransientRetry {
      try await client.appsAppStoreVersionsGetToManyRelated(
        path: .init(id: appID),
        query: .init(filterPlatform: filter.map { [$0] }, filterAppVersionState: [.readyForDistribution], limit: 1)
      ).ok.body.json.data.first
    }
    guard let live, let build = try await attachedBuild(versionID: live.id, client: client) else { return nil }
    return try await Builds.build(id: build.id, client: client)
  }

  // MARK: Logs

  /// A signature's logs: Apple's `diagnostic-logs` document.
  public struct Logs: Codable, Hashable, Sendable {
    public let version: String?
    public let productData: [Product]?

    public struct Product: Codable, Hashable, Sendable {
      public let signatureId: String?
      public let diagnosticInsights: [Insight]?
      public let diagnosticLogs: [Log]?
    }

    public struct Insight: Codable, Hashable, Sendable {
      public let insightsURL: String?
      public let insightsCategory: String?
      public let insightsString: String?
    }

    public struct Log: Codable, Hashable, Sendable {
      public let callStackTree: [Tree]?
      public let diagnosticMetaData: MetaData?
    }

    public struct Tree: Codable, Hashable, Sendable {
      public let callStackPerThread: Bool?
      public let callStacks: [CallStack]?
    }

    public struct CallStack: Codable, Hashable, Sendable {
      public let callStackRootFrames: [Frame]?
    }

    public struct MetaData: Codable, Hashable, Sendable {
      public let bundleId: String?
      public let event: String?
      public let osVersion: String?
      public let appVersion: String?
      public let writesCaused: String?
      public let deviceType: String?
      public let platformArchitecture: String?
      public let eventDetail: String?
      public let buildVersion: String?
    }
  }

  /// A frame of a call stack: the frames it called sit under it.
  public struct Frame: Codable, Hashable, Sendable {
    public let sampleCount: Int?
    /// The frame App Store Connect blames for the issue.
    public let isBlameFrame: Bool?
    public let symbolName: String?
    public let insightsCategory: String?
    public let offsetIntoSymbol: String?
    public let binaryName: String?
    public let fileName: String?
    public let binaryUUID: String?
    public let lineNumber: String?
    public let address: String?
    public let rawFrame: String?
    public let subFrames: [Frame]?
  }

  /// A signature's logs (a few sampled events, each with its call stacks).
  public static func logs(signatureID: String, client: ASCClient) async throws -> Logs {
    let body = try await withTransientRetry {
      try await client.diagnosticSignaturesLogsGetToManyRelated(path: .init(id: signatureID), query: .init(limit: 200)).ok.body
    }
    guard case .applicationVnd_apple_diagnosticLogsJson(let document) = body else { return Logs(version: nil, productData: nil) }
    return try converted(document)
  }

  // MARK: Metrics

  /// Performance and power metrics: Apple's `xcode-metrics` document.
  public struct Metrics: Codable, Hashable, Sendable {
    public let version: String?
    public let insights: Insights?
    public let productData: [Product]?

    public struct Insights: Codable, Hashable, Sendable {
      public let trendingUp: [Insight]?
      public let regressions: [Insight]?
    }

    public struct Insight: Codable, Hashable, Sendable {
      public let metricCategory: String?
      public let latestVersion: String?
      public let metric: String?
      public let summaryString: String?
      /// The earlier versions it's compared with (Apple's spec says a string; it sends an array of
      /// version strings, seen 2026-11-04).
      public let referenceVersions: [String]?
      public let maxLatestVersionValue: Double?
      public let subSystemLabel: String?
      public let highImpact: Bool?
      public let populations: [Population]?
    }

    public struct Population: Codable, Hashable, Sendable {
      public let deltaPercentage: Double?
      public let percentile: String?
      public let summaryString: String?
      public let referenceAverageValue: Double?
      public let latestVersionValue: Double?
      public let device: String?
    }

    public struct Product: Codable, Hashable, Sendable {
      public let platform: String?
      public let metricCategories: [Category]?
    }

    public struct Category: Codable, Hashable, Sendable {
      /// `LAUNCH`, `HANG`, `MEMORY`, `DISK`, `BATTERY`, `TERMINATION`, `ANIMATION`, `STORAGE`.
      public let identifier: String?
      public let metrics: [Metric]?
    }

    public struct Metric: Codable, Hashable, Sendable {
      public let identifier: String?
      public let unit: Unit?
      public let datasets: [Dataset]?
    }

    public struct Unit: Codable, Hashable, Sendable {
      public let identifier: String?
      public let displayName: String?
    }

    public struct Dataset: Codable, Hashable, Sendable {
      public let filterCriteria: Criteria?
      public let points: [Point]?
    }

    public struct Criteria: Codable, Hashable, Sendable {
      public let percentile: String?
      public let device: String?
      public let deviceMarketingName: String?
    }

    public struct Point: Codable, Hashable, Sendable {
      public let version: String?
      public let value: Double?
      public let errorMargin: Double?
      public let goal: String?
    }
  }

  /// The metric categories (`LAUNCH`, `HANG`, …).
  public static let metricTypes = ["LAUNCH", "HANG", "MEMORY", "DISK", "BATTERY", "TERMINATION", "ANIMATION", "STORAGE"]

  /// An app's metrics across its recent versions, or one build's with `buildID`; `types` narrows
  /// the categories.
  public static func metrics(appID: String, buildID: String? = nil, types: [String]? = nil, client: ASCClient) async throws -> Metrics {
    if let buildID {
      typealias Filter = Operations.BuildsPerfPowerMetricsGetToManyRelated.Input.Query.FilterMetricTypePayloadPayload
      let body = try await withTransientRetry {
        try await client.buildsPerfPowerMetricsGetToManyRelated(
          path: .init(id: buildID), query: .init(filterMetricType: types.map { $0.compactMap(Filter.init(rawValue:)) })
        ).ok.body
      }
      guard case .applicationVnd_apple_xcodeMetricsJson(let document) = body else { return Metrics(version: nil, insights: nil, productData: nil) }
      return try converted(document)
    }
    typealias Filter = Operations.AppsPerfPowerMetricsGetToManyRelated.Input.Query.FilterMetricTypePayloadPayload
    let body = try await withTransientRetry {
      try await client.appsPerfPowerMetricsGetToManyRelated(
        path: .init(id: appID), query: .init(filterMetricType: types.map { $0.compactMap(Filter.init(rawValue:)) })
      ).ok.body
    }
    guard case .applicationVnd_apple_xcodeMetricsJson(let document) = body else { return Metrics(version: nil, insights: nil, productData: nil) }
    return try converted(document)
  }

  /// Apple's document as our model: the generated types encode with Apple's keys, which ours use.
  private static func converted<Source: Encodable, Target: Decodable>(_ source: Source) throws -> Target {
    try JSONDecoder().decode(Target.self, from: JSONEncoder().encode(source))
  }
}
