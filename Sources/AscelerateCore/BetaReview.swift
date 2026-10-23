import ASCKit
import Foundation

/// TestFlight's beta review: a build's review state and the app's beta license agreement. The
/// reviewer's information is `ReviewInformation.beta`; submitting is `Builds.submitForBetaReview`.
public enum BetaReview {
  /// A build's beta review: its submission's ID and state (WAITING_FOR_REVIEW, IN_REVIEW,
  /// APPROVED, REJECTED).
  public struct Submission: Hashable, Sendable {
    public let id: String
    public let state: String?
  }

  /// The build's beta review; nil when it was never submitted.
  public static func submission(buildID: String, client: ASCClient) async throws -> Submission? {
    try await client.betaAppReviewSubmissionsGetCollection(query: .init(filterBuild: [buildID])).ok.body.json
      .data.first.map { Submission(id: $0.id, state: $0.attributes?.betaReviewState) }
  }

  /// The app's beta license agreement, which every app has; empty text is Apple's standard one.
  public struct LicenseAgreement: Hashable, Sendable {
    public let id: String
    public let text: String
  }

  public static func licenseAgreement(appID: String, client: ASCClient) async throws -> LicenseAgreement? {
    try await client.betaLicenseAgreementsGetCollection(query: .init(filterApp: [appID])).ok.body.json
      .data.first.map { LicenseAgreement(id: $0.id, text: $0.attributes?.agreementText ?? "") }
  }

  /// Replaces the agreement's text; empty text brings back Apple's standard agreement.
  public static func setLicenseAgreement(_ text: String, id: String, client: ASCClient) async throws {
    _ = try await client.betaLicenseAgreementsUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(attributes: .init(agreementText: text), id: id, _type: "betaLicenseAgreements")))
    ).ok
  }
}
