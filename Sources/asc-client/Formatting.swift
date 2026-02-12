import Foundation

func expandPath(_ path: String) -> String {
  if path.hasPrefix("~/") {
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(String(path.dropFirst(2))).path
  }
  return path
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
