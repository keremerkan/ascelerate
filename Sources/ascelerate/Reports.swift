import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

/// Shared plumbing for the `reports` commands (sales, finance, analytics).
///
/// App Store Connect's Sales and Finance report endpoints return a **gzipped TSV** as the raw
/// response body (content type `application/a-gzip`), not via HTTP transfer-encoding — so
/// URLSession does not decompress it for us; `Gzip` (AscelerateCore) does. Analytics report
/// *segments* are likewise gzipped files at presigned URLs.
enum Reports {
  // MARK: - Vendor number

  /// Resolves the vendor number from the `--vendor-number` flag, falling back to config.
  /// Throws a guiding error when neither is set.
  /// `--vendor-number`, else the saved one; the config is read only when the flag is missing (a
  /// run with the key in the environment may have no config file).
  static func resolveVendorNumber(_ flag: String?, config: () throws -> Config) throws -> String {
    if let flag, !flag.trimmingCharacters(in: .whitespaces).isEmpty {
      return flag.trimmingCharacters(in: .whitespaces)
    }
    if let v = try config().vendorNumber, !v.isEmpty { return v }
    throw ValidationError(
      """
      No vendor number set. Pass --vendor-number, or save one with 'ascelerate configure'.
      Find it in App Store Connect → Payments and Financial Reports (top-left, e.g. 80012345).
      """)
  }

  // MARK: - Report download

  /// Decompresses a report download (an `application/a-gzip` body) into its TSV text.
  static func reportText(_ gzipped: Data) throws -> String {
    guard let text = String(data: try Gzip.decompress(gzipped), encoding: .utf8) else {
      throw ValidationError("Report data was not valid UTF-8 text.")
    }
    return text
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
      let path = expandPath(try confirmOutputPath(output, isDirectory: false))
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

  /// Turns a 404 from a report download into a friendlier hint (the body isn't parsed on downloads).
  static func notFoundHint(_ error: Error, date: String) -> Error {
    if ASCError.from(error)?.statusCode == 404 {
      return ValidationError(
        """
        No report found for \(date). It may not be available yet (data lags ~1 day),
        or there was no activity in that period. Try an earlier --date.
        """)
    }
    return error
  }

  /// Prints a units-by-(title, product type) summary for a Sales report, optionally for one app:
  /// its own rows and its in-app purchases' and subscriptions' (`SalesReports.rows`, whose
  /// `parentSKU` names their app).
  static func summarizeSales(_ text: String, app: (appleID: String, sku: String?)?) {
    let (header, lines) = TSV.parse(text)
    guard !lines.isEmpty else {
      print("Report is empty — no sales in this period.")
      return
    }
    // Non-SALES report types (SUBSCRIPTION, SUBSCRIBER, ...) have different columns —
    // summarizing them here would misleadingly collapse everything into "0 units".
    guard header.contains("Units"), header.contains("Title") else {
      print("This report type has no Units/Title columns to summarize — showing raw data.")
      print()
      print(text, terminator: text.hasSuffix("\n") ? "" : "\n")
      return
    }

    var data = SalesReports.rows(tsv: text)
    if let app {
      data = data.filter { $0.appleID == app.appleID || (app.sku != nil && $0.parentSKU == app.sku) }
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
      let key = Key(title: row.title.isEmpty ? "—" : row.title, sku: row.sku.isEmpty ? "—" : row.sku, type: row.productType.isEmpty ? "—" : row.productType)
      if units[key] == nil { order.append(key) }
      units[key, default: 0] += row.units
      total += row.units
    }

    if let first = data.first, !first.beginDate.isEmpty, !first.endDate.isEmpty {
      print("Period: \(first.beginDate) – \(first.endDate)")
      print()
    }

    let sorted = order.sorted { (units[$0] ?? 0) > (units[$1] ?? 0) }
    Table.print(
      headers: ["Title", "SKU", "Product Type", "Units"],
      rows: sorted.map { [$0.title, $0.sku, $0.type, "\(units[$0] ?? 0)"] })
    print()
    print("Total units: \(bold("\(total)"))" + (app == nil ? "" : " (the app, its in-app purchases and subscriptions)"))
    print("Tip: product type identifiers distinguish app downloads from updates/IAPs. Use --raw for full data.")
  }

  // MARK: - Finance

  /// Prints a quantity-by-title summary and proceeds-by-currency totals for a Finance report.
  static func summarizeFinance(_ text: String) {
    let (header, rows) = TSV.parse(text)
    guard header.contains("Quantity") else {
      // Unrecognized layout (e.g. an empty period) — show it verbatim.
      print(text, terminator: text.hasSuffix("\n") ? "" : "\n")
      return
    }

    var qty: [String: Int] = [:]
    var order: [String] = []
    // Decimal: summing money as Double drifts.
    var proceeds: [String: Decimal] = [:]
    var totalQty = 0
    for row in rows {
      // Footer/total lines don't have a numeric Quantity — skip them.
      guard let q = Int(value(row, header, "Quantity") ?? "") else { continue }
      let title = value(row, header, "Title") ?? "—"
      if qty[title] == nil { order.append(title) }
      qty[title, default: 0] += q
      totalQty += q
      if let share = Decimal(string: value(row, header, "Extended Partner Share") ?? "", locale: Locale(identifier: "en_US_POSIX")),
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
      print("Proceeds (\(currency)): \(amount.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))))")
    }
  }
}
