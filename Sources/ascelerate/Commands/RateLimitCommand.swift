import ArgumentParser
import ASCKit
import Foundation

struct RateLimitCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "rate-limit",
    abstract: "Show API rate limit status."
  )

  @OptionGroup var jsonOption: JSONOption

  private struct RateLimit: Encodable {
    let limit: Int
    let used: Int
    let remaining: Int
  }

  func run() async throws {
    jsonOption.activate()
    // Reports the limit; never waits for it.
    let client = try ClientFactory.makeClient(waitsForRateLimit: false)
    let rateLimitHeader = try await ASCRateLimit.header {
      try await client.appsGetCollection(query: .init(limit: 1)).ok
    }

    guard let header = rateLimitHeader else {
      if jsonOption.json { throw ValidationError("No rate limit header in response.") }
      print("No rate limit header in response.")
      return
    }

    // Parse "user-hour-lim:3500;user-hour-rem:500;"
    var values: [String: Int] = [:]
    for part in header.components(separatedBy: ";") where !part.isEmpty {
      let kv = part.components(separatedBy: ":")
      if kv.count == 2, let val = Int(kv[1]) {
        values[kv[0]] = val
      }
    }

    guard let limit = values["user-hour-lim"],
          let remaining = values["user-hour-rem"] else {
      if jsonOption.json { throw ValidationError("Could not parse rate limit header: \(header)") }
      print("Could not parse rate limit header: \(header)")
      return
    }

    let used = limit - remaining

    if jsonOption.json {
      try printJSON(RateLimit(limit: limit, used: used, remaining: remaining))
      return
    }

    let pct = limit > 0 ? Int(Double(remaining) / Double(limit) * 100) : 0

    print("Hourly limit: \(limit) requests (rolling window)")
    print("Used:         \(used)")
    print("Remaining:    \(remaining) (\(pct)%)")
  }
}
