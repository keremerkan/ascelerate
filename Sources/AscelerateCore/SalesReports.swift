import ASCKit
import Compression
import Foundation
import zlib

/// Sales and Trends reports (`salesReports`): what was downloaded and bought, per day, week, month
/// or year, by app, product, country and device. App Store Connect sends each report as a gzipped
/// TSV; a published period never changes. Reports need the account's vendor number (App Store
/// Connect's Payments and Financial Reports shows it), which the API doesn't give.
public enum SalesReports {
  public enum Frequency: String, Sendable, CaseIterable {
    case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY"
  }

  /// What a row counts, from its product type identifier.
  public enum Kind: String, Sendable {
    /// A first download (free or paid).
    case download
    case redownload
    case update
    case inAppPurchase
    /// An auto-renewable subscription's purchase or renewal.
    case subscription
    case other
  }

  /// A row of a Sales summary report. Units are negative for refunds; proceeds are per unit, in
  /// `proceedsCurrency`.
  public struct Row: Sendable, Hashable {
    public let title: String
    public let sku: String
    /// The app's or the in-app purchase's Apple ID.
    public let appleID: String
    /// An in-app purchase's app, by the app's SKU; nil for an app.
    public let parentSKU: String?
    public let productType: String
    public let units: Int
    public let proceeds: Decimal
    public let proceedsCurrency: String?
    public let countryCode: String
    public let device: String?
    /// The period's first and last day as the report gives them (MM/dd/yyyy).
    public let beginDate: String
    public let endDate: String
    /// A subscription row's "New" or "Renewal".
    public let subscription: String?

    public var kind: Kind {
      SalesReports.kind(of: productType)
    }

    /// The row's proceeds: units times proceeds per unit.
    public var totalProceeds: Decimal {
      proceeds * Decimal(units)
    }
  }

  /// What a product type identifier counts (Apple's list: 1 and 1F/1T/F1 are downloads, 3 are
  /// re-downloads, 7 are updates, IA and FI in-app purchases, IAY auto-renewable subscriptions).
  public static func kind(of productType: String) -> Kind {
    let base = productType.split(separator: "-").first.map(String.init) ?? productType
    switch base {
      case "1", "1F", "1T", "1E", "1EP", "1EU", "F1": return .download
      case "3", "3F", "3T", "F3": return .redownload
      case "7", "7F", "7T", "F7": return .update
      case "IAY": return .subscription
      default: return base.hasPrefix("IA") || base.hasPrefix("FI") ? .inAppPurchase : .other
    }
  }

  /// A Sales summary report as App Store Connect sends it (gzipped TSV); nil when it has none for
  /// the period: not published yet, or nothing happened. `date` is yyyy-MM-dd (daily; weekly: the
  /// Sunday ending the week), yyyy-MM (monthly) or yyyy (yearly).
  public static func download(
    vendorNumber: String, frequency: Frequency, date: String, client: ASCClient
  ) async throws -> Data? {
    typealias Query = Operations.SalesReportsGetCollection.Input.Query
    do {
      let body = try await client.salesReportsGetCollection(query: .init(
        filterVendorNumber: [vendorNumber], filterReportType: [.sales], filterReportSubType: [.summary],
        filterFrequency: [Query.FilterFrequencyPayloadPayload(rawValue: frequency.rawValue) ?? .daily],
        filterReportDate: [date]
      )).ok.body.applicationAGzip
      return try await Data(collecting: body, upTo: 512 << 20)
    } catch where ASCError.from(error)?.statusCode == 404 {
      return nil
    }
  }

  /// A downloaded report's rows.
  public static func rows(_ gzipped: Data) throws -> [Row] {
    guard let text = String(data: try Gzip.decompress(gzipped), encoding: .utf8) else {
      throw ReportError.notText
    }
    return rows(tsv: text)
  }

  /// A Sales summary report's rows, from its TSV text.
  public static func rows(tsv text: String) -> [Row] {
    let (header, lines) = TSV.parse(text)
    func column(_ name: String) -> Int? { header.firstIndex(of: name) }
    guard let units = column("Units"), let type = column("Product Type Identifier") else { return [] }
    let title = column("Title"), sku = column("SKU"), appleID = column("Apple Identifier")
    let parent = column("Parent Identifier"), proceeds = column("Developer Proceeds")
    let currency = column("Currency of Proceeds"), country = column("Country Code"), device = column("Device")
    let begin = column("Begin Date"), end = column("End Date"), subscription = column("Subscription")
    return lines.map { line in
      func value(_ index: Int?) -> String? {
        guard let index, index < line.count else { return nil }
        let value = line[index].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
      }
      return Row(
        title: value(title) ?? "", sku: value(sku) ?? "", appleID: value(appleID) ?? "", parentSKU: value(parent),
        productType: value(type) ?? "", units: Int(value(units) ?? "") ?? 0,
        proceeds: Decimal(string: value(proceeds) ?? "", locale: Locale(identifier: "en_US_POSIX")) ?? 0,
        proceedsCurrency: value(currency), countryCode: value(country) ?? "", device: value(device),
        beginDate: value(begin) ?? "", endDate: value(end) ?? "", subscription: value(subscription))
    }
  }

  /// The day App Store Connect's reports count in (Pacific Time): `daysAgo` days before today
  /// there, as yyyy-MM-dd.
  public static func reportDay(daysAgo: Int, from now: Date = .now) -> String {
    let calendar = reportCalendar
    let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
    return day.formatted(Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day().dateSeparator(.dash))
  }

  /// The Gregorian calendar in Pacific Time, which report periods follow.
  public static var reportCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
    return calendar
  }

  public enum ReportError: LocalizedError {
    case notText

    public var errorDescription: String? {
      "The report wasn't readable text."
    }
  }
}

/// Tab-separated report text.
public enum TSV {
  /// The header row and the data rows, without empty lines.
  public static func parse(_ text: String) -> (header: [String], rows: [[String]]) {
    let lines = text.split(whereSeparator: \.isNewline).map(String.init)
    guard let first = lines.first else { return ([], []) }
    return (first.components(separatedBy: "\t"), lines.dropFirst().map { $0.components(separatedBy: "\t") })
  }
}

/// Gzip files (reports, analytics segments), read in-process with zlib in its gzip mode: every
/// member of the stream (RFC 1952 allows several, concatenated), each with its header read and
/// its CRC-32 and length checked against its trailer.
public enum Gzip {
  public enum GzipError: LocalizedError {
    case notGzip, truncated

    public var errorDescription: String? {
      switch self {
        case .notGzip: "The data isn't gzip-compressed."
        case .truncated: "The compressed data is incomplete."
      }
    }
  }

  /// A member whose content doesn't match its trailer (CRC-32 or length), a damaged DEFLATE
  /// stream, or bytes after a member that aren't another member.
  public struct Damaged: LocalizedError, Sendable {
    public var errorDescription: String? { "The compressed data is damaged (its checksum doesn't match, or it has data after its end)." }
  }

  /// The content of every member, in order.
  public static func decompress(_ data: Data) throws -> Data {
    var out = Data()
    _ = try inflateMembers(data) { out.append($0) }
    return out
  }

  /// Decompresses to a file a piece at a time, for data whose decompressed copy is too large to
  /// hold in memory beside it (an App Analytics report's segment unzips to tens of megabytes). On
  /// a failure the file is removed.
  public static func decompress(_ data: Data, to url: URL) throws {
    guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
    let handle = try FileHandle(forWritingTo: url)
    do {
      _ = try inflateMembers(data) { try handle.write(contentsOf: $0) }
      try handle.close()
    } catch {
      try? handle.close()
      try? FileManager.default.removeItem(at: url)
      throw error
    }
  }

  /// How many members the stream has (each read and checked); for tests and diagnostics.
  public static func memberCount(_ data: Data) throws -> Int {
    try inflateMembers(data) { _ in }
  }

  /// Inflates every member, handing each piece of content to `write`, and returns the count.
  private static func inflateMembers(_ data: Data, write: (Data) throws -> Void) throws -> Int {
    guard data.count >= 18, data[data.startIndex] == 0x1F, data[data.startIndex + 1] == 0x8B,
      data[data.startIndex + 2] == 8
    else { throw GzipError.notGzip }
    var stream = z_stream()
    // 15 + 16: a gzip header and trailer around the DEFLATE stream, checked by zlib.
    guard inflateInit2_(&stream, 15 + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
      throw GzipError.notGzip
    }
    defer { inflateEnd(&stream) }
    return try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
      guard let base = raw.bindMemory(to: Bytef.self).baseAddress else { throw GzipError.notGzip }
      stream.next_in = UnsafeMutablePointer(mutating: base)
      stream.avail_in = uInt(raw.count)
      var buffer = [Bytef](repeating: 0, count: 1 << 16)
      var members = 0
      while true {
        var status: Int32 = Z_OK
        while status != Z_STREAM_END {
          let produced: Int = buffer.withUnsafeMutableBufferPointer { out in
            stream.next_out = out.baseAddress
            stream.avail_out = uInt(out.count)
            status = inflate(&stream, Z_NO_FLUSH)
            return out.count - Int(stream.avail_out)
          }
          if produced > 0 { try write(Data(buffer[0..<produced])) }
          switch status {
            case Z_OK, Z_STREAM_END: continue
            case Z_BUF_ERROR where stream.avail_in == 0: throw GzipError.truncated
            default: throw Damaged()
          }
        }
        members += 1
        guard stream.avail_in > 0 else { return members }
        // Another member, or nothing: bytes that don't start one are refused.
        guard stream.avail_in >= 2, let next = stream.next_in, next[0] == 0x1F, next[1] == 0x8B else { throw Damaged() }
        inflateReset(&stream)
      }
    }
  }
}
