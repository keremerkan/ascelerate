import Foundation

/// A workflow run's progress as `run-workflow --json-events` reports it, one JSON object per line.
/// `event` is one of:
/// - `workflow`: the run starts; `name` (the file's name), `steps` (each step's command) and
///   `lines` (each step's line in the file).
/// - `step`: `index` (1-based) of `count`, `command`, `line`, and `state`: `running`, then
///   `succeeded`, `failed` (with `message`, the error) or `dry-run` (its writes weren't sent and the
///   run goes on).
/// - `progress`: a running step's upload (`builds upload --api`): `index`, `sent` of `bytes`, at
///   most once per percent.
/// - `finished`: `succeeded`, `completed` steps of `count`, `message` when it stopped.
/// A nested workflow's events carry its `depth` (1 for a workflow a step runs).
struct WorkflowEvent: Encodable {
  let event: String
  var name: String?
  var steps: [String]?
  var lines: [Int]?
  var index: Int?
  var count: Int?
  var command: String?
  var line: Int?
  var state: String?
  var message: String?
  var succeeded: Bool?
  var completed: Int?
  var depth: Int?
  var sent: Int64?
  var bytes: Int64?
}

/// A question a command asks while events are on, before it reads the answer from stdin (one line).
/// `kind` says what the answer is: `confirm` (`y` or `n`), `choice` (one of `options`, by its
/// number from 1), `choices` (numbers separated by commas, or `all`), `text`. `optional` when an
/// empty answer is accepted (it takes the default).
struct PromptEvent: Encodable {
  var event = "prompt"
  let kind: String
  let message: String
  var options: [String]?
  var optional: Bool?
}
