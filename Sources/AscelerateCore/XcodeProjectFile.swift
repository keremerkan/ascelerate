import Foundation

/// What an Xcode project's file says about its targets and languages, read from either format:
/// the old-style property list `project.pbxproj`, or the JSON `project.xcproj` Xcode 27.2 can
/// convert a project to (`xcodebuild -convert-project "Xcode Project"`). Only the project file:
/// settings from `.xcconfig` files aren't in it (`xcodebuild -showBuildSettings` resolves those).
public struct XcodeProjectFile: Sendable {
  public struct Target: Sendable, Hashable {
    /// The ID schemes name it by (`BlueprintIdentifier`); both formats keep it.
    public let id: String
    public let name: String
    /// Without Apple's `com.apple.product-type.` prefix: `application`, `app-extension`,
    /// `bundle.ui-testing`…
    public let productType: String
    /// Its Release build settings: the project's, with the target's own over them. A setting with
    /// other conditions (`[sdk=macosx*]`) keeps them in its key, as in the Release configuration of
    /// a property-list project. List values are joined with spaces.
    public let releaseSettings: [String: String]

    public var isApp: Bool { productType == "application" }
    public var isUITestBundle: Bool { productType == "bundle.ui-testing" }
  }

  public let targets: [Target]
  /// The languages the project declares, Base included (`knownRegions`, or the JSON's
  /// `localizations`: its development language, which `supported` leaves out, then the others).
  public let localizations: [String]
  /// Whether it was read from the JSON format.
  public let isJSON: Bool

  /// Reads the `.xcodeproj` at `project`: its `project.xcproj` when it has one, else its
  /// `project.pbxproj`; nil when neither can be read.
  public init?(project: URL) {
    if let data = try? Data(contentsOf: project.appending(path: "project.xcproj")), let file = Self.json(data) {
      self = file
    } else if let data = try? Data(contentsOf: project.appending(path: "project.pbxproj")), let file = Self.propertyList(data) {
      self = file
    } else {
      return nil
    }
  }

  init(targets: [Target], localizations: [String], isJSON: Bool) {
    (self.targets, self.localizations, self.isJSON) = (targets, localizations, isJSON)
  }

  public func target(id: String) -> Target? {
    targets.first { $0.id == id }
  }

  // MARK: JSON (`project.xcproj`)

  /// Xcode writes it with trailing commas, which plain JSON refuses; JSON5 reading takes them.
  /// Settings are one dictionary per target and for the project, a configuration or SDK written into
  /// the key (`CODE_SIGN_IDENTITY[config=Release][sdk=macosx*]`).
  static func json(_ data: Data) -> XcodeProjectFile? {
    guard let root = (try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed])) as? [String: Any] else {
      return nil
    }
    let projectSettings = release(root["build-settings"] as? [String: Any] ?? [:])
    let targets = (root["targets"] as? [[String: Any]] ?? []).compactMap { target -> Target? in
      guard let id = target["id"] as? String, let name = target["name"] as? String else { return nil }
      let own = release(target["build-settings"] as? [String: Any] ?? [:])
      return Target(
        id: id, name: name, productType: productType(target["product-type"] as? String),
        releaseSettings: projectSettings.merging(own) { _, own in own })
    }
    let languages = root["localizations"] as? [String: Any]
    let supported = languages?["supported"] as? [String] ?? []
    let development = (languages?["development"] as? String).map { [$0] } ?? []
    let localizations = development.filter { !supported.contains($0) } + supported
    return XcodeProjectFile(targets: targets, localizations: localizations, isJSON: true)
  }

  /// The settings that apply to Release: unconditional ones, and those for Release with that
  /// condition taken out of the key (over the unconditional ones); other configurations' left out.
  static func release(_ settings: [String: Any]) -> [String: String] {
    var plain: [String: String] = [:]
    var forRelease: [String: String] = [:]
    for (key, value) in settings {
      guard let value = text(value) else { continue }
      guard let bracket = key.firstIndex(of: "[") else {
        plain[key] = value
        continue
      }
      let conditions = key[bracket...].split(separator: "]").map { $0.dropFirst() }.filter { !$0.isEmpty }
      let configurations = conditions.filter { $0.hasPrefix("config=") }
      guard !configurations.isEmpty else {
        plain[key] = value
        continue
      }
      guard configurations.contains(where: { $0 == "config=Release" }) else { continue }
      let rest = conditions.filter { !$0.hasPrefix("config=") }.map { "[\($0)]" }.joined()
      forRelease[String(key[..<bracket]) + rest] = value
    }
    return plain.merging(forRelease) { _, release in release }
  }

  // MARK: Property list (`project.pbxproj`)

  static func propertyList(_ data: Data) -> XcodeProjectFile? {
    guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
      let objects = plist["objects"] as? [String: [String: Any]]
    else { return nil }
    func release(_ owner: [String: Any]?) -> [String: String] {
      guard let listID = owner?["buildConfigurationList"] as? String,
        let configurations = (objects[listID]?["buildConfigurations"] as? [String])?.compactMap({ objects[$0] })
      else { return [:] }
      let release = configurations.first { $0["name"] as? String == "Release" } ?? configurations.first
      return (release?["buildSettings"] as? [String: Any] ?? [:]).compactMapValues(text)
    }
    let project = (plist["rootObject"] as? String).flatMap { objects[$0] }
    let projectSettings = release(project)
    let targets = objects.compactMap { id, object -> Target? in
      guard object["isa"] as? String == "PBXNativeTarget", let name = object["name"] as? String else { return nil }
      return Target(
        id: id, name: name, productType: productType(object["productType"] as? String),
        releaseSettings: projectSettings.merging(release(object)) { _, own in own })
    }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    return XcodeProjectFile(targets: targets, localizations: project?["knownRegions"] as? [String] ?? [], isJSON: false)
  }

  // MARK: Values

  private static func productType(_ raw: String?) -> String {
    guard let raw else { return "" }
    let prefix = "com.apple.product-type."
    return raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
  }

  /// A setting's value as text: a string, or a list joined with spaces.
  private static func text(_ value: Any) -> String? {
    if let string = value as? String { return string }
    if let list = value as? [String] { return list.joined(separator: " ") }
    return nil
  }
}
