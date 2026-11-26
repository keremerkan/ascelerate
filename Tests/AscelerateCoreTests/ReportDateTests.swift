import Foundation
import Testing
@testable import AscelerateCore

@Suite struct ReportDateTests {
  @Test func defaultDatesAreTheLastCompletedPeriodInPacificTime() {
    // Wednesday 2026-11-25 10:00 in Los Angeles (18:00 UTC).
    let wednesday = Date(timeIntervalSince1970: 1_795_629_600)
    #expect(SalesReports.defaultDate(frequency: "DAILY", from: wednesday) == "2026-11-24")
    #expect(SalesReports.defaultDate(frequency: "WEEKLY", from: wednesday) == "2026-11-22")
    #expect(SalesReports.defaultDate(frequency: "MONTHLY", from: wednesday) == "2026-10")
    #expect(SalesReports.defaultDate(frequency: "YEARLY", from: wednesday) == "2025")
    // On a Sunday the week ending today isn't complete: the one before.
    let sunday = wednesday.addingTimeInterval(-3 * 86_400)
    #expect(SalesReports.defaultDate(frequency: "WEEKLY", from: sunday) == "2026-11-15")
    // 23:30 UTC on 2026-11-26 is the 26th's afternoon in Los Angeles: yesterday is the 25th.
    #expect(SalesReports.defaultDate(frequency: "DAILY", from: Date(timeIntervalSince1970: 1_795_735_800)) == "2026-11-25")
  }
}
