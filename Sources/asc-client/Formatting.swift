import ArgumentParser
import Foundation

// MARK: - ANSI Colors

private let isTerminal = isatty(STDOUT_FILENO) != 0
private let isStderrTerminal = isatty(STDERR_FILENO) != 0

func red(_ text: String) -> String { isTerminal ? "\u{1B}[31m\(text)\u{1B}[0m" : text }
func green(_ text: String) -> String { isTerminal ? "\u{1B}[32m\(text)\u{1B}[0m" : text }
func yellow(_ text: String) -> String { isTerminal ? "\u{1B}[38;5;208m\(text)\u{1B}[0m" : text }
func bold(_ text: String) -> String { isTerminal ? "\u{1B}[1m\(text)\u{1B}[0m" : text }
func stderrRed(_ text: String) -> String { isStderrTerminal ? "\u{1B}[31m\(text)\u{1B}[0m" : text }

/// When true, all interactive confirmation prompts are automatically accepted.
nonisolated(unsafe) var autoConfirm = false

/// Set by `builds upload` after a successful upload so subsequent workflow steps
/// (e.g. `await-processing`, `attach-latest-build`) can wait for this specific build.
nonisolated(unsafe) var lastUploadedBuildVersion: String?

/// Prints a [y/N] prompt and returns true if the user (or --yes flag) confirms.
/// Prompts for non-empty text input; retries on empty.
func promptText(_ message: String) -> String {
  print(message, terminator: "")
  guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
        !line.isEmpty else {
    print("Value cannot be empty. Try again.")
    return promptText(message)
  }
  return line
}

/// Prints a [y/N] prompt and returns true if the user (or --yes flag) confirms.
func confirm(_ prompt: String) -> Bool {
  print(prompt, terminator: "")
  if autoConfirm {
    print("y (auto)")
    return true
  }
  guard let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
    answer == "y" || answer == "yes"
  else {
    return false
  }
  return true
}

/// Cleans up a path from interactive input (e.g. drag-drop into Terminal).
/// Strips surrounding quotes and removes backslash escapes.
func sanitizePath(_ path: String) -> String {
  var result = path.trimmingCharacters(in: .whitespacesAndNewlines)

  // Strip surrounding quotes
  if (result.hasPrefix("'") && result.hasSuffix("'"))
    || (result.hasPrefix("\"") && result.hasSuffix("\""))
  {
    result = String(result.dropFirst().dropLast())
  }

  // Remove backslash escapes (e.g. "\ " -> " ", "\~" -> "~")
  result = result.replacingOccurrences(of: "\\", with: "")

  return result
}

func expandPath(_ path: String) -> String {
  let cleaned = sanitizePath(path)
  if cleaned.hasPrefix("~/") {
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(String(cleaned.dropFirst(2))).path
  }
  return cleaned
}

/// Returns a locale code with its human-readable language name, e.g. "en-US (English (US))" or "tr (Turkish)".
func localeName(_ code: String) -> String {
  guard let name = Locale.current.localizedString(forIdentifier: code) else {
    return code
  }
  return "\(code) (\(name))"
}

func formatBytes(_ bytes: Int) -> String {
  if bytes < 1024 { return "\(bytes) bytes" }
  let kb = Double(bytes) / 1024
  if kb < 1024 { return String(format: "%.1f KB", kb) }
  let mb = kb / 1024
  return String(format: "%.1f MB", mb)
}

func formatDate(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.dateStyle = .medium
  formatter.timeStyle = .short
  return formatter.string(from: date)
}

/// Checks if a path exists. If so, warns and prompts for a new name (pre-filled with the current name).
/// Returns the confirmed path to use.
func confirmOutputPath(_ path: String, isDirectory: Bool) -> String {
  var current = path
  let fm = FileManager.default

  while true {
    var isDir: ObjCBool = false
    let exists = fm.fileExists(atPath: expandPath(current), isDirectory: &isDir)

    if !exists { return current }

    if autoConfirm {
      let kind = isDir.boolValue ? "Folder" : "File"
      print("\(kind) '\(current)' already exists. Overwriting. (auto)")
      return current
    }

    let kind = isDir.boolValue ? "Folder" : "File"
    print("\(kind) '\(current)' already exists. Press Enter to overwrite or type a new name:")
    print("> ", terminator: "")
    fflush(stdout)

    guard let line = readLine() else { return current }
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return current }
    current = trimmed
  }
}

/// Checks whether the installed shell completion script matches the current version.
/// When `interactive` is true (bare invocation), offers to run install-completions automatically.
/// Otherwise shows a one-time warning. No-op if completions were never installed.
/// Returns true if the user was prompted (interactive mode only).
@discardableResult
func checkCompletionsVersion(interactive: Bool = false) -> Bool {
  struct Once { nonisolated(unsafe) static var checked = false }
  guard !Once.checked else { return false }
  Once.checked = true

  guard let shell = ProcessInfo.processInfo.environment["SHELL"] else { return false }
  let home = FileManager.default.homeDirectoryForCurrentUser

  let completionPath: String
  if shell.hasSuffix("/zsh") {
    completionPath = home.appendingPathComponent(".zfunc/_asc-client").path
  } else if shell.hasSuffix("/bash") {
    completionPath = home.appendingPathComponent(".bash_completions/asc-client.bash").path
  } else {
    return false
  }

  guard FileManager.default.fileExists(atPath: completionPath),
    let data = FileManager.default.contents(atPath: completionPath),
    let contents = String(data: data, encoding: .utf8)
  else { return false }

  let currentVersion = ASCClient.appVersion
  let prefix = "# asc-client v"

  // Version stamp may be on line 1 (bash) or line 2 (zsh, after #compdef)
  var isOutdated = false
  var detail = ""
  if let range = contents.range(of: prefix),
    contents[contents.startIndex..<range.lowerBound].filter({ $0 == "\n" }).count <= 1
  {
    let afterPrefix = contents[range.upperBound...]
    let stampedVersion = String(afterPrefix.prefix(while: { $0 != "\n" }))
    if stampedVersion == currentVersion { return false }
    isOutdated = true
    detail = " (v\(stampedVersion) → v\(currentVersion))"
  } else {
    isOutdated = true
  }

  guard isOutdated else { return false }

  if interactive {
    print("Shell completions are outdated\(detail). Update now? [Y/n] ", terminator: "")
    fflush(stdout)
    let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    if answer.isEmpty || answer == "y" || answer == "yes" {
      do {
        let command = try InstallCompletionsCommand.parseAsRoot([]) as! InstallCompletionsCommand
        try command.run()
      } catch {
        print("Failed to update completions: \(error)")
      }
    }
    return true
  } else {
    print("\nNOTE: Shell completions are outdated\(detail). Run 'asc-client install-completions' to update.\n")
    return false
  }
}

/// Prints a numbered list and reads a single selection.
func promptSelection<T>(
  _ title: String,
  items: [T],
  display: (T) -> String,
  prompt: String? = nil
) throws -> T {
  guard !items.isEmpty else {
    throw ValidationError("No items to select from.")
  }
  print("\(title):")
  for (i, item) in items.enumerated() {
    print("  [\(i + 1)] \(display(item))")
  }
  print()
  let label = prompt ?? "Select"
  print("\(label) (1-\(items.count)): ", terminator: "")
  guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
        let choice = Int(input),
        choice >= 1, choice <= items.count else {
    throw ValidationError("Invalid selection.")
  }
  return items[choice - 1]
}

/// Prints a numbered list and reads one or more selections (comma-separated or 'all').
/// When `defaultAll` is true, empty input selects all items.
func promptMultiSelection<T>(
  _ title: String,
  items: [T],
  display: (T) -> String,
  prompt: String? = nil,
  defaultAll: Bool = false
) throws -> [T] {
  guard !items.isEmpty else {
    throw ValidationError("No items to select from.")
  }
  print("\(title):")
  for (i, item) in items.enumerated() {
    print("  [\(i + 1)] \(display(item))")
  }
  print()
  let label = prompt ?? "Select"
  let defaultHint = defaultAll ? " [all]" : ""
  print("\(label) (comma-separated numbers, or 'all')\(defaultHint): ", terminator: "")
  let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

  if input.isEmpty && defaultAll {
    return items
  }
  guard !input.isEmpty else {
    throw ValidationError("No selection made.")
  }
  if input.lowercased() == "all" {
    return items
  }

  let parts = input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
  var selected: [T] = []
  for part in parts {
    guard let num = Int(part), num >= 1, num <= items.count else {
      throw ValidationError("Invalid selection '\(part)'. Enter numbers between 1 and \(items.count).")
    }
    selected.append(items[num - 1])
  }
  return selected
}

/// Parses and validates a string value against a CaseIterable enum.
/// Returns the matched enum case, or throws with a list of valid values.
func parseEnum<T: RawRepresentable & CaseIterable>(
  _ value: String,
  name: String
) throws -> T where T.RawValue == String {
  guard let val = T(rawValue: value.uppercased()) else {
    let valid = T.allCases.map(\.rawValue).joined(separator: ", ")
    throw ValidationError("Invalid \(name) '\(value)'. Valid values: \(valid)")
  }
  return val
}

/// Parses and validates an optional filter value against a CaseIterable enum.
/// Returns nil when input is nil, or a single-element array on success.
func parseFilter<T: RawRepresentable & CaseIterable>(
  _ value: String?,
  name: String
) throws -> [T]? where T.RawValue == String {
  guard let value else { return nil }
  return [try parseEnum(value, name: name)]
}

/// Collects all items from paginated API responses into a single sorted array.
/// Throws if no items are found.
func fetchAll<S: AsyncSequence, Item>(
  _ pages: S,
  data: (S.Element) -> [Item],
  emptyMessage: String,
  sort: ((Item, Item) -> Bool)? = nil
) async throws -> [Item] {
  var result: [Item] = []
  for try await page in pages {
    result.append(contentsOf: data(page))
  }
  guard !result.isEmpty else {
    throw ValidationError(emptyMessage)
  }
  if let sort {
    result.sort(by: sort)
  }
  return result
}

/// Converts a camelCase or SCREAMING_SNAKE_CASE field name to a human-readable title.
/// Examples: "whatsNew" → "What's New", "privacyPolicyURL" → "Privacy Policy URL",
///           "prepareForSubmission" → "Prepare for Submission", "READY_FOR_SALE" → "Ready for Sale"
func formatFieldName(_ name: String) -> String {
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
  ]
  if let override = overrides[name] { return override }

  // SCREAMING_SNAKE_CASE (e.g. "PREPARE_FOR_SUBMISSION", "APP_IPHONE_67")
  if name.contains("_") {
    return name.split(separator: "_")
      .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
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
func formatState<T>(_ value: T) -> String {
  formatFieldName("\(value)")
}

/// Returns the visible length of a string, stripping ANSI escape sequences.
private func visibleLength(_ str: String) -> Int {
  str.replacingOccurrences(
    of: "\u{1B}\\[[0-9;]*m",
    with: "",
    options: .regularExpression
  ).count
}

/// Pads a string to a target visible width, accounting for ANSI escape sequences.
private func padToVisible(_ str: String, width: Int) -> String {
  let visible = visibleLength(str)
  if visible >= width { return str }
  return str + String(repeating: " ", count: width - visible)
}

enum Table {
  static func print(headers: [String], rows: [[String]]) {
    guard !rows.isEmpty else {
      Swift.print("No results.")
      return
    }

    let columnCount = headers.count
    var widths = headers.map(\.count)

    for row in rows {
      for (i, cell) in row.prefix(columnCount).enumerated() {
        widths[i] = max(widths[i], visibleLength(cell))
      }
    }

    let headerLine = headers.enumerated().map { i, h in
      h.padding(toLength: widths[i], withPad: " ", startingAt: 0)
    }.joined(separator: "  ")

    let separator = widths.map { String(repeating: "─", count: $0) }.joined(separator: "──")

    Swift.print(headerLine)
    Swift.print(separator)

    for row in rows {
      if row.allSatisfy({ $0.isEmpty }) {
        Swift.print()
        continue
      }
      let line = row.prefix(columnCount).enumerated().map { i, cell in
        padToVisible(cell, width: widths[i])
      }.joined(separator: "  ")
      Swift.print(line)
    }
  }
}
