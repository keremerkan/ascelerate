import Foundation

/// Reads the files of a zip archive held in memory: stored and deflated entries, as Xcode Cloud's
/// log bundles have them (no ZIP64, no encryption). Folders are left out.
public enum ZipReader {
  public enum ZipError: LocalizedError {
    case notAZip
    case unsupported(String)

    public var errorDescription: String? {
      switch self {
        case .notAZip: "The file isn't a zip archive."
        case .unsupported(let what): "The zip archive uses \(what), which isn't supported."
      }
    }
  }

  /// Each file's path in the archive and its contents.
  public static func files(in data: Data) throws -> [(path: String, data: Data)] {
    let bytes = [UInt8](data)
    // The end of central directory record, searched from the end (a comment can follow it).
    guard bytes.count >= 22,
      let end = stride(from: bytes.count - 22, through: max(0, bytes.count - 22 - 65_535), by: -1)
        .first(where: { uint32(bytes, $0) == 0x0605_4b50 })
    else { throw ZipError.notAZip }
    let count = Int(uint16(bytes, end + 10))
    var offset = Int(uint32(bytes, end + 16))
    var files: [(String, Data)] = []
    for _ in 0..<count {
      guard offset + 46 <= bytes.count, uint32(bytes, offset) == 0x0201_4b50 else { throw ZipError.notAZip }
      let method = uint16(bytes, offset + 10)
      let compressedSize = Int(uint32(bytes, offset + 20))
      let size = Int(uint32(bytes, offset + 24))
      let nameLength = Int(uint16(bytes, offset + 28))
      let extraLength = Int(uint16(bytes, offset + 30))
      let commentLength = Int(uint16(bytes, offset + 32))
      let localOffset = Int(uint32(bytes, offset + 42))
      let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
      offset += 46 + nameLength + extraLength + commentLength
      if name.hasSuffix("/") { continue }
      guard compressedSize != 0xFFFF_FFFF, size != 0xFFFF_FFFF else { throw ZipError.unsupported("ZIP64") }
      guard localOffset + 30 <= bytes.count, uint32(bytes, localOffset) == 0x0403_4b50 else { throw ZipError.notAZip }
      let start = localOffset + 30 + Int(uint16(bytes, localOffset + 26)) + Int(uint16(bytes, localOffset + 28))
      guard start + compressedSize <= bytes.count else { throw ZipError.notAZip }
      let compressed = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + compressedSize))
      switch method {
        case 0: files.append((name, compressed))
        // Foundation's zlib is raw DEFLATE, as zip entries hold it.
        case 8: files.append((name, try (compressed as NSData).decompressed(using: .zlib) as Data))
        default: throw ZipError.unsupported("compression method \(method)")
      }
    }
    return files
  }

  private static func uint16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
    UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
  }

  private static func uint32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
    UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
  }
}
