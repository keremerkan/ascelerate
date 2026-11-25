import Foundation

/// A line `splitArguments` can't split: a quote left open.
public struct UnterminatedQuote: LocalizedError, Equatable, Sendable {
  public let line: String
  public var errorDescription: String? { "Unterminated quote in: \(line)" }
}

/// Splits a line into arguments as a shell would for plain words and quotes: any whitespace
/// separates them, single and double quotes group, and a backslash before a quote, a backslash or
/// whitespace takes that character as it is (`"the \"great\" one"`); any other backslash stays.
/// Quoted empty strings (`--body ""`) are kept as empty arguments, and an unterminated quote
/// throws instead of gluing the rest of the line.
public func splitArguments(_ line: String) throws(UnterminatedQuote) -> [String] {
  var result: [String] = []
  var current = ""
  var currentWasQuoted = false
  var inQuote: Character?
  var escaping = false

  func flush() {
    if !current.isEmpty || currentWasQuoted { result.append(current) }
    current = ""
    currentWasQuoted = false
  }

  for char in line {
    if escaping {
      escaping = false
      if char == "\"" || char == "'" || char == "\\" || (inQuote == nil && char.isWhitespace) {
        current.append(char)
      } else {
        current.append("\\")
        current.append(char)
      }
    } else if char == "\\" {
      escaping = true
    } else if let quote = inQuote {
      if char == quote { inQuote = nil } else { current.append(char) }
    } else if char == "'" || char == "\"" {
      inQuote = char
      currentWasQuoted = true
    } else if char.isWhitespace {
      flush()
    } else {
      current.append(char)
    }
  }
  if escaping { current.append("\\") }

  if inQuote != nil { throw UnterminatedQuote(line: line) }
  flush()
  return result
}
