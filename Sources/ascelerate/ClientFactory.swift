import ArgumentParser
import ASCKit
import Foundation

enum ClientFactory {
  /// `--dry-run` or `ASCELERATE_DRY_RUN` set to 1, true, yes or on: reads go out, every write is
  /// printed instead of sent.
  static var isDryRun: Bool { dryRunFlag || dryRunFromEnvironment == true }

  /// `ASCELERATE_DRY_RUN` read once: true for 1/true/yes/on, false for 0/false/no/off or empty or
  /// unset, nil for anything else (refused by `checkDryRunEnvironment`, Kerem 2026-11-26: `true`
  /// used to run live with no warning).
  static let dryRunFromEnvironment: Bool? = {
    guard let raw = ProcessInfo.processInfo.environment["ASCELERATE_DRY_RUN"] else { return false }
    switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
      case "1", "true", "yes", "on": return true
      case "", "0", "false", "no", "off": return false
      default: return nil
    }
  }()

  /// Refuses an `ASCELERATE_DRY_RUN` value that is neither on nor off, before anything runs.
  static func checkDryRunEnvironment() throws {
    guard dryRunFromEnvironment == nil else { return }
    let raw = ProcessInfo.processInfo.environment["ASCELERATE_DRY_RUN"] ?? ""
    throw ValidationError("ASCELERATE_DRY_RUN='\(raw)' is neither on (1, true, yes, on) nor off (0, false, no, off); nothing was run.")
  }

  /// An App Store Connect client (ASCKit, generated from Apple's spec). It waits out the hourly
  /// API limit (see `rateLimitWait`) unless `waitsForRateLimit` is false.
  static func makeClient(waitsForRateLimit: Bool = true) throws -> ASCClient {
    // Not in output read by a program (--json, --json-events) or with -y (scripts and agents).
    if !autoConfirm, !jsonMode, !EventOutput.emitsEvents {
      checkForUpdates()
    }
    let key = try APICredentials.current()
    return try .appStoreConnect(
      credentials: ASCCredentials(keyID: key.keyID, issuerID: key.issuerID, privateKeyPEM: try key.privateKey()),
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
    try? FileHandle.standardError.write(contentsOf: Data(text.utf8))
  }
}
