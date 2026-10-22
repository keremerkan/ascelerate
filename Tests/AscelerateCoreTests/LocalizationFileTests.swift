import Foundation
import Testing
@testable import AscelerateCore

/// The localization file format the export and import commands share.
@Suite struct LocalizationFileTests {
  @Test func writesSortedFieldsAndLeavesOutMissingOnes() throws {
    let data = try LocalizationFile.encode(["tr": AppInfoLocaleFields(name: "Uygulama"), "en-US": AppInfoLocaleFields(name: "App", subtitle: "Sub")])
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.range(of: "\"en-US\"")!.lowerBound < text.range(of: "\"tr\"")!.lowerBound)
    #expect(text.contains("\"subtitle\" : \"Sub\""))
    #expect(!text.contains("privacy"))
  }

  @Test func readsOnlyTheFieldsPresentAndIgnoresUnknownOnes() throws {
    let file = try LocalizationFile.decode(Data(#"{"de-DE": {"description": "Text", "extra": 1}}"#.utf8), as: LocaleFields.self)
    #expect(file == ["de-DE": LocaleFields(description: "Text")])
  }

  @Test func refusesWhatIsntAFile() {
    #expect(throws: LocalizationFile.FileError.self) { try LocalizationFile.decode(Data("[]".utf8), as: LocaleFields.self) }
    #expect(throws: LocalizationFile.FileError.self) { try LocalizationFile.decode(Data("{}".utf8), as: LocaleFields.self) }
    #expect(throws: LocalizationFile.FileError.self) { try LocalizationFile.decode(Data(#"{"tr": {"name": 3}}"#.utf8), as: AppInfoLocaleFields.self) }
  }
}
