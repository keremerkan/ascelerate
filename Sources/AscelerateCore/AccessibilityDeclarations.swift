import ASCKit
import Foundation

/// An app's App Store accessibility declarations (`accessibilityDeclarations`): which accessibility
/// features it supports, one declaration per device family. A declaration is a draft until
/// published; publishing a changed one leaves the old one `REPLACED`. A device family takes one
/// draft at a time (another is refused), and a draft can only be published once the app is on the
/// App Store on that device's platform (verified live 2026-10-20).
public enum AccessibilityDeclarations {
  /// A declarable feature: its short name (`voiceover`, `larger-text`…), the API attribute and
  /// the App Store's label.
  public struct Feature: Sendable {
    public let name: String
    public let attribute: String
    public let label: String
  }

  public static let features: [Feature] = [
    Feature(name: "voiceover", attribute: "supportsVoiceover", label: "VoiceOver"),
    Feature(name: "voice-control", attribute: "supportsVoiceControl", label: "Voice Control"),
    Feature(name: "larger-text", attribute: "supportsLargerText", label: "Larger Text"),
    Feature(name: "dark-interface", attribute: "supportsDarkInterface", label: "Dark Interface"),
    Feature(
      name: "differentiate-without-color", attribute: "supportsDifferentiateWithoutColorAlone",
      label: "Differentiate Without Color Alone"),
    Feature(name: "sufficient-contrast", attribute: "supportsSufficientContrast", label: "Sufficient Contrast"),
    Feature(name: "reduced-motion", attribute: "supportsReducedMotion", label: "Reduced Motion"),
    Feature(name: "captions", attribute: "supportsCaptions", label: "Captions"),
    Feature(name: "audio-descriptions", attribute: "supportsAudioDescriptions", label: "Audio Descriptions"),
  ]

  /// The features App Store Connect asks about for a device family: Larger Text isn't asked on the
  /// Mac (its declarations store no value for it).
  public static func features(for deviceFamily: String) -> [Feature] {
    deviceFamily == "MAC" ? features.filter { $0.name != "larger-text" } : features
  }

  /// A feature's value to send: whether it's supported, or nil when it doesn't apply to the family.
  private static func value(_ name: String, supported: Set<String>, deviceFamily: String) -> Bool? {
    features(for: deviceFamily).contains { $0.name == name } ? supported.contains(name) : nil
  }

  public struct Declaration: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// Raw device family (`IPHONE`, `IPAD`, `MAC`, `APPLE_TV`, `APPLE_WATCH`, `VISION`).
    public let deviceFamily: String?
    /// `DRAFT`, `PUBLISHED` or `REPLACED`.
    public let state: String?
    /// Feature name (voiceover, larger-text, …) → supported. A feature that doesn't apply to the
    /// device family (Larger Text on the Mac) is missing.
    public let supports: [String: Bool]

    public init(id: String, deviceFamily: String?, state: String?, supports: [String: Bool]) {
      self.id = id
      self.deviceFamily = deviceFamily
      self.state = state
      self.supports = supports
    }
  }

  /// All of the app's declarations, replaced ones included.
  public static func list(appID: String, client: ASCClient) async throws -> [Declaration] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.appsAccessibilityDeclarationsGetToManyRelated(path: .init(id: appID), query: .init(limit: 200)).ok.body.json
    }.flatMap(\.data).map { declaration in
      let a = declaration.attributes
      let values: [String: Bool?] = [
        "voiceover": a?.supportsVoiceover, "voice-control": a?.supportsVoiceControl, "larger-text": a?.supportsLargerText,
        "dark-interface": a?.supportsDarkInterface, "differentiate-without-color": a?.supportsDifferentiateWithoutColorAlone,
        "sufficient-contrast": a?.supportsSufficientContrast, "reduced-motion": a?.supportsReducedMotion,
        "captions": a?.supportsCaptions, "audio-descriptions": a?.supportsAudioDescriptions,
      ]
      return Declaration(
        id: declaration.id, deviceFamily: a?.deviceFamily, state: a?.state, supports: values.compactMapValues { $0 })
    }
  }

  /// Declares a device family's support as a new draft: the named features supported, every other
  /// one that applies to the family not.
  @discardableResult
  public static func create(
    appID: String, deviceFamily: String, supported: Set<String>, client: ASCClient
  ) async throws -> Components.Schemas.AccessibilityDeclaration {
    let has = { (name: String) in value(name, supported: supported, deviceFamily: deviceFamily) }
    return try await client.accessibilityDeclarationsCreateInstance(body: .json(.init(data: .init(
      attributes: .init(
        deviceFamily: deviceFamily,
        supportsAudioDescriptions: has("audio-descriptions"), supportsCaptions: has("captions"),
        supportsDarkInterface: has("dark-interface"), supportsDifferentiateWithoutColorAlone: has("differentiate-without-color"),
        supportsLargerText: has("larger-text"), supportsReducedMotion: has("reduced-motion"),
        supportsSufficientContrast: has("sufficient-contrast"), supportsVoiceControl: has("voice-control"),
        supportsVoiceover: has("voiceover")
      ),
      relationships: .init(app: .init(data: .init(id: appID, _type: "apps"))),
      _type: "accessibilityDeclarations"
    )))).created.body.json.data
  }

  /// Sets a device family's declaration's features (the named ones supported, every other one that
  /// applies to the family not) and, with `publish`, publishes it.
  public static func update(
    id: String, deviceFamily: String, supported: Set<String>, publish: Bool, client: ASCClient
  ) async throws {
    let has = { (name: String) in value(name, supported: supported, deviceFamily: deviceFamily) }
    _ = try await client.accessibilityDeclarationsUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(
        attributes: .init(
          publish: publish ? true : nil,
          supportsAudioDescriptions: has("audio-descriptions"), supportsCaptions: has("captions"),
          supportsDarkInterface: has("dark-interface"), supportsDifferentiateWithoutColorAlone: has("differentiate-without-color"),
          supportsLargerText: has("larger-text"), supportsReducedMotion: has("reduced-motion"),
          supportsSufficientContrast: has("sufficient-contrast"), supportsVoiceControl: has("voice-control"),
          supportsVoiceover: has("voiceover")
        ),
        id: id, _type: "accessibilityDeclarations"
      )))
    ).ok
  }

  /// Deletes a draft declaration.
  public static func delete(id: String, client: ASCClient) async throws {
    _ = try await client.accessibilityDeclarationsDeleteInstance(path: .init(id: id)).noContent
  }

  /// Publishes a draft declaration as it is.
  public static func publish(id: String, client: ASCClient) async throws {
    _ = try await client.accessibilityDeclarationsUpdateInstance(
      path: .init(id: id),
      body: .json(.init(data: .init(attributes: .init(publish: true), id: id, _type: "accessibilityDeclarations")))
    ).ok
  }
}
