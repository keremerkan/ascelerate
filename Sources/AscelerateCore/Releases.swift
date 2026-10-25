import ASCKit
import Foundation

/// How an App Store version reaches customers: its release type (by hand, right after approval, or
/// after approval but not before a date), its phased release (an update offered to automatic
/// updates over seven days), and releasing a version that waits for the developer.
public enum Releases {
  /// A version's phased release.
  public struct PhasedRelease: Sendable, Hashable {
    public let id: String
    /// Raw `phasedReleaseState`: INACTIVE until the version is released, then ACTIVE, PAUSED or
    /// COMPLETE.
    public let state: String?
    public let startDate: Date?
    /// The day of the seven it's on.
    public let currentDayNumber: Int?
    /// Days it was paused.
    public let totalPauseDuration: Int?

    init(_ release: Components.Schemas.AppStoreVersionPhasedRelease) {
      let attributes = release.attributes
      id = release.id
      state = attributes?.phasedReleaseState
      startDate = attributes?.startDate
      currentDayNumber = attributes?.currentDayNumber
      totalPauseDuration = attributes?.totalPauseDuration
    }
  }

  /// Sets a version's release type; `earliestReleaseDate` goes with SCHEDULED and is cleared
  /// otherwise.
  public static func setReleaseType(
    _ releaseType: ASCEnum.AppStoreVersionUpdateRequestReleaseType, earliestReleaseDate: Date?, versionID: String,
    client: ASCClient
  ) async throws {
    let date = releaseType == .scheduled ? earliestReleaseDate : nil
    try await ASCNulls.sending(date == nil ? [["data", "attributes", "earliestReleaseDate"]] : []) {
      _ = try await client.appStoreVersionsUpdateInstance(
        path: .init(id: versionID),
        body: .json(.init(data: .init(
          attributes: .init(earliestReleaseDate: date, releaseType: releaseType.rawValue), id: versionID,
          _type: "appStoreVersions")))
      ).ok
    }
  }

  /// A version's phased release; nil when it has none.
  public static func phasedRelease(versionID: String, client: ASCClient) async throws -> PhasedRelease? {
    try await optionalRelated {
      try await client.appStoreVersionsAppStoreVersionPhasedReleaseGetToOneRelated(path: .init(id: versionID)).ok.body.json.data
    }.map(PhasedRelease.init)
  }

  /// Gives a version a phased release, which starts when the version is released.
  public static func enablePhasedRelease(versionID: String, client: ASCClient) async throws -> PhasedRelease {
    PhasedRelease(try await client.appStoreVersionPhasedReleasesCreateInstance(body: .json(.init(data: .init(
      attributes: .init(phasedReleaseState: ASCEnum.PhasedReleaseState.inactive.rawValue),
      relationships: .init(appStoreVersion: .init(data: .init(id: versionID, _type: "appStoreVersions"))),
      _type: "appStoreVersionPhasedReleases"
    )))).created.body.json.data)
  }

  /// Pauses (PAUSED), resumes (ACTIVE) or completes (COMPLETE: every customer gets the update now)
  /// a phased release.
  public static func setPhasedReleaseState(
    _ state: ASCEnum.PhasedReleaseState, id: String, client: ASCClient
  ) async throws -> PhasedRelease {
    PhasedRelease(try await client.appStoreVersionPhasedReleasesUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(
        attributes: .init(phasedReleaseState: state.rawValue), id: id, _type: "appStoreVersionPhasedReleases")))
    ).ok.body.json.data)
  }

  /// Removes a phased release: the version goes to every customer at once.
  public static func removePhasedRelease(id: String, client: ASCClient) async throws {
    _ = try await client.appStoreVersionPhasedReleasesDeleteInstance(path: .init(id: id)).noContent
  }

  /// Releases a version in Pending Developer Release.
  public static func release(versionID: String, client: ASCClient) async throws {
    _ = try await client.appStoreVersionReleaseRequestsCreateInstance(body: .json(.init(data: .init(
      relationships: .init(appStoreVersion: .init(data: .init(id: versionID, _type: "appStoreVersions"))),
      _type: "appStoreVersionReleaseRequests"
    )))).created
  }
}
