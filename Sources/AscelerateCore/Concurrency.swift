import Foundation

/// Maps `items` through an async `transform` with bounded concurrency, preserving input order.
/// Used to parallelize per-item API lookups (e.g. preflight price checks) that would otherwise
/// run as a sequential N+1 loop, without overwhelming the API with unbounded concurrency.
public func boundedConcurrentMap<T: Sendable, R: Sendable>(
  _ items: [T], maxConcurrent: Int = 6, _ transform: @escaping @Sendable (T) async throws -> R
) async throws -> [R] {
  try await withThrowingTaskGroup(of: (Int, R).self) { group in
    var results = [R?](repeating: nil, count: items.count)
    var next = 0
    var running = 0
    while next < items.count || running > 0 {
      while running < maxConcurrent, next < items.count {
        let index = next
        let item = items[index]
        group.addTask { (index, try await transform(item)) }
        next += 1
        running += 1
      }
      if let (index, value) = try await group.next() {
        results[index] = value
        running -= 1
      }
    }
    return results.map { $0! }
  }
}
