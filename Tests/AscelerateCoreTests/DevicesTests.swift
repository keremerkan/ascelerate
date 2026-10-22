import Testing
@testable import AscelerateCore

/// UDIDs in Apple's three forms, and what isn't one.
@Suite struct DevicesTests {
  @Test func udids() {
    #expect(Devices.isValidUDID(String(repeating: "a1", count: 20)))
    #expect(Devices.isValidUDID("00008103-001234567890ABCD"))
    #expect(Devices.isValidUDID("56B0F982-0C73-5EBB-9C24-DA2B3B8A00D4"))
    #expect(!Devices.isValidUDID(String(repeating: "a1", count: 19)))
    #expect(!Devices.isValidUDID("00008103-001234567890ABCG"))
    #expect(!Devices.isValidUDID(" 00008103-001234567890ABCD"))
    #expect(!Devices.isValidUDID(""))
  }
}
