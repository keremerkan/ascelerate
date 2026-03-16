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

/// Resolves a folder path from an optional argument. If nil, lists subdirectories and zip
/// files in the current directory and lets the user pick one or type a path manually.
/// Zip files are extracted to a temporary directory automatically.
func resolveFolder(_ folder: String?, prompt: String) throws -> String {
  if let f = folder {
    let path = expandPath(f)
    if path.hasSuffix(".zip") {
      guard FileManager.default.fileExists(atPath: path) else {
        throw ValidationError("File not found at '\(path)'.")
      }
      return try extractZipToTemp(path)
    }
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
      throw ValidationError("Folder not found at '\(path)'.")
    }
    return path
  }

  // List subdirectories and zip files in the current directory
  let cwd = FileManager.default.currentDirectoryPath
  let entries = (try? FileManager.default.contentsOfDirectory(atPath: cwd))?
    .filter { !$0.hasPrefix(".") }
    .sorted() ?? []

  var candidates: [(name: String, isZip: Bool)] = []
  for entry in entries {
    let path = (cwd as NSString).appendingPathComponent(entry)
    if entry.hasSuffix(".zip") {
      candidates.append((entry, true))
    } else {
      var isDir: ObjCBool = false
      if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
        candidates.append((entry, false))
      }
    }
  }

  if !candidates.isEmpty {
    print("\(prompt):")
    for (i, c) in candidates.enumerated() {
      let suffix = c.isZip ? " (zip)" : ""
      print("  [\(i + 1)] \(c.name)\(suffix)")
    }
    let manualOption = candidates.count + 1
    print("  [\(manualOption)] Enter path manually")
    print()
    print("Select (1-\(manualOption)): ", terminator: "")

    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
          let choice = Int(input),
          choice >= 1, choice <= manualOption else {
      throw ValidationError("Invalid selection.")
    }

    if choice <= candidates.count {
      let selected = candidates[choice - 1]
      let fullPath = (cwd as NSString).appendingPathComponent(selected.name)
      return selected.isZip ? try extractZipToTemp(fullPath) : fullPath
    }
  }

  // Manual path entry
  let path = expandPath(promptText("Path to folder or zip: "))
  if path.hasSuffix(".zip") {
    guard FileManager.default.fileExists(atPath: path) else {
      throw ValidationError("File not found at '\(path)'.")
    }
    return try extractZipToTemp(path)
  }
  var isDir: ObjCBool = false
  guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
    throw ValidationError("Folder not found at '\(path)'.")
  }
  return path
}

/// Extracts a zip file to a temporary directory and returns the path.
/// If the zip contains a single root directory, returns that directory instead.
func extractZipToTemp(_ zipPath: String) throws -> String {
  let tempDir = NSTemporaryDirectory() + "asc-media-\(UUID().uuidString)"
  try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
  process.arguments = ["-q", zipPath, "-d", tempDir]
  try process.run()
  process.waitUntilExit()

  guard process.terminationStatus == 0 else {
    throw ValidationError("Failed to extract zip file '\(zipPath)'.")
  }

  // If the zip has a single root directory, use that as the media folder
  let contents = try FileManager.default.contentsOfDirectory(atPath: tempDir)
    .filter { !$0.hasPrefix(".") && $0 != "__MACOSX" }
  if contents.count == 1 {
    let inner = (tempDir as NSString).appendingPathComponent(contents[0])
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: inner, isDirectory: &isDir), isDir.boolValue {
      return inner
    }
  }

  return tempDir
}

/// Resolves a file path from an optional argument. If nil, lists files matching the given
/// extension in the current directory and lets the user pick one or type a path manually.
func resolveFile(_ file: String?, extension ext: String, prompt: String) throws -> String {
  if let f = file {
    let path = expandPath(f)
    guard FileManager.default.fileExists(atPath: path) else {
      throw ValidationError("File not found at '\(path)'.")
    }
    return path
  }

  // List matching files in the current directory
  let cwd = FileManager.default.currentDirectoryPath
  let candidates = (try? FileManager.default.contentsOfDirectory(atPath: cwd))?
    .filter { $0.hasSuffix(".\(ext)") }
    .sorted() ?? []

  if !candidates.isEmpty {
    print("\(prompt):")
    for (i, name) in candidates.enumerated() {
      print("  [\(i + 1)] \(name)")
    }
    let manualOption = candidates.count + 1
    print("  [\(manualOption)] Enter path manually")
    print()
    print("Select (1-\(manualOption)): ", terminator: "")

    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
          let choice = Int(input),
          choice >= 1, choice <= manualOption else {
      throw ValidationError("Invalid selection.")
    }

    if choice <= candidates.count {
      return (cwd as NSString).appendingPathComponent(candidates[choice - 1])
    }
  }

  // Manual path entry
  let path = expandPath(promptText("Path to file: "))
  guard FileManager.default.fileExists(atPath: path) else {
    throw ValidationError("File not found at '\(path)'.")
  }
  return path
}

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
/// Returns a version detail string like " (v0.5.0 → v0.6.1)" if completions are outdated, nil if current.
func completionsVersionDetail() -> String? {
  guard let shell = ProcessInfo.processInfo.environment["SHELL"] else { return nil }
  let home = FileManager.default.homeDirectoryForCurrentUser

  let completionPath: String
  if shell.hasSuffix("/zsh") {
    completionPath = home.appendingPathComponent(".zfunc/_asc").path
  } else if shell.hasSuffix("/bash") {
    completionPath = home.appendingPathComponent(".bash_completions/asc.bash").path
  } else {
    return nil
  }

  guard FileManager.default.fileExists(atPath: completionPath),
    let data = FileManager.default.contents(atPath: completionPath),
    let contents = String(data: data, encoding: .utf8)
  else { return nil }

  let currentVersion = ASC.appVersion
  let prefix = "# asc v"

  // Version stamp may be on line 1 (bash) or line 2 (zsh, after #compdef)
  if let range = contents.range(of: prefix),
    contents[contents.startIndex..<range.lowerBound].filter({ $0 == "\n" }).count <= 1
  {
    let afterPrefix = contents[range.upperBound...]
    let stampedVersion = String(afterPrefix.prefix(while: { $0 != "\n" }))
    if stampedVersion == currentVersion { return nil }
    return " (v\(stampedVersion) → v\(currentVersion))"
  }
  return ""  // installed but no stamp — outdated
}

/// Returns a version detail string like " (v0.5.0 → v0.6.1)" if skill is outdated, nil if current or not installed.
func skillVersionDetail() -> String? {
  let path = InstallSkillCommand.skillPath
  guard FileManager.default.fileExists(atPath: path),
        let data = FileManager.default.contents(atPath: path),
        let contents = String(data: data, encoding: .utf8)
  else { return nil }

  let prefix = "<!-- asc v"
  guard let range = contents.range(of: prefix) else { return nil }
  let afterPrefix = contents[range.upperBound...]
  guard let endRange = afterPrefix.range(of: " -->") else { return nil }
  let stampedVersion = String(afterPrefix[..<endRange.lowerBound])

  let currentVersion = ASC.appVersion
  if stampedVersion == currentVersion { return nil }
  return " (v\(stampedVersion) → v\(currentVersion))"
}

// MARK: - Legacy Migration (asc-client → asc)

/// Migrates configuration, completions, and skill from legacy `asc-client` paths to `asc`.
/// Runs once per process. Silently skips if nothing to migrate.
func migrateFromLegacyName() {
  struct Once { nonisolated(unsafe) static var migrated = false }
  guard !Once.migrated else { return }
  Once.migrated = true

  let fm = FileManager.default
  let home = fm.homeDirectoryForCurrentUser

  // 1. Migrate config directory: ~/.asc-client/ → ~/.asc/
  let oldConfigDir = home.appendingPathComponent(".asc-client")
  let newConfigDir = home.appendingPathComponent(".asc")
  if fm.fileExists(atPath: oldConfigDir.path), !fm.fileExists(atPath: newConfigDir.path) {
    do {
      try fm.moveItem(at: oldConfigDir, to: newConfigDir)
      print("Migrated configuration from ~/.asc-client/ to ~/.asc/")
    } catch {
      print("Warning: could not migrate ~/.asc-client/ to ~/.asc/: \(error.localizedDescription)")
    }
  }

  // Update privateKeyPath in config.json if it still references the old directory
  let configFile = newConfigDir.appendingPathComponent("config.json")
  if let data = fm.contents(atPath: configFile.path),
     var json = String(data: data, encoding: .utf8),
     json.contains(".asc-client/")
  {
    json = json.replacingOccurrences(of: ".asc-client/", with: ".asc/")
    try? json.write(to: configFile, atomically: true, encoding: .utf8)
  }

  // 2. Remove old completion files (user needs to run install-completions)
  var completionsMigrated = false
  let oldZshCompletion = home.appendingPathComponent(".zfunc/_asc-client")
  if fm.fileExists(atPath: oldZshCompletion.path) {
    try? fm.removeItem(at: oldZshCompletion)
    completionsMigrated = true
  }
  let oldBashCompletion = home.appendingPathComponent(".bash_completions/asc-client.bash")
  if fm.fileExists(atPath: oldBashCompletion.path) {
    try? fm.removeItem(at: oldBashCompletion)
    completionsMigrated = true
  }
  if completionsMigrated {
    print("Removed old asc-client shell completions. Run 'asc install-completions' to reinstall.")
  }

  // 3. Remove old skill directory
  let oldSkillDir = home.appendingPathComponent(".claude/skills/asc-client")
  if fm.fileExists(atPath: oldSkillDir.path) {
    try? fm.removeItem(at: oldSkillDir)
    print("Removed old asc-client skill. Run 'asc install-skill' to reinstall.")
  }
}

/// Check for outdated completions and skill, print NOTE for non-interactive contexts.
func checkForUpdates() {
  struct Once { nonisolated(unsafe) static var checked = false }
  guard !Once.checked else { return }
  Once.checked = true

  var notes: [String] = []
  if let detail = completionsVersionDetail() {
    notes.append("Shell completions are outdated\(detail). Run 'asc install-completions' to update.")
  }
  if let detail = skillVersionDetail() {
    notes.append("Claude Code skill is outdated\(detail). Run 'asc install-skill' to update.")
  }
  if !notes.isEmpty {
    print("NOTE: " + notes.joined(separator: "\n      ") + "\n")
  }
}

/// Check for outdated completions and skill, interactively offer to update.
func checkForUpdatesInteractively() async -> Bool {
  struct Once { nonisolated(unsafe) static var checked = false }
  guard !Once.checked else { return false }
  Once.checked = true

  let completions = completionsVersionDetail()
  let skill = skillVersionDetail()

  guard completions != nil || skill != nil else { return false }

  // Build prompt
  var items: [String] = []
  if let detail = completions { items.append("shell completions\(detail)") }
  if let detail = skill { items.append("Claude Code skill\(detail)") }

  let label = items.joined(separator: " and ")
  print("\(label.prefix(1).uppercased())\(label.dropFirst()) outdated. Update now? [Y/n] ", terminator: "")
  fflush(stdout)

  let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
  guard answer.isEmpty || answer == "y" || answer == "yes" else { return true }

  if completions != nil {
    do {
      let command = try InstallCompletionsCommand.parseAsRoot([]) as! InstallCompletionsCommand
      try command.run()
    } catch {
      print("Failed to update completions: \(error)")
    }
  }

  if skill != nil {
    do {
      let command = try InstallSkillCommand.parseAsRoot([]) as! InstallSkillCommand
      try await command.run()
    } catch {
      print("Failed to update skill: \(error)")
    }
  }

  return true
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
    "CANCELED": "Cancelled",
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

// MARK: - Shared Locale Fields

/// Shared JSON schema for IAP and subscription localizations (name + description).
struct ProductLocaleFields: Codable {
  var name: String?
  var description: String?
}

/// JSON schema for subscription group localizations (name + customAppName).
struct GroupLocaleFields: Codable {
  var name: String?
  var customAppName: String?
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
