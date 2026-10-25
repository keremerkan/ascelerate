import ASCKit
import Foundation

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

/// Gzip files (reports, analytics segments), read in-process: the member's DEFLATE stream after
/// its header, which Foundation's zlib decompression reads.
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

  public static func decompress(_ data: Data) throws -> Data {
    let bytes = [UInt8](data)
    guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else { throw GzipError.notGzip }
    let flags = bytes[3]
    var offset = 10
    if flags & 0x04 != 0 {  // FEXTRA: a length, then that many bytes
      guard offset + 2 <= bytes.count else { throw GzipError.truncated }
      offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
    }
    for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {  // FNAME, FCOMMENT: zero-terminated
      guard let end = bytes[offset...].firstIndex(of: 0) else { throw GzipError.truncated }
      offset = end + 1
    }
    if flags & 0x02 != 0 { offset += 2 }  // FHCRC
    // The member ends with its CRC-32 and size (8 bytes).
    guard offset < bytes.count - 8 else { throw GzipError.truncated }
    return try (Data(bytes[offset..<(bytes.count - 8)]) as NSData).decompressed(using: .zlib) as Data
  }
}
