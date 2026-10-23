import Foundation
import Testing
@testable import AscelerateCore

/// Testers from a CSV file, as `testflight testers import` reads it.
@Suite struct BetaTestersTests {
  @Test func readsEmailsWithOptionalNames() {
    let testers = BetaTesters.parseCSV("a@example.com\nb@example.com,Ada\nc@example.com, Ada , Lovelace \n")
    #expect(testers == [
      .init(email: "a@example.com"),
      .init(email: "b@example.com", firstName: "Ada"),
      .init(email: "c@example.com", firstName: "Ada", lastName: "Lovelace"),
    ])
  }

  @Test func skipsHeaderCommentsBlankLinesAndEmptyNames() {
    let testers = BetaTesters.parseCSV("Email,First Name,Last Name\n# a comment\n\n  \nd@example.com,,Hopper\n")
    #expect(testers == [.init(email: "d@example.com", lastName: "Hopper")])
  }

  @Test func readsWindowsLineEndings() {
    #expect(BetaTesters.parseCSV("e@example.com\r\nf@example.com\r\n") == [.init(email: "e@example.com"), .init(email: "f@example.com")])
  }
}
