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
  }

  /// The app's Test Information languages, by locale code.
  public static func localizations(appID: String, client: ASCClient) async throws -> [Localization] {
    try await client.betaAppLocalizationsGetCollection(query: .init(filterApp: [appID], limit: 50)).ok.body.json
      .data.map(Localization.init).sorted { $0.locale < $1.locale }
  }
}
