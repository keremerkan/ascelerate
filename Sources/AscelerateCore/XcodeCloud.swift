import ASCKit
import Foundation

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
    /// Edited in Xcode or App Store Connect right now.
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
    public let issues: IssueCounts
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

    init(_ counts: Components.Schemas.CiIssueCounts?) {
      errors = counts?.errors ?? 0
      warnings = counts?.warnings ?? 0
      analyzerWarnings = counts?.analyzerWarnings ?? 0
      testFailures = counts?.testFailures ?? 0
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
    let response = try await client.ciBuildRunsGetInstance(
      path: .init(id: id), query: .init(include: [.workflow, .sourceBranchOrTag, .pullRequest])
    ).ok.body.json
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
    public let issues: IssueCounts
  }

  public static func actions(runID: String, client: ASCClient) async throws -> [BuildAction] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.ciBuildRunsActionsGetToManyRelated(path: .init(id: runID), query: .init(limit: 200)).ok.body.json
    }.flatMap(\.data).map { action in
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
  }

  public static func issues(actionID: String, client: ASCClient) async throws -> [Issue] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.ciBuildActionsIssuesGetToManyRelated(path: .init(id: actionID), query: .init(limit: 200)).ok.body.json
    }.flatMap(\.data).map { issue in
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

    public struct Destination: Codable, Hashable, Sendable {
      public let deviceName: String?
      public let osVersion: String?
      public let status: String?
      /// Seconds.
      public let duration: Double?
    }
  }

  public static func testResults(actionID: String, client: ASCClient) async throws -> [TestResult] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.ciBuildActionsTestResultsGetToManyRelated(path: .init(id: actionID), query: .init(limit: 200)).ok.body.json
    }.flatMap(\.data).map { result in
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
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.ciBuildActionsArtifactsGetToManyRelated(path: .init(id: actionID), query: .init(limit: 200)).ok.body.json
    }.flatMap(\.data).map { artifact in
      let a = artifact.attributes
      return Artifact(id: artifact.id, fileName: a?.fileName, type: a?.fileType, size: a?.fileSize, downloadURL: a?.downloadUrl)
    }
  }

  /// Downloads an artifact to `destination`, replacing a file already there. Its link is signed
  /// and expires, so it's read fresh first.
  public static func download(artifactID: String, to destination: URL, client: ASCClient) async throws {
    let artifact = try await client.ciArtifactsGetInstance(path: .init(id: artifactID)).ok.body.json.data
    guard let link = artifact.attributes?.downloadUrl, let url = URL(string: link) else { throw DownloadError.noLink }
    let (temporary, response) = try await URLSession.shared.download(from: url)
    if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
      throw DownloadError.status(response.statusCode)
    }
    let manager = FileManager.default
    if manager.fileExists(atPath: destination.path(percentEncoded: false)) { try manager.removeItem(at: destination) }
    try manager.moveItem(at: temporary, to: destination)
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
        XcodeVersion(
          id: version.id, name: version.attributes?.name, version: version.attributes?.version,
          macOSVersions: (version.relationships?.macOsVersions?.data ?? []).compactMap { macOSes[$0.id] })
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
