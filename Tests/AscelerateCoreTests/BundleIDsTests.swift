import Testing
@testable import AscelerateCore

/// The developer portal's rules for a bundle ID's description and identifier, with the samples
/// its Register an App ID form accepted and refused.
@Suite struct BundleIDsTests {
  @Test(arguments: ["Test App", "Test-App", "Test - App", "Test.App", "App1 2", "Test'App", "12345"])
  func acceptsName(_ name: String) {
    #expect(BundleIDs.isValidName(name))
  }

  @Test(arguments: ["", "Test_App", "Test,App", "Test(App)", "Test!", "Test?", "Test/App", "Test+App", "Türkçe", "İş", "Café", "Test:App", "Test#1", "Test \"App\"", String(repeating: "a", count: 51)])
  func refusesName(_ name: String) {
    #expect(!BundleIDs.isValidName(name))
  }

  @Test func identifiers() {
    for explicit in ["com.example.App", "com.ex-ample.App1", "comexample"] {
      #expect(BundleIDs.isValidIdentifier(explicit, wildcard: false))
    }
    for explicit in ["", "com.example_app", "com.example.*", "com.Example.ÄPP", String(repeating: "a", count: 156)] {
      #expect(!BundleIDs.isValidIdentifier(explicit, wildcard: false))
    }
    for wildcard in ["com.example.*", "com.*", "com.example*", "com.ex-ample.*"] {
      #expect(BundleIDs.isValidIdentifier(wildcard, wildcard: true))
    }
    for wildcard in ["*", "com.example", "com.*.app", "com.ex_ample.*"] {
      #expect(!BundleIDs.isValidIdentifier(wildcard, wildcard: true))
    }
  }
}
