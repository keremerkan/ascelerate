import Foundation
import ASCKit
import Testing
@testable import AscelerateCore

/// The start conditions an update sends: always as a set (Apple ignores one sent as null on its
/// own), each with the edit on top of what the workflow has, so what the edit doesn't hold stays.
@Suite struct XcodeCloudConditionsTests {
  func edit(branch: XcodeCloud.ChangeStart? = nil, manualBranch: XcodeCloud.NamePatterns? = nil, hasSchedule: Bool = false) -> XcodeCloud.WorkflowEdit {
    XcodeCloud.WorkflowEdit(
      name: "W", description: "", isEnabled: true, isLockedForEditing: false, clean: false,
      xcodeVersionID: nil, macOSVersionID: nil, branch: branch, tag: nil, pullRequest: nil,
      hasSchedule: hasSchedule, scheduleText: nil, manualBranch: manualBranch, manualTag: nil, manualPullRequest: nil,
      actions: [])
  }

  @Test func manualOnlyLeavesEveryOtherConditionOut() {
    let conditions = XcodeCloud.conditions(edit(manualBranch: .any), current: nil)
    #expect(conditions.manualBranch?.source?.isAllMatch == true)
    #expect(conditions.missing == [
      "branchStartCondition", "tagStartCondition", "pullRequestStartCondition", "scheduledStartCondition",
      "manualTagStartCondition", "manualPullRequestStartCondition",
    ])
  }

  @Test func anEditedConditionKeepsWhatTheEditDoesntHold() throws {
    let current = try JSONDecoder().decode(Components.Schemas.CiWorkflow.AttributesPayload.self, from: Data(#"""
      {"branchStartCondition": {"autoCancel": false, "source": {"isAllMatch": true},
        "filesAndFoldersRule": {"mode": "START_IF_ANY_FILE_MATCHES", "matchers": [{"directory": "Sources"}]}},
       "scheduledStartCondition": {"source": {"isAllMatch": true}, "schedule": {"frequency": "WEEKLY", "days": ["MONDAY"], "hour": 9, "minute": 0}}}
      """#.utf8))
    let source = XcodeCloud.NamePatterns(isAny: false, patterns: [.init(pattern: "release/", isPrefix: true)])
    let conditions = XcodeCloud.conditions(edit(branch: .init(source: source, autoCancel: true), hasSchedule: true), current: current)
    #expect(conditions.branch?.autoCancel == true)
    #expect(conditions.branch?.source?.isAllMatch == false)
    #expect(conditions.branch?.source?.patterns?.first?.pattern == "release/")
    #expect(conditions.branch?.source?.patterns?.first?.isPrefix == true)
    #expect(conditions.branch?.filesAndFoldersRule?.matchers?.first?.directory == "Sources")
    // The schedule goes as read, its times untouched.
    #expect(conditions.schedule?.schedule?.hour == 9)
    #expect(!conditions.missing.contains("scheduledStartCondition"))
  }
}
