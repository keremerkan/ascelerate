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

  /// Deletes every screenshot in a set; returns how many there were. Under dry run the
  /// stopped deletes count as done.
  public static func deleteAllScreenshots(inSet setID: String, client: ASCClient) async throws -> Int {
    let screenshots = try await client.appScreenshotSetsAppScreenshotsGetToManyRelated(path: .init(id: setID)).ok.body.json.data
    for screenshot in screenshots { _ = try await unlessDryRunStopped { try await deleteScreenshot(screenshot.id, client: client) } }
    return screenshots.count
  }

  /// Deletes every preview in a set; returns how many there were. Under dry run the
  /// stopped deletes count as done.
  public static func deleteAllPreviews(inSet setID: String, client: ASCClient) async throws -> Int {
    let previews = try await client.appPreviewSetsAppPreviewsGetToManyRelated(path: .init(id: setID)).ok.body.json.data
    for preview in previews { _ = try await unlessDryRunStopped { try await deletePreview(preview.id, client: client) } }
    return previews.count
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
