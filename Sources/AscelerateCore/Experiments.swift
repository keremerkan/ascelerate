import ASCKit
import Foundation

/// Product page optimization (v2 experiments): A/B tests of an app's product page against the live
/// version's, with up to three treatments. A treatment has a name, optionally an alternate app
/// icon, and a localization per language whose screenshots and previews are media like a
/// version's (`AssetLibrary.Owner.treatmentLocalization`).
public enum Experiments {
  /// How many treatments a test takes.
  public static let treatmentLimit = 3

  public struct Experiment: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// Raw platform (`IOS`, `MAC_OS`…).
    public let platform: String?
    /// `PREPARE_FOR_SUBMISSION`, `READY_FOR_REVIEW`, `WAITING_FOR_REVIEW`, `IN_REVIEW`, `ACCEPTED`,
    /// `APPROVED`, `REJECTED`, `COMPLETED`, `STOPPED`…
    public let state: String?
    /// The share of visitors who see a treatment, in percent.
    public let trafficProportion: Int?
    /// Whether App Review has to approve it before it can start.
    public let reviewRequired: Bool?
    public let startDate: Date?
    public let endDate: Date?
  }

  public struct Treatment: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// An alternate app icon to test, by its name in the build's asset catalog.
    public let appIconName: String?
    /// That icon as an image URL template (`{w}x{h}bb.{f}`).
    public let appIconTemplate: String?
    /// When the treatment was applied to the original product page.
    public let promotedDate: Date?
  }

  public struct Localization: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let locale: String
  }

  /// An app icon of a build: the primary one or an alternate a treatment can test.
  public struct Icon: Codable, Hashable, Sendable {
    public let name: String
    /// `APP_STORE`, `MESSAGES_APP_STORE`, `ALTERNATE_EXPERIMENTAL`…
    public let type: String?
    public let imageTemplate: String?
  }

  public enum LookupError: LocalizedError {
    case notFound(String, names: [String])
    case treatmentNotFound(String, names: [String])

    public var errorDescription: String? {
      switch self {
        case .notFound(let ref, let names):
          "No experiment '\(ref)' found." + (names.isEmpty ? "" : " Experiments: \(names.joined(separator: ", ")).")
        case .treatmentNotFound(let ref, let names):
          "No treatment '\(ref)' found." + (names.isEmpty ? "" : " Treatments: \(names.joined(separator: ", ")).")
      }
    }
  }

  // MARK: Tests

  public static func list(appID: String, client: ASCClient) async throws -> [Experiment] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.appsAppStoreVersionExperimentsV2GetToManyRelated(path: .init(id: appID), query: .init(limit: 200)).ok.body.json
    }.flatMap(\.data).map(experiment)
  }

  /// An app's test by name (any case) or ID.
  public static func find(_ ref: String, appID: String, client: ASCClient) async throws -> Experiment {
    let all = try await list(appID: appID, client: client)
    guard let match = all.first(where: { $0.id == ref || $0.name.lowercased() == ref.lowercased() }) else {
      throw LookupError.notFound(ref, names: all.map(\.name))
    }
    return match
  }

  public static func get(id: String, client: ASCClient) async throws -> Experiment {
    experiment(try await client.appStoreVersionExperimentsV2GetInstance(path: .init(id: id)).ok.body.json.data)
  }

  /// A new test of the live version's product page on `platform` (raw), shown to `traffic`
  /// percent of visitors.
  @discardableResult
  public static func create(
    appID: String, name: String, platform: String, trafficProportion: Int, client: ASCClient
  ) async throws -> Experiment {
    experiment(try await client.appStoreVersionExperimentsV2CreateInstance(body: .json(.init(data: .init(
      attributes: .init(name: name, platform: platform, trafficProportion: trafficProportion),
      relationships: .init(app: .init(data: .init(id: appID, _type: "apps"))),
      _type: "appStoreVersionExperiments"
    )))).created.body.json.data)
  }

  /// Renames a test or changes its traffic share; nil values are left as they are.
  public static func update(id: String, name: String? = nil, trafficProportion: Int? = nil, client: ASCClient) async throws {
    try await patch(id: id, .init(name: name, trafficProportion: trafficProportion), client: client)
  }

  /// Starts a test (one that needed App Review once it's approved).
  public static func start(id: String, client: ASCClient) async throws {
    try await patch(id: id, .init(started: true), client: client)
  }

  /// Stops a running test; it can't be started again.
  public static func stop(id: String, client: ASCClient) async throws {
    try await patch(id: id, .init(started: false), client: client)
  }

  /// Deletes a test, after its treatments' placements while it's editable
  /// (`AssetLibrary.clearPlacements`; one that went through review holds only reviewed images).
  public static func delete(id: String, state: String? = nil, client: ASCClient) async throws {
    var state = state
    if state == nil { state = try await get(id: id, client: client).state }
    if ["PREPARE_FOR_SUBMISSION", "REJECTED"].contains(state) {
      for treatment in try await treatments(experimentID: id, client: client) {
        try await clearPlacements(treatmentID: treatment.id, client: client)
      }
    }
    _ = try await client.appStoreVersionExperimentsV2DeleteInstance(path: .init(id: id)).noContent
  }

  private static func patch(
    id: String, _ attributes: Components.Schemas.AppStoreVersionExperimentV2UpdateRequest.DataPayload.AttributesPayload,
    client: ASCClient
  ) async throws {
    _ = try await client.appStoreVersionExperimentsV2UpdateInstance(
      path: .init(id: id), body: .json(.init(data: .init(attributes: attributes, id: id, _type: "appStoreVersionExperiments")))
    ).ok
  }

  // MARK: Treatments

  public static func treatments(experimentID: String, client: ASCClient) async throws -> [Treatment] {
    try await client.appStoreVersionExperimentsV2AppStoreVersionExperimentTreatmentsGetToManyRelated(
      path: .init(id: experimentID), query: .init(limit: 50)
    ).ok.body.json.data.map(treatment)
  }

  /// A test's treatment by name (any case) or ID.
  public static func treatment(_ ref: String, experimentID: String, client: ASCClient) async throws -> Treatment {
    let all = try await treatments(experimentID: experimentID, client: client)
    guard let match = all.first(where: { $0.id == ref || $0.name.lowercased() == ref.lowercased() }) else {
      throw LookupError.treatmentNotFound(ref, names: all.map(\.name))
    }
    return match
  }

  @discardableResult
  public static func createTreatment(
    experimentID: String, name: String, appIconName: String? = nil, client: ASCClient
  ) async throws -> Treatment {
    treatment(try await client.appStoreVersionExperimentTreatmentsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(appIconName: appIconName, name: name),
      relationships: .init(
        appStoreVersionExperimentV2: .init(data: .init(id: experimentID, _type: "appStoreVersionExperiments"))),
      _type: "appStoreVersionExperimentTreatments"
    )))).created.body.json.data)
  }

  /// Renames a treatment or changes its app icon; nil values are left as they are, and
  /// `appIconName` given as `.some(nil)` goes back to the app's own icon (sent as null).
  public static func updateTreatment(
    id: String, name: String? = nil, appIconName: String?? = nil, client: ASCClient
  ) async throws {
    let nulls = appIconName.map { $0 == nil } == true ? [["data", "attributes", "appIconName"]] : []
    try await ASCNulls.sending(nulls) {
      _ = try await client.appStoreVersionExperimentTreatmentsUpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
        attributes: .init(appIconName: appIconName ?? nil, name: name), id: id, _type: "appStoreVersionExperimentTreatments"
      )))).ok
    }
  }

  /// Deletes a treatment, after its placements (`AssetLibrary.clearPlacements`).
  public static func deleteTreatment(id: String, client: ASCClient) async throws {
    try await clearPlacements(treatmentID: id, client: client)
    _ = try await client.appStoreVersionExperimentTreatmentsDeleteInstance(path: .init(id: id)).noContent
  }

  private static func clearPlacements(treatmentID: String, client: ASCClient) async throws {
    for localization in try await localizations(treatmentID: treatmentID, client: client) {
      try await AssetLibrary.clearPlacements(on: .treatmentLocalization(localization.id), client: client)
    }
  }

  // MARK: Localizations

  /// A treatment's languages, by locale code.
  public static func localizations(treatmentID: String, client: ASCClient) async throws -> [Localization] {
    try await client.appStoreVersionExperimentTreatmentsAppStoreVersionExperimentTreatmentLocalizationsGetToManyRelated(
      path: .init(id: treatmentID), query: .init(limit: 50)
    ).ok.body.json.data.map { Localization(id: $0.id, locale: $0.attributes?.locale ?? "") }.sorted { $0.locale < $1.locale }
  }

  /// A new language for a treatment. Apple seeds it with the live version's media in that
  /// language (seen live 2026-10-13: its screenshots, previews and iPhone Duo placements).
  @discardableResult
  public static func createLocalization(treatmentID: String, locale: String, client: ASCClient) async throws -> Localization {
    let created = try await client.appStoreVersionExperimentTreatmentLocalizationsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(locale: locale),
      relationships: .init(
        appStoreVersionExperimentTreatment: .init(data: .init(id: treatmentID, _type: "appStoreVersionExperimentTreatments"))),
      _type: "appStoreVersionExperimentTreatmentLocalizations"
    )))).created.body.json.data
    return Localization(id: created.id, locale: created.attributes?.locale ?? locale)
  }

  /// Removes a language from a treatment, after its placements (`AssetLibrary.clearPlacements`);
  /// that language then shows the original page.
  public static func deleteLocalization(id: String, client: ASCClient) async throws {
    try await AssetLibrary.clearPlacements(on: .treatmentLocalization(id), client: client)
    _ = try await client.appStoreVersionExperimentTreatmentLocalizationsDeleteInstance(path: .init(id: id)).noContent
  }

  // MARK: Icons

  /// A build's app icons: its primary icon and the alternates a treatment can test.
  public static func icons(buildID: String, client: ASCClient) async throws -> [Icon] {
    try await client.buildsIconsGetToManyRelated(path: .init(id: buildID), query: .init(limit: 50)).ok.body.json.data.map {
      Icon(name: $0.attributes?.name ?? "", type: $0.attributes?.iconType, imageTemplate: $0.attributes?.iconAsset?.templateUrl)
    }
  }

  // MARK: Mapping

  private static func experiment(_ e: Components.Schemas.AppStoreVersionExperimentV2) -> Experiment {
    let a = e.attributes
    return Experiment(
      id: e.id, name: a?.name ?? e.id, platform: a?.platform, state: a?.state, trafficProportion: a?.trafficProportion,
      reviewRequired: a?.reviewRequired, startDate: a?.startDate, endDate: a?.endDate)
  }

  private static func treatment(_ t: Components.Schemas.AppStoreVersionExperimentTreatment) -> Treatment {
    let a = t.attributes
    return Treatment(
      id: t.id, name: a?.name ?? t.id, appIconName: a?.appIconName, appIconTemplate: a?.appIcon?.templateUrl,
      promotedDate: a?.promotedDate)
  }
}
