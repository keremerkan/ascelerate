import Foundation
import Synchronization

/// A product's prices as a file, the format of the `pricing export` commands: the base territory
/// (app and in-app purchase schedules; a subscription has none) and one customer price per
/// territory, `{"baseTerritory": "USA", "prices": {"USA": "4.99", "FRA": "5.99"}}`. A file applies
/// to any product of the same kind, matched to that product's own tiers by customer price.
public struct PriceFile: Codable, Sendable, Equatable {
  public var baseTerritory: String?
  public var prices: [String: String]

  public init(baseTerritory: String? = nil, prices: [String: String]) {
    self.baseTerritory = baseTerritory
    self.prices = prices
  }

  public enum FileError: LocalizedError {
    case unreadable
    case empty

    public var errorDescription: String? {
      switch self {
        case .unreadable: "This isn't a price file: it needs \"prices\", one customer price per territory code."
        case .empty: "The price file has no prices."
      }
    }
  }

  /// A schedule's file without a price for its base territory.
  public struct BaseMissing: LocalizedError {
    public let territoryID: String

    public init(territoryID: String) {
      self.territoryID = territoryID
    }

    public var errorDescription: String? {
      "The price file has no price for the base territory \(territoryID)."
    }
  }

  /// Reads a file, territory codes in uppercase.
  public static func decode(_ data: Data) throws -> PriceFile {
    guard let file = try? JSONDecoder().decode(PriceFile.self, from: data) else { throw FileError.unreadable }
    let prices = Dictionary(file.prices.map { ($0.key.uppercased(), $0.value) }) { first, _ in first }
    guard !prices.isEmpty else { throw FileError.empty }
    return PriceFile(baseTerritory: file.baseTerritory?.uppercased(), prices: prices)
  }

  /// The file's JSON, keys sorted, as the export commands write it.
  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }

  /// A file price that matched no tier of its territory.
  public struct Mismatch: Sendable, Hashable {
    public let territoryID: String
    public let price: String
    /// The territory's closest customer prices, nearest first.
    public let nearest: [String]
  }

  /// The tier of each file price, and the prices no tier has.
  public struct Resolution: Sendable {
    public var points: [String: AppPricing.PricePoint] = [:]
    public var mismatches: [Mismatch] = []
  }

  /// Matches each price to its territory's tier. Apple's comparable prices for the tier of
  /// `base` (the file's base, else the USA or the first territory) settle every territory whose
  /// price equals them in one request; the others read their tier lists `batchSize` territories
  /// per call, four calls at a time. `progress` gets the territories settled so far and the total.
  public func resolve(
    batchSize: Int = 1,
    tiers: @escaping @Sendable (_ territoryIDs: [String]) async throws -> [String: [AppPricing.PricePoint]],
    equalizations: @escaping @Sendable (_ pricePointID: String) async throws -> [AppPricing.PricePoint],
    progress: (@Sendable (_ done: Int, _ total: Int) -> Void)? = nil
  ) async throws -> Resolution {
    var resolution = Resolution()
    let total = prices.count
    let base = baseTerritory.flatMap { prices[$0] != nil ? $0 : nil }
      ?? (prices["USA"] != nil ? "USA" : prices.keys.sorted()[0])
    var pending = prices
    progress?(0, total)
    if let basePrice = pending.removeValue(forKey: base) {
      let baseTiers = try await tiers([base])[base] ?? []
      switch Self.match(basePrice, in: baseTiers) {
        case .success(let point):
          resolution.points[base] = point
          for comparable in try await equalizations(point.id) {
            if let price = pending[comparable.territoryID], Self.isSame(price, comparable.customerPrice) {
              resolution.points[comparable.territoryID] = comparable
              pending.removeValue(forKey: comparable.territoryID)
            }
          }
        case .failure(let nearest):
          resolution.mismatches.append(Mismatch(territoryID: base, price: basePrice, nearest: nearest.prices))
      }
    }
    let settled = Mutex(total - pending.count)
    progress?(total - pending.count, total)
    let others = pending.sorted { $0.key < $1.key }
    let batches = stride(from: 0, to: others.count, by: max(batchSize, 1)).map { Array(others[$0..<min($0 + max(batchSize, 1), others.count)]) }
    let matched = try await boundedConcurrentMap(batches, maxConcurrent: 4) { batch in
      let read = try await tiers(batch.map(\.key))
      let done = settled.withLock { count in
        count += batch.count
        return count
      }
      progress?(done, total)
      return batch.map { entry in (entry.key, entry.value, Self.match(entry.value, in: read[entry.key] ?? [])) }
    }.flatMap { $0 }
    for (territoryID, price, result) in matched {
      switch result {
        case .success(let point): resolution.points[territoryID] = point
        case .failure(let nearest):
          resolution.mismatches.append(Mismatch(territoryID: territoryID, price: price, nearest: nearest.prices))
      }
    }
    resolution.mismatches.sort { $0.territoryID < $1.territoryID }
    return resolution
  }

  private struct Nearest: Error {
    let prices: [String]
  }

  /// The tier with this customer price, or the five nearest prices.
  private static func match(_ price: String, in tiers: [AppPricing.PricePoint]) -> Result<AppPricing.PricePoint, Nearest> {
    if let point = tiers.first(where: { isSame(price, $0.customerPrice) }) { return .success(point) }
    let target = Double(price.trimmingCharacters(in: .whitespaces)) ?? 0
    let nearest = tiers.sorted { abs((Double($0.customerPrice) ?? 0) - target) < abs((Double($1.customerPrice) ?? 0) - target) }
      .prefix(5).map(\.customerPrice)
    return .failure(Nearest(prices: Array(nearest)))
  }

  private static func isSame(_ price: String, _ tierPrice: String) -> Bool {
    guard let value = Double(price.trimmingCharacters(in: .whitespaces)), let tier = Double(tierPrice) else { return false }
    return abs(value - tier) < 0.001
  }
}
