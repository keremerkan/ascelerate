import Testing
@testable import AscelerateCore

/// Workflow lines split into arguments.
@Suite struct ArgumentsTests {
  @Test func quotesAndEscapes() throws {
    #expect(try splitArguments(#"reviews respond 123 --body "Thanks for the \"great\" review" -y"#)
      == ["reviews", "respond", "123", "--body", #"Thanks for the "great" review"#, "-y"])
    #expect(try splitArguments(#"a 'it\'s' "back\\slash""#) == ["a", "it's", #"back\slash"#])
    #expect(try splitArguments(#"a path\ with\ spaces"#) == ["a", "path with spaces"])
    // Other backslashes stay.
    #expect(try splitArguments(#"--text "a\nb""#) == ["--text", #"a\nb"#])
    #expect(try splitArguments(#"--body """#) == ["--body", ""])
  }

  @Test func anyWhitespaceSeparates() throws {
    #expect(try splitArguments("a\tb  c\u{00A0}d") == ["a", "b", "c", "d"])
  }

  @Test func anOpenQuoteThrows() {
    #expect(throws: UnterminatedQuote.self) { try splitArguments(#"a "b"#) }
    #expect(throws: UnterminatedQuote.self) { try splitArguments(#"a "b\""#) }
  }
}
