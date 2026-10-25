import ASCKit
import Foundation

/// What App Review needs before a version can be submitted, read in one go: the version's build,
/// its text and screenshots in every language, its App Review information, and the app's
/// category, content rights, price and availability. `Report.checks` turns it into checks that
/// pass or name their problems.
///
/// The rules follow App Store Connect: a language without screenshots of its own shows the
/// primary language's, so only the primary language needs them; the description and keywords
/// have no such fallback; What's New exists only once a version of the platform was released.
/// App Store Connect also checks what the API doesn't show (App Privacy, the age rating
/// questionnaire), so a submission can still be refused for its own reasons.
public enum Preflight {
  /// Version states a version can go to App Review from.
  public static let submittableStates: Set<String> = [
    "PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY",
  ]

  /// A text field checked per language, named as the localization files name it.
  public enum Field: String, Sendable, Hashable {
    case name, subtitle, privacyPolicyURL, description, whatsNew, keywords, supportURL

    /// The most characters App Store Connect takes, where it limits the field.
    public var limit: Int? {
      switch self {
        case .description, .whatsNew: 4000
        case .keywords: 100
        case .name, .subtitle: 30
        case .privacyPolicyURL, .supportURL: nil
      }
    }
  }

  /// One language of the version or of App Information.
  public struct Language: Sendable, Hashable {
    public let locale: String
    public let isPrimary: Bool
    /// App Information's text; nil when App Information lacks the language.
    public let appInfo: [Field: String]?
    /// The version's text; nil when the version lacks the language.
    public let version: [Field: String]?
    /// Screenshot sets that hold screenshots, and how many they hold; nil when the version lacks
    /// the language.
    public let screenshotSets: Int?
    public let screenshots: Int?
  }

  public struct Report: Sendable {
    public let versionID: String
    public let versionString: String?
    public let platform: String?
    /// Raw `appVersionState`.
    public let state: String?
    public let copyright: String?
    /// The attached build; nil when there's none.
    public let build: Builds.Build?
    /// Whether What's New is asked for: only once a version of the platform was released.
    public let requiresWhatsNew: Bool
    public let primaryLocale: String
    /// The primary language first, the rest by code.
    public let languages: [Language]
    /// The version's App Review information; nil when it has none yet.
    public let review: ReviewInformation?
    /// The primary category's ID (UTILITIES); nil when none is set.
    public let primaryCategory: String?
    /// Raw `contentRightsDeclaration`; nil when not answered.
    public let contentRights: String?
    public let hasPrice: Bool
    /// The territories it's available in; nil when availability was never set up.
    public let availableTerritories: Int?

    public var checks: [Check] {
      var checks: [Check] = []
      func add(_ item: Item, _ problems: [Problem]) {
        checks.append(Check(item: item, problems: problems))
      }
      func isEmpty(_ text: String?) -> Bool {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }

      add(.versionState, state.map(submittableStates.contains) == true ? [] : [.notSubmittable])

      var buildProblems: [Problem] = []
      if let build {
        if build.processingState != "VALID" { buildProblems.append(.notValid) }
        if build.usesNonExemptEncryption == nil { buildProblems.append(.exportCompliance) }
      } else {
        buildProblems.append(.missing)
      }
      add(.build, buildProblems)

      add(.copyright, isEmpty(copyright) ? [.missing] : [])
      let contact = [review?.contactFirstName, review?.contactLastName, review?.contactPhone, review?.contactEmail]
      add(.reviewContact, contact.contains(where: isEmpty) ? [.missing] : [])
      let needsSignIn = review?.demoAccountRequired ?? true
      add(.signIn, needsSignIn && (isEmpty(review?.demoAccountName) || isEmpty(review?.demoAccountPassword)) ? [.missing] : [])
      add(.category, primaryCategory == nil ? [.missing] : [])
      add(.contentRights, contentRights == nil ? [.missing] : [])
      add(.price, hasPrice ? [] : [.missing])
      add(.availability, availableTerritories == nil ? [.notSetUp] : availableTerritories == 0 ? [.missing] : [])

      for language in languages {
        if let fields = language.appInfo {
          var required: [Field] = [.name]
          if language.isPrimary { required.append(.privacyPolicyURL) }
          add(.appInformation(language.locale), Self.problems(fields, required: required, checked: [.name, .subtitle]))
        }
        if let fields = language.version {
          var required: [Field] = [.description, .keywords]
          if requiresWhatsNew { required.append(.whatsNew) }
          if language.isPrimary { required.append(.supportURL) }
          add(
            .localization(language.locale),
            Self.problems(fields, required: required, checked: [.description, .whatsNew, .keywords]))
        }
        if let screenshots = language.screenshots {
          add(.screenshots(language.locale), screenshots == 0 && language.isPrimary ? [.missing] : [])
        }
      }

      return checks
    }

    /// A language's missing required fields and fields over their limit.
    private static func problems(_ fields: [Field: String], required: [Field], checked: [Field]) -> [Problem] {
      let missing = required.filter { (fields[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      let tooLong = checked.filter { field in field.limit.map { (fields[field] ?? "").count > $0 } ?? false }
      return (missing.isEmpty ? [] : [.missingFields(missing)]) + tooLong.map(Problem.tooLong)
    }
  }

  /// What a check is about.
  public enum Item: Sendable, Hashable {
    case versionState, build, copyright, reviewContact, signIn, category, contentRights, price, availability
    case appInformation(String), localization(String), screenshots(String)

    /// The language of a per-language check.
    public var locale: String? {
      switch self {
        case .appInformation(let locale), .localization(let locale), .screenshots(let locale): locale
        default: nil
      }
    }
  }

  public enum Problem: Sendable, Hashable {
    /// Nothing there (no build, no screenshots, no copyright, an incomplete contact or sign-in...).
    case missing
    case missingFields([Field])
    case tooLong(Field)
    /// The version is in a state it can't be submitted from.
    case notSubmittable
    /// The build hasn't finished processing, or failed it.
    case notValid
    /// Export compliance isn't answered for the build.
    case exportCompliance
    /// Availability was never set up.
    case notSetUp
  }

  public struct Check: Sendable, Hashable {
    public let item: Item
    public let problems: [Problem]

    public var passed: Bool { problems.isEmpty }
  }

  /// Reads everything the checks need about a version of an app.
  public static func report(appID: String, versionID: String, client: ASCClient) async throws -> Report {
    async let app = client.appsGetInstance(
      path: .init(id: appID), query: .init(fieldsApps: [.primaryLocale, .contentRightsDeclaration])
    ).ok.body.json.data
    async let version = client.appStoreVersionsGetInstance(
      path: .init(id: versionID),
      query: .init(fieldsAppStoreVersions: [.versionString, .platform, .appVersionState, .copyright])
    ).ok.body.json.data
    async let build = attachedBuild(versionID: versionID, client: client)
    async let localizations = client.appStoreVersionsAppStoreVersionLocalizationsGetToManyRelated(
      path: .init(id: versionID), query: .init(limit: 50)
    ).ok.body.json.data
    async let appInfo = appInformation(appID: appID, client: client)
    async let review = ReviewInformation.appStore(versionID: versionID, client: client)
    async let schedule = AppPricing.schedule(appID: appID, client: client)
    async let availability = AppAvailability.availability(appID: appID, client: client)

    let versionAttributes = try await version.attributes
    let platform = versionAttributes?.platform
    async let released = hasReleasedVersion(appID: appID, platform: platform, except: versionID, client: client)
    let versionLocalizations = try await localizations
    async let screenshots = screenshotCounts(localizationIDs: versionLocalizations.map(\.id), client: client)

    let primaryLocale = try await app.attributes?.primaryLocale ?? ""
    let (category, infoLocalizations) = try await appInfo
    let versionByLocale = Dictionary(
      versionLocalizations.compactMap { localization in localization.attributes?.locale.map { ($0, localization) } },
      uniquingKeysWith: { first, _ in first })
    let infoByLocale = Dictionary(
      infoLocalizations.compactMap { localization in localization.attributes?.locale.map { ($0, localization) } },
      uniquingKeysWith: { first, _ in first })
    let counts = try await screenshots
    let languages = Set(versionByLocale.keys).union(infoByLocale.keys).sorted { lhs, rhs in
      lhs == primaryLocale || (rhs != primaryLocale && lhs < rhs)
    }.map { locale in
      let info = infoByLocale[locale]?.attributes
      let text = versionByLocale[locale]?.attributes
      let count = versionByLocale[locale].flatMap { counts[$0.id] }
      return Language(
        locale: locale, isPrimary: locale == primaryLocale,
        appInfo: info.map { info in
          [.name: info.name ?? "", .subtitle: info.subtitle ?? "", .privacyPolicyURL: info.privacyPolicyUrl ?? ""]
        },
        version: text.map { text in
          [
            .description: text.description ?? "", .whatsNew: text.whatsNew ?? "", .keywords: text.keywords ?? "",
            .supportURL: text.supportUrl ?? "",
          ]
        },
        screenshotSets: count?.sets, screenshots: count?.screenshots)
    }

    return Report(
      versionID: versionID, versionString: versionAttributes?.versionString, platform: platform,
      state: versionAttributes?.appVersionState, copyright: versionAttributes?.copyright,
      build: try await build.map { Builds.Build($0) }, requiresWhatsNew: try await released, primaryLocale: primaryLocale,
      languages: languages, review: try await review?.information, primaryCategory: category,
      contentRights: try await app.attributes?.contentRightsDeclaration, hasPrice: try await schedule != nil,
      availableTerritories: try await availability.map { $0.territories.count(where: \.available) })
  }

  /// The active app info's primary category and localizations.
  private static func appInformation(
    appID: String, client: ASCClient
  ) async throws -> (category: String?, localizations: [Components.Schemas.AppInfoLocalization]) {
    let response = try await client.appsAppInfosGetToManyRelated(
      path: .init(id: appID),
      query: .init(include: [.appInfoLocalizations, .primaryCategory], limitAppInfoLocalizations: 50)
    ).ok.body.json
    let appInfo = try AppInfos.pickActive(from: response.data)
    // Included localizations carry no back-reference: the app info's own list says which are its.
    let ids = Set(appInfo.relationships?.appInfoLocalizations?.data?.map(\.id) ?? [])
    let localizations = (response.included ?? []).compactMap { item -> Components.Schemas.AppInfoLocalization? in
      if case .appInfoLocalizations(let localization) = item, ids.contains(localization.id) { return localization }
      return nil
    }
    return (appInfo.relationships?.primaryCategory?.data?.id, localizations)
  }

  /// Each version localization's screenshot sets that hold screenshots, and their screenshots.
  private static func screenshotCounts(
    localizationIDs: [String], client: ASCClient
  ) async throws -> [String: (sets: Int, screenshots: Int)] {
    let counts = try await boundedConcurrentMap(localizationIDs) { id in
      // A set holds 10 screenshots at most, so one included page counts them all.
      let sets = try await client.appStoreVersionLocalizationsAppScreenshotSetsGetToManyRelated(
        path: .init(id: id), query: .init(limit: 50, include: [.appScreenshots], limitAppScreenshots: 10)
      ).ok.body.json.data.map { $0.relationships?.appScreenshots?.data?.count ?? 0 }.filter { $0 > 0 }
      return (id, (sets.count, sets.reduce(0, +)))
    }
    return Dictionary(counts, uniquingKeysWith: { first, _ in first })
  }
}
