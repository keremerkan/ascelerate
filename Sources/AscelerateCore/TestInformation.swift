import ASCKit
import Foundation

/// An app's TestFlight Test Information: per language, what testers read about the beta and where
/// they send feedback (`betaAppLocalizations`). Its languages are TestFlight's (see
/// `Builds.TestNotes`), the ones a build's What to Test is written in.
public enum TestInformation {
  public struct Localization: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let locale: String
    public let description: String?
    public let feedbackEmail: String?
    public let marketingURL: String?
    public let privacyPolicyURL: String?
    public let tvOSPrivacyPolicy: String?

    public init(_ localization: Components.Schemas.BetaAppLocalization) {
      let attributes = localization.attributes
      id = localization.id
      locale = attributes?.locale ?? ""
      description = attributes?.description
      feedbackEmail = attributes?.feedbackEmail
      marketingURL = attributes?.marketingUrl
      privacyPolicyURL = attributes?.privacyPolicyUrl
      tvOSPrivacyPolicy = attributes?.tvOsPrivacyPolicy
    }

    /// The language as a localization file's entry.
    public var fields: BetaAppLocaleFields {
      BetaAppLocaleFields(
        description: description, feedbackEmail: feedbackEmail, marketingURL: marketingURL,
        privacyPolicyURL: privacyPolicyURL, tvOsPrivacyPolicy: tvOSPrivacyPolicy)
    }
  }

  /// The app's Test Information languages, by locale code.
  public static func localizations(appID: String, client: ASCClient) async throws -> [Localization] {
    try await client.betaAppLocalizationsGetCollection(query: .init(filterApp: [appID], limit: 50)).ok.body.json
      .data.map(Localization.init).sorted { $0.locale < $1.locale }
  }

  /// Saves one language's fields: a language the app has is updated (nil fields left as they
  /// are, empty ones cleared), another one created. `report` hears of each language as it's saved
  /// (true: created), on the caller's actor.
  public static func save(
    _ updates: [(locale: String, fields: BetaAppLocaleFields)], appID: String, client: ASCClient,
    isolation: isolated (any Actor)? = #isolation, report: (_ locale: String, _ created: Bool) -> Void = { _, _ in }
  ) async throws {
    let existing = try await localizations(appID: appID, client: client)
    _ = try await save(updates, existing: existing, appID: appID, client: client, report: report)
  }

  /// `save` with the languages already read (`localizations(appID:)`), so nothing is read again.
  /// Returns the languages as App Store Connect saved them, in the order of `updates`.
  public static func save(
    _ updates: [(locale: String, fields: BetaAppLocaleFields)], existing: [Localization], appID: String,
    client: ASCClient, isolation: isolated (any Actor)? = #isolation,
    report: (_ locale: String, _ created: Bool) -> Void = { _, _ in }
  ) async throws -> [Localization] {
    var saved: [Localization] = []
    for (locale, fields, existingID) in saveTargets(updates.map { ($0.locale, $0.fields) }, existing: existing.map { ($0.locale, $0.id) }) {
      if let existingID {
        saved.append(try await update(id: existingID, fields: fields, client: client))
        report(locale, false)
      } else {
        let created = try await client.betaAppLocalizationsCreateInstance(body: .json(.init(data: .init(
          attributes: .init(
            description: value(fields.description), feedbackEmail: value(fields.feedbackEmail), locale: locale,
            marketingUrl: value(fields.marketingURL), privacyPolicyUrl: value(fields.privacyPolicyURL),
            tvOsPrivacyPolicy: value(fields.tvOsPrivacyPolicy)),
          relationships: .init(app: .init(data: .init(id: appID, _type: "apps"))),
          _type: "betaAppLocalizations"
        )))).created.body.json.data
        saved.append(Localization(created))
        report(locale, true)
      }
    }
    return saved
  }

  private static func update(id: String, fields: BetaAppLocaleFields, client: ASCClient) async throws -> Localization {
    let cleared = [
      ("description", fields.description), ("feedbackEmail", fields.feedbackEmail),
      ("marketingUrl", fields.marketingURL), ("privacyPolicyUrl", fields.privacyPolicyURL),
      ("tvOsPrivacyPolicy", fields.tvOsPrivacyPolicy),
    ].filter { $0.1?.isEmpty == true }.map { ["data", "attributes", $0.0] }
    return try await ASCNulls.sending(cleared) {
      Localization(try await client.betaAppLocalizationsUpdateInstance(
        path: .init(id: id),
        body: .json(.init(data: .init(
          attributes: .init(
            description: value(fields.description), feedbackEmail: value(fields.feedbackEmail),
            marketingUrl: value(fields.marketingURL), privacyPolicyUrl: value(fields.privacyPolicyURL),
            tvOsPrivacyPolicy: value(fields.tvOsPrivacyPolicy)),
          id: id, _type: "betaAppLocalizations")))
      ).ok.body.json.data)
    }
  }

  /// Nil for an empty text: it isn't sent.
  private static func value(_ text: String?) -> String? {
    text?.isEmpty == true ? nil : text
  }

  /// Removes a language.
  public static func delete(id: String, client: ASCClient) async throws {
    _ = try await client.betaAppLocalizationsDeleteInstance(path: .init(id: id)).noContent
  }
}

/// Each update with the ID of the existing record for its locale (nil: create it), in the updates'
/// order; the first record of a locale wins. Shared by Test Information and What to Test.
func saveTargets<Value>(_ updates: [(String, Value)], existing: [(locale: String, id: String)]) -> [(locale: String, value: Value, existingID: String?)] {
  let byLocale = Dictionary(existing.map { ($0.locale, $0.id) }, uniquingKeysWith: { first, _ in first })
  return updates.map { ($0.0, $0.1, byLocale[$0.0]) }
}
