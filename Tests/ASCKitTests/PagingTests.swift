import Foundation
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
}
