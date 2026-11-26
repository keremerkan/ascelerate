import Testing
@testable import AscelerateCore

@Suite struct SaveTargetsTests {
  @Test func existingLocalesUpdateOthersCreateInOrder() {
    let targets = saveTargets(
      [("tr", "a"), ("en-US", "b"), ("de-DE", "c")],
      existing: [("en-US", "E1"), ("tr", "T1"), ("tr", "T2")])
    #expect(targets.map(\.locale) == ["tr", "en-US", "de-DE"])
    #expect(targets.map(\.value) == ["a", "b", "c"])
    // The first record of a locale wins; a locale without one is created.
    #expect(targets.map(\.existingID) == ["T1", "E1", nil])
  }
}
