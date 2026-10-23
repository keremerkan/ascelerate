import ASCKit
import Foundation

/// What testers send from TestFlight: crash reports and screenshots, each with a comment and the
/// device's details (`betaFeedbackCrashSubmissions`, `betaFeedbackScreenshotSubmissions`).
public enum BetaFeedback {
  public enum Kind: String, Codable, Hashable, Sendable {
    case crash, screenshot
  }

  /// One image of a screenshot submission. Its URL is presigned and expires (`expirationDate`).
  public struct Image: Codable, Hashable, Sendable {
    public let url: String?
    public let width: Int?
    public let height: Int?
    public let expirationDate: Date?
  }

  public struct Submission: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: Kind
    public let createdDate: Date?
    public let email: String?
    public let comment: String?
    public let deviceModel: String?
    public let deviceFamily: String?
    public let osVersion: String?
    public let appPlatform: String?
    public let locale: String?
    public let timeZone: String?
    public let architecture: String?
    public let connectionType: String?
    public let batteryPercentage: Int?
    public let diskBytesAvailable: Int64?
    public let diskBytesTotal: Int64?
    public let appUptimeInMilliseconds: Int64?
    public let buildBundleID: String?
    public let buildID: String?
    /// The build's number (`CFBundleVersion`), when the build came included.
    public let buildNumber: String?
    /// A screenshot submission's images; empty for a crash.
    public let images: [Image]
  }

  public struct Page: Sendable {
    public let submissions: [Submission]
    /// The next page's link, for `page(…, after:)`; nil on the last page.
    public let next: String?
  }

  /// A page of the app's crash or screenshot feedback, newest first: the first one, or the one
  /// `after` links to. `platform` and `buildIDs` narrow it.
  public static func page(
    _ kind: Kind, appID: String, platform: Platform? = nil, buildIDs: [String]? = nil, limit: Int = 50,
    after link: String? = nil, client: ASCClient
  ) async throws -> Page {
    switch kind {
      case .crash:
        let response = try await ASCPaging.page(link) {
          try await client.appsBetaFeedbackCrashSubmissionsGetToManyRelated(
            path: .init(id: appID),
            query: .init(
              filterAppPlatform: platformFilter(platform), filterBuild: buildIDs, sort: [.minusCreatedDate],
              limit: min(limit, 200), include: [.build])
          ).ok.body.json
        }
        var numbers: [String: String] = [:]
        for case .builds(let build) in response.included ?? [] { numbers[build.id] = build.attributes?.version }
        return Page(
          submissions: response.data.map { Submission(crash: $0, buildNumbers: numbers) }, next: response.links.next)
      case .screenshot:
        let response = try await ASCPaging.page(link) {
          try await client.appsBetaFeedbackScreenshotSubmissionsGetToManyRelated(
            path: .init(id: appID),
            query: .init(
              filterAppPlatform: platformFilter(platform), filterBuild: buildIDs, sort: [.minusCreatedDate],
              limit: min(limit, 200), include: [.build])
          ).ok.body.json
        }
        var numbers: [String: String] = [:]
        for case .builds(let build) in response.included ?? [] { numbers[build.id] = build.attributes?.version }
        return Page(
          submissions: response.data.map { Submission(screenshot: $0, buildNumbers: numbers) }, next: response.links.next)
    }
  }

  /// One submission, as it is now (a screenshot's image URLs fresh).
  public static func submission(_ kind: Kind, id: String, client: ASCClient) async throws -> Submission {
    switch kind {
      case .crash:
        Submission(crash: try await client.betaFeedbackCrashSubmissionsGetInstance(path: .init(id: id)).ok.body.json.data)
      case .screenshot:
        Submission(
          screenshot: try await client.betaFeedbackScreenshotSubmissionsGetInstance(path: .init(id: id)).ok.body.json.data)
    }
  }

  /// A crash submission's crash log; nil when there's none.
  public static func crashLog(submissionID: String, client: ASCClient) async throws -> String? {
    let text = try await client.betaFeedbackCrashSubmissionsCrashLogGetToOneRelated(path: .init(id: submissionID))
      .ok.body.json.data.attributes?.logText
    return text?.isEmpty == false ? text : nil
  }

  public static func delete(_ kind: Kind, id: String, client: ASCClient) async throws {
    switch kind {
      case .crash: _ = try await client.betaFeedbackCrashSubmissionsDeleteInstance(path: .init(id: id)).noContent
      case .screenshot: _ = try await client.betaFeedbackScreenshotSubmissionsDeleteInstance(path: .init(id: id)).noContent
    }
  }
}

extension BetaFeedback.Submission {
  init(crash submission: Components.Schemas.BetaFeedbackCrashSubmission, buildNumbers: [String: String] = [:]) {
    let a = submission.attributes
    let buildID = submission.relationships?.build?.data?.id
    self.init(
      id: submission.id, kind: .crash, createdDate: a?.createdDate, email: a?.email, comment: a?.comment,
      deviceModel: a?.deviceModel, deviceFamily: a?.deviceFamily, osVersion: a?.osVersion, appPlatform: a?.appPlatform,
      locale: a?.locale, timeZone: a?.timeZone, architecture: a?.architecture, connectionType: a?.connectionType,
      batteryPercentage: a?.batteryPercentage, diskBytesAvailable: a?.diskBytesAvailable,
      diskBytesTotal: a?.diskBytesTotal, appUptimeInMilliseconds: a?.appUptimeInMilliseconds,
      buildBundleID: a?.buildBundleId, buildID: buildID, buildNumber: buildID.flatMap { buildNumbers[$0] }, images: [])
  }

  init(screenshot submission: Components.Schemas.BetaFeedbackScreenshotSubmission, buildNumbers: [String: String] = [:]) {
    let a = submission.attributes
    let buildID = submission.relationships?.build?.data?.id
    self.init(
      id: submission.id, kind: .screenshot, createdDate: a?.createdDate, email: a?.email, comment: a?.comment,
      deviceModel: a?.deviceModel, deviceFamily: a?.deviceFamily, osVersion: a?.osVersion, appPlatform: a?.appPlatform,
      locale: a?.locale, timeZone: a?.timeZone, architecture: a?.architecture, connectionType: a?.connectionType,
      batteryPercentage: a?.batteryPercentage, diskBytesAvailable: a?.diskBytesAvailable,
      diskBytesTotal: a?.diskBytesTotal, appUptimeInMilliseconds: a?.appUptimeInMilliseconds,
      buildBundleID: a?.buildBundleId, buildID: buildID, buildNumber: buildID.flatMap { buildNumbers[$0] },
      images: (a?.screenshots ?? []).map {
        BetaFeedback.Image(url: $0.url, width: $0.width, height: $0.height, expirationDate: $0.expirationDate)
      })
  }
}
