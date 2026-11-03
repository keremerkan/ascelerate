import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

/// Xcode Cloud: products, workflows, build runs and what each run produced.
struct XcodeCloudCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "xcode-cloud",
    abstract: "Xcode Cloud products, workflows and build runs.",
    discussion: """
      A product is made in Xcode when its repository is first connected (Integrate > Create Workflow); the API can't make one. A product is named by its app's bundle ID (or \
      alias), its name or its ID; a workflow by its name or ID; a build run by its number or ID.
      """,
    subcommands: [
      Products.self, Workflows.self, Runs.self, Start.self, Rerun.self, Repositories.self, XcodeVersions.self,
    ]
  )

  static let productHelp = ArgumentHelp("The product: its app's bundle ID or alias, its name, or its ID.")
  static let aliasCompletion = CompletionKind.shellCommand(
    "grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'")

  // MARK: Lookups

  /// A product by its ID, name (case-insensitive) or app's bundle ID (aliases resolved).
  static func findProduct(_ ref: String, client: ASCClient) async throws -> XcodeCloud.Product {
    let products = try await XcodeCloud.products(client: client)
    let bundleID = resolveAlias(ref)
    if let match = products.first(where: {
      $0.id == ref || $0.bundleID == bundleID || $0.name?.lowercased() == ref.lowercased()
    }) {
      return match
    }
    let names = products.map { $0.bundleID ?? $0.name ?? $0.id }
    throw ValidationError(
      "No Xcode Cloud product '\(ref)'."
        + (names.isEmpty
          ? " The team has none yet: set one up in Xcode (Integrate > Create Workflow)."
          : " Products: \(names.joined(separator: ", ")).")
    )
  }

  static func findWorkflow(_ ref: String, product: XcodeCloud.Product, client: ASCClient) async throws -> XcodeCloud.Workflow {
    let workflows = try await XcodeCloud.workflows(productID: product.id, client: client)
    if let match = workflows.first(where: { $0.id == ref || $0.name?.lowercased() == ref.lowercased() }) {
      return match
    }
    let names = workflows.compactMap(\.name)
    throw ValidationError(
      "No workflow '\(ref)' in \(productName(product))." + (names.isEmpty ? "" : " Workflows: \(names.joined(separator: ", ")).")
    )
  }

  /// A build run by its number (searched newest first) or ID.
  static func findRun(_ ref: String, product: XcodeCloud.Product, client: ASCClient) async throws -> XcodeCloud.Run {
    guard let number = Int(ref) else { return try await XcodeCloud.run(id: ref, client: client) }
    var link: String?
    repeat {
      let page = try await XcodeCloud.runsPage(productID: product.id, link: link, pageSize: 200, client: client)
      if let run = page.runs.first(where: { $0.number == number }) { return run }
      // Newest first: once past the number, it isn't there.
      if let last = page.runs.last?.number, last < number { break }
      link = page.next
    } while link != nil
    throw ValidationError("No build run \(number) in \(productName(product)).")
  }

  static func productName(_ product: XcodeCloud.Product) -> String {
    product.name ?? product.bundleID ?? product.id
  }

  // MARK: Display

  /// A run's or action's state: its result once complete, else its progress.
  static func state(progress: String?, status: String?) -> String {
    guard progress == "COMPLETE", let status else { return formatState(progress ?? "-") }
    return switch status {
      case "SUCCEEDED": green(formatState(status))
      case "FAILED", "ERRORED": red(formatState(status))
      default: yellow(formatState(status))
    }
  }

  static func duration(from start: Date?, to end: Date?) -> String {
    guard let start else { return "-" }
    let seconds = Int((end ?? .now).timeIntervalSince(start))
    return seconds < 60 ? "\(seconds)s" : seconds < 3600 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds / 3600)h \(seconds / 60 % 60)m"
  }

  /// "2 errors, 5 warnings" (the non-zero counts), or "-".
  static func issueSummary(_ counts: XcodeCloud.IssueCounts) -> String {
    let parts = [
      (counts.errors, "error"), (counts.testFailures, "test failure"), (counts.warnings, "warning"),
      (counts.analyzerWarnings, "analyzer warning"),
    ].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
    return parts.isEmpty ? "-" : parts.joined(separator: ", ")
  }

  /// The branch, tag or pull request a run built.
  static func source(_ run: XcodeCloud.Run) -> String {
    if let number = run.pullRequestNumber { return "PR #\(number)" + (run.pullRequestTitle.map { " \($0)" } ?? "") }
    return run.reference.map { run.referenceKind == "TAG" ? "tag \($0)" : $0 } ?? "-"
  }

  static func startConditionText(_ condition: XcodeCloud.StartCondition) -> String {
    let what = condition.patterns.isEmpty ? "any" : condition.patterns.joined(separator: ", ")
    return switch condition.kind {
      case "branch": "Branch changes: \(what)"
      case "tag": "Tag changes: \(what)"
      case "pullRequest": "Pull requests into: \(what)"
      case "schedule": "Schedule: \(condition.schedule ?? "-") on \(what)"
      case "manualBranch": "By hand, branches: \(what)"
      case "manualTag": "By hand, tags: \(what)"
      case "manualPullRequest": "By hand, pull requests into: \(what)"
      default: "\(condition.kind): \(what)"
    }
  }

  // MARK: Products

  struct Products: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the team's Xcode Cloud products (apps and frameworks).")

    @OptionGroup var jsonOption: JSONOption

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let products = try await XcodeCloud.products(client: client)
      if jsonOption.json { try printJSON(products); return }
      guard !products.isEmpty else {
        print("No Xcode Cloud products. Set one up in Xcode: Integrate > Create Workflow.")
        return
      }
      Table.print(
        headers: ["Name", "Type", "Bundle ID", "Repository", "Created"],
        rows: products.map {
          [
            $0.name ?? "-", formatState($0.type ?? "-"), $0.bundleID ?? "-", $0.repositories.joined(separator: ", "),
            $0.createdDate.map(formatDate) ?? "-",
          ]
        })
    }
  }

  // MARK: Workflows

  struct Workflows: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "A product's workflows.",
      subcommands: [List.self, Info.self, Update.self, Enable.self, Disable.self, Delete.self],
      defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "List a product's workflows.")

      @Argument(help: XcodeCloudCommand.productHelp, completion: XcodeCloudCommand.aliasCompletion)
      var product: String

      @OptionGroup var jsonOption: JSONOption

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let product = try await XcodeCloudCommand.findProduct(product, client: client)
        let workflows = try await XcodeCloud.workflows(productID: product.id, client: client)
        if jsonOption.json { try printJSON(workflows); return }
        guard !workflows.isEmpty else {
          print("\(XcodeCloudCommand.productName(product)) has no workflows.")
          return
        }
        Table.print(
          headers: ["Name", "Enabled", "Actions", "Starts on", "Xcode"],
          rows: workflows.map { w in
            [
              w.name ?? w.id, w.isEnabled ? green("Yes") : yellow("No"),
              w.actions.map { formatState($0.type ?? "-") }.joined(separator: ", "),
              w.startConditions.map { XcodeCloudCommand.startConditionText($0) }.joined(separator: "; "),
              w.xcodeVersion ?? "-",
            ]
          })
      }
    }

    struct Info: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "A workflow's actions, start conditions and environment.")

      @Argument(help: XcodeCloudCommand.productHelp, completion: XcodeCloudCommand.aliasCompletion)
      var product: String

      @Argument(help: "The workflow's name or ID.")
      var workflow: String

      @OptionGroup var jsonOption: JSONOption

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let product = try await XcodeCloudCommand.findProduct(product, client: client)
        let w = try await XcodeCloudCommand.findWorkflow(workflow, product: product, client: client)
        if jsonOption.json { try printJSON(w); return }
        print(bold(w.name ?? w.id) + (w.isEnabled ? "" : yellow(" disabled")) + (w.isLockedForEditing ? yellow(" (being edited)") : ""))
        if let description = w.description, !description.isEmpty { print(description) }
        print()
        Table.print(
          headers: ["", ""],
          rows: [
            ["Repository", w.repository ?? "-"],
            ["Project", w.containerFilePath ?? "-"],
            ["Xcode", w.xcodeVersion ?? "-"],
            ["macOS", w.macOSVersion ?? "-"],
            ["Clean builds", w.clean ? "Yes" : "No"],
            ["Last modified", w.lastModifiedDate.map(formatDate) ?? "-"],
          ])
        print()
        print(bold("Start conditions"))
        if w.startConditions.isEmpty { print("  None") }
        for condition in w.startConditions { print("  \(XcodeCloudCommand.startConditionText(condition))") }
        print()
        print(bold("Actions"))
        Table.print(
          headers: ["Name", "Type", "Scheme", "Platform", "Required", "Distribution"],
          rows: w.actions.map { a in
            [
              a.name ?? "-", formatState(a.type ?? "-"), a.scheme ?? "-", formatState(a.platform ?? "-"),
              a.isRequiredToPass ? "Yes" : "No", a.distribution.map { formatState($0) } ?? a.testPlan.map { "Test plan \($0)" } ?? "-",
            ]
          })
      }
    }

    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Change a workflow.")

      @Argument(help: XcodeCloudCommand.productHelp, completion: XcodeCloudCommand.aliasCompletion)
      var product: String

      @Argument(help: "The workflow's name or ID.")
      var workflow: String

      @Flag(name: .long, help: "Start it only by hand: removes its branch, tag, pull request and schedule start conditions.")
      var manualOnly = false

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func validate() throws {
        guard manualOnly else { throw ValidationError("Nothing to change. Pass --manual-only.") }
      }

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let product = try await XcodeCloudCommand.findProduct(product, client: client)
        let w = try await XcodeCloudCommand.findWorkflow(workflow, product: product, client: client)
        let automatic = w.startConditions.filter { XcodeCloud.automaticStartKinds.contains($0.kind) }
        let manual = w.startConditions.filter { !XcodeCloud.automaticStartKinds.contains($0.kind) }
        guard !automatic.isEmpty else {
          print("Workflow '\(w.name ?? w.id)' already starts only by hand.")
          return
        }
        guard !manual.isEmpty else {
          throw ValidationError(
            "Workflow '\(w.name ?? w.id)' has no manual start condition, and Xcode Cloud wants at least one. Add one in Xcode or App Store Connect first.")
        }
        print("Workflow '\(w.name ?? w.id)' stops starting on:")
        for condition in automatic { print("  \(XcodeCloudCommand.startConditionText(condition))") }
        print("It can still be started:")
        for condition in manual { print("  \(XcodeCloudCommand.startConditionText(condition))") }
        guard confirm("Change it? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        try await XcodeCloud.removeAutomaticStarts(workflowID: w.id, client: client)
        print(green("Updated") + " workflow '\(w.name ?? w.id)': it starts only by hand now.")
      }
    }

    struct Enable: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Turn a workflow on: it starts builds again.")

      @Argument(help: XcodeCloudCommand.productHelp, completion: XcodeCloudCommand.aliasCompletion)
      var product: String

      @Argument(help: "The workflow's name or ID.")
      var workflow: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        try await XcodeCloudCommand.setEnabled(true, product: product, workflow: workflow, yes: yes)
      }
    }

    struct Disable: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Turn a workflow off: it starts no builds, on its own or by hand.")

      @Argument(help: XcodeCloudCommand.productHelp, completion: XcodeCloudCommand.aliasCompletion)
      var product: String

      @Argument(help: "The workflow's name or ID.")
      var workflow: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        try await XcodeCloudCommand.setEnabled(false, product: product, workflow: workflow, yes: yes)
      }
    }

    struct Delete: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Delete a workflow (its build runs stay).")

      @Argument(help: XcodeCloudCommand.productHelp, completion: XcodeCloudCommand.aliasCompletion)
      var product: String

      @Argument(help: "The workflow's name or ID.")
      var workflow: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let product = try await XcodeCloudCommand.findProduct(product, client: client)
        let w = try await XcodeCloudCommand.findWorkflow(workflow, product: product, client: client)
        guard confirm("Delete workflow '\(w.name ?? w.id)' of \(XcodeCloudCommand.productName(product))? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        try await XcodeCloud.deleteWorkflow(id: w.id, client: client)
        print(green("Deleted") + " workflow '\(w.name ?? w.id)'.")
      }
    }
  }

  static func setEnabled(_ isEnabled: Bool, product ref: String, workflow ref2: String, yes: Bool) async throws {
    if yes { autoConfirm = true }
    let client = try ClientFactory.makeClient()
    let product = try await findProduct(ref, client: client)
    let w = try await findWorkflow(ref2, product: product, client: client)
    guard w.isEnabled != isEnabled else {
      print("Workflow '\(w.name ?? w.id)' is already \(isEnabled ? "on" : "off").")
      return
    }
    guard confirm("Turn workflow '\(w.name ?? w.id)' \(isEnabled ? "on" : "off")? [y/N] ") else {
      print(yellow("Cancelled."))
      return
    }
    try await XcodeCloud.setEnabled(workflowID: w.id, isEnabled, client: client)
    print(green(isEnabled ? "Enabled" : "Disabled") + " workflow '\(w.name ?? w.id)'.")
  }

  // MARK: Build runs

  struct Runs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "A product's build runs and what each one produced.",
      subcommands: [List.self, Info.self, Issues.self, Tests.self, Artifacts.self],
      defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "List a product's build runs, newest first.")

      @Argument(help: XcodeCloudCommand.productHelp, completion: XcodeCloudCommand.aliasCompletion)
      var product: String

      @Option(name: .long, help: "Only this workflow's runs (name or ID).")
      var workflow: String?

      @Option(name: .long, help: "How many runs (default 25).")
      var limit = 25

      @OptionGroup var jsonOption: JSONOption

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let product = try await XcodeCloudCommand.findProduct(product, client: client)
        var workflowID: String?
        if let workflow { workflowID = try await XcodeCloudCommand.findWorkflow(workflow, product: product, client: client).id }
        let runs = try await XcodeCloud.runs(productID: product.id, workflowID: workflowID, limit: limit, client: client)
        if jsonOption.json { try printJSON(runs); return }
        guard !runs.isEmpty else {
          print("No build runs yet.")
          return
        }
        Table.print(
          headers: ["#", "Workflow", "State", "Source", "Commit", "Started", "Duration", "Issues"],
          rows: runs.map { r in
            [
              r.number.map(String.init) ?? "-", r.workflowName ?? "-",
              XcodeCloudCommand.state(progress: r.progress, status: r.status), XcodeCloudCommand.source(r),
              r.commit?.sha.map { String($0.prefix(7)) } ?? "-",
              (r.startedDate ?? r.createdDate).map(formatDate) ?? "-",
              XcodeCloudCommand.duration(from: r.startedDate, to: r.finishedDate), XcodeCloudCommand.issueSummary(r.issues),
            ]
          })
      }
    }

    struct Info: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "A build run's details and its actions.")

      @Argument(help: XcodeCloudCommand.productHelp, completion: XcodeCloudCommand.aliasCompletion)
      var product: String

      @Argument(help: "The run's number or ID.")
      var run: String

      @OptionGroup var jsonOption: JSONOption

      private struct Result: Encodable {
        let run: XcodeCloud.Run
        let actions: [XcodeCloud.BuildAction]
      }

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let product = try await XcodeCloudCommand.findProduct(product, client: client)
        let r = try await XcodeCloudCommand.findRun(run, product: product, client: client)
        let actions = try await XcodeCloud.actions(runID: r.id, client: client)
        if jsonOption.json { try printJSON(Result(run: r, actions: actions)); return }
        print(bold("Build \(r.number.map(String.init) ?? r.id)") + " · \(r.workflowName ?? "-") · "
          + XcodeCloudCommand.state(progress: r.progress, status: r.status))
        let sha: String? = r.commit?.sha.map { String($0.prefix(7)) }
        let subject: String? = r.commit?.message?.split(separator: "\n").first.map(String.init)
        let commit = [sha, subject].compactMap { $0 }.joined(separator: " ")
        let started: Date? = r.startedDate ?? r.createdDate
        var rows: [[String]] = [
          ["Source", XcodeCloudCommand.source(r)],
          ["Commit", commit.isEmpty ? "-" : commit],
          ["Author", r.commit?.author ?? "-"],
          ["Started by", r.startReason.map { formatState($0) } ?? "-"],
          ["Started", started.map(formatDate) ?? "-"],
          ["Duration", XcodeCloudCommand.duration(from: r.startedDate, to: r.finishedDate)],
          ["Issues", XcodeCloudCommand.issueSummary(r.issues)],
        ]
        if let reason = r.cancelReason { rows.append(["Cancelled", reason]) }
        if let url = r.commit?.url { rows.append(["Commit link", url]) }
        Table.print(headers: ["", ""], rows: rows)
        print()
        Table.print(
          headers: ["Action", "Type", "State", "Duration", "Issues"],
          rows: actions.map { a in
            [
              a.name ?? "-", formatState(a.type ?? "-"), XcodeCloudCommand.state(progress: a.progress, status: a.status),
              XcodeCloudCommand.duration(from: a.startedDate, to: a.finishedDate), XcodeCloudCommand.issueSummary(a.issues),
            ]
          })
      }
    }

    struct Issues: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "A build run's errors and warnings, per action.")

      @Argument(help: XcodeCloudCommand.productHelp, completion: XcodeCloudCommand.aliasCompletion)
      var product: String

      @Argument(help: "The run's number or ID.")
      var run: String

      @Flag(name: .long, help: "Errors only (no warnings).")
      var errors = false

      @OptionGroup var jsonOption: JSONOption

      private struct Entry: Encodable {
        let action: String?
        let issue: XcodeCloud.Issue
      }

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let product = try await XcodeCloudCommand.findProduct(product, client: client)
        let r = try await XcodeCloudCommand.findRun(run, product: product, client: client)
        var entries: [Entry] = []
        for action in try await XcodeCloud.actions(runID: r.id, client: client) {
          entries += try await XcodeCloud.issues(actionID: action.id, client: client)
            .filter { !errors || $0.type == "ERROR" }
            .map { Entry(action: action.name, issue: $0) }
        }
        if jsonOption.json { try printJSON(entries); return }
        guard !entries.isEmpty else {
          print(errors ? "No errors." : "No issues.")
          return
        }
        for e in entries {
          let type = e.issue.type ?? "-"
          let label = type == "ERROR" || type == "TEST_FAILURE" ? red(formatState(type)) : yellow(formatState(type))
          let place = e.issue.path.map { $0 + (e.issue.line.map { ":\($0)" } ?? "") }
          print("\(label) [\(e.action ?? "-")]" + (place.map { " \($0)" } ?? ""))
          print("  \(e.issue.message ?? "-")")
        }
      }
    }

    struct Tests: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "A build run's test results.")

      @Argument(help: XcodeCloudCommand.productHelp, completion: XcodeCloudCommand.aliasCompletion)
      var product: String

      @Argument(help: "The run's number or ID.")
      var run: String

      @Flag(name: .long, help: "Only tests that failed somewhere.")
      var failed = false

      @OptionGroup var jsonOption: JSONOption

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let product = try await XcodeCloudCommand.findProduct(product, client: client)
        let r = try await XcodeCloudCommand.findRun(run, product: product, client: client)
        var results: [XcodeCloud.TestResult] = []
        for action in try await XcodeCloud.actions(runID: r.id, client: client) where action.type == "TEST" {
          results += try await XcodeCloud.testResults(actionID: action.id, client: client)
        }
        if failed { results = results.filter { ["FAILURE", "MIXED"].contains($0.status) } }
        if jsonOption.json { try printJSON(results); return }
        guard !results.isEmpty else {
          print(failed ? "No failed tests." : "No test results.")
          return
        }
        Table.print(
          headers: ["Test", "Status", "Destinations"],
          rows: results.map { t in
            let status = t.status ?? "-"
            return [
              [t.className, t.name].compactMap { $0 }.joined(separator: "."),
              status == "SUCCESS" ? green(formatState(status)) : status == "FAILURE" || status == "MIXED" ? red(formatState(status)) : formatState(status),
              t.destinations.map { [$0.deviceName, $0.osVersion].compactMap { $0 }.joined(separator: " ") }.joined(separator: ", "),
            ]
          })
        for t in results where t.message != nil && t.status != "SUCCESS" {
          print()
          print(red([t.className, t.name].compactMap { $0 }.joined(separator: ".")) + (t.path.map { " \($0)" + (t.line.map { ":\($0)" } ?? "") } ?? ""))
          print("  \(t.message ?? "")")
        }
      }
    }

    struct Artifacts: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "A build run's artifacts (logs, archives, products), or download them.")

      @Argument(help: XcodeCloudCommand.productHelp, completion: XcodeCloudCommand.aliasCompletion)
      var product: String

      @Argument(help: "The run's number or ID.")
      var run: String

      @Option(name: .long, help: "Download them into this folder.")
      var download: String?

      @Option(name: .long, help: "Only artifacts of these types, comma-separated (e.g. LOG_BUNDLE,ARCHIVE).")
      var type: String?

      @OptionGroup var jsonOption: JSONOption

      private struct Entry: Encodable {
        let action: String?
        let artifact: XcodeCloud.Artifact
      }

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let product = try await XcodeCloudCommand.findProduct(product, client: client)
        let r = try await XcodeCloudCommand.findRun(run, product: product, client: client)
        let types = type.map { Set($0.uppercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }) }
        var entries: [Entry] = []
        for action in try await XcodeCloud.actions(runID: r.id, client: client) {
          entries += try await XcodeCloud.artifacts(actionID: action.id, client: client)
            .filter { a in types.map { a.type.map($0.contains) ?? false } ?? true }
            .map { Entry(action: action.name, artifact: $0) }
        }
        if let download {
          let folder = URL(filePath: expandPath(download))
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          for e in entries {
            let name = e.artifact.fileName ?? e.artifact.id
            print("Downloading \(name)…", terminator: "")
            fflush(stdout)
            try await XcodeCloud.download(artifactID: e.artifact.id, to: folder.appending(path: name), client: client)
            print(" " + green("done"))
          }
          print("\(entries.count) artifact\(entries.count == 1 ? "" : "s") in \(folder.path(percentEncoded: false))")
          return
        }
        if jsonOption.json { try printJSON(entries); return }
        guard !entries.isEmpty else {
          print("No artifacts.")
          return
        }
        Table.print(
          headers: ["Action", "File", "Type", "Size"],
          rows: entries.map {
            [$0.action ?? "-", $0.artifact.fileName ?? "-", formatState($0.artifact.type ?? "-"), $0.artifact.size.map(formatBytes) ?? "-"]
          })
      }
    }
  }

  // MARK: Starting

  struct Start: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Start a workflow's build: on a branch, a tag or a pull request.",
      discussion: "Without --branch, --tag or --pull-request, Xcode Cloud builds what the workflow's start condition allows by hand."
    )

    @Argument(help: XcodeCloudCommand.productHelp, completion: XcodeCloudCommand.aliasCompletion)
    var product: String

    @Argument(help: "The workflow's name or ID.")
    var workflow: String

    @Option(name: .long, help: "Build this branch.")
    var branch: String?

    @Option(name: .long, help: "Build this tag.")
    var tag: String?

    @Option(name: .long, help: "Build this pull request (its number).")
    var pullRequest: Int?

    @Flag(name: .long, help: "Build without the cache.")
    var clean = false

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func validate() throws {
      if [branch != nil, tag != nil, pullRequest != nil].filter({ $0 }).count > 1 {
        throw ValidationError("Pass only one of --branch, --tag and --pull-request.")
      }
    }

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let product = try await XcodeCloudCommand.findProduct(product, client: client)
      let w = try await XcodeCloudCommand.findWorkflow(workflow, product: product, client: client)
      var referenceID: String?
      var pullRequestID: String?
      var what = "what the workflow allows by hand"
      if branch != nil || tag != nil || pullRequest != nil {
        guard let repositoryID = w.repositoryID else { throw ValidationError("Workflow '\(w.name ?? w.id)' has no repository.") }
        if let number = pullRequest {
          let requests = try await XcodeCloud.pullRequests(repositoryID: repositoryID, client: client)
          guard let request = requests.first(where: { $0.number == number }) else {
            throw ValidationError("No pull request #\(number) in \(w.repository ?? "the repository").")
          }
          pullRequestID = request.id
          what = "pull request #\(number)" + (request.title.map { " (\($0))" } ?? "")
        } else {
          let name = branch ?? tag ?? ""
          let kind = branch != nil ? "BRANCH" : "TAG"
          let references = try await XcodeCloud.gitReferences(repositoryID: repositoryID, client: client)
          guard let reference = references.first(where: { $0.kind == kind && $0.name == name }) else {
            throw ValidationError("No \(kind == "BRANCH" ? "branch" : "tag") '\(name)' in \(w.repository ?? "the repository").")
          }
          referenceID = reference.id
          what = kind == "BRANCH" ? "branch \(name)" : "tag \(name)"
        }
      }
      guard w.isEnabled else { throw ValidationError("Workflow '\(w.name ?? w.id)' is off. Turn it on with 'xcode-cloud workflows enable'.") }
      guard confirm("Start '\(w.name ?? w.id)' of \(XcodeCloudCommand.productName(product)) on \(what)\(clean ? ", clean" : "")? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      let run = try await XcodeCloud.start(
        workflowID: w.id, gitReferenceID: referenceID, pullRequestID: pullRequestID, clean: clean ? true : nil, client: client)
      print(green("Started") + " build \(run.number.map(String.init) ?? run.id).")
    }
  }

  struct Rerun: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Build an earlier run's commit again, with its workflow.")

    @Argument(help: XcodeCloudCommand.productHelp, completion: XcodeCloudCommand.aliasCompletion)
    var product: String

    @Argument(help: "The run's number or ID.")
    var run: String

    @Flag(name: .long, help: "Build without the cache.")
    var clean = false

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let product = try await XcodeCloudCommand.findProduct(product, client: client)
      let earlier = try await XcodeCloudCommand.findRun(run, product: product, client: client)
      guard let workflowID = earlier.workflowID else { throw ValidationError("Build \(run) has no workflow any more.") }
      guard confirm("Build \(earlier.number.map(String.init) ?? earlier.id) (\(XcodeCloudCommand.source(earlier))) again\(clean ? ", clean" : "")? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      let started = try await XcodeCloud.start(workflowID: workflowID, rerunOf: earlier.id, clean: clean ? true : nil, client: client)
      print(green("Started") + " build \(started.number.map(String.init) ?? started.id).")
    }
  }

  // MARK: Reference

  struct Repositories: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the repositories Xcode Cloud can reach.")

    @OptionGroup var jsonOption: JSONOption

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let repositories = try await XcodeCloud.repositories(client: client)
      if jsonOption.json { try printJSON(repositories); return }
      guard !repositories.isEmpty else {
        print("No repositories. Xcode connects one when you set up a product.")
        return
      }
      Table.print(
        headers: ["Repository", "Clone URL", "Last accessed"],
        rows: repositories.map {
          [
            [$0.owner, $0.name].compactMap { $0 }.joined(separator: "/"), $0.httpCloneURL ?? $0.sshCloneURL ?? "-",
            $0.lastAccessedDate.map(formatDate) ?? "-",
          ]
        })
    }
  }

  struct XcodeVersions: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "xcode-versions", abstract: "List the Xcode versions Xcode Cloud offers, with the macOS versions each runs on.")

    @OptionGroup var jsonOption: JSONOption

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let versions = try await XcodeCloud.xcodeVersions(client: client)
      if jsonOption.json { try printJSON(versions); return }
      Table.print(
        headers: ["Xcode", "Version", "macOS"],
        rows: versions.map { [$0.name ?? "-", $0.version ?? "-", $0.macOSVersions.joined(separator: ", ")] })
    }
  }
}
