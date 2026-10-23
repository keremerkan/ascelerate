import ASCKit
import Foundation

/// An app's builds with their TestFlight states, and what can be done with one: find it, expire
/// it, tell testers about it, attach it to an App Store version.
public enum Builds {
  /// A build with its pre-release train (the version it belongs to) and its TestFlight details.
  public struct Build: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// The build number (`CFBundleVersion`).
    public let number: String?
    /// Its train's version (`CFBundleShortVersionString`), e.g. "5.3".
    public let version: String?
    /// Raw platform of its train (IOS, MAC_OS, TV_OS, VISION_OS).
    public let platform: String?
    public let uploadedDate: Date?
    public let expirationDate: Date?
    public let expired: Bool
    /// PROCESSING, FAILED, INVALID or VALID.
    public let processingState: String?
    /// Nil until export compliance is answered (by the build's Info.plist or afterwards).
    public let usesNonExemptEncryption: Bool?
    public let minOSVersion: String?
    /// The build's icon (`imageAsset.templateUrl`), when Apple has made one.
    public let iconTemplateURL: String?
    /// The `buildBetaDetails` record, when it was read with the build.
    public let betaDetailID: String?
    public let internalState: String?
    public let externalState: String?
    public let autoNotify: Bool?
    /// The beta groups that have it, when they were read with it (`list` and `page` read them).
    public let groupIDs: [String]

    public init(
      _ build: Components.Schemas.Build, train: Components.Schemas.PrereleaseVersion? = nil,
      detail: Components.Schemas.BuildBetaDetail? = nil
    ) {
      let attributes = build.attributes
      id = build.id
      number = attributes?.version
      version = train?.attributes?.version
      platform = train?.attributes?.platform
      uploadedDate = attributes?.uploadedDate
      expirationDate = attributes?.expirationDate
      expired = attributes?.expired ?? false
      processingState = attributes?.processingState
      usesNonExemptEncryption = attributes?.usesNonExemptEncryption
      minOSVersion = attributes?.minOsVersion
      iconTemplateURL = attributes?.iconAssetToken?.templateUrl.flatMap { $0.isEmpty ? nil : $0 }
      betaDetailID = detail?.id
      internalState = detail?.attributes?.internalBuildState
      externalState = detail?.attributes?.externalBuildState
      autoNotify = detail?.attributes?.autoNotifyEnabled
      groupIDs = build.relationships?.betaGroups?.data?.map(\.id) ?? []
    }
  }

  public enum LookupError: LocalizedError {
    case notFound(String)
    case none

    public var errorDescription: String? {
      switch self {
        case .notFound(let number): "No build '\(number)' found for this app."
        case .none: "No builds found for this app. Upload a build first."
      }
    }
  }

  /// The app's builds, newest first, with their trains and TestFlight details, up to `limit` (nil:
  /// all).
  public static func list(
    appID: String, platform: Platform? = nil, version: String? = nil, number: String? = nil, includeExpired: Bool = true,
    groupID: String? = nil, limit: Int? = nil, client: ASCClient
  ) async throws -> [Build] {
    var builds: [Build] = []
    var link: String?
    repeat {
      let page = try await page(
        appID: appID, platform: platform, version: version, number: number, includeExpired: includeExpired,
        groupID: groupID, limit: min(limit ?? 50, 50), after: link, client: client)
      builds += page.builds
      link = page.next
    } while link != nil && builds.count < limit ?? .max
    return limit.map { Array(builds.prefix($0)) } ?? builds
  }

  public struct Page: Sendable {
    public let builds: [Build]
    /// The next page's link, for `page(…, after:)`; nil on the last page.
    public let next: String?
  }

  /// A page of the app's builds, newest first, with their trains and TestFlight details: the first
  /// one, or the one `after` links to. Apple includes at most 50 builds' TestFlight details in a
  /// response however many builds it holds (seen live: a page of 200 builds came with 50), so a
  /// page holds 50 at most. `groupID` narrows them to a beta group's.
  public static func page(
    appID: String, platform: Platform? = nil, version: String? = nil, number: String? = nil, includeExpired: Bool = true,
    groupID: String? = nil, limit: Int = 50, after link: String? = nil, client: ASCClient
  ) async throws -> Page {
    let response = try await ASCPaging.page(link) {
      try await client.buildsGetCollection(query: .init(
        filterVersion: number.map { [$0] },
        filterExpired: includeExpired ? nil : ["false"],
        filterPreReleaseVersionVersion: version.map { [$0] },
        filterPreReleaseVersionPlatform: platformFilter(platform),
        filterApp: [appID],
        filterBetaGroups: groupID.map { [$0] },
        sort: [.minusUploadedDate],
        limit: min(limit, 50),
        include: [.preReleaseVersion, .buildBetaDetail, .betaGroups],
        limitBetaGroups: 50
      )).ok.body.json
    }
    return Page(builds: resolve(response), next: response.links.next)
  }

  /// One build with its train, TestFlight details and groups, as it is now.
  public static func build(id: String, client: ASCClient) async throws -> Build {
    let response = try await client.buildsGetInstance(
      path: .init(id: id),
      query: .init(include: [.preReleaseVersion, .buildBetaDetail, .betaGroups], limitBetaGroups: 50)
    ).ok.body.json
    var train: Components.Schemas.PrereleaseVersion?
    var detail: Components.Schemas.BuildBetaDetail?
    for item in response.included ?? [] {
      switch item {
        case .preReleaseVersions(let included): train = included
        case .buildBetaDetails(let included): detail = included
        default: break
      }
    }
    return Build(response.data, train: train, detail: detail)
  }

  /// A page's builds with their included trains and details.
  static func resolve(_ response: Components.Schemas.BuildsResponse) -> [Build] {
    var trains: [String: Components.Schemas.PrereleaseVersion] = [:]
    var details: [String: Components.Schemas.BuildBetaDetail] = [:]
    for item in response.included ?? [] {
      switch item {
        case .preReleaseVersions(let train): trains[train.id] = train
        case .buildBetaDetails(let detail): details[detail.id] = detail
        default: break
      }
    }
    return response.data.map { build in
      Build(
        build, train: build.relationships?.preReleaseVersion?.data.flatMap { trains[$0.id] },
        detail: build.relationships?.buildBetaDetail?.data.flatMap { details[$0.id] })
    }
  }

  /// A build by number, or the latest one that hasn't expired when `number` is nil (an explicit
  /// number still finds an expired build). A universal-purchase app can share build numbers
  /// across platforms; `choose` then picks.
  public static func find(
    appID: String, number: String?, platform: Platform? = nil, client: ASCClient, choose: Choose<Build>
  ) async throws -> Build {
    let builds = try await list(
      appID: appID, platform: platform, number: number, includeExpired: number != nil, limit: 10, client: client)
    guard let latest = builds.first else {
      throw number.map(LookupError.notFound) ?? LookupError.none
    }
    if number != nil, builds.count > 1 {
      return try await choose("Multiple builds numbered \(number ?? "?") found", builds) { build in
        let uploaded = build.uploadedDate.map { formatDate($0) } ?? "?"
        return "\(build.label) — uploaded \(uploaded)"
      }
    }
    return latest
  }

  /// The app's pre-release versions (trains), newest first.
  public static func preReleaseVersions(
    appID: String, platform: Platform? = nil, limit: Int = 200, client: ASCClient
  ) async throws -> [Components.Schemas.PrereleaseVersion] {
    try await client.preReleaseVersionsGetCollection(query: .init(
      filterPlatform: platformFilter(platform), filterApp: [appID], sort: [.minusVersion], limit: min(limit, 200)
    )).ok.body.json.data
  }

  // MARK: What to Test

  /// A build's What to Test in one language (`betaBuildLocalizations`). TestFlight's languages
  /// differ from the App Store's: `tr`, `ja`, `ko` are bare, `en-US`, `de-DE`, `fr-FR` qualified,
  /// and `tr-TR` is refused.
  public struct TestNotes: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let locale: String
    /// Nil until it's written.
    public let text: String?
  }

  /// A build's What to Test per language, by locale code.
  public static func testNotes(buildID: String, client: ASCClient) async throws -> [TestNotes] {
    try await client.betaBuildLocalizationsGetCollection(query: .init(filterBuild: [buildID], limit: 50)).ok.body.json
      .data.sorted { ($0.attributes?.locale ?? "") < ($1.attributes?.locale ?? "") }
      .map { TestNotes(id: $0.id, locale: $0.attributes?.locale ?? "", text: $0.attributes?.whatsNew) }
  }

  /// Sets What to Test per language: updates the languages the build has, creates the others.
  /// `report` hears of each language as it's saved (true: created), on the caller's actor.
  public static func setTestNotes(
    _ updates: [(locale: String, text: String)], buildID: String, client: ASCClient,
    isolation: isolated (any Actor)? = #isolation, report: (_ locale: String, _ created: Bool) -> Void = { _, _ in }
  ) async throws {
    let existing = try await testNotes(buildID: buildID, client: client)
    let byLocale = Dictionary(existing.map { ($0.locale, $0) }, uniquingKeysWith: { first, _ in first })
    for (locale, text) in updates {
      if let notes = byLocale[locale] {
        _ = try await client.betaBuildLocalizationsUpdateInstance(
          path: .init(id: notes.id),
          body: .json(.init(data: .init(attributes: .init(whatsNew: text), id: notes.id, _type: "betaBuildLocalizations")))
        ).ok
        report(locale, false)
      } else {
        _ = try await client.betaBuildLocalizationsCreateInstance(body: .json(.init(data: .init(
          attributes: .init(locale: locale, whatsNew: text),
          relationships: .init(build: .init(data: .init(id: buildID, _type: "builds"))),
          _type: "betaBuildLocalizations"
        )))).created
        report(locale, true)
      }
    }
  }

  /// Submits the build for beta review, which external testing needs (only the first build of a
  /// version gets a full review; later ones of an approved version pass at once). Returns the
  /// review's state.
  @discardableResult
  public static func submitForBetaReview(buildID: String, client: ASCClient) async throws -> String? {
    try await client.betaAppReviewSubmissionsCreateInstance(body: .json(.init(data: .init(
      relationships: .init(build: .init(data: .init(id: buildID, _type: "builds"))),
      _type: "betaAppReviewSubmissions"
    )))).created.body.json.data.attributes?.betaReviewState
  }

  // MARK: Individual testers

  /// The testers given this build on its own, outside its groups.
  public static func individualTesters(buildID: String, client: ASCClient) async throws -> [BetaTesters.Tester] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.buildsIndividualTestersGetToManyRelated(path: .init(id: buildID), query: .init(limit: 200)).ok.body.json
    }.flatMap(\.data).map(BetaTesters.Tester.init)
  }

  /// Gives a tester the build on its own: an existing tester of the app by email, else a new one
  /// (App Store Connect sends the invitation).
  public static func addIndividualTester(
    email: String, firstName: String? = nil, lastName: String? = nil, buildID: String, appID: String, client: ASCClient
  ) async throws {
    if let tester = try await BetaTesters.find(email: email, appID: appID, client: client) {
      _ = try await client.buildsIndividualTestersCreateToManyRelationship(
        path: .init(id: buildID), body: .json(.init(data: [.init(id: tester.id, _type: "betaTesters")]))
      ).noContent
    } else {
      _ = try await client.betaTestersCreateInstance(body: .json(.init(data: .init(
        attributes: .init(email: email, firstName: firstName, lastName: lastName),
        relationships: .init(builds: .init(data: [.init(id: buildID, _type: "builds")])),
        _type: "betaTesters"
      )))).created
    }
  }

  /// Takes the build away from a tester given it on its own (the tester stays in their groups).
  public static func removeIndividualTester(testerID: String, buildID: String, client: ASCClient) async throws {
    _ = try await client.buildsIndividualTestersDeleteToManyRelationship(
      path: .init(id: buildID), body: .json(.init(data: [.init(id: testerID, _type: "betaTesters")]))
    ).noContent
  }

  /// Ends a build's testing: testers can no longer install it.
  public static func expire(id: String, client: ASCClient) async throws {
    _ = try await client.buildsUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(attributes: .init(expired: true), id: id, _type: "builds")))
    ).ok
  }

  /// Answers export compliance for a build Apple asks about (its Info.plist doesn't say).
  public static func setUsesNonExemptEncryption(_ value: Bool, buildID: String, client: ASCClient) async throws {
    _ = try await client.buildsUpdateInstance(
      path: .init(id: buildID),
      body: .json(.init(data: .init(attributes: .init(usesNonExemptEncryption: value), id: buildID, _type: "builds")))
    ).ok
  }

  /// Tells the build's testers it's available.
  public static func notifyTesters(buildID: String, client: ASCClient) async throws {
    _ = try await client.buildBetaNotificationsCreateInstance(body: .json(.init(data: .init(
      relationships: .init(build: .init(data: .init(id: buildID, _type: "builds"))),
      _type: "buildBetaNotifications"
    )))).created
  }

  /// The build's TestFlight details (states, automatic notification), or nil.
  public static func betaDetail(buildID: String, client: ASCClient) async throws -> Components.Schemas.BuildBetaDetail? {
    try await client.buildBetaDetailsGetCollection(query: .init(filterBuild: [buildID])).ok.body.json.data.first
  }

  /// What testers did with a build: App Store Connect's Invites, Installs, Sessions, Crashes and
  /// Feedback columns.
  public struct Usage: Codable, Hashable, Sendable {
    public let invites: Int
    public let installs: Int
    public let sessions: Int
    public let crashes: Int
    public let feedback: Int
  }

  /// The build's usage over the last year (one data point; Apple keeps a build for 90 days).
  public static func usage(buildID: String, client: ASCClient) async throws -> Usage {
    let points = try await client.buildsBetaBuildUsagesGetMetrics(path: .init(id: buildID)).ok.body.json.data
      .flatMap { $0.dataPoints ?? [] }
    func sum(_ value: (Components.Schemas.BetaBuildUsagesV1MetricResponse.DataPayloadPayload.DataPointsPayloadPayload.ValuesPayload) -> Int?) -> Int {
      points.reduce(0) { $0 + ($1.values.flatMap(value) ?? 0) }
    }
    return Usage(
      invites: sum(\.inviteCount), installs: sum(\.installCount), sessions: sum(\.sessionCount),
      crashes: sum(\.crashCount), feedback: sum(\.feedbackCount))
  }

  /// Whether testers are told automatically when the build becomes available.
  public static func setAutoNotify(_ enabled: Bool, detailID: String, client: ASCClient) async throws {
    _ = try await client.buildBetaDetailsUpdateInstance(
      path: .init(id: detailID),
      body: .json(.init(data: .init(attributes: .init(autoNotifyEnabled: enabled), id: detailID, _type: "buildBetaDetails")))
    ).ok
  }

  /// Attaches a build to an App Store version.
  public static func attach(buildID: String, toVersion versionID: String, client: ASCClient) async throws {
    _ = try await client.appStoreVersionsBuildUpdateToOneRelationship(
      path: .init(id: versionID),
      body: .json(.init(data: .init(id: buildID, _type: "builds")))
    ).noContent
  }

  /// Takes the attached build off an App Store version (sent as `{"data": null}`).
  public static func detach(fromVersion versionID: String, client: ASCClient) async throws {
    _ = try await ASCNulls.sending([["data"]]) {
      try await client.appStoreVersionsBuildUpdateToOneRelationship(
        path: .init(id: versionID),
        body: .json(.init(data: .init(id: "none", _type: "builds")))
      ).noContent
    }
  }

  /// Where a wait for processing stands, for the caller to show.
  public enum ProcessingUpdate: Sendable {
    /// No build matches yet (it can take minutes to appear after an upload).
    case notFound(elapsed: Int)
    case processing(Build)
  }

  public enum ProcessingError: LocalizedError {
    case ended(number: String, state: String)
    case timedOut(minutes: Int)

    public var errorDescription: String? {
      switch self {
        case .ended(let number, let state): "Build \(number) processing ended with state: \(state.lowercased())"
        case .timedOut(let minutes): "Timed out after \(minutes) minutes."
      }
    }
  }

  /// Polls until the latest build (by `number` and `platform` when given) is processed, every
  /// `interval` seconds for up to `timeout` minutes. Returns it once VALID; throws when it ends in
  /// another state or the time runs out.
  public static func waitForProcessing(
    appID: String, number: String?, platform: Platform? = nil, interval: Int = 30, timeout: Int = 30,
    client: ASCClient, report: (ProcessingUpdate) -> Void = { _ in }
  ) async throws -> Build {
    let deadline = Date().addingTimeInterval(Double(timeout * 60))
    var elapsed = 0
    while Date() < deadline {
      if let build = try await list(appID: appID, platform: platform, number: number, limit: 1, client: client).first,
        let state = build.processingState
      {
        switch state {
          case "VALID": return build
          case "PROCESSING": report(.processing(build))
          default: throw ProcessingError.ended(number: build.number ?? "?", state: state)
        }
      } else {
        elapsed += interval
        report(.notFound(elapsed: elapsed))
      }
      try await Task.sleep(for: .seconds(interval))
    }
    throw ProcessingError.timedOut(minutes: timeout)
  }
}

extension Builds.Build {
  /// Its train, e.g. "iOS 5.3".
  public var train: String {
    "\(platform.map { formatState($0) } ?? "?") \(version ?? "?")"
  }

  /// Its train and number, e.g. "iOS 5.3 (42)".
  public var label: String {
    "\(train) (\(number ?? "?"))"
  }
}
