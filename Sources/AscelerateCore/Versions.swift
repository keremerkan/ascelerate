import ASCKit
import Foundation

/// What `createVersion` did.
public enum VersionCreation: Sendable {
  /// The version was created.
  case created(Components.Schemas.AppStoreVersion)
  /// The version already existed in PREPARE_FOR_SUBMISSION, so there was nothing to create.
  case alreadyInPreparation(Components.Schemas.AppStoreVersion)
}

public enum VersionCreationError: LocalizedError {
  /// The version exists for the platform in a state other than PREPARE_FOR_SUBMISSION
  /// (raw `appVersionState`, when known).
  case alreadyExists(versionString: String, platform: Platform, state: String?)

  public var errorDescription: String? {
    switch self {
      case .alreadyExists(let versionString, let platform, let state):
        return "Version \(versionString) already exists for \(formatState(platform.rawValue)) (state: \(state.map { formatState($0) } ?? "unknown"))."
    }
  }
}

/// Creates an App Store version for one platform unless it exists. One app record can hold the
/// same version string per platform (universal purchase), so only that platform's version counts:
/// one still in PREPARE_FOR_SUBMISSION is returned as is, any other state throws
/// `VersionCreationError.alreadyExists`. A nil `releaseType` keeps the previous version's setting.
public func createVersion(
  appID: String, versionString: String, platform: Platform,
  releaseType: ASCEnum.AppStoreVersionCreateRequestReleaseType?, copyright: String?, client: ASCClient
) async throws -> VersionCreation {
  let existingVersions = try await client.appsAppStoreVersionsGetToManyRelated(
    path: .init(id: appID), query: .init(filterVersionString: [versionString])
  ).ok.body.json
  if let existing = existingVersions.data.first(where: {
    $0.attributes?.versionString == versionString && $0.attributes?.platform == platform.rawValue
  }) {
    let state = existing.attributes?.appVersionState
    guard state == "PREPARE_FOR_SUBMISSION" else {
      throw VersionCreationError.alreadyExists(versionString: versionString, platform: platform, state: state)
    }
    return .alreadyInPreparation(existing)
  }

  let response = try await client.appStoreVersionsCreateInstance(body: .json(.init(data: .init(
    attributes: .init(
      copyright: copyright,
      platform: platform.rawValue,
      releaseType: releaseType?.rawValue,
      versionString: versionString
    ),
    relationships: .init(app: .init(data: .init(id: appID, _type: "apps"))),
    _type: "appStoreVersions"
  )))).created.body.json
  return .created(response.data)
}

/// Changes an App Store version's own fields; a nil one is left as it is. App Store Connect takes
/// both only while the version is editable (`VersionLocalizations.editableStates`).
public func updateVersion(
  versionID: String, versionString: String? = nil, copyright: String? = nil, client: ASCClient
) async throws -> Components.Schemas.AppStoreVersion {
  try await client.appStoreVersionsUpdateInstance(
    path: .init(id: versionID),
    body: .json(.init(data: .init(
      attributes: .init(copyright: copyright, versionString: versionString), id: versionID, _type: "appStoreVersions")))
  ).ok.body.json.data
}
