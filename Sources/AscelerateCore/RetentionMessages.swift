import ASCKit
import Foundation

/// Retention messaging (App Store Connect API 4.6): what the App Store shows a subscriber who goes
/// to cancel in their subscription settings. A message is the app's: versions (one unreleased at a
/// time, reviewed by App Review), each with a header and body per language and an optional image
/// (an asset library placement on the version). A subscription shows one message and, in it, any
/// of its retention offers. Verified live 2026-11-05 on a test app (never submitted): a new message
/// has no version until one is created, which starts in Prepare for Submission; a second unreleased
/// version is refused (409 "Version already exists"); a message still shown by a subscription can be
/// deleted; a subscription showed four offers at once.
public enum RetentionMessages {
  public struct Message: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// Newest first as Apple lists them; the unreleased one, if any, is `editable`.
    public let versions: [Version]
    /// The subscriptions showing it, by ID.
    public let subscriptionIDs: [String]

    /// The version being prepared (or rejected), else the latest.
    public var current: Version? { versions.first(where: \.isEditable) ?? versions.first }
  }

  public struct Version: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// PREPARE_FOR_SUBMISSION, WAITING_FOR_REVIEW, IN_REVIEW, APPROVED, REJECTED…
    public let state: String

    /// Whether its languages and image can change: not while App Review has it, not once approved.
    public var isEditable: Bool { RetentionMessages.editableStates.contains(state) }
  }

  public struct Localization: Hashable, Identifiable, Sendable {
    public let id: String
    public let locale: String
    public let header: String
    public let body: String
  }

  /// The image on a version: its placement, and the library image placed.
  public struct Image: Hashable, Sendable {
    public let placementID: String
    public let imageID: String?
    public let fileName: String?
    public let state: String?
    /// The image's address (`{w}x{h}bb.{f}` placeholders) and size, once Apple has processed it.
    public let imageTemplate: String?
    public let width: Int?
    public let height: Int?
  }

  public static let editableStates: Set = ["PREPARE_FOR_SUBMISSION", "REJECTED", "DEVELOPER_REJECTED"]
  /// The most characters each field takes (and at least one): Apple's 409 says so.
  public static let headerLimit = 66
  public static let bodyLimit = 144

  /// The app's messages with their versions and the subscriptions showing them.
  public static func list(appID: String, client: ASCClient) async throws -> [Message] {
    let pages = try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.appsRetentionMessagesGetToManyRelated(
        path: .init(id: appID),
        query: .init(limit: 200, include: [.versions, .subscriptions], limitVersions: 50, limitSubscriptions: 50)
      ).ok.body.json
    }
    var versions: [String: Version] = [:]
    for page in pages {
      for case .retentionMessageVersions(let version) in page.included ?? [] {
        versions[version.id] = Version(id: version.id, state: version.attributes?.state ?? "")
      }
    }
    return pages.flatMap(\.data).map { message in
      Message(
        id: message.id, name: message.attributes?.referenceName ?? "",
        versions: (message.relationships?.versions?.data ?? []).compactMap { versions[$0.id] },
        subscriptionIDs: (message.relationships?.subscriptions?.data ?? []).map(\.id))
    }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  /// A message by its name (case-insensitive) or ID.
  public static func find(_ nameOrID: String, appID: String, client: ASCClient) async throws -> Message {
    let messages = try await list(appID: appID, client: client)
    guard let message = messages.first(where: { $0.id == nameOrID || $0.name.caseInsensitiveCompare(nameOrID) == .orderedSame })
    else { throw RetentionError.noMessage(nameOrID, known: messages.map(\.name)) }
    return message
  }

  /// A new message with its first version, ready for its languages.
  public static func create(appID: String, name: String, client: ASCClient) async throws -> (message: String, version: String) {
    let message = try await client.retentionMessagesCreateInstance(body: .json(.init(data: .init(
      attributes: .init(referenceName: name),
      relationships: .init(app: .init(data: .init(id: appID, _type: "apps"))),
      _type: "retentionMessages")))).created.body.json.data.id
    return (message, try await createVersion(messageID: message, client: client))
  }

  /// A new version, for changing a message once the last one went to App Review (one unreleased
  /// version at a time).
  public static func createVersion(messageID: String, client: ASCClient) async throws -> String {
    try await client.retentionMessageVersionsCreateInstance(body: .json(.init(data: .init(
      relationships: .init(retentionMessage: .init(data: .init(id: messageID, _type: "retentionMessages"))),
      _type: "retentionMessageVersions")))).created.body.json.data.id
  }

  /// Deletes a message, and its image placements first (`AssetLibrary.clearPlacements`), so the
  /// images can still be deleted from the library.
  public static func delete(_ message: Message, client: ASCClient) async throws {
    for version in message.versions where version.isEditable {
      try await AssetLibrary.clearPlacements(on: .retentionMessageVersion(version.id), client: client)
    }
    _ = try await client.retentionMessagesDeleteInstance(path: .init(id: message.id)).noContent
  }

  // MARK: Languages

  public static func localizations(versionID: String, client: ASCClient) async throws -> [Localization] {
    try await client.retentionMessageVersionsLocalizationsGetToManyRelated(path: .init(id: versionID), query: .init(limit: 50))
      .ok.body.json.data.map {
        Localization(
          id: $0.id, locale: $0.attributes?.locale ?? "", header: $0.attributes?.header ?? "", body: $0.attributes?.body ?? "")
      }
      .sorted { $0.locale < $1.locale }
  }

  /// Saves a language's header and body: changes the existing localization, or creates one.
  public static func save(
    locale: String, header: String, body: String, versionID: String, existing: Localization?, client: ASCClient
  ) async throws {
    if let existing {
      _ = try await client.retentionMessageLocalizationsUpdateInstance(
        path: .init(id: existing.id),
        body: .json(.init(data: .init(attributes: .init(body: body, header: header), id: existing.id, _type: "retentionMessageLocalizations")))
      ).ok
    } else {
      _ = try await client.retentionMessageLocalizationsCreateInstance(body: .json(.init(data: .init(
        attributes: .init(body: body, header: header, locale: locale),
        relationships: .init(retentionMessageVersion: .init(data: .init(id: versionID, _type: "retentionMessageVersions"))),
        _type: "retentionMessageLocalizations")))).created
    }
  }

  public static func deleteLocalization(id: String, client: ASCClient) async throws {
    _ = try await client.retentionMessageLocalizationsDeleteInstance(path: .init(id: id)).noContent
  }

  /// The fields that don't fit Apple's limits, in words; empty when both do.
  public static func problems(header: String, body: String) -> [String] {
    var problems: [String] = []
    for (name, value, limit) in [("header", header, headerLimit), ("body", body, bodyLimit)] {
      if value.isEmpty { problems.append("The \(name) can't be empty.") }
      if value.count > limit { problems.append("The \(name) has \(value.count) characters; it takes \(limit) at most.") }
    }
    return problems
  }

  // MARK: Image

  /// The asset library slot of a message's image: one per version, 16:9 (`appAssetLibraryRefData`,
  /// read 2026-11-05).
  public static let imageSlot = AssetLibrary.Slot(
    fileLabel: "Image", placementType: .retentionMessageAsset, group: "DEFAULT_PROFILE", category: "CREATIVE_ASSETS",
    imageSpecs: [.size(3840, 2160, ["png", "jpg", "jpeg"]), .size(5244, 2950, ["png"])],
    isSingle: true, isPlatformIndependent: true)

  /// A version's image; nil without one.
  public static func image(versionID: String, client: ASCClient) async throws -> Image? {
    guard
      let response = try await optionalRelated({
        try await client.retentionMessageVersionsPlacementGetToOneRelated(
          path: .init(id: versionID), query: .init(include: [.image])
        ).ok.body.json
      })
    else { return nil }
    let imageID = response.data.relationships?.value1?.value2.image?.data?.id
    let image = (response.included ?? []).lazy.compactMap { item -> Components.Schemas.AppAssetLibraryImage? in
      if case .appAssetLibraryImages(let image) = item, image.id == imageID { image } else { nil }
    }.first
    let asset = image?.attributes?.common.imageAsset
    // An empty address comes before Apple has processed it.
    return Image(
      placementID: response.data.id, imageID: imageID, fileName: image?.attributes?.common.fileName, state: image?.attributes?.stateName,
      imageTemplate: asset?.templateUrl.flatMap { $0.isEmpty ? nil : $0 }, width: asset?.width, height: asset?.height)
  }

  /// Uploads an image to the app's asset library and places it on the version, then removes the
  /// image it replaces. Check its size first (`imageSlot.imageSpecs`).
  public static func setImage(
    _ file: MediaFile, versionID: String, appID: String, replacing current: Image?, client: ASCClient
  ) async throws {
    let libraryID = try await AssetLibrary.libraryID(appID: appID, client: client)
    let imageID = try await AssetLibrary.uploadImage(file, category: imageSlot.category, libraryID: libraryID, client: client)
    if let current { try await removeImage(current, client: client) }
    _ = try await AssetLibrary.place(
      .image(imageID), on: .retentionMessageVersion(versionID), type: imageSlot.placementType, group: imageSlot.group,
      client: client)
  }

  /// Takes a version's image off it, and out of the library when nothing else uses it (a removed
  /// placement leaves its image in the library otherwise).
  public static func removeImage(_ image: Image, client: ASCClient) async throws {
    try await AssetLibrary.deletePlacement(id: image.placementID, client: client)
    if let imageID = image.imageID { _ = try await AssetLibrary.deleteIfUnused([.image(imageID)], client: client) }
  }

  // MARK: Subscriptions

  /// The message a subscription shows; nil without one.
  public static func messageID(subscriptionID: String, client: ASCClient) async throws -> String? {
    try await optionalRelated {
      try await client.subscriptionsRetentionMessageGetToOneRelated(path: .init(id: subscriptionID)).ok.body.json.data.id
    }
  }

  /// Sets the message a subscription shows, or none.
  public static func assign(_ messageID: String?, subscriptionID: String, client: ASCClient) async throws {
    func send() async throws {
      _ = try await client.subscriptionsRetentionMessageUpdateToOneRelationship(
        path: .init(id: subscriptionID), body: .json(.init(data: .init(id: messageID ?? "", _type: "retentionMessages"))))
    }
    if messageID == nil {
      try await ASCNulls.sending([["data"]], send)
    } else {
      try await send()
    }
  }

  /// The retention offers a subscription shows in its message, by ID.
  public static func shownOffers(subscriptionID: String, client: ASCClient) async throws -> [String] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.subscriptionsRetentionMessageOffersGetToManyRelationship(path: .init(id: subscriptionID), query: .init(limit: 200))
        .ok.body.json
    }.flatMap(\.data).map(\.id)
  }

  /// Makes a subscription's message show exactly `offerIDs`: adds the missing ones and removes the rest.
  public static func showOffers(_ offerIDs: [String], subscriptionID: String, client: ASCClient) async throws {
    let shown = try await shownOffers(subscriptionID: subscriptionID, client: client)
    let added = offerIDs.filter { !shown.contains($0) }
    let removed = shown.filter { !offerIDs.contains($0) }
    if !removed.isEmpty {
      _ = try await client.subscriptionsRetentionMessageOffersDeleteToManyRelationship(
        path: .init(id: subscriptionID), body: .json(.init(data: removed.map { .init(id: $0, _type: "retentionOffers") })))
    }
    if !added.isEmpty {
      _ = try await client.subscriptionsRetentionMessageOffersCreateToManyRelationship(
        path: .init(id: subscriptionID), body: .json(.init(data: added.map { .init(id: $0, _type: "retentionOffers") })))
    }
  }

  /// A version's review submission item.
  public static func reviewItem(versionID: String) -> ReviewSubmissions.DraftItem { .retentionMessageVersion(versionID) }
}

public enum RetentionError: LocalizedError {
  case noMessage(String, known: [String])
  case noEditableVersion(String)

  public var errorDescription: String? {
    switch self {
      case .noMessage(let name, let known):
        known.isEmpty
          ? "The app has no retention messages."
          : "No retention message “\(name)”. The app's messages: \(known.joined(separator: ", "))."
      case .noEditableVersion(let state):
        "The message's latest version is \(formatState(state)) and can't change. Create a new version first."
    }
  }
}

/// A subscription's retention offers: discounts or free time offered in its retention message to
/// subscribers going to cancel. Verified live 2026-11-05: Apple takes a paid subscription duration
/// of 1–24, 36, 48 or 60 months and an optional wait between offers of 2–24 months; a free trial's
/// prices name territories without a tier; the target plan type is UPFRONT when none is sent. Only
/// the eligibility changes after creating one (`RetentionOfferUpdateRequest`).
extension Subscriptions {
  public struct RetentionOffer: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    /// The offer's identifier (unique within the subscription).
    public let offerID: String?
    public let mode: String?
    public let duration: String?
    public let periods: Int?
    /// How long a subscriber must have paid for it, in months.
    public let paidMonths: Int?
    /// How long since their last offer, in months.
    public let waitMonths: Int?
    /// UPFRONT or MONTHLY: the billing plan it's for.
    public let planType: String?
  }

  /// The months a retention or win-back offer can ask subscribers to have paid for, and to have
  /// waited since their last offer (Apple's 409s list them).
  public static let offerPaidMonths = Array(1...24) + [36, 48, 60]
  public static let offerWaitMonths = 2...24

  public static func retentionOffers(subscriptionID: String, client: ASCClient) async throws -> [RetentionOffer] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.subscriptionsRetentionOffersGetToManyRelated(path: .init(id: subscriptionID), query: .init(limit: 200))
        .ok.body.json
    }.flatMap(\.data).map(retentionOffer)
  }

  /// One offer, with how many territories it has a price in (included prices are capped at 50,
  /// so the count is the relationship's total).
  public static func retentionOffer(id: String, client: ASCClient) async throws -> (offer: RetentionOffer, priceCount: Int) {
    let data = try await client.retentionOffersGetInstance(path: .init(id: id), query: .init(include: [.prices], limitPrices: 50))
      .ok.body.json.data
    let prices = data.relationships?.prices
    return (retentionOffer(data), prices?.meta?.paging.total ?? prices?.data?.count ?? 0)
  }

  /// Creates an offer with its prices in one request.
  public static func createRetentionOffer(
    subscriptionID: String, name: String, offerID: String, mode: String, duration: String, periods: Int,
    paidMonths: Int, waitMonths: Int?, planType: String?, prices: [OfferPrice], client: ASCClient
  ) async throws -> RetentionOffer {
    let localIDs = prices.indices.map { "${price\($0)}" }
    let inlines = zip(localIDs, prices).map { localID, price in
      Components.Schemas.RetentionOfferPriceInlineCreate(
        id: localID,
        relationships: .init(
          subscriptionPricePoint: price.pricePointID.map { .init(data: .init(id: $0, _type: "subscriptionPricePoints")) },
          territory: .init(data: .init(id: price.territoryID, _type: "territories"))),
        _type: "retentionOfferPrices")
    }
    return retentionOffer(try await client.retentionOffersCreateInstance(body: .json(.init(
      data: .init(
        attributes: .init(
          customerEligibilityPaidSubscriptionDurationInMonths: paidMonths, customerEligibilityWaitBetweenOffersInMonths: waitMonths,
          duration: duration, offerId: offerID, offerMode: mode, periodCount: periods, referenceName: name,
          targetSubscriptionPlanType: planType),
        relationships: .init(
          prices: .init(data: localIDs.map { .init(id: $0, _type: "retentionOfferPrices") }),
          subscription: .init(data: .init(id: subscriptionID, _type: "subscriptions"))),
        _type: "retentionOffers"),
      included: inlines
    ))).created.body.json.data)
  }

  /// Changes an offer's eligibility, the only thing that can change. A wait between offers can't be
  /// removed once set: sending it as null failed with HTTP 500 every time (2026-11-05).
  public static func updateRetentionOffer(id: String, paidMonths: Int?, waitMonths: Int?, client: ASCClient) async throws {
    _ = try await client.retentionOffersUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(
        attributes: .init(
          customerEligibilityPaidSubscriptionDurationInMonths: paidMonths, customerEligibilityWaitBetweenOffersInMonths: waitMonths),
        id: id, _type: "retentionOffers")))
    ).ok
  }

  public static func deleteRetentionOffer(id: String, client: ASCClient) async throws {
    _ = try await client.retentionOffersDeleteInstance(path: .init(id: id)).noContent
  }

  private static func retentionOffer(_ data: Components.Schemas.RetentionOffer) -> RetentionOffer {
    let a = data.attributes
    return RetentionOffer(
      id: data.id, name: a?.referenceName, offerID: a?.offerId, mode: a?.offerMode, duration: a?.duration, periods: a?.periodCount,
      paidMonths: a?.customerEligibilityPaidSubscriptionDurationInMonths, waitMonths: a?.customerEligibilityWaitBetweenOffersInMonths,
      planType: a?.targetSubscriptionPlanType)
  }
}
