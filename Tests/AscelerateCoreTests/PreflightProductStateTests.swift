import Testing
@testable import AscelerateCore

@Suite struct PreflightProductStateTests {
  @Test func offSaleIsSkippedApprovedAndInReviewPass() {
    for state in ["DEVELOPER_REMOVED_FROM_SALE", "REMOVED_FROM_SALE"] { #expect(Preflight.productState(state) == .skipped) }
    for state in ["READY_TO_SUBMIT", "APPROVED", "PENDING_BINARY_APPROVAL", "WAITING_FOR_REVIEW", "IN_REVIEW"] {
      #expect(Preflight.productState(state) == .submittable)
    }
    for state in ["MISSING_METADATA", "REJECTED", "DEVELOPER_ACTION_NEEDED", nil] as [String?] {
      #expect(Preflight.productState(state) == .notSubmittable)
    }
  }
}
