// Splits swift-openapi-generator's output into files of about 3,000 lines, as extensions of the
// same types. The compiler works one file at a time, so the generator's three giant files
// (Types+Operations, Types+Components+Schemas and Client, 35,000 to 77,000 lines each) kept one
// job busy long after the rest of the module was done. Split, ASCKit builds in parallel and with
// less memory (measured 2026-10-30, ASCKit alone: debug 64 s → 25 s, 9.7 → 6.6 GB; release
// 245 s → 165 s, 16.7 → 13.6 GB).
//
//   swift Scripts/split-generated.swift <generator output directory> <destination directory>
//
// Run by Scripts/update-asc-spec.sh. The destination directory is replaced.
import Foundation

let chunkSize = 3000

guard CommandLine.arguments.count == 3 else {
  print("usage: swift Scripts/split-generated.swift <generator output directory> <destination directory>")
  exit(2)
}
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
let fileManager = FileManager.default
if fileManager.fileExists(atPath: destination.path) {
  try fileManager.removeItem(at: destination)
}
try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

func write(_ name: String, _ text: String) throws {
  try text.write(to: destination.appendingPathComponent(name), atomically: true, encoding: .utf8)
}

/// The import block (everything before the first declaration or doc comment at column 0) and the rest.
func headerAndBody(_ text: String) -> (header: String, body: [Substring]) {
  let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
  let starts = ["///", "extension ", "enum ", "struct ", "public enum ", "public struct ", "public protocol ",
                "public func ", "public typealias ", "public extension "]
  let start = lines.firstIndex { line in starts.contains { line.hasPrefix($0) } } ?? lines.endIndex
  return (lines[..<start].joined(separator: "\n"), Array(lines[start...]))
}

/// A container's body without the closing lines in `closers` and blank lines at its end.
func trimmed(_ lines: ArraySlice<Substring>, closers: Set<Substring>) -> ArraySlice<Substring> {
  var lines = lines
  while let last = lines.last, last.isEmpty || closers.contains(last) { lines.removeLast() }
  return lines
}

/// The members at `indent` spaces of a container's body, each with its doc comments.
func members(_ lines: ArraySlice<Substring>, indent: Int) -> [[Substring]] {
  let closer = String(repeating: " ", count: indent) + "}"
  var result: [[Substring]] = [], current: [Substring] = []
  for line in lines {
    current.append(line)
    if line.hasPrefix(closer) {
      result.append(current)
      current = []
    }
  }
  precondition(current.allSatisfy { $0.allSatisfy(\.isWhitespace) }, "Unexpected lines after the last member: \(current.prefix(5))")
  return result
}

/// Writes `groups` to `<prefix>+NN.swift` files of about `chunkSize` lines, each in `opener … }`.
func writeChunks(_ prefix: String, header: String, opener: String, _ groups: [[Substring]], dedent: Int = 0) throws -> Int {
  let padding = String(repeating: " ", count: dedent)
  var count = 0, buffer: [Substring] = []
  func flush() throws {
    guard !buffer.isEmpty else { return }
    count += 1
    let body = buffer.map { $0.hasPrefix(padding) ? $0.dropFirst(dedent) : $0 }.joined(separator: "\n")
    try write("\(prefix)+\(count < 10 ? "0" : "")\(count).swift", "\(header)\n\(opener)\n\(body)\n}\n")
    buffer = []
  }
  for group in groups {
    buffer += group
    if buffer.count >= chunkSize { try flush() }
  }
  try flush()
  return count
}

func index(of prefix: String, in lines: [Substring]) -> Int {
  guard let index = lines.firstIndex(where: { $0.hasPrefix(prefix) }) else {
    print("Not found in the generator's output: \(prefix)")
    exit(1)
  }
  return index
}

for name in try fileManager.contentsOfDirectory(atPath: source.path).sorted() where name.hasSuffix(".swift") {
  let text = try String(contentsOf: source.appendingPathComponent(name), encoding: .utf8)
  let (header, body) = headerAndBody(text)
  switch name {
  case "Types+Operations.swift":
    // public enum Operations { <operations at 4 spaces> }
    let start = index(of: "public enum Operations {", in: body)
    let operations = members(trimmed(body[(start + 1)...], closers: ["}"]), indent: 4)
    try write(name, "\(header)\n\(body[..<start].joined(separator: "\n"))\npublic enum Operations {}\n")
    let files = try writeChunks("Operations", header: header, opener: "extension Operations {", operations)
    print("\(name): \(operations.count) operations in \(files) files")
  case "Types+Components+Schemas.swift":
    // extension Components { public enum Schemas { <schemas at 8 spaces> } }
    let start = index(of: "    public enum Schemas {", in: body)
    let schemas = members(trimmed(body[(start + 1)...], closers: ["}", "    }"]), indent: 8)
    try write(name, "\(header)\nextension Components {\n\(body[1..<start].joined(separator: "\n"))\n    public enum Schemas {}\n}\n")
    let files = try writeChunks("Schemas", header: header, opener: "extension Components.Schemas {", schemas, dedent: 4)
    print("\(name): \(schemas.count) schemas in \(files) files")
  case "Client.swift":
    // public struct Client: APIProtocol { <stored properties, init, methods at 4 spaces> }
    let start = index(of: "public struct Client: APIProtocol {", in: body)
    let groups = members(trimmed(body[(start + 1)...], closers: ["}"]), indent: 4)
    let isMethod = { (group: [Substring]) in group.contains { $0.hasPrefix("    public func ") } }
    // The stored properties and the init stay in the struct. The methods move to extensions in
    // other files, which can't see `private` members.
    let kept = groups.filter { !isMethod($0) }.joined().map {
      $0.replacingOccurrences(of: "    private let client:", with: "    let client:")
        .replacingOccurrences(of: "    private var converter:", with: "    var converter:")
    }
    let methods = groups.filter(isMethod)
    try write(name, "\(header)\n\(body[...start].joined(separator: "\n"))\n\(kept.joined(separator: "\n"))\n}\n")
    let files = try writeChunks("Client", header: header, opener: "extension Client {", methods)
    print("\(name): \(methods.count) methods in \(files) files")
  default:
    try write(name, text)
  }
}
