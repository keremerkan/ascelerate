import Testing
@testable import AscelerateCore

@Suite struct SetSyncTests {
  private typealias Item = ClassicMedia.SetSync.Item

  @Test func sameFilesInOrderAreUnchanged() {
    let sync = ClassicMedia.SetSync(files: ["a", "b"], current: [Item(id: "1", checksum: "a"), Item(id: "2", checksum: "b")])
    #expect(sync.kept == ["1", "2"])
    #expect(sync.deletions.isEmpty)
    #expect(sync.isUnchanged)
  }

  @Test func checksumsMatchWhateverTheirCase() {
    let sync = ClassicMedia.SetSync(files: ["abc"], current: [Item(id: "1", checksum: "ABC")])
    #expect(sync.isUnchanged)
  }

  @Test func aChangedFileIsUploadedAndItsOldItemDeleted() {
    let sync = ClassicMedia.SetSync(
      files: ["a", "new", "c"],
      current: [Item(id: "1", checksum: "a"), Item(id: "2", checksum: "b"), Item(id: "3", checksum: "c")])
    #expect(sync.kept == ["1", nil, "3"])
    #expect(sync.deletions == ["2"])
    #expect(!sync.isUnchanged)
  }

  @Test func movedFilesAreOnlyReordered() {
    let sync = ClassicMedia.SetSync(files: ["b", "a"], current: [Item(id: "1", checksum: "a"), Item(id: "2", checksum: "b")])
    #expect(sync.kept == ["2", "1"])
    #expect(sync.deletions.isEmpty)
    #expect(!sync.isUnchanged)
  }

  @Test func aFileTwiceTakesTwoItems() {
    let sync = ClassicMedia.SetSync(
      files: ["a", "a", "a"], current: [Item(id: "1", checksum: "a"), Item(id: "2", checksum: "a")])
    #expect(sync.kept == ["1", "2", nil])
    #expect(sync.deletions.isEmpty)
  }

  @Test func anItemWithoutAChecksumIsNeverKept() {
    // A failed upload, or one whose file never arrived.
    let sync = ClassicMedia.SetSync(files: ["a"], current: [Item(id: "1", checksum: nil)])
    #expect(sync.kept == [nil])
    #expect(sync.deletions == ["1"])
  }

  @Test func extraItemsAreDeleted() {
    let sync = ClassicMedia.SetSync(files: ["a"], current: [Item(id: "1", checksum: "a"), Item(id: "2", checksum: "z")])
    #expect(sync.kept == ["1"])
    #expect(sync.deletions == ["2"])
    #expect(!sync.isUnchanged)
  }

  @Test func anEmptySetUploadsEverything() {
    let sync = ClassicMedia.SetSync(files: ["a", "b"], current: [])
    #expect(sync.kept == [nil, nil])
    #expect(sync.deletions.isEmpty)
    #expect(!sync.isUnchanged)
  }
}
