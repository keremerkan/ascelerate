import ArgumentParser
import Foundation

/// Tracks workflow files currently being executed to detect circular references.
nonisolated(unsafe) private var activeWorkflows: [String] = []

struct RunWorkflowCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "run-workflow",
    abstract: "Run a sequence of asc-client commands from a workflow file."
  )

  @Argument(help: "Path to the workflow file.")
  var file: String

  @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
  var yes = false

  func run() async throws {
    let path = expandPath(file)

    // Resolve to absolute path for reliable cycle detection
    let resolvedPath: String
    if path.hasPrefix("/") {
      resolvedPath = path
    } else {
      resolvedPath = FileManager.default.currentDirectoryPath + "/" + path
    }

    if activeWorkflows.contains(resolvedPath) {
      throw ValidationError("Circular workflow detected: '\((resolvedPath as NSString).lastPathComponent)' is already running.")
    }

    let contents: String
    do {
      contents = try String(contentsOfFile: path, encoding: .utf8)
    } catch {
      throw ValidationError("Cannot read workflow file: \(path)")
    }

    let steps = contents
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && !$0.hasPrefix("#") }

    guard !steps.isEmpty else {
      throw ValidationError("Workflow file has no commands.")
    }

    let filename = (path as NSString).lastPathComponent
    print("Workflow: \(filename) (\(steps.count) \(steps.count == 1 ? "step" : "steps"))")
    for (i, step) in steps.enumerated() {
      print("  \(i + 1). \(step)")
    }
    print()

    if yes { autoConfirm = true }

    if !confirm("Run this workflow? [y/N] ") {
      print("Aborted.")
      throw ExitCode.failure
    }

    print()

    activeWorkflows.append(resolvedPath)
    defer { activeWorkflows.removeAll { $0 == resolvedPath } }

    for (i, step) in steps.enumerated() {
      let label = "[\(i + 1)/\(steps.count)]"
      print("\(label) \(step)")

      let args = splitArguments(step)
      do {
        var command = try ASCClient.parseAsRoot(args)
        if var async = command as? AsyncParsableCommand {
          try await async.run()
        } else {
          try command.run()
        }
      } catch {
        print("\nError: \(error.localizedDescription)")
        print("\nWorkflow stopped at step \(i + 1) of \(steps.count).")
        throw ExitCode.failure
      }

      print()
    }

    print("Workflow complete. All \(steps.count) \(steps.count == 1 ? "step" : "steps") succeeded.")
  }
}

/// Splits a command string into arguments, respecting single and double quotes.
private func splitArguments(_ line: String) -> [String] {
  var args: [String] = []
  var current = ""
  var inSingle = false
  var inDouble = false

  for char in line {
    if char == "'" && !inDouble {
      inSingle.toggle()
    } else if char == "\"" && !inSingle {
      inDouble.toggle()
    } else if char == " " && !inSingle && !inDouble {
      if !current.isEmpty {
        args.append(current)
        current = ""
      }
    } else {
      current.append(char)
    }
  }
  if !current.isEmpty {
    args.append(current)
  }

  return args
}
