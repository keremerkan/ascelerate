import ASCKit
import Foundation

/// An app's App Store information (`appInfos`): its state, categories, age ratings and per-locale
/// name and subtitle. An app holds several: the live one, one being prepared with the next version,
/// and replaced ones. Also the app-level details shown with it (content rights, primary language,
/// App Store Server Notifications endpoints).
public enum AppInfos {
  /// States in which an app info's localizations and categories can change.
  public static let editableStates: Set<String> = ["PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW"]

  public enum AppInfoError: LocalizedError {
    case notFound
    /// The app info's raw state, when known.
    case notEditable(state: String?)

    public var errorDescription: String? {
      switch self {
        case .notFound:
          return "No app info found."
        case .notEditable(let state):
          let stateName = state.map { formatState($0) } ?? "unknown"
          return "App info is in state '\(stateName)' — updates are only allowed in PREPARE_FOR_SUBMISSION or WAITING_FOR_REVIEW."
      }
    }
  }

  /// An app info relationship to a category.
  public enum CategorySlot: String, CaseIterable, Sendable {
    case primaryCategory, primarySubcategoryOne, primarySubcategoryTwo
    case secondaryCategory, secondarySubcategoryOne, secondarySubcategoryTwo
  }

  /// A category and its subcategories (Games has them), by ID: the ID is the name
  /// (`DEVELOPER_TOOLS`, `GAMES_PUZZLE`).
  public struct Category: Sendable, Hashable {
    public let id: String
    public let subcategories: [String]
  }

  /// The most relevant app info: an editable one over the live one, never a replaced one.
  public static func pickActive(from appInfos: [Components.Schemas.AppInfo]) throws -> Components.Schemas.AppInfo {
    let candidates = appInfos.filter { $0.attributes?.state != "REPLACED_WITH_NEW_INFO" }
    guard let appInfo = candidates.first(where: { editableStates.contains($0.attributes?.state ?? "") })
      ?? candidates.first
      ?? appInfos.first
    else {
      throw AppInfoError.notFound
    }
    return appInfo
  }

  public static func findActive(appID: String, client: ASCClient) async throws -> Components.Schemas.AppInfo {
    try pickActive(from: await client.appsAppInfosGetToManyRelated(path: .init(id: appID)).ok.body.json.data)
  }

  /// Throws `AppInfoError.notEditable` unless the app info's localizations and categories can change.
  public static func checkEditable(_ appInfo: Components.Schemas.AppInfo) throws {
    guard let state = appInfo.attributes?.state, editableStates.contains(state) else {
      throw AppInfoError.notEditable(state: appInfo.attributes?.state)
    }
  }

  /// The fields of an app info localization that can be cleared (sent as null: an empty URL is
  /// refused).
  public enum LocalizationField: String, Sendable {
    case subtitle, privacyPolicyUrl, privacyChoicesUrl, privacyPolicyText
  }

  /// Changes an app info localization's fields; a nil one is left as it is, and the ones in
  /// `clearing` are removed. `privacyPolicyText` is the policy Apple TV shows instead of a URL.
  @discardableResult
  public static func updateLocalization(
    id: String, name: String? = nil, subtitle: String? = nil, privacyPolicyURL: String? = nil,
    privacyChoicesURL: String? = nil, privacyPolicyText: String? = nil, clearing: [LocalizationField] = [],
    client: ASCClient
  ) async throws -> Components.Schemas.AppInfoLocalization {
    try await ASCNulls.sending(clearing.map { ["data", "attributes", $0.rawValue] }) {
      try await client.appInfoLocalizationsUpdateInstance(
        path: .init(id: id),
        body: .json(.init(data: .init(
          attributes: .init(
            name: name, privacyChoicesUrl: privacyChoicesURL, privacyPolicyText: privacyPolicyText,
            privacyPolicyUrl: privacyPolicyURL, subtitle: subtitle),
          id: id,
          _type: "appInfoLocalizations"
        )))
      ).ok.body.json.data
    }
  }

  /// The App Store's 50 languages, as app info and version localizations name them (`tr`,
  /// `de-DE`, `zh-Hans`; seen live 2026-10-22).
  public static let locales = [
    "ar-SA", "bn-BD", "ca", "cs", "da", "de-DE", "el", "en-AU", "en-CA", "en-GB", "en-US", "es-ES", "es-MX", "fi",
    "fr-CA", "fr-FR", "gu-IN", "he", "hi", "hr", "hu", "id", "it", "ja", "kn-IN", "ko", "ml-IN", "mr-IN", "ms", "nl-NL",
    "no", "or-IN", "pa-IN", "pl", "pt-BR", "pt-PT", "ro", "ru", "sk", "sl-SI", "sv", "ta-IN", "te-IN", "th", "tr", "uk",
    "ur-PK", "vi", "zh-Hans", "zh-Hant",
  ]

  /// Adds a language to an app info, with its app name (App Store Connect fills in the primary
  /// language's).
  @discardableResult
  public static func createLocalization(
    appInfoID: String, locale: String, name: String, client: ASCClient
  ) async throws -> Components.Schemas.AppInfoLocalization {
    try await client.appInfoLocalizationsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(locale: locale, name: name),
      relationships: .init(appInfo: .init(data: .init(id: appInfoID, _type: "appInfos"))),
      _type: "appInfoLocalizations"
    )))).created.body.json.data
  }

  public static func deleteLocalization(id: String, client: ASCClient) async throws {
    _ = try await client.appInfoLocalizationsDeleteInstance(path: .init(id: id)).noContent
  }

  /// Sets an app info's categories: each slot in `changes` to its category ID, or none for nil
  /// (sent as `{"data": null}`). Slots not in `changes` are left as they are.
  public static func updateCategories(
    appInfoID: String, _ changes: [CategorySlot: String?], client: ASCClient
  ) async throws {
    // A set slot's category ID; nil for a slot left alone or cleared.
    func id(_ slot: CategorySlot) -> String? { changes[slot] ?? nil }
    let cleared = changes.filter { $0.value == nil }.keys.map { ["data", "relationships", $0.rawValue, "data"] }
    _ = try await ASCNulls.sending(cleared) {
      try await client.appInfosUpdateInstance(
        path: .init(id: appInfoID),
        body: .json(.init(data: .init(
          id: appInfoID,
          relationships: .init(
            primaryCategory: id(.primaryCategory).map { .init(data: .init(id: $0, _type: "appCategories")) },
            primarySubcategoryOne: id(.primarySubcategoryOne).map { .init(data: .init(id: $0, _type: "appCategories")) },
            primarySubcategoryTwo: id(.primarySubcategoryTwo).map { .init(data: .init(id: $0, _type: "appCategories")) },
            secondaryCategory: id(.secondaryCategory).map { .init(data: .init(id: $0, _type: "appCategories")) },
            secondarySubcategoryOne: id(.secondarySubcategoryOne).map { .init(data: .init(id: $0, _type: "appCategories")) },
            secondarySubcategoryTwo: id(.secondarySubcategoryTwo).map { .init(data: .init(id: $0, _type: "appCategories")) }),
          _type: "appInfos"
        )))
      ).ok
    }
  }

  /// The top-level App Store categories of any of the platforms, with their subcategories, sorted
  /// by ID.
  public static func categories(platforms: [ASCEnum.Platform], client: ASCClient) async throws -> [Category] {
    let filter = platforms.compactMap {
      Operations.AppCategoriesGetCollection.Input.Query.FilterPlatformsPayloadPayload(rawValue: $0.rawValue)
    }
    let response = try await client.appCategoriesGetCollection(query: .init(
      filterPlatforms: filter, existsParent: false, limit: 200, include: [.subcategories], limitSubcategories: 50
    )).ok.body.json
    return response.data.map { category in
      Category(id: category.id, subcategories: (category.relationships?.subcategories?.data ?? []).map(\.id).sorted())
    }.sorted { $0.id < $1.id }
  }

  /// The age rating App Store Connect gives an app info in each territory (raw values such as
  /// `FOUR_PLUS`, with local systems' own: Korea `ALL`, Vietnam `ZERO_ZERO`), by territory code.
  /// Replaces the deprecated single `appStoreAgeRating`. Empty until the age rating questionnaire
  /// is answered.
  public static func territoryAgeRatings(appInfoID: String, client: ASCClient) async throws -> [String: String] {
    let ratings = try await client.appInfosTerritoryAgeRatingsGetToManyRelated(
      path: .init(id: appInfoID), query: .init(limit: 200, include: [.territory])
    ).ok.body.json.data
    return Dictionary(
      ratings.compactMap { rating in
        rating.relationships?.territory?.data.flatMap { territory in
          rating.attributes?.appStoreAgeRating.map { (territory.id, $0) }
        }
      },
      uniquingKeysWith: { first, _ in first })
  }

  /// An app info's age rating questionnaire (`ageRatingDeclarations`); its answers are nil until
  /// it's first answered.
  public static func ageRatingDeclaration(
    appInfoID: String, client: ASCClient
  ) async throws -> Components.Schemas.AgeRatingDeclaration {
    try await client.appInfosAgeRatingDeclarationGetToOneRelated(path: .init(id: appInfoID)).ok.body.json.data
  }

  /// Changes age rating questionnaire answers: a nil attribute is left as it is, and the ones
  /// named in `clearing` (`kidsAgeBand`, `developerAgeRatingInfoUrl`) are sent as null, which
  /// removes them (an empty URL is refused). The territory ratings follow at once.
  @discardableResult
  public static func updateAgeRatingDeclaration(
    id: String, _ attributes: Components.Schemas.AgeRatingDeclarationUpdateRequest.DataPayload.AttributesPayload,
    clearing: [String] = [], client: ASCClient
  ) async throws -> Components.Schemas.AgeRatingDeclaration {
    try await ASCNulls.sending(clearing.map { ["data", "attributes", $0] }) {
      try await client.ageRatingDeclarationsUpdateInstance(
        path: .init(id: id),
        body: .json(.init(data: .init(attributes: attributes, id: id, _type: "ageRatingDeclarations")))
      ).ok.body.json.data
    }
  }

  /// An App Store Server Notifications environment of an app.
  public enum NotificationEnvironment: String, CaseIterable, Sendable {
    case production, sandbox
  }

  /// Where an app's App Store Server Notifications go in one environment: the server's URL and the
  /// notification version (`V1`, `V2`).
  public struct NotificationEndpoint: Codable, Hashable, Sendable {
    public var url: String
    public var version: String

    public init(url: String, version: String = "V2") {
      self.url = url
      self.version = version
    }
  }

  /// The app's App Store Server Notifications endpoint in the environment; nil when it has none.
  public static func notificationEndpoint(
    of app: Components.Schemas.App, _ environment: NotificationEnvironment
  ) -> NotificationEndpoint? {
    let attributes = app.attributes
    let (url, version) =
      switch environment {
        case .production: (attributes?.subscriptionStatusUrl, attributes?.subscriptionStatusUrlVersion)
        case .sandbox: (attributes?.subscriptionStatusUrlForSandbox, attributes?.subscriptionStatusUrlVersionForSandbox)
      }
    return url.map { NotificationEndpoint(url: $0, version: version ?? "V2") }
  }

  /// Changes an app's own details shown with its app information; a nil one is left as it is.
  /// `contentRights` says whether the app contains, shows or accesses third-party content
  /// (`contentRightsDeclaration`: `USES_THIRD_PARTY_CONTENT` or `DOES_NOT_USE_THIRD_PARTY_CONTENT`);
  /// `primaryLocale` is the language its product page falls back to, one it has a localization in.
  /// `notificationEndpoints` sets each listed environment's App Store Server Notifications endpoint,
  /// or removes it for nil (URL and version sent as null: App Store Connect refuses a URL without
  /// its version, and an empty one). `accessibilityURL` is the page about the app's accessibility
  /// its product page links to; `.some(nil)` removes it. Returns the app as saved: reading the app
  /// right afterwards can still return the old values for about a second.
  @discardableResult
  public static func updateApp(
    appID: String, contentRights: String? = nil, primaryLocale: String? = nil,
    notificationEndpoints: [NotificationEnvironment: NotificationEndpoint?] = [:], accessibilityURL: String?? = nil,
    client: ASCClient
  ) async throws -> Components.Schemas.App {
    // A set environment's endpoint; nil for one left alone or removed.
    func endpoint(_ environment: NotificationEnvironment) -> NotificationEndpoint? {
      notificationEndpoints[environment] ?? nil
    }
    var removed = notificationEndpoints.filter { $0.value == nil }.keys.flatMap { environment in
      environment == .production
        ? ["subscriptionStatusUrl", "subscriptionStatusUrlVersion"]
        : ["subscriptionStatusUrlForSandbox", "subscriptionStatusUrlVersionForSandbox"]
    }
    if case .some(.none) = accessibilityURL {
      removed.append("accessibilityUrl")
    }
    return try await ASCNulls.sending(removed.map { ["data", "attributes", $0] }) {
      try await client.appsUpdateInstance(
        path: .init(id: appID),
        body: .json(.init(data: .init(
          attributes: .init(
            accessibilityUrl: accessibilityURL ?? nil, contentRightsDeclaration: contentRights, primaryLocale: primaryLocale,
            subscriptionStatusUrl: endpoint(.production)?.url,
            subscriptionStatusUrlForSandbox: endpoint(.sandbox)?.url,
            subscriptionStatusUrlVersion: endpoint(.production)?.version,
            subscriptionStatusUrlVersionForSandbox: endpoint(.sandbox)?.version),
          id: appID, _type: "apps")))
      ).ok.body.json.data
    }
  }
}


/// An app's age rating answers, as `apps app-info age-rating export`/`import` write and read them:
/// Apple's raw values, flags named `is…`. A nil field is left as it is.
public struct AgeRatingFields: Codable, Equatable, Sendable {
  // Intensity-based (NONE, INFREQUENT_OR_MILD, FREQUENT_OR_INTENSE)
  public var alcoholTobaccoOrDrugUseOrReferences: String?
  public var contests: String?
  public var gamblingSimulated: String?
  public var gunsOrOtherWeapons: String?
  public var horrorOrFearThemes: String?
  public var matureOrSuggestiveThemes: String?
  public var profanityOrCrudeHumor: String?
  public var sexualContentOrNudity: String?
  public var sexualContentGraphicAndNudity: String?
  public var violenceCartoonOrFantasy: String?
  public var violenceRealistic: String?
  public var violenceRealisticProlongedGraphicOrSadistic: String?
  public var medicalOrTreatmentInformation: String?

  // Boolean
  public var isAdvertising: Bool?
  public var isGambling: Bool?
  public var isUnrestrictedWebAccess: Bool?
  public var isUserGeneratedContent: Bool?
  public var isMessagingAndChat: Bool?
  public var isLootBox: Bool?
  public var isHealthOrWellnessTopics: Bool?
  public var isParentalControls: Bool?
  public var isAgeAssurance: Bool?
  public var isSocialMedia: Bool?
  public var isSocialMediaAgeRestricted: Bool?

  // Other
  public var kidsAgeBand: String?
  /// Apple's `ageRatingOverrideV2` (NINE_PLUS … EIGHTEEN_PLUS); the v1 field is deprecated.
  public var ageRatingOverride: String?

  public init(
    alcoholTobaccoOrDrugUseOrReferences: String? = nil,
    contests: String? = nil,
    gamblingSimulated: String? = nil,
    gunsOrOtherWeapons: String? = nil,
    horrorOrFearThemes: String? = nil,
    matureOrSuggestiveThemes: String? = nil,
    profanityOrCrudeHumor: String? = nil,
    sexualContentOrNudity: String? = nil,
    sexualContentGraphicAndNudity: String? = nil,
    violenceCartoonOrFantasy: String? = nil,
    violenceRealistic: String? = nil,
    violenceRealisticProlongedGraphicOrSadistic: String? = nil,
    medicalOrTreatmentInformation: String? = nil,
    isAdvertising: Bool? = nil,
    isGambling: Bool? = nil,
    isUnrestrictedWebAccess: Bool? = nil,
    isUserGeneratedContent: Bool? = nil,
    isMessagingAndChat: Bool? = nil,
    isLootBox: Bool? = nil,
    isHealthOrWellnessTopics: Bool? = nil,
    isParentalControls: Bool? = nil,
    isAgeAssurance: Bool? = nil,
    isSocialMedia: Bool? = nil,
    isSocialMediaAgeRestricted: Bool? = nil,
    kidsAgeBand: String? = nil,
    ageRatingOverride: String? = nil
  ) {
    self.alcoholTobaccoOrDrugUseOrReferences = alcoholTobaccoOrDrugUseOrReferences
    self.contests = contests
    self.gamblingSimulated = gamblingSimulated
    self.gunsOrOtherWeapons = gunsOrOtherWeapons
    self.horrorOrFearThemes = horrorOrFearThemes
    self.matureOrSuggestiveThemes = matureOrSuggestiveThemes
    self.profanityOrCrudeHumor = profanityOrCrudeHumor
    self.sexualContentOrNudity = sexualContentOrNudity
    self.sexualContentGraphicAndNudity = sexualContentGraphicAndNudity
    self.violenceCartoonOrFantasy = violenceCartoonOrFantasy
    self.violenceRealistic = violenceRealistic
    self.violenceRealisticProlongedGraphicOrSadistic = violenceRealisticProlongedGraphicOrSadistic
    self.medicalOrTreatmentInformation = medicalOrTreatmentInformation
    self.isAdvertising = isAdvertising
    self.isGambling = isGambling
    self.isUnrestrictedWebAccess = isUnrestrictedWebAccess
    self.isUserGeneratedContent = isUserGeneratedContent
    self.isMessagingAndChat = isMessagingAndChat
    self.isLootBox = isLootBox
    self.isHealthOrWellnessTopics = isHealthOrWellnessTopics
    self.isParentalControls = isParentalControls
    self.isAgeAssurance = isAgeAssurance
    self.isSocialMedia = isSocialMedia
    self.isSocialMediaAgeRestricted = isSocialMediaAgeRestricted
    self.kidsAgeBand = kidsAgeBand
    self.ageRatingOverride = ageRatingOverride
  }

  /// The answers of a declaration as Apple sends them.
  public init(_ attributes: Components.Schemas.AgeRatingDeclaration.AttributesPayload?) {
    self.init(
      alcoholTobaccoOrDrugUseOrReferences: attributes?.alcoholTobaccoOrDrugUseOrReferences,
      contests: attributes?.contests,
      gamblingSimulated: attributes?.gamblingSimulated,
      gunsOrOtherWeapons: attributes?.gunsOrOtherWeapons,
      horrorOrFearThemes: attributes?.horrorOrFearThemes,
      matureOrSuggestiveThemes: attributes?.matureOrSuggestiveThemes,
      profanityOrCrudeHumor: attributes?.profanityOrCrudeHumor,
      sexualContentOrNudity: attributes?.sexualContentOrNudity,
      sexualContentGraphicAndNudity: attributes?.sexualContentGraphicAndNudity,
      violenceCartoonOrFantasy: attributes?.violenceCartoonOrFantasy,
      violenceRealistic: attributes?.violenceRealistic,
      violenceRealisticProlongedGraphicOrSadistic: attributes?.violenceRealisticProlongedGraphicOrSadistic,
      medicalOrTreatmentInformation: attributes?.medicalOrTreatmentInformation,
      isAdvertising: attributes?.advertising,
      isGambling: attributes?.gambling,
      isUnrestrictedWebAccess: attributes?.unrestrictedWebAccess,
      isUserGeneratedContent: attributes?.userGeneratedContent,
      isMessagingAndChat: attributes?.messagingAndChat,
      isLootBox: attributes?.lootBox,
      isHealthOrWellnessTopics: attributes?.healthOrWellnessTopics,
      isParentalControls: attributes?.parentalControls,
      isAgeAssurance: attributes?.ageAssurance,
      isSocialMedia: attributes?.socialMedia,
      isSocialMediaAgeRestricted: attributes?.socialMediaAgeRestricted,
      kidsAgeBand: attributes?.kidsAgeBand,
      ageRatingOverride: attributes?.ageRatingOverrideV2
    )
  }
}
