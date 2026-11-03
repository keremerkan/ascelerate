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


  /// The settings `workflows update` and `workflows create` change.
  struct WorkflowOptions: ParsableArguments {
    @Option(name: .long, help: "The name (new name for update).")
    var name: String?

    @Option(name: .long, help: "New description ('' clears it).")
    var description: String?

    @Option(name: .long, help: "Build without Xcode Cloud's cache: true or false.")
    var clean: Bool?

    @Option(name: .long, help: "Only Admins and App Managers may change it: true or false.")
    var restrictEditing: Bool?

    @Option(name: .long, help: "Xcode version: its name or version (Latest Release, Xcode 27.2, 27B52).")
    var xcode: String?

    @Option(name: .long, help: "macOS version: its name or version, among those the Xcode version runs on.")
    var macos: String?

    @Option(name: .long, help: "Start on changes to these branches, 'any', or 'off'.")
    var branchChanges: String?

    @Option(name: .long, help: "Start on changes to these tags, 'any', or 'off'.")
    var tagChanges: String?

    @Option(name: .long, help: "Start on pull requests into these branches, 'any', or 'off'.")
    var pullRequests: String?

    @Option(name: .long, help: "The pull requests' source branches (with --pull-requests), or 'any'.")
    var pullRequestSource: String?

    @Option(name: .long, help: "A newer change cancels a running build (branch, tag and pull request conditions): true or false.")
    var autoCancel: Bool?

    @Flag(name: .long, help: "Remove its schedule.")
    var removeSchedule = false

    @Option(name: .long, help: "May be started by hand on these branches, 'any', or 'off'.")
    var manualBranches: String?

    @Option(name: .long, help: "May be started by hand on these tags, 'any', or 'off'.")
    var manualTags: String?

    @Option(name: .long, help: "May be started by hand on pull requests into these branches, 'any', or 'off'.")
    var manualPullRequests: String?

    @Flag(name: .long, help: "Start it only by hand: removes its branch, tag, pull request and schedule start conditions.")
    var manualOnly = false

    @Option(name: .long, parsing: .singleValue, help: ArgumentHelp(
      "An action as TYPE:SCHEME[:PLATFORM] (build, test, analyze, archive; ios, macos, tvos, watchos, visionos); repeat for several. Replaces the actions.",
      valueName: "action"))
    var action: [String] = []

    @Option(name: .long, help: "Archive actions' distribution preparation: internal (TestFlight internal testing only), app-store (App Store Connect: TestFlight and the App Store, nothing submitted), or none.")
    var distribution: String?

    /// Applies the options; returns the Xcode and macOS versions' names by ID, for the change list.
    func apply(to edit: inout XcodeCloud.WorkflowEdit, client: ASCClient) async throws -> [String: String] {
      var versionNames: [String: String] = [:]
      if let name { edit.name = name }
      if let description { edit.description = description }
      if let clean { edit.clean = clean }
      if let restrictEditing { edit.isLockedForEditing = restrictEditing }
      if xcode != nil || macos != nil {
        let versions = try await XcodeCloud.xcodeVersions(client: client)
        for version in versions {
          versionNames[version.id] = version.name
          for option in version.macOSOptions { versionNames[option.id] = option.name }
        }
        if let xcode {
          guard let match = versions.first(where: { [$0.id, $0.name, $0.version].contains(xcode) }) else {
            throw ValidationError("No Xcode version '\(xcode)'. Versions: \(versions.compactMap(\.name).joined(separator: ", ")).")
          }
          edit.xcodeVersionID = match.id
        }
        let options = versions.first { $0.id == edit.xcodeVersionID }?.macOSOptions ?? []
        if let macos {
          guard let match = options.first(where: { [$0.id, $0.name].contains(macos) || $0.name.hasSuffix(macos) }) else {
            throw ValidationError("No macOS version '\(macos)' for this Xcode version. Versions: \(options.map(\.name).joined(separator: ", ")).")
          }
          edit.macOSVersionID = match.id
        } else if !options.contains(where: { $0.id == edit.macOSVersionID }) {
          // The new Xcode version doesn't run on the current macOS version.
          edit.macOSVersionID = options.first?.id
        }
      }
      if manualOnly {
        (edit.branch, edit.tag, edit.pullRequest, edit.hasSchedule) = (nil, nil, nil, false)
      }
      if let branchChanges {
        edit.branch = try Self.patterns(branchChanges).map { XcodeCloud.ChangeStart(source: $0, autoCancel: edit.branch?.autoCancel ?? true) }
      }
      if let tagChanges {
        edit.tag = try Self.patterns(tagChanges).map { XcodeCloud.ChangeStart(source: $0, autoCancel: edit.tag?.autoCancel ?? true) }
      }
      if let pullRequests {
        edit.pullRequest = try Self.patterns(pullRequests).map {
          XcodeCloud.PullRequestStart(source: edit.pullRequest?.source ?? .any, destination: $0, autoCancel: edit.pullRequest?.autoCancel ?? true)
        }
      }
      if let pullRequestSource {
        guard edit.pullRequest != nil else { throw ValidationError("--pull-request-source needs a pull request condition (--pull-requests).") }
        guard let source = try Self.patterns(pullRequestSource) else { throw ValidationError("--pull-request-source takes branches or 'any'.") }
        edit.pullRequest?.source = source
      }
      if let autoCancel {
        edit.branch?.autoCancel = autoCancel
        edit.tag?.autoCancel = autoCancel
        edit.pullRequest?.autoCancel = autoCancel
      }
      if removeSchedule { edit.hasSchedule = false }
      if let manualBranches { edit.manualBranch = try Self.patterns(manualBranches) }
      if let manualTags { edit.manualTag = try Self.patterns(manualTags) }
      if let manualPullRequests {
        edit.manualPullRequest = try Self.patterns(manualPullRequests).map {
          XcodeCloud.PullRequestStart(source: edit.manualPullRequest?.source ?? .any, destination: $0, autoCancel: false)
        }
      }
      if !action.isEmpty {
        edit.actions = try action.map { try Self.action($0, among: edit.actions) }
      }
      if let distribution {
        let audience: String? = switch distribution.lowercased() {
          case "internal": "INTERNAL_ONLY"
          case "app-store", "appstore": "APP_STORE_ELIGIBLE"
          case "none": nil
          default: throw ValidationError("--distribution takes internal, app-store or none.")
        }
        guard edit.actions.contains(where: { $0.type == "ARCHIVE" }) else {
          throw ValidationError("--distribution needs an archive action.")
        }
        for i in edit.actions.indices where edit.actions[i].type == "ARCHIVE" { edit.actions[i].distribution = audience }
      }
      return versionNames
    }

    /// TYPE:SCHEME[:PLATFORM]. The workflow's action of that type, scheme and platform when it
    /// has one (keeping its name, destination and test settings); the platform defaults to that
    /// of one of its actions with the scheme.
    static func action(_ value: String, among existing: [XcodeCloud.WorkflowAction]) throws -> XcodeCloud.WorkflowAction {
      let parts = value.split(separator: ":", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
      guard (2...3).contains(parts.count), !parts[1].isEmpty else {
        throw ValidationError("An action is TYPE:SCHEME[:PLATFORM], like archive:MyApp:ios ('\(value)').")
      }
      let type = parts[0].uppercased()
      guard XcodeCloud.WorkflowAction.types.contains(type) else {
        throw ValidationError("No action type '\(parts[0])'. Types: build, test, analyze, archive.")
      }
      let scheme = parts[1]
      let platform: String
      if parts.count == 3 {
        platform = parts[2].uppercased().replacingOccurrences(of: "_", with: "")
        guard XcodeCloud.WorkflowAction.platforms.contains(platform) else {
          throw ValidationError("No platform '\(parts[2])'. Platforms: ios, macos, tvos, watchos, visionos.")
        }
      } else {
        let platforms = Set(existing.filter { $0.scheme == scheme }.map(\.platform))
        guard platforms.count == 1, let only = platforms.first else {
          throw ValidationError("Name the platform of '\(value)': TYPE:SCHEME:PLATFORM.")
        }
        platform = only
      }
      if let same = existing.first(where: { $0.type == type && $0.scheme == scheme && $0.platform == platform }) { return same }
      // Another action of the scheme and platform (a build becoming an archive) keeps its options.
      if var like = existing.first(where: { $0.scheme == scheme && $0.platform == platform }) {
        like.type = type
        like.name = XcodeCloud.WorkflowAction.defaultName(type: type, platform: platform)
        like.distribution = type == "ARCHIVE" ? "APP_STORE_ELIGIBLE" : nil
        return like
      }
      return XcodeCloud.WorkflowAction(
        type: type, scheme: scheme, platform: platform, distribution: type == "ARCHIVE" ? "APP_STORE_ELIGIBLE" : nil)
    }

    /// 'off' for none, 'any', or names (a trailing * for names that begin with it).
    static func patterns(_ value: String) throws -> XcodeCloud.NamePatterns? {
      switch value.lowercased() {
        case "off", "none": return nil
        case "any", "all": return .any
        default:
          let names = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
          guard !names.isEmpty else { throw ValidationError("Give branch or tag names, 'any', or 'off'.") }
          return XcodeCloud.NamePatterns(isAny: false, patterns: names.map {
            $0.hasSuffix("*") ? .init(pattern: String($0.dropLast()), isPrefix: true) : .init(pattern: $0, isPrefix: false)
          })
      }
    }

    static func text(_ patterns: XcodeCloud.NamePatterns?) -> String {
      guard let patterns else { return "off" }
      return patterns.isAny ? "any" : patterns.patterns.map { $0.pattern + ($0.isPrefix ? "*" : "") }.joined(separator: ", ")
    }

    /// What a save would change, a line each.
    static func changes(from old: XcodeCloud.WorkflowEdit, to new: XcodeCloud.WorkflowEdit, names: [String: String]) -> [String] {
      var lines: [String] = []
      func line(_ title: String, _ a: String, _ b: String) { if a != b { lines.append("\(title): \(a) → \(b)") } }
      line("Name", old.name, new.name)
      line("Description", old.description.isEmpty ? "-" : old.description, new.description.isEmpty ? "-" : new.description)
      line("Clean builds", "\(old.clean)", "\(new.clean)")
      line("Restrict editing", "\(old.isLockedForEditing)", "\(new.isLockedForEditing)")
      let name = { (id: String?) in id.map { names[$0] ?? $0 } ?? "-" }
      line("Xcode", name(old.xcodeVersionID), name(new.xcodeVersionID))
      line("macOS", name(old.macOSVersionID), name(new.macOSVersionID))
      // A change condition with "(auto-cancel)" when a newer change cancels a running build.
      let change = { (patterns: XcodeCloud.NamePatterns?, autoCancel: Bool?) in
        text(patterns) + (patterns != nil && autoCancel == true ? " (auto-cancel)" : "")
      }
      line("Branch changes", change(old.branch?.source, old.branch?.autoCancel), change(new.branch?.source, new.branch?.autoCancel))
      line("Tag changes", change(old.tag?.source, old.tag?.autoCancel), change(new.tag?.source, new.tag?.autoCancel))
      line(
        "Pull requests into", change(old.pullRequest?.destination, old.pullRequest?.autoCancel),
        change(new.pullRequest?.destination, new.pullRequest?.autoCancel))
      line("Pull requests from", text(old.pullRequest?.source), text(new.pullRequest?.source))
      line("Schedule", old.hasSchedule ? (old.scheduleText ?? "on") : "off", new.hasSchedule ? (new.scheduleText ?? "on") : "off")
      line("By hand, branches", text(old.manualBranch), text(new.manualBranch))
      line("By hand, tags", text(old.manualTag), text(new.manualTag))
      line("By hand, pull requests into", text(old.manualPullRequest?.destination), text(new.manualPullRequest?.destination))
      line("Actions", actions(old.actions), actions(new.actions))
      return lines
    }

    /// "Archive - iOS (MyApp, App Store Connect); Build - macOS (MyApp-macOS)".
    static func actions(_ actions: [XcodeCloud.WorkflowAction]) -> String {
      guard !actions.isEmpty else { return "-" }
      return actions.map { action in
        var details = [action.scheme]
        if action.type == "ARCHIVE" {
          let distribution = switch action.distribution {
            case "INTERNAL_ONLY": "TestFlight internal testing only"
            case "APP_STORE_ELIGIBLE": "App Store Connect"
            default: "no distribution"
          }
          details.append(distribution)
        }
        if !action.isRequiredToPass { details.append("not required to pass") }
        return "\(action.name) (\(details.joined(separator: ", ")))"
      }.joined(separator: "; ")
    }
  }

  struct Workflows: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "A product's workflows.",
      subcommands: [List.self, Info.self, Create.self, Update.self, Enable.self, Disable.self, Delete.self],
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
        print(bold(w.name ?? w.id) + (w.isEnabled ? "" : yellow(" disabled")) + (w.isLockedForEditing ? yellow(" (editing restricted)") : ""))
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

    struct Create: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Make a workflow as a copy of another one, with its own name, actions and start conditions.",
        discussion: """
          The copy keeps the workflow's repository, project or workspace, Xcode and macOS \
          versions, settings, start conditions and actions, apart from what the options change. \
          Environment variables and post-actions (TestFlight groups, notifications) aren't in the \
          API: add them in App Store Connect. Xcode makes a product with its first \
          workflow, so there is always one to copy. Options as for update; --action replaces the \
          actions: archive:MyApp:ios archives the MyApp scheme for iOS and \
          uploads it for TestFlight and the App Store unless --distribution says otherwise; \
          nothing goes to review on its own.

          ascelerate xcode-cloud workflows create MyApp --like Default --name "TestFlight" \\
            --action archive:MyApp:ios --manual-branches main
          """
      )

      @Argument(help: XcodeCloudCommand.productHelp, completion: XcodeCloudCommand.aliasCompletion)
      var product: String

      @Option(name: .long, help: "The workflow to copy, by name or ID (not needed when the product has one).")
      var like: String?

      @OptionGroup var options: WorkflowOptions

      @Flag(name: .long, help: "Create it turned off.")
      var disabled = false

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        guard let name = options.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
          throw ValidationError("Name the new workflow with --name.")
        }
        let client = try ClientFactory.makeClient()
        let product = try await XcodeCloudCommand.findProduct(product, client: client)
        let workflows = try await XcodeCloud.workflows(productID: product.id, client: client)
        guard !workflows.contains(where: { $0.name?.lowercased() == name.lowercased() }) else {
          throw ValidationError("\(product.name ?? product.id) already has a workflow named '\(name)'.")
        }
        let source: XcodeCloud.Workflow
        if let like {
          source = try await XcodeCloudCommand.findWorkflow(like, product: product, client: client)
        } else if workflows.count == 1 {
          source = workflows[0]
        } else {
          throw ValidationError("Name the workflow to copy with --like: \(workflows.compactMap(\.name).joined(separator: ", ")).")
        }
        let original = try await XcodeCloud.edit(workflowID: source.id, client: client)
        var edit = original
        let versionNames = try await options.apply(to: &edit, client: client)
        edit.isEnabled = !disabled
        guard edit.hasStartCondition else { throw ValidationError("A workflow needs a start condition.") }
        guard !edit.actions.isEmpty else { throw ValidationError("A workflow needs an action (--action).") }
        print("New workflow '\(name)' for \(product.name ?? product.id), a copy of '\(source.name ?? source.id)' with:")
        let changes = WorkflowOptions.changes(from: original, to: edit, names: versionNames).filter { !$0.hasPrefix("Name:") }
        for line in changes { print("  \(line)") }
        if !changes.contains(where: { $0.hasPrefix("Actions:") }) { print("  Actions: \(WorkflowOptions.actions(edit.actions))") }
        if disabled { print("  Turned off") }
        guard confirm("Create? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        let id = try await XcodeCloud.createWorkflow(edit, copying: source.id, client: client)
        print(green("Created") + " workflow '\(name)' (\(id)).")
      }
    }

    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Change a workflow's settings and start conditions.",
        discussion: """
          Start condition options take a comma-separated list of branch or tag names, a name \
          ending in * for names that begin with it (release/*), 'any', or 'off' to remove the \
          condition. --action replaces the actions (TYPE:SCHEME[:PLATFORM]; an action the \
          workflow has keeps its settings). Environment variables, post-actions and a schedule's \
          times are changed in App Store Connect.
          """
      )

      @Argument(help: XcodeCloudCommand.productHelp, completion: XcodeCloudCommand.aliasCompletion)
      var product: String

      @Argument(help: "The workflow's name or ID.")
      var workflow: String

      @OptionGroup var options: WorkflowOptions

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let product = try await XcodeCloudCommand.findProduct(product, client: client)
        let w = try await XcodeCloudCommand.findWorkflow(workflow, product: product, client: client)
        let original = try await XcodeCloud.edit(workflowID: w.id, client: client)
        var edit = original
        let versionNames = try await options.apply(to: &edit, client: client)
        guard edit != original else {
          print("Nothing to change.")
          return
        }
        guard edit.hasStartCondition else {
          throw ValidationError("A workflow needs a start condition; this would leave '\(w.name ?? w.id)' with none.")
        }
        print("Workflow '\(w.name ?? w.id)':")
        for line in WorkflowOptions.changes(from: original, to: edit, names: versionNames) { print("  \(line)") }
        guard confirm("Save? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        try await XcodeCloud.save(edit, original: original, workflowID: w.id, client: client)
        print(green("Updated") + " workflow '\(edit.name)'.")
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
      subcommands: [List.self, Info.self, Issues.self, Tests.self, Logs.self, Artifacts.self],
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
          headers: ["#", "Workflow", "State", "Source", "Commit", "Started", "Duration"],
          rows: runs.map { r in
            [
              r.number.map(String.init) ?? "-", r.workflowName ?? "-",
              XcodeCloudCommand.state(progress: r.progress, status: r.status), XcodeCloudCommand.source(r),
              r.commit?.sha.map { String($0.prefix(7)) } ?? "-",
              (r.startedDate ?? r.createdDate).map(formatDate) ?? "-",
              XcodeCloudCommand.duration(from: r.startedDate, to: r.finishedDate),
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
        /// Each action's, in the same order, counted from its issues.
        let issueCounts: [XcodeCloud.IssueCounts]
        /// The App Store Connect builds it uploaded, with their processing and TestFlight states.
        let builds: [Builds.Build]
      }

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let product = try await XcodeCloudCommand.findProduct(product, client: client)
        let r = try await XcodeCloudCommand.findRun(run, product: product, client: client)
        async let uploaded = XcodeCloud.builds(runID: r.id, client: client)
        let actions = try await XcodeCloud.actions(runID: r.id, client: client)
        // Apple sends no counts (seen 2026-11-03): each action's are counted from its issues.
        let counts = try await boundedConcurrentMap(actions) { action in
          if let counts = action.issues { return counts }
          return XcodeCloud.IssueCounts(issues: try await XcodeCloud.issues(actionID: action.id, client: client))
        }
        let builds = try await uploaded
        if jsonOption.json { try printJSON(Result(run: r, actions: actions, issueCounts: counts, builds: builds)); return }
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
          ["Issues", XcodeCloudCommand.issueSummary(.total(counts))],
        ]
        if let reason = r.cancelReason { rows.append(["Cancelled", reason]) }
        // What it uploaded: "1.0 (21) iOS · Processing · TestFlight internal: Ready to Test, external: Ready to Submit".
        for build in builds {
          let name = "\(build.version ?? "-") (\(build.number ?? "-"))" + (build.platform.map { " " + formatState($0) } ?? "")
          let testFlight = [build.internalState.map { "internal: \(formatState($0))" }, build.externalState.map { "external: \(formatState($0))" }]
            .compactMap { $0 }.joined(separator: ", ")
          rows.append([
            "Uploaded build",
            [name, build.processingState.map { formatState($0) }, testFlight.isEmpty ? nil : "TestFlight \(testFlight)"]
              .compactMap { $0 }.joined(separator: " · "),
          ])
        }
        if let url = r.commit?.url { rows.append(["Commit link", url]) }
        Table.print(headers: ["", ""], rows: rows)
        print()
        Table.print(
          headers: ["Action", "Type", "State", "Duration", "Issues"],
          rows: zip(actions, counts).map { a, count in
            [
              a.name ?? "-", formatState(a.type ?? "-"), XcodeCloudCommand.state(progress: a.progress, status: a.status),
              XcodeCloudCommand.duration(from: a.startedDate, to: a.finishedDate), XcodeCloudCommand.issueSummary(count),
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
          let place = e.issue.projectPath.map { $0 + (e.issue.line.map { ":\($0)" } ?? "") }
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
          print(red([t.className, t.name].compactMap { $0 }.joined(separator: ".")) + (t.projectPath.map { " \($0)" + (t.line.map { ":\($0)" } ?? "") } ?? ""))
          print("  \(t.message ?? "")")
        }
      }
    }

    struct Logs: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "A build run's logs, from each action's log bundle: list them, or print one.")

      @Argument(help: XcodeCloudCommand.productHelp, completion: XcodeCloudCommand.aliasCompletion)
      var product: String

      @Argument(help: "The run's number or ID.")
      var run: String

      @Option(name: .long, help: "Only this action's logs (its name).")
      var action: String?

      @Option(name: .long, help: "Print this log (its name as listed, e.g. ci_post_clone.log or app-store/xcodebuild-export-archive.log).")
      var show: String?

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let product = try await XcodeCloudCommand.findProduct(product, client: client)
        let r = try await XcodeCloudCommand.findRun(run, product: product, client: client)
        var actions = try await XcodeCloud.actions(runID: r.id, client: client)
        if let action {
          actions = actions.filter { $0.name?.lowercased() == action.lowercased() }
          guard !actions.isEmpty else { throw ValidationError("No action '\(action)' in build \(run).") }
        }
        var rows: [[String]] = []
        for a in actions {
          for log in try await XcodeCloud.logs(actionID: a.id, client: client) {
            if let show {
              guard log.name == show else { continue }
              if actions.count > 1 { print(bold("\(a.name ?? "-") · \(log.name)")) }
              print(log.text)
            } else {
              rows.append([a.name ?? "-", log.name, "\(log.text.split(separator: "\n", omittingEmptySubsequences: false).count)"])
            }
          }
        }
        if show == nil {
          guard !rows.isEmpty else {
            print("No logs yet.")
            return
          }
          Table.print(headers: ["Action", "Log", "Lines"], rows: rows)
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
            // On a terminal, the share received so far after the name, redrawn as it grows.
            let showsProgress = isTerminal
            try await XcodeCloud.download(artifactID: e.artifact.id, to: folder.appending(path: name), client: client) { bytes, expected in
              guard showsProgress, expected > 0 else { return }
              print("\r\u{1B}[KDownloading \(name)… \(bytes * 100 / expected)%", terminator: "")
              fflush(stdout)
            }
            if showsProgress { print("\r\u{1B}[KDownloading \(name)…", terminator: "") }
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
