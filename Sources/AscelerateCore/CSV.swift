import Foundation

/// Reading CSV files people export from spreadsheets and App Store Connect.
public enum CSV {
  /// A CSV file's rows of fields: comma-separated (semicolons or tabs when the first line has
  /// more of those), fields quoted with doubled quotes inside, a byte order mark ignored.
  public static func rows(_ text: String) -> [[String]] {
    let text = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    let firstLine = text.prefix { !$0.isNewline }
    let delimiter: Character = [",", ";", "\t"].max { first, second in
      firstLine.filter { $0 == first }.count < firstLine.filter { $0 == second }.count
    } ?? ","
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    var iterator = text.makeIterator()
    var pending: Character?
    while let character = pending ?? iterator.next() {
      pending = nil
      if inQuotes {
        if character == "\"" {
          let next = iterator.next()
          if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
        } else {
          field.append(character)
        }
      } else if character == "\"" {
        inQuotes = true
      } else if character == delimiter {
        row.append(field)
        field = ""
      } else if character.isNewline {
        row.append(field)
        rows.append(row)
        row = []
        field = ""
      } else {
        field.append(character)
      }
    }
    if !field.isEmpty || !row.isEmpty {
      row.append(field)
      rows.append(row)
    }
    return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
  }
}
