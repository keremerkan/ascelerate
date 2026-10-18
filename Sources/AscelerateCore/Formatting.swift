import Foundation

/// Converts a camelCase or SCREAMING_SNAKE_CASE field name to a human-readable title.
/// Examples: "whatsNew" → "What's New", "privacyPolicyURL" → "Privacy Policy URL",
///           "prepareForSubmission" → "Prepare for Submission", "READY_FOR_SALE" → "Ready for Sale"
public func formatFieldName(_ name: String) -> String {
  // Known special cases
  let overrides: [String: String] = [
    "whatsNew": "What's New",
    "privacyPolicyURL": "Privacy Policy URL",
    "privacyChoicesURL": "Privacy Choices URL",
    "marketingURL": "Marketing URL",
    "supportURL": "Support URL",
    "promotionalText": "Promotional Text",
    "macOS": "macOS",
    "iOS": "iOS",
    "tvOS": "tvOS",
    "visionOS": "visionOS",
    "CANCELED": "Cancelled",
    "iphone": "iPhone",
    "ipad": "iPad",
    "appleTv": "Apple TV",
    "vision": "Apple Vision",
    "VISION": "Apple Vision",
    "IOS": "iOS",
    "ios": "iOS",  // legacy encryption declarations report the platform in lowercase
    "MAC_OS": "macOS",
    "TV_OS": "tvOS",
    "VISION_OS": "visionOS",
  ]
  if let override = overrides[name] { return override }

  // SCREAMING_SNAKE_CASE (e.g. "PREPARE_FOR_SUBMISSION", "APP_IPHONE_67") — or a
  // single all-caps word (e.g. "MANUAL"): raw API enum values land here too
  let isAllCaps = name.count >= 2 && name.allSatisfy { $0.isUppercase || $0.isNumber || $0 == "_" }
  if name.contains("_") || isAllCaps {
    // Words whose casing isn't Title Case (raw values like DEVELOPER_ID_APPLICATION, IPAD).
    let words: [Substring: String] = [
      "ID": "ID", "IOS": "iOS", "TVOS": "tvOS", "IPAD": "iPad", "IPHONE": "iPhone", "IMESSAGE": "iMessage",
      "ICLOUD": "iCloud", "TV": "TV", "URL": "URL", "NFC": "NFC", "RSA": "RSA", "PSP": "PSP", "CPT": "CPT", "CPA": "CPA", "CPM": "CPM",
    ]
    // Short words stay lowercase unless they come first ("Waiting for Review", "In Review").
    let minorWords: Set<Substring> = ["A", "AN", "AND", "AT", "BY", "FOR", "FROM", "IN", "OF", "ON", "OR", "THE", "TO", "WITH"]
    return name.split(separator: "_").enumerated()
      .map { index, word in
        if let fixed = words[word] { return fixed }
        if index > 0 && minorWords.contains(word) { return word.lowercased() }
        return word.prefix(1).uppercased() + word.dropFirst().lowercased()
      }
      .joined(separator: " ")
  }

  // camelCase → split on uppercase boundaries
  var words: [String] = []
  var current = ""
  for char in name {
    if char.isUppercase && !current.isEmpty {
      // Check for consecutive uppercase (acronyms like "URL", "ID")
      if current.last?.isUppercase == true {
        current.append(char)
      } else {
        words.append(current)
        current = String(char)
      }
    } else if char.isLowercase && current.count > 1 && current.allSatisfy(\.isUppercase) {
      // End of acronym — split off the last uppercase as start of new word
      let acronym = String(current.dropLast())
      words.append(acronym)
      current = String(current.last!) + String(char)
    } else {
      current.append(char)
    }
  }
  if !current.isEmpty { words.append(current) }

  return words.enumerated().map { i, word in
    if word.allSatisfy(\.isUppercase) && word.count >= 2 { return word } // preserve acronyms
    return i == 0 ? word.prefix(1).uppercased() + word.dropFirst() : word.prefix(1).uppercased() + word.dropFirst()
  }.joined(separator: " ")
}

/// Formats any enum value printed via `"\($0)"` into a human-readable title.
/// Works by converting the string representation to a readable form.
public func formatState<T>(_ value: T) -> String {
  formatFieldName("\(value)")
}

/// Returns a locale code with its human-readable language name, e.g. "en-US (English (US))" or "tr (Turkish)".
public func localeName(_ code: String) -> String {
  guard let name = Locale.current.localizedString(forIdentifier: code) else {
    return code
  }
  return "\(code) (\(name))"
}

public func formatDate(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.dateStyle = .medium
  formatter.timeStyle = .short
  return formatter.string(from: date)
}

public func formatBytes(_ bytes: Int) -> String {
  if bytes < 1024 { return "\(bytes) bytes" }
  let kb = Double(bytes) / 1024
  if kb < 1024 { return String(format: "%.1f KB", kb) }
  let mb = kb / 1024
  return String(format: "%.1f MB", mb)
}

/// Maps `items` through an async `transform` with bounded concurrency, preserving input order.
/// Used to parallelize per-item API lookups (e.g. preflight price checks) that would otherwise
/// run as a sequential N+1 loop, without overwhelming the API with unbounded concurrency.
public func boundedConcurrentMap<T: Sendable, R: Sendable>(
  _ items: [T], maxConcurrent: Int = 6, _ transform: @escaping @Sendable (T) async throws -> R
) async throws -> [R] {
  try await withThrowingTaskGroup(of: (Int, R).self) { group in
    var results = [R?](repeating: nil, count: items.count)
    var next = 0
    var running = 0
    while next < items.count || running > 0 {
      while running < maxConcurrent, next < items.count {
        let index = next
        let item = items[index]
        group.addTask { (index, try await transform(item)) }
        next += 1
        running += 1
      }
      if let (index, value) = try await group.next() {
        results[index] = value
        running -= 1
      }
    }
    return results.map { $0! }
  }
}
