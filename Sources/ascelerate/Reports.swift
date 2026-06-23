import AppStoreAPI
import AppStoreConnect
import ArgumentParser
import Foundation

/// Shared plumbing for the `reports` commands (sales, finance, analytics).
///
/// App Store Connect's Sales and Finance report endpoints return a **gzipped TSV** as the raw
/// response body (content type `application/a-gzip`), not via HTTP transfer-encoding — so
/// URLSession does not decompress it for us. We download to a temp file and run `gzip -dc`.
/// Analytics report *segments* are likewise gzipped files at presigned URLs.
enum Reports {
  // MARK: - Vendor number

  /// Resolves the vendor number from the `--vendor-number` flag, falling back to config.
  /// Throws a guiding error when neither is set.
  static func resolveVendorNumber(_ flag: String?, config: Config) throws -> String {
    if let flag, !flag.trimmingCharacters(in: .whitespaces).isEmpty {
      return flag.trimmingCharacters(in: .whitespaces)
    }
    if let v = config.vendorNumber, !v.isEmpty { return v }
    throw ValidationError(
      """
      No vendor number set. Pass --vendor-number, or save one with 'ascelerate configure'.
      Find it in App Store Connect → Payments and Financial Reports (top-left, e.g. 80012345).
      """)
  }

  // MARK: - Gzip

  /// Runs `gzip -dc <file>` and returns the decompressed bytes.
  static func gunzipFile(at url: URL) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
    process.arguments = ["-dc", url.path]
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = Pipe()
    try process.run()
    // readDataToEndOfFile drains the pipe as gzip streams, so this can't deadlock on buffer fill.
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw ValidationError(
        "Failed to decompress report (gzip exited \(process.terminationStatus)).")
    }
    return data
  }

  /// Decompresses raw gzipped bytes by writing them to a temp file and running `gzip -dc`.
  static func gunzip(_ data: Data) throws -> Data {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("ascelerate-report-\(UUID().uuidString).gz")
    try data.write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }
    return try gunzipFile(at: tmp)
  }

  // MARK: - Report download

  /// Downloads a `Request<Data>` report endpoint and returns the decompressed TSV text.
  static func fetchReportText(
    _ request: Request<Data>, client: AppStoreConnectClient
  ) async throws -> String {
    let fileURL = try await client.download(request)
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let decompressed = try gunzipFile(at: fileURL)
    guard let text = String(data: decompressed, encoding: .utf8) else {
      throw ValidationError("Report data was not valid UTF-8 text.")
    }
    return text
  }

  // MARK: - TSV

  /// Splits TSV text into a header row and data rows, dropping empty lines.
  static func parseTSV(_ text: String) -> (header: [String], rows: [[String]]) {
    let lines = text.split(whereSeparator: \.isNewline).map(String.init)
    guard let first = lines.first else { return ([], []) }
    let header = first.components(separatedBy: "\t")
    let rows = lines.dropFirst().map { $0.components(separatedBy: "\t") }
    return (header, rows)
  }

  /// Reads a column value from a TSV row by header name, or nil if the column is absent/short.
  static func value(_ row: [String], _ header: [String], _ column: String) -> String? {
    guard let i = header.firstIndex(of: column), i < row.count else { return nil }
    let v = row[i].trimmingCharacters(in: .whitespaces)
    return v.isEmpty ? nil : v
  }

  // MARK: - Output

  /// Writes raw report text to `output` and prints a confirmation, or prints the text to stdout
  /// when `raw` is set. Returns true if the caller should stop (output written or raw printed).
  static func emitRaw(_ text: String, output: String?, raw: Bool) throws -> Bool {
    if let output {
      let path = expandPath(confirmOutputPath(output, isDirectory: false))
      try text.write(toFile: path, atomically: true, encoding: .utf8)
      success("Saved", "report to \(path)")
      return true
    }
    if raw {
      print(text, terminator: text.hasSuffix("\n") ? "" : "\n")
      return true
    }
    return false
  }

  // MARK: - Sales

  /// Default report date for the most recent completed period, in Apple's reporting time zone.
  /// DAILY → yesterday, WEEKLY → most recent Sunday, MONTHLY → last month, YEARLY → last year.
  static func defaultSalesDate(frequency: Resources.V1.SalesReports.FilterFrequency) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? cal.timeZone
    let formatter = DateFormatter()
    formatter.calendar = cal
    formatter.timeZone = cal.timeZone
    let now = Date()

    switch frequency {
    case .weekly:
      formatter.dateFormat = "yyyy-MM-dd"
      // Apple weekly reports are keyed by the Sunday that ends the week.
      let weekday = cal.component(.weekday, from: now)  // 1 = Sunday
      let daysSinceSunday = (weekday - 1 + 7) % 7
      let lastSunday = cal.date(byAdding: .day, value: -(daysSinceSunday == 0 ? 7 : daysSinceSunday), to: now)!
      return formatter.string(from: lastSunday)
    case .monthly:
      formatter.dateFormat = "yyyy-MM"
      return formatter.string(from: cal.date(byAdding: .month, value: -1, to: now)!)
    case .yearly:
      formatter.dateFormat = "yyyy"
      return formatter.string(from: cal.date(byAdding: .year, value: -1, to: now)!)
    case .daily:
      formatter.dateFormat = "yyyy-MM-dd"
      return formatter.string(from: cal.date(byAdding: .day, value: -1, to: now)!)
    }
  }

  /// Turns a 404 from a report download into a friendlier hint (the body isn't parsed on downloads).
  static func notFoundHint(_ error: ResponseError, date: String) -> Error {
    if case .requestFailure(_, let status, _) = error, status == 404 {
      return ValidationError(
        """
        No report found for \(date). It may not be available yet (data lags ~1 day),
        or there was no activity in that period. Try an earlier --date.
        """)
    }
    return error
  }

  /// Prints a units-by-(title, product type) summary for a Sales report, optionally filtered to one app.
  static func summarizeSales(_ text: String, appleID: String?) {
    let (header, rows) = parseTSV(text)
    guard !rows.isEmpty else {
      print("Report is empty — no sales in this period.")
      return
    }

    var data = rows
    if let appleID {
      data = rows.filter { value($0, header, "Apple Identifier") == appleID }
      guard !data.isEmpty else {
        print("No rows for the selected app in this report.")
        return
      }
    }

    struct Key: Hashable { let title: String; let sku: String; let type: String }
    var units: [Key: Int] = [:]
    var order: [Key] = []
    var total = 0
    for row in data {
      let key = Key(
        title: value(row, header, "Title") ?? "—",
        sku: value(row, header, "SKU") ?? "—",
        type: value(row, header, "Product Type Identifier") ?? "—")
      let u = Int(value(row, header, "Units") ?? "") ?? 0
      if units[key] == nil { order.append(key) }
      units[key, default: 0] += u
      total += u
    }

    let begin = data.first.flatMap { value($0, header, "Begin Date") }
    let end = data.first.flatMap { value($0, header, "End Date") }
    if let begin, let end {
      print("Period: \(begin) – \(end)")
      print()
    }

    let sorted = order.sorted { (units[$0] ?? 0) > (units[$1] ?? 0) }
    Table.print(
      headers: ["Title", "SKU", "Product Type", "Units"],
      rows: sorted.map { [$0.title, $0.sku, $0.type, "\(units[$0] ?? 0)"] })
    print()
    print("Total units: \(bold("\(total)"))")
    print("Tip: product type identifiers distinguish app downloads from updates/IAPs. Use --raw for full data.")
  }

  // MARK: - Finance

  /// Prints a quantity-by-title summary and proceeds-by-currency totals for a Finance report.
  static func summarizeFinance(_ text: String) {
    let (header, rows) = parseTSV(text)
    guard header.contains("Quantity") else {
      // Unrecognized layout (e.g. an empty period) — show it verbatim.
      print(text, terminator: text.hasSuffix("\n") ? "" : "\n")
      return
    }

    var qty: [String: Int] = [:]
    var order: [String] = []
    var proceeds: [String: Double] = [:]
    var totalQty = 0
    for row in rows {
      // Footer/total lines don't have a numeric Quantity — skip them.
      guard let q = Int(value(row, header, "Quantity") ?? "") else { continue }
      let title = value(row, header, "Title") ?? "—"
      if qty[title] == nil { order.append(title) }
      qty[title, default: 0] += q
      totalQty += q
      if let share = Double(value(row, header, "Extended Partner Share") ?? ""),
        let currency = value(row, header, "Partner Share Currency")
      {
        proceeds[currency, default: 0] += share
      }
    }

    guard totalQty != 0 || !proceeds.isEmpty else {
      print("Report has no billable rows for this period.")
      return
    }

    let sorted = order.sorted { (qty[$0] ?? 0) > (qty[$1] ?? 0) }
    Table.print(headers: ["Title", "Quantity"], rows: sorted.map { [$0, "\(qty[$0] ?? 0)"] })
    print()
    print("Total quantity: \(bold("\(totalQty)"))")
    for (currency, amount) in proceeds.sorted(by: { $0.key < $1.key }) {
      print("Proceeds (\(currency)): \(String(format: "%.2f", amount))")
    }
  }
}
