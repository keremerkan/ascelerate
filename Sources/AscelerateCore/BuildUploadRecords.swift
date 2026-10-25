import ASCKit
import Foundation

/// An app's build upload records (`buildUploads`), from the API's uploads and altool's alike: each
/// with its state and Apple's errors, warnings and notes. Uploads leave records behind that never
/// complete (a second one made when a flaky connection sent the create request again, or one
/// whose run failed); `stale` finds them.
public enum BuildUploadRecords {
  /// One of Apple's messages about an upload.
  public struct Detail: Hashable, Sendable {
    public let code: String?
    public let description: String?

    /// "CODE: description", or whichever there is.
    public var text: String {
      [code, description].compactMap { $0 }.joined(separator: ": ")
    }
  }

  public struct Upload: Hashable, Identifiable, Sendable {
    public let id: String
    public let version: String?
    public let build: String?
    /// The raw platform: IOS, MAC_OS, TV_OS, VISION_OS.
    public let platform: String?
    /// AWAITING_UPLOAD, PROCESSING, COMPLETE or FAILED.
    public let state: String?
    public let createdDate: Date?
    /// When the file arrived; nil for a record that never got one.
    public let uploadedDate: Date?
    /// Nil when Apple sends none at all, empty when it sends an empty list.
    public let errors: [Detail]?
    public let warnings: [Detail]?
    public let infos: [Detail]?
  }

  /// The app's upload records, newest first (Apple sorts records without an upload date first
  /// whatever the order, so all are read and ordered by creation here). The filters narrow it to
  /// a version, a build number, a platform.
  public static func list(
    appID: String, version: String? = nil, build: String? = nil, platform: String? = nil, client: ASCClient
  ) async throws -> [Upload] {
    typealias PlatformFilter = Operations.AppsBuildUploadsGetToManyRelated.Input.Query.FilterPlatformPayloadPayload
    return try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.appsBuildUploadsGetToManyRelated(
        path: .init(id: appID),
        query: .init(
          filterCfBundleShortVersionString: version.map { [$0] }, filterCfBundleVersion: build.map { [$0] },
          filterPlatform: platform.flatMap(PlatformFilter.init(rawValue:)).map { [$0] }, limit: 200)
      ).ok.body.json
    }.flatMap(\.data).map(upload).sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
  }

  /// The records that will never complete: still waiting for their file while another upload of
  /// the same build has moved past that, or for over a day. A slow upload in progress is neither,
  /// so it's never included.
  public static func stale(
    appID: String, version: String? = nil, build: String? = nil, platform: String? = nil, client: ASCClient
  ) async throws -> [Upload] {
    stale(in: try await list(appID: appID, version: version, build: build, platform: platform, client: client))
  }

  /// The records of `uploads` that will never complete (see `stale(appID:…)`).
  public static func stale(in uploads: [Upload], now: Date = .now) -> [Upload] {
    let key = { (u: Upload) in [u.version, u.build, u.platform].map { $0 ?? "" } }
    let waiting = { (u: Upload) in u.state == "AWAITING_UPLOAD" }
    let movedOn = Set(uploads.filter { !waiting($0) }.map(key))
    let dayAgo = now.addingTimeInterval(-24 * 3600)
    return uploads.filter { u in
      waiting(u) && (movedOn.contains(key(u)) || (u.createdDate ?? .distantFuture) < dayAgo)
    }
  }

  public static func delete(id: String, client: ASCClient) async throws {
    _ = try await withTransientRetry { try await client.buildUploadsDeleteInstance(path: .init(id: id)).noContent }
  }

  private static func upload(_ data: Components.Schemas.BuildUpload) -> Upload {
    let a = data.attributes
    let details = { (list: [Components.Schemas.StateDetail]?) in
      list.map { $0.map { Detail(code: $0.code, description: $0.description) } }
    }
    return Upload(
      id: data.id, version: a?.cfBundleShortVersionString, build: a?.cfBundleVersion, platform: a?.platform,
      state: a?.state?.state, createdDate: a?.createdDate, uploadedDate: a?.uploadedDate,
      errors: details(a?.state?.errors), warnings: details(a?.state?.warnings), infos: details(a?.state?.infos))
  }
}
