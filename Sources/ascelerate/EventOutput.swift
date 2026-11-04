import Foundation

/// Where a command that other tools can follow reports progress (`screenshot`, `builds archive`,
/// `builds upload`, `run-workflow`). Normally it's readable text on stdout; with `--json-events`
/// stdout carries one JSON event per line for other tools, and the text moves to stderr.
enum EventOutput {
  @TaskLocal static var emitsEvents = false
  /// Where events go when it isn't stdout: `run-workflow` keeps the original stdout for its events
  /// and points stdout at stderr, so a step's own output (progress dots without a newline, say)
  /// can't run into an event's line.
  nonisolated(unsafe) static var eventDescriptor: Int32?
  /// Set while `run-workflow --json-events` runs its steps: the stream is the workflow's (its steps,
  /// questions and end), so a step's own command events stay out of it. `builds upload` ends with
  /// a `finished` event of its own, which a program following the workflow took for the
  /// workflow's end (seen 2026-11-04: the run showed as stopped while the next upload went on).
  @TaskLocal static var inWorkflow = false

  /// The workflow step running, while `run-workflow --json-events` runs one: what a step's upload
  /// reports its progress as (`progress` events of the workflow's stream).
  struct Step: Sendable {
    let index: Int
    let depth: Int?
  }

  @TaskLocal static var step: Step?

  /// A line of the readable progress.
  static func log(_ text: String = "") {
    if emitsEvents {
      FileHandle.standardError.write(Data((text + "\n").utf8))
    } else {
      print(text)
    }
  }

  // One overload per event type, so call sites can write `.device(…)`.
  static func emit(_ event: ScreenshotEvent) { if !inWorkflow { write(event) } }
  static func emit(_ event: BuildEvent) { if !inWorkflow { write(event) } }
  static func emit(_ event: WorkflowEvent) { write(event) }
  static func emit(_ event: PromptEvent) { write(event) }

  private static func write(_ event: some Encodable) {
    guard emitsEvents else { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(event), let line = String(data: data, encoding: .utf8) else { return }
    if let eventDescriptor {
      FileHandle(fileDescriptor: eventDescriptor, closeOnDealloc: false).write(Data((line + "\n").utf8))
    } else {
      print(line)
    }
  }
}
