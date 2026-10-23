import ASCKit
import Foundation

/// An app's TestFlight groups: internal ones (App Store Connect users) and external ones (anyone
/// invited by email or a public link, after beta review), and the builds each can test.
public enum BetaGroups {
  public struct Group: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isInternal: Bool
    /// An internal group that gets every build as it's processed (it has no list of builds).
    public let hasAccessToAllBuilds: Bool
    public let publicLinkEnabled: Bool
    public let publicLink: String?
    /// The most testers the public link takes, when it's limited.
    public let publicLinkLimit: Int?
    public let feedbackEnabled: Bool
    /// Whether testers can run the iOS builds on Apple silicon Macs and Apple Vision Pro (App
    /// Store Connect's "Test iPhone and iPad Apps on …"; nil when Apple doesn't say).
    public let iOSBuildsOnMac: Bool?
    public let iOSBuildsOnVision: Bool?
    public let createdDate: Date?

    public init(_ group: Components.Schemas.BetaGroup) {
      let attributes = group.attributes
      id = group.id
      name = attributes?.name ?? ""
      isInternal = attributes?.isInternalGroup ?? false
      hasAccessToAllBuilds = attributes?.hasAccessToAllBuilds ?? false
      publicLinkEnabled = attributes?.publicLinkEnabled ?? false
      publicLink = attributes?.publicLink
      publicLinkLimit = attributes?.publicLinkLimitEnabled == true ? attributes?.publicLinkLimit : nil
      feedbackEnabled = attributes?.feedbackEnabled ?? false
      iOSBuildsOnMac = attributes?.iosBuildsAvailableForAppleSiliconMac
      iOSBuildsOnVision = attributes?.iosBuildsAvailableForAppleVision
      createdDate = attributes?.createdDate
    }
  }

  /// The app's groups, by name.
  public static func list(appID: String, client: ASCClient) async throws -> [Group] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.betaGroupsGetCollection(query: .init(filterApp: [appID], sort: [.name], limit: 200)).ok.body.json
    }.flatMap(\.data).map(Group.init)
  }

  /// Creates a group. An internal one can get every build as it's processed; an external one can
  /// have a public link, limited to a number of testers (which turns the link on).
  public static func create(
    appID: String, name: String, isInternal: Bool, allBuilds: Bool = false, publicLink: Bool = false,
    publicLinkLimit: Int? = nil, feedback: Bool? = nil, client: ASCClient
  ) async throws -> Group {
    let linkEnabled = publicLink || publicLinkLimit != nil
    let response = try await client.betaGroupsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(
        feedbackEnabled: feedback,
        hasAccessToAllBuilds: allBuilds ? true : nil,
        isInternalGroup: isInternal ? true : nil,
        name: name,
        publicLinkEnabled: linkEnabled ? true : nil,
        publicLinkLimit: publicLinkLimit,
        publicLinkLimitEnabled: publicLinkLimit != nil ? true : nil
      ),
      relationships: .init(app: .init(data: .init(id: appID, _type: "apps"))),
      _type: "betaGroups"
    )))).created.body.json
    return Group(response.data)
  }

  /// Changes a group's name, public link, feedback and where its iOS builds run; nil leaves one as
  /// it is. A limit of 0 removes the public link's limit.
  @discardableResult
  public static func update(
    groupID: String, name: String? = nil, publicLink: Bool? = nil, publicLinkLimit: Int? = nil, feedback: Bool? = nil,
    iOSBuildsOnMac: Bool? = nil, iOSBuildsOnVision: Bool? = nil, client: ASCClient
  ) async throws -> Group {
    let response = try await client.betaGroupsUpdateInstance(
      path: .init(id: groupID),
      body: .json(.init(data: .init(
        attributes: .init(
          feedbackEnabled: feedback,
          iosBuildsAvailableForAppleSiliconMac: iOSBuildsOnMac,
          iosBuildsAvailableForAppleVision: iOSBuildsOnVision,
          name: name,
          publicLinkEnabled: publicLink,
          publicLinkLimit: (publicLinkLimit ?? 0) > 0 ? publicLinkLimit : nil,
          publicLinkLimitEnabled: publicLinkLimit.map { $0 > 0 }
        ),
        id: groupID,
        _type: "betaGroups"
      )))
    ).ok.body.json
    return Group(response.data)
  }

  /// Deletes a group: its testers lose access to its builds (they stay testers of the app).
  public static func delete(groupID: String, client: ASCClient) async throws {
    _ = try await client.betaGroupsDeleteInstance(path: .init(id: groupID)).noContent
  }

  /// The group's testers, by email.
  public static func testers(groupID: String, client: ASCClient) async throws -> [BetaTesters.Tester] {
    try await BetaTesters.list(groupID: groupID, client: client)
  }

  /// Takes a tester out of a group (they stay a tester of the app).
  public static func removeTester(_ testerID: String, fromGroup groupID: String, client: ASCClient) async throws {
    _ = try await client.betaGroupsBetaTestersDeleteToManyRelationship(
      path: .init(id: groupID), body: .json(.init(data: [.init(id: testerID, _type: "betaTesters")]))
    ).noContent
  }

  /// Gives a group a build to test.
  public static func addBuild(_ buildID: String, toGroup groupID: String, client: ASCClient) async throws {
    _ = try await client.betaGroupsBuildsCreateToManyRelationship(
      path: .init(id: groupID), body: .json(.init(data: [.init(id: buildID, _type: "builds")]))
    ).noContent
  }

  /// Takes a build away from a group.
  public static func removeBuild(_ buildID: String, fromGroup groupID: String, client: ASCClient) async throws {
    _ = try await client.betaGroupsBuildsDeleteToManyRelationship(
      path: .init(id: groupID), body: .json(.init(data: [.init(id: buildID, _type: "builds")]))
    ).noContent
  }
}
