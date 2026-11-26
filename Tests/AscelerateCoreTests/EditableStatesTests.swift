import ASCKit
import Testing
@testable import AscelerateCore

@Suite struct EditableStatesTests {
  /// `findVersion` filters by these: one that isn't a filter value would drop out unnoticed.
  @Test func everyEditableStateIsAVersionStateFilter() {
    typealias State = Operations.AppsAppStoreVersionsGetToManyRelated.Input.Query.FilterAppVersionStatePayloadPayload
    for state in VersionLocalizations.editableStates { #expect(State(rawValue: state) != nil, "\(state)") }
  }
}
