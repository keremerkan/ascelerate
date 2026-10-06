import ASCKit
import Foundation
import ImageIO

/// App Asset Library (App Store Connect API 4.5.1): every app has a library of images and videos,
/// and "placements" put them on version, custom product page, event, and experiment localizations.
/// Existing screenshot sets show up as placements too (`APP_IPHONE_67` lands in
/// `IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE`), but some display classes, such as iPhone Duo, exist only
/// here and have no `ScreenshotDisplayType`. Verified live 2026-10-06: the library's ID equals the
/// app's ID, placements keep creation order (no ordering request needed), and placement states
/// include `ACTIVE`, which the spec's enum lacks.
enum AssetLibrary {
  /// Media folders with no `ScreenshotDisplayType` that upload through the library instead,
  /// mapped to their placement group (`appAssetLibraryRefData` placementProfileGroups).
  static let placementGroups = ["APP_IPHONE_DUO": "IPHONE_DUO_PROFILE"]

  /// Pixel sizes the library accepts per placement group (`appAssetLibraryRefData` imageSpecs):
  /// the Duo's inner display unfolded, then its cover display, each in both orientations.
  static let acceptedSizes = ["IPHONE_DUO_PROFILE": [(2853, 2007), (2007, 2853), (2034, 1398), (1398, 2034)]]

  static func libraryID(appID: String, client: ASCClient) async throws -> String {
    try await client.appsAssetLibraryGetToOneRelated(path: .init(id: appID)).ok.body.json.data.id
  }

  /// Throws if the image's pixel size is not one the placement group accepts.
  static func validateSize(of file: MediaFile, group: String) throws {
    guard let accepted = acceptedSizes[group] else { return }
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: file.path) as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else {
      throw MediaUploadError.cannotReadFile(file.path)
    }
    guard accepted.contains(where: { $0 == (width, height) }) else {
      throw MediaUploadError.unsupportedSize(width: width, height: height, accepted: accepted)
    }
  }

  /// Uploads an image to the library (reserve, upload chunks, commit) and returns its ID.
  static func uploadImage(_ file: MediaFile, libraryID: String, client: ASCClient) async throws -> String {
    try await uploadAsset(
      filePath: file.path,
      reserve: {
        let created = try await client.appAssetLibraryImagesCreateInstance(body: .json(.init(data: .init(
          attributes: .init(category: "APP_SCREENSHOTS_AND_PREVIEWS", fileName: file.fileName, fileSize: Int64(file.fileSize)),
          relationships: .init(assetLibrary: .init(data: .init(id: libraryID, _type: "appAssetLibraries"))),
          _type: "appAssetLibraryImages"
        )))).created.body.json.data
        guard case .awaitingUpload(let attributes) = created.attributes else {
          throw MediaUploadError.noUploadOperations
        }
        return (created.id, attributes.value2.uploadOperations ?? [])
      },
      // The library takes no checksum, only the uploaded flag.
      commit: { id, _ in
        _ = try await client.appAssetLibraryImagesUpdateInstance(
          path: .init(id: id),
          body: .json(.init(data: .init(attributes: .init(uploaded: true), id: id, _type: "appAssetLibraryImages")))
        ).ok
      }
    )
  }

  /// Places a library image on an App Store version localization as a screenshot in `group`.
  static func placeScreenshot(imageID: String, localizationID: String, group: String, client: ASCClient) async throws {
    _ = try await client.appAssetLibraryPlacementsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(placementGroup: group, placementType: "APP_SCREENSHOT"),
      relationships: .init(
        appStoreVersionLocalization: .init(data: .init(id: localizationID, _type: "appStoreVersionLocalizations")),
        image: .init(data: .init(id: imageID, _type: "appAssetLibraryImages"))
      ),
      _type: "appAssetLibraryPlacements"
    )))).created
  }

  /// The localization's screenshot placement IDs in `group`, in display order.
  static func screenshotPlacementIDs(localizationID: String, group: String, client: ASCClient) async throws -> [String] {
    try await client.appStoreVersionLocalizationsPlacementsGetToManyRelated(
      path: .init(id: localizationID),
      query: .init(filterPlacementType: [.appScreenshot], filterPlacementGroup: [group], sort: [.placementGroupPosition], limit: 200)
    ).ok.body.json.data.map(\.id)
  }

  static func deletePlacement(id: String, client: ASCClient) async throws {
    _ = try await client.appAssetLibraryPlacementsDeleteInstance(path: .init(id: id)).noContent
  }
}
