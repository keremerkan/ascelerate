import Testing
@testable import AscelerateCore

/// Where a new introductory offer can't go, by Apple's rules seen live: no overlap within a
/// territory, and one future offer per territory.
@Suite struct IntroductoryOfferTests {
  private func offer(_ territory: String, _ start: String?, _ end: String?) -> Subscriptions.IntroductoryOffer {
    Subscriptions.IntroductoryOffer(
      id: territory, territoryID: territory, mode: "FREE_TRIAL", duration: "TWO_WEEKS", periods: 1,
      startDate: start, endDate: end, customerPrice: nil)
  }

  @Test func overlaps() {
    let today = "2026-10-22"
    let novDec = offer("USA", "2026-11-01", "2026-12-31")
    // Open-ended from today runs into November.
    #expect(novDec.overlaps(start: nil, end: nil, today: today))
    #expect(!novDec.overlaps(start: nil, end: "2026-10-31", today: today))
    #expect(novDec.overlaps(start: "2026-12-31", end: nil, today: today))
    #expect(!novDec.overlaps(start: "2027-01-01", end: nil, today: today))
  }

  @Test func conflicts() {
    let today = "2026-10-22"
    let existing = [offer("USA", "2026-11-01", "2026-12-31"), offer("TUR", "2026-10-01", "2026-10-20")]
    // Overlapping in the USA; Türkiye's ended before.
    #expect(Subscriptions.introductoryOfferConflicts(["USA", "TUR", "CAN"], existing: existing, start: nil, end: nil, today: today) == ["USA"])
    // A later offer after the USA's future one: still refused (one future offer per territory).
    #expect(Subscriptions.introductoryOfferConflicts(["USA", "CAN"], existing: existing, start: "2027-01-01", end: nil, today: today) == ["USA"])
    // Before it, from today: fine.
    #expect(Subscriptions.introductoryOfferConflicts(["USA"], existing: existing, start: nil, end: "2026-10-31", today: today).isEmpty)
  }
}
