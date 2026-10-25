import ASCKit
import Foundation

/// Files sent to App Review with a version's App Review information (`appStoreReviewAttachments`):
/// list, upload, delete. They hang off the version's review record, which an upload creates when
/// the version has none yet.
public enum ReviewAttachments {
  public struct Attachment: Hashable, Sendable, Identifiable {
    public let id: String
    public let fileName: String?
    public let fileSize: Int?
    /// The raw asset delivery state: AWAITING_UPLOAD, UPLOAD_COMPLETE, COMPLETE or FAILED.
    public let state: String?
  }

  /// The version's App Review record ID; nil when the version has none yet.
  public static func detailID(versionID: String, client: ASCClient) async throws -> String? {
    try await optionalRelated {
      try await client.appStoreVersionsAppStoreReviewDetailGetToOneRelated(path: .init(id: versionID)).ok.body.json.data
    }?.id
  }

  /// The version's App Review record ID, creating an empty record when it has none.
  public static func ensureDetailID(versionID: String, client: ASCClient) async throws -> String {
    if let id = try await detailID(versionID: versionID, client: client) {
      return id
    }
    return try await client.appStoreReviewDetailsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(),
      relationships: .init(appStoreVersion: .init(data: .init(id: versionID, _type: "appStoreVersions"))),
      _type: "appStoreReviewDetails"
    )))).created.body.json.data.id
  }

  /// A review record's attachments (the first 50).
  public static func list(detailID: String, client: ASCClient) async throws -> [Attachment] {
    try await client.appStoreReviewDetailsAppStoreReviewAttachmentsGetToManyRelated(
      path: .init(id: detailID), query: .init(limit: 50)
    ).ok.body.json.data.map(attachment)
  }

  /// One attachment.
  public static func attachment(id: String, client: ASCClient) async throws -> Attachment {
    attachment(try await client.appStoreReviewAttachmentsGetInstance(path: .init(id: id)).ok.body.json.data)
  }

  /// Uploads a file as an attachment of the review record (reserve, upload, commit). Returns its ID.
  @discardableResult
  public static func upload(_ file: MediaFile, detailID: String, client: ASCClient) async throws -> String {
    try await uploadAsset(
      filePath: file.path,
      reserve: {
        let r = try await client.appStoreReviewAttachmentsCreateInstance(body: .json(.init(data: .init(
          attributes: .init(fileName: file.fileName, fileSize: file.fileSize),
          relationships: .init(
            appStoreReviewDetail: .init(data: .init(id: detailID, _type: "appStoreReviewDetails"))),
          _type: "appStoreReviewAttachments"
        )))).created.body.json
        return (r.data.id, r.data.attributes?.uploadOperations ?? [])
      },
      commit: { id, md5 in
        _ = try await client.appStoreReviewAttachmentsUpdateInstance(
          path: .init(id: id),
          body: .json(.init(data: .init(
            attributes: .init(sourceFileChecksum: md5, uploaded: true), id: id,
            _type: "appStoreReviewAttachments")))
        ).ok
      })
  }

  public static func delete(id: String, client: ASCClient) async throws {
    _ = try await client.appStoreReviewAttachmentsDeleteInstance(path: .init(id: id)).noContent
  }

  private static func attachment(_ data: Components.Schemas.AppStoreReviewAttachment) -> Attachment {
    Attachment(
      id: data.id, fileName: data.attributes?.fileName, fileSize: data.attributes?.fileSize,
      state: data.attributes?.assetDeliveryState?.state)
  }
}
