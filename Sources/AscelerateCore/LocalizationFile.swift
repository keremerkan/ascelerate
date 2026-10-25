import Foundation

/// A localization file, the format of the `localizations export`/`import` commands: one object per
/// locale code, `{"en-US": {"name": "My App", "subtitle": "…"}}`. Only the fields present in a file
/// change on import; a missing field is left as it is.
public enum LocalizationFile {
  public enum FileError: LocalizedError {
    case unreadable(String)
    case empty

    public var errorDescription: String? {
      switch self {
        case .unreadable(let detail): "This isn't a localization file: \(detail)"
        case .empty: "The localization file has no languages."
      }
    }
  }

  /// The file's JSON, pretty-printed with sorted keys, as the export commands write it.
  public static func encode<Fields: Encodable>(_ file: [String: Fields]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(file)
  }

  /// Reads a file. Unknown fields are ignored, as the import commands do.
  public static func decode<Fields: Decodable>(_ data: Data, as type: Fields.Type = Fields.self) throws -> [String: Fields] {
    let file: [String: Fields]
    do {
      file = try JSONDecoder().decode([String: Fields].self, from: data)
    } catch let error as DecodingError {
      throw FileError.unreadable(describe(error))
    }
    guard !file.isEmpty else { throw FileError.empty }
    return file
  }

  private static func describe(_ error: DecodingError) -> String {
    switch error {
      case .typeMismatch(_, let context), .valueNotFound(_, let context):
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
      case .keyNotFound(let key, _):
        return "missing \(key.stringValue)"
      case .dataCorrupted(let context):
        return context.underlyingError.map { "\($0.localizedDescription)" } ?? context.debugDescription
      @unknown default:
        return "\(error)"
    }
  }
}

/// The App Information text of one locale, as `apps app-info export`/`import` write and read it.
/// A nil field is left as it is.
public struct AppInfoLocaleFields: Codable, Equatable, Sendable {
  public var name: String?
  public var subtitle: String?
  public var privacyPolicyURL: String?
  public var privacyChoicesURL: String?

  public init(name: String? = nil, subtitle: String? = nil, privacyPolicyURL: String? = nil, privacyChoicesURL: String? = nil) {
    self.name = name
    self.subtitle = subtitle
    self.privacyPolicyURL = privacyPolicyURL
    self.privacyChoicesURL = privacyChoicesURL
  }
}

/// A build's What to Test in one locale, as `testflight whats-new export`/`import` write and read
/// it. A nil field is left as it is.
public struct WhatsNewFields: Codable, Equatable, Sendable {
  public var whatsNew: String?

  public init(whatsNew: String? = nil) {
    self.whatsNew = whatsNew
  }
}

/// An app's Test Information in one locale, as `testflight app-info export`/`import` write and
/// read it. A nil field is left as it is.
public struct BetaAppLocaleFields: Codable, Equatable, Sendable {
  public var description: String?
  public var feedbackEmail: String?
  public var marketingURL: String?
  public var privacyPolicyURL: String?
  public var tvOsPrivacyPolicy: String?

  public init(
    description: String? = nil, feedbackEmail: String? = nil, marketingURL: String? = nil,
    privacyPolicyURL: String? = nil, tvOsPrivacyPolicy: String? = nil
  ) {
    self.description = description
    self.feedbackEmail = feedbackEmail
    self.marketingURL = marketingURL
    self.privacyPolicyURL = privacyPolicyURL
    self.tvOsPrivacyPolicy = tvOsPrivacyPolicy
  }
}

/// An in-app purchase's or subscription's language, as `iap`/`sub localizations export`/`import`
/// write and read it. A nil field is left as it is.
public struct ProductLocaleFields: Codable, Equatable, Sendable {
  public var name: String?
  public var description: String?

  public init(name: String? = nil, description: String? = nil) {
    self.name = name
    self.description = description
  }
}

/// A subscription group's language, as `sub group-localizations export`/`import` write and read
/// it. A nil field is left as it is.
public struct GroupLocaleFields: Codable, Equatable, Sendable {
  public var name: String?
  public var customAppName: String?

  public init(name: String? = nil, customAppName: String? = nil) {
    self.name = name
    self.customAppName = customAppName
  }
}

/// An in-app event's language, as `events localizations export`/`import` write and read it. A nil
/// field is left as it is.
public struct EventLocaleFields: Codable, Equatable, Sendable {
  public var name: String?
  public var shortDescription: String?
  public var longDescription: String?

  public init(name: String? = nil, shortDescription: String? = nil, longDescription: String? = nil) {
    self.name = name
    self.shortDescription = shortDescription
    self.longDescription = longDescription
  }
}

/// A custom product page's language, as `product-pages localizations export`/`import` write and
/// read it. A nil field is left as it is.
public struct ProductPageLocaleFields: Codable, Equatable, Sendable {
  public var promotionalText: String?

  public init(promotionalText: String? = nil) {
    self.promotionalText = promotionalText
  }
}
