import Testing
@testable import AscelerateCore

@Suite struct FieldLimitsTests {
  @Test func overLimitNamesEachLongField() {
    let fine = LocaleFields(description: "Short", keywords: String(repeating: "k", count: 100))
    #expect(fine.overLimit.isEmpty)
    let long = LocaleFields(keywords: String(repeating: "k", count: 101), promotionalText: String(repeating: "p", count: 171))
    #expect(long.overLimit == ["keywords: 101 characters (at most 100)", "promotionalText: 171 characters (at most 170)"])
    #expect(AppInfoLocaleFields(name: String(repeating: "n", count: 31)).overLimit == ["name: 31 characters (at most 30)"])
  }

  @Test func theErrorListsOnlyLanguagesWithProblems() {
    #expect(FieldsOverLimit(["en-US": [], "tr": []]) == nil)
    let error = FieldsOverLimit(["tr": ["name: 31 characters (at most 30)"], "en-US": []])
    #expect(error?.problems.keys.sorted() == ["tr"])
    #expect(error?.errorDescription?.contains("tr: name: 31") == true)
  }
}
