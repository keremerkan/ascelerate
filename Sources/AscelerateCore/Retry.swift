import ASCKit
import Foundation

/// Whether an error is worth retrying: a server-side failure, or a dropped, timed-out or failed
/// connection (seen live mid-upload: lost connection, timeout, TLS failure). Client-side errors
/// (4xx validation, conflicts) won't fix themselves. HTTP 429 isn't retried here: the client
/// already waited out the hourly limit as long as allowed (`ASCRateLimitWait`), so a 429 that
/// gets this far means waiting was capped.
public func isTransientError(_ error: Error) -> Bool {
  if let ascError = ASCError.from(error) {
    return (500...599).contains(ascError.statusCode)
  }
  guard let urlError = (ascUnderlyingError(error) ?? error) as? URLError else { return false }
  let transientCodes: Set<URLError.Code> = [
    .networkConnectionLost, .timedOut, .secureConnectionFailed, .cannotConnectToHost,
    .notConnectedToInternet, .dnsLookupFailed, .cannotFindHost,
  ]
  return transientCodes.contains(urlError.code)
}

/// Runs an API call, retrying with backoff (2s, then 5s) when the error is transient
/// (see `isTransientError`). Non-transient errors throw immediately; a transient error on the
/// final attempt is thrown as-is. Only wrap calls that are safe to repeat: a POST whose first
/// attempt lost its connection may have been carried out.
public func withTransientRetry<T>(_ operation: () async throws -> T) async throws -> T {
  for delay in [Duration.seconds(2), .seconds(5)] {
    do {
      return try await operation()
    } catch where isTransientError(error) {
      try? await Task.sleep(for: delay)
    }
  }
  return try await operation()
}

/// Runs a write, returning nil instead of failing when dry run stopped it, so a multi-step
/// command goes on to preview its later writes (the stopped request is already printed).
public func unlessDryRunStopped<T>(_ write: () async throws -> T) async throws -> T? {
  do {
    return try await write()
  } catch where ASCDryRunStop.from(error) != nil {
    return nil
  }
}
