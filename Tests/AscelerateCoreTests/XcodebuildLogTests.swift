import Testing
@testable import AscelerateCore

/// Test logs in xcodebuild's shape.
@Suite struct XcodebuildLogTests {
  func bundle(_ verdict: String) -> String {
    """
    Test Suite 'All tests' started at 2026-11-26 01:02:03.456.
    Test Suite 'AppUITests.xctest' started at 2026-11-26 01:02:03.457.
    Test Case '-[AppUITests testScreenshots]' \(verdict) (12.345 seconds).
    Test Suite 'AppUITests.xctest' \(verdict) at 2026-11-26 01:02:15.802.
    Test Suite 'All tests' \(verdict) at 2026-11-26 01:02:15.803.
    \tExecuted 1 test, with \(verdict == "passed" ? 0 : 1) failures (0 unexpected) in 12.345 (12.346) seconds

    """
  }

  @Test func oneBundle() {
    #expect(XcodebuildLog.testsPassed(bundle("passed") + "** TEST EXECUTE SUCCEEDED **\n"))
    #expect(!XcodebuildLog.testsPassed(bundle("failed") + "** TEST EXECUTE FAILED **\n"))
  }

  @Test func twoBundles() {
    #expect(XcodebuildLog.testsPassed(bundle("passed") + bundle("passed")))
    // The first failed, the second passed: not a pass, whatever the last line says.
    #expect(!XcodebuildLog.testsPassed(bundle("failed") + bundle("passed")))
  }

  @Test func aCrashAfterThePassedVerdictStillPasses() {
    // Xcode 27.1's result bundle importer crashed after the tests passed: no TEST EXECUTE line.
    let crash = bundle("passed") + "Fatal error: Unable to write data for …/StandardOutputAndStandardError.txt due to resourceChanged\n"
    #expect(XcodebuildLog.testsPassed(crash))
  }

  @Test func noVerdictIsNoPass() {
    #expect(!XcodebuildLog.testsPassed("Test Suite 'All tests' started at 2026-11-26 01:02:03.456.\n"))
    #expect(!XcodebuildLog.testsPassed("** BUILD FAILED **\n"))
  }
}
