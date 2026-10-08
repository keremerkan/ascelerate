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
    let statuses = try await withThrowingTaskGroup(of: HTTPResponse.Status.self) { group in
      for _ in 0..<4 {
        group.addTask {
          try await waiting.intercept(request, body: nil, baseURL: url, operationID: "test") { _, _, _ in server.respond() }.0.status
        }
      }
      return try await group.reduce(into: []) { $0.append($1) }
    }
    #expect(statuses.allSatisfy { $0 == .ok })
    #expect(notices.all.compactMap { $0 }.count == 1)
    #expect(notices.all.filter { $0 == nil }.count == 1)
  }
}
