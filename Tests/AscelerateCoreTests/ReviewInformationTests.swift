import Foundation
import Testing
@testable import AscelerateCore

/// What a review information save sends.
@Suite struct ReviewInformationTests {
  let saved = ReviewInformation(
    contactFirstName: "Ada", contactLastName: "Lovelace", contactPhone: "+44 20 1234 5678",
    contactEmail: "ada@example.com", demoAccountRequired: true, demoAccountName: "demo", notes: "Notes")

  @Test func sendsOnlyChangedFieldsAndClearsEmptyOnes() {
    var edited = saved
    edited.notes = ""
    edited.demoAccountName = "reviewer"
    edited.demoAccountRequired = true
    let (values, cleared) = edited.changes(from: saved)
    #expect(values == ReviewInformation(demoAccountName: "reviewer"))
    #expect(cleared == [["data", "attributes", "notes"]])
  }

  @Test func leavesNilFieldsAsTheyAre() {
    let (values, cleared) = ReviewInformation(notes: "New").changes(from: saved)
    #expect(values == ReviewInformation(notes: "New"))
    #expect(cleared.isEmpty)
  }

  @Test func sendsTheWholeContactWhenOneFieldChanges() {
    let (values, _) = ReviewInformation(contactPhone: "+44 20 8765 4321").changes(from: saved)
    #expect(values == ReviewInformation(
      contactFirstName: "Ada", contactLastName: "Lovelace", contactPhone: "+44 20 8765 4321",
      contactEmail: "ada@example.com"))
  }

  @Test func turnsOffARequiredDemoAccount() {
    let (values, _) = ReviewInformation(demoAccountRequired: false).changes(from: saved)
    #expect(values == ReviewInformation(demoAccountRequired: false))
  }
}
