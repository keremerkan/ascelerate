import ASCKit
import Foundation

/// The screenshot and preview sets of a localization: an App Store version's, a custom product
/// page's, or a product page optimization treatment's.
public enum LocalizationMedia {
  public typealias Owner = AssetLibrary.Owner

  public static func screenshotSets(on owner: Owner, client: ASCClient) async throws -> [Components.Schemas.AppScreenshotSet] {
    switch owner {
    case .versionLocalization(let id):
      try await client.appStoreVersionLocalizationsAppScreenshotSetsGetToManyRelated(path: .init(id: id), query: .init(limit: 50)).ok.body.json.data
    case .productPageLocalization(let id):
      try await client.appCustomProductPageLocalizationsAppScreenshotSetsGetToManyRelated(path: .init(id: id), query: .init(limit: 50)).ok.body.json.data
    case .treatmentLocalization(let id):
      try await client.appStoreVersionExperimentTreatmentLocalizationsAppScreenshotSetsGetToManyRelated(path: .init(id: id), query: .init(limit: 50)).ok.body.json.data
    case .eventLocalization, .retentionMessageVersion:
      // An event's media are library placements only.
      []
    }
  }

  public static func previewSets(on owner: Owner, client: ASCClient) async throws -> [Components.Schemas.AppPreviewSet] {
    switch owner {
    case .versionLocalization(let id):
      try await client.appStoreVersionLocalizationsAppPreviewSetsGetToManyRelated(path: .init(id: id), query: .init(limit: 50)).ok.body.json.data
    case .productPageLocalization(let id):
      try await client.appCustomProductPageLocalizationsAppPreviewSetsGetToManyRelated(path: .init(id: id), query: .init(limit: 50)).ok.body.json.data
    case .treatmentLocalization(let id):
      try await client.appStoreVersionExperimentTreatmentLocalizationsAppPreviewSetsGetToManyRelated(path: .init(id: id), query: .init(limit: 50)).ok.body.json.data
    case .eventLocalization, .retentionMessageVersion:
      []
    }
  }

  /// A screenshot set's screenshots, in their order (a set holds ten at most).
  public static func screenshots(setID: String, client: ASCClient) async throws -> [Components.Schemas.AppScreenshot] {
    try await client.appScreenshotSetsAppScreenshotsGetToManyRelated(path: .init(id: setID), query: .init(limit: 50)).ok.body.json.data
  }

  /// An owner's screenshot sets with their screenshots in order, in one request (the screenshots
  /// included). A set whose screenshots didn't all come (the included resources stop at 50) is
  /// read on its own.
  public static func screenshotSetsWithScreenshots(
    on owner: Owner, client: ASCClient
  ) async throws -> [(set: Components.Schemas.AppScreenshotSet, screenshots: [Components.Schemas.AppScreenshot])] {
    let response: Components.Schemas.AppScreenshotSetsResponse
    switch owner {
      case .versionLocalization(let id):
        response = try await client.appStoreVersionLocalizationsAppScreenshotSetsGetToManyRelated(
          path: .init(id: id), query: .init(limit: 50, include: [.appScreenshots], limitAppScreenshots: 10)).ok.body.json
      case .productPageLocalization(let id):
        response = try await client.appCustomProductPageLocalizationsAppScreenshotSetsGetToManyRelated(
          path: .init(id: id), query: .init(limit: 50, include: [.appScreenshots], limitAppScreenshots: 10)).ok.body.json
      case .treatmentLocalization(let id):
        response = try await client.appStoreVersionExperimentTreatmentLocalizationsAppScreenshotSetsGetToManyRelated(
          path: .init(id: id), query: .init(limit: 50, include: [.appScreenshots], limitAppScreenshots: 10)).ok.body.json
      case .eventLocalization, .retentionMessageVersion:
        return []
    }
    var byID: [String: Components.Schemas.AppScreenshot] = [:]
    for case .appScreenshots(let screenshot) in response.included ?? [] { byID[screenshot.id] = screenshot }
    var result: [(set: Components.Schemas.AppScreenshotSet, screenshots: [Components.Schemas.AppScreenshot])] = []
    for set in response.data {
      let ids = set.relationships?.appScreenshots?.data?.map(\.id)
      if let ids, ids.allSatisfy({ byID[$0] != nil }) {
        result.append((set, ids.compactMap { byID[$0] }))
      } else {
        result.append((set, try await screenshots(setID: set.id, client: client)))
      }
    }
    return result
  }

  public static func screenshotSetsWithScreenshots(localizationID: String, client: ASCClient) async throws
    -> [(set: Components.Schemas.AppScreenshotSet, screenshots: [Components.Schemas.AppScreenshot])] {
    try await screenshotSetsWithScreenshots(on: .versionLocalization(localizationID), client: client)
  }

  /// The same for preview sets.
  public static func previewSetsWithPreviews(
    on owner: Owner, client: ASCClient
  ) async throws -> [(set: Components.Schemas.AppPreviewSet, previews: [Components.Schemas.AppPreview])] {
    let response: Components.Schemas.AppPreviewSetsResponse
    switch owner {
      case .versionLocalization(let id):
        response = try await client.appStoreVersionLocalizationsAppPreviewSetsGetToManyRelated(
          path: .init(id: id), query: .init(limit: 50, include: [.appPreviews], limitAppPreviews: 3)).ok.body.json
      case .productPageLocalization(let id):
        response = try await client.appCustomProductPageLocalizationsAppPreviewSetsGetToManyRelated(
          path: .init(id: id), query: .init(limit: 50, include: [.appPreviews], limitAppPreviews: 3)).ok.body.json
      case .treatmentLocalization(let id):
        response = try await client.appStoreVersionExperimentTreatmentLocalizationsAppPreviewSetsGetToManyRelated(
          path: .init(id: id), query: .init(limit: 50, include: [.appPreviews], limitAppPreviews: 3)).ok.body.json
      case .eventLocalization, .retentionMessageVersion:
        return []
    }
    var byID: [String: Components.Schemas.AppPreview] = [:]
    for case .appPreviews(let preview) in response.included ?? [] { byID[preview.id] = preview }
    var result: [(set: Components.Schemas.AppPreviewSet, previews: [Components.Schemas.AppPreview])] = []
    for set in response.data {
      let ids = set.relationships?.appPreviews?.data?.map(\.id)
      if let ids, ids.allSatisfy({ byID[$0] != nil }) {
        result.append((set, ids.compactMap { byID[$0] }))
      } else {
        result.append((set, try await previews(setID: set.id, client: client)))
      }
    }
    return result
  }

  public static func previewSetsWithPreviews(localizationID: String, client: ASCClient) async throws
    -> [(set: Components.Schemas.AppPreviewSet, previews: [Components.Schemas.AppPreview])] {
    try await previewSetsWithPreviews(on: .versionLocalization(localizationID), client: client)
  }

  /// A preview set's previews, in their order.
  public static func previews(setID: String, client: ASCClient) async throws -> [Components.Schemas.AppPreview] {
    try await client.appPreviewSetsAppPreviewsGetToManyRelated(path: .init(id: setID), query: .init(limit: 50)).ok.body.json.data
  }

  /// The classic sets apart from the API's mirrors of library slots (iPhone Duo), which list the
  /// same media as the slot's placements.
  public static func classicScreenshotSets(on owner: Owner, client: ASCClient) async throws -> [Components.Schemas.AppScreenshotSet] {
    try await screenshotSets(on: owner, client: client).filter { AssetLibrary.slots[$0.attributes?.screenshotDisplayType ?? ""] == nil }
  }

  public static func classicPreviewSets(on owner: Owner, client: ASCClient) async throws -> [Components.Schemas.AppPreviewSet] {
    try await previewSets(on: owner, client: client).filter { AssetLibrary.slots["APP_\($0.attributes?.previewType ?? "")"] == nil }
  }
}
