import ASCKit
import Foundation
import ImageIO

/// App Asset Library (App Store Connect API 4.5.1): every app has a library of images and videos,
/// and "placements" put them on version, custom product page, event, and experiment localizations.
/// Existing screenshot sets show up as placements too (`APP_IPHONE_67` lands in
/// `IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE`), but some display classes, such as iPhone Duo, exist only
/// here and have no `ScreenshotDisplayType`, and so do the product page header and search results
/// images (category `CREATIVE_ASSETS`). Verified live 2026-10-06: the library's ID equals the
/// app's ID, placements keep creation order (no ordering request needed), and placement states
/// include `ACTIVE`, which the spec's enum lacks.
enum AssetLibrary {
  typealias PlacementType =
    Operations.AppStoreVersionLocalizationsPlacementsGetToManyRelated.Input.Query.FilterPlacementTypePayloadPayload

  /// Image sizes and file types a placement accepts (`appAssetLibraryRefData` imageSpecs).
  struct ImageSpec: Sendable {
    let widths: ClosedRange<Int>
    let heights: ClosedRange<Int>
    /// Width:height a size in the ranges must match, for specs that aren't a single size.
    let aspect: (width: Int, height: Int)?
    let extensions: Set<String>

    static func size(_ width: Int, _ height: Int, _ extensions: Set<String>) -> ImageSpec {
      ImageSpec(widths: width...width, heights: height...height, aspect: nil, extensions: extensions)
    }

    func accepts(width: Int, height: Int, fileExtension: String) -> Bool {
      extensions.contains(fileExtension) && fits(width: width, height: height)
    }

    func fits(width: Int, height: Int) -> Bool {
      widths.contains(width) && heights.contains(height) && aspect.map { width * $0.height == height * $0.width } ?? true
    }

    var description: String {
      let types = extensions.sorted().filter { $0 != "jpeg" }.map { $0.uppercased() }.joined(separator: "/")
      guard let aspect else { return "\(widths.lowerBound)×\(heights.lowerBound) \(types)" }
      return "\(aspect.width):\(aspect.height) from \(widths.lowerBound)×\(heights.lowerBound) to \(widths.upperBound)×\(heights.upperBound) \(types)"
    }
  }

  /// A media folder whose images go through the library instead of a classic screenshot set.
  struct Slot: Sendable {
    /// What a file is called on its progress line.
    let fileLabel: String
    let placementType: PlacementType
    /// The placement profile group (`appAssetLibraryRefData` placementProfileGroups).
    let group: String
    let category: String
    let imageSpecs: [ImageSpec]
    /// One image per localization, replaced on upload, instead of an ordered set.
    let isSingle: Bool
    /// Placed on every platform's versions, not only iOS.
    let isPlatformIndependent: Bool
  }

  /// Whether a library image could belong to `slot`: same asset category and a size the slot
  /// accepts. An unplaced image has no placement to tell, so this is how `media library --only`
  /// tells a Duo screenshot (2853×2007) from a 6.9" one (1320×2868); an image with no size yet
  /// (an unfinished upload) matches no slot.
  static func image(_ image: Components.Schemas.AppAssetLibraryImage, fits slot: Slot) -> Bool {
    guard let common = image.attributes?.common, common.category == slot.category,
      let width = common.imageAsset?.width, let height = common.imageAsset?.height
    else { return false }
    return slot.imageSpecs.contains { $0.fits(width: width, height: height) }
  }

  /// Media folders uploaded through the library, by folder name. Specs from
  /// `appAssetLibraryRefData`, read live 2026-10-08: iPhone Duo (its inner display unfolded, then
  /// its cover display), and the product page header and search results images, which version,
  /// custom product page and product page optimization localizations each hold one of.
  static let slots: [String: Slot] = [
    "APP_IPHONE_DUO": Slot(
      fileLabel: "Screenshot", placementType: .appScreenshot, group: "IPHONE_DUO_PROFILE",
      category: "APP_SCREENSHOTS_AND_PREVIEWS",
      imageSpecs: [(2853, 2007), (2007, 2853), (2034, 1398), (1398, 2034)].map { .size($0.0, $0.1, ["png", "jpg", "jpeg"]) },
      isSingle: false, isPlatformIndependent: false),
    "PRODUCT_PAGE_HEADER": Slot(
      fileLabel: "Header    ", placementType: .productPageHeaderAsset, group: "DEFAULT_PROFILE",
      category: "CREATIVE_ASSETS",
      imageSpecs: [.size(3840, 1646, ["png"]), .size(5244, 2950, ["png"])],
      isSingle: true, isPlatformIndependent: true),
    "APP_STORE_SEARCH_RESULTS": Slot(
      fileLabel: "Search    ", placementType: .appStoreSearchResultsAsset, group: "DEFAULT_PROFILE",
      category: "CREATIVE_ASSETS",
      imageSpecs: [
        ImageSpec(widths: 1920...3840, heights: 1280...2560, aspect: (3, 2), extensions: ["png", "jpg", "jpeg"]),
        .size(5244, 2950, ["png"]),
      ],
      isSingle: true, isPlatformIndependent: true),
  ]

  static func libraryID(appID: String, client: ASCClient) async throws -> String {
    try await withTransientRetry {
      try await client.appsAssetLibraryGetToOneRelated(path: .init(id: appID)).ok.body.json.data.id
    }
  }

  /// Throws if the image's pixel size or file type is not one the slot accepts.
  static func validateSize(of file: MediaFile, slot: Slot) throws {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: file.path) as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else {
      throw MediaUploadError.cannotReadFile(file.path)
    }
    let fileExtension = (file.fileName as NSString).pathExtension.lowercased()
    guard slot.imageSpecs.contains(where: { $0.accepts(width: width, height: height, fileExtension: fileExtension) }) else {
      throw MediaUploadError.unsupportedImage(
        "\(width)×\(height) \(fileExtension.uppercased())", accepted: slot.imageSpecs.map(\.description))
    }
  }

  /// Uploads an image to the library (reserve, upload chunks, commit) and returns its ID.
  static func uploadImage(_ file: MediaFile, category: String, libraryID: String, client: ASCClient) async throws -> String {
    try await uploadAsset(
      filePath: file.path,
      reserve: {
        // Repeating a reserve whose connection dropped can at worst leave an unplaced image in
        // the library, which nothing shows.
        let created = try await withTransientRetry {
          try await client.appAssetLibraryImagesCreateInstance(body: .json(.init(data: .init(
            attributes: .init(category: category, fileName: file.fileName, fileSize: Int64(file.fileSize)),
            relationships: .init(assetLibrary: .init(data: .init(id: libraryID, _type: "appAssetLibraries"))),
            _type: "appAssetLibraryImages"
          )))).created.body.json.data
        }
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

  /// Places a library image on an App Store version localization in `slot` and returns the
  /// placement's ID. Transient failures are retried, but a dropped connection
  /// can hide a placement the server did create, and posting it again would show the screenshot
  /// twice, so a retry first looks for a placement of the same image.
  @discardableResult
  static func placeImage(imageID: String, localizationID: String, slot: Slot, client: ASCClient) async throws -> String {
    var isRetry = false
    return try await withTransientRetry {
      if isRetry,
        let existing = try await placements(localizationID: localizationID, slot: slot, imageID: imageID, client: client).first {
        return existing.id
      }
      isRetry = true
      return try await client.appAssetLibraryPlacementsCreateInstance(body: .json(.init(data: .init(
        attributes: .init(placementGroup: slot.group, placementType: slot.placementType.rawValue),
        relationships: .init(
          appStoreVersionLocalization: .init(data: .init(id: localizationID, _type: "appStoreVersionLocalizations")),
          image: .init(data: .init(id: imageID, _type: "appAssetLibraryImages"))
        ),
        _type: "appAssetLibraryPlacements"
      )))).created.body.json.data.id
    }
  }

  /// The localization's placements in `slot`, in display order, optionally only those of one image.
  static func placements(
    localizationID: String, slot: Slot, imageID: String? = nil, client: ASCClient
  ) async throws -> [Components.Schemas.AppAssetLibraryPlacement] {
    try await withTransientRetry {
      try await client.appStoreVersionLocalizationsPlacementsGetToManyRelated(
        path: .init(id: localizationID),
        query: .init(
          filterPlacementType: [slot.placementType], filterPlacementGroup: [slot.group], filterImage: imageID.map { [$0] },
          sort: [.placementGroupPosition], limit: 200)
      ).ok.body.json.data
    }
  }

  /// The ID and file name of a placement's image. The placement list can't include images
  /// (HTTP 500 every time, seen live 2026-10-07), so this costs one request per placement.
  static func placedImage(placementID: String, client: ASCClient) async throws -> (id: String?, fileName: String?) {
    let response = try await withTransientRetry {
      try await client.appAssetLibraryPlacementsGetInstance(path: .init(id: placementID), query: .init(include: [.image])).ok.body.json
    }
    var fileName: String?
    for case .appAssetLibraryImages(let image) in response.included ?? [] {
      fileName = image.attributes?.common.fileName
    }
    return (response.data.relationships?.value1?.value2.image?.data?.id, fileName)
  }

  static func placementFileName(id: String, client: ASCClient) async throws -> String? {
    try await placedImage(placementID: id, client: client).fileName
  }

  // MARK: - Removing images

  /// Image states before App Review. Images in any other state (in review, approved, rejected,
  /// archived) were reviewed and are never deleted by ascelerate.
  static let unreviewedStates: Set<String> = [
    "AWAITING_UPLOAD", "UPLOAD_COMPLETE", "COMPLETE", "FAILED", "PREPARE_FOR_SUBMISSION",
  ]

  /// Whether ascelerate may delete a library image: it has no placement anywhere and never went
  /// through review. Versions share images (a new version's screenshots are placements of the
  /// previous version's images), and old versions keep theirs as INACTIVE placements of ARCHIVED
  /// images (verified back to a 2011 version, 2026-10-08), so an image no placement uses was only
  /// ever on a placement someone deleted. `image` must come with its placements included: a
  /// missing placements list counts as in use.
  static func isUnused(_ image: Components.Schemas.AppAssetLibraryImage) -> Bool {
    guard let placements = image.relationships?.placements?.data else { return false }
    return placements.isEmpty && unreviewedStates.contains(image.attributes?.stateName ?? "")
  }

  /// Deletes a library image if `isUnused` allows it, checked against a fresh read. Returns
  /// whether it was deleted.
  static func deleteImageIfUnused(id: String, client: ASCClient) async throws -> Bool {
    let image = try await withTransientRetry {
      try await client.appAssetLibraryImagesGetInstance(
        path: .init(id: id), query: .init(include: [.placements], limitPlacements: 1)
      ).ok.body.json.data
    }
    guard isUnused(image) else { return false }
    do {
      _ = try await withTransientRetry {
        try await client.appAssetLibraryImagesDeleteInstance(path: .init(id: id)).noContent
      }
    } catch where ASCError.from(error)?.statusCode == 404 {
    }
    return true
  }

  /// Removes a placement, then deletes its library image when nothing uses it any more: a removed
  /// placement leaves its image in the library otherwise (seen live). Returns whether the image
  /// was deleted. Under dry run the delete is shown and not sent, and the image is kept.
  @discardableResult
  static func removePlacement(id: String, client: ASCClient) async throws -> Bool {
    let imageID = try await placedImage(placementID: id, client: client).id
    guard try await unlessDryRunStopped({ try await deletePlacement(id: id, client: client) }) != nil,
      let imageID
    else { return false }
    return try await deleteImageIfUnused(id: imageID, client: client)
  }

  /// Deletes a placement. One that is already gone (a retried delete, or removed elsewhere)
  /// counts as deleted.
  static func deletePlacement(id: String, client: ASCClient) async throws {
    do {
      _ = try await withTransientRetry {
        try await client.appAssetLibraryPlacementsDeleteInstance(path: .init(id: id)).noContent
      }
    } catch where ASCError.from(error)?.statusCode == 404 {
    }
  }
}

extension Components.Schemas.AppAssetLibraryImage.AttributesPayload {
  /// The image's raw state (the payload is discriminated by it).
  var stateName: String {
    switch self {
      case .accepted: "ACCEPTED"
      case .approved: "APPROVED"
      case .archived: "ARCHIVED"
      case .awaitingUpload: "AWAITING_UPLOAD"
      case .complete: "COMPLETE"
      case .failed: "FAILED"
      case .inReview: "IN_REVIEW"
      case .prepareForSubmission: "PREPARE_FOR_SUBMISSION"
      case .readyForReview: "READY_FOR_REVIEW"
      case .rejected: "REJECTED"
      case .uploadComplete: "UPLOAD_COMPLETE"
      case .waitingForReview: "WAITING_FOR_REVIEW"
    }
  }

  /// The attributes every image state shares (file name, size, …).
  var common: Components.Schemas.AppAssetLibraryImageCommonAttributes {
    switch self {
      case .complete(let attributes), .prepareForSubmission(let attributes): attributes
      case .accepted(let attributes): attributes.value1
      case .approved(let attributes): attributes.value1
      case .archived(let attributes): attributes.value1
      case .awaitingUpload(let attributes): attributes.value1
      case .failed(let attributes): attributes.value1
      case .inReview(let attributes): attributes.value1
      case .readyForReview(let attributes): attributes.value1
      case .rejected(let attributes): attributes.value1
      case .uploadComplete(let attributes): attributes.value1
      case .waitingForReview(let attributes): attributes.value1
    }
  }
}
