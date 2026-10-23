import ASCKit
import Foundation

/// What a reviewer needs besides the build: a contact, a demo account and notes. App Review keeps
/// one per App Store version (`appStoreReviewDetails`), TestFlight's beta review one per app
/// (`betaAppReviewDetails`, which always exists). The property names are the API's attribute names.
///
/// The contact goes as a whole (seen live 2026-10-23): Apple wants all four contact fields in any
/// request that sets one, refuses to clear one, and refuses every change to an App Store record
/// without a complete contact (a phone number starts with + and the country code). A new App Store
/// record requires a demo account until told otherwise; whether one is given is checked at
/// submission, not on save.
public struct ReviewInformation: Codable, Hashable, Sendable {
  public var contactFirstName: String?
  public var contactLastName: String?
  public var contactPhone: String?
  public var contactEmail: String?
  public var demoAccountRequired: Bool?
  public var demoAccountName: String?
  public var demoAccountPassword: String?
  public var notes: String?

  public init(
    contactFirstName: String? = nil, contactLastName: String? = nil, contactPhone: String? = nil,
    contactEmail: String? = nil, demoAccountRequired: Bool? = nil, demoAccountName: String? = nil,
    demoAccountPassword: String? = nil, notes: String? = nil
  ) {
    self.contactFirstName = contactFirstName
    self.contactLastName = contactLastName
    self.contactPhone = contactPhone
    self.contactEmail = contactEmail
    self.demoAccountRequired = demoAccountRequired
    self.demoAccountName = demoAccountName
    self.demoAccountPassword = demoAccountPassword
    self.notes = notes
  }

  /// A saved record: its ID and contents.
  public struct Detail: Hashable, Sendable {
    public let id: String
    public let information: ReviewInformation
  }

  /// What changed from `old`: the new values to send, and the attributes emptied, which Apple
  /// clears only when they're sent as null. A nil field is left as it is.
  func changes(from old: ReviewInformation) -> (values: ReviewInformation, cleared: [[String]]) {
    var values = ReviewInformation()
    var cleared: [String] = []
    func compare(_ keyPath: WritableKeyPath<ReviewInformation, String?>, _ name: String) {
      guard let new = self[keyPath: keyPath], new != old[keyPath: keyPath] ?? "" else { return }
      if new.isEmpty { cleared.append(name) } else { values[keyPath: keyPath] = new }
    }
    compare(\.contactFirstName, "contactFirstName")
    compare(\.contactLastName, "contactLastName")
    compare(\.contactPhone, "contactPhone")
    compare(\.contactEmail, "contactEmail")
    compare(\.demoAccountName, "demoAccountName")
    compare(\.demoAccountPassword, "demoAccountPassword")
    compare(\.notes, "notes")
    if let required = demoAccountRequired, required != (old.demoAccountRequired ?? false) {
      values.demoAccountRequired = required
    }
    let contact: [WritableKeyPath<ReviewInformation, String?>] = [
      \.contactFirstName, \.contactLastName, \.contactPhone, \.contactEmail,
    ]
    if contact.contains(where: { values[keyPath: $0] != nil }) {
      for keyPath in contact where values[keyPath: keyPath] == nil {
        values[keyPath: keyPath] = (self[keyPath: keyPath] ?? old[keyPath: keyPath]).flatMap { $0.isEmpty ? nil : $0 }
      }
    }
    return (values, cleared.map { ["data", "attributes", $0] })
  }

  // MARK: TestFlight beta review

  /// The app's beta review information.
  public static func beta(appID: String, client: ASCClient) async throws -> Detail? {
    guard let detail = try await client.betaAppReviewDetailsGetCollection(query: .init(filterApp: [appID]))
      .ok.body.json.data.first
    else { return nil }
    let a = detail.attributes
    return Detail(id: detail.id, information: ReviewInformation(
      contactFirstName: a?.contactFirstName, contactLastName: a?.contactLastName, contactPhone: a?.contactPhone,
      contactEmail: a?.contactEmail, demoAccountRequired: a?.demoAccountRequired, demoAccountName: a?.demoAccountName,
      demoAccountPassword: a?.demoAccountPassword, notes: a?.notes))
  }

  /// Saves the beta review information: the fields given that differ from `old`, the record as it
  /// is (empty ones cleared, nil ones left as they are; the contact as a whole).
  public static func saveBeta(
    _ information: ReviewInformation, from old: ReviewInformation = .init(), detailID: String, client: ASCClient
  ) async throws {
    let (v, cleared) = information.changes(from: old)
    _ = try await ASCNulls.sending(cleared) {
      try await client.betaAppReviewDetailsUpdateInstance(
        path: .init(id: detailID),
        body: .json(.init(data: .init(
          attributes: .init(
            contactEmail: v.contactEmail, contactFirstName: v.contactFirstName, contactLastName: v.contactLastName,
            contactPhone: v.contactPhone, demoAccountName: v.demoAccountName,
            demoAccountPassword: v.demoAccountPassword, demoAccountRequired: v.demoAccountRequired, notes: v.notes),
          id: detailID, _type: "betaAppReviewDetails")))
      ).ok
    }
  }

  // MARK: App Review

  /// A version's App Review information; nil until it has some.
  public static func appStore(versionID: String, client: ASCClient) async throws -> Detail? {
    guard let detail = try await optionalRelated({
      try await client.appStoreVersionsAppStoreReviewDetailGetToOneRelated(path: .init(id: versionID)).ok.body.json.data
    }) else { return nil }
    let a = detail.attributes
    return Detail(id: detail.id, information: ReviewInformation(
      contactFirstName: a?.contactFirstName, contactLastName: a?.contactLastName, contactPhone: a?.contactPhone,
      contactEmail: a?.contactEmail, demoAccountRequired: a?.demoAccountRequired, demoAccountName: a?.demoAccountName,
      demoAccountPassword: a?.demoAccountPassword, notes: a?.notes))
  }

  /// Saves a version's App Review information: the fields given that differ from `old` on the
  /// version's record (`detailID`), or every field given on a new one when the version has none.
  /// Returns the record's ID.
  @discardableResult
  public static func saveAppStore(
    _ information: ReviewInformation, from old: ReviewInformation = .init(), detailID: String?, versionID: String,
    client: ASCClient
  ) async throws -> String {
    let (v, cleared) = information.changes(from: old)
    guard let detailID else {
      return try await client.appStoreReviewDetailsCreateInstance(body: .json(.init(data: .init(
        attributes: .init(
          contactEmail: v.contactEmail, contactFirstName: v.contactFirstName, contactLastName: v.contactLastName,
          contactPhone: v.contactPhone, demoAccountName: v.demoAccountName,
          demoAccountPassword: v.demoAccountPassword, demoAccountRequired: v.demoAccountRequired, notes: v.notes),
        relationships: .init(appStoreVersion: .init(data: .init(id: versionID, _type: "appStoreVersions"))),
        _type: "appStoreReviewDetails"
      )))).created.body.json.data.id
    }
    _ = try await ASCNulls.sending(cleared) {
      try await client.appStoreReviewDetailsUpdateInstance(
        path: .init(id: detailID),
        body: .json(.init(data: .init(
          attributes: .init(
            contactEmail: v.contactEmail, contactFirstName: v.contactFirstName, contactLastName: v.contactLastName,
            contactPhone: v.contactPhone, demoAccountName: v.demoAccountName,
            demoAccountPassword: v.demoAccountPassword, demoAccountRequired: v.demoAccountRequired, notes: v.notes),
          id: detailID, _type: "appStoreReviewDetails")))
      ).ok
    }
    return detailID
  }
}
