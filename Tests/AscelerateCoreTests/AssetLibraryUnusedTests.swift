import ASCKit
import Foundation
import Testing
@testable import AscelerateCore

/// `isUnused`, which every library delete rests on: no placement at all, and never reviewed.
@Suite struct AssetLibraryUnusedTests {
  func image(state: String, placements: String?) throws -> Components.Schemas.AppAssetLibraryImage {
    let relationships = placements.map { #", "relationships": {"placements": {"data": \#($0)}}"# } ?? ""
    let json = #"{"type": "appAssetLibraryImages", "id": "1", "attributes": {"state": "\#(state)", "fileName": "a.png", "fileSize": 10}\#(relationships)}"#
    return try JSONDecoder().decode(Components.Schemas.AppAssetLibraryImage.self, from: Data(json.utf8))
  }

  @Test func onlyAnUnplacedUnreviewedImageIsUnused() throws {
    #expect(AssetLibrary.isUnused(try image(state: "COMPLETE", placements: "[]")))
    #expect(AssetLibrary.isUnused(try image(state: "FAILED", placements: "[]")))
    // Placed somewhere (the live version shares it): kept.
    #expect(!AssetLibrary.isUnused(try image(state: "COMPLETE", placements: #"[{"type": "appAssetLibraryPlacements", "id": "p"}]"#)))
    // Through review: kept even unplaced.
    #expect(!AssetLibrary.isUnused(try image(state: "APPROVED", placements: "[]")))
    #expect(!AssetLibrary.isUnused(try image(state: "ARCHIVED", placements: "[]")))
    // Placements not read: kept (nothing is deleted on a guess).
    #expect(!AssetLibrary.isUnused(try image(state: "COMPLETE", placements: nil)))
  }
}
