import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

struct DiagnosticsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "diagnostics",
    abstract: "Hangs, slow launches and disk writes users' devices reported, and performance and power metrics.",
    discussion: """
      What Xcode's Organizer shows, from devices that share analytics with developers. Without \
      --build, the build of the version on the App Store.
      """,
    subcommands: [Signatures.self, Logs.self, Metrics.self],
    defaultSubcommand: Signatures.self
  )

  /// The build asked for, else the one on the App Store.
  static func build(appID: String, number: String?, platform: Platform?, client: ASCClient) async throws -> Builds.Build {
    if number != nil {
      return try await TestFlightCommand.findBuild(appID: appID, buildVersion: number, platform: platform, client: client)
    }
    guard let live = try await Diagnostics.liveBuild(appID: appID, platform: platform?.rawValue, client: client) else {
      throw ValidationError("No version of the app is on the App Store\(platform.map { " for \(formatState($0.rawValue))" } ?? ""); pass --build.")
    }
    return live
  }

  /// Comma-separated types as Apple's raw values (`hangs` → `HANGS`, `disk-writes` → `DISK_WRITES`).
  static func types(_ value: String?, among known: [String], name: String) throws -> [String]? {
    try value.map { value in
      try value.split(separator: ",").map { item in
        let raw = item.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: "-", with: "_")
        guard known.contains(raw) else {
          throw ValidationError("No \(name) '\(item)'. Choose from: \(known.map { $0.lowercased().replacingOccurrences(of: "_", with: "-") }.joined(separator: ", ")).")
        }
        return raw
      }
    }
  }

  struct Signatures: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "signatures",
      abstract: "A build's top hang, launch and disk write signatures, heaviest first.",
      discussion: "Each signature's ID reads its logs: ascelerate diagnostics logs <id>."
    )

    @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
    var app: String

    @Option(name: .long, help: "Build number. Defaults to the build of the version on the App Store.")
    var build: String?

    @OptionGroup var platformOption: PlatformOption

    @Option(name: .long, help: "hangs, launches or disk-writes; comma-separated for several.")
    var type: String?

    @OptionGroup var jsonOption: JSONOption

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: app, client: client)
      let build = try await DiagnosticsCommand.build(appID: app.id, number: build, platform: try platformOption.parsed(), client: client)
      let types = try DiagnosticsCommand.types(type, among: Diagnostics.signatureTypes, name: "type")
      let signatures = try await Diagnostics.signatures(buildID: build.id, types: types, client: client)
      if jsonOption.json { try printJSON(signatures); return }
      print(bold("Build \(build.label)"))
      guard !signatures.isEmpty else {
        print("No diagnostics for this build yet. They come from users' devices that share analytics, a day or more after release.")
        return
      }
      Table.print(
        headers: ["Type", "Weight", "Trend", "Signature", "ID"],
        rows: signatures.map { s in
          [
            formatState(s.type ?? "-"), s.weight.map { String(format: "%.1f%%", $0) } ?? "-",
            s.trend == "UP" ? red("↑ up") : s.trend == "DOWN" ? green("↓ down") : "-",
            String((s.signature ?? "-").prefix(70)), s.id,
          ]
        })
    }
  }

  struct Logs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "A signature's logs: each sampled event with its device, OS and call stacks.",
      discussion: "The frame App Store Connect blames is marked with ▶."
    )

    @Argument(help: "The signature's ID (from diagnostics signatures).")
    var signature: String

    @Option(name: .long, help: "The most frames to print per call stack (0 for all).")
    var frames = 40

    @OptionGroup var jsonOption: JSONOption

    func run() async throws {
      jsonOption.activate()
      let logs = try await Diagnostics.logs(signatureID: signature, client: ClientFactory.makeClient())
      if jsonOption.json { try printJSON(logs); return }
      let products = logs.productData ?? []
      guard products.contains(where: { !($0.diagnosticLogs ?? []).isEmpty }) else {
        print("No logs for this signature.")
        return
      }
      for product in products {
        for insight in product.diagnosticInsights ?? [] {
          print(yellow("Insight: ") + (insight.insightsString ?? "-") + (insight.insightsURL.map { " (\($0))" } ?? ""))
        }
        for (index, log) in (product.diagnosticLogs ?? []).enumerated() {
          let m = log.diagnosticMetaData
          print()
          print(bold("Log \(index + 1)") + " · " + [m?.event, m?.deviceType, m?.osVersion, m?.appVersion.map { "app \($0)" }, m?.buildVersion.map { "(\($0))" }]
            .compactMap(\.self).joined(separator: " · "))
          if let detail = m?.eventDetail { print(detail) }
          if let writes = m?.writesCaused { print("Writes caused: \(writes)") }
          for tree in log.callStackTree ?? [] {
            for (stackIndex, stack) in (tree.callStacks ?? []).enumerated() {
              if (tree.callStacks ?? []).count > 1 { print(bold("  Call stack \(stackIndex + 1)")) }
              var printed = 0
              for frame in stack.callStackRootFrames ?? [] { printFrame(frame, depth: 0, printed: &printed) }
              if frames > 0, printed >= frames { print("  … (more frames: --frames 0 prints them all)") }
            }
          }
        }
      }
    }

    /// A frame and the frames under it, indented by depth, up to `frames` lines.
    private func printFrame(_ frame: Diagnostics.Frame, depth: Int, printed: inout Int) {
      guard frames == 0 || printed < frames else { return }
      let mark = frame.isBlameFrame == true ? "▶ " : "  "
      let symbol = frame.symbolName ?? frame.rawFrame ?? frame.address ?? "?"
      // Apple sends empty strings for what it doesn't know (a system frame's file and line).
      let file = frame.fileName.flatMap { $0.isEmpty ? nil : $0 }
      let line = frame.lineNumber.flatMap { $0.isEmpty || $0 == "0" ? nil : $0 }
      let place = [frame.binaryName.flatMap { $0.isEmpty ? nil : $0 }, file.map { $0 + (line.map { ":\($0)" } ?? "") }]
        .compactMap(\.self).joined(separator: " · ")
      let samples = frame.sampleCount.map { " (\($0))" } ?? ""
      let text = "  " + String(repeating: " ", count: min(depth, 30)) + mark + symbol + (place.isEmpty ? "" : "  — \(place)") + samples
      print(frame.isBlameFrame == true ? bold(text) : text)
      printed += 1
      for sub in frame.subFrames ?? [] { printFrame(sub, depth: depth + 1, printed: &printed) }
    }
  }

  struct Metrics: AsyncParsableCommand {
    /// Apple's `percentile.fifty` as "50th (typical)", `percentile.ninety` as "90th".
    static func percentile(_ raw: String?) -> String {
      switch raw {
        case "percentile.fifty": "50th (typical)"
        case "percentile.ninety": "90th"
        case let raw?: raw.replacingOccurrences(of: "percentile.", with: "")
        case nil: "-"
      }
    }

    /// A value rounded by its size: 1050, 27.2, 0.35.
    static func value(_ value: Double) -> String {
      String(format: abs(value) >= 100 ? "%.0f" : abs(value) >= 10 ? "%.1f" : "%.2f", value)
    }

    static let configuration = CommandConfiguration(
      abstract: "Performance and power metrics across the app's recent versions (or one build).",
      discussion: """
        Each metric's value per version, for all devices at the typical (50th) and worst-case \
        (90th) percentiles; --device narrows to a device kind, --all shows every device and \
        percentile. Apple's regressions and trends come first.
        """
    )

    @Argument(help: "The app's bundle ID or alias.", completion: appAliasCompletion)
    var app: String

    @Option(name: .long, help: "Build number: that build's metrics only.")
    var build: String?

    @OptionGroup var platformOption: PlatformOption

    @Option(name: .long, help: "launch, hang, memory, disk, battery, termination, animation or storage; comma-separated.")
    var type: String?

    @Flag(name: .long, help: "Every device and percentile, not only all devices.")
    var all = false

    @OptionGroup var jsonOption: JSONOption

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: app, client: client)
      let types = try DiagnosticsCommand.types(type, among: AscelerateCore.Diagnostics.metricTypes, name: "metric type")
      var buildID: String?
      if build != nil {
        buildID = try await DiagnosticsCommand.build(appID: app.id, number: build, platform: try platformOption.parsed(), client: client).id
      }
      let metrics = try await AscelerateCore.Diagnostics.metrics(appID: app.id, buildID: buildID, types: types, client: client)
      if jsonOption.json { try printJSON(metrics); return }
      let insights = (metrics.insights?.regressions ?? []).map { ("Regression", $0) } + (metrics.insights?.trendingUp ?? []).map { ("Trending up", $0) }
      for (kind, insight) in insights {
        print(yellow("\(kind): ") + (insight.summaryString ?? [insight.metricCategory, insight.metric].compactMap(\.self).joined(separator: " ")))
      }
      if !insights.isEmpty { print() }
      var any = false
      for product in metrics.productData ?? [] {
        for category in product.metricCategories ?? [] {
          for metric in category.metrics ?? [] {
            let datasets = (metric.datasets ?? []).filter { all || ($0.filterCriteria?.device ?? "all").lowercased().hasPrefix("all") }
            guard !datasets.isEmpty else { continue }
            any = true
            let versions = Array(Set(datasets.flatMap { $0.points ?? [] }.compactMap(\.version)))
              .sorted { $0.compare($1, options: .numeric) == .orderedAscending }.suffix(6)
            print(bold(formatState(category.identifier ?? "-") + " · " + formatFieldName(metric.identifier ?? "-"))
              + (metric.unit?.displayName.map { " (\($0))" } ?? ""))
            Table.print(
              headers: ["Devices", "Percentile"] + versions,
              rows: datasets.map { set in
                let c = set.filterCriteria
                return [c?.deviceMarketingName ?? c?.device ?? "-", Self.percentile(c?.percentile)] + versions.map { version in
                  set.points?.first { $0.version == version }?.value.map(Self.value) ?? "-"
                }
              })
            print()
          }
        }
      }
      if !any { print("No metrics yet. They come from users' devices that share analytics, and need enough of them.") }
    }
  }
}
