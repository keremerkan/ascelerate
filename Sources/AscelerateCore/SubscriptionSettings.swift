import ASCKit
import Foundation

/// The app's settings for all its subscriptions: the billing grace period and streamlined
/// purchasing.
///
/// Seen live 2026-10-22: every app has a grace period record (off: both opt-ins false, no
/// duration or renewal type), changed only with a PATCH. Turning on production alone sets the
/// others to App Store Connect's defaults (sandbox on, 16 days, all renewals); production can't
/// be on with sandbox off (409); turning both off clears the duration and renewal type, and a
/// change while off is ignored. Turning on sandbox with a duration alone left the renewal type
/// empty, so `updateGracePeriod` callers should send all four when turning it on.
extension Subscriptions {
  public struct GracePeriod: Equatable, Sendable {
    public let id: String
    /// On for customers (production); sandbox is then on too.
    public var optIn: Bool
    public var sandboxOptIn: Bool
    /// THREE_DAYS, SIXTEEN_DAYS or TWENTY_EIGHT_DAYS; nil while off.
    public var duration: String?
    /// ALL_RENEWALS, or PAID_TO_PAID_ONLY (not when a free trial or an offer turns paid); nil while off.
    public var renewalType: String?

    init(_ period: Components.Schemas.SubscriptionGracePeriod) {
      id = period.id
      optIn = period.attributes?.optIn ?? false
      sandboxOptIn = period.attributes?.sandboxOptIn ?? false
      duration = period.attributes?.duration
      renewalType = period.attributes?.renewalType
    }
  }

  public static func gracePeriod(appID: String, client: ASCClient) async throws -> GracePeriod {
    GracePeriod(try await client.appsSubscriptionGracePeriodGetToOneRelated(path: .init(id: appID)).ok.body.json.data)
  }

  /// Changes the given settings and returns them as saved.
  public static func updateGracePeriod(
    id: String, optIn: Bool? = nil, sandboxOptIn: Bool? = nil, duration: String? = nil, renewalType: String? = nil,
    client: ASCClient
  ) async throws -> GracePeriod {
    GracePeriod(try await client.subscriptionGracePeriodsUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(
        attributes: .init(duration: duration, optIn: optIn, renewalType: renewalType, sandboxOptIn: sandboxOptIn),
        id: id, _type: "subscriptionGracePeriods")))
    ).ok.body.json.data)
  }

  /// Whether customers can buy the app's subscriptions outside the app (on its product page);
  /// on by default. Turning it off needs an approved build with the StoreKit purchase APIs (Apple
  /// refuses otherwise: "cannot be disabled for this app", seen 2026-10-22).
  public static func streamlinedPurchasing(appID: String, client: ASCClient) async throws -> Bool {
    try await client.appsGetInstance(path: .init(id: appID), query: .init(fieldsApps: [.streamlinedPurchasingEnabled]))
      .ok.body.json.data.attributes?.streamlinedPurchasingEnabled ?? true
  }

  /// Turns streamlined purchasing on or off and returns it as saved.
  public static func setStreamlinedPurchasing(appID: String, enabled: Bool, client: ASCClient) async throws -> Bool {
    try await client.appsUpdateInstance(
      path: .init(id: appID),
      body: .json(.init(data: .init(attributes: .init(streamlinedPurchasingEnabled: enabled), id: appID, _type: "apps")))
    ).ok.body.json.data.attributes?.streamlinedPurchasingEnabled ?? enabled
  }
}
