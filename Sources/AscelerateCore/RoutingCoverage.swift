import ASCKit
import Foundation

/// A version's routing app coverage file (`routingAppCoverages`): the .geojson of the regions a
/// navigation app gives directions in. A version holds one; replacing it is delete, then upload.
public enum RoutingCoverage {
  public struct Coverage: Hashable, Sendable, Identifiable {
    public let id: String
    public let fileName: String?
    public let fileSize: Int?
    /// The raw asset delivery state: AWAITING_UPLOAD, UPLOAD_COMPLETE, COMPLETE or FAILED.
    public let state: String?
  }

  /// The version's coverage file; nil when it has none.
  public static func coverage(versionID: String, client: ASCClient) async throws -> Coverage? {
    guard let data = try await optionalRelated({
      try await client.appStoreVersionsRoutingAppCoverageGetToOneRelated(path: .init(id: versionID)).ok.body.json.data
    }) else { return nil }
    return Coverage(
      id: data.id, fileName: data.attributes?.fileName, fileSize: data.attributes?.fileSize,
      state: data.attributes?.assetDeliveryState?.state)
  }

  public static func delete(id: String, client: ASCClient) async throws {
    _ = try await client.routingAppCoveragesDeleteInstance(path: .init(id: id)).noContent
  }

  /// Uploads a file as the version's coverage (reserve, upload, commit). The version mustn't have
  /// one already. Returns its ID.
  @discardableResult
  public static func upload(_ file: MediaFile, versionID: String, client: ASCClient) async throws -> String {
    try await uploadAsset(
      filePath: file.path,
      reserve: {
        let r = try await client.routingAppCoveragesCreateInstance(body: .json(.init(data: .init(
          attributes: .init(fileName: file.fileName, fileSize: file.fileSize),
          relationships: .init(appStoreVersion: .init(data: .init(id: versionID, _type: "appStoreVersions"))),
          _type: "routingAppCoverages"
        )))).created.body.json
        return (r.data.id, r.data.attributes?.uploadOperations ?? [])
      },
      commit: { id, md5 in
        _ = try await client.routingAppCoveragesUpdateInstance(
          path: .init(id: id),
          body: .json(.init(data: .init(
            attributes: .init(sourceFileChecksum: md5, uploaded: true), id: id, _type: "routingAppCoverages")))
        ).ok
      })
  }
}
