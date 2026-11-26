import Foundation

/// What an xcodebuild test log says.
public enum XcodebuildLog {
  /// Whether every test bundle passed. XCTest prints `Test Suite 'All tests' started at …` when a
  /// bundle begins and `… passed at …` or `… failed at …` when it ends: only those verdicts count.
  /// At least one, none failed, and no `** TEST EXECUTE FAILED **` (a run whose tests passed and
  /// then xcodebuild crashed has the verdict and no such line).
  public static func testsPassed(_ log: String) -> Bool {
    let verdicts = log.components(separatedBy: "Test Suite 'All tests' ").dropFirst().compactMap { piece -> Bool? in
      if piece.hasPrefix("passed") { return true }
      if piece.hasPrefix("failed") { return false }
      return nil
    }
    return !verdicts.isEmpty && !verdicts.contains(false) && !log.contains("** TEST EXECUTE FAILED **")
  }
}
