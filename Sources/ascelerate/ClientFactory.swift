import ASCKit
import Foundation

enum ClientFactory {
  /// `--dry-run` or `ASCELERATE_DRY_RUN=1`: reads go out, every write is printed instead of sent.
  static var isDryRun: Bool { dryRunFlag || ProcessInfo.processInfo.environment["ASCELERATE_DRY_RUN"] == "1" }

  /// An App Store Connect client (ASCKit, generated from Apple's spec). It waits out the hourly
  /// API limit (see `rateLimitWait`) unless `waitsForRateLimit` is false.
  static func makeClient(waitsForRateLimit: Bool = true) throws -> ASCClient {
    if !autoConfirm {
      checkForUpdates()
    }
    let config = try Config.load()
    let keyPath = expandPath(config.privateKeyPath)

    guard FileManager.default.fileExists(atPath: keyPath) else {
      throw ConfigError.missingPrivateKey(keyPath)
    }

    return try .appStoreConnect(
      credentials: ASCCredentials(
        keyID: config.keyId,
        issuerID: config.issuerId,
        privateKeyPEM: String(contentsOfFile: keyPath, encoding: .utf8)
      ),
      dryRun: isDryRun,
      rateLimitWait: waitsForRateLimit ? rateLimitWait : nil
    )
  }

  /// Waiting for the hourly API limit, capped by `ASCELERATE_MAX_RATE_LIMIT_WAIT` (seconds in
  /// total for the run; 0 fails at the first 429 as before).
  private static var rateLimitWait: ASCRateLimitWait {
    let cap = ProcessInfo.processInfo.environment["ASCELERATE_MAX_RATE_LIMIT_WAIT"].flatMap(TimeInterval.init)
    return ASCRateLimitWait(maxTotalWait: cap) { RateLimitNotice.shared.update(resumeAt: $0) }
  }
}

/// Tells the user the run is waiting for App Store Connect's hourly API limit, on stderr so
/// stdout (JSON, piped output) stays clean: a live countdown on a terminal, one line otherwise.
final class RateLimitNotice: @unchecked Sendable {
  static let shared = RateLimitNotice()

  private let lock = NSLock()
  private var ticker: Task<Void, Never>?
  private let isTerminal = isatty(STDERR_FILENO) != 0

  func update(resumeAt: Date?) {
    lock.withLock {
      ticker?.cancel()
      ticker = nil
      guard let resumeAt else {
        write(isTerminal ? "\r\u{1B}[KContinuing.\n" : "Continuing.\n")
        return
      }
      let time = resumeAt.formatted(date: .omitted, time: .shortened)
      write("\nApp Store Connect's hourly API limit is used up. Waiting until \(time) to continue; press Ctrl-C to stop.\n")
      guard isTerminal else { return }
      ticker = Task { [weak self] in
        while !Task.isCancelled {
          let left = max(0, Int(resumeAt.timeIntervalSinceNow))
          self?.write(String(format: "\r\u{1B}[K%d:%02d left", left / 60, left % 60))
          try? await Task.sleep(for: .seconds(1))
        }
      }
    }
  }

  private func write(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
  }
}
