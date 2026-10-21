import ASCKit
import Foundation

/// An app's in-app events: the event, its schedule per territory, its text per language, and its
/// event card and details page media. The media are asset library placements (`EVENT_CARD_ASSET`,
/// `EVENT_DETAILS_PAGE_ASSET`); an `appEventScreenshots` or `appEventVideoClips` upload becomes a
/// placement with the same ID (verified live 2026-10-21).
public enum AppEvents {
  /// When the event shows, in some territories (nil: all of them).
  public struct Schedule: Codable, Hashable, Sendable {
    public var territories: [String]?
    public var publishStart: Date?
    public var eventStart: Date?
    public var eventEnd: Date?

    public init(territories: [String]? = nil, publishStart: Date? = nil, eventStart: Date? = nil, eventEnd: Date? = nil) {
      self.territories = territories
      self.publishStart = publishStart
      self.eventStart = eventStart
      self.eventEnd = eventEnd
    }
  }

  public struct Event: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let referenceName: String
    /// `DRAFT`, `READY_FOR_REVIEW`, `WAITING_FOR_REVIEW`, `IN_REVIEW`, `REJECTED`, `ACCEPTED`,
    /// `APPROVED`, `PUBLISHED`, `PAST`, `ARCHIVED`…
    public let state: String?
    /// `LIVE_EVENT`, `PREMIERE`, `CHALLENGE`, `COMPETITION`, `NEW_SEASON`, `MAJOR_UPDATE`, `SPECIAL_EVENT`.
    public let badge: String?
    public let deepLink: String?
    /// `NO_COST_ASSOCIATED` (App Store Connect: In-App Purchase Not Required) or `IN_APP_PURCHASE`
    /// (Required). The API takes any string.
    public let purchaseRequirement: String?
    /// Empty until set; App Store Connect then shows the app's primary language.
    public let primaryLocale: String?
    /// `NORMAL` or `HIGH`.
    public let priority: String?
    /// `APPROPRIATE_FOR_ALL_USERS`, `ATTRACT_NEW_USERS`, `KEEP_ACTIVE_USERS_INFORMED`, `BRING_BACK_LAPSED_USERS`.
    public let purpose: String?
    public let schedules: [Schedule]
    public let archivedSchedules: [Schedule]
  }

  public struct Localization: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let locale: String
    public let name: String?
    public let shortDescription: String?
    public let longDescription: String?
  }

  public enum AssetType: String, CaseIterable, Sendable {
    /// The card in the App Store: 1920×1080 or 3840×2160.
    case eventCard = "EVENT_CARD"
    /// The event's own page: 1080×1920 or 2160×3840.
    case eventDetailsPage = "EVENT_DETAILS_PAGE"
  }

  /// An event card or details page image or video.
  public struct Media: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let isVideo: Bool
    /// `EVENT_CARD` or `EVENT_DETAILS_PAGE`.
    public let assetType: String?
    /// The upload's state: `AWAITING_UPLOAD`, `UPLOAD_COMPLETE`, `COMPLETE` or `FAILED`.
    public let state: String?
    /// A video's processing state after the upload (`PROCESSING`, `COMPLETE`, `FAILED`…).
    public let videoState: String?
    public let fileName: String?
    /// The image (a video's preview image) as an URL template (`{w}x{h}bb.{f}`).
    public let imageTemplate: String?
    public let width: Int?
    public let height: Int?
    /// Where a processed video plays from.
    public let videoURL: String?
    public let errors: [String]
  }

  public enum LookupError: LocalizedError {
    case notFound(String)

    public var errorDescription: String? {
      switch self {
        case .notFound(let ref): "No in-app event '\(ref)' found for this app."
      }
    }
  }

  // MARK: Events

  public static func list(appID: String, states: [String]? = nil, client: ASCClient) async throws -> [Event] {
    typealias State = Operations.AppsAppEventsGetToManyRelated.Input.Query.FilterEventStatePayloadPayload
    let filter = states?.compactMap(State.init(rawValue:))
    return try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.appsAppEventsGetToManyRelated(path: .init(id: appID), query: .init(filterEventState: filter, limit: 200))
        .ok.body.json
    }.flatMap(\.data).map(event)
  }

  /// An app's event by reference name or ID.
  public static func find(_ ref: String, appID: String, client: ASCClient) async throws -> Event {
    guard let event = try await list(appID: appID, client: client).first(where: { $0.referenceName == ref || $0.id == ref })
    else { throw LookupError.notFound(ref) }
    return event
  }

  public static func get(id: String, client: ASCClient) async throws -> Event {
    event(try await client.appEventsGetInstance(path: .init(id: id)).ok.body.json.data)
  }

  /// A new draft event; nil fields are left unset.
  @discardableResult
  public static func create(
    appID: String, referenceName: String, badge: String? = nil, deepLink: String? = nil, primaryLocale: String? = nil,
    priority: String? = nil, purchaseRequirement: String? = nil, purpose: String? = nil, schedules: [Schedule]? = nil,
    client: ASCClient
  ) async throws -> Event {
    event(try await client.appEventsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(
        badge: badge, deepLink: deepLink, primaryLocale: primaryLocale, priority: priority,
        purchaseRequirement: purchaseRequirement, purpose: purpose, referenceName: referenceName,
        territorySchedules: schedules?.map {
          .init(eventEnd: $0.eventEnd, eventStart: $0.eventStart, publishStart: $0.publishStart, territories: $0.territories)
        }
      ),
      relationships: .init(app: .init(data: .init(id: appID, _type: "apps"))),
      _type: "appEvents"
    )))).created.body.json.data)
  }

  /// Changes an event's fields; nil ones are left as they are. `badge` and `deepLink` given as
  /// `.some(nil)` are removed (sent as null). `schedules` replaces every schedule.
  @discardableResult
  public static func update(
    id: String, referenceName: String? = nil, badge: String?? = nil, deepLink: String?? = nil, primaryLocale: String? = nil,
    priority: String? = nil, purchaseRequirement: String? = nil, purpose: String? = nil, schedules: [Schedule]? = nil,
    client: ASCClient
  ) async throws -> Event {
    var cleared: [[String]] = []
    if case .some(.none) = badge { cleared.append(["data", "attributes", "badge"]) }
    if case .some(.none) = deepLink { cleared.append(["data", "attributes", "deepLink"]) }
    return event(try await ASCNulls.sending(cleared) {
      try await client.appEventsUpdateInstance(
        path: .init(id: id),
        body: .json(.init(data: .init(
          attributes: .init(
            badge: badge ?? nil, deepLink: deepLink ?? nil, primaryLocale: primaryLocale, priority: priority,
            purchaseRequirement: purchaseRequirement, purpose: purpose, referenceName: referenceName,
            territorySchedules: schedules?.map {
              .init(eventEnd: $0.eventEnd, eventStart: $0.eventStart, publishStart: $0.publishStart, territories: $0.territories)
            }
          ),
          id: id,
          _type: "appEvents"
        )))
      ).ok.body.json.data
    })
  }

  /// Deletes an event, after its localizations' placements while it's a draft or rejected
  /// (`AssetLibrary.clearPlacements`; one that went through review holds only reviewed media).
  public static func delete(id: String, state: String? = nil, client: ASCClient) async throws {
    var state = state
    if state == nil { state = try await get(id: id, client: client).state }
    if ["DRAFT", "REJECTED"].contains(state) {
      for localization in try await localizations(eventID: id, client: client) {
        try await AssetLibrary.clearPlacements(on: .eventLocalization(localization.id), client: client)
      }
    }
    _ = try await client.appEventsDeleteInstance(path: .init(id: id)).noContent
  }

  // MARK: Localizations

  public static func localizations(eventID: String, client: ASCClient) async throws -> [Localization] {
    try await client.appEventsLocalizationsGetToManyRelated(path: .init(id: eventID), query: .init(limit: 50))
      .ok.body.json.data.compactMap(localization)
  }

  @discardableResult
  public static func createLocalization(
    eventID: String, locale: String, name: String? = nil, shortDescription: String? = nil, longDescription: String? = nil,
    client: ASCClient
  ) async throws -> Localization? {
    localization(try await client.appEventLocalizationsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(locale: locale, longDescription: longDescription, name: name, shortDescription: shortDescription),
      relationships: .init(appEvent: .init(data: .init(id: eventID, _type: "appEvents"))),
      _type: "appEventLocalizations"
    )))).created.body.json.data)
  }

  /// Changes a localization's text; nil fields are left as they are.
  @discardableResult
  public static func updateLocalization(
    id: String, name: String? = nil, shortDescription: String? = nil, longDescription: String? = nil, client: ASCClient
  ) async throws -> Localization? {
    localization(try await client.appEventLocalizationsUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(
        attributes: .init(longDescription: longDescription, name: name, shortDescription: shortDescription),
        id: id,
        _type: "appEventLocalizations"
      )))
    ).ok.body.json.data)
  }

  /// Deletes a language, after its placements (`AssetLibrary.clearPlacements`).
  public static func deleteLocalization(id: String, client: ASCClient) async throws {
    try await AssetLibrary.clearPlacements(on: .eventLocalization(id), client: client)
    _ = try await client.appEventLocalizationsDeleteInstance(path: .init(id: id)).noContent
  }

  // MARK: Media

  /// A localization's images and videos.
  public static func media(localizationID: String, client: ASCClient) async throws -> [Media] {
    async let screenshots = client.appEventLocalizationsAppEventScreenshotsGetToManyRelated(
      path: .init(id: localizationID), query: .init(limit: 50)
    ).ok.body.json.data
    async let clips = client.appEventLocalizationsAppEventVideoClipsGetToManyRelated(
      path: .init(id: localizationID), query: .init(limit: 50)
    ).ok.body.json.data
    let images = try await screenshots.map { shot in
      let a = shot.attributes
      return Media(
        id: shot.id, isVideo: false, assetType: a?.appEventAssetType, state: a?.assetDeliveryState?.state, videoState: nil,
        fileName: a?.fileName, imageTemplate: a?.imageAsset?.templateUrl, width: a?.imageAsset?.width,
        height: a?.imageAsset?.height, videoURL: nil, errors: messages(a?.assetDeliveryState?.errors))
    }
    let videos = try await clips.map { clip in
      let a = clip.attributes
      return Media(
        id: clip.id, isVideo: true, assetType: a?.appEventAssetType,
        state: a?.assetDeliveryState?.state, videoState: a?.videoDeliveryState?.state, fileName: a?.fileName,
        // Empty (0×0) while the video is processing.
        imageTemplate: a?.previewImage?.templateUrl.flatMap { $0.isEmpty ? nil : $0 },
        width: a?.previewImage?.width, height: a?.previewImage?.height,
        videoURL: a?.videoUrl.flatMap { $0.isEmpty ? nil : $0 },
        errors: messages(a?.videoDeliveryState?.errors) + messages(a?.assetDeliveryState?.errors))
    }
    return images + videos
  }

  /// Uploads an image as a localization's event card or details page image; returns its ID.
  public static func uploadImage(
    _ file: MediaFile, localizationID: String, assetType: AssetType, client: ASCClient
  ) async throws -> String {
    try await uploadAsset(
      filePath: file.path,
      reserve: {
        let r = try await client.appEventScreenshotsCreateInstance(body: .json(.init(data: .init(
          attributes: .init(appEventAssetType: assetType.rawValue, fileName: file.fileName, fileSize: file.fileSize),
          relationships: .init(appEventLocalization: .init(data: .init(id: localizationID, _type: "appEventLocalizations"))),
          _type: "appEventScreenshots"
        )))).created.body.json
        return (r.data.id, r.data.attributes?.uploadOperations ?? [])
      },
      commit: { id, _ in
        _ = try await client.appEventScreenshotsUpdateInstance(
          path: .init(id: id),
          body: .json(.init(data: .init(attributes: .init(uploaded: true), id: id, _type: "appEventScreenshots")))
        ).ok
      })
  }

  /// Uploads a video as a localization's event card or details page video; returns its ID.
  /// `previewFrame` is the poster frame's timecode, hh:mm:ss:frame (00:00:03:00; Apple refuses 00:00:03).
  public static func uploadVideo(
    _ file: MediaFile, localizationID: String, assetType: AssetType, previewFrame: String? = nil, client: ASCClient
  ) async throws -> String {
    try await uploadAsset(
      filePath: file.path,
      reserve: {
        let r = try await client.appEventVideoClipsCreateInstance(body: .json(.init(data: .init(
          attributes: .init(
            appEventAssetType: assetType.rawValue, fileName: file.fileName, fileSize: file.fileSize,
            previewFrameTimeCode: previewFrame),
          relationships: .init(appEventLocalization: .init(data: .init(id: localizationID, _type: "appEventLocalizations"))),
          _type: "appEventVideoClips"
        )))).created.body.json
        return (r.data.id, r.data.attributes?.uploadOperations ?? [])
      },
      commit: { id, _ in
        _ = try await client.appEventVideoClipsUpdateInstance(
          path: .init(id: id),
          body: .json(.init(data: .init(
            attributes: .init(previewFrameTimeCode: previewFrame, uploaded: true), id: id, _type: "appEventVideoClips")))
        ).ok
      })
  }

  /// Removes an image or video from its localization; the library keeps the file, for reuse.
  /// Deleted as the placement it is: `DELETE appEventScreenshots/{id}` answers HTTP 500 for media
  /// placed from the library, although it deletes them (seen live 2026-10-21).
  public static func deleteMedia(_ media: Media, client: ASCClient) async throws {
    try await AssetLibrary.deletePlacement(id: media.id, client: client)
  }

  // MARK: Decoding

  private static func event(_ event: Components.Schemas.AppEvent) -> Event {
    let a = event.attributes
    return Event(
      id: event.id, referenceName: a?.referenceName ?? "", state: a?.eventState, badge: a?.badge,
      deepLink: a?.deepLink.map { "\($0)" }, purchaseRequirement: a?.purchaseRequirement, primaryLocale: a?.primaryLocale,
      priority: a?.priority, purpose: a?.purpose,
      schedules: (a?.territorySchedules ?? []).map {
        Schedule(territories: $0.territories, publishStart: $0.publishStart, eventStart: $0.eventStart, eventEnd: $0.eventEnd)
      },
      archivedSchedules: (a?.archivedTerritorySchedules ?? []).map {
        Schedule(territories: $0.territories, publishStart: $0.publishStart, eventStart: $0.eventStart, eventEnd: $0.eventEnd)
      })
  }

  private static func localization(_ localization: Components.Schemas.AppEventLocalization) -> Localization? {
    guard let a = localization.attributes, let locale = a.locale else { return nil }
    return Localization(
      id: localization.id, locale: locale, name: a.name, shortDescription: a.shortDescription,
      longDescription: a.longDescription)
  }

  private static func messages(_ errors: [Components.Schemas.AppMediaStateError]?) -> [String] {
    (errors ?? []).compactMap { $0.description ?? $0.code }
  }
}
