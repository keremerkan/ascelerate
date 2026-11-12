import Compression
import Foundation
import zlib

/// Reads the files of a zip archive held in memory: stored and deflated entries (no ZIP64, no
/// encryption), as Xcode Cloud's log bundles have them. Folders are left out. Every read is checked
/// against the data, so a truncated or malformed archive throws `notAZip` rather than trapping, and
/// every file's CRC-32 is checked. What an archive can unpack to is bounded without limits too: a
/// deflated entry is unpacked into the room it declares, a declared size DEFLATE can't reach from
/// its compressed bytes (about 1,032 to 1 at best) is refused before anything is allocated, and no
/// two files' bytes may overlap. So the compressed sizes add up to at most the archive, and the
/// total stays within about a thousand times it. The whole directory is checked before anything
/// is unpacked. `Limits` refuses an archive, an entry count, an entry or a total over a size.
///
/// Paths come back as the archive has them (`../x` included), and two entries with one path both
/// come back: a caller writing files to disk must check them itself.
public enum ZipReader {
  public enum ZipError: LocalizedError, Equatable {
    case notAZip
    case unsupported(String)
    /// The archive is over `Limits.archiveSize`, in bytes.
    case archiveTooLarge(limit: Int)
    /// The archive holds more files than `Limits.entries`.
    case tooManyEntries(limit: Int)
    /// A file in the archive is over `Limits.entrySize` once unpacked, in bytes.
    case entryTooLarge(path: String, limit: Int)
    /// The archive's files together are over `Limits.totalSize` once unpacked, in bytes.
    case totalTooLarge(limit: Int)

    public var errorDescription: String? {
      switch self {
        case .notAZip: "The file isn't a zip archive, or it's damaged."
        case .unsupported(let what): "The zip archive uses \(what), which isn't supported."
        case .archiveTooLarge(let limit): "The zip archive is larger than \(formatBytes(limit))."
        case .tooManyEntries(let limit): "The zip archive holds more than \(limit) files."
        case .entryTooLarge(let path, let limit): "\(path) in the zip archive is larger than \(formatBytes(limit))."
        case .totalTooLarge(let limit): "The zip archive's files come to more than \(formatBytes(limit))."
      }
    }
  }

  /// The most an archive may hold; nil leaves that one open.
  public struct Limits: Sendable, Equatable {
    /// The archive's own size, in bytes. A caller reading a file from disk can compare the file's
    /// size with it first.
    public var archiveSize: Int?
    /// The number of files (folders not counted).
    public var entries: Int?
    /// A file's unpacked size, in bytes.
    public var entrySize: Int?
    /// All files' unpacked sizes together, in bytes.
    public var totalSize: Int?

    public init(archiveSize: Int? = nil, entries: Int? = nil, entrySize: Int? = nil, totalSize: Int? = nil) {
      self.archiveSize = archiveSize
      self.entries = entries
      self.entrySize = entrySize
      self.totalSize = totalSize
    }

    /// No limits beyond the archive's own declared sizes.
    public static let none = Limits()
  }

  /// Each file's path in the archive and its contents, in the archive's order. The whole central
  /// directory is checked first (structure, ZIP64, encryption, methods, sizes, limits, overlaps),
  /// so an archive is refused before anything is unpacked.
  public static func files(in data: Data, limits: Limits = .none) throws -> [(path: String, data: Data)] {
    if let limit = limits.archiveSize, data.count > limit { throw ZipError.archiveTooLarge(limit: limit) }
    let bytes = [UInt8](data)
    return try entries(bytes, limits: limits).map { entry in
      let compressed = try slice(bytes, entry.dataStart, entry.compressedSize)
      let content = entry.method == 0 ? Data(compressed) : try inflate(compressed, size: entry.size)
      guard crc32(content) == entry.crc else { throw ZipError.notAZip }
      return (entry.name, content)
    }
  }

  private struct Entry {
    let name: String
    let method: UInt16
    let crc: UInt32
    let size: Int
    let compressedSize: Int
    /// Where the local header starts, and where its data starts.
    let headerStart: Int
    let dataStart: Int
  }

  /// The archive's files as its central directory lists them, each checked: the central directory
  /// and local headers in bounds and signed, no ZIP64, no encryption, a supported method, sizes
  /// DEFLATE can reach, the limits, and no two files' bytes (local header to data end) overlapping
  /// each other or the central directory. So the compressed sizes add up to at most the archive,
  /// and what it unpacks to stays within about 1,032 times it.
  private static func entries(_ bytes: [UInt8], limits: Limits) throws -> [Entry] {
    // The end of central directory record, searched from the end (a comment can follow it).
    guard bytes.count >= 22,
      let end = stride(from: bytes.count - 22, through: max(0, bytes.count - 22 - 65_535), by: -1)
        .first(where: { (try? uint32(bytes, $0)) == 0x0605_4b50 })
    else { throw ZipError.notAZip }
    let count = Int(try uint16(bytes, end + 10))
    let directorySize = Int(try uint32(bytes, end + 12))
    let directoryStart = Int(try uint32(bytes, end + 16))
    // ZIP64 marks the end record's fields so and puts the real ones in a record of its own.
    guard count != 0xFFFF, directorySize != 0xFFFF_FFFF, directoryStart != 0xFFFF_FFFF else {
      throw ZipError.unsupported("ZIP64")
    }
    var offset = directoryStart
    var entries: [Entry] = []
    var total = 0
    for _ in 0..<count {
      guard try uint32(bytes, offset) == 0x0201_4b50 else { throw ZipError.notAZip }
      let flags = try uint16(bytes, offset + 8)
      let method = try uint16(bytes, offset + 10)
      let crc = try uint32(bytes, offset + 16)
      let compressedSize = Int(try uint32(bytes, offset + 20))
      let size = Int(try uint32(bytes, offset + 24))
      let nameLength = Int(try uint16(bytes, offset + 28))
      let extraLength = Int(try uint16(bytes, offset + 30))
      let commentLength = Int(try uint16(bytes, offset + 32))
      let localOffset = Int(try uint32(bytes, offset + 42))
      let name = String(decoding: try slice(bytes, offset + 46, nameLength), as: UTF8.self)
      offset += 46 + nameLength + extraLength + commentLength
      if name.hasSuffix("/") { continue }
      if let limit = limits.entries, entries.count == limit { throw ZipError.tooManyEntries(limit: limit) }
      guard compressedSize != 0xFFFF_FFFF, size != 0xFFFF_FFFF, localOffset != 0xFFFF_FFFF else {
        throw ZipError.unsupported("ZIP64")
      }
      guard flags & 1 == 0 else { throw ZipError.unsupported("encryption") }
      switch method {
        case 0: guard compressedSize == size else { throw ZipError.notAZip }
        // DEFLATE's best is about 1,032 to 1: a larger declared size is a lie, refused before its
        // room is allocated.
        case 8: guard size <= compressedSize * 1_032 + 64 else { throw ZipError.notAZip }
        default: throw ZipError.unsupported("compression method \(method)")
      }
      if let limit = limits.entrySize, size > limit { throw ZipError.entryTooLarge(path: name, limit: limit) }
      total += size
      if let limit = limits.totalSize, total > limit { throw ZipError.totalTooLarge(limit: limit) }
      guard try uint32(bytes, localOffset) == 0x0403_4b50 else { throw ZipError.notAZip }
      let dataStart = localOffset + 30 + Int(try uint16(bytes, localOffset + 26)) + Int(try uint16(bytes, localOffset + 28))
      _ = try slice(bytes, dataStart, compressedSize)
      entries.append(Entry(
        name: name, method: method, crc: crc, size: size, compressedSize: compressedSize,
        headerStart: localOffset, dataStart: dataStart))
    }
    // No file's bytes may overlap another's or the central directory: entries sharing data would
    // unpack it again for each, and a DEFLATE stream quoting the next file's header could chain
    // every file into one shared run.
    let ranges = entries.map { $0.headerStart..<($0.dataStart + $0.compressedSize) } + [directoryStart..<(directoryStart + directorySize)]
    let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
    for (earlier, later) in zip(sorted, sorted.dropFirst()) where later.lowerBound < earlier.upperBound {
      throw ZipError.notAZip
    }
    return entries
  }

  /// A raw DEFLATE stream unpacked into the room its entry declares plus a byte, so an entry that
  /// unpacks to more than it declares is refused rather than expanding without bound.
  private static func inflate(_ compressed: ArraySlice<UInt8>, size: Int) throws -> Data {
    guard size > 0 else { return Data() }
    guard !compressed.isEmpty else { throw ZipError.notAZip }
    var output = [UInt8](repeating: 0, count: size + 1)
    let written = compressed.withUnsafeBufferPointer { source in
      output.withUnsafeMutableBufferPointer { destination in
        // Compression's zlib is raw DEFLATE, as zip entries hold it.
        compression_decode_buffer(
          destination.baseAddress!, destination.count, source.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
      }
    }
    guard written == size else { throw ZipError.notAZip }
    return Data(output[0..<size])
  }

  /// The CRC-32 zip stores for each file (zlib's).
  static func crc32(_ data: Data) -> UInt32 {
    data.withUnsafeBytes { buffer in
      var crc = zlib.crc32(0, nil, 0)
      var remaining = buffer.count
      var pointer = buffer.bindMemory(to: Bytef.self).baseAddress
      // zlib takes a 32-bit length.
      while remaining > 0, let start = pointer {
        let chunk = min(remaining, Int(UInt32.max))
        crc = zlib.crc32(crc, start, uInt(chunk))
        pointer = start + chunk
        remaining -= chunk
      }
      return UInt32(crc)
    }
  }

  private static func slice(_ bytes: [UInt8], _ at: Int, _ count: Int) throws -> ArraySlice<UInt8> {
    guard at >= 0, count >= 0, at <= bytes.count, count <= bytes.count - at else { throw ZipError.notAZip }
    return bytes[at..<(at + count)]
  }

  private static func uint16(_ bytes: [UInt8], _ at: Int) throws -> UInt16 {
    let b = try slice(bytes, at, 2)
    return UInt16(b[at]) | UInt16(b[at + 1]) << 8
  }

  private static func uint32(_ bytes: [UInt8], _ at: Int) throws -> UInt32 {
    let b = try slice(bytes, at, 4)
    return UInt32(b[at]) | UInt32(b[at + 1]) << 8 | UInt32(b[at + 2]) << 16 | UInt32(b[at + 3]) << 24
  }
}
