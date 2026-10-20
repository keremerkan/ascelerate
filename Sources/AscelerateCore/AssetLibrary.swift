import ASCKit
import Foundation

/// App Asset Library (App Store Connect API 4.5.1): every app has a library of images and videos,
/// and "placements" put them on version, custom product page, event, and experiment localizations.
/// Existing screenshot sets show up as placements too (`APP_IPHONE_67` lands in
/// `IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE`), but some display classes, such as iPhone Duo, exist only
/// here and have no `ScreenshotDisplayType`, and so do the product page header and search results
/// images (category `CREATIVE_ASSETS`). Verified live 2026-10-06: the library's ID equals the
/// app's ID, placements keep creation order (no ordering request needed), and placement states
/// include `ACTIVE`, which the spec's enum lacks.
public enum AssetLibrary {
  public typealias PlacementType =
    Operations.AppStoreVersionLocalizationsPlacementsGetToManyRelated.Input.Query.FilterPlacementTypePayloadPayload

  /// Image sizes and file types a placement accepts (`appAssetLibraryRefData` imageSpecs).
  public struct ImageSpec: Sendable {
    public let widths: ClosedRange<Int>
    public let heights: ClosedRange<Int>
    /// Width:height a size in the ranges must match, for specs that aren't a single size.
    public let aspect: (width: Int, height: Int)?
    public let extensions: Set<String>
    /// Whether the image may have an alpha channel; most current sizes refuse one.
    public var alphaAllowed = true

    public static func size(_ width: Int, _ height: Int, _ extensions: Set<String>) -> ImageSpec {
      ImageSpec(widths: width...width, heights: height...height, aspect: nil, extensions: extensions)
    }

    public func accepts(width: Int, height: Int, fileExtension: String) -> Bool {
      extensions.contains(fileExtension) && fits(width: width, height: height)
    }

    public func fits(width: Int, height: Int) -> Bool {
      widths.contains(width) && heights.contains(height) && aspect.map { width * $0.height == height * $0.width } ?? true
    }

    public var description: String {
      let types = extensions.sorted().filter { $0 != "jpeg" }.map { $0.uppercased() }.joined(separator: "/")
      guard let aspect else { return "\(widths.lowerBound)×\(heights.lowerBound) \(types)" }
      return "\(aspect.width):\(aspect.height) from \(widths.lowerBound)×\(heights.lowerBound) to \(widths.upperBound)×\(heights.upperBound) \(types)"
    }
  }

  /// Video sizes, lengths, frame rates and file types a placement accepts
  /// (`appAssetLibraryRefData` videoSpecs).
  public struct VideoSpec: Sendable {
    public let widths: ClosedRange<Int>
    public let heights: ClosedRange<Int>
    /// Width:height a size in the ranges must match, for specs that aren't a single size.
    public let aspect: (width: Int, height: Int)?
    public let seconds: ClosedRange<Double>
    /// Accepted frame rates (each a range; 30 and 60 are given as 30...30 and 60...60).
    public let frameRates: [ClosedRange<Double>]
    public let requiresAudio: Bool
    public let extensions: Set<String> = ["mp4", "m4v", "mov"]

    public static func size(
      _ width: Int, _ height: Int, seconds: ClosedRange<Double>, frameRates: [ClosedRange<Double>], requiresAudio: Bool
    ) -> VideoSpec {
      VideoSpec(
        widths: width...width, heights: height...height, aspect: nil, seconds: seconds, frameRates: frameRates,
        requiresAudio: requiresAudio)
    }

    public func accepts(width: Int, height: Int, seconds length: Double, fps: Double, hasAudio: Bool, fileExtension: String) -> Bool {
      extensions.contains(fileExtension) && widths.contains(width) && heights.contains(height)
        && (aspect.map { width * $0.height == height * $0.width } ?? true)
        && seconds.contains(length.rounded(.down))
        // 29.97 fps counts as 30.
        && frameRates.contains { ($0.lowerBound - 0.5)...($0.upperBound + 0.5) ~= fps }
        && (hasAudio || !requiresAudio)
    }

    public var description: String {
      let size = aspect.map { "\($0.width):\($0.height) from \(widths.lowerBound)×\(heights.lowerBound) to \(widths.upperBound)×\(heights.upperBound)" }
        ?? "\(widths.lowerBound)×\(heights.lowerBound)"
      let rates = frameRates.map { $0.lowerBound == $0.upperBound ? "\(Int($0.lowerBound))" : "\(Int($0.lowerBound))–\(Int($0.upperBound))" }
      return "\(size), \(Int(seconds.lowerBound))–\(Int(seconds.upperBound)) s at \(rates.joined(separator: " or ")) fps\(requiresAudio ? " with audio" : "")"
    }
  }

  /// A media folder whose files go through the library instead of a classic screenshot set.
  public struct Slot: Sendable {
    /// What an image is called on its progress line.
    public let fileLabel: String
    public let placementType: PlacementType
    /// The placement profile group (`appAssetLibraryRefData` placementProfileGroups).
    public let group: String
    public let category: String
    public let imageSpecs: [ImageSpec]
    /// Where the folder's videos go (header and search results take a video in the same place as
    /// the image; iPhone Duo previews are their own placement type), or nil for images only.
    public var videoPlacementType: PlacementType? = nil
    public var videoSpecs: [VideoSpec] = []
    /// What a video is called on its progress line.
    public var videoLabel = "Preview   "
    /// One file (image or video) per localization, replaced on upload, instead of an ordered set.
    public let isSingle: Bool
    /// Placed on every platform's versions, not only iOS.
    public let isPlatformIndependent: Bool
  }

  /// What a placement is on.
  public enum Owner: Sendable {
    case versionLocalization(String)
    case productPageLocalization(String)
    /// A product page optimization treatment's localization.
    case treatmentLocalization(String)
  }

  /// A library image or video.
  public enum Asset: Hashable, Sendable {
    case image(String)
    case video(String)

    public var id: String {
      switch self {
        case .image(let id), .video(let id): id
      }
    }
  }

  /// The placement group (`appAssetLibraryRefData` placementProfileGroups) each classic
  /// screenshot display type's screenshots and previews land in: used to find a classic set's
  /// library assets and, with `media library --only`, to recognize unplaced ones. A wrong entry
  /// can only miss a cleanup, since only unused assets are ever deleted.
  public static let displayTypeGroups: [String: String] = [
    "APP_IPHONE_67": "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE",
    "APP_IPHONE_65": "IPHONE_FACE_ID_LARGE_PROFILE",
    "APP_IPHONE_61": "IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE",
    "APP_IPHONE_58": "IPHONE_FACE_ID_MEDIUM_PROFILE",
    "APP_IPHONE_55": "IPHONE_HOME_BUTTON_LARGE_PROFILE",
    "APP_IPHONE_47": "IPHONE_HOME_BUTTON_MEDIUM_PROFILE",
    "APP_IPHONE_40": "IPHONE_HOME_BUTTON_40_PROFILE",
    "APP_IPHONE_35": "IPHONE_HOME_BUTTON_35_PROFILE",
    "APP_IPAD_PRO_3GEN_129": "IPAD_13_PROFILE",
    "APP_IPAD_PRO_129": "IPAD_129_PROFILE",
    "APP_IPAD_PRO_3GEN_11": "IPAD_11_PROFILE",
    "APP_IPAD_105": "IPAD_105_PROFILE",
    "APP_IPAD_97": "IPAD_97_PROFILE",
    "APP_DESKTOP": "MAC_PROFILE",
    "APP_APPLE_TV": "TV_PROFILE",
    "APP_APPLE_VISION_PRO": "VISION_PRO_PROFILE",
    "APP_WATCH_ULTRA": "WATCH_ULTRA_PROFILE",
    "APP_WATCH_SERIES_10": "WATCH_SERIES_10_PROFILE",
    "APP_WATCH_SERIES_7": "WATCH_SERIES_7_PROFILE",
    "APP_WATCH_SERIES_4": "WATCH_SERIES_4_PROFILE",
    "APP_WATCH_SERIES_3": "WATCH_SERIES_3_PROFILE",
  ]

  /// The spec IDs (`appAssetLibraryRefData`) each placement type and group accepts, keyed
  /// "TYPE|GROUP". Every library image and video records the spec it was accepted under, which is
  /// how `media library --only` tells an unplaced Duo screenshot from a 6.9" one, or a header
  /// video from a Duo preview.
  public static func specIDs(client: ASCClient) async throws -> [String: Set<String>] {
    let types = ["APP_SCREENSHOT", "APP_PREVIEW", "PRODUCT_PAGE_HEADER_ASSET", "APP_STORE_SEARCH_RESULTS_ASSET"]
    let data = try await withTransientRetry {
      try await client.appAssetLibraryRefDataGetCollection(query: .init(filterPlacementTypes: types)).ok.body.json.data
    }
    var result: [String: Set<String>] = [:]
    for datum in data {
      for type in datum.attributes?.placementTypes ?? [] {
        guard let typeID = type.placementTypeId else { continue }
        for mapping in type.specMappings ?? [] {
          guard let group = mapping.placementGroupId else { continue }
          result["\(typeID)|\(group)", default: []].formUnion(mapping.specs ?? [])
        }
      }
    }
    return result
  }

  /// The image specs each screenshot display type accepts, keyed by display type: those of its
  /// placement group in `appAssetLibraryRefData` (`displayTypeGroups`, plus the screenshot slots
  /// such as APP_IPHONE_DUO). Read live 2026-10-19, every one is a single size, in both
  /// orientations, and most refuse an alpha channel.
  public static func screenshotSpecs(client: ASCClient) async throws -> [String: [ImageSpec]] {
    let byGroup = try await refDataSpecs(placementType: "APP_SCREENSHOT", client: client).images
    let slotGroups = slots.filter { $0.value.placementType == .appScreenshot }.mapValues(\.group)
    return displayTypeGroups.merging(slotGroups) { classic, _ in classic }.compactMapValues { byGroup[$0] }
  }

  /// The video specs each display type's app previews accept, keyed by display type, like
  /// `screenshotSpecs` (iPhone Duo's from its slot). Read live 2026-10-19: iPhone and iPhone Duo
  /// 1920×886 or 886×1920, iPad 13" 1600×1200 or 1200×1600, all 15–30 s at 23–30 fps with audio.
  public static func previewSpecs(client: ASCClient) async throws -> [String: [VideoSpec]] {
    let byGroup = try await refDataSpecs(placementType: "APP_PREVIEW", client: client).videos
    let slotGroups = slots.filter { $0.value.videoPlacementType == .appPreview }.mapValues(\.group)
    return displayTypeGroups.merging(slotGroups) { classic, _ in classic }.compactMapValues { byGroup[$0] }
  }

  /// The image and video specs of a placement type's groups in `appAssetLibraryRefData`, keyed by
  /// placement group.
  private static func refDataSpecs(
    placementType: String, client: ASCClient
  ) async throws -> (images: [String: [ImageSpec]], videos: [String: [VideoSpec]]) {
    let data = try await withTransientRetry {
      try await client.appAssetLibraryRefDataGetCollection(query: .init(filterPlacementTypes: [placementType])).ok.body.json.data
    }
    var images: [String: [ImageSpec]] = [:]
    var videos: [String: [VideoSpec]] = [:]
    for datum in data {
      let imageSpecs = Dictionary(
        (datum.attributes?.imageSpecs ?? []).compactMap { spec -> (String, ImageSpec)? in
          guard let id = spec.specId, let size = spec.dimensions,
            let minWidth = size.minWidth, let maxWidth = size.maxWidth, let minHeight = size.minHeight,
            let maxHeight = size.maxHeight
          else { return nil }
          let extensions = Set((spec.fileExtensions ?? []).map { $0.trimmingPrefix(".").lowercased() })
          return (id, ImageSpec(
            widths: minWidth...maxWidth, heights: minHeight...maxHeight, aspect: nil, extensions: extensions,
            alphaAllowed: spec.alphaAllowed ?? true))
        }, uniquingKeysWith: { first, _ in first })
      let videoSpecs = Dictionary(
        (datum.attributes?.videoSpecs ?? []).compactMap { spec -> (String, VideoSpec)? in
          guard let id = spec.specId, let size = spec.dimensions,
            let minWidth = size.minWidth, let maxWidth = size.maxWidth, let minHeight = size.minHeight,
            let maxHeight = size.maxHeight,
            let shortest = spec.duration?.min.flatMap(seconds(iso8601:)),
            let longest = spec.duration?.max.flatMap(seconds(iso8601:))
          else { return nil }
          let rates = (spec.frameRates ?? []).compactMap { rate in
            rate.minFps.flatMap { low in rate.maxFps.map { Double(low)...Double($0) } }
          }
          return (id, VideoSpec(
            widths: minWidth...maxWidth, heights: minHeight...maxHeight, aspect: nil, seconds: shortest...longest,
            frameRates: rates, requiresAudio: spec.audioRequired ?? false))
        }, uniquingKeysWith: { first, _ in first })
      for type in datum.attributes?.placementTypes ?? [] where type.placementTypeId == placementType {
        for mapping in type.specMappings ?? [] {
          guard let group = mapping.placementGroupId else { continue }
          images[group, default: []] += (mapping.specs ?? []).compactMap { imageSpecs[$0] }
          videos[group, default: []] += (mapping.specs ?? []).compactMap { videoSpecs[$0] }
        }
      }
    }
    return (images, videos)
  }

  /// Seconds in an ISO 8601 duration as the reference data gives them ("PT15S", "PT1M30S").
  private static func seconds(iso8601 duration: String) -> Double? {
    guard let match = duration.wholeMatch(of: /PT(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?/) else { return nil }
    return Double(match.1.map { Int($0) ?? 0 } ?? 0) * 60 + (match.2.flatMap { Double($0) } ?? 0)
  }

  /// The classic preview type of a screenshot display type: its name without `APP_`. Watch and
  /// iMessage screenshots have no previews.
  public static func previewType(of displayType: String) -> ASCEnum.PreviewType? {
    guard displayType.hasPrefix("APP_"), !displayType.hasPrefix("APP_WATCH_") else { return nil }
    return ASCEnum.PreviewType(rawValue: String(displayType.dropFirst(4)))
  }

  /// Places a library image or video on an App Store version localization and returns the
  /// placement's ID. Transient failures are retried, but a dropped connection can hide a
  /// placement the server did create, and posting it again would show the asset twice, so a retry
  /// first looks for a placement of the same asset.
  @discardableResult
  public static func place(
    _ asset: Asset, on owner: Owner, type: PlacementType, group: String, client: ASCClient
  ) async throws -> String {
    var isRetry = false
    return try await withTransientRetry {
      if isRetry,
        let existing = try await placements(on: owner, type: type, group: group, of: asset, client: client).first {
        return existing.id
      }
      isRetry = true
      let image: Components.Schemas.AppAssetLibraryPlacementCreateRequest.DataPayload.RelationshipsPayload.ImagePayload? =
        if case .image(let id) = asset { .init(data: .init(id: id, _type: "appAssetLibraryImages")) } else { nil }
      let video: Components.Schemas.AppAssetLibraryPlacementCreateRequest.DataPayload.RelationshipsPayload.VideoPayload? =
        if case .video(let id) = asset { .init(data: .init(id: id, _type: "appAssetLibraryVideos")) } else { nil }
      typealias Relationships = Components.Schemas.AppAssetLibraryPlacementCreateRequest.DataPayload.RelationshipsPayload
      var version: Relationships.AppStoreVersionLocalizationPayload?
      var productPage: Relationships.AppCustomProductPageLocalizationPayload?
      var treatment: Relationships.AppStoreVersionExperimentTreatmentLocalizationPayload?
      switch owner {
        case .versionLocalization(let id): version = .init(data: .init(id: id, _type: "appStoreVersionLocalizations"))
        case .productPageLocalization(let id): productPage = .init(data: .init(id: id, _type: "appCustomProductPageLocalizations"))
        case .treatmentLocalization(let id):
          treatment = .init(data: .init(id: id, _type: "appStoreVersionExperimentTreatmentLocalizations"))
      }
      return try await client.appAssetLibraryPlacementsCreateInstance(body: .json(.init(data: .init(
        attributes: .init(placementGroup: group, placementType: type.rawValue),
        relationships: .init(
          appCustomProductPageLocalization: productPage, appStoreVersionExperimentTreatmentLocalization: treatment,
          appStoreVersionLocalization: version, image: image, video: video
        ),
        _type: "appAssetLibraryPlacements"
      )))).created.body.json.data.id
    }
  }

  /// Uploads a video to the library (reserve, upload chunks, commit) and returns its ID.
  public static func uploadVideo(_ file: MediaFile, category: String, libraryID: String, client: ASCClient) async throws -> String {
    try await uploadAsset(
      filePath: file.path,
      reserve: {
        // As with images, a repeated reserve can at worst leave an unplaced video behind.
        let created = try await withTransientRetry {
          try await client.appAssetLibraryVideosCreateInstance(body: .json(.init(data: .init(
            attributes: .init(category: category, fileName: file.fileName, fileSize: Int64(file.fileSize)),
            relationships: .init(assetLibrary: .init(data: .init(id: libraryID, _type: "appAssetLibraries"))),
            _type: "appAssetLibraryVideos"
          )))).created.body.json.data
        }
        guard case .awaitingUpload(let attributes) = created.attributes else {
          throw MediaUploadError.noUploadOperations
        }
        return (created.id, attributes.value2.uploadOperations ?? [])
      },
      commit: { id, _ in
        _ = try await client.appAssetLibraryVideosUpdateInstance(
          path: .init(id: id),
          body: .json(.init(data: .init(attributes: .init(uploaded: true), id: id, _type: "appAssetLibraryVideos")))
        ).ok
      }
    )
  }

  /// Uploads an image to the library (reserve, upload chunks, commit) and returns its ID.
  public static func uploadImage(_ file: MediaFile, category: String, libraryID: String, client: ASCClient) async throws -> String {
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

  /// Deletes a placement. One that is already gone (a retried delete, or removed elsewhere)
  /// counts as deleted.
  public static func deletePlacement(id: String, client: ASCClient) async throws {
    do {
      _ = try await withTransientRetry {
        try await client.appAssetLibraryPlacementsDeleteInstance(path: .init(id: id)).noContent
      }
    } catch where ASCError.from(error)?.statusCode == 404 {
    }
  }

  public typealias ImageSort = Operations.AppAssetLibrariesImagesGetToManyRelated.Input.Query.SortPayloadPayload

  /// A library's images, each with at most one of its placements (enough to tell whether it's
  /// placed anywhere), 200 per page. `specIDs` limits them to images accepted under those specs
  /// (`specIDs(client:)` maps a placement type and group to its specs, e.g. the 6.9" iPhone's
  /// screenshots); nil lists every image.
  public static func images(
    libraryID: String, specIDs: [String]? = nil, sort: ImageSort? = nil, client: ASCClient
  ) async throws -> [Components.Schemas.AppAssetLibraryImage] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await withTransientRetry {
        try await client.appAssetLibrariesImagesGetToManyRelated(
          path: .init(id: libraryID),
          query: .init(
            filterSpecId: specIDs, sort: sort.map { [$0] }, limit: 200, include: [.placements], limitPlacements: 1)
        ).ok.body.json
      }
    }.flatMap(\.data)
  }

  /// Every video in a library, like `images(libraryID:client:)`.
  public static func videos(libraryID: String, client: ASCClient) async throws -> [Components.Schemas.AppAssetLibraryVideo] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await withTransientRetry {
        try await client.appAssetLibrariesVideosGetToManyRelated(
          path: .init(id: libraryID), query: .init(limit: 200, include: [.placements], limitPlacements: 1)
        ).ok.body.json
      }
    }.flatMap(\.data)
  }

  /// The placement types and groups a `media library --only` kind covers: a library folder's
  /// own (Duo screenshots and previews, the header, search results), or a classic display type's
  /// screenshots and previews.
  public static func placementTargets(ofKind kind: String) -> [(type: String, group: String)]? {
    if let slot = slots[kind] {
      return [(slot.placementType.rawValue, slot.group)] + (slot.videoPlacementType.map { [($0.rawValue, slot.group)] } ?? [])
    }
    guard let group = displayTypeGroups[kind] else { return nil }
    return [("APP_SCREENSHOT", group), ("APP_PREVIEW", group)]
  }

  /// Media folders uploaded through the library, by folder name. Specs from
  /// `appAssetLibraryRefData`, read live 2026-10-08: iPhone Duo (its inner display unfolded, then
  /// its cover display), and the product page header and search results images, which version,
  /// custom product page and product page optimization localizations each hold one of.
  public static let slots: [String: Slot] = [
    "APP_IPHONE_DUO": Slot(
      fileLabel: "Screenshot", placementType: .appScreenshot, group: "IPHONE_DUO_PROFILE",
      category: "APP_SCREENSHOTS_AND_PREVIEWS",
      imageSpecs: [(2853, 2007), (2007, 2853), (2034, 1398), (1398, 2034)].map { .size($0.0, $0.1, ["png", "jpg", "jpeg"]) },
      videoPlacementType: .appPreview,
      videoSpecs: [(1920, 886), (886, 1920)].map {
        .size($0.0, $0.1, seconds: 15...30, frameRates: [23...30], requiresAudio: true)
      },
      isSingle: false, isPlatformIndependent: false),
    "PRODUCT_PAGE_HEADER": Slot(
      fileLabel: "Header    ", placementType: .productPageHeaderAsset, group: "DEFAULT_PROFILE",
      category: "CREATIVE_ASSETS",
      imageSpecs: [.size(3840, 1646, ["png"]), .size(5244, 2950, ["png"])],
      videoPlacementType: .productPageHeaderAsset,
      videoSpecs: [.size(3840, 1646, seconds: 5...30, frameRates: [30...30, 60...60], requiresAudio: false)],
      videoLabel: "Header    ",
      isSingle: true, isPlatformIndependent: true),
    "APP_STORE_SEARCH_RESULTS": Slot(
      fileLabel: "Search    ", placementType: .appStoreSearchResultsAsset, group: "DEFAULT_PROFILE",
      category: "CREATIVE_ASSETS",
      imageSpecs: [
        ImageSpec(widths: 1920...3840, heights: 1280...2560, aspect: (3, 2), extensions: ["png", "jpg", "jpeg"]),
        .size(5244, 2950, ["png"]),
      ],
      videoPlacementType: .appStoreSearchResultsAsset,
      videoSpecs: [
        VideoSpec(
          widths: 1920...3840, heights: 1280...2560, aspect: (3, 2), seconds: 5...30, frameRates: [30...30, 60...60],
          requiresAudio: false)
      ],
      videoLabel: "Search    ",
      isSingle: true, isPlatformIndependent: true),
  ]

  public static func libraryID(appID: String, client: ASCClient) async throws -> String {
    try await withTransientRetry {
      try await client.appsAssetLibraryGetToOneRelated(path: .init(id: appID)).ok.body.json.data.id
    }
  }


  /// The localization's placements in `slot`, in display order, optionally only those of one asset.
  public static func placements(
    localizationID: String, slot: Slot, of asset: Asset? = nil, client: ASCClient
  ) async throws -> [Components.Schemas.AppAssetLibraryPlacement] {
    try await placements(
      localizationID: localizationID, type: slot.placementType, group: slot.group, of: asset, client: client)
  }

  public static func placements(
    localizationID: String, type: PlacementType, group: String, of asset: Asset? = nil, client: ASCClient
  ) async throws -> [Components.Schemas.AppAssetLibraryPlacement] {
    try await placements(on: .versionLocalization(localizationID), type: type, group: group, of: asset, client: client)
  }

  /// The placements of `type` in `group` on `owner`, in display order, optionally only those of
  /// one asset.
  public static func placements(
    on owner: Owner, type: PlacementType, group: String, of asset: Asset? = nil, client: ASCClient
  ) async throws -> [Components.Schemas.AppAssetLibraryPlacement] {
    var imageID: String?, videoID: String?
    switch asset {
      case .image(let id): imageID = id
      case .video(let id): videoID = id
      case nil: break
    }
    return try await withTransientRetry {
      switch owner {
        case .versionLocalization(let id):
          return try await client.appStoreVersionLocalizationsPlacementsGetToManyRelated(
            path: .init(id: id),
            query: .init(
              filterPlacementType: [type], filterPlacementGroup: [group], filterImage: imageID.map { [$0] },
              filterVideo: videoID.map { [$0] }, sort: [.placementGroupPosition], limit: 200)
          ).ok.body.json.data
        case .productPageLocalization(let id):
          let pageType = Operations.AppCustomProductPageLocalizationsPlacementsGetToManyRelated.Input.Query
            .FilterPlacementTypePayloadPayload(rawValue: type.rawValue)
          return try await client.appCustomProductPageLocalizationsPlacementsGetToManyRelated(
            path: .init(id: id),
            query: .init(
              filterPlacementType: pageType.map { [$0] } ?? [], filterPlacementGroup: [group],
              filterImage: imageID.map { [$0] }, filterVideo: videoID.map { [$0] }, sort: [.placementGroupPosition], limit: 200)
          ).ok.body.json.data
        case .treatmentLocalization(let id):
          let treatmentType = Operations.AppStoreVersionExperimentTreatmentLocalizationsPlacementsGetToManyRelated.Input.Query
            .FilterPlacementTypePayloadPayload(rawValue: type.rawValue)
          return try await client.appStoreVersionExperimentTreatmentLocalizationsPlacementsGetToManyRelated(
            path: .init(id: id),
            query: .init(
              filterPlacementType: treatmentType.map { [$0] } ?? [], filterPlacementGroup: [group],
              filterImage: imageID.map { [$0] }, filterVideo: videoID.map { [$0] }, sort: [.placementGroupPosition], limit: 200)
          ).ok.body.json.data
      }
    }
  }

  /// Every placement of the library folders (iPhone Duo screenshots and previews, header, search
  /// results) on `owner`, with the folder name it belongs to.
  public static func slotPlacements(on owner: Owner, client: ASCClient) async throws
    -> [(kind: String, placement: Components.Schemas.AppAssetLibraryPlacement)] {
    var result: [(String, Components.Schemas.AppAssetLibraryPlacement)] = []
    for (name, slot) in slots.sorted(by: { $0.key < $1.key }) {
      var types = [slot.placementType]
      if let videoType = slot.videoPlacementType, videoType != slot.placementType { types.append(videoType) }
      for type in types {
        result += try await placements(on: owner, type: type, group: slot.group, client: client).map { (name, $0) }
      }
    }
    return result
  }

  /// The asset and file name behind a placement. The placement list can't include its assets
  /// (HTTP 500 every time, seen live 2026-10-07), so this costs one request per placement.
  public static func placedAsset(placementID: String, client: ASCClient) async throws -> (asset: Asset?, fileName: String?) {
    let response = try await withTransientRetry {
      try await client.appAssetLibraryPlacementsGetInstance(
        path: .init(id: placementID), query: .init(include: [.image, .video])
      ).ok.body.json
    }
    var fileName: String?
    for included in response.included ?? [] {
      switch included {
        case .appAssetLibraryImages(let image): fileName = image.attributes?.common.fileName
        case .appAssetLibraryVideos(let video): fileName = video.attributes?.common.fileName
        default: break
      }
    }
    let relationships = response.data.relationships
    if let id = relationships?.value1?.value2.image?.data?.id { return (.image(id), fileName) }
    if let id = relationships?.value2?.value2.video?.data?.id { return (.video(id), fileName) }
    return (nil, fileName)
  }

  public static func placementFileName(id: String, client: ASCClient) async throws -> String? {
    try await placedAsset(placementID: id, client: client).fileName
  }

  // MARK: - Removing images

  /// Image states before App Review. Images in any other state (in review, approved, rejected,
  /// archived) were reviewed and are never deleted by ascelerate.
  public static let unreviewedStates: Set<String> = [
    "AWAITING_UPLOAD", "UPLOAD_COMPLETE", "COMPLETE", "FAILED", "PREPARE_FOR_SUBMISSION",
  ]

  /// Whether ascelerate may delete a library image: it has no placement anywhere and never went
  /// through review. Versions share images (a new version's screenshots are placements of the
  /// previous version's images), and old versions keep theirs as INACTIVE placements of ARCHIVED
  /// images (verified back to a 2011 version, 2026-10-08), so an image no placement uses was only
  /// ever on a placement someone deleted. `image` must come with its placements included: a
  /// missing placements list counts as in use.
  public static func isUnused(_ image: Components.Schemas.AppAssetLibraryImage) -> Bool {
    guard let placements = image.relationships?.placements?.data else { return false }
    return placements.isEmpty && unreviewedStates.contains(image.attributes?.stateName ?? "")
  }

  /// The same rule for a library video.
  public static func isUnused(_ video: Components.Schemas.AppAssetLibraryVideo) -> Bool {
    guard let placements = video.relationships?.placements?.data else { return false }
    return placements.isEmpty && unreviewedStates.contains(video.attributes?.stateName ?? "")
  }
}

extension Components.Schemas.AppAssetLibraryVideo.AttributesPayload {
  /// The video's raw state (the payload is discriminated by it).
  public var stateName: String {
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

  /// The attributes every video state shares (file name, size, spec, …).
  public var common: Components.Schemas.AppAssetLibraryVideoCommonAttributes {
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

extension Components.Schemas.AppAssetLibraryImage.AttributesPayload {
  /// The image's raw state (the payload is discriminated by it).
  public var stateName: String {
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
  public var common: Components.Schemas.AppAssetLibraryImageCommonAttributes {
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
