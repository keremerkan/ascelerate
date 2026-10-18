import ASCKit
import Foundation

/// Picks one of several matches where a lookup is ambiguous: `title` says what matched, and
/// `describe` labels an item.
public typealias Choose<T> = (_ title: String, _ items: [T], _ describe: (T) -> String) async throws -> T

/// App Store version platforms as the spec names them.
public typealias Platform = ASCEnum.Platform

/// Maps a Platform to an endpoint-specific platform filter enum. Every generated
/// platform filter enum shares the same raw values (IOS, MAC_OS, TV_OS, VISION_OS),
/// so one generic mapping covers versions, builds, and future endpoints.
public func platformFilter<F: RawRepresentable>(_ platform: Platform?) -> [F]? where F.RawValue == String {
  platform.map {
    guard let filter = F(rawValue: $0.rawValue) else {
      preconditionFailure("Platform \($0.rawValue) is missing from \(F.self) — ASCKit enums out of sync.")
    }
    return [filter]
  }
}

/// The app with exactly this bundle ID.
public func findApp(exactBundleID bundleID: String, client: ASCClient) async throws -> Components.Schemas.App {
  let response = try await client.appsGetCollection(query: .init(filterBundleId: [bundleID])).ok.body.json
  // filter[bundleId] can return prefix matches, so find the exact match
  guard let app = response.data.first(where: { $0.attributes?.bundleId == bundleID }) else {
    throw AppLookupError.notFound(bundleID)
  }
  return app
}

/// Resolves an App Store version: the given version string, or else the editable version, or else
/// the latest one. A universal-purchase app can match on several platforms; `choose` then picks.
public func findVersion(
  appID: String, versionString: String?, platform: Platform? = nil, client: ASCClient,
  choose: Choose<Components.Schemas.AppStoreVersion>
) async throws -> Components.Schemas.AppStoreVersion {
  func describe(_ v: Components.Schemas.AppStoreVersion) -> String {
    let p = v.attributes?.platform.map { formatState($0) } ?? "?"
    let ver = v.attributes?.versionString ?? "?"
    let state = v.attributes?.appVersionState.map { formatState($0) } ?? "?"
    return "\(p) — \(ver) (\(state))"
  }

  // When no specific version requested, prefer editable versions (prepareForSubmission/waitingForReview)
  if versionString == nil {
    var editable = try await client.appsAppStoreVersionsGetToManyRelated(
      path: .init(id: appID), query: .init(filterAppVersionState: [.prepareForSubmission, .waitingForReview])
    ).ok.body.json.data

    // Filter by platform if specified
    if let platform {
      editable = editable.filter { $0.attributes?.platform == platform.rawValue }
    }

    if editable.count == 1 {
      return editable[0]
    } else if editable.count > 1 {
      return try await choose("Multiple editable versions found", editable, describe)
    }
  }

  // A universal-purchase app can hold the same version string on multiple
  // platforms — filter by platform, and let `choose` pick if still ambiguous.
  var candidates = try await client.appsAppStoreVersionsGetToManyRelated(
    path: .init(id: appID),
    query: .init(filterPlatform: platformFilter(platform), filterVersionString: versionString.map { [$0] })
  ).ok.body.json.data
  if versionString == nil {
    // Fallback (no editable versions): reduce to the latest version per platform.
    // The API returns versions newest-first, so keep the first one seen per platform.
    var seenPlatforms = Set<String?>()
    candidates = candidates.filter { seenPlatforms.insert($0.attributes?.platform).inserted }
  }
  if candidates.count > 1 {
    return try await choose("Multiple matching versions found", candidates, describe)
  }
  guard let version = candidates.first else {
    if let v = versionString {
      throw AppLookupError.versionNotFound(v, platform)
    }
    throw AppLookupError.noVersions(platform)
  }
  return version
}

/// Runs a to-one related fetch, mapping Apple's "no related object" answers (HTTP 404 or
/// `{"data": null}`) to nil.
public func optionalRelated<T>(_ fetch: () async throws -> T) async throws -> T? {
  do {
    return try await fetch()
  } catch where ASCError.isMissingRelated(error) {
    return nil
  }
}

/// The build attached to an App Store version, or nil.
public func attachedBuild(versionID: String, client: ASCClient) async throws -> Components.Schemas.Build? {
  try await optionalRelated {
    try await client.appStoreVersionsBuildGetToOneRelated(path: .init(id: versionID)).ok.body.json.data
  }
}

/// The platform of an App Store version.
public func versionPlatform(_ version: Components.Schemas.AppStoreVersion) -> Platform? {
  version.attributes?.platform.flatMap(Platform.init(rawValue:))
}

public enum AppLookupError: LocalizedError {
  case notFound(String)
  case versionNotFound(String, Platform?)
  case noVersions(Platform?)

  private static func platformSuffix(_ platform: Platform?) -> String {
    platform.map { " for \(formatState($0.rawValue))" } ?? ""
  }

  public var errorDescription: String? {
    switch self {
      case .notFound(let bundleID):
        return "No app found with bundle ID '\(bundleID)'."
      case .versionNotFound(let version, let platform):
        return "No App Store version '\(version)' found\(Self.platformSuffix(platform))."
      case .noVersions(let platform):
        return "No App Store versions found\(Self.platformSuffix(platform))."
    }
  }
}
