import ASCKit
import AscelerateCore
import Foundation

// App Store Connect side of the `ads` commands. Kept apart from the Ads files: ASCKit and
// AppleAdsClient both generate top-level `Client`, `Components` and `Operations` types, so no
// file can import both.

/// App names by App Store app ID (Apple Ads' `promotedObjectId`), from App Store Connect.
/// Apple Ads can promote apps of other accounts, which stay unnamed.
func appStoreAppNames() async throws -> [String: String] {
  let client = try ClientFactory.makeClient()
  let apps = try await ASCPaging.allPages(next: { $0.links.next }) {
    try await client.appsGetCollection(query: .init(limit: 200)).ok.body.json
  }.flatMap(\.data)
  return Dictionary(apps.map { ($0.id, $0.attributes?.name ?? $0.id) }, uniquingKeysWith: { a, _ in a })
}

/// The App Store app ID of a bundle ID or alias (nil for nil), for filtering campaigns by app.
func appStoreAppID(bundleID: String?) async throws -> String? {
  guard let bundleID else { return nil }
  return try await findApp(bundleID: bundleID, client: ClientFactory.makeClient()).id
}

/// A write the Apple Ads dry-run gate stopped, as ASCKit's `ASCDryRunStop`, so `--dry-run`
/// reporting and `run-workflow`'s handling of stopped writes work the same for both APIs.
func adsDryRunStop(method: String, path: String) -> Error {
  ASCDryRun.recordBlockedWrite()
  return ASCDryRunStop(method: method, path: path)
}

/// The App Store app ID, name and primary category ID (e.g. `UTILITIES`) of a bundle ID or alias.
func appStoreApp(bundleID: String) async throws -> (id: String, name: String, primaryCategory: String?) {
  let client = try ClientFactory.makeClient()
  let app = try await findApp(bundleID: bundleID, client: client)
  // The category relationship only carries its ID when included.
  let infos = try await client.appsAppInfosGetToManyRelated(
    path: .init(id: app.id), query: .init(include: [.primaryCategory])
  ).ok.body.json.data
  let info = try AppsCommand.AppInfoCommand.pickActiveAppInfo(from: infos)
  return (app.id, app.attributes?.name ?? bundleID, info.relationships?.primaryCategory?.data?.id)
}
