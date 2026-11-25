import Testing
@testable import AscelerateCore

/// One way of finding an item by ID, identifier or name.
@Suite struct ReferenceTests {
  struct Item { let id: String; let bundle: String?; let name: String? }
  let items = [
    Item(id: "1", bundle: "com.x.mykit", name: "Main"),
    Item(id: "2", bundle: nil, name: "MyKit"),
    Item(id: "3", bundle: nil, name: "Twin"),
    Item(id: "4", bundle: nil, name: "twin"),
    Item(id: "5", bundle: nil, name: "1"),
  ]

  func find(_ ref: String, bundle: String? = nil) throws -> String? {
    try Reference.find(ref, in: items, kind: "product", id: \.id, identifiers: [\.bundle], identifierReference: bundle,
      name: \.name, label: { "\($0.name ?? "-") (\($0.id))" })?.id
  }

  @Test func passesGoIdThenIdentifierThenName() throws {
    // An ID wins over a name that reads the same.
    #expect(try find("1") == "1")
    // The bundle ID an alias stands for wins over a product named like the alias.
    #expect(try find("mykit", bundle: "com.x.mykit") == "1")
    #expect(try find("mykit") == "2")
    #expect(try find("MAIN") == "1")
    #expect(try find("nothing") == nil)
  }

  @Test func aNameOfSeveralIsRefused() {
    #expect(throws: Reference.Ambiguous.self) { try find("TWIN") }
  }

  @Test func listsAreDeduplicatedInOrder() {
    #expect(Reference.unique(["a", "b", "a", "c", "b"]) == ["a", "b", "c"])
  }
}
