import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import ASCKit

/// The dry-run and write gates: every write stopped (or gated), reads and Apple's calculations through.
@Suite struct GateTests {
  final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func add() { lock.withLock { value += 1 } }
  }

  func send(_ middleware: some ClientMiddleware, _ method: HTTPRequest.Method, operationID: String) async throws -> Int {
    let calls = Calls()
    let request = HTTPRequest(method: method, scheme: "https", authority: "api.example.com", path: "/v1/things")
    _ = try await middleware.intercept(request, body: nil, baseURL: URL(string: "https://api.example.com")!, operationID: operationID) { _, _, _ in
      calls.add()
      return (HTTPResponse(status: .ok), nil)
    }
    return calls.count
  }

  @Test func dryRunStopsEveryWriteAndLetsReadsAndCalculationsThrough() async throws {
    let gate = DryRunMiddleware()
    #expect(try await send(gate, .get, operationID: "apps_getCollection") == 1)
    for method in [HTTPRequest.Method.post, .patch, .put, .delete] {
      await #expect(throws: ASCDryRunStop.self) { _ = try await send(gate, method, operationID: "apps_updateInstance") }
    }
    for id in ASCDryRun.calculations {
      #expect(try await send(gate, .post, operationID: id) == 1, "\(id)")
    }
  }

  @Test func theWriteGateSeesWritesOnly() async throws {
    let seen = Calls()
    let gate = WriteGateMiddleware { _, _ in seen.add() }
    _ = try await send(gate, .get, operationID: "apps_getCollection")
    _ = try await send(gate, .post, operationID: "subscriptionPriceChangePreviews_createInstance")
    #expect(seen.count == 0)
    _ = try await send(gate, .delete, operationID: "apps_deleteInstance")
    _ = try await send(gate, .patch, operationID: "apps_updateInstance")
    #expect(seen.count == 2)
  }

  /// A calculation's ID that no operation has any more would make that POST a write the gates stop.
  @Test func everyCalculationIsAnOperation() {
    let ids: Set<String> = [
      Operations.SubscriptionPriceTierEqualizationsCreateInstance.id,
      Operations.SubscriptionPriceChangePreviewsCreateInstance.id,
      Operations.GameCenterMatchmakingRuleSetTestsCreateInstance.id,
    ]
    #expect(ids == ASCDryRun.calculations)
  }
}
