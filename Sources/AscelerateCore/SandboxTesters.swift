import ASCKit
import Foundation

/// Sandbox testers (`/v2/sandboxTesters`): the Apple Accounts that buy in-app purchases and
/// subscriptions in the sandbox. The API lists and changes them and clears their purchase history;
/// creating and deleting them is App Store Connect's (Users and Access > Sandbox).
public enum SandboxTesters {
  public struct Tester: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let firstName: String?
    public let lastName: String?
    /// The tester's Apple Account (an email address).
    public let account: String?
    /// The storefront it buys in, as a territory code (`USA`, `TUR`).
    public let territory: String?
    public let applePayCompatible: Bool?
    /// Whether purchases stop for an extra step (payment, terms), as App Store Connect's
    /// "Interrupt Purchases for This Tester".
    public let interruptPurchases: Bool?
    /// How fast a monthly subscription renews: `MONTHLY_RENEWAL_EVERY_ONE_HOUR`, …`_THIRTY_MINUTES`,
    /// `_FIFTEEN_MINUTES`, `_FIVE_MINUTES` or `_THREE_MINUTES`.
    public let renewalRate: String?

    public var name: String { [firstName, lastName].compactMap(\.self).joined(separator: " ") }

    init(_ tester: Components.Schemas.SandboxTesterV2) {
      let a = tester.attributes
      id = tester.id
      firstName = a?.firstName
      lastName = a?.lastName
      account = a?.acAccountName
      territory = a?.territory
      applePayCompatible = a?.applePayCompatible
      interruptPurchases = a?.interruptPurchases
      renewalRate = a?.subscriptionRenewalRate
    }
  }

  public enum LookupError: LocalizedError {
    case notFound(String)

    public var errorDescription: String? {
      switch self {
        case .notFound(let reference): "No sandbox tester '\(reference)'. Use its Apple Account (email) or ID."
      }
    }
  }

  /// The team's sandbox testers, by name.
  public static func list(client: ASCClient) async throws -> [Tester] {
    try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.sandboxTestersV2GetCollection(query: .init(limit: 200)).ok.body.json
      }
    }
    .flatMap(\.data).map(Tester.init)
    .sorted { ($0.account ?? "").localizedStandardCompare($1.account ?? "") == .orderedAscending }
  }

  /// A tester by its Apple Account (case-insensitive) or ID, among `testers`.
  public static func find(_ reference: String, in testers: [Tester]) throws -> Tester {
    guard let tester = testers.first(where: { $0.id == reference || $0.account?.lowercased() == reference.lowercased() }) else {
      throw LookupError.notFound(reference)
    }
    return tester
  }

  /// Changes a tester's storefront, interrupted purchases or renewal rate (nil leaves one as it
  /// is); returns the tester as saved.
  public static func update(
    id: String, territory: String? = nil, interruptPurchases: Bool? = nil, renewalRate: String? = nil, client: ASCClient
  ) async throws -> Tester {
    let saved = try await client.sandboxTestersV2UpdateInstance(path: .init(id: id), body: .json(.init(data: .init(
      attributes: .init(interruptPurchases: interruptPurchases, subscriptionRenewalRate: renewalRate, territory: territory),
      id: id, _type: "sandboxTesters"))))
      .ok.body.json.data
    return Tester(saved)
  }

  /// Clears the purchase history of the testers (one request for all): their in-app purchases
  /// and subscriptions can be bought again from the start.
  public static func clearPurchaseHistory(testerIDs: [String], client: ASCClient) async throws {
    _ = try await client.sandboxTestersClearPurchaseHistoryRequestV2CreateInstance(body: .json(.init(data: .init(
      relationships: .init(sandboxTesters: .init(data: testerIDs.map { .init(id: $0, _type: "sandboxTesters") })),
      _type: "sandboxTestersClearPurchaseHistoryRequest")))).created
  }
}
