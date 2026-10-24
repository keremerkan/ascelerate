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
    /// An in-app event's localization (its event card and details page media).
    case eventLocalization(String)
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
    let types = Array(categoryPlacementTypes.values.joined())
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
    let byGroup = try await refDataSpecs(placementTypes: ["APP_SCREENSHOT"], client: client).images
    let slotGroups = slots.filter { $0.value.placementType == .appScreenshot }.mapValues(\.group)
    return displayTypeGroups.merging(slotGroups) { classic, _ in classic }.compactMapValues { byGroup[$0] }
  }

  /// The video specs each display type's app previews accept, keyed by display type, like
  /// `screenshotSpecs` (iPhone Duo's from its slot). Read live 2026-10-19: iPhone and iPhone Duo
  /// 1920×886 or 886×1920, iPad 13" 1600×1200 or 1200×1600, all 15–30 s at 23–30 fps with audio.
  public static func previewSpecs(client: ASCClient) async throws -> [String: [VideoSpec]] {
    let byGroup = try await refDataSpecs(placementTypes: ["APP_PREVIEW"], client: client).videos
    let slotGroups = slots.filter { $0.value.videoPlacementType == .appPreview }.mapValues(\.group)
    return displayTypeGroups.merging(slotGroups) { classic, _ in classic }.compactMapValues { byGroup[$0] }
  }

  /// The image and video specs a placement type accepts in a group, live from
  /// `appAssetLibraryRefData`: an in-app event card's (`EVENT_CARD_ASSET`, `DEFAULT_PROFILE`) are
  /// 16:9 images 1920–3840 wide and 16:9 videos of 15–30 s at 30 or 60 fps (read 2026-10-21).
  public static func placementSpecs(
    type: String, group: String, client: ASCClient
  ) async throws -> (images: [ImageSpec], videos: [VideoSpec]) {
    let specs = try await refDataSpecs(placementTypes: [type], client: client)
    return (specs.images[group] ?? [], specs.videos[group] ?? [])
  }

  /// The placement types a library asset of each category (`CREATIVE_ASSETS`,
  /// `APP_SCREENSHOTS_AND_PREVIEWS`) can go to.
  private static let categoryPlacementTypes: [String: [String]] = [
    "CREATIVE_ASSETS": [
      "PRODUCT_PAGE_HEADER_ASSET", "APP_STORE_SEARCH_RESULTS_ASSET", "EVENT_CARD_ASSET", "EVENT_DETAILS_PAGE_ASSET",
    ],
    "APP_SCREENSHOTS_AND_PREVIEWS": ["APP_SCREENSHOT", "APP_PREVIEW", "IMESSAGE_APP_SCREENSHOT"],
  ]

  /// Every image and video spec an asset of `category` can match, from `appAssetLibraryRefData`:
  /// App Store Connect takes an upload outside them, then fails it (seen 2026-10-21 with an
  /// iPhone screenshot uploaded as a creative asset).
  public static func specs(category: String, client: ASCClient) async throws -> (images: [ImageSpec], videos: [VideoSpec]) {
    let specs = try await refDataSpecs(placementTypes: categoryPlacementTypes[category] ?? [], client: client)
    return (Array(specs.images.values.joined()), Array(specs.videos.values.joined()))
  }

  /// A spec's aspect ratio ("16:9"), which bounds a range of sizes (a single size needs none).
  private static func aspect(_ ratio: String?) -> (width: Int, height: Int)? {
    let parts = ratio?.split(separator: ":").compactMap { Int($0) } ?? []
    return parts.count == 2 && parts[0] > 0 && parts[1] > 0 ? (parts[0], parts[1]) : nil
  }

  /// The image and video specs of a placement type's groups in `appAssetLibraryRefData`, keyed by
  /// placement group.
  private static func refDataSpecs(
    placementTypes: [String], client: ASCClient
  ) async throws -> (images: [String: [ImageSpec]], videos: [String: [VideoSpec]]) {
    let data = try await withTransientRetry {
      try await client.appAssetLibraryRefDataGetCollection(query: .init(filterPlacementTypes: placementTypes)).ok.body.json.data
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
          let isRange = minWidth != maxWidth || minHeight != maxHeight
          return (id, ImageSpec(
            widths: minWidth...maxWidth, heights: minHeight...maxHeight, aspect: isRange ? aspect(spec.aspectRatio) : nil,
            extensions: extensions,
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
          let isRange = minWidth != maxWidth || minHeight != maxHeight
          return (id, VideoSpec(
            widths: minWidth...maxWidth, heights: minHeight...maxHeight, aspect: isRange ? aspect(spec.aspectRatio) : nil,
            seconds: shortest...longest,
            frameRates: rates, requiresAudio: spec.audioRequired ?? false))
        }, uniquingKeysWith: { first, _ in first })
      for type in datum.attributes?.placementTypes ?? [] where placementTypes.contains(type.placementTypeId ?? "") {
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
      var event: Relationships.AppEventLocalizationPayload?
      switch owner {
        case .versionLocalization(let id): version = .init(data: .init(id: id, _type: "appStoreVersionLocalizations"))
        case .productPageLocalization(let id): productPage = .init(data: .init(id: id, _type: "appCustomProductPageLocalizations"))
        case .treatmentLocalization(let id):
          treatment = .init(data: .init(id: id, _type: "appStoreVersionExperimentTreatmentLocalizations"))
        case .eventLocalization(let id): event = .init(data: .init(id: id, _type: "appEventLocalizations"))
      }
      return try await client.appAssetLibraryPlacementsCreateInstance(body: .json(.init(data: .init(
        attributes: .init(placementGroup: group, placementType: type.rawValue),
        relationships: .init(
          appCustomProductPageLocalization: productPage, appEventLocalization: event,
          appStoreVersionExperimentTreatmentLocalization: treatment,
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
    try await ASCPaging.allPagesConcurrently(next: { $0.links.next }) {
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
    try await ASCPaging.allPagesConcurrently(next: { $0.links.next }) {
      try await withTransientRetry {
        try await client.appAssetLibrariesVideosGetToManyRelated(
          path: .init(id: libraryID), query: .init(limit: 200, include: [.placements], limitPlacements: 1)
        ).ok.body.json
      }
    }.flatMap(\.data)
  }

  public typealias PlacedImage = (image: Components.Schemas.AppAssetLibraryImage, placementState: String?)
  public typealias PlacedVideo = (video: Components.Schemas.AppAssetLibraryVideo, placementState: String?)

  /// A library's images and videos, each with the state of the one placement it comes with (nil
  /// without one), images newest first. An unreviewed asset whose placement is INACTIVE may be
  /// placed only on owners that were deleted (`usage(of:)` tells); an ACTIVE one is in use.
  /// The image pages after the first load a few at a time; `progress` gets everything read so far
  /// after each one (the videos with the first), and how many assets there are in all, so a large
  /// library can show its newest images while the rest load.
  public static func assetsWithPlacementState(
    libraryID: String, client: ASCClient,
    progress: (@Sendable (_ images: [PlacedImage], _ videos: [PlacedVideo], _ total: Int) async throws -> Void)? = nil
  ) async throws -> (images: [PlacedImage], videos: [PlacedVideo]) {
    let videoPages = Task {
      try await ASCPaging.allPagesConcurrently(next: { $0.links.next }) {
        try await withTransientRetry {
          try await client.appAssetLibrariesVideosGetToManyRelated(
            path: .init(id: libraryID),
            query: .init(fieldsAppAssetLibraryPlacements: [.state], limit: 200, include: [.placements], limitPlacements: 1)
          ).ok.body.json
        }
      }
    }
    defer { videoPages.cancel() }
    var images: [PlacedImage] = []
    var videos: [PlacedVideo]?
    var total = 0
    _ = try await ASCPaging.allPagesConcurrently(next: { $0.links.next }) { page in
      if videos == nil {
        let read = try await videoPages.value.flatMap { page in
          page.data.map { ($0, placementState($0.relationships?.placements?.data?.first?.id, in: page.included)) }
        }
        videos = read
        total = (page.meta?.paging.total ?? page.data.count) + read.count
      }
      images += page.data.map { ($0, placementState($0.relationships?.placements?.data?.first?.id, in: page.included)) }
      try await progress?(images, videos ?? [], total)
    } _: {
      try await withTransientRetry {
        try await client.appAssetLibrariesImagesGetToManyRelated(
          path: .init(id: libraryID),
          query: .init(
            sort: [.minusCreatedDate], fieldsAppAssetLibraryPlacements: [.state], limit: 200, include: [.placements],
            limitPlacements: 1)
        ).ok.body.json
      }
    }
    return (images, videos ?? [])
  }

  private static func placementState(_ id: String?, in included: [Components.Schemas.AppAssetLibraryPlacement]?) -> String? {
    id.flatMap { id in included?.first { $0.id == id }?.attributes?.state }
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
    try await ownerPlacements(on: owner, type: type, group: group, of: asset, client: client).data
  }

  /// An owner's placements with their images or videos, in their order.
  public static func placementsWithMedia(
    on owner: Owner, type: PlacementType, group: String, client: ASCClient
  ) async throws -> [(placement: Components.Schemas.AppAssetLibraryPlacement, image: Components.Schemas.AppAssetLibraryImage?, video: Components.Schemas.AppAssetLibraryVideo?)] {
    let result = try await ownerPlacements(on: owner, type: type, group: group, media: .full, client: client)
    var images: [String: Components.Schemas.AppAssetLibraryImage] = [:]
    var videos: [String: Components.Schemas.AppAssetLibraryVideo] = [:]
    for included in result.included {
      switch included {
        case .appAssetLibraryImages(let image): images[image.id] = image
        case .appAssetLibraryVideos(let video): videos[video.id] = video
        default: break
      }
    }
    return result.data.map { placement in
      let relationships = placement.relationships
      return (
        placement, relationships?.value1?.value2.image?.data.flatMap { images[$0.id] },
        relationships?.value2?.value2.video?.data.flatMap { videos[$0.id] }
      )
    }
  }

  /// Whether an owner's placements come with their images and videos, and how much of them.
  private enum IncludedMedia {
    case none, stateOnly, full
  }

  /// An owner's placements, every page, optionally narrowed to a type and group or to one asset,
  /// and with their images and videos as `media` asks. Placements keep their group order.
  private static func ownerPlacements(
    on owner: Owner, type: PlacementType? = nil, group: String? = nil, of asset: Asset? = nil, media: IncludedMedia = .none,
    client: ASCClient
  ) async throws -> (data: [Components.Schemas.AppAssetLibraryPlacement], included: [Components.Schemas.AppAssetLibraryPlacementsResponse.IncludedPayloadPayload]) {
    var imageID: String?, videoID: String?
    switch asset {
      case .image(let id): imageID = id
      case .video(let id): videoID = id
      case nil: break
    }
    let types = type.map { [$0.rawValue] }
    let groups = group.map { [$0] }
    let includingMedia = media != .none
    let stateOnly = media == .stateOnly
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        switch owner {
          case .versionLocalization(let id):
            try await client.appStoreVersionLocalizationsPlacementsGetToManyRelated(
              path: .init(id: id),
              query: .init(
                filterPlacementType: types?.compactMap { .init(rawValue: $0) }, filterPlacementGroup: groups,
                filterImage: imageID.map { [$0] }, filterVideo: videoID.map { [$0] }, sort: [.placementGroupPosition],
                fieldsAppAssetLibraryImages: stateOnly ? [.state] : nil, fieldsAppAssetLibraryVideos: stateOnly ? [.state] : nil,
                limit: 200, include: includingMedia ? [.image, .video] : nil)
            ).ok.body.json
          case .productPageLocalization(let id):
            try await client.appCustomProductPageLocalizationsPlacementsGetToManyRelated(
              path: .init(id: id),
              query: .init(
                filterPlacementType: types?.compactMap { .init(rawValue: $0) }, filterPlacementGroup: groups,
                filterImage: imageID.map { [$0] }, filterVideo: videoID.map { [$0] }, sort: [.placementGroupPosition],
                fieldsAppAssetLibraryImages: stateOnly ? [.state] : nil, fieldsAppAssetLibraryVideos: stateOnly ? [.state] : nil,
                limit: 200, include: includingMedia ? [.image, .video] : nil)
            ).ok.body.json
          case .treatmentLocalization(let id):
            try await client.appStoreVersionExperimentTreatmentLocalizationsPlacementsGetToManyRelated(
              path: .init(id: id),
              query: .init(
                filterPlacementType: types?.compactMap { .init(rawValue: $0) }, filterPlacementGroup: groups,
                filterImage: imageID.map { [$0] }, filterVideo: videoID.map { [$0] }, sort: [.placementGroupPosition],
                fieldsAppAssetLibraryImages: stateOnly ? [.state] : nil, fieldsAppAssetLibraryVideos: stateOnly ? [.state] : nil,
                limit: 200, include: includingMedia ? [.image, .video] : nil)
            ).ok.body.json
          case .eventLocalization(let id):
            try await client.appEventLocalizationsPlacementsGetToManyRelated(
              path: .init(id: id),
              query: .init(
                filterPlacementType: types?.compactMap { .init(rawValue: $0) }, filterPlacementGroup: groups,
                filterImage: imageID.map { [$0] }, filterVideo: videoID.map { [$0] }, sort: [.placementGroupPosition],
                fieldsAppAssetLibraryImages: stateOnly ? [.state] : nil, fieldsAppAssetLibraryVideos: stateOnly ? [.state] : nil,
                limit: 200, include: includingMedia ? [.image, .video] : nil)
            ).ok.body.json
        }
      }
    }
    return (pages.flatMap(\.data), pages.flatMap { $0.included ?? [] })
  }

  /// Deletes the placements of unreviewed images and videos on `owner`, for deleting the owner:
  /// deleting a custom product page leaves the placements still on it behind, INACTIVE and without
  /// an owner, and those keep their images from ever being deleted (seen live 2026-10-21; App
  /// Store Connect's own Delete fails on them too). Deleting them first leaves the images unplaced
  /// in the library instead (a placement's classic screenshot or preview goes with it). Placements
  /// of reviewed media, such as a new version's or a copied page's copies of the live version's,
  /// are left: those can't be deleted anyway, and there can be hundreds. Returns how many it deleted.
  @discardableResult
  public static func clearPlacements(on owner: Owner, client: ASCClient) async throws -> Int {
    let placements = try await ownerPlacements(on: owner, media: .stateOnly, client: client)
    var unreviewed = Set<String>()
    for included in placements.included {
      switch included {
        case .appAssetLibraryImages(let image) where unreviewedStates.contains(image.attributes?.stateName ?? ""):
          unreviewed.insert(image.id)
        case .appAssetLibraryVideos(let video) where unreviewedStates.contains(video.attributes?.stateName ?? ""):
          unreviewed.insert(video.id)
        default:
          break
      }
    }
    let ids = placements.data.filter { placement in
      let relationships = placement.relationships
      let media = relationships?.value1?.value2.image?.data?.id ?? relationships?.value2?.value2.video?.data?.id
      return media.map(unreviewed.contains) ?? false
    }.map(\.id)
    // Under dry run each stopped delete is printed and the owner's own delete still previewed.
    _ = try await boundedConcurrentMap(ids, maxConcurrent: 4) { id in
      try await unlessDryRunStopped { try await deletePlacement(id: id, client: client) }
    }
    return ids.count
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

  /// The asset and file name behind one placement. For an owner's placements, `placementsWithMedia`
  /// reads them all with their assets in one request.
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

  // MARK: - Removing images

  /// Image states before App Review. Images in any other state (in review, approved, rejected,
  /// archived) were reviewed and are never deleted by ascelerate.
  public static let unreviewedStates: Set<String> = [
    "AWAITING_UPLOAD", "UPLOAD_COMPLETE", "COMPLETE", "FAILED", "PREPARE_FOR_SUBMISSION",
  ]

  /// Deletes each of these library assets that `isUnused` allows; returns how many it deleted.
  /// An asset still placed anywhere (e.g. shared with the live version) is kept.
  public static func deleteIfUnused(_ assets: [Asset], client: ASCClient) async throws -> Int {
    try await boundedConcurrentMap(assets, maxConcurrent: 8) { try await deleteIfUnused($0, client: client) }.count(where: \.self)
  }

  /// Deletes a library image or video if `isUnused` allows it, checked against a fresh read.
  /// Returns whether it was deleted.
  public static func deleteIfUnused(_ asset: Asset, client: ASCClient) async throws -> Bool {
    do {
      switch asset {
        case .image(let id):
          let image = try await withTransientRetry { try await self.image(id: id, client: client) }
          guard isUnused(image) else { return false }
          _ = try await withTransientRetry { try await client.appAssetLibraryImagesDeleteInstance(path: .init(id: id)).noContent }
        case .video(let id):
          let video = try await withTransientRetry { try await self.video(id: id, client: client) }
          guard isUnused(video) else { return false }
          _ = try await withTransientRetry { try await client.appAssetLibraryVideosDeleteInstance(path: .init(id: id)).noContent }
      }
    } catch where ASCError.from(error)?.statusCode == 404 {
    }
    return true
  }

  /// One library image, with as much of its placements as `isUnused` needs.
  public static func image(id: String, client: ASCClient) async throws -> Components.Schemas.AppAssetLibraryImage {
    try await client.appAssetLibraryImagesGetInstance(path: .init(id: id), query: .init(include: [.placements], limitPlacements: 1))
      .ok.body.json.data
  }

  /// One library video, with as much of its placements as `isUnused` needs.
  public static func video(id: String, client: ASCClient) async throws -> Components.Schemas.AppAssetLibraryVideo {
    try await client.appAssetLibraryVideosGetInstance(path: .init(id: id), query: .init(include: [.placements], limitPlacements: 1))
      .ok.body.json.data
  }

  /// Gives an image or video a name of its own (App Store Connect's Name; the file name stays).
  public static func rename(_ asset: Asset, to name: String, client: ASCClient) async throws {
    try await update(asset, name: name, client: client)
  }

  /// Archives an image or video that went through review (App Store Connect's Archive Asset): it
  /// can't be deleted; it moves to the library's archived assets and can't be placed again.
  public static func archive(_ asset: Asset, client: ASCClient) async throws {
    try await update(asset, archived: true, client: client)
  }

  private static func update(_ asset: Asset, name: String? = nil, archived: Bool? = nil, client: ASCClient) async throws {
    switch asset {
      case .image(let id):
        _ = try await client.appAssetLibraryImagesUpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
          attributes: .init(archived: archived, referenceName: name), id: id, _type: "appAssetLibraryImages")))).ok
      case .video(let id):
        _ = try await client.appAssetLibraryVideosUpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
          attributes: .init(archived: archived, referenceName: name), id: id, _type: "appAssetLibraryVideos")))).ok
    }
  }

  /// Where an image or video is placed: one entry per placement, with what holds it.
  public struct Usage: Hashable, Sendable {
    public enum Kind: String, Sendable {
      case version, customProductPage, experimentTreatment, event
    }

    public let placementID: String
    public let placementType: String?
    public let placementGroup: String?
    public let state: String?
    public let kind: Kind
    /// The localization holding it and its language.
    public let localizationID: String?
    public let locale: String?
    /// What the localization belongs to: an App Store version, a custom product page version, a
    /// treatment or an in-app event (by ID).
    public let parentID: String?
  }

  /// An image's or video's placements with their owners (one request, plus one per owner).
  /// Deleting an owner (a custom product page, a test, an event) leaves its placements behind,
  /// INACTIVE and with no owner (seen live 2026-10-21); App Store Connect doesn't count those as
  /// uses ("This asset hasn't been used yet"), so they're left out. They still block deleting
  /// the asset (409 STATE_ERROR.ASSET_HAS_PLACEMENTS; App Store Connect's own Delete fails too),
  /// and a DELETE of such a placement answers 204 but leaves it in place.
  /// `parents: false` leaves `parentID` empty and skips those requests.
  public static func usage(of asset: Asset, parents: Bool = true, client: ASCClient) async throws -> [Usage] {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        switch asset {
          case .image(let id):
            try await client.appAssetLibraryImagesPlacementsGetToManyRelated(
              path: .init(id: id),
              query: .init(
                fieldsAppEventLocalizations: [.locale], fieldsAppStoreVersionLocalizations: [.locale],
                fieldsAppCustomProductPageLocalizations: [.locale], fieldsAppStoreVersionExperimentTreatmentLocalizations: [.locale],
                limit: 200,
                include: [
                  .appStoreVersionLocalization, .appCustomProductPageLocalization, .appStoreVersionExperimentTreatmentLocalization,
                  .appEventLocalization,
                ])
            ).ok.body.json
          case .video(let id):
            try await client.appAssetLibraryVideosPlacementsGetToManyRelated(
              path: .init(id: id),
              query: .init(
                fieldsAppEventLocalizations: [.locale], fieldsAppStoreVersionLocalizations: [.locale],
                fieldsAppCustomProductPageLocalizations: [.locale], fieldsAppStoreVersionExperimentTreatmentLocalizations: [.locale],
                limit: 200,
                include: [
                  .appStoreVersionLocalization, .appCustomProductPageLocalization, .appStoreVersionExperimentTreatmentLocalization,
                  .appEventLocalization,
                ])
            ).ok.body.json
        }
      }
    }
    var locales: [String: String] = [:]
    for included in pages.flatMap({ $0.included ?? [] }) {
      switch included {
        case .appStoreVersionLocalizations(let l): locales[l.id] = l.attributes?.locale
        case .appCustomProductPageLocalizations(let l): locales[l.id] = l.attributes?.locale
        case .appStoreVersionExperimentTreatmentLocalizations(let l): locales[l.id] = l.attributes?.locale
        case .appEventLocalizations(let l): locales[l.id] = l.attributes?.locale
        default: break
      }
    }
    let placed = pages.flatMap(\.data).compactMap { placement -> (placement: Components.Schemas.AppAssetLibraryPlacement, kind: Usage.Kind, localizationID: String)? in
      let common = placement.relationships.map { relationships -> Components.Schemas.AppAssetLibraryPlacementCommonRelationships? in
        relationships.value1?.value1 ?? relationships.value2?.value1
      } ?? nil
      if let id = common?.appStoreVersionLocalization?.data?.id { return (placement, .version, id) }
      if let id = common?.appCustomProductPageLocalization?.data?.id { return (placement, .customProductPage, id) }
      if let id = common?.appStoreVersionExperimentTreatmentLocalization?.data?.id { return (placement, .experimentTreatment, id) }
      if let id = common?.appEventLocalization?.data?.id { return (placement, .event, id) }
      return nil
    }
    // Included localizations come without their relationships (with or without fields), so each
    // one's parent is read on its own.
    let localizations = Dictionary(placed.map { ($0.localizationID, $0.kind) }, uniquingKeysWith: { first, _ in first })
    let parentIDs = !parents ? [:] : Dictionary(uniqueKeysWithValues: try await boundedConcurrentMap(Array(localizations)) { entry in
      (entry.key, try await parentID(of: entry.value, localizationID: entry.key, client: client))
    })
    return placed.map { placed in
      Usage(
        placementID: placed.placement.id, placementType: placed.placement.attributes?.placementType,
        placementGroup: placed.placement.attributes?.placementGroup, state: placed.placement.attributes?.state,
        kind: placed.kind, localizationID: placed.localizationID, locale: locales[placed.localizationID],
        parentID: parentIDs[placed.localizationID] ?? nil)
    }
  }

  /// What a localization holding a placement belongs to: its App Store version, custom product
  /// page version, treatment or in-app event.
  private static func parentID(of kind: Usage.Kind, localizationID id: String, client: ASCClient) async throws -> String? {
    switch kind {
      case .version:
        try await client.appStoreVersionLocalizationsGetInstance(path: .init(id: id), query: .init(include: [.appStoreVersion]))
          .ok.body.json.data.relationships?.appStoreVersion?.data?.id
      case .customProductPage:
        try await client.appCustomProductPageLocalizationsGetInstance(
          path: .init(id: id), query: .init(include: [.appCustomProductPageVersion])
        ).ok.body.json.data.relationships?.appCustomProductPageVersion?.data?.id
      case .experimentTreatment:
        try await client.appStoreVersionExperimentTreatmentLocalizationsGetInstance(
          path: .init(id: id), query: .init(include: [.appStoreVersionExperimentTreatment])
        ).ok.body.json.data.relationships?.appStoreVersionExperimentTreatment?.data?.id
      case .event:
        try await client.appEventLocalizationsGetInstance(path: .init(id: id), query: .init(include: [.appEvent]))
          .ok.body.json.data.relationships?.appEvent?.data?.id
    }
  }

  /// Whether ascelerate may delete a library image: it has no placement anywhere and never went
  /// through review. Versions share images (a new version's screenshots are placements of the
  /// previous version's images), and old versions keep theirs as INACTIVE placements of ARCHIVED
  /// images (verified back to a 2011 version, 2026-10-08), so an image no placement uses was only
  /// ever on a placement someone deleted. `image` must come with its placements included: a
  /// missing placements list counts as in use. So does a placement left behind by a deleted
  /// owner, which blocks deleting the asset all the same (see `usage(of:)`).
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
