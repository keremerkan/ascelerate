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
