import Foundation
import Testing
@testable import AscelerateCore

@Suite struct StaleUploadsTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func upload(_ id: String, build: String = "1", state: String, hoursAgo: Double = 1) -> BuildUploadRecords.Upload {
    BuildUploadRecords.Upload(
      id: id, version: "1.0", build: build, platform: "IOS", state: state,
      createdDate: now.addingTimeInterval(-hoursAgo * 3600), uploadedDate: nil, errors: nil, warnings: nil, infos: nil)
  }

  private func stale(_ uploads: [BuildUploadRecords.Upload]) -> [String] {
    BuildUploadRecords.stale(in: uploads, now: now).map(\.id)
  }

  @Test func aWaitingRecordBesideOneThatWentThroughIsStale() {
    #expect(stale([upload("a", state: "AWAITING_UPLOAD"), upload("b", state: "COMPLETE")]) == ["a"])
    #expect(stale([upload("a", state: "AWAITING_UPLOAD"), upload("b", state: "PROCESSING")]) == ["a"])
  }

  @Test func aFailedSiblingDoesNotCount() {
    // The build can be uploaded again: the waiting record may be that upload.
    #expect(stale([upload("a", state: "AWAITING_UPLOAD"), upload("b", state: "FAILED")]).isEmpty)
  }

  @Test func anotherBuildsRecordDoesNotCount() {
    #expect(stale([upload("a", state: "AWAITING_UPLOAD"), upload("b", build: "2", state: "COMPLETE")]).isEmpty)
  }

  @Test func aWaitingRecordOverADayOldIsStale() {
    #expect(stale([upload("a", state: "AWAITING_UPLOAD", hoursAgo: 25)]) == ["a"])
    #expect(stale([upload("a", state: "AWAITING_UPLOAD", hoursAgo: 23)]).isEmpty)
  }

  @Test func onlyWaitingRecordsAreStale() {
    #expect(stale([upload("a", state: "COMPLETE", hoursAgo: 48), upload("b", state: "FAILED", hoursAgo: 48)]).isEmpty)
  }
}
