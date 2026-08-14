import AppStoreConnect
import ArgumentParser
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
    let config = try Config.load()
    let keyPath = expandPath(config.privateKeyPath)

    guard FileManager.default.fileExists(atPath: keyPath) else {
      throw ConfigError.missingPrivateKey(keyPath)
    }

    let privateKey = try JWT.PrivateKey(contentsOf: URL(fileURLWithPath: keyPath))
    var jwt = JWT(
      keyID: config.keyId,
      issuerID: config.issuerId,
      expiryDuration: 20 * 60,
      privateKey: privateKey
    )
    let token = try jwt.token()

    var request = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com/v1/apps?limit=1")!)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ValidationError("Unexpected response.")
    }

    guard http.statusCode >= 200, http.statusCode < 300 else {
      throw ValidationError("API returned HTTP \(http.statusCode).")
    }

    guard let header = http.value(forHTTPHeaderField: "X-Rate-Limit") else {
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
