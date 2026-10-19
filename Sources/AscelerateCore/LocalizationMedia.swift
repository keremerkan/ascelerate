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
    }
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
