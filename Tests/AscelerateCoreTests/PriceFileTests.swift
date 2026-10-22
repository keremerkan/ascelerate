import Foundation
import Synchronization
import Testing
@testable import AscelerateCore

/// Price files: reading them, and matching their prices to tiers.
@Suite struct PriceFileTests {
  private func point(_ territory: String, _ price: String) -> AppPricing.PricePoint {
    AppPricing.PricePoint(id: "\(territory)-\(price)", territoryID: territory, customerPrice: price, proceeds: "0")
  }

  @Test func decodeUppercasesTerritories() throws {
    let file = try PriceFile.decode(Data(#"{"baseTerritory": "usa", "prices": {"usa": "4.99", "tur": "99.99"}}"#.utf8))
    #expect(file.baseTerritory == "USA")
    #expect(file.prices == ["USA": "4.99", "TUR": "99.99"])
    #expect(throws: PriceFile.FileError.self) { try PriceFile.decode(Data(#"{"prices": {}}"#.utf8)) }
  }

  @Test func resolve() async throws {
    let tiers: [String: [AppPricing.PricePoint]] = [
      "USA": [point("USA", "3.99"), point("USA", "4.99")],
      "TUR": [point("TUR", "99.99"), point("TUR", "149.99"), point("TUR", "199.99")],
      "DEU": [point("DEU", "4.99"), point("DEU", "5.99")],
    ]
    let file = PriceFile(baseTerritory: "USA", prices: ["USA": "4.99", "DEU": "5.99", "TUR": "120"])
    let reads = Mutex<[[String]]>([])
    let steps = Mutex<[Int]>([])
    let resolution = try await file.resolve(
      batchSize: 9,
      tiers: { ids in
        reads.withLock { $0.append(ids) }
        return tiers.filter { ids.contains($0.key) }
      },
      equalizations: { _ in [point("DEU", "5.99"), point("TUR", "199.99")] },
      progress: { done, _ in steps.withLock { $0.append(done) } })
    #expect(resolution.points["USA"]?.customerPrice == "4.99")
    // From Apple's comparable prices, without reading Germany's tiers.
    #expect(resolution.points["DEU"]?.id == "DEU-5.99")
    #expect(resolution.points["TUR"] == nil)
    #expect(resolution.mismatches.first?.territoryID == "TUR")
    #expect(resolution.mismatches.first?.nearest.first == "99.99")
    #expect(reads.withLock { $0 } == [["USA"], ["TUR"]])
    #expect(steps.withLock { $0 } == [0, 2, 3])
  }

  @Test func resolveInBatches() async throws {
    let prices = Dictionary(uniqueKeysWithValues: (0..<20).map { (String(format: "T%02d", $0), "1.99") })
    let reads = Mutex<[[String]]>([])
    let resolution = try await PriceFile(baseTerritory: "T00", prices: prices).resolve(
      batchSize: 9,
      tiers: { ids in
        reads.withLock { $0.append(ids) }
        return Dictionary(uniqueKeysWithValues: ids.map { ($0, [AppPricing.PricePoint(id: $0, territoryID: $0, customerPrice: "1.99", proceeds: "0")]) })
      },
      equalizations: { _ in [] })
    #expect(resolution.points.count == 20)
    // The base on its own, then the other 19 in batches of 9, 9 and 1.
    #expect(reads.withLock { $0 }.map(\.count).sorted() == [1, 1, 9, 9])
  }
}
