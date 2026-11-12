import CryptoKit
import Foundation
import Testing
@testable import AscelerateCore

@Suite struct ZipReaderTests {
  struct Entry {
    var name: String
    var content: Data
    var deflate = false
    /// The unpacked size the entry declares, when it should lie.
    var declaredSize: Int?
    var flags: UInt16 = 0
    var method: UInt16?
    /// The CRC-32 the entry declares, when it should lie.
    var crc: UInt32?
    /// The compressed size the entry declares, when it should lie (stored entries).
    var compressedSize: Int?
    /// Points the entry at an earlier entry's data instead of its own.
    var sharesDataOf: Int?
  }

  /// A zip archive of `entries`, with each file's CRC-32.
  private func zip(_ entries: [Entry]) throws -> Data {
    var offsets: [UInt32] = []
    var archive = Data()
    var directory = Data()
    for entry in entries {
      let body = entry.deflate ? try (entry.content as NSData).compressed(using: .zlib) as Data : entry.content
      let size = UInt32(entry.declaredSize ?? entry.content.count)
      let compressedSize = UInt32(entry.compressedSize ?? body.count)
      let name = Data(entry.name.utf8)
      let crc = entry.crc ?? ZipReader.crc32(entry.content)
      let method: UInt16 = entry.method ?? (entry.deflate ? 8 : 0)
      let offset: UInt32
      if let shared = entry.sharesDataOf {
        offset = offsets[shared]
      } else {
        offset = UInt32(archive.count)
        let local: [Data] = [
          le32(0x0403_4b50), le16(20), le16(entry.flags), le16(method), le16(0), le16(0),
          le32(crc), le32(compressedSize), le32(size), le16(UInt16(name.count)), le16(0), name, body,
        ]
        local.forEach { archive.append($0) }
      }
      offsets.append(offset)
      let central: [Data] = [
        le32(0x0201_4b50), le16(20), le16(20), le16(entry.flags), le16(method), le16(0), le16(0),
        le32(crc), le32(compressedSize), le32(size), le16(UInt16(name.count)),
        le16(0), le16(0), le16(0), le16(0), le32(0), le32(offset), name,
      ]
      central.forEach { directory.append($0) }
    }
    let directoryOffset = UInt32(archive.count)
    archive += directory
    let endRecord: [Data] = [
      le32(0x0605_4b50), le16(0), le16(0), le16(UInt16(entries.count)), le16(UInt16(entries.count)),
      le32(UInt32(directory.count)), le32(directoryOffset), le16(0),
    ]
    endRecord.forEach { archive.append($0) }
    return archive
  }

  private func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
  private func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

  private let text = Data(String(repeating: "Xcode Cloud log line\n", count: 200).utf8)

  @Test func readsStoredAndDeflatedEntriesAndSkipsFolders() throws {
    let files = try ZipReader.files(in: zip([
      Entry(name: "logs/", content: Data()),
      Entry(name: "logs/stored.txt", content: Data("plain".utf8)),
      Entry(name: "logs/deflated.log", content: text, deflate: true),
      Entry(name: "logs/empty.log", content: Data(), deflate: true),
    ]))
    #expect(files.map(\.path) == ["logs/stored.txt", "logs/deflated.log", "logs/empty.log"])
    #expect(files[0].data == Data("plain".utf8))
    #expect(files[1].data == text)
    #expect(files[2].data.isEmpty)
  }

  @Test func refusesWhatIsntAZip() {
    #expect(throws: ZipReader.ZipError.notAZip) { try ZipReader.files(in: Data("not a zip at all".utf8)) }
    #expect(throws: ZipReader.ZipError.notAZip) { try ZipReader.files(in: Data()) }
  }

  @Test func refusesTruncatedArchivesWithoutTrapping() throws {
    let archive = try zip([Entry(name: "a.log", content: text, deflate: true), Entry(name: "b.txt", content: text)])
    // Cut in every part: the entries, the central directory, the end record.
    for cut in stride(from: 1, to: archive.count, by: 7) {
      #expect(throws: ZipReader.ZipError.self) { try ZipReader.files(in: archive.prefix(cut)) }
    }
    // The central directory pointing past the data.
    var damaged = archive
    let end = damaged.count - 22
    damaged.replaceSubrange((end + 16)..<(end + 20), with: le32(0xFFFF_FFF0))
    #expect(throws: ZipReader.ZipError.self) { try ZipReader.files(in: damaged) }
  }

  @Test func refusesAnEntryUnpackingToMoreThanItDeclares() throws {
    let archive = try zip([Entry(name: "bomb.log", content: text, deflate: true, declaredSize: 100)])
    #expect(throws: ZipReader.ZipError.notAZip) { try ZipReader.files(in: archive) }
    let short = try zip([Entry(name: "short.log", content: text, deflate: true, declaredSize: text.count + 50)])
    #expect(throws: ZipReader.ZipError.notAZip) { try ZipReader.files(in: short) }
  }

  @Test func refusesEncryptionAndUnknownMethods() throws {
    let encrypted = try zip([Entry(name: "secret.txt", content: text, flags: 1)])
    #expect(throws: ZipReader.ZipError.unsupported("encryption")) { try ZipReader.files(in: encrypted) }
    let bzip2 = try zip([Entry(name: "a.txt", content: text, method: 12)])
    #expect(throws: ZipReader.ZipError.unsupported("compression method 12")) { try ZipReader.files(in: bzip2) }
  }

  @Test func refusesInconsistentEntries() throws {
    // A stored entry whose compressed and unpacked sizes differ.
    let stored = try zip([Entry(name: "a.txt", content: text, declaredSize: text.count - 1)])
    #expect(throws: ZipReader.ZipError.notAZip) { try ZipReader.files(in: stored) }
    // A wrong CRC-32: the same length, other bytes.
    let crc = try zip([Entry(name: "a.log", content: text, deflate: true, crc: 0x1234_5678)])
    #expect(throws: ZipReader.ZipError.notAZip) { try ZipReader.files(in: crc) }
    // A local header without its signature.
    var archive = try zip([Entry(name: "a.txt", content: Data("1".utf8))])
    archive.replaceSubrange(0..<4, with: le32(0x0000_0000))
    #expect(throws: ZipReader.ZipError.notAZip) { try ZipReader.files(in: archive) }
  }

  @Test func refusesASizeDeflateCantReachBeforeAllocatingIt() throws {
    // 1 GB declared for a few KB of DEFLATE: refused at once, without its room allocated.
    let archive = try zip([Entry(name: "bomb.log", content: text, deflate: true, declaredSize: 1 << 30)])
    let started = ContinuousClock.now
    #expect(throws: ZipReader.ZipError.notAZip) { try ZipReader.files(in: archive) }
    #expect(ContinuousClock.now - started < .milliseconds(200))
  }

  @Test func refusesEntriesSharingOneFilesData() throws {
    var entries = [Entry(name: "a.log", content: text, deflate: true)]
    for index in 1...50 { entries.append(Entry(name: "copy\(index).log", content: text, deflate: true, sharesDataOf: 0)) }
    #expect(throws: ZipReader.ZipError.notAZip) { try ZipReader.files(in: zip(entries)) }
  }

  @Test func refusesFilesWhoseBytesOverlap() throws {
    // a.txt's data made to run on through b.txt's header and data, its sizes and CRC-32 made to fit:
    // every entry is valid on its own, but the bytes are read twice.
    var archive = try zip([Entry(name: "a.txt", content: Data("1".utf8)), Entry(name: "b.txt", content: text)])
    let aData = 30 + 5
    let bEnd = aData + 1 + 30 + 5 + text.count
    let span = archive.subdata(in: aData..<bEnd)
    let crc = le32(ZipReader.crc32(span)), length = le32(UInt32(span.count))
    archive.replaceSubrange(14..<18, with: crc)
    archive.replaceSubrange(18..<22, with: length)
    archive.replaceSubrange(22..<26, with: length)
    let directory = bEnd
    archive.replaceSubrange((directory + 16)..<(directory + 20), with: crc)
    archive.replaceSubrange((directory + 20)..<(directory + 24), with: length)
    archive.replaceSubrange((directory + 24)..<(directory + 28), with: length)
    #expect(throws: ZipReader.ZipError.notAZip) { try ZipReader.files(in: archive) }
  }

  @Test func refusesAnArchiveOverItsTotalBeforeUnpackingAny() throws {
    let entries = (1...20).map { Entry(name: "log\($0).log", content: text, deflate: true) }
    let archive = try zip(entries)
    #expect(throws: ZipReader.ZipError.totalTooLarge(limit: text.count * 10)) {
      try ZipReader.files(in: archive, limits: .init(totalSize: text.count * 10))
    }
  }

  @Test func refusesZip64() throws {
    var archive = try zip([Entry(name: "a.txt", content: Data("1".utf8))])
    let end = archive.count - 22
    archive.replaceSubrange((end + 8)..<(end + 12), with: le16(0xFFFF) + le16(0xFFFF))
    archive.replaceSubrange((end + 16)..<(end + 20), with: le32(0xFFFF_FFFF))
    #expect(throws: ZipReader.ZipError.unsupported("ZIP64")) { try ZipReader.files(in: archive) }
  }

  @Test func appliesItsLimits() throws {
    let archive = try zip([
      Entry(name: "one.txt", content: Data("1".utf8)),
      Entry(name: "two.log", content: text, deflate: true),
    ])
    #expect(throws: ZipReader.ZipError.archiveTooLarge(limit: 64)) {
      try ZipReader.files(in: archive, limits: .init(archiveSize: 64))
    }
    #expect(throws: ZipReader.ZipError.tooManyEntries(limit: 1)) {
      try ZipReader.files(in: archive, limits: .init(entries: 1))
    }
    #expect(throws: ZipReader.ZipError.entryTooLarge(path: "two.log", limit: 1_000)) {
      try ZipReader.files(in: archive, limits: .init(entrySize: 1_000))
    }
    #expect(throws: ZipReader.ZipError.totalTooLarge(limit: text.count)) {
      try ZipReader.files(in: archive, limits: .init(totalSize: text.count))
    }
    // Folders don't count as entries, and limits the archive meets let it through.
    let withFolder = try zip([Entry(name: "dir/", content: Data()), Entry(name: "dir/one.txt", content: Data("1".utf8))])
    #expect(try ZipReader.files(in: withFolder, limits: .init(entries: 1)).count == 1)
    #expect(try ZipReader.files(in: archive, limits: .init(archiveSize: archive.count, entries: 2, entrySize: text.count, totalSize: text.count + 1)).count == 2)
  }

  /// An archive made by /usr/bin/zip (Info-ZIP, as Xcode Cloud's log bundles are): a stored file, a
  /// folder and a deflated log, read as zip wrote them.
  @Test func readsAnArchiveZipMade() throws {
    let archive = try #require(Data(base64Encoded: "UEsDBAoAAAAAAFhnbF19DhbaAwAAAAMAAAARABwAY2lfcG9zdF9jbG9uZS5sb2dVVAkAA9eN9WrXjfVqdXgLAAEE9QEAAAQAAAAAb2sKUEsDBAoAAAAAAFhnbF0AAAAAAAAAAAAAAAALABwAeGNvZGVidWlsZC9VVAkAA9eN9WrXjfVqdXgLAAEE9QEAAAQAAAAAUEsDBBQAAAAIAFhnbF0vNWnd3QAAAIMKAAAfABwAeGNvZGVidWlsZC94Y29kZWJ1aWxkLWJ1aWxkLmxvZ1VUCQAD1431ateN9Wp1eAsAAQT1AQAABAAAAACV1jsKAkEMgOFaT+EFlMlrd7X1Clb2rgz4AgWvr41VTPHDlH/3kWS06bAWWYsepO3a98lxsb9fH/3Sb+fV3C+nlWye7z6/lppaTa2WraXWytZT62UbqY2yHVI7lO2Y2rFsp9ROZbtN7bZsW7ZoZfwHjsgJoRNiJwRPiJ4QPiF+QgCFCCoRVDR7RFCJoBJBJYJKBJUIKhFUImhE0IigofVJBI0IGhE0ImhE0IigEUEngk4EnQg6uoBE0ImgE0Engk4EnQgGEQwiGEQwiGCgTwwRDCIYRDCIYBDB4Sf4AVBLAQIeAwoAAAAAAFhnbF19DhbaAwAAAAMAAAARABgAAAAAAAEAAACkgQAAAABjaV9wb3N0X2Nsb25lLmxvZ1VUBQAD1431anV4CwABBPUBAAAEAAAAAFBLAQIeAwoAAAAAAFhnbF0AAAAAAAAAAAAAAAALABgAAAAAAAAAEADtQU4AAAB4Y29kZWJ1aWxkL1VUBQAD1431anV4CwABBPUBAAAEAAAAAFBLAQIeAxQAAAAIAFhnbF0vNWnd3QAAAIMKAAAfABgAAAAAAAEAAACkgZMAAAB4Y29kZWJ1aWxkL3hjb2RlYnVpbGQtYnVpbGQubG9nVVQFAAPXjfVqdXgLAAEE9QEAAAQAAAAAUEsFBgAAAAADAAMADQEAAMkBAAAAAA=="))
    let files = try ZipReader.files(in: archive, limits: .init(archiveSize: archive.count, entries: 2, entrySize: 4_096))
    #expect(files.map(\.path) == ["ci_post_clone.log", "xcodebuild/xcodebuild-build.log"])
    #expect(files[0].data == Data("ok\n".utf8))
    #expect(files[1].data.count == 2_691)
    #expect(SHA256Hex(files[1].data) == "29c5dd2e6ff4d27005c5995fa8d1167884cc9d3570d77c36b944439839032660")
  }

  private func SHA256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
