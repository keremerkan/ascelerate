import Foundation
import Testing
@testable import AscelerateCore

@Suite struct GzipTests {
  /// A gzip member with a file name in its header (FNAME), as gzip writes one; the CRC isn't checked.
  private func gzip(_ body: Data) throws -> Data {
    var data = Data([0x1F, 0x8B, 8, 0x08, 0, 0, 0, 0, 0, 0x03])
    data.append(Data("report.csv".utf8) + [0])
    data.append(try (body as NSData).compressed(using: .zlib) as Data)
    data.append(Data(repeating: 0, count: 4))
    withUnsafeBytes(of: UInt32(body.count).littleEndian) { data.append(contentsOf: $0) }
    return data
  }

  @Test func toFileMatchesInMemory() throws {
    var generator = SystemRandomNumberGenerator()
    let rows = (0..<60_000).map { _ in "2026-10-\(Int.random(in: 10...31, using: &generator))\tTR\tiPhone\t\(Int.random(in: 0...999, using: &generator))\n" }
    let body = Data(rows.joined().utf8)
    let zipped = try gzip(body)
    #expect(try Gzip.decompress(zipped) == body)
    let url = URL.temporaryDirectory.appending(path: "gzip-test-\(UUID().uuidString).csv")
    defer { try? FileManager.default.removeItem(at: url) }
    try Gzip.decompress(zipped, to: url)
    #expect(try Data(contentsOf: url) == body)
  }

  @Test func refusesWhatIsntGzip() {
    #expect(throws: Gzip.GzipError.self) { try Gzip.decompress(Data(repeating: 7, count: 40)) }
  }
}
