import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import ASCKit

/// Records what the middleware announces.
final class Notices: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [Date?] = []

  var all: [Date?] { lock.withLock { values } }
  func add(_ value: Date?) { lock.withLock { values.append(value) } }
}

/// Holds callers until `count` have arrived, then lets them all through (and every later one).
actor Barrier {
  private let count: Int
  private var arrived = 0
  private var waiting: [CheckedContinuation<Void, Never>] = []

  init(count: Int) {
    self.count = count
  }

  func arrive() async {
    arrived += 1
    if arrived >= count {
      waiting.forEach { $0.resume() }
      waiting = []
      return
    }
    await withCheckedContinuation { waiting.append($0) }
  }
}

/// A fake App Store Connect that answers 429 (with `Retry-After`) a given number of times, then 200.
final class FakeServer: @unchecked Sendable {
  private let lock = NSLock()
  private var limited: Int
  private(set) var requests = 0
  let retryAfter: String

  init(limited: Int, retryAfter: String = "1") {
    self.limited = limited
    self.retryAfter = retryAfter
  }

  func respond() -> (HTTPResponse, HTTPBody?) {
    lock.withLock {
      requests += 1
      guard limited > 0 else { return (HTTPResponse(status: .ok), nil) }
      limited -= 1
      var response = HTTPResponse(status: .tooManyRequests)
      response.headerFields[.retryAfter] = retryAfter
      return (response, nil)
    }
  }
}

@Suite struct RateLimitWaitTests {
  let request = HTTPRequest(method: .get, scheme: "https", authority: "api.example.com", path: "/v1/apps")

  func middleware(cap: TimeInterval?, notices: Notices) -> RateLimitWaitMiddleware {
    RateLimitWaitMiddleware(
      policy: ASCRateLimitWait(maxTotalWait: cap) { notices.add($0) }, gate: RateLimitGate())
  }

  @Test func waitsForRetryAfterThenSendsAgain() async throws {
    let notices = Notices()
    let server = FakeServer(limited: 1)
    let started = Date()
    let (response, _) = try await middleware(cap: nil, notices: notices).intercept(
      request, body: nil, baseURL: URL(string: "https://api.example.com")!, operationID: "test"
    ) { _, _, _ in server.respond() }
    #expect(response.status == .ok)
    #expect(server.requests == 2)
    #expect(Date().timeIntervalSince(started) >= 0.9)
    // One "waiting until" notice, then one "continuing".
    #expect(notices.all.count == 2)
    #expect(notices.all.first! != nil)
    #expect(notices.all.last! == nil)
  }

  @Test func capOfZeroReturnsTheFirst429() async throws {
    let notices = Notices()
    let server = FakeServer(limited: 1)
    let (response, _) = try await middleware(cap: 0, notices: notices).intercept(
      request, body: nil, baseURL: URL(string: "https://api.example.com")!, operationID: "test"
    ) { _, _, _ in server.respond() }
    #expect(response.status == .tooManyRequests)
    #expect(server.requests == 1)
    #expect(notices.all.isEmpty)
  }

  @Test func capCoversTheWholeRun() async throws {
    // Two 1-second waits don't fit a 1.5-second cap: the second 429 is returned.
    let notices = Notices()
    let server = FakeServer(limited: 2)
    let (response, _) = try await middleware(cap: 1.5, notices: notices).intercept(
      request, body: nil, baseURL: URL(string: "https://api.example.com")!, operationID: "test"
    ) { _, _, _ in server.respond() }
    #expect(response.status == .tooManyRequests)
    #expect(server.requests == 2)
  }

  @Test func concurrentRequestsShareOneWaitAndOneNotice() async throws {
    let notices = Notices()
    let server = FakeServer(limited: 4)
    let waiting = middleware(cap: nil, notices: notices)
    let url = URL(string: "https://api.example.com")!
    let request = request
    // All four are sent before any 429 comes back, as concurrent requests are: a task that
    // started late would otherwise go out after the wait and start a second one.
    let sent = Barrier(count: 4)
    let statuses = try await withThrowingTaskGroup(of: HTTPResponse.Status.self) { group in
      for _ in 0..<4 {
        group.addTask {
          try await waiting.intercept(request, body: nil, baseURL: url, operationID: "test") { _, _, _ in
            await sent.arrive()
            return server.respond()
          }.0.status
        }
      }
      return try await group.reduce(into: []) { $0.append($1) }
    }
    #expect(statuses.allSatisfy { $0 == .ok })
    #expect(notices.all.compactMap { $0 }.count == 1)
    #expect(notices.all.filter { $0 == nil }.count == 1)
  }

  @Test func longerWaitThanMaxWaitIsReturned() async throws {
    // A spent hourly quota asks for most of an hour: returned at once rather than waited out.
    let notices = Notices()
    let server = FakeServer(limited: 1, retryAfter: "2186")
    let (response, _) = try await RateLimitWaitMiddleware(
      policy: ASCRateLimitWait(maxTotalWait: nil, maxWait: 60) { notices.add($0) }, gate: RateLimitGate()
    ).intercept(
      request, body: nil, baseURL: URL(string: "https://api.example.com")!, operationID: "test"
    ) { _, _, _ in server.respond() }
    #expect(response.status == .tooManyRequests)
    #expect(server.requests == 1)
    #expect(notices.all.isEmpty)
  }

  @Test func pacingAllowsABurstThenSpacesRequests() async throws {
    let pacing = PacingMiddleware(pacing: ASCRequestPacing(burst: 3, perSecond: 10), gate: PacingGate())
    let server = FakeServer(limited: 0)
    let started = Date()
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<8 {
        group.addTask {
          _ = try await pacing.intercept(
            request, body: nil, baseURL: URL(string: "https://api.example.com")!, operationID: "test"
          ) { _, _, _ in server.respond() }
        }
      }
      try await group.waitForAll()
    }
    // Three at once, then five more a tenth of a second apart.
    let elapsed = Date().timeIntervalSince(started)
    #expect(server.requests == 8)
    #expect(elapsed >= 0.45 && elapsed < 1.5)
  }

  @Test func pacingLetsOtherRequestsGoAheadOfBackgroundOnes() async throws {
    let pacing = PacingMiddleware(pacing: ASCRequestPacing(burst: 1, perSecond: 20), gate: PacingGate())
    let order = Order()
    try await withThrowingTaskGroup(of: Void.self) { group in
      // Ten background requests queue up first; the one that comes after them goes next.
      for index in 0..<10 {
        group.addTask {
          try await ASCRequestPacing.$isBackground.withValue(true) {
            _ = try await pacing.intercept(
              request, body: nil, baseURL: URL(string: "https://api.example.com")!, operationID: "test"
            ) { _, _, _ in order.add("background \(index)"); return (HTTPResponse(status: .ok), nil) }
          }
        }
      }
      try await Task.sleep(for: .milliseconds(30))
      group.addTask {
        _ = try await pacing.intercept(
          request, body: nil, baseURL: URL(string: "https://api.example.com")!, operationID: "test"
        ) { _, _, _ in order.add("page"); return (HTTPResponse(status: .ok), nil) }
      }
      try await group.waitForAll()
    }
    let all = order.all
    #expect(all.count == 11)
    // The burst's one request and at most one more background request went before it.
    #expect((all.firstIndex(of: "page") ?? 99) <= 2)
  }

  @Test func pacingCancelsAWaitingRequest() async throws {
    let pacing = PacingMiddleware(pacing: ASCRequestPacing(burst: 1, perSecond: 1), gate: PacingGate())
    let send: @Sendable () async throws -> Void = {
      _ = try await pacing.intercept(
        request, body: nil, baseURL: URL(string: "https://api.example.com")!, operationID: "test"
      ) { _, _, _ in (HTTPResponse(status: .ok), nil) }
    }
    try await send()
    let waiting = Task { try await send() }
    try await Task.sleep(for: .milliseconds(50))
    waiting.cancel()
    await #expect(throws: CancellationError.self) { try await waiting.value }
  }
}

/// What reached the server, in order.
private final class Order: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [String] = []

  func add(_ item: String) {
    lock.withLock { items.append(item) }
  }

  var all: [String] { lock.withLock { items } }
}
