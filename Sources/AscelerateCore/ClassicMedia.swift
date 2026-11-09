import ASCKit
import Foundation

// MARK: - Screenshot and Preview Writes

/// Writes to classic screenshot and preview sets, shared by `apps media` (version
/// localizations) and `product-pages media` (custom product page localizations).
public enum ClassicMedia {
  /// The localization a new set is created under.
  public typealias Owner = AssetLibrary.Owner

  public static func createScreenshotSet(
    _ displayType: ASCEnum.ScreenshotDisplayType, owner: Owner, client: ASCClient
  ) async throws -> String {
    typealias Relationships = Components.Schemas.AppScreenshotSetCreateRequest.DataPayload.RelationshipsPayload
    let relationships: Relationships
    switch owner {
    case .versionLocalization(let id):
      relationships = .init(appStoreVersionLocalization: .init(data: .init(id: id, _type: "appStoreVersionLocalizations")))
    case .productPageLocalization(let id):
      relationships = .init(appCustomProductPageLocalization: .init(data: .init(id: id, _type: "appCustomProductPageLocalizations")))
    case .treatmentLocalization(let id):
      relationships = .init(appStoreVersionExperimentTreatmentLocalization: .init(
        data: .init(id: id, _type: "appStoreVersionExperimentTreatmentLocalizations")))
    case .eventLocalization, .retentionMessageVersion:
      throw MediaUploadError.noMediaSets
    }
    return try await client.appScreenshotSetsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(screenshotDisplayType: displayType.rawValue),
      relationships: relationships,
      _type: "appScreenshotSets"
    )))).created.body.json.data.id
  }

  public static func createPreviewSet(
    _ previewType: ASCEnum.PreviewType, owner: Owner, client: ASCClient
  ) async throws -> String {
    typealias Relationships = Components.Schemas.AppPreviewSetCreateRequest.DataPayload.RelationshipsPayload
    let relationships: Relationships
    switch owner {
    case .versionLocalization(let id):
      relationships = .init(appStoreVersionLocalization: .init(data: .init(id: id, _type: "appStoreVersionLocalizations")))
    case .productPageLocalization(let id):
      relationships = .init(appCustomProductPageLocalization: .init(data: .init(id: id, _type: "appCustomProductPageLocalizations")))
    case .treatmentLocalization(let id):
      relationships = .init(appStoreVersionExperimentTreatmentLocalization: .init(
        data: .init(id: id, _type: "appStoreVersionExperimentTreatmentLocalizations")))
    case .eventLocalization, .retentionMessageVersion:
      throw MediaUploadError.noMediaSets
    }
    return try await client.appPreviewSetsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(previewType: previewType.rawValue),
      relationships: relationships,
      _type: "appPreviewSets"
    )))).created.body.json.data.id
  }

  /// Reserves, uploads and commits a screenshot in `setID`; returns its ID.
  public static func uploadScreenshot(_ file: MediaFile, setID: String, client: ASCClient) async throws -> String {
    try await uploadAsset(
      filePath: file.path,
      reserve: {
        let response = try await client.appScreenshotsCreateInstance(body: .json(.init(data: .init(
          attributes: .init(fileName: file.fileName, fileSize: file.fileSize),
          relationships: .init(appScreenshotSet: .init(data: .init(id: setID, _type: "appScreenshotSets"))),
          _type: "appScreenshots"
        )))).created.body.json
        return (response.data.id, response.data.attributes?.uploadOperations ?? [])
      },
      commit: { id, md5 in
        _ = try await client.appScreenshotsUpdateInstance(
          path: .init(id: id),
          body: .json(.init(data: .init(
            attributes: .init(sourceFileChecksum: md5, uploaded: true), id: id, _type: "appScreenshots")))
        ).ok
      })
  }

  /// Reserves, uploads and commits an app preview in `setID`; returns its ID.
  public static func uploadPreview(
    _ file: MediaFile, setID: String, previewFrame: String? = nil, client: ASCClient
  ) async throws -> String {
    try await uploadAsset(
      filePath: file.path,
      reserve: {
        let response = try await client.appPreviewsCreateInstance(body: .json(.init(data: .init(
          attributes: .init(
            fileName: file.fileName, fileSize: file.fileSize, mimeType: mediaMimeType(for: file.fileName),
            previewFrameTimeCode: previewFrame),
          relationships: .init(appPreviewSet: .init(data: .init(id: setID, _type: "appPreviewSets"))),
          _type: "appPreviews"
        )))).created.body.json
        return (response.data.id, response.data.attributes?.uploadOperations ?? [])
      },
      commit: { id, md5 in
        _ = try await client.appPreviewsUpdateInstance(
          path: .init(id: id),
          body: .json(.init(data: .init(
            attributes: .init(previewFrameTimeCode: previewFrame, sourceFileChecksum: md5, uploaded: true),
            id: id, _type: "appPreviews")))
        ).ok
      })
  }

  public static func deleteScreenshot(_ id: String, client: ASCClient) async throws {
    _ = try await client.appScreenshotsDeleteInstance(path: .init(id: id)).noContent
  }

  public static func deletePreview(_ id: String, client: ASCClient) async throws {
    _ = try await client.appPreviewsDeleteInstance(path: .init(id: id)).noContent
  }

  public static func deleteScreenshotSet(_ id: String, client: ASCClient) async throws {
    _ = try await client.appScreenshotSetsDeleteInstance(path: .init(id: id)).noContent
  }

  public static func deletePreviewSet(_ id: String, client: ASCClient) async throws {
    _ = try await client.appPreviewSetsDeleteInstance(path: .init(id: id)).noContent
  }

  /// How a set's uploaded screenshots or previews line up with a folder's files (`media upload
  /// --replace`). Apple keeps the MD5 sent when an item was committed (`sourceFileChecksum`), so an
  /// item with a file's checksum is that file, uploaded already: it's kept. Files without one are
  /// uploaded, items no file matches are deleted, and the set is then put in the files' order. A
  /// file in the folder twice takes two items.
  public struct SetSync: Equatable, Sendable {
    /// An item of the set as it stands: its checksum, nil when it can't be kept (failed, or
    /// its file never arrived).
    public struct Item: Equatable, Sendable {
      public let id: String
      public let checksum: String?

      public init(id: String, checksum: String?) {
        self.id = id
        self.checksum = checksum
      }
    }

    /// Per file, in the files' order: the item it matches (kept), or nil (to upload).
    public let kept: [String?]
    /// Items no file matches, in the set's order.
    public let deletions: [String]
    /// The set holds the files already, in their order, and nothing else.
    public let isUnchanged: Bool

    /// `files`: the files' MD5 checksums, in order; `current`: the set's items, in its order.
    public init(files: [String], current: [Item]) {
      var available = current.filter { $0.checksum != nil }
      var kept: [String?] = []
      for checksum in files {
        if let index = available.firstIndex(where: { $0.checksum?.caseInsensitiveCompare(checksum) == .orderedSame }) {
          kept.append(available.remove(at: index).id)
        } else {
          kept.append(nil)
        }
      }
      let keptIDs = Set(kept.compactMap(\.self))
      self.kept = kept
      deletions = current.map(\.id).filter { !keptIDs.contains($0) }
      isUnchanged = deletions.isEmpty && kept.allSatisfy { $0 != nil } && kept.compactMap(\.self) == current.map(\.id)
    }

    /// A screenshot as an item: kept unless it failed or is still awaiting its file.
    public static func item(_ screenshot: Components.Schemas.AppScreenshot) -> Item {
      Item(id: screenshot.id, checksum: keepable(screenshot.attributes?.assetDeliveryState) ? screenshot.attributes?.sourceFileChecksum : nil)
    }

    /// A preview as an item: kept unless it failed or is still awaiting its file.
    public static func item(_ preview: Components.Schemas.AppPreview) -> Item {
      Item(id: preview.id, checksum: keepable(preview.attributes?.assetDeliveryState) ? preview.attributes?.sourceFileChecksum : nil)
    }

    private static func keepable(_ state: Components.Schemas.AppMediaAssetState?) -> Bool {
      !["FAILED", "AWAITING_UPLOAD"].contains(state?.state ?? "")
    }
  }

  /// Sets the order of a screenshot set's screenshots.
  public static func reorderScreenshots(setID: String, ids: [String], client: ASCClient) async throws {
    _ = try await client.appScreenshotSetsAppScreenshotsReplaceToManyRelationship(
      path: .init(id: setID),
      body: .json(.init(data: ids.map { .init(id: $0, _type: "appScreenshots") }))
    ).noContent
  }

  /// Sets the order of a preview set's previews.
  public static func reorderPreviews(setID: String, ids: [String], client: ASCClient) async throws {
    _ = try await client.appPreviewSetsAppPreviewsReplaceToManyRelationship(
      path: .init(id: setID),
      body: .json(.init(data: ids.map { .init(id: $0, _type: "appPreviews") }))
    ).noContent
  }
}
