import Foundation
import HTTPTypes
import Testing
@testable import ASCKit

@Suite struct PagingTests {
  let next = "https://api.appstoreconnect.apple.com/v1/appAssetLibraries/1/images?include=placements&sort=-createdDate&cursor=200%3A650&limit=200"

  @Test func offsetCursorGivesEveryLaterPage() throws {
    let links = try #require(ASCPaging.offsetLinks(after: next))
    #expect(links.count == 3)
    #expect(links.map { URLComponents(string: $0)?.queryItems?.first { $0.name == "cursor" }?.value } == ["200:650", "400:650", "600:650"])
    #expect(links.allSatisfy { $0.contains("include=placements&sort=-createdDate&") && $0.hasSuffix("&limit=200") })
  }

  @Test func otherCursorsAreFollowedOneByOne() {
    #expect(ASCPaging.offsetLinks(after: next.replacingOccurrences(of: "200%3A650", with: "eyJvZmZzZXQiOjIwMH0")) == nil)
    #expect(ASCPaging.offsetLinks(after: "https://api.appstoreconnect.apple.com/v1/apps?limit=200") == nil)
  }

  @Test func pagesArriveInOrder() async throws {
    actor Received {
      var pages: [Int] = []
      func add(_ page: Int) { pages.append(page) }
    }
    let received = Received()
    let total = 1_000
    let pages = try await ASCPaging.allPagesConcurrently(
      next: { $0 == 0 ? "https://example.com/list?cursor=100%3A\(total)" : nil },
      received: { await received.add($0) }
    ) {
      guard let url = ASCPaging.nextPageURL else { return 0 }
      let offset = Int(URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first!.value!.split(separator: ":")[0])!
      // Later pages finish first, to check the order still holds.
      try await Task.sleep(for: .milliseconds(total - offset))
      return offset
    }
    #expect(pages == Array(stride(from: 0, to: total, by: 100)))
    #expect(await received.pages == pages)
  }

  /// A next page goes to the same server: its path is sent after the server URL's own, once.
  @Test(arguments: [
    ("https://api.appstoreconnect.apple.com", "https://api.appstoreconnect.apple.com/v1/apps?cursor=Mg"),
    ("https://mock.example.com/asc", "https://mock.example.com/asc/v1/apps?cursor=Mg"),
    ("https://mock.example.com/asc/", "https://mock.example.com/asc/v1/apps?cursor=Mg"),
  ])
  func nextPagePathAfterServerPath(server: String, next: String) async throws {
    let base = try #require(URL(string: server))
    let sent = try await ASCPaging.$nextPageURL.withValue(URL(string: next)) {
      try await PagingMiddleware().intercept(
        HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/v1/apps"), body: nil, baseURL: base,
        operationID: "appsGetCollection"
      ) { request, _, _ in (HTTPResponse(status: .ok, headerFields: [.location: request.path ?? ""]), nil) }
    }
    #expect(sent.0.headerFields[.location] == "/v1/apps?cursor=Mg")
  }
}
