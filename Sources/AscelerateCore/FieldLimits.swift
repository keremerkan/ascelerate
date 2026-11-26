import Foundation

/// The most characters App Store Connect takes in its text fields.
public enum FieldLimits {
  // App Store versions and App Information
  public static let appName = 30
  public static let subtitle = 30
  public static let promotionalText = 170
  public static let description = 4000
  public static let whatsNew = 4000
  public static let keywords = 100
  /// App Review's notes, also a product's.
  public static let reviewNotes = 4000

  // In-app purchases, subscriptions and their groups, offers, in-app events
  public static let referenceName = 64
  public static let productDisplayName = 35
  public static let productDescription = 55
  /// A subscription group's custom app name.
  public static let customAppName = 30

  // In-app events
  public static let eventName = 30
  public static let eventShortDescription = 50
  public static let eventLongDescription = 120

  /// A custom product page's or product page optimization test's reference name.
  public static let pageReferenceName = 100

  // Featuring nominations
  public static let nominationName = 60
  public static let nominationDescription = 1000
  public static let nominationNotes = 500

  // TestFlight
  public static let whatToTest = 4000
  public static let betaAppDescription = 4000

  /// An asset library image's or video's name.
  public static let assetName = 255
}

extension FieldLimits {
  /// "field: N characters (at most M)" for each value over its limit, in the files' field names.
  static func overLimit(_ values: [(name: String, value: String?, limit: Int)]) -> [String] {
    values.compactMap { entry in
      guard let value = entry.value, value.count > entry.limit else { return nil }
      return "\(entry.name): \(value.count) characters (at most \(entry.limit))"
    }
  }
}

extension LocaleFields {
  /// The fields longer than App Store Connect takes, checked before anything is sent.
  public var overLimit: [String] {
    FieldLimits.overLimit([
      ("description", description, FieldLimits.description), ("whatsNew", whatsNew, FieldLimits.whatsNew),
      ("keywords", keywords, FieldLimits.keywords), ("promotionalText", promotionalText, FieldLimits.promotionalText),
    ])
  }
}

extension AppInfoLocaleFields {
  /// The fields longer than App Store Connect takes, checked before anything is sent.
  public var overLimit: [String] {
    FieldLimits.overLimit([("name", name, FieldLimits.appName), ("subtitle", subtitle, FieldLimits.subtitle)])
  }
}

/// Languages of a localization file with fields over their limits: nothing is sent.
public struct FieldsOverLimit: LocalizedError, Sendable {
  public let problems: [String: [String]]
  /// Nil when every language fits.
  public init?(_ problems: [String: [String]]) {
    let found = problems.filter { !$0.value.isEmpty }
    guard !found.isEmpty else { return nil }
    self.problems = found
  }
  public var errorDescription: String? {
    "Too long for App Store Connect, nothing was sent:\n" + problems.sorted { $0.key < $1.key }
      .map { "  \($0.key): " + $0.value.joined(separator: ", ") }.joined(separator: "\n")
  }
}

