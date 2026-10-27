import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

struct ReportsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "reports",
    abstract: "Download Sales, Finance, and App Analytics reports.",
    subcommands: [Sales.self, Finance.self, Analytics.self]
  )
}

// MARK: - Sales

extension ReportsCommand {
  struct Sales: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "sales",
      abstract: "Download a Sales & Trends report (units/downloads, proceeds)."
    )

    @Option(name: .long, help: "Frequency: DAILY, WEEKLY, MONTHLY, YEARLY (default: DAILY).")
    var frequency: String = "DAILY"

    @Option(
      name: .long,
      help:
        "Report date. DAILY/WEEKLY: YYYY-MM-DD (weekly = the Sunday ending the week), MONTHLY: YYYY-MM, YEARLY: YYYY. Defaults to the most recent completed period."
    )
    var date: String?

    @Option(
      name: .long,
      help:
        "Report type (default: SALES). Others: SUBSCRIPTION, SUBSCRIBER, SUBSCRIPTION_EVENT, INSTALLS, PRE_ORDER, SUBSCRIPTION_OFFER_CODE_REDEMPTION."
    )
    var type: String = "SALES"

    @Option(
      name: .customLong("sub-type"),
      help: "Report sub-type (default: SUMMARY). Others: DETAILED, SUMMARY_TERRITORY, SUMMARY_CHANNEL, SUMMARY_INSTALL_TYPE.")
    var subType: String = "SUMMARY"

    @Option(name: .customLong("vendor-number"), help: "Vendor number (overrides config).")
    var vendorNumber: String?

    @Option(name: .customLong("bundle-id"), help: "Filter the summary to one app by bundle ID or alias.")
    var bundleID: String?

    @Option(name: .long, help: "Save the raw TSV report to this path instead of summarizing.")
    var output: String?

    @Flag(name: .long, help: "Print the raw TSV instead of a summary.")
    var raw: Bool = false

    func run() async throws {
      let config = try Config.load()
      let vendor = try Reports.resolveVendorNumber(vendorNumber, config: config)
      typealias Query = Operations.SalesReportsGetCollection.Input.Query
      let freq: Query.FilterFrequencyPayloadPayload = try parseEnum(frequency, name: "frequency")
      let reportType: Query.FilterReportTypePayloadPayload = try parseEnum(type, name: "type")
      let subTypeEnum: Query.FilterReportSubTypePayloadPayload = try parseEnum(subType, name: "sub-type")
      let reportDate = date ?? Reports.defaultSalesDate(frequency: freq.rawValue)

      let client = try ClientFactory.makeClient()

      var appleID: String?
      if let bundleID {
        appleID = try await findApp(bundleID: bundleID, client: client).id
      }

      print("Fetching \(formatState(freq)) \(reportType.rawValue) report for \(reportDate)…")

      let text: String
      do {
        let body = try await client.salesReportsGetCollection(query: .init(
          filterVendorNumber: [vendor], filterReportType: [reportType], filterReportSubType: [subTypeEnum],
          filterFrequency: [freq], filterReportDate: [reportDate]
        )).ok.body.applicationAGzip
        text = try Reports.reportText(try await Data(collecting: body, upTo: 512 << 20))
      } catch {
        throw Reports.notFoundHint(error, date: reportDate)
      }

      if try Reports.emitRaw(text, output: output, raw: raw) { return }
      print()
      Reports.summarizeSales(text, appleID: appleID)
    }
  }
}

// MARK: - Finance

extension ReportsCommand {
  struct Finance: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "finance",
      abstract: "Download a Financial report (units, partner proceeds) for a fiscal period."
    )

    @Option(
      name: .long,
      help:
        "Fiscal report date as YYYY-MM, where MM is Apple's fiscal period (01–12), not a calendar month."
    )
    var date: String

    @Option(name: .long, help: "Region code (e.g. US, EU, GB, JP, AU, WW for worldwide).")
    var region: String

    @Option(name: .long, help: "Report type: FINANCIAL or FINANCE_DETAIL (default: FINANCIAL).")
    var type: String = "FINANCIAL"

    @Option(name: .customLong("vendor-number"), help: "Vendor number (overrides config).")
    var vendorNumber: String?

    @Option(name: .long, help: "Save the raw TSV report to this path instead of summarizing.")
    var output: String?

    @Flag(name: .long, help: "Print the raw TSV instead of a summary.")
    var raw: Bool = false

    func run() async throws {
      let config = try Config.load()
      let vendor = try Reports.resolveVendorNumber(vendorNumber, config: config)
      let reportType: Operations.FinanceReportsGetCollection.Input.Query.FilterReportTypePayloadPayload =
        try parseEnum(type, name: "type")

      let client = try ClientFactory.makeClient()

      print("Fetching \(reportType.rawValue) report for \(date), region \(region.uppercased())…")

      let text: String
      do {
        let body = try await client.financeReportsGetCollection(query: .init(
          filterVendorNumber: [vendor], filterReportType: [reportType], filterRegionCode: [region.uppercased()], filterReportDate: [date]
        )).ok.body.applicationAGzip
        text = try Reports.reportText(try await Data(collecting: body, upTo: 512 << 20))
      } catch {
        throw Reports.notFoundHint(error, date: date)
      }

      if try Reports.emitRaw(text, output: output, raw: raw) { return }
      print()
      Reports.summarizeFinance(text)
    }
  }
}

// MARK: - Analytics

extension ReportsCommand {
  struct Analytics: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "analytics",
      abstract: "Download App Analytics report data (downloads, impressions, sessions, etc.)."
    )

    @Argument(help: "The bundle identifier (or alias) of the app.")
    var bundleID: String

    @Option(
      name: .long,
      help:
        "Category: APP_STORE_ENGAGEMENT, APP_USAGE, COMMERCE, FRAMEWORK_USAGE, PERFORMANCE (default: APP_STORE_ENGAGEMENT)."
    )
    var category: String = "APP_STORE_ENGAGEMENT"

    @Option(name: .long, help: "Granularity: DAILY, WEEKLY, MONTHLY (default: DAILY).")
    var granularity: String = "DAILY"

    @Option(
      name: .customLong("report-name"),
      help: "Filter to a single report by exact name (see the picker for available names).")
    var reportName: String?

    @Option(
      name: .customLong("processing-date"),
      help: "Processing date of the instance to download (YYYY-MM-DD). Defaults to the most recent.")
    var processingDate: String?

    @Flag(name: .long, help: "Create/use an ONGOING report request instead of a one-time snapshot.")
    var ongoing: Bool = false

    @Option(name: .long, help: "Directory to save the report segments (default: ./<app>-analytics).")
    var output: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes: Bool = false

    func run() async throws {
      if yes { autoConfirm = true }

      let cat: Operations.AnalyticsReportRequestsReportsGetToManyRelated.Input.Query.FilterCategoryPayloadPayload =
        try parseEnum(category, name: "category")
      let gran: Operations.AnalyticsReportsInstancesGetToManyRelated.Input.Query.FilterGranularityPayloadPayload =
        try parseEnum(granularity, name: "granularity")

      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appName = app.attributes?.name ?? bundleID

      // 1. Find or create the report request.
      guard let requestID = try await findOrCreateRequest(appID: app.id, appName: appName, client: client)
      else { return }

      // 2. Pick the report within the requested category.
      var reports = try await AscelerateCore.Analytics.reports(requestID: requestID, category: cat, client: client)
      if let reportName {
        reports = reports.filter { $0.name == reportName }
      }
      guard !reports.isEmpty else {
        print(
          "No reports available yet for \(category)\(reportName.map { " named \"\($0)\"" } ?? "").")
        print("If you just created the request, Apple is still generating it — re-run in a few minutes.")
        return
      }

      let report: AscelerateCore.Analytics.Report
      if reports.count == 1 {
        report = reports[0]
      } else if autoConfirm {
        let names = reports.map(\.name).joined(separator: ", ")
        throw ValidationError(
          "Multiple reports in \(category). Pass --report-name. Available: \(names)")
      } else {
        report = try promptSelection("Multiple reports in \(category)", items: reports.sorted { $0.name < $1.name }) { $0.name }
      }
      let displayName = report.name

      // 3. Pick the instance (processing date) at the requested granularity.
      let instances = try await AscelerateCore.Analytics.instances(
        reportID: report.id, granularity: gran, processingDate: processingDate, client: client)
      guard let instance = instances.max(by: { ($0.processingDate ?? "") < ($1.processingDate ?? "") }) else {
        print(
          "No \(granularity) instances available yet for \"\(displayName)\"\(processingDate.map { " on \($0)" } ?? "").")
        print("The snapshot may still be processing — re-run later.")
        return
      }
      let instanceDate = instance.processingDate ?? "unknown"

      // 4. Collect the instance's segments.
      let segments = try await AscelerateCore.Analytics.segments(instanceID: instance.id, client: client)
      guard !segments.isEmpty else {
        print("Instance \(instanceDate) has no segments yet — re-run later.")
        return
      }

      // 5. Download, decompress, and save each segment.
      let safeName = appName.replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: " ", with: "-")
      let outDir = expandPath(output ?? "./\(safeName)-analytics")
      try FileManager.default.createDirectory(
        atPath: outDir, withIntermediateDirectories: true)

      print("Downloading \"\(displayName)\" (\(granularity), processed \(instanceDate)) — \(segments.count) segment(s)…")
      var totalRows = 0
      var savedFiles: [String] = []
      for (i, segment) in segments.enumerated() where segment.url != nil {
        let text = String(decoding: try await AscelerateCore.Analytics.download(segment, number: i + 1), as: UTF8.self)
        totalRows += max(0, text.split(whereSeparator: \.isNewline).count - 1)
        let file = (outDir as NSString).appendingPathComponent("segment-\(i + 1).csv")
        try text.write(toFile: file, atomically: true, encoding: .utf8)
        savedFiles.append(file)
      }

      print()
      success("Saved", "\(savedFiles.count) segment file(s) (\(totalRows) data rows) to \(outDir)")
    }

    /// Returns the ID of an existing report request matching the requested access type, creating one
    /// (with confirmation) if none exists. Returns nil if the user declines creation.
    private func findOrCreateRequest(
      appID: String, appName: String, client: ASCClient
    ) async throws -> String? {
      let accessType: AscelerateCore.Analytics.AccessType = ongoing ? .ongoing : .oneTimeSnapshot
      if let request = try await AscelerateCore.Analytics.activeRequest(appID: appID, accessType: accessType, client: client) {
        return request.id
      }

      let kind = ongoing ? "ongoing" : "one-time snapshot"
      guard
        confirm(
          "No \(kind) analytics report request exists for '\(appName)'. Create one? [y/N] ")
      else {
        cancelled()
        return nil
      }

      let created = try await AscelerateCore.Analytics.createRequest(appID: appID, accessType: accessType, client: client)
      success("Created", "report request \(created.id).")
      print("Apple is now generating the report. This can take a while — re-run this command later to download it.")
      return created.id
    }
  }
}
