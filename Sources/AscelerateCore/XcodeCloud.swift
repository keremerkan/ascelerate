import ASCKit
import Foundation
import Synchronization

/// Xcode Cloud: an app's or framework's product (`ciProducts`, made in Xcode when the repository
/// is first connected; the API can't create one), its workflows, their build runs with each run's
/// actions, issues, test results and artifacts, and the repositories and Xcode and macOS
/// versions workflows use.
public enum XcodeCloud {
  // MARK: Products

  public struct Product: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    /// `APP` or `FRAMEWORK`.
    public let type: String?
    public let createdDate: Date?
    /// The app's ID and bundle ID (an app's product; a framework has none).
    public let appID: String?
    public let bundleID: String?
    /// `owner/name` of each primary repository.
    public let repositories: [String]
  }

  /// Every product of the team. Each product's repositories are read on their own:
  /// `include=primaryRepositories` on the list answers HTTP 500 (seen 2026-11-03, with or
  /// without its limit), while the product's own `primaryRepositories` endpoint works.
  public static func products(client: ASCClient) async throws -> [Product] {
    let pages = try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.ciProductsGetCollection(query: .init(limit: 200, include: [.app])).ok.body.json
    }
    var bundleIDs: [String: String] = [:]
    for case .apps(let app) in pages.flatMap({ $0.included ?? [] }) { bundleIDs[app.id] = app.attributes?.bundleId }
    let products = pages.flatMap(\.data)
    let repositories = try await boundedConcurrentMap(products) { product in
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.ciProductsPrimaryRepositoriesGetToManyRelated(path: .init(id: product.id), query: .init(limit: 200)).ok.body.json
      }.flatMap(\.data).map(repositoryName)
    }
    return zip(products, repositories).map { product, repositories in
      let appID = product.relationships?.app?.data?.id
      return Product(
        id: product.id, name: product.attributes?.name, type: product.attributes?.productType,
        createdDate: product.attributes?.createdDate, appID: appID, bundleID: appID.flatMap { bundleIDs[$0] },
        repositories: repositories)
    }
  }

  /// Deletes a product with its workflows and build runs (Xcode Cloud stops building it).
  public static func deleteProduct(id: String, client: ASCClient) async throws {
    _ = try await client.ciProductsDeleteInstance(path: .init(id: id)).noContent
  }

  // MARK: Workflows

  public struct Workflow: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let description: String?
    public let isEnabled: Bool
    /// App Store Connect's "Restrict Editing": only Admins and App Managers may change it.
    public let isLockedForEditing: Bool
    /// Builds start from a clean state (no cached derived data).
    public let clean: Bool
    /// The project or workspace built.
    public let containerFilePath: String?
    public let lastModifiedDate: Date?
    public let actions: [Action]
    public let startConditions: [StartCondition]
    public let repositoryID: String?
    public let repository: String?
    public let xcodeVersion: String?
    public let macOSVersion: String?
  }

  /// A workflow's build, test, analyze or archive step.
  public struct Action: Codable, Hashable, Sendable {
    public let name: String?
    /// `BUILD`, `TEST`, `ANALYZE` or `ARCHIVE`.
    public let type: String?
    public let scheme: String?
    /// `MACOS`, `IOS`, `TVOS`, `WATCHOS`, `VISIONOS`.
    public let platform: String?
    public let isRequiredToPass: Bool
    /// An archive's distribution: `INTERNAL_ONLY` or `APP_STORE_ELIGIBLE`.
    public let distribution: String?
    public let testPlan: String?
  }

  /// When a workflow starts on its own (a change to a branch or tag, a pull request, a schedule)
  /// or what it may be started for by hand (`manualBranch`, `manualTag`, `manualPullRequest`).
  public struct StartCondition: Codable, Hashable, Sendable {
    /// `branch`, `tag`, `pullRequest`, `schedule`, `manualBranch`, `manualTag` or `manualPullRequest`.
    public let kind: String
    /// The branches or tags it applies to; empty for any. A pattern ending in `*` is a prefix.
    public let patterns: [String]
    /// A schedule's frequency and time (`WEEKLY MONDAY,FRIDAY 09:00 Europe/Istanbul`).
    public let schedule: String?
  }

  public static func workflows(productID: String, client: ASCClient) async throws -> [Workflow] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.ciProductsWorkflowsGetToManyRelated(
        path: .init(id: productID), query: .init(limit: 200, include: [.repository, .xcodeVersion, .macOsVersion])
      ).ok.body.json
    }.flatMap { page in
      var repositories: [String: String] = [:]
      var xcodes: [String: String] = [:]
      var macOSes: [String: String] = [:]
      for item in page.included ?? [] {
        switch item {
          case .scmRepositories(let repository): repositories[repository.id] = repositoryName(repository)
          case .ciXcodeVersions(let version): xcodes[version.id] = version.attributes?.name ?? version.attributes?.version
          case .ciMacOsVersions(let version): macOSes[version.id] = version.attributes?.name ?? version.attributes?.version
          default: break
        }
      }
      return page.data.map { workflow($0, repositories: repositories, xcodes: xcodes, macOSes: macOSes) }
    }
    .sorted { ($0.name ?? "").localizedStandardCompare($1.name ?? "") == .orderedAscending }
  }

  private static func workflow(
    _ workflow: Components.Schemas.CiWorkflow, repositories: [String: String], xcodes: [String: String], macOSes: [String: String]
  ) -> Workflow {
    let a = workflow.attributes
    let repositoryID = workflow.relationships?.repository?.data?.id
    var conditions: [StartCondition] = []
    if let c = a?.branchStartCondition { conditions.append(.init(kind: "branch", patterns: patterns(c.source), schedule: nil)) }
    if let c = a?.tagStartCondition { conditions.append(.init(kind: "tag", patterns: tagPatterns(c.source), schedule: nil)) }
    if let c = a?.pullRequestStartCondition { conditions.append(.init(kind: "pullRequest", patterns: patterns(c.destination), schedule: nil)) }
    if let c = a?.scheduledStartCondition {
      let s = c.schedule
      let time = s.flatMap { s in s.hour.map { String(format: "%02d:%02d", $0, s.minute ?? 0) } }
      let schedule = [s?.frequency, s?.days?.joined(separator: ","), time, s?.timezone].compactMap { $0 }.joined(separator: " ")
      conditions.append(.init(kind: "schedule", patterns: patterns(c.source), schedule: schedule.isEmpty ? nil : schedule))
    }
    if let c = a?.manualBranchStartCondition { conditions.append(.init(kind: "manualBranch", patterns: patterns(c.source), schedule: nil)) }
    if let c = a?.manualTagStartCondition { conditions.append(.init(kind: "manualTag", patterns: tagPatterns(c.source), schedule: nil)) }
    if let c = a?.manualPullRequestStartCondition {
      conditions.append(.init(kind: "manualPullRequest", patterns: patterns(c.destination), schedule: nil))
    }
    return Workflow(
      id: workflow.id, name: a?.name, description: a?.description, isEnabled: a?.isEnabled ?? false,
      isLockedForEditing: a?.isLockedForEditing ?? false, clean: a?.clean ?? false, containerFilePath: a?.containerFilePath,
      lastModifiedDate: a?.lastModifiedDate,
      actions: (a?.actions ?? []).map { action in
        Action(
          name: action.name, type: action.actionType, scheme: action.scheme, platform: action.platform,
          isRequiredToPass: action.isRequiredToPass ?? false, distribution: action.buildDistributionAudience,
          testPlan: action.testConfiguration?.testPlanName)
      },
      startConditions: conditions, repositoryID: repositoryID, repository: repositoryID.flatMap { repositories[$0] },
      xcodeVersion: workflow.relationships?.xcodeVersion?.data.flatMap { xcodes[$0.id] },
      macOSVersion: workflow.relationships?.macOsVersion?.data.flatMap { macOSes[$0.id] })
  }

  private static func patterns(_ patterns: Components.Schemas.CiBranchPatterns?) -> [String] {
    guard let patterns, patterns.isAllMatch != true else { return [] }
    return (patterns.patterns ?? []).compactMap { p in p.pattern.map { p.isPrefix == true ? $0 + "*" : $0 } }
  }

  private static func tagPatterns(_ patterns: Components.Schemas.CiTagPatterns?) -> [String] {
    guard let patterns, patterns.isAllMatch != true else { return [] }
    return (patterns.patterns ?? []).compactMap { p in p.pattern.map { p.isPrefix == true ? $0 + "*" : $0 } }
  }

  /// Turns a workflow on or off: an off one starts no builds, by its conditions or by hand.
  public static func setEnabled(workflowID: String, _ isEnabled: Bool, client: ASCClient) async throws {
    _ = try await client.ciWorkflowsUpdateInstance(path: .init(id: workflowID), body: .json(.init(data: .init(
      attributes: .init(isEnabled: isEnabled), id: workflowID, _type: "ciWorkflows")))).ok
  }

  /// The start conditions that start a workflow on their own (as `StartCondition.kind`).
  public static let automaticStartKinds: Set<String> = ["branch", "tag", "pullRequest", "schedule"]

  /// Takes away a workflow's automatic start conditions (branch and tag changes, pull requests,
  /// the schedule); the manual ones stay, so it's started only by hand. Xcode Cloud wants a
  /// workflow to keep at least one start condition.
  ///
  /// Apple ignores a start condition sent as null on its own (the update answers 200 and changes
  /// nothing), but replaces the start conditions as a set when the update also carries one of
  /// them (seen 2026-11-03). So the workflow's manual conditions are read and sent back as they
  /// are, with the automatic ones as null.
  public static func removeAutomaticStarts(workflowID: String, client: ASCClient) async throws {
    let current = try await client.ciWorkflowsGetInstance(path: .init(id: workflowID)).ok.body.json.data.attributes
    let automatic = ["branchStartCondition", "tagStartCondition", "pullRequestStartCondition", "scheduledStartCondition"]
    try await ASCNulls.sending(automatic.map { ["data", "attributes", $0] }) {
      _ = try await client.ciWorkflowsUpdateInstance(path: .init(id: workflowID), body: .json(.init(data: .init(
        attributes: .init(
          manualBranchStartCondition: current?.manualBranchStartCondition,
          manualPullRequestStartCondition: current?.manualPullRequestStartCondition,
          manualTagStartCondition: current?.manualTagStartCondition),
        id: workflowID, _type: "ciWorkflows")))).ok
    }
  }

  // MARK: Editing a workflow

  /// A branch or tag name pattern: the name itself, or (`isPrefix`) what names start with.
  public struct NamePattern: Hashable, Sendable {
    public var pattern: String
    public var isPrefix: Bool

    public init(pattern: String, isPrefix: Bool) {
      self.pattern = pattern
      self.isPrefix = isPrefix
    }
  }

  /// Which branches or tags: any, or those the patterns match.
  public struct NamePatterns: Hashable, Sendable {
    public var isAny: Bool
    public var patterns: [NamePattern]

    public init(isAny: Bool = true, patterns: [NamePattern] = []) {
      self.isAny = isAny
      self.patterns = patterns
    }

    public static let any = NamePatterns()
  }

  /// A start condition on changes (to branches or tags): which ones, and whether a newer change
  /// cancels a build still running for the same one.
  public struct ChangeStart: Hashable, Sendable {
    public var source: NamePatterns
    public var autoCancel: Bool

    public init(source: NamePatterns = .any, autoCancel: Bool = true) {
      self.source = source
      self.autoCancel = autoCancel
    }
  }

  /// Pull requests from some branches into some branches.
  public struct PullRequestStart: Hashable, Sendable {
    public var source: NamePatterns
    public var destination: NamePatterns
    public var autoCancel: Bool

    public init(source: NamePatterns = .any, destination: NamePatterns = .any, autoCancel: Bool = true) {
      self.source = source
      self.destination = destination
      self.autoCancel = autoCancel
    }
  }

  /// A workflow's settings that can be edited. What it doesn't hold (actions, a schedule's times,
  /// files-and-folders rules, test destinations) goes back as the workflow has it.
  public struct WorkflowEdit: Hashable, Sendable {
    public var name: String
    public var description: String
    public var isEnabled: Bool
    public var isLockedForEditing: Bool
    public var clean: Bool
    public var xcodeVersionID: String?
    public var macOSVersionID: String?
    public var branch: ChangeStart?
    public var tag: ChangeStart?
    public var pullRequest: PullRequestStart?
    /// Whether it has a schedule (its times are kept as they are; only removing it is offered).
    public var hasSchedule: Bool
    /// The schedule as read, for showing it ("WEEKLY MONDAY 09:00 Europe/Istanbul on main").
    public let scheduleText: String?
    public var manualBranch: NamePatterns?
    public var manualTag: NamePatterns?
    public var manualPullRequest: PullRequestStart?

    /// Whether at least one start condition is left: Xcode Cloud wants one.
    public var hasStartCondition: Bool {
      branch != nil || tag != nil || pullRequest != nil || hasSchedule || manualBranch != nil || manualTag != nil
        || manualPullRequest != nil
    }
  }

  /// A workflow's editable settings as App Store Connect has them now.
  public static func edit(workflowID: String, client: ASCClient) async throws -> WorkflowEdit {
    let workflow = try await withTransientRetry {
      try await client.ciWorkflowsGetInstance(path: .init(id: workflowID), query: .init(include: [.xcodeVersion, .macOsVersion])).ok.body.json.data
    }
    let a = workflow.attributes
    return WorkflowEdit(
      name: a?.name ?? "", description: a?.description ?? "", isEnabled: a?.isEnabled ?? false,
      isLockedForEditing: a?.isLockedForEditing ?? false, clean: a?.clean ?? false,
      xcodeVersionID: workflow.relationships?.xcodeVersion?.data?.id, macOSVersionID: workflow.relationships?.macOsVersion?.data?.id,
      branch: a?.branchStartCondition.map { ChangeStart(source: patterns($0.source), autoCancel: $0.autoCancel ?? false) },
      tag: a?.tagStartCondition.map { ChangeStart(source: patterns($0.source), autoCancel: $0.autoCancel ?? false) },
      pullRequest: a?.pullRequestStartCondition.map {
        PullRequestStart(source: patterns($0.source), destination: patterns($0.destination), autoCancel: $0.autoCancel ?? false)
      },
      hasSchedule: a?.scheduledStartCondition != nil,
      scheduleText: a?.scheduledStartCondition.flatMap { c in
        self.workflow(workflow, repositories: [:], xcodes: [:], macOSes: [:]).startConditions.first { $0.kind == "schedule" }?.schedule
      },
      manualBranch: a?.manualBranchStartCondition.map { patterns($0.source) },
      manualTag: a?.manualTagStartCondition.map { patterns($0.source) },
      manualPullRequest: a?.manualPullRequestStartCondition.map {
        PullRequestStart(source: patterns($0.source), destination: patterns($0.destination), autoCancel: false)
      })
  }

  private static func patterns(_ patterns: Components.Schemas.CiBranchPatterns?) -> NamePatterns {
    guard let patterns, patterns.isAllMatch != true else { return .any }
    return NamePatterns(isAny: false, patterns: (patterns.patterns ?? []).map { NamePattern(pattern: $0.pattern ?? "", isPrefix: $0.isPrefix ?? false) })
  }

  private static func patterns(_ patterns: Components.Schemas.CiTagPatterns?) -> NamePatterns {
    guard let patterns, patterns.isAllMatch != true else { return .any }
    return NamePatterns(isAny: false, patterns: (patterns.patterns ?? []).map { NamePattern(pattern: $0.pattern ?? "", isPrefix: $0.isPrefix ?? false) })
  }

  private static func branchPatterns(_ patterns: NamePatterns) -> Components.Schemas.CiBranchPatterns {
    patterns.isAny
      ? .init(isAllMatch: true, patterns: [])
      : .init(isAllMatch: false, patterns: patterns.patterns.map { .init(isPrefix: $0.isPrefix, pattern: $0.pattern) })
  }

  private static func tagPatterns(_ patterns: NamePatterns) -> Components.Schemas.CiTagPatterns {
    patterns.isAny
      ? .init(isAllMatch: true, patterns: [])
      : .init(isAllMatch: false, patterns: patterns.patterns.map { .init(isPrefix: $0.isPrefix, pattern: $0.pattern) })
  }

  /// Saves what changed from `original`. Start conditions go as a set whenever one of them
  /// changed: Apple ignores a condition sent as null on its own but replaces the set when the
  /// update carries one (seen 2026-11-03). Each condition is the workflow's as read fresh with the
  /// edit on top, so what the edit doesn't hold (a files-and-folders rule, a schedule's times)
  /// stays.
  public static func save(_ edit: WorkflowEdit, original: WorkflowEdit, workflowID: String, client: ASCClient) async throws {
    let current = try await withTransientRetry {
      try await client.ciWorkflowsGetInstance(path: .init(id: workflowID)).ok.body.json.data.attributes
    }
    typealias Attributes = Components.Schemas.CiWorkflowUpdateRequest.DataPayload.AttributesPayload
    var attributes = Attributes()
    if edit.name != original.name { attributes.name = edit.name }
    if edit.description != original.description { attributes.description = edit.description }
    if edit.isEnabled != original.isEnabled { attributes.isEnabled = edit.isEnabled }
    if edit.isLockedForEditing != original.isLockedForEditing { attributes.isLockedForEditing = edit.isLockedForEditing }
    if edit.clean != original.clean { attributes.clean = edit.clean }
    var nulls: [[String]] = []
    let conditionsChanged = edit.branch != original.branch || edit.tag != original.tag || edit.pullRequest != original.pullRequest
      || edit.hasSchedule != original.hasSchedule || edit.manualBranch != original.manualBranch
      || edit.manualTag != original.manualTag || edit.manualPullRequest != original.manualPullRequest
    if conditionsChanged {
      if let branch = edit.branch {
        var condition = current?.branchStartCondition ?? .init()
        condition.source = branchPatterns(branch.source)
        condition.autoCancel = branch.autoCancel
        attributes.branchStartCondition = condition
      } else {
        nulls.append(["data", "attributes", "branchStartCondition"])
      }
      if let tag = edit.tag {
        var condition = current?.tagStartCondition ?? .init()
        condition.source = tagPatterns(tag.source)
        condition.autoCancel = tag.autoCancel
        attributes.tagStartCondition = condition
      } else {
        nulls.append(["data", "attributes", "tagStartCondition"])
      }
      if let pullRequest = edit.pullRequest {
        var condition = current?.pullRequestStartCondition ?? .init()
        condition.source = branchPatterns(pullRequest.source)
        condition.destination = branchPatterns(pullRequest.destination)
        condition.autoCancel = pullRequest.autoCancel
        attributes.pullRequestStartCondition = condition
      } else {
        nulls.append(["data", "attributes", "pullRequestStartCondition"])
      }
      if edit.hasSchedule, let schedule = current?.scheduledStartCondition {
        attributes.scheduledStartCondition = schedule
      } else {
        nulls.append(["data", "attributes", "scheduledStartCondition"])
      }
      if let manual = edit.manualBranch {
        attributes.manualBranchStartCondition = .init(source: branchPatterns(manual))
      } else {
        nulls.append(["data", "attributes", "manualBranchStartCondition"])
      }
      if let manual = edit.manualTag {
        attributes.manualTagStartCondition = .init(source: tagPatterns(manual))
      } else {
        nulls.append(["data", "attributes", "manualTagStartCondition"])
      }
      if let manual = edit.manualPullRequest {
        attributes.manualPullRequestStartCondition = .init(
          destination: branchPatterns(manual.destination), source: branchPatterns(manual.source))
      } else {
        nulls.append(["data", "attributes", "manualPullRequestStartCondition"])
      }
    }
    typealias Relationships = Components.Schemas.CiWorkflowUpdateRequest.DataPayload.RelationshipsPayload
    var relationships: Relationships?
    if edit.xcodeVersionID != original.xcodeVersionID || edit.macOSVersionID != original.macOSVersionID {
      relationships = Relationships(
        macOsVersion: edit.macOSVersionID.map { .init(data: .init(id: $0, _type: "ciMacOsVersions")) },
        xcodeVersion: edit.xcodeVersionID.map { .init(data: .init(id: $0, _type: "ciXcodeVersions")) })
    }
    try await ASCNulls.sending(nulls) {
      _ = try await client.ciWorkflowsUpdateInstance(path: .init(id: workflowID), body: .json(.init(data: .init(
        attributes: attributes, id: workflowID, relationships: relationships, _type: "ciWorkflows")))).ok
    }
  }

  /// Deletes a workflow; its build runs stay.
  public static func deleteWorkflow(id: String, client: ASCClient) async throws {
    _ = try await client.ciWorkflowsDeleteInstance(path: .init(id: id)).noContent
  }

  // MARK: Build runs

  public struct Run: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let number: Int?
    public let workflowID: String?
    public let workflowName: String?
    /// `PENDING`, `RUNNING` or `COMPLETE`.
    public let progress: String?
    /// Once complete: `SUCCEEDED`, `FAILED`, `ERRORED`, `CANCELED` or `SKIPPED`.
    public let status: String?
    /// What started it, as Apple says it (`GIT_REF_CHANGE`, `MANUAL`, `PULL_REQUEST_OPEN`, …).
    public let startReason: String?
    public let cancelReason: String?
    public let createdDate: Date?
    public let startedDate: Date?
    public let finishedDate: Date?
    /// The branch or tag built.
    public let reference: String?
    /// `BRANCH` or `TAG`.
    public let referenceKind: String?
    public let pullRequestNumber: Int?
    public let pullRequestTitle: String?
    public let commit: Commit?
    /// The run's issue counts, when Apple sends them: it sent none for a run with 2 warnings, nor
    /// for its actions (seen 2026-11-03), so they're counted from the actions' issues instead
    /// (`IssueCounts(issues:)`).
    public let issues: IssueCounts?
    /// The App Store Connect builds an archive action made.
    public let buildIDs: [String]
  }

  public struct Commit: Codable, Hashable, Sendable {
    public let sha: String?
    public let message: String?
    public let author: String?
    public let url: String?
  }

  public struct IssueCounts: Codable, Hashable, Sendable {
    public let errors: Int
    public let warnings: Int
    public let analyzerWarnings: Int
    public let testFailures: Int

    public init(errors: Int = 0, warnings: Int = 0, analyzerWarnings: Int = 0, testFailures: Int = 0) {
      (self.errors, self.warnings, self.analyzerWarnings, self.testFailures) = (errors, warnings, analyzerWarnings, testFailures)
    }

    /// The counts added up (a run's from its actions').
    public static func total(_ counts: [IssueCounts]) -> IssueCounts {
      IssueCounts(
        errors: counts.reduce(0) { $0 + $1.errors }, warnings: counts.reduce(0) { $0 + $1.warnings },
        analyzerWarnings: counts.reduce(0) { $0 + $1.analyzerWarnings }, testFailures: counts.reduce(0) { $0 + $1.testFailures })
    }

    /// Counted from a list of issues.
    public init(issues: [Issue]) {
      self.init(
        errors: issues.count { $0.type == "ERROR" }, warnings: issues.count { $0.type == "WARNING" },
        analyzerWarnings: issues.count { $0.type == "ANALYZER_WARNING" }, testFailures: issues.count { $0.type == "TEST_FAILURE" })
    }

    /// Apple's counts, nil when it sends none.
    init?(_ counts: Components.Schemas.CiIssueCounts?) {
      guard let counts else { return nil }
      errors = counts.errors ?? 0
      warnings = counts.warnings ?? 0
      analyzerWarnings = counts.analyzerWarnings ?? 0
      testFailures = counts.testFailures ?? 0
    }
  }

  /// A product's build runs (or one workflow's), newest first, up to `limit`.
  public static func runs(productID: String, workflowID: String? = nil, limit: Int = 25, client: ASCClient) async throws -> [Run] {
    var runs: [Run] = []
    var link: String?
    repeat {
      let page = try await runsPage(productID: productID, workflowID: workflowID, link: link, pageSize: min(limit, 200), client: client)
      runs += page.runs
      link = page.next
    } while link != nil && runs.count < limit
    return Array(runs.prefix(limit))
  }

  /// One page of build runs, newest first: the first (`link` nil) or the one a page's `next`
  /// points to, for a list that loads more as it scrolls.
  public static func runsPage(
    productID: String, workflowID: String? = nil, link: String? = nil, pageSize: Int = 25, client: ASCClient
  ) async throws -> (runs: [Run], next: String?) {
    if let workflowID {
      let page = try await ASCPaging.page(link) {
        try await client.ciWorkflowsBuildRunsGetToManyRelated(
          path: .init(id: workflowID),
          query: .init(sort: [.minusNumber], limit: pageSize, include: [.workflow, .sourceBranchOrTag, .pullRequest])
        ).ok.body.json
      }
      return (runs(page.data, included: page.included), page.links.next)
    }
    let page = try await ASCPaging.page(link) {
      try await client.ciProductsBuildRunsGetToManyRelated(
        path: .init(id: productID),
        query: .init(sort: [.minusNumber], limit: pageSize, include: [.workflow, .sourceBranchOrTag, .pullRequest])
      ).ok.body.json
    }
    return (runs(page.data, included: page.included), page.links.next)
  }

  public static func run(id: String, client: ASCClient) async throws -> Run {
    let response = try await withTransientRetry {
      try await client.ciBuildRunsGetInstance(
        path: .init(id: id), query: .init(include: [.workflow, .sourceBranchOrTag, .pullRequest])
      ).ok.body.json
    }
    return runs([response.data], included: response.included).first!
  }

  private static func runs<Included: XcodeCloudRunIncluded>(_ runs: [Components.Schemas.CiBuildRun], included: [Included]?) -> [Run] {
    var workflows: [String: String] = [:]
    var references: [String: (name: String?, kind: String?)] = [:]
    var pullRequests: [String: (number: Int?, title: String?)] = [:]
    for item in included ?? [] {
      if let workflow = item.workflow { workflows[workflow.id] = workflow.attributes?.name }
      if let reference = item.gitReference { references[reference.id] = (reference.attributes?.name, reference.attributes?.kind) }
      if let request = item.pullRequest { pullRequests[request.id] = (request.attributes?.number, request.attributes?.title) }
    }
    return runs.map { run in
      let a = run.attributes
      let workflowID = run.relationships?.workflow?.data?.id
      let reference = run.relationships?.sourceBranchOrTag?.data.flatMap { references[$0.id] }
      let pullRequest = run.relationships?.pullRequest?.data.flatMap { pullRequests[$0.id] }
      let commit = a?.sourceCommit.map { c in
        Commit(sha: c.commitSha, message: c.message, author: c.author?.displayName ?? c.committer?.displayName, url: c.webUrl)
      }
      return Run(
        id: run.id, number: a?.number, workflowID: workflowID, workflowName: workflowID.flatMap { workflows[$0] },
        progress: a?.executionProgress, status: a?.completionStatus, startReason: a?.startReason, cancelReason: a?.cancelReason,
        createdDate: a?.createdDate, startedDate: a?.startedDate, finishedDate: a?.finishedDate,
        reference: reference?.name, referenceKind: reference?.kind,
        pullRequestNumber: pullRequest?.number, pullRequestTitle: pullRequest?.title, commit: commit,
        issues: IssueCounts(a?.issueCounts), buildIDs: (run.relationships?.builds?.data ?? []).map(\.id))
    }
  }

  /// Starts a workflow: on a branch or tag (`gitReferenceID`), a pull request (`pullRequestID`),
  /// or as a rebuild of an earlier run (`rerunOf`, same commit). Without one, Apple picks what the
  /// workflow's manual start condition allows. `clean` builds without the cache.
  @discardableResult
  public static func start(
    workflowID: String, gitReferenceID: String? = nil, pullRequestID: String? = nil, rerunOf runID: String? = nil,
    clean: Bool? = nil, client: ASCClient
  ) async throws -> Run {
    let created = try await client.ciBuildRunsCreateInstance(body: .json(.init(data: .init(
      attributes: clean.map { .init(clean: $0) },
      relationships: .init(
        buildRun: runID.map { .init(data: .init(id: $0, _type: "ciBuildRuns")) },
        pullRequest: pullRequestID.map { .init(data: .init(id: $0, _type: "scmPullRequests")) },
        sourceBranchOrTag: gitReferenceID.map { .init(data: .init(id: $0, _type: "scmGitReferences")) },
        workflow: .init(data: .init(id: workflowID, _type: "ciWorkflows"))),
      _type: "ciBuildRuns")))).created.body.json.data
    return try await run(id: created.id, client: client)
  }

  // MARK: A run's actions

  public struct BuildAction: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    /// `BUILD`, `TEST`, `ANALYZE` or `ARCHIVE`.
    public let type: String?
    public let progress: String?
    public let status: String?
    public let isRequiredToPass: Bool
    public let startedDate: Date?
    public let finishedDate: Date?
    /// Apple's counts, when it sends them (it sent none, seen 2026-11-03): see `Run.issues`.
    public let issues: IssueCounts?
  }

  public static func actions(runID: String, client: ASCClient) async throws -> [BuildAction] {
    try await withTransientRetry { try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.ciBuildRunsActionsGetToManyRelated(path: .init(id: runID), query: .init(limit: 200)).ok.body.json
    } }.flatMap(\.data).map { action in
      let a = action.attributes
      return BuildAction(
        id: action.id, name: a?.name, type: a?.actionType, progress: a?.executionProgress, status: a?.completionStatus,
        isRequiredToPass: a?.isRequiredToPass ?? false, startedDate: a?.startedDate, finishedDate: a?.finishedDate,
        issues: IssueCounts(a?.issueCounts))
    }
  }

  public struct Issue: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// `ANALYZER_WARNING`, `ERROR`, `TEST_FAILURE` or `WARNING`.
    public let type: String?
    public let category: String?
    public let message: String?
    public let path: String?
    public let line: Int?

    /// `path` within the repository, without Xcode Cloud's `file:///Volumes/workspace/repository/`.
    public var projectPath: String? { XcodeCloud.projectPath(path) }
  }

  public static func issues(actionID: String, client: ASCClient) async throws -> [Issue] {
    try await withTransientRetry { try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.ciBuildActionsIssuesGetToManyRelated(path: .init(id: actionID), query: .init(limit: 200)).ok.body.json
    } }.flatMap(\.data).map { issue in
      let a = issue.attributes
      return Issue(
        id: issue.id, type: a?.issueType, category: a?.category, message: a?.message,
        path: a?.fileSource?.path, line: a?.fileSource?.lineNumber)
    }
  }

  public struct TestResult: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let className: String?
    public let name: String?
    /// `SUCCESS`, `FAILURE`, `MIXED` (differs per destination), `SKIPPED` or `EXPECTED_FAILURE`.
    public let status: String?
    public let message: String?
    public let path: String?
    public let line: Int?
    public let destinations: [Destination]

    public var projectPath: String? { XcodeCloud.projectPath(path) }

    public struct Destination: Codable, Hashable, Sendable {
      public let deviceName: String?
      public let osVersion: String?
      public let status: String?
      /// Seconds.
      public let duration: Double?
    }
  }

  public static func testResults(actionID: String, client: ASCClient) async throws -> [TestResult] {
    try await withTransientRetry { try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.ciBuildActionsTestResultsGetToManyRelated(path: .init(id: actionID), query: .init(limit: 200)).ok.body.json
    } }.flatMap(\.data).map { result in
      let a = result.attributes
      return TestResult(
        id: result.id, className: a?.className, name: a?.name, status: a?.status, message: a?.message,
        path: a?.fileSource?.path, line: a?.fileSource?.lineNumber,
        destinations: (a?.destinationTestResults ?? []).map {
          .init(deviceName: $0.deviceName, osVersion: $0.osVersion, status: $0.status, duration: $0.duration)
        })
    }
  }

  public struct Artifact: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let fileName: String?
    /// `ARCHIVE`, `ARCHIVE_EXPORT`, `LOG_BUNDLE`, `RESULT_BUNDLE`, `TEST_PRODUCTS`, `XCODEBUILD_PRODUCTS`, …
    public let type: String?
    public let size: Int?
    /// A signed download link, good for a while after it's read.
    public let downloadURL: String?
  }

  public static func artifacts(actionID: String, client: ASCClient) async throws -> [Artifact] {
    try await withTransientRetry { try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.ciBuildActionsArtifactsGetToManyRelated(path: .init(id: actionID), query: .init(limit: 200)).ok.body.json
    } }.flatMap(\.data).map { artifact in
      let a = artifact.attributes
      return Artifact(id: artifact.id, fileName: a?.fileName, type: a?.fileType, size: a?.fileSize, downloadURL: a?.downloadUrl)
    }
  }

  /// Downloads an artifact to `destination`, replacing a file already there. Its link is signed
  /// and expires, so it's read fresh first. With `received`, it reports the bytes in so far and
  /// the file's size (-1 when unknown) as they arrive, a few times a second; cancelling the task
  /// stops the download. A download that fails mid-way throws a `URLError` whose
  /// `downloadTaskResumeData` can be passed back as `resumeData` to go on from there.
  public static func download(
    artifactID: String, to destination: URL, resumeData: Data? = nil, client: ASCClient,
    received: (@Sendable (_ bytes: Int64, _ expected: Int64) -> Void)? = nil
  ) async throws {
    let artifact = try await withTransientRetry { try await client.ciArtifactsGetInstance(path: .init(id: artifactID)).ok.body.json.data }
    guard let link = artifact.attributes?.downloadUrl, let url = URL(string: link) else { throw DownloadError.noLink }
    // A session of its own with the delegate: the async download(from:delegate:) passes no
    // progress to its task delegate (the bar stayed at zero, seen 2026-11-03). Two minutes
    // without data end a try (the default's one); a 330 MB download stopped with a timeout, so
    // one that stops mid-way goes on from where it stopped, up to three times.
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 120
    var resumeData = resumeData
    for attempt in 1...4 {
      let delegate = DownloadDelegate(destination: destination, received: received)
      let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
      defer { session.finishTasksAndInvalidate() }
      let task = resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: url)
      do {
        try await withTaskCancellationHandler {
          try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            delegate.finished.withLock { $0 = continuation }
            task.resume()
          }
        } onCancel: {
          task.cancel()
        }
        return
      } catch let error as URLError where !Task.isCancelled && attempt < 4 && error.downloadTaskResumeData != nil {
        resumeData = error.downloadTaskResumeData
      }
    }
  }

  public enum DownloadError: LocalizedError {
    case noLink
    case status(Int)

    public var errorDescription: String? {
      switch self {
        case .noLink: "App Store Connect gave no download link for the artifact."
        case .status(let code): "The artifact's download failed (HTTP \(code))."
      }
    }
  }

  /// A file's path within the repository: issues and tests name files as
  /// `file:///Volumes/workspace/repository/<path>`, where Xcode Cloud checks the repository out.
  public static func projectPath(_ path: String?) -> String? {
    guard var path else { return nil }
    if path.hasPrefix("file://") { path.removeFirst("file://".count) }
    let checkout = "/Volumes/workspace/repository/"
    if path.hasPrefix(checkout) { path.removeFirst(checkout.count) }
    return path
  }

  /// An action's log, from its log bundle.
  public struct LogFile: Hashable, Identifiable, Sendable {
    /// The file's name (`ci_post_clone.log`, `xcodebuild-build.log`).
    public let name: String
    public let text: String
    public var id: String { name }
  }

  /// An action's logs, read from its log bundle artifact (none until the action has one): the
  /// scripts' and package resolution's first, the build's last, as Xcode Cloud ran them. Each
  /// line starts with Xcode Cloud's timestamp and a tab.
  public static func logs(actionID: String, client: ASCClient) async throws -> [LogFile] {
    guard let bundle = try await artifacts(actionID: actionID, client: client).first(where: { $0.type == "LOG_BUNDLE" }) else { return [] }
    let artifact = try await withTransientRetry { try await client.ciArtifactsGetInstance(path: .init(id: bundle.id)).ok.body.json.data }
    guard let link = artifact.attributes?.downloadUrl, let url = URL(string: link) else { throw DownloadError.noLink }
    let (data, response) = try await withTransientRetry { try await URLSession.shared.data(from: url) }
    if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
      throw DownloadError.status(response.statusCode)
    }
    let order = ["ci_post_clone", "resolve_package_dependencies", "ci_pre_xcodebuild", "ci_post_xcodebuild"]
    return try ZipReader.files(in: data)
      .filter { $0.path.hasSuffix(".log") || $0.path.hasSuffix(".txt") }
      .map { LogFile(name: ($0.path as NSString).lastPathComponent, text: String(decoding: $0.data, as: UTF8.self)) }
      .sorted { a, b in
        let rank = { (name: String) in order.firstIndex { name.hasPrefix($0) } ?? (name.hasPrefix("xcodebuild") ? order.count + 1 : order.count) }
        return (rank(a.name), a.name) < (rank(b.name), b.name)
      }
  }

  // MARK: Repositories and versions

  public struct Repository: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let owner: String?
    public let name: String?
    public let httpCloneURL: String?
    public let sshCloneURL: String?
    public let lastAccessedDate: Date?
  }

  /// The repositories Xcode Cloud can reach.
  public static func repositories(client: ASCClient) async throws -> [Repository] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.scmRepositoriesGetCollection(query: .init(limit: 200)).ok.body.json
    }.flatMap(\.data).map { repository in
      let a = repository.attributes
      return Repository(
        id: repository.id, owner: a?.ownerName, name: a?.repositoryName, httpCloneURL: a?.httpCloneUrl,
        sshCloneURL: a?.sshCloneUrl, lastAccessedDate: a?.lastAccessedDate)
    }
  }

  private static func repositoryName(_ repository: Components.Schemas.ScmRepository) -> String {
    [repository.attributes?.ownerName, repository.attributes?.repositoryName].compactMap { $0 }.joined(separator: "/")
  }

  public struct GitReference: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    /// `BRANCH` or `TAG`.
    public let kind: String?
  }

  /// A repository's branches and tags (deleted ones left out).
  public static func gitReferences(repositoryID: String, client: ASCClient) async throws -> [GitReference] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.scmRepositoriesGitReferencesGetToManyRelated(path: .init(id: repositoryID), query: .init(limit: 200)).ok.body.json
    }.flatMap(\.data).filter { $0.attributes?.isDeleted != true }.map {
      GitReference(id: $0.id, name: $0.attributes?.name, kind: $0.attributes?.kind)
    }
  }

  public struct PullRequest: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let number: Int?
    public let title: String?
    public let sourceBranch: String?
    public let destinationBranch: String?
    public let isClosed: Bool
    public let url: String?
  }

  public static func pullRequests(repositoryID: String, client: ASCClient) async throws -> [PullRequest] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.scmRepositoriesPullRequestsGetToManyRelated(path: .init(id: repositoryID), query: .init(limit: 200)).ok.body.json
    }.flatMap(\.data).map { request in
      let a = request.attributes
      return PullRequest(
        id: request.id, number: a?.number, title: a?.title, sourceBranch: a?.sourceBranchName,
        destinationBranch: a?.destinationBranchName, isClosed: a?.isClosed ?? false, url: a?.webUrl)
    }
  }

  public struct XcodeVersion: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let version: String?
    /// The macOS versions it runs on.
    public let macOSVersions: [String]
    /// The same with their IDs, for choosing one.
    public let macOSOptions: [VersionOption]
  }

  /// An Xcode or macOS version to choose: its ID and name ("Latest Release", "Xcode 27.2").
  public struct VersionOption: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
  }

  /// The Xcode versions Xcode Cloud offers, with the macOS versions each runs on.
  public static func xcodeVersions(client: ASCClient) async throws -> [XcodeVersion] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.ciXcodeVersionsGetCollection(query: .init(limit: 200, include: [.macOsVersions], limitMacOsVersions: 50)).ok.body.json
    }.flatMap { page in
      var macOSes: [String: String] = [:]
      for version in page.included ?? [] {
        macOSes[version.id] = version.attributes?.name ?? version.attributes?.version
      }
      return page.data.map { version in
        let options = (version.relationships?.macOsVersions?.data ?? []).compactMap { link in
          macOSes[link.id].map { VersionOption(id: link.id, name: $0) }
        }
        return XcodeVersion(
          id: version.id, name: version.attributes?.name, version: version.attributes?.version,
          macOSVersions: options.map(\.name), macOSOptions: options)
      }
    }
  }
}

/// The included resources of a build run response and a build runs response, read alike.
protocol XcodeCloudRunIncluded {
  var workflow: Components.Schemas.CiWorkflow? { get }
  var gitReference: Components.Schemas.ScmGitReference? { get }
  var pullRequest: Components.Schemas.ScmPullRequest? { get }
}

extension Components.Schemas.CiBuildRunsResponse.IncludedPayloadPayload: XcodeCloudRunIncluded {
  var workflow: Components.Schemas.CiWorkflow? { if case .ciWorkflows(let value) = self { value } else { nil } }
  var gitReference: Components.Schemas.ScmGitReference? { if case .scmGitReferences(let value) = self { value } else { nil } }
  var pullRequest: Components.Schemas.ScmPullRequest? { if case .scmPullRequests(let value) = self { value } else { nil } }
}

extension Components.Schemas.CiBuildRunResponse.IncludedPayloadPayload: XcodeCloudRunIncluded {
  var workflow: Components.Schemas.CiWorkflow? { if case .ciWorkflows(let value) = self { value } else { nil } }
  var gitReference: Components.Schemas.ScmGitReference? { if case .scmGitReferences(let value) = self { value } else { nil } }
  var pullRequest: Components.Schemas.ScmPullRequest? { if case .scmPullRequests(let value) = self { value } else { nil } }
}

/// A download's session delegate: reports the bytes as they're written (at most every quarter
/// second, and at the end), moves the file to its destination, and ends the wait with how it went.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
  let destination: URL
  let received: (@Sendable (Int64, Int64) -> Void)?
  let finished = Mutex<CheckedContinuation<Void, any Error>?>(nil)
  private let last = Mutex(Date.distantPast)
  /// What went wrong moving the file or with the response, reported when the task completes.
  private let failure = Mutex<(any Error)?>(nil)

  init(destination: URL, received: (@Sendable (Int64, Int64) -> Void)?) {
    self.destination = destination
    self.received = received
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    guard let received else { return }
    let isDue = last.withLock { last in
      guard Date.now.timeIntervalSince(last) >= 0.25 || totalBytesWritten == totalBytesExpectedToWrite else { return false }
      last = .now
      return true
    }
    if isDue { received(totalBytesWritten, totalBytesExpectedToWrite) }
  }

  // The file is deleted when this returns, so it's moved here.
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    do {
      if let response = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
        throw XcodeCloud.DownloadError.status(response.statusCode)
      }
      let manager = FileManager.default
      if manager.fileExists(atPath: destination.path(percentEncoded: false)) { try manager.removeItem(at: destination) }
      try manager.moveItem(at: location, to: destination)
    } catch {
      failure.withLock { $0 = error }
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
    let continuation = finished.withLock { continuation in
      defer { continuation = nil }
      return continuation
    }
    if let error = error ?? failure.withLock({ $0 }) {
      continuation?.resume(throwing: error)
    } else {
      continuation?.resume()
    }
  }
}
