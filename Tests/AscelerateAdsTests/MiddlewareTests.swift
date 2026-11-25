import AppleAdsClient
import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import AscelerateAds

/// The Apple Ads middleware against a fake transport: what it retries, and the rate-limit cap.
@Suite struct MiddlewareTests {
  /// A transport answering from a script, counting the requests.
  final class Script: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [Result<HTTPResponse, any Error>]
    private(set) var sent = 0
    init(_ answers: [Result<HTTPResponse, any Error>]) { self.answers = answers }
    func next() throws -> HTTPResponse {
      lock.lock()
      defer { lock.unlock() }
      sent += 1
      return try answers.removeFirst().get()
    }
  }

  /// A network error as the runtime hands it to a middleware: wrapped in its `ClientError`.
  static func dropped() -> any Error {
    ClientError(operationID: "test", operationInput: "", causeDescription: "Transport threw an error.",
      underlyingError: URLError(.networkConnectionLost))
  }

  func run(_ method: HTTPRequest.Method, _ path: String, script: Script, options: Ads.Options = .init()) async throws -> HTTPResponse {
    var middleware = Ads.Middleware(options: options)
    middleware.retryDelay = .zero
    let request = HTTPRequest(method: method, scheme: "https", authority: "api.example.com", path: path)
    return try await middleware.intercept(request, body: nil, baseURL: URL(string: "https://api.example.com")!, operationID: "test") { _, _, _ in
      (try script.next(), nil)
    }.0
  }

  @Test func aReadIsSentAgainAfterAWrappedNetworkError() async throws {
    let script = Script([.failure(Self.dropped()), .success(HTTPResponse(status: .ok))])
    let response = try await run(.post, "/api/v1/campaigns/query", script: script)
    #expect(response.status == .ok)
    #expect(script.sent == 2)
  }

  @Test func aWriteIsNeverSentTwice() async throws {
    let script = Script([.failure(Self.dropped()), .success(HTTPResponse(status: .ok))])
    await #expect(throws: (any Error).self) { try await run(.put, "/api/v1/campaigns/1", script: script) }
    #expect(script.sent == 1)
  }

  @Test func aReadGivesUpAfterThreeAttempts() async throws {
    let script = Script([.failure(Self.dropped()), .failure(Self.dropped()), .failure(Self.dropped()), .success(HTTPResponse(status: .ok))])
    await #expect(throws: (any Error).self) { try await run(.get, "/api/v1/acls", script: script) }
    #expect(script.sent == 3)
  }

  @Test func aCapOfZeroReturnsTheFirst429() async throws {
    var limited = HTTPResponse(status: .tooManyRequests)
    limited.headerFields[HTTPField.Name("Retry-After")!] = "1"
    let script = Script([.success(limited), .success(HTTPResponse(status: .ok))])
    await #expect(throws: AdsError.self) {
      try await run(.get, "/api/v1/acls", script: script, options: .init(maxRateLimitWait: 0))
    }
    #expect(script.sent == 1)
  }

  @Test func signInFailuresNameTheServerNotTheCredentials() {
    var error = AdsError(status: nil, code: nil, message: nil, details: [])
    error.signInStatus = 503
    #expect(error.errorDescription?.contains("sign-in failed (HTTP 503)") == true)
    #expect(error.errorDescription?.contains("credentials") == false)
    error.signInStatus = 401
    #expect(error.errorDescription?.contains("credentials") == true)
  }
}

/// One rate limit wait and the paging stop.
@Suite struct WaitAndPagingTests {
  @Test func aSingleWaitIsBounded() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(Ads.Middleware.singleWait(30, now: now) == 30)
    #expect(Ads.Middleware.singleWait(3600, now: now) == 3600)
    // A reset sent as a time: waited until then within the hour, refused beyond it.
    #expect(Ads.Middleware.singleWait(1_800_000_120, now: now) == 120)
    #expect(Ads.Middleware.singleWait(1_800_009_000, now: now) == nil)
    #expect(Ads.Middleware.singleWait(99_999, now: now) == nil)
  }

  @Test func aFarResetReturnsThe429() async throws {
    var limited = HTTPResponse(status: .tooManyRequests)
    limited.headerFields[HTTPField.Name("RateLimit-Reset")!] = "99999999"
    let script = MiddlewareTests.Script([.success(limited), .success(HTTPResponse(status: .ok))])
    await #expect(throws: AdsError.self) { try await MiddlewareTests().run(.get, "/api/v1/acls", script: script) }
    #expect(script.sent == 1)
  }

  /// Pages served by a script; returns the sizes asked for.
  func read(_ pages: [(rows: Int, total: Int?)], asked: Int = 5000) async throws -> Int {
    var served = pages
    let rows = try await Ads.reportRows { (_: Components.Schemas.RequestPagination) -> (rows: [Int], count: Int?) in
      let page = served.isEmpty ? (rows: 0, total: nil) : served.removeFirst()
      return (Array(repeating: 1, count: page.rows), page.total)
    }
    return rows.count
  }

  @Test func theTotalDecidesWhenApplePagesShort() async throws {
    // Apple serves 1,000 a page although 5,000 were asked: the total keeps it reading.
    #expect(try await read([(1000, 2500), (1000, 2500), (500, 2500)]) == 2500)
  }

  @Test func withoutATotalAShortPageEnds() async throws {
    #expect(try await read([(5000, nil), (20, nil), (5000, nil)]) == 5020)
  }

  @Test func anEmptyPageAlwaysEnds() async throws {
    #expect(try await read([(5000, 99999), (0, 99999), (5000, nil)]) == 5000)
  }
}
