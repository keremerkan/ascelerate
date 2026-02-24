import Foundation

/// When true, all interactive confirmation prompts are automatically accepted.
nonisolated(unsafe) var autoConfirm = false

/// Set by `builds upload` after a successful upload so subsequent workflow steps
/// (e.g. `await-processing`, `attach-latest-build`) can wait for this specific build.
nonisolated(unsafe) var lastUploadedBuildVersion: String?

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
/// Shows a one-time note if completions are outdated. No-op if completions were never installed.
func checkCompletionsVersion() {
  struct Once { nonisolated(unsafe) static var checked = false }
  guard !Once.checked else { return }
  Once.checked = true

  guard let shell = ProcessInfo.processInfo.environment["SHELL"] else { return }
  let home = FileManager.default.homeDirectoryForCurrentUser

  let completionPath: String
  if shell.hasSuffix("/zsh") {
    completionPath = home.appendingPathComponent(".zfunc/_asc-client").path
  } else if shell.hasSuffix("/bash") {
    completionPath = home.appendingPathComponent(".bash_completions/asc-client.bash").path
  } else {
    return
  }

  guard FileManager.default.fileExists(atPath: completionPath),
    let data = FileManager.default.contents(atPath: completionPath),
    let contents = String(data: data, encoding: .utf8)
  else { return }

  let currentVersion = ASCClient.appVersion
  let prefix = "# asc-client v"

  // Version stamp may be on line 1 (bash) or line 2 (zsh, after #compdef)
  if let range = contents.range(of: prefix),
    contents[contents.startIndex..<range.lowerBound].filter({ $0 == "\n" }).count <= 1
  {
    let afterPrefix = contents[range.upperBound...]
    let stampedVersion = String(afterPrefix.prefix(while: { $0 != "\n" }))
    if stampedVersion == currentVersion { return }
    print("\nNOTE: Shell completions are outdated (v\(stampedVersion) → v\(currentVersion)). Run 'asc-client install-completions' to update.\n")
  } else {
    print("\nNOTE: Shell completions may be outdated. Run 'asc-client install-completions' to update.\n")
  }
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
        widths[i] = max(widths[i], cell.count)
      }
    }

    let headerLine = headers.enumerated().map { i, h in
      h.padding(toLength: widths[i], withPad: " ", startingAt: 0)
    }.joined(separator: "  ")

    let separator = widths.map { String(repeating: "─", count: $0) }.joined(separator: "──")

    Swift.print(headerLine)
    Swift.print(separator)

    for row in rows {
      let line = row.prefix(columnCount).enumerated().map { i, cell in
        cell.padding(toLength: widths[i], withPad: " ", startingAt: 0)
      }.joined(separator: "  ")
      Swift.print(line)
    }
  }
}
