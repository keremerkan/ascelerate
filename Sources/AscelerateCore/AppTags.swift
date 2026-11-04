import ASCKit
import Foundation

/// An app's tags (`apps/{id}/appTags`): the words Apple shows on the App Store for what the app
/// does, each in the territories it applies to. Apple chooses them; the developer only hides or
/// shows each one.
public enum AppTags {
  public struct Tag: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let visibleInAppStore: Bool
    /// The territories it's shown in, as territory codes.
    public let territories: [String]
  }

  /// An app's tags by name, with their territories.
  public static func list(appID: String, client: ASCClient) async throws -> [Tag] {
    let tags = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.appsAppTagsGetToManyRelated(path: .init(id: appID), query: .init(limit: 200)).ok.body.json
      }
    }.flatMap(\.data)
    return try await boundedConcurrentMap(tags) { tag in
      // Read on their own: an include caps them at 50 of the 175 territories.
      let territories = try await withTransientRetry {
        try await ASCPaging.allPages(next: { $0.links.next }) {
          try await client.appTagsTerritoriesGetToManyRelated(path: .init(id: tag.id), query: .init(limit: 200)).ok.body.json
        }
      }.flatMap(\.data).map(\.id).sorted()
      return Tag(id: tag.id, name: tag.attributes?.name, visibleInAppStore: tag.attributes?.visibleInAppStore ?? false, territories: territories)
    }
    .sorted { ($0.name ?? "").localizedStandardCompare($1.name ?? "") == .orderedAscending }
  }

  /// Shows or hides a tag on the App Store.
  public static func setVisible(_ visible: Bool, tagID: String, client: ASCClient) async throws {
    _ = try await client.appTagsUpdateInstance(path: .init(id: tagID), body: .json(.init(data: .init(
      attributes: .init(visibleInAppStore: visible), id: tagID, _type: "appTags")))).ok
  }
}
