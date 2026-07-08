import AppStoreAPI
import AppStoreConnect
import ArgumentParser
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
      let freq: Resources.V1.SalesReports.FilterFrequency = try parseEnum(frequency, name: "frequency")
      let reportType: Resources.V1.SalesReports.FilterReportType = try parseEnum(type, name: "type")
      let subTypeEnum: Resources.V1.SalesReports.FilterReportSubType = try parseEnum(
        subType, name: "sub-type")
      let reportDate = date ?? Reports.defaultSalesDate(frequency: freq)

      let client = try ClientFactory.makeClient()

      var appleID: String?
      if let bundleID {
        appleID = try await findApp(bundleID: bundleID, client: client).id
      }

      print("Fetching \(formatState(freq)) \(reportType.rawValue) report for \(reportDate)…")

      let text: String
      do {
        text = try await Reports.fetchReportText(
          Resources.v1.salesReports.get(
            filterVendorNumber: [vendor],
            filterReportType: [reportType],
            filterReportSubType: [subTypeEnum],
            filterFrequency: [freq],
            filterReportDate: [reportDate]
          ),
          client: client
        )
      } catch let error as ResponseError {
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
      let reportType: Resources.V1.FinanceReports.FilterReportType = try parseEnum(type, name: "type")

      let client = try ClientFactory.makeClient()

      print("Fetching \(reportType.rawValue) report for \(date), region \(region.uppercased())…")

      let text: String
      do {
        text = try await Reports.fetchReportText(
          Resources.v1.financeReports.get(
            filterVendorNumber: [vendor],
            filterReportType: [reportType],
            filterRegionCode: [region.uppercased()],
            filterReportDate: [date]
          ),
          client: client
        )
      } catch let error as ResponseError {
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

      let cat: Resources.V1.AnalyticsReportRequests.WithID.Reports.FilterCategory = try parseEnum(
        category, name: "category")
      let gran: Resources.V1.AnalyticsReports.WithID.Instances.FilterGranularity = try parseEnum(
        granularity, name: "granularity")

      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appName = app.attributes?.name ?? bundleID

      // 1. Find or create the report request.
      guard let requestID = try await findOrCreateRequest(appID: app.id, appName: appName, client: client)
      else { return }

      // 2. Pick the report within the requested category.
      let reportsResp = try await client.send(
        Resources.v1.analyticsReportRequests.id(requestID).reports.get(
          filterCategory: [cat], limit: 200))
      var reports = reportsResp.data
      if let reportName {
        reports = reports.filter { $0.attributes?.name == reportName }
      }
      guard !reports.isEmpty else {
        print(
          "No reports available yet for \(category)\(reportName.map { " named \"\($0)\"" } ?? "").")
        print("If you just created the request, Apple is still generating it — re-run in a few minutes.")
        return
      }

      let report: AnalyticsReport
      if reports.count == 1 {
        report = reports[0]
      } else if autoConfirm {
        let names = reports.compactMap { $0.attributes?.name }.joined(separator: ", ")
        throw ValidationError(
          "Multiple reports in \(category). Pass --report-name. Available: \(names)")
      } else {
        report = try promptSelection(
          "Multiple reports in \(category)", items: reports.sorted {
            ($0.attributes?.name ?? "") < ($1.attributes?.name ?? "")
          }
        ) { $0.attributes?.name ?? $0.id }
      }
      let displayName = report.attributes?.name ?? report.id

      // 3. Pick the instance (processing date) at the requested granularity.
      let instancesResp = try await client.send(
        Resources.v1.analyticsReports.id(report.id).instances.get(
          filterGranularity: [gran],
          filterProcessingDate: processingDate.map { [$0] },
          limit: 200))
      guard
        let instance = instancesResp.data.max(by: {
          ($0.attributes?.processingDate ?? "") < ($1.attributes?.processingDate ?? "")
        })
      else {
        print(
          "No \(granularity) instances available yet for \"\(displayName)\"\(processingDate.map { " on \($0)" } ?? "").")
        print("The snapshot may still be processing — re-run later.")
        return
      }
      let instanceDate = instance.attributes?.processingDate ?? "unknown"

      // 4. Collect the instance's segments.
      var segments: [AnalyticsReportSegment] = []
      for try await page in client.pages(
        Resources.v1.analyticsReportInstances.id(instance.id).segments.get(limit: 200))
      {
        segments.append(contentsOf: page.data)
      }
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
      for (i, segment) in segments.enumerated() {
        guard let url = segment.attributes?.url else { continue }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
          throw ValidationError(
            "Segment \(i + 1) download failed (HTTP \(http.statusCode)). The presigned URL may have expired — re-run the command.")
        }
        let text = String(decoding: try Reports.gunzip(data), as: UTF8.self)
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
      appID: String, appName: String, client: AppStoreConnectClient
    ) async throws -> String? {
      let existing = try await client.send(
        Resources.v1.apps.id(appID).analyticsReportRequests.get(
          filterAccessType: ongoing ? [.ongoing] : [.oneTimeSnapshot], limit: 50))
      if let request = existing.data.first(where: { $0.attributes?.isStoppedDueToInactivity != true }) {
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

      typealias Body = AnalyticsReportRequestCreateRequest
      let accessType: Body.Data.Attributes.AccessType = ongoing ? .ongoing : .oneTimeSnapshot
      let created = try await client.send(
        Resources.v1.analyticsReportRequests.post(
          Body(
            data: Body.Data(
              attributes: Body.Data.Attributes(accessType: accessType),
              relationships: Body.Data.Relationships(
                app: Body.Data.Relationships.App(
                  data: Body.Data.Relationships.App.Data(id: appID)))))))
      success("Created", "report request \(created.data.id).")
      print("Apple is now generating the report. This can take a while — re-run this command later to download it.")
      return created.data.id
    }
  }
}
