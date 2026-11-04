import Foundation
import Testing
@testable import AscelerateCore

/// Both project file formats give the same targets, Release settings and languages.
@Suite struct XcodeProjectFileTests {
  /// A small project in the old property-list format: an app with a Release override, a UI test
  /// bundle, and an SDK-conditional setting.
  static let propertyList = """
    // !$*UTF8*$!
    {
      archiveVersion = 1;
      objects = {
        P1 = { isa = PBXProject; buildConfigurationList = PL; knownRegions = (en, Base, tr, "zh-Hans"); };
        PL = { isa = XCConfigurationList; buildConfigurations = (PD, PR); };
        PD = { isa = XCBuildConfiguration; name = Debug; buildSettings = { SDKROOT = iphoneos; CURRENT_PROJECT_VERSION = 1; }; };
        PR = { isa = XCBuildConfiguration; name = Release; buildSettings = { SDKROOT = iphoneos; CURRENT_PROJECT_VERSION = 7; }; };
        T1 = { isa = PBXNativeTarget; name = MyApp; productType = "com.apple.product-type.application"; buildConfigurationList = TL; };
        TL = { isa = XCConfigurationList; buildConfigurations = (TD, TR); };
        TD = { isa = XCBuildConfiguration; name = Debug; buildSettings = { PRODUCT_BUNDLE_IDENTIFIER = com.example.MyApp.debug; }; };
        TR = { isa = XCBuildConfiguration; name = Release; buildSettings = {
          PRODUCT_BUNDLE_IDENTIFIER = com.example.MyApp; MARKETING_VERSION = 2.1;
          "CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Distribution";
          LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks");
        }; };
        T2 = { isa = PBXNativeTarget; name = MyAppUITests; productType = "com.apple.product-type.bundle.ui-testing"; buildConfigurationList = UL; };
        UL = { isa = XCConfigurationList; buildConfigurations = (UR); };
        UR = { isa = XCBuildConfiguration; name = Release; buildSettings = { TEST_TARGET_NAME = MyApp; }; };
      };
      rootObject = P1;
    }
    """

  /// The same project as Xcode 27.2's JSON format writes it (trailing commas included): one
  /// settings dictionary each, configurations in the keys, the development language apart from
  /// the others.
  static let json = """
    {
      "default-configuration": "Release",
      "configurations": [ "Debug", "Release", ],
      "localizations": { "development": "en", "supported": [ "Base", "tr", "zh-Hans", ], },
      "build-settings": {
        "SDKROOT": "iphoneos",
        "CURRENT_PROJECT_VERSION[config=Debug]": "1",
        "CURRENT_PROJECT_VERSION[config=Release]": "7",
      },
      "targets": [
        {
          "id": "T1",
          "name": "MyApp",
          "product-type": "application",
          "build-settings": {
            "PRODUCT_BUNDLE_IDENTIFIER": "com.example.MyApp",
            "PRODUCT_BUNDLE_IDENTIFIER[config=Debug]": "com.example.MyApp.debug",
            "MARKETING_VERSION[config=Release]": "2.1",
            "CODE_SIGN_IDENTITY[config=Release][sdk=macosx*]": "Apple Distribution",
            "LD_RUNPATH_SEARCH_PATHS": [ "$(inherited)", "@executable_path/Frameworks", ],
          },
        }, {
          "id": "T2",
          "name": "MyAppUITests",
          "product-type": "bundle.ui-testing",
          "build-settings": { "TEST_TARGET_NAME": "MyApp", },
        },
      ],
    }
    """

  @Test func bothFormatsAgree() throws {
    let old = try #require(XcodeProjectFile.propertyList(Data(Self.propertyList.utf8)))
    let new = try #require(XcodeProjectFile.json(Data(Self.json.utf8)))
    #expect(!old.isJSON && new.isJSON)
    #expect(old.localizations == ["en", "Base", "tr", "zh-Hans"])
    #expect(new.localizations == old.localizations)
    for file in [old, new] {
      let app = try #require(file.target(id: "T1"))
      #expect(app.isApp && app.name == "MyApp")
      #expect(app.releaseSettings["PRODUCT_BUNDLE_IDENTIFIER"] == "com.example.MyApp")
      #expect(app.releaseSettings["MARKETING_VERSION"] == "2.1")
      // The project's Release value, under the target's.
      #expect(app.releaseSettings["CURRENT_PROJECT_VERSION"] == "7")
      #expect(app.releaseSettings["SDKROOT"] == "iphoneos")
      #expect(app.releaseSettings["CODE_SIGN_IDENTITY[sdk=macosx*]"] == "Apple Distribution")
      #expect(app.releaseSettings["LD_RUNPATH_SEARCH_PATHS"] == "$(inherited) @executable_path/Frameworks")
      let tests = try #require(file.target(id: "T2"))
      #expect(tests.isUITestBundle && tests.name == "MyAppUITests")
    }
  }

  @Test func otherConfigurationsAreLeftOut() {
    let settings = XcodeProjectFile.release([
      "A": "plain", "A[config=Debug]": "debug", "B[config=Debug]": "only debug", "C[config=Release]": "release",
    ])
    #expect(settings == ["A": "plain", "C": "release"])
  }

  @Test func readsTheFolder() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "XcodeProjectFileTests-\(UUID().uuidString)/MyApp.xcodeproj")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
    try Self.propertyList.write(to: folder.appending(path: "project.pbxproj"), atomically: true, encoding: .utf8)
    #expect(XcodeProjectFile(project: folder)?.isJSON == false)
    // A converted project has the JSON file only; it's read first when both are there.
    try Self.json.write(to: folder.appending(path: "project.xcproj"), atomically: true, encoding: .utf8)
    #expect(XcodeProjectFile(project: folder)?.isJSON == true)
  }
}
