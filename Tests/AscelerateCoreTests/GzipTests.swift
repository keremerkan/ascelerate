import Foundation
import Testing
import zlib
@testable import AscelerateCore

@Suite struct GzipTests {
  /// One gzip member, as gzip writes it: a header (with a file name, FNAME, and optionally an
  /// extra field, FEXTRA), the DEFLATE stream, the CRC-32 and the length.
  private func member(_ body: Data, name: String? = "report.csv", extra: Data? = nil) throws -> Data {
    var flags: UInt8 = 0
    if name != nil { flags |= 0x08 }
    if extra != nil { flags |= 0x04 }
    var data = Data([0x1F, 0x8B, 8, flags, 0, 0, 0, 0, 0, 0x03])
    if let extra {
      withUnsafeBytes(of: UInt16(extra.count).littleEndian) { data.append(contentsOf: $0) }
      data.append(extra)
    }
    if let name { data.append(Data(name.utf8) + [0]) }
    // Foundation's zlib compression is a raw DEFLATE stream.
    data.append(try (body as NSData).compressed(using: .zlib) as Data)
    let crc = body.withUnsafeBytes { UInt32(zlib.crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt($0.count))) }
    withUnsafeBytes(of: crc.littleEndian) { data.append(contentsOf: $0) }
    withUnsafeBytes(of: UInt32(body.count).littleEndian) { data.append(contentsOf: $0) }
    return data
  }

  private func rows(_ count: Int, _ tag: String) -> Data {
    Data((0..<count).map { "2026-10-\($0 % 28 + 1)\t\(tag)\t\($0)\n" }.joined().utf8)
  }

  @Test func toFileMatchesInMemory() throws {
    let body = rows(60_000, "TR")
    let zipped = try member(body)
    #expect(try Gzip.decompress(zipped) == body)
    let url = URL.temporaryDirectory.appending(path: "gzip-test-\(UUID().uuidString).csv")
    defer { try? FileManager.default.removeItem(at: url) }
    try Gzip.decompress(zipped, to: url)
    #expect(try Data(contentsOf: url) == body)
  }

  @Test func everyMemberIsRead() throws {
    let (a, b, c) = (rows(2_000, "A"), rows(3_000, "B"), rows(10, "C"))
    let two = try member(a) + member(b)
    #expect(try Gzip.decompress(two) == a + b)
    #expect(try Gzip.memberCount(two) == 2)
    // A later member with its own header fields (FEXTRA and FNAME), and one without a name.
    let three = try member(a) + member(b, name: "second.csv", extra: Data([1, 2, 3, 4])) + member(c, name: nil)
    #expect(try Gzip.decompress(three) == a + b + c)
    #expect(try Gzip.memberCount(three) == 3)
    let url = URL.temporaryDirectory.appending(path: "gzip-members-\(UUID().uuidString).csv")
    defer { try? FileManager.default.removeItem(at: url) }
    try Gzip.decompress(three, to: url)
    #expect(try Data(contentsOf: url) == a + b + c)
  }

  @Test func aBadTrailerOnAnyMemberThrows() throws {
    var first = try member(rows(500, "A"))
    first[first.count - 8] ^= 0xFF  // the first member's CRC
    #expect(throws: Gzip.Damaged.self) { try Gzip.decompress(first) }
    var two = try member(rows(500, "A")) + member(rows(500, "B"))
    two[two.count - 1] ^= 0x01  // the second member's length
    #expect(throws: Gzip.Damaged.self) { try Gzip.decompress(two) }
    let url = URL.temporaryDirectory.appending(path: "gzip-damaged-\(UUID().uuidString).csv")
    #expect(throws: Gzip.Damaged.self) { try Gzip.decompress(two, to: url) }
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test func dataAfterAMemberThatIsntOneIsRefused() throws {
    let zipped = try member(rows(500, "A")) + Data("trailing garbage".utf8)
    #expect(throws: Gzip.Damaged.self) { try Gzip.decompress(zipped) }
  }

  @Test func aCutShortStreamThrows() throws {
    let zipped = try member(rows(5_000, "A"))
    #expect(throws: (any Error).self) { try Gzip.decompress(zipped.prefix(zipped.count / 2)) }
    #expect(throws: (any Error).self) { try Gzip.decompress(zipped.dropLast(4)) }
  }

  @Test func refusesWhatIsntGzip() {
    #expect(throws: Gzip.GzipError.self) { try Gzip.decompress(Data(repeating: 7, count: 40)) }
  }
}
