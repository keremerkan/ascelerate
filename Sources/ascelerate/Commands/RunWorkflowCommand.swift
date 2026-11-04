import ArgumentParser
import ASCKit
import Foundation

/// Tracks workflow files currently being executed to detect circular references.
nonisolated(unsafe) private var activeWorkflows: [String] = []

/// How deep a workflow runs: 0 for the one on the command line, 1 for one a step of it runs.
private enum WorkflowDepth {
  @TaskLocal static var current = 0
}

struct RunWorkflowCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "run-workflow",
    abstract: "Run a sequence of asc commands from a workflow file."
  )

  @Argument(help: "Path to the workflow file. If omitted, lists workflow files in the current directory.",
            completion: .file(extensions: ["workflow", "txt"]))
  var file: String?

  @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
  var yes = false

  @Flag(name: .long, help: "Check that every step parses (arguments and options), without running any.")
  var check = false

  @OptionGroup var jsonOption: JSONOption

  @Flag(
    name: .customLong("json-events"),
    help: """
      Print one JSON event per line on stdout (the steps, each one's outcome, and every question a \
      step asks, before it reads the answer from stdin), with the readable output on stderr. The \
      workflow isn't confirmed first: the program running it did that.
      """)
  var jsonEvents = false

  func run() async throws {
    let resolvedFile: String
    if let file {
      resolvedFile = file
    } else {
      resolvedFile = try selectWorkflowFile()
    }
    let path = expandPath(resolvedFile)

    // Resolve to a canonical absolute path for reliable cycle detection —
    // `a.workflow`, `./a.workflow`, and a symlink to it must all compare equal.
    let resolvedPath = URL(fileURLWithPath: path).standardizedFileURL
      .resolvingSymlinksInPath().path

    if activeWorkflows.contains(resolvedPath) {
      throw ValidationError("Circular workflow detected: '\((resolvedPath as NSString).lastPathComponent)' is already running.")
    }

    let contents: String
    do {
      contents = try String(contentsOfFile: path, encoding: .utf8)
    } catch {
      throw ValidationError("Cannot read workflow file: \(path)")
    }

    // Each step with its line in the file (from 1), for messages and editors.
    let numbered = contents
      .components(separatedBy: .newlines)
      .enumerated()
      .map { (line: $0.offset + 1, text: $0.element.trimmingCharacters(in: .whitespaces)) }
      .filter { !$0.text.isEmpty && !$0.text.hasPrefix("#") }
    let steps = numbered.map(\.text)

    guard !steps.isEmpty else {
      throw ValidationError("Workflow file has no commands.")
    }

    if check {
      try checkSteps(numbered)
      return
    }

    let filename = (path as NSString).lastPathComponent
    if jsonEvents && WorkflowDepth.current == 0 && !EventOutput.emitsEvents {
      try await runWithEvents(path: path)
      return
    }
    let depth = EventOutput.emitsEvents ? WorkflowDepth.current : nil
    EventOutput.emit(WorkflowEvent(event: "workflow", name: filename, steps: steps, lines: numbered.map(\.line), depth: depth))
    print("Workflow: \(filename) (\(steps.count) \(steps.count == 1 ? "step" : "steps"))")
    for (i, step) in steps.enumerated() {
      print("  \(i + 1). \(step)")
    }
    print()

    if yes { autoConfirm = true }

    // With events, the program running the workflow confirmed it.
    if !EventOutput.emitsEvents, !confirm("Run this workflow? [y/N] ") {
      print("Aborted.")
      throw ExitCode.failure
    }

    print()

    activeWorkflows.append(resolvedPath)
    defer { activeWorkflows.removeAll { $0 == resolvedPath } }

    // A step that passes its own -y (or a nested `run-workflow --yes`) sets the
    // global autoConfirm — restore this workflow's own setting after each step
    // so one -y step can't auto-accept every later prompt. Same for --json.
    let workflowAutoConfirm = autoConfirm
    let workflowJSONMode = jsonMode
    let workflowDryRun = dryRunFlag

    func stepEvent(_ i: Int, _ state: String, message: String? = nil) {
      EventOutput.emit(WorkflowEvent(
        event: "step", index: i + 1, count: steps.count, command: steps[i], line: numbered[i].line, state: state, message: message,
        depth: depth))
    }

    for (i, step) in steps.enumerated() {
      let label = "[\(i + 1)/\(steps.count)]"
      print("\(label) \(step)")
      stepEvent(i, "running")

      let args = try extractDryRunFlag(splitArguments(step))
      let blockedBefore = ASCDryRun.blockedWrites
      do {
        defer {
          autoConfirm = workflowAutoConfirm
          jsonMode = workflowJSONMode
          dryRunFlag = workflowDryRun
        }
        var command: any ParsableCommand
        do {
          command = try Ascelerate.parseAsRoot(args)
        } catch {
          throw StepParseError(message: Ascelerate.message(for: error))
        }
        try await WorkflowDepth.$current.withValue(WorkflowDepth.current + 1) {
          try await EventOutput.$step.withValue(EventOutput.Step(index: i + 1, depth: depth)) {
            if var async = command as? AsyncParsableCommand {
              try await async.run()
            } else {
              try command.run()
            }
          }
        }
        stepEvent(i, "succeeded")
      } catch where ASCDryRun.blockedWrites > blockedBefore {
        // In a dry run a step fails at its first stopped write; keep going so the
        // run shows every step's writes. Later steps can still fail on what wasn't created.
        print(yellow("\nDry run: this step's writes were not sent. Continuing."))
        stepEvent(i, "dry-run")
      } catch {
        let message = (error as? StepParseError)?.message ?? describeError(error)
        print("\nError: \(message)")
        print("\nWorkflow stopped at step \(i + 1) of \(steps.count).")
        stepEvent(i, "failed", message: message)
        EventOutput.emit(WorkflowEvent(
          event: "finished", count: steps.count, message: message, succeeded: false, completed: i, depth: depth))
        throw ExitCode.failure
      }

      print()
    }

    if ClientFactory.isDryRun {
      print("Dry run complete. All \(steps.count) \(steps.count == 1 ? "step" : "steps") ran; no writes were sent.")
    } else {
      print("Workflow complete. All \(steps.count) \(steps.count == 1 ? "step" : "steps") succeeded.")
    }
    EventOutput.emit(WorkflowEvent(event: "finished", count: steps.count, succeeded: true, completed: steps.count, depth: depth))
  }

  /// Runs the workflow with events: they keep the original stdout, and stdout points at stderr
  /// until the run ends, so everything readable (the steps' own output too) goes to stderr.
  private func runWithEvents(path: String) async throws {
    fflush(stdout)
    let events = dup(STDOUT_FILENO)
    guard events >= 0 else { throw ValidationError("Couldn't set up the event output.") }
    dup2(STDERR_FILENO, STDOUT_FILENO)
    EventOutput.eventDescriptor = events
    defer {
      fflush(stdout)
      dup2(events, STDOUT_FILENO)
      close(events)
      EventOutput.eventDescriptor = nil
    }
    var command = self
    command.jsonEvents = false
    try await EventOutput.$emitsEvents.withValue(true) {
      try await EventOutput.$inWorkflow.withValue(true) {
        try await XcodebuildOutput.$followedByProgram.withValue(true) {
          try await command.run()
        }
      }
    }
  }

  /// Parses every step without running it, and says which don't parse (with their line).
  private func checkSteps(_ steps: [(line: Int, text: String)]) throws {
    struct Result: Encodable {
      let line: Int
      let command: String
      let valid: Bool
      var error: String?
    }
    let results = steps.map { step -> Result in
      do {
        _ = try Ascelerate.parseAsRoot(try extractDryRunFlag(splitArguments(step.text)))
        return Result(line: step.line, command: step.text, valid: true)
      } catch {
        return Result(line: step.line, command: step.text, valid: false, error: Ascelerate.message(for: error))
      }
    }
    if jsonOption.json {
      try printJSON(results)
    } else {
      for result in results {
        print(result.valid ? "  \(green("✓")) \(result.line): \(result.command)" : "  \(red("✗")) \(result.line): \(result.command)")
        if let error = result.error { print("      \(error)") }
      }
      let invalid = results.count { !$0.valid }
      print(invalid == 0 ? "All \(results.count) steps parse." : "\(invalid) of \(results.count) steps don't parse.")
    }
    if results.contains(where: { !$0.valid }) { throw ExitCode.failure }
  }
}

/// A step that doesn't parse, with ArgumentParser's own wording.
private struct StepParseError: Error {
  let message: String
}

/// Lists workflow files (.workflow, .txt) in the current directory and prompts the user to select one.
private func selectWorkflowFile() throws -> String {
  let cwd = FileManager.default.currentDirectoryPath
  let extensions = [".workflow", ".txt"]
  let files = (try? FileManager.default.contentsOfDirectory(atPath: cwd))?
    .filter { name in extensions.contains(where: { name.hasSuffix($0) }) }
    .sorted() ?? []

  if files.isEmpty {
    print("No .workflow or .txt files found in the current directory.")
    guard let input = readAnswer("Enter file path: ")?.trimmingCharacters(in: .whitespacesAndNewlines),
          !input.isEmpty else {
      throw ValidationError("No file provided.")
    }
    return input
  }

  print("Workflow files:")
  for (i, file) in files.enumerated() {
    print("  \(i + 1). \(file)")
  }
  print("  \(files.count + 1). Enter path manually")
  print()
  guard let input = readAnswer("Select (1-\(files.count + 1)): ")?.trimmingCharacters(in: .whitespacesAndNewlines),
        let choice = Int(input),
        choice >= 1, choice <= files.count + 1 else {
    throw ValidationError("Invalid selection.")
  }

  if choice == files.count + 1 {
    guard let path = readAnswer("Enter file path: ")?.trimmingCharacters(in: .whitespacesAndNewlines),
          !path.isEmpty else {
      throw ValidationError("No file provided.")
    }
    return path
  }

  return files[choice - 1]
}

