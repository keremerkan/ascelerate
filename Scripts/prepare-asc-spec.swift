// Prepares Apple's App Store Connect OpenAPI spec for swift-openapi-generator: writes it to
// Sources/ASCKit/openapi.json and regenerates the nameOverrides section of
// Sources/ASCKit/openapi-generator-config.yaml (the rest of that file is left as is).
//
//   swift Scripts/prepare-asc-spec.swift ~/Downloads/openapi.oas.json
//
// Download the spec from https://developer.apple.com/documentation/appstoreconnectapi (OpenAPI
// specification link). Changes made to it:
// - String enums inside components/schemas become plain strings. The generator's enums are
//   closed, so a value Apple's spec does not list (it has happened: placement state ACTIVE in
//   4.5.1) would fail decoding of the whole response. Enums in query parameters stay typed:
//   they only shape requests. Empty parameter enums (no cases, which wouldn't compile) are dropped.
// - Bracketed parameter names and descending sort values get readable Swift names
//   (`filter[bundleId]` → `filterBundleId`, `-uploadedDate` → `minusUploadedDate`) through the
//   config's nameOverrides.
// - `anyOf` blocks that only restate required properties are dropped (they generate empty types).
// - A discriminated `oneOf` whose discriminator property no branch declares becomes an `anyOf`
//   (the asset library placement's `relationships`, which could never decode).
import Foundation

guard CommandLine.arguments.count == 2 else {
  print("usage: swift Scripts/prepare-asc-spec.swift <path to Apple's openapi.oas.json>")
  exit(2)
}

let input = URL(fileURLWithPath: (CommandLine.arguments[1] as NSString).expandingTildeInPath)
let kitDirectory = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent()
  .appendingPathComponent("Sources/ASCKit")
let output = kitDirectory.appendingPathComponent("openapi.json")
let configFile = kitDirectory.appendingPathComponent("openapi-generator-config.yaml")

guard var spec = try JSONSerialization.jsonObject(with: Data(contentsOf: input)) as? [String: Any],
  var components = spec["components"] as? [String: Any],
  let schemas = components["schemas"] as? [String: Any]
else {
  print("Not an OpenAPI document with components/schemas: \(input.path)")
  exit(1)
}

// Before opening them, record every string enum a command may need to validate input against:
// named schemas (BundleIdPlatform) and inline enums in request schemas, named after their path
// (DeviceUpdateRequest → data → attributes → status: DeviceUpdateRequestStatus).
var enumCatalog: [String: [String]] = [:]

func catalogInline(_ value: Any, owner: String, path: [String]) {
  if let object = value as? [String: Any] {
    if let values = object["enum"] as? [String], !(values.count == 1 && path.last == "type") {
      enumCatalog[owner + path.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()] = values
    }
    for (key, child) in object {
      let skip: Set<String> = ["properties", "data", "attributes", "items", "relationships"]
      catalogInline(child, owner: owner, path: skip.contains(key) ? path : path + [key])
    }
  } else if let array = value as? [Any] {
    for child in array { catalogInline(child, owner: owner, path: path) }
  }
}

for (name, schema) in schemas {
  if let values = (schema as? [String: Any])?["enum"] as? [String] {
    enumCatalog[name] = values
  } else if name.hasSuffix("CreateRequest") || name.hasSuffix("UpdateRequest") || name.hasSuffix("InlineCreate") {
    catalogInline(schema, owner: name, path: [])
  }
}

var openedEnums = 0

func openEnums(_ value: Any) -> Any {
  if var object = value as? [String: Any] {
    if object["enum"] != nil, (object["type"] as? String) == "string" {
      object["enum"] = nil
      openedEnums += 1
    }
    return object.mapValues(openEnums)
  }
  if let array = value as? [Any] {
    return array.map(openEnums)
  }
  return value
}

// An `anyOf` whose branches only restate which properties are required (the placement create
// and ordering requests use it to say "image or video, plus one localization") makes the
// generator emit one empty variant per branch instead of the object's properties. Drop it.
var droppedConstraints = 0

func isConstraintOnly(_ branch: Any) -> Bool {
  guard let branch = branch as? [String: Any], Set(branch.keys).isSubset(of: ["required", "properties", "type"]) else {
    return false
  }
  return (branch["properties"] as? [String: Any] ?? [:]).values.allSatisfy {
    ($0 as? [String: Any]).map { Set($0.keys).isSubset(of: ["required", "type"]) } ?? false
  }
}

func dropConstraintAnyOf(_ value: Any) -> Any {
  if var object = value as? [String: Any] {
    if object["properties"] != nil, let branches = object["anyOf"] as? [Any], branches.allSatisfy(isConstraintOnly) {
      object["anyOf"] = nil
      droppedConstraints += 1
    }
    return object.mapValues(dropConstraintAnyOf)
  }
  if let array = value as? [Any] {
    return array.map(dropConstraintAnyOf)
  }
  return value
}

// A discriminated `oneOf` whose discriminator property none of its branches declares can never
// decode: the placement's `relationships` is keyed on `mediaType`, which Apple sends in its
// `attributes`. Make it a plain `anyOf`, which decodes whichever branches fit.
var misplacedDiscriminators = 0

/// The property names a schema declares, following `$ref`s and `allOf`.
func declaredProperties(_ value: Any) -> Set<String> {
  guard let object = value as? [String: Any] else { return [] }
  if let ref = object["$ref"] as? String, let name = ref.split(separator: "/").last {
    return declaredProperties(schemas[String(name)] ?? [:])
  }
  var names = Set((object["properties"] as? [String: Any] ?? [:]).keys)
  for branch in object["allOf"] as? [Any] ?? [] { names.formUnion(declaredProperties(branch)) }
  return names
}

func fixMisplacedDiscriminators(_ value: Any) -> Any {
  if var object = value as? [String: Any] {
    if let property = (object["discriminator"] as? [String: Any])?["propertyName"] as? String,
      let branches = object["oneOf"] as? [Any],
      !branches.contains(where: { declaredProperties($0).contains(property) }) {
      object["discriminator"] = nil
      object["oneOf"] = nil
      object["anyOf"] = branches
      misplacedDiscriminators += 1
    }
    return object.mapValues(fixMisplacedDiscriminators)
  }
  if let array = value as? [Any] {
    return array.map(fixMisplacedDiscriminators)
  }
  return value
}

components["schemas"] = fixMisplacedDiscriminators(dropConstraintAnyOf(openEnums(schemas)))
spec["components"] = components

// Parameters with an empty enum (e.g. `fields[appKeywords]`: AppKeyword has no attributes) would
// generate an enum with no cases, which doesn't compile; make them plain strings.
var emptyEnums = 0

func dropEmptyEnums(_ value: Any) -> Any {
  if var object = value as? [String: Any] {
    if let values = object["enum"] as? [Any], values.isEmpty {
      object["enum"] = nil
      emptyEnums += 1
    }
    return object.mapValues(dropEmptyEnums)
  }
  if let array = value as? [Any] {
    return array.map(dropEmptyEnums)
  }
  return value
}

spec["paths"] = dropEmptyEnums(spec["paths"] ?? [:])

let data = try JSONSerialization.data(withJSONObject: spec, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try data.write(to: output)
let version = (spec["info"] as? [String: Any])?["version"] as? String ?? "?"
print("Wrote \(output.path) (spec \(version), \(openedEnums) schema enums opened, \(emptyEnums) empty parameter enums dropped, \(droppedConstraints) constraint-only anyOfs dropped, \(misplacedDiscriminators) misplaced discriminators made anyOf)")

// ASCEnums.swift: the enum catalog as Swift enums, for validating input (`parseEnum`) and
// naming values in code; requests and responses carry the raw strings.
let keywords: Set<String> = [
  "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init", "inout",
  "internal", "let", "open", "operator", "private", "protocol", "public", "rethrows", "static", "struct",
  "subscript", "typealias", "var", "break", "case", "continue", "default", "defer", "do", "else", "fallthrough",
  "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while", "as", "catch", "false", "is", "nil",
  "super", "self", "Self", "throw", "throws", "true", "try", "Type", "any", "some",
]

/// `PREPARE_FOR_SUBMISSION` → `prepareForSubmission`, `1_MONTH` → `_1Month`, `DEFAULT` → `` `default` ``
func caseName(_ raw: String) -> String {
  let words = raw.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { $0.lowercased() }
  var name = words.enumerated().map { $0.offset == 0 ? $0.element : $0.element.prefix(1).uppercased() + $0.element.dropFirst() }.joined()
  if name.isEmpty || name.first!.isNumber { name = "_" + name }
  return keywords.contains(name) ? "`\(name)`" : name
}

var enumSource = """
  // Generated by Scripts/prepare-asc-spec.swift from Apple's spec (\(version)). Do not edit.
  // Every string enum in the spec's schemas: named ones (BundleIdPlatform) and inline ones in request
  // schemas, named after their path (DeviceUpdateRequest → status: DeviceUpdateRequestStatus). The
  // generated client carries these values as plain strings (see the prepare script); use the enums to
  // validate input and to name values in code.

  public enum ASCEnum {

  """
for (name, values) in enumCatalog.sorted(by: { $0.key < $1.key }) {
  var seen = Set<String>()
  let cases = values.map { raw -> String in
    var swiftName = caseName(raw)
    // Two raw values mapping to one name (rare): fall back to the raw characters.
    if !seen.insert(swiftName).inserted {
      swiftName = "_" + raw.filter { $0.isLetter || $0.isNumber }
      seen.insert(swiftName)
    }
    return "    case \(swiftName) = \"\(raw)\""
  }
  enumSource += "  public enum \(name): String, CaseIterable, Sendable {\n\(cases.joined(separator: "\n"))\n  }\n\n"
}
enumSource = enumSource.trimmingCharacters(in: .newlines) + "\n}\n"
try enumSource.write(to: kitDirectory.appendingPathComponent("ASCEnums.swift"), atomically: true, encoding: .utf8)
print("Wrote \(enumCatalog.count) enums to ASCEnums.swift")

// Every bracketed parameter name in the spec, e.g. `filter[appStoreVersions.platform]`.
var bracketed = Set<String>()
for operations in (spec["paths"] as? [String: Any] ?? [:]).values {
  for operation in (operations as? [String: Any] ?? [:]).values {
    for parameter in (operation as? [String: Any])?["parameters"] as? [[String: Any]] ?? [] {
      if let name = parameter["name"] as? String, name.contains("[") { bracketed.insert(name) }
      // Descending sort values, e.g. `-uploadedDate`.
      let items = (parameter["schema"] as? [String: Any])?["items"] as? [String: Any]
      for value in items?["enum"] as? [String] ?? [] where value.hasPrefix("-") { bracketed.insert(value) }
    }
  }
}

/// `filter[appStoreVersions.platform]` → `filterAppStoreVersionsPlatform`, `-uploadedDate` → `minusUploadedDate`
func swiftName(_ name: String) -> String {
  let words = (name.hasPrefix("-") ? ["minus"] : [])
    + name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
  return words.enumerated().map { $0.offset == 0 ? $0.element : $0.element.prefix(1).uppercased() + $0.element.dropFirst() }.joined()
}

let marker = "# --- nameOverrides: generated by Scripts/prepare-asc-spec.swift, do not edit below ---"
let config = try String(contentsOf: configFile, encoding: .utf8)
let head = config.components(separatedBy: marker)[0].trimmingCharacters(in: .whitespacesAndNewlines)
let overrides = bracketed.sorted().map { "  \"\($0)\": \(swiftName($0))" }.joined(separator: "\n")
try (head + "\n\n" + marker + "\nnameOverrides:\n" + overrides + "\n").write(to: configFile, atomically: true, encoding: .utf8)
print("Wrote \(bracketed.count) nameOverrides to \(configFile.path)")
