import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation
import Synchronization

/// A human-readable description for inline error reporting (per-item FAIL lines and
/// similar catch sites): Apple's error entries for API errors, and the underlying error
/// rather than the runtime's verbose `ClientError` wrapper otherwise.
func describeError(_ error: Error) -> String {
  if let stop = ASCDryRunStop.from(error) { return stop.description }
  if let ascError = ASCError.from(error) {
    if ascError.statusCode == 429 { return "API rate limit exceeded (HTTP 429)" }
    if !ascError.errors.isEmpty {
      let reasons = ascError.errors.flatMap(\.reasons).map { [$0.title, $0.detail].filter { !$0.isEmpty }.joined(separator: ": ") }
      return ascError.errors.map { "\($0.title): \($0.detail)" }.joined(separator: "; ") + " (HTTP \(ascError.statusCode))"
        + reasons.map { "\n  - \($0)" }.joined()
    }
    return "HTTP \(ascError.statusCode)"
  }
  // ValidationError's localizedDescription is the generic "The operation couldn't be completed".
  if let validation = error as? ValidationError { return validation.message }
  // A command that ended with only its exit code (its reason is in its output above): an
  // ExitCode's own description is the framework's "ArgumentParser.ExitCode error 1".
  if let exit = error as? ExitCode { return "The command ended with exit code \(exit.rawValue). Its output above says why." }
  return (ascUnderlyingError(error) ?? error).localizedDescription
}

// MARK: - ANSI Colors

/// Whether stdout is a terminal: colors and live progress only go there.
let isTerminal = isatty(STDOUT_FILENO) != 0
private let isStderrTerminal = isatty(STDERR_FILENO) != 0

func red(_ text: String) -> String { isTerminal ? "\u{1B}[31m\(text)\u{1B}[0m" : text }
func green(_ text: String) -> String { isTerminal ? "\u{1B}[32m\(text)\u{1B}[0m" : text }
func yellow(_ text: String) -> String { isTerminal ? "\u{1B}[38;5;208m\(text)\u{1B}[0m" : text }
func bold(_ text: String) -> String { isTerminal ? "\u{1B}[1m\(text)\u{1B}[0m" : text }
func stderrRed(_ text: String) -> String { isStderrTerminal ? "\u{1B}[31m\(text)\u{1B}[0m" : text }

/// Prints the standard "Cancelled." message used when a user declines a confirmation prompt.
func cancelled() { print(yellow("Cancelled.")) }

/// Prints a success line: a green `label` (typically a verb like "Created"/"Updated"),
/// optionally followed by a space and plain `detail` text.
func success(_ label: String, _ detail: String = "") {
  print(detail.isEmpty ? green(label) : green(label) + " " + detail)
}

// MARK: - Child Process Signal Forwarding

/// Active child processes that should be interrupted on Ctrl-C.
/// Mutated by ScreenshotShell.run/stream/runToLog from concurrent task groups,
/// so all access must go through `processLock`.
nonisolated(unsafe) private var activeProcesses: [Process] = []

/// The dispatch source for SIGINT handling. Stored globally to keep it alive.
nonisolated(unsafe) private var signalSource: [any DispatchSourceSignal]?

/// Serializes access to `activeProcesses`, `interruptCleanup` and `signalSource`. Required because
/// the screenshot runner spawns simctl/xcodebuild processes concurrently across
/// devices via task groups; without locking, append/removeAll on the array races
/// and corrupts memory (bus error).
private let processLock = NSLock()

/// Folders a Ctrl-C deletes before exiting (an export's temporary folder): the handler exits at
/// once, so the `defer`s that would delete them don't run.
nonisolated(unsafe) private var interruptCleanup: [String] = []

/// Waits for a started child process with Ctrl-C forwarded to it: Foundation starts each child in
/// a process group of its own, which neither the terminal's Ctrl-C nor a signal to this process
/// reaches, so without this it goes on running (and writing to our output) after we exit.
/// `pipe`, the process's standard output, is read to its end first and returned: output past the
/// ~64 KB pipe buffer would otherwise block the child while this waits for it.
@discardableResult
func waitForwardingInterrupts(_ process: Process, reading pipe: Pipe? = nil) -> Data {
  processLock.lock()
  activeProcesses.append(process)
  processLock.unlock()
  setupSignalHandler()
  defer {
    processLock.lock()
    activeProcesses.removeAll { $0 === process }
    processLock.unlock()
  }
  let data = pipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
  process.waitUntilExit()
  return data
}

/// A tool that failed (xcodebuild, altool), with the lines of its output that say why: what a
/// workflow step reports as its error, which an exit code alone didn't ("The operation couldn't be
/// completed (ArgumentParser.ExitCode error 1.)"). The tool's whole output went where it always
/// does; these are only its error lines.
struct ToolFailure: LocalizedError {
  let tool: String
  let status: Int32
  let errors: [String]

  var errorDescription: String? {
    errors.isEmpty ? "\(tool) ended with exit code \(status)." : errors.joined(separator: "\n")
  }
}

/// The kinds of error lines `runReportingErrors` keeps.
enum ToolErrorLines {
  /// xcodebuild: compiler and build errors (`…: error: …`, `error: …`) and its failure banner.
  case xcodebuild
  /// altool: its `*** Error:` lines and the `ERROR` ones of its newer output.
  case altool

  /// Bytes every pattern below contains one of.
  fileprivate static let needles = [Data("rror".utf8), Data("RROR".utf8), Data("FAILED".utf8)]

  fileprivate func matches(_ line: String) -> Bool {
    switch self {
      case .xcodebuild:
        line.contains(": error:") || line.hasPrefix("error:") || (line.hasPrefix("** ") && line.hasSuffix(" FAILED **"))
      case .altool:
        line.contains("*** Error") || line.contains("ERROR:") || line.hasPrefix("ERROR")
          || (line.localizedCaseInsensitiveContains("error:") && !line.localizedCaseInsensitiveContains("no errors"))
    }
  }
}

/// Runs `process` (its output set to where it goes, as usual) to its end, passing Ctrl-C on as
/// `waitForwardingInterrupts` does, and throws `ToolFailure` with the error lines of its output
/// when it fails. Its stdout and stderr still reach their places as it writes them.
func runReportingErrors(_ process: Process, tool: String, errors kind: ToolErrorLines) throws {
  final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func add(_ line: String) {
      lock.lock()
      defer { lock.unlock() }
      if lines.count < 10, !lines.contains(line) { lines.append(line) }
    }

    var collected: [String] {
      lock.lock()
      defer { lock.unlock() }
      return lines
    }
  }
  let collector = Collector()
  let group = DispatchGroup()
  // Each stream read on its own, written on to where it went, and scanned line by line.
  func forward(_ destination: Any?, set: (Pipe) -> Void) {
    let target = destination as? FileHandle ?? FileHandle.standardOutput
    let pipe = Pipe()
    set(pipe)
    let reader = pipe.fileHandleForReading
    group.enter()
    DispatchQueue.global().async {
      var pending = Data()
      func scan(_ bytes: Data) {
        // Only lines that can be errors are decoded: every kind's pattern has one of these (on
        // 50 MB of build output, 0.3 s instead of 1.3 s).
        guard ToolErrorLines.needles.contains(where: { bytes.range(of: $0) != nil }) else { return }
        let line = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if kind.matches(line) { collector.add(line) }
      }
      while true {
        let data = reader.availableData
        if data.isEmpty { break }
        // A reader that went away (EPIPE) mustn't abort the run: the throwing write, ignored.
        try? target.write(contentsOf: data)
        pending.append(data)
        var start = pending.startIndex
        while let newline = pending[start...].firstIndex(of: 0x0A) {
          scan(pending[start..<newline])
          start = pending.index(after: newline)
        }
        pending = Data(pending[start...])
      }
      scan(pending)
      group.leave()
    }
  }
  forward(process.standardOutput) { process.standardOutput = $0 }
  forward(process.standardError ?? FileHandle.standardError) { process.standardError = $0 }
  try process.run()
  waitForwardingInterrupts(process)
  group.wait()
  guard process.terminationStatus != 0 else { return }
  throw ToolFailure(tool: tool, status: process.terminationStatus, errors: collector.collected)
}

/// Has a Ctrl-C delete `path` (a temporary folder) before exiting.
func removeOnInterrupt(_ path: String) {
  processLock.lock()
  defer { processLock.unlock() }
  interruptCleanup.append(path)
}

/// Deletes `path` (a temporary folder) when the process ends, normally or on a signal.
func removeAtExit(_ path: String) {
  removeOnInterrupt(path)
  processLock.lock()
  defer { processLock.unlock() }
  atExitCleanup.append(path)
  guard !atExitInstalled else { return }
  atExitInstalled = true
  atexit {
    processLock.lock()
    let folders = atExitCleanup
    processLock.unlock()
    for folder in folders { try? FileManager.default.removeItem(atPath: folder) }
  }
}

nonisolated(unsafe) private var atExitCleanup: [String] = []
nonisolated(unsafe) private var atExitInstalled = false

/// Whether the tool was started with SIGINT ignored, read once at start (`recordInheritedSignals`)
/// before any handler replaces the inherited disposition.
nonisolated(unsafe) private(set) var sigintInheritedIgnored = false

func recordInheritedSignals() {
  var current = sigaction()
  if sigaction(SIGINT, nil, &current) == 0 {
    // Compared as addresses: C function pointers aren't Equatable (SIG_IGN is 1).
    sigintInheritedIgnored = unsafeBitCast(current.__sigaction_u.__sa_handler, to: Int.self) == unsafeBitCast(SIG_IGN, to: Int.self)
  }
}

/// Installs a SIGINT handler using DispatchSource (kqueue-based).
/// Unlike sigaction, this persists even when Swift's async runtime overrides
/// the process-level signal disposition — kqueue monitors signals independently.
///
/// Uses a no-op handler instead of SIG_IGN to prevent the parent from terminating.
/// SIG_IGN is inherited by child processes and preserved across exec/posix_spawn,
/// which would cause xcodebuild to silently ignore SIGINT. A custom handler is
/// reset to SIG_DFL in child processes, so they receive Ctrl-C normally.
private func setupSignalHandler() {
  processLock.lock()
  if signalSource != nil {
    processLock.unlock()
    return
  }

  // SIGTERM and SIGHUP too (a program following --json-events or a CI job
  // stops the tool with SIGTERM), so the children are stopped and the folders cleaned up for
  // each; the exit code is 128 plus the signal, as a shell reports it.
  var sources: [DispatchSourceSignal] = []
  // SIGINT inherited as ignored (a script's `ascelerate … &`) stays ignored for the whole run,
  // children included (Kerem, 2026-11-26); SIGTERM and SIGHUP still stop it.
  for number in sigintInheritedIgnored ? [SIGTERM, SIGHUP] : [SIGINT, SIGTERM, SIGHUP] {
    signal(number, { _ in })
    let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
    source.setEventHandler {
      // Snapshot the running processes under lock, then signal them outside the lock
      // so a concurrent track/untrack can't deadlock with the kill syscall.
      processLock.lock()
      let snapshot = activeProcesses.filter { $0.isRunning }
      let folders = interruptCleanup
      processLock.unlock()
      for process in snapshot {
        let pid = process.processIdentifier
        // Xcode's build service starts each compile in a process group of its own, so the group
        // signal below doesn't reach them, and they kept compiling for a minute after the build
        // stopped (seen 2026-10-23): list them before it stops.
        let descendants = descendantProcesses(of: pid)
        // SIGTERM instead of SIGINT: xcodebuild ignores SIGINT during package resolution.
        // killpg to reach the entire process group (Foundation uses POSIX_SPAWN_SETPGROUP).
        if killpg(pid, SIGTERM) != 0 {
          kill(pid, SIGTERM)
        }
        for descendant in descendants {
          kill(descendant, SIGTERM)
        }
      }
      for folder in folders {
        try? FileManager.default.removeItem(atPath: folder)
      }
      _exit(128 + number)
    }
    source.resume()
    sources.append(source)
  }
  signalSource = sources
  processLock.unlock()
}

/// Every process started under `pid`, children first, as they are now.
private func descendantProcesses(of pid: pid_t) -> [pid_t] {
  var result: [pid_t] = []
  var pending = [pid]
  while let parent = pending.popLast() {
    let count = proc_listchildpids(parent, nil, 0)
    guard count > 0 else { continue }
    // Room for a few started meanwhile.
    var children = [pid_t](repeating: 0, count: Int(count) + 16)
    let found = proc_listchildpids(parent, &children, Int32(children.count * MemoryLayout<pid_t>.size))
    let list = children.prefix(Int(max(found, 0))).filter { $0 > 0 }
    result += list
    pending += list
  }
  return result
}

/// When true, all interactive confirmation prompts are automatically accepted.
nonisolated(unsafe) var autoConfirm = false

/// When true, the running command was invoked with --json: results go to stdout
/// as machine-readable JSON, and interactive input prompts refuse instead of
/// asking (a prompt would corrupt the JSON stream).
nonisolated(unsafe) var jsonMode = false

/// Set by `--dry-run` (see `extractDryRunFlag`); `ASCELERATE_DRY_RUN=1` does the same.
nonisolated(unsafe) var dryRunFlag = false

/// Removes `--dry-run` from a command line and records it in `dryRunFlag`. ArgumentParser has
/// no global options (a root option isn't accepted after a subcommand name), so it is taken out
/// before parsing and accepted anywhere before a `--` terminator.
func extractDryRunFlag(_ args: [String]) -> [String] {
  let end = args.firstIndex(of: "--") ?? args.endIndex
  let options = args[..<end]
  guard options.contains("--dry-run") else { return args }
  dryRunFlag = true
  return options.filter { $0 != "--dry-run" } + args[end...]
}

/// The flag responsible for the current non-interactive mode, for error messages.
var nonInteractiveFlag: String { jsonMode ? "--json" : "--yes" }

/// Shared `--json` flag for read commands. Call `activate()` at the top of `run()`.
struct JSONOption: ParsableArguments {
  @Flag(name: .long, help: "Output machine-readable JSON instead of formatted text.")
  var json = false

  func activate() { if json { jsonMode = true } }
}

/// Finds what a write acts on by its exact name: `find(true)`. Only interactively, when nothing has
/// exactly that name, does a sole partial match (`find(false)`) count, after the user confirms it
/// by name; under --yes a partial match is never taken.
func findForWrite<T>(
  _ name: String, _ kind: String, describe: (T) -> String, _ find: (_ exact: Bool) async throws -> T
) async throws -> T {
  do {
    return try await find(true)
  } catch {
    guard !autoConfirm, !jsonMode, let partial = try? await find(false) else { throw error }
    guard confirm("No \(kind) is named exactly '\(name)'. Use \(describe(partial))? [y/N] ") else { throw error }
    return partial
  }
}

/// Prints a value as pretty-printed JSON (sorted keys, ISO 8601 dates).
func printJSON(_ value: some Encodable) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  encoder.dateEncodingStrategy = .iso8601
  let data = try encoder.encode(value)
  print(String(decoding: data, as: UTF8.self))
}

/// Build numbers recorded by `builds upload` so subsequent workflow steps
/// (`await-processing`, `build attach-latest`) can wait for this specific build.
/// Tracked per platform — one workflow can upload iOS and macOS builds with
/// different build numbers.
nonisolated(unsafe) private var uploadedBuilds: [UploadedBuild] = []

/// A build `builds upload` sent: its number, and as far as the file says, its platform, version
/// and app, so the wait finds this build and not another app's or version's of the same number.
struct UploadedBuild: Sendable {
  let number: String
  let platform: Platform?
  let version: String?
  let bundleID: String?
}

/// Records a successful upload.
func recordUploadedBuild(_ build: UploadedBuild) {
  uploadedBuilds.append(build)
}

/// The latest build uploaded earlier in this process for the app (nil: any) and `platform`; with
/// no platform, the most recent upload of any platform. A platform-specific miss deliberately does
/// NOT fall back to another platform's build — that's how a macOS await would end up polling for
/// an iOS build number.
func lastUploadedBuild(for platform: Platform?, bundleID: String? = nil) -> UploadedBuild? {
  uploadedBuilds.last { build in
    (bundleID == nil || build.bundleID == nil || build.bundleID == bundleID) && (platform == nil || build.platform == platform)
  }
}

/// Archive extensions recognized by `resolveFolder`.
private let archiveExtensions = [".zip", ".tar.gz", ".tgz", ".tar"]

/// Returns true if the path ends with a recognized archive extension.
private func isArchive(_ path: String) -> Bool {
  let lower = path.lowercased()
  return archiveExtensions.contains { lower.hasSuffix($0) }
}

/// Extracts an archive (zip, tar, tar.gz) to a temp directory and returns the path.
private func extractArchiveToTemp(_ path: String) throws -> String {
  if path.lowercased().hasSuffix(".zip") {
    return try extractZipToTemp(path)
  } else {
    return try extractTarToTemp(path)
  }
}

/// Resolves a folder path from an optional argument. If nil, lists subdirectories and
/// archive files in the current directory and lets the user pick one or type a path manually.
/// Archives (zip, tar, tar.gz) are extracted to a temporary directory automatically.
func resolveFolder(_ folder: String?, prompt: String) throws -> String {
  if let f = folder {
    let path = expandPath(f)
    if isArchive(path) {
      guard FileManager.default.fileExists(atPath: path) else {
        throw ValidationError("File not found at '\(path)'.")
      }
      return try extractArchiveToTemp(path)
    }
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
      throw ValidationError("Folder not found at '\(path)'.")
    }
    return path
  }

  // List subdirectories and archive files in the current directory
  let cwd = FileManager.default.currentDirectoryPath
  let entries = (try? FileManager.default.contentsOfDirectory(atPath: cwd))?
    .filter { !$0.hasPrefix(".") }
    .sorted() ?? []

  var candidates: [(name: String, isArchive: Bool)] = []
  for entry in entries {
    let path = (cwd as NSString).appendingPathComponent(entry)
    if isArchive(entry) {
      candidates.append((entry, true))
    } else {
      var isDir: ObjCBool = false
      if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
        candidates.append((entry, false))
      }
    }
  }

  if !candidates.isEmpty {
    print("\(prompt):")
    for (i, c) in candidates.enumerated() {
      let suffix = c.isArchive ? " (archive)" : ""
      print("  [\(i + 1)] \(c.name)\(suffix)")
    }
    let manualOption = candidates.count + 1
    print("  [\(manualOption)] Enter path manually")
    print()

    let options = candidates.map { $0.name + ($0.isArchive ? " (archive)" : "") } + ["Enter path manually"]
    guard let input = readAnswer("Select (1-\(manualOption)): ", kind: .choice, options: options)?.trimmingCharacters(in: .whitespacesAndNewlines),
          let choice = Int(input),
          choice >= 1, choice <= manualOption else {
      throw ValidationError("Invalid selection.")
    }

    if choice <= candidates.count {
      let selected = candidates[choice - 1]
      let fullPath = (cwd as NSString).appendingPathComponent(selected.name)
      return selected.isArchive ? try extractArchiveToTemp(fullPath) : fullPath
    }
  }

  // Manual path entry
  let path = expandPath(try promptText("Path to folder or archive: "))
  if isArchive(path) {
    guard FileManager.default.fileExists(atPath: path) else {
      throw ValidationError("File not found at '\(path)'.")
    }
    return try extractArchiveToTemp(path)
  }
  var isDir: ObjCBool = false
  guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
    throw ValidationError("Folder not found at '\(path)'.")
  }
  return path
}

/// Runs an executable and returns its stdout. Reads the pipe before waiting so
/// large output cannot deadlock against the pipe buffer.
private func captureOutput(_ executable: String, _ arguments: [String]) throws -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = Pipe()
  try process.run()
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw ValidationError("Failed to inspect archive with \(executable) (exit \(process.terminationStatus)).")
  }
  return String(data: data, encoding: .utf8) ?? ""
}

/// Refuses archives with symlink entries or path-traversal names before extraction.
/// Both /usr/bin/unzip and /usr/bin/tar create symlink entries and then write later
/// entries *through* them, letting a crafted archive place files anywhere the user
/// can write. Media archives have no legitimate use for either.
private func ensureSafeArchiveEntries(paths: [String], hasLinkEntries: Bool, archivePath: String) throws {
  if hasLinkEntries {
    throw ValidationError("Archive '\(archivePath)' contains symbolic or hard link entries and cannot be used.")
  }
  for path in paths where !path.isEmpty {
    if path.hasPrefix("/") || path.split(separator: "/").contains("..") {
      throw ValidationError("Archive '\(archivePath)' contains an unsafe path ('\(path)').")
    }
  }
}

/// Extracts a zip file to a temporary directory and returns the media root.
func extractZipToTemp(_ zipPath: String) throws -> String {
  // Pre-scan: bare names for path checks, mode listing for symlink detection.
  let names = try captureOutput("/usr/bin/zipinfo", ["-1", zipPath])
    .components(separatedBy: .newlines)
  let hasLinks = try captureOutput("/usr/bin/zipinfo", [zipPath])
    .components(separatedBy: .newlines)
    .contains { $0.hasPrefix("l") }
  try ensureSafeArchiveEntries(paths: names, hasLinkEntries: hasLinks, archivePath: zipPath)

  let tempDir = NSTemporaryDirectory() + "ascelerate-media-\(UUID().uuidString)"
  try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
  // The unpacked copy goes when the run ends (it was left behind in the temporary folder).
  removeAtExit(tempDir)

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
  process.arguments = ["-q", zipPath, "-d", tempDir]
  try process.run()
  process.waitUntilExit()

  guard process.terminationStatus == 0 else {
    throw ValidationError("Failed to extract zip file '\(zipPath)'.")
  }

  return findMediaRoot(in: tempDir, ignoring: ["__MACOSX"])
}

/// Extracts a tar (or tar.gz/tgz) file to a temporary directory and returns the media root.
func extractTarToTemp(_ tarPath: String) throws -> String {
  // Pre-scan: bare names for path checks, verbose listing for link detection.
  let names = try captureOutput("/usr/bin/tar", ["-tf", tarPath])
    .components(separatedBy: .newlines)
  let hasLinks = try captureOutput("/usr/bin/tar", ["-tvf", tarPath])
    .components(separatedBy: .newlines)
    .contains { $0.hasPrefix("l") || $0.hasPrefix("h") }
  try ensureSafeArchiveEntries(paths: names, hasLinkEntries: hasLinks, archivePath: tarPath)

  let tempDir = NSTemporaryDirectory() + "ascelerate-media-\(UUID().uuidString)"
  try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
  // The unpacked copy goes when the run ends (it was left behind in the temporary folder).
  removeAtExit(tempDir)

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
  process.arguments = ["-xf", tarPath, "-C", tempDir]
  try process.run()
  process.waitUntilExit()

  guard process.terminationStatus == 0 else {
    throw ValidationError("Failed to extract archive '\(tarPath)'.")
  }

  return findMediaRoot(in: tempDir)
}

/// Walks down from `root` through single-child directories until it finds the media root:
/// a directory containing locale subdirectories (e.g. en-US, de-DE, tr) that in turn
/// contain display type subdirectories (e.g. APP_IPHONE_67).
/// A folder named "tr" wrapping the actual locales won't fool it — the locale dirs must
/// contain display types, not more locales.
private func findMediaRoot(in root: String, ignoring: [String] = []) -> String {
  let fm = FileManager.default
  var current = root

  while true {
    let entries = ((try? fm.contentsOfDirectory(atPath: current)) ?? [])
      .filter { !$0.hasPrefix(".") && !ignoring.contains($0) }

    // Find locale-looking subdirectories
    let localeDirs = entries.filter { name in
      var isDir: ObjCBool = false
      let path = (current as NSString).appendingPathComponent(name)
      return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        && isLocaleCode(name)
    }

    // Verify at least one locale dir contains display type subdirectories
    // (SCREAMING_SNAKE_CASE like APP_IPHONE_67), not more locale dirs.
    if !localeDirs.isEmpty {
      let confirmed = localeDirs.contains { locale in
        let localePath = (current as NSString).appendingPathComponent(locale)
        let children = ((try? fm.contentsOfDirectory(atPath: localePath)) ?? [])
          .filter { !$0.hasPrefix(".") }
        return children.contains { name in
          var isDir: ObjCBool = false
          let path = (localePath as NSString).appendingPathComponent(name)
          return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            && name.range(of: #"^[A-Z][A-Z0-9_]+$"#, options: .regularExpression) != nil
        }
      }
      if confirmed { return current }
    }

    // If there's exactly one subdirectory, descend into it
    let subdirs = entries.filter { name in
      var isDir: ObjCBool = false
      let path = (current as NSString).appendingPathComponent(name)
      return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    guard subdirs.count == 1 else { return current }
    current = (current as NSString).appendingPathComponent(subdirs[0])
  }
}

/// Matches locale codes used by App Store Connect (e.g. en-US, de-DE, tr, zh-Hans, pt-BR).
private func isLocaleCode(_ name: String) -> Bool {
  name.range(of: #"^[a-z]{2}(-[a-zA-Z]{2,8})?$"#, options: .regularExpression) != nil
}

/// Resolves a file path from an optional argument. If nil, lists files matching the given
/// extension in the current directory and lets the user pick one or type a path manually.
func resolveFile(_ file: String?, extension ext: String, prompt: String) throws -> String {
  if let f = file {
    let path = expandPath(f)
    guard FileManager.default.fileExists(atPath: path) else {
      throw ValidationError("File not found at '\(path)'.")
    }
    return path
  }

  // List matching files in the current directory
  let cwd = FileManager.default.currentDirectoryPath
  let candidates = (try? FileManager.default.contentsOfDirectory(atPath: cwd))?
    .filter { $0.hasSuffix(".\(ext)") }
    .sorted() ?? []

  if !candidates.isEmpty {
    print("\(prompt):")
    for (i, name) in candidates.enumerated() {
      print("  [\(i + 1)] \(name)")
    }
    let manualOption = candidates.count + 1
    print("  [\(manualOption)] Enter path manually")
    print()

    guard let input = readAnswer("Select (1-\(manualOption)): ", kind: .choice, options: candidates + ["Enter path manually"])?
      .trimmingCharacters(in: .whitespacesAndNewlines),
          let choice = Int(input),
          choice >= 1, choice <= manualOption else {
      throw ValidationError("Invalid selection.")
    }

    if choice <= candidates.count {
      return (cwd as NSString).appendingPathComponent(candidates[choice - 1])
    }
  }

  // Manual path entry
  let path = expandPath(try promptText("Path to file: "))
  guard FileManager.default.fileExists(atPath: path) else {
    throw ValidationError("File not found at '\(path)'.")
  }
  return path
}

/// Prompts for non-empty text input; retries on empty.
func promptText(_ message: String) throws -> String {
  if autoConfirm || jsonMode {
    let label = message.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
    throw ValidationError("\(label) is required — cannot prompt with \(nonInteractiveFlag).")
  }
  guard let line = readAnswer(message) else {
    throw ValidationError("No input available (stdin closed).")
  }
  let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else {
    print("Value cannot be empty. Try again.")
    return try promptText(message)
  }
  return trimmed
}

/// What a question asks for, as its `prompt` event names it.
enum PromptKind: String {
  case confirm, choice, choices, text
}

/// Asks a question and reads the answer, one line from stdin; nil when stdin is closed. Every
/// prompt goes through here: with events on (`--json-events`), the question is printed as a whole
/// line and also goes out as a `prompt` event first, so a program running the command can answer
/// it; in a terminal it waits on the same line.
func readAnswer(_ prompt: String, kind: PromptKind = .text, options: [String]? = nil, optional: Bool = false) -> String? {
  if EventOutput.emitsEvents {
    print(prompt)
    EventOutput.emit(PromptEvent(
      kind: kind.rawValue, message: prompt.trimmingCharacters(in: .whitespaces), options: options, optional: optional ? true : nil))
  } else {
    print(prompt, terminator: "")
  }
  return readLine()
}

/// Prints a [y/N] prompt and returns true if the user (or --yes flag) confirms.
func confirm(_ prompt: String) -> Bool {
  if autoConfirm {
    print(prompt, terminator: "")
    print("y (auto)")
    return true
  }
  guard let answer = readAnswer(prompt, kind: .confirm)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
    answer == "y" || answer == "yes"
  else {
    return false
  }
  return true
}

/// Cleans up a path from interactive input (e.g. drag-drop into Terminal).
/// Strips surrounding quotes and removes backslash escapes.
func sanitizePath(_ path: String) -> String {
  var result = path.trimmingCharacters(in: .whitespacesAndNewlines)

  // Strip surrounding quotes
  if (result.hasPrefix("'") && result.hasSuffix("'"))
    || (result.hasPrefix("\"") && result.hasSuffix("\""))
  {
    result = String(result.dropFirst().dropLast())
  }

  // Remove backslash escapes (e.g. "\ " -> " ", "\~" -> "~")
  result = result.replacingOccurrences(of: "\\", with: "")

  return result
}

/// The user's home folder for ascelerate's own files and `~` in paths: `$HOME` when set, as shells
/// take it (a test or sandbox points it at a temporary folder), else the account's.
/// `homeDirectoryForCurrentUser` ignores `$HOME`.
let homeDirectory: URL = {
  if let home = ProcessInfo.processInfo.environment["HOME"], home.hasPrefix("/") {
    return URL(fileURLWithPath: home, isDirectory: true)
  }
  return FileManager.default.homeDirectoryForCurrentUser
}()

func expandPath(_ path: String) -> String {
  let cleaned = sanitizePath(path)
  if cleaned.hasPrefix("~/") {
    return homeDirectory
      .appendingPathComponent(String(cleaned.dropFirst(2))).path
  }
  return cleaned
}

/// Checks if a path exists. If so, warns and prompts for a new name (pre-filled with the current name).
/// Returns the confirmed path to use.
func confirmOutputPath(_ path: String, isDirectory: Bool) throws -> String {
  var current = path
  let fm = FileManager.default

  while true {
    var isDir: ObjCBool = false
    let exists = fm.fileExists(atPath: expandPath(current), isDirectory: &isDir)

    if !exists { return current }

    if autoConfirm {
      let kind = isDir.boolValue ? "Folder" : "File"
      print("\(kind) '\(current)' already exists. Overwriting. (auto)")
      return current
    }

    let kind = isDir.boolValue ? "Folder" : "File"
    print("\(kind) '\(current)' already exists. Press Enter to overwrite or type a new name:")
    fflush(stdout)

    // End of input isn't Enter: nothing answered, so nothing is replaced.
    guard let line = readAnswer("> ", optional: true) else {
      throw ValidationError("'\(current)' exists and no answer came (end of input); pass --yes to replace it or choose another path.")
    }
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return current }
    current = trimmed
  }
}

/// Compares dotted numeric versions (e.g. "0.12.0"). Returns true if `a` is strictly older than `b`.
/// Missing components are treated as 0; non-numeric parts as 0.
func isVersionOlder(_ a: String, than b: String) -> Bool {
  let pa = a.split(separator: ".").map { Int($0) ?? 0 }
  let pb = b.split(separator: ".").map { Int($0) ?? 0 }
  for i in 0..<max(pa.count, pb.count) {
    let x = i < pa.count ? pa[i] : 0
    let y = i < pb.count ? pb[i] : 0
    if x != y { return x < y }
  }
  return false
}

@discardableResult
/// Returns a version detail string like " (v0.5.0 → v0.6.1)" if completions are older than this
/// binary (a genuine upgrade), nil if current or newer. Never reports a downgrade — an older
/// binary in PATH must not offer to "update" files installed by a newer one.
func completionsVersionDetail() -> String? {
  guard let completionPath = completionScriptPath() else { return nil }

  guard FileManager.default.fileExists(atPath: completionPath),
    let data = FileManager.default.contents(atPath: completionPath),
    let contents = String(data: data, encoding: .utf8)
  else { return nil }

  let currentVersion = Ascelerate.appVersion
  let prefix = "# ascelerate v"

  // Version stamp may be on line 1 (bash) or line 2 (zsh, after #compdef)
  if let range = contents.range(of: prefix),
    contents[contents.startIndex..<range.lowerBound].filter({ $0 == "\n" }).count <= 1
  {
    let afterPrefix = contents[range.upperBound...]
    let stampedVersion = String(afterPrefix.prefix(while: { $0 != "\n" }))
    guard isVersionOlder(stampedVersion, than: currentVersion) else { return nil }
    return " (v\(stampedVersion) → v\(currentVersion))"
  }
  return ""  // installed but no stamp — outdated
}

/// Where `install-completions` puts the completion script for the user's shell (zsh or bash), or
/// nil for another shell.
func completionScriptPath() -> String? {
  guard let shell = ProcessInfo.processInfo.environment["SHELL"] else { return nil }
  if shell.hasSuffix("/zsh") { return homeDirectory.appendingPathComponent(".zfunc/_ascelerate").path }
  if shell.hasSuffix("/bash") { return homeDirectory.appendingPathComponent(".bash_completions/ascelerate.bash").path }
  return nil
}

/// Whether shell completions are installed and current: `current`, `outdated`, `missing`, or
/// `unsupported` for a shell other than zsh and bash.
func completionsStatus() -> String {
  guard let path = completionScriptPath() else { return "unsupported" }
  guard FileManager.default.fileExists(atPath: path) else { return "missing" }
  return completionsVersionDetail() == nil ? "current" : "outdated"
}

/// Whether the AI agent skill is installed and current: `current`, `outdated` or `missing`.
func skillStatus() -> String {
  guard !InstallSkillCommand.installedSkillPaths().isEmpty else { return "missing" }
  return skillVersionDetail() == nil ? "current" : "outdated"
}

/// Returns a version detail string like " (v0.5.0 → v0.6.1)" if any CLI-installed (stamped) skill
/// is outdated, nil if all are current / none installed. Unstamped skills (e.g. installed via
/// `npx ascelerate-skill`) carry no version, so they're skipped to avoid false "outdated" prompts.
func skillVersionDetail() -> String? {
  let currentVersion = Ascelerate.appVersion
  let prefix = "<!-- ascelerate v"

  for path in InstallSkillCommand.installedSkillPaths() {
    guard let data = FileManager.default.contents(atPath: path),
      let contents = String(data: data, encoding: .utf8),
      let range = contents.range(of: prefix),
      let endRange = contents[range.upperBound...].range(of: " -->")
    else { continue }  // not installed or unstamped — skip
    let stampedVersion = String(contents[range.upperBound..<endRange.lowerBound])
    if isVersionOlder(stampedVersion, than: currentVersion) {
      return " (v\(stampedVersion) → v\(currentVersion))"
    }
  }
  return nil
}

// MARK: - Legacy Migration (asc-client/asc → ascelerate)

/// Check for outdated completions and skill, print NOTE for non-interactive contexts.
func checkForUpdates() {
  struct Once { nonisolated(unsafe) static var checked = false }
  guard !Once.checked else { return }
  Once.checked = true

  var notes: [String] = []
  if let detail = completionsVersionDetail() {
    notes.append("Shell completions are outdated\(detail). Run 'ascelerate install-completions' to update.")
  }
  if let detail = skillVersionDetail() {
    notes.append("ascelerate skill is outdated\(detail). Run 'ascelerate install-skill' to update.")
  }
  if !notes.isEmpty {
    // stderr: API commands may be running under --json, and stdout must stay parseable.
    try? FileHandle.standardError.write(contentsOf: Data(("NOTE: " + notes.joined(separator: "\n      ") + "\n\n").utf8))
  }
}

/// Check for outdated completions and skill, interactively offer to update.
func checkForUpdatesInteractively() async -> Bool {
  struct Once { nonisolated(unsafe) static var checked = false }
  guard !Once.checked else { return false }
  Once.checked = true
  // Offered only to someone at a terminal: a script's or an agent's closed stdin isn't a yes.
  guard isatty(STDIN_FILENO) != 0 else { return false }

  let completions = completionsVersionDetail()
  let skill = skillVersionDetail()

  guard completions != nil || skill != nil else { return false }

  // Build prompt
  var items: [String] = []
  if let detail = completions { items.append("shell completions\(detail)") }
  if let detail = skill { items.append("ascelerate skill\(detail)") }

  let label = items.joined(separator: " and ")
  // End of input is no.
  guard let answer = readAnswer("\(label.prefix(1).uppercased())\(label.dropFirst()) outdated. Update now? [Y/n] ", kind: .confirm, optional: true)?
    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  else { print(); return true }
  guard answer.isEmpty || answer == "y" || answer == "yes" else { return true }

  if completions != nil {
    do {
      let command = try InstallCompletionsCommand.parseAsRoot([]) as! InstallCompletionsCommand
      try command.run()
    } catch {
      print("Failed to update completions: \(error)")
    }
  }

  if skill != nil {
    do {
      let command = try InstallSkillCommand.parseAsRoot([]) as! InstallSkillCommand
      try await command.run()
    } catch {
      print("Failed to update skill: \(error)")
    }
  }

  return true
}

/// Prints a numbered list and reads a single selection.
/// Under `--yes` (autoConfirm) an arbitrary auto-pick would be dangerous, so the
/// prompt refuses instead — `nonInteractiveHint` tells the user how to disambiguate
/// (e.g. "Pass --platform to disambiguate.").
func promptSelection<T>(
  _ title: String,
  items: [T],
  display: (T) -> String,
  prompt: String? = nil,
  nonInteractiveHint: String? = nil
) throws -> T {
  guard !items.isEmpty else {
    throw ValidationError("No items to select from.")
  }
  if autoConfirm || jsonMode {
    let listing = items.map { "  - \(display($0))" }.joined(separator: "\n")
    let hint = nonInteractiveHint.map { " \($0)" } ?? ""
    throw ValidationError("\(title) (\(items.count)) — cannot prompt with \(nonInteractiveFlag).\(hint)\n\(listing)")
  }
  print("\(title):")
  for (i, item) in items.enumerated() {
    print("  [\(i + 1)] \(display(item))")
  }
  print()
  let label = prompt ?? "Select"
  guard let line = readAnswer("\(label) (1-\(items.count)): ", kind: .choice, options: items.map(display)) else {
    throw ValidationError("No input available (stdin closed).")
  }
  guard let choice = Int(line.trimmingCharacters(in: .whitespacesAndNewlines)),
        choice >= 1, choice <= items.count else {
    throw ValidationError("Invalid selection.")
  }
  return items[choice - 1]
}

/// Prints a numbered list and reads one or more selections (comma-separated or 'all').
/// When `defaultAll` is true, empty input selects all items.
func promptMultiSelection<T>(
  _ title: String,
  items: [T],
  display: (T) -> String,
  prompt: String? = nil,
  defaultAll: Bool = false
) throws -> [T] {
  guard !items.isEmpty else {
    throw ValidationError("No items to select from.")
  }
  if autoConfirm || jsonMode {
    throw ValidationError("\(title) (\(items.count)) — cannot prompt with \(nonInteractiveFlag).")
  }
  print("\(title):")
  for (i, item) in items.enumerated() {
    print("  [\(i + 1)] \(display(item))")
  }
  print()
  let label = prompt ?? "Select"
  let defaultHint = defaultAll ? " [all]" : ""
  guard let line = readAnswer(
    "\(label) (comma-separated numbers, or 'all')\(defaultHint): ", kind: .choices, options: items.map(display), optional: defaultAll)
  else {
    throw ValidationError("No input available (stdin closed).")
  }
  let input = line.trimmingCharacters(in: .whitespacesAndNewlines)

  if input.isEmpty && defaultAll {
    return items
  }
  guard !input.isEmpty else {
    throw ValidationError("No selection made.")
  }
  if input.lowercased() == "all" {
    return items
  }

  let parts = input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
  var selected: [T] = []
  for part in parts {
    guard let num = Int(part), num >= 1, num <= items.count else {
      throw ValidationError("Invalid selection '\(part)'. Enter numbers between 1 and \(items.count).")
    }
    selected.append(items[num - 1])
  }
  return selected
}

/// Parses and validates a string value against a CaseIterable enum.
/// Returns the matched enum case, or throws with a list of valid values.
func parseEnum<T: RawRepresentable & CaseIterable>(
  _ value: String,
  name: String
) throws -> T where T.RawValue == String {
  guard let val = T(rawValue: value.uppercased()) else {
    let valid = T.allCases.map(\.rawValue).joined(separator: ", ")
    throw ValidationError("Invalid \(name) '\(value)'. Valid values: \(valid)")
  }
  return val
}

/// Parses and validates an optional filter value against a CaseIterable enum.
/// Returns nil when input is nil, or a single-element array on success.
func parseFilter<T: RawRepresentable & CaseIterable>(
  _ value: String?,
  name: String
) throws -> [T]? where T.RawValue == String {
  guard let value else { return nil }
  return [try parseEnum(value, name: name)]
}

/// Collects all items from paginated API responses into a single sorted array.
/// Throws if no items are found.
func fetchAll<S: AsyncSequence, Item>(
  _ pages: S,
  data: (S.Element) -> [Item],
  emptyMessage: String,
  sort: ((Item, Item) -> Bool)? = nil
) async throws -> [Item] {
  var collected: [S.Element] = []
  for try await page in pages {
    collected.append(page)
  }
  return try fetchAll(collected, data: data, emptyMessage: emptyMessage, sort: sort)
}

/// `fetchAll` for pages already fetched (e.g. by `ASCPaging.allPages`).
func fetchAll<Page, Item>(
  _ pages: [Page],
  data: (Page) -> [Item],
  emptyMessage: String,
  sort: ((Item, Item) -> Bool)? = nil
) throws -> [Item] {
  var result = pages.flatMap(data)
  guard !result.isEmpty else {
    throw ValidationError(emptyMessage)
  }
  if let sort {
    result.sort(by: sort)
  }
  return result
}

/// Returns the visible length of a string, stripping ANSI escape sequences.
private func visibleLength(_ str: String) -> Int {
  let stripped = str.replacingOccurrences(
    of: "\u{1B}\\[[0-9;]*m",
    with: "",
    options: .regularExpression
  )
  // Terminal cells, not Characters: CJK and emoji glyphs occupy two cells each —
  // counting them as one misaligns every column after a Japanese app title.
  return stripped.reduce(0) { $0 + terminalWidth($1) }
}

/// Approximate terminal cell width of a character (wcwidth-style): East Asian
/// wide/fullwidth ranges and emoji render as two cells, everything else as one.
private func terminalWidth(_ char: Character) -> Int {
  guard let scalar = char.unicodeScalars.first else { return 1 }
  switch scalar.value {
  case 0x1100...0x115F,        // Hangul Jamo
       0x2E80...0x303E,        // CJK Radicals, Kangxi, CJK Symbols and Punctuation
       0x3041...0x33FF,        // Hiragana, Katakana, CJK Compatibility
       0x3400...0x4DBF,        // CJK Extension A
       0x4E00...0x9FFF,        // CJK Unified Ideographs
       0xA000...0xA4CF,        // Yi
       0xAC00...0xD7A3,        // Hangul Syllables
       0xF900...0xFAFF,        // CJK Compatibility Ideographs
       0xFE30...0xFE4F,        // CJK Compatibility Forms
       0xFF00...0xFF60,        // Fullwidth Forms
       0xFFE0...0xFFE6,        // Fullwidth Signs
       0x1F300...0x1FAFF,      // Emoji & pictographs
       0x20000...0x3FFFD:      // CJK Extensions B+
    return 2
  default:
    return 1
  }
}

/// Pads a string to a target visible width, accounting for ANSI escape sequences.
private func padToVisible(_ str: String, width: Int) -> String {
  let visible = visibleLength(str)
  if visible >= width { return str }
  return str + String(repeating: " ", count: width - visible)
}

// MARK: - Shared Locale Fields

/// A localization reduced to the fields the shared import/export helpers operate on.
struct LocalizationRecord {
  let id: String
  let locale: String
  let name: String?
  let description: String?
}

/// A core product localization (IAP or subscription), whose missing values are empty strings.
protocol ProductLocalization {
  var id: String { get }
  var locale: String { get }
  var name: String { get }
  var description: String { get }
}

extension ProductLocalization {
  var localizationRecord: LocalizationRecord {
    LocalizationRecord(
      id: id, locale: locale, name: name.isEmpty ? nil : name, description: description.isEmpty ? nil : description)
  }
}

extension InAppPurchases.Localization: ProductLocalization {}
extension Subscriptions.Localization: ProductLocalization {}

/// Writes product (IAP/subscription) localizations to a JSON file keyed by locale.
func exportProductLocalizations(
  _ existing: [LocalizationRecord], productID: String, output: String?
) throws {
  var result: [String: ProductLocaleFields] = [:]
  for loc in existing where !loc.locale.isEmpty {
    result[loc.locale] = ProductLocaleFields(name: loc.name, description: loc.description)
  }
  try writeLocalizationFile(result, defaultName: "\(productID)-localizations.json", output: output)
}

/// Drives the shared create-or-update import flow for product (IAP/subscription) localizations:
/// prints the plan, confirms, then for each locale either updates the existing localization or
/// creates a missing one (prompting first). `create`/`update` perform the type-specific API calls.
func importProductLocalizations(
  _ localeUpdates: [String: ProductLocaleFields],
  productName: String,
  existing: [LocalizationRecord],
  verbose: Bool,
  create: (_ locale: String, _ name: String, _ description: String?) async throws -> LocalizationRecord,
  update: (_ id: String, _ name: String?, _ description: String?) async throws -> LocalizationRecord
) async throws {
  print("Importing \(localeUpdates.count) locale(s) for '\(productName)':")
  for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
    print(
      "  [\(localeName(locale))] \(fields.name ?? "—") — \(fields.description?.prefix(60) ?? "—")\(fields.description.map { $0.count > 60 ? "..." : "" } ?? "")"
    )
  }
  print()

  guard confirm("Send updates for \(localeUpdates.count) locale(s)? [y/N] ") else {
    cancelled()
    return
  }
  print()

  let byLocale = Dictionary(
    existing.map { ($0.locale, $0) }, uniquingKeysWith: { first, _ in first })

  for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
    guard let record = byLocale[locale] else {
      guard let name = fields.name else {
        print(
          "  [\(localeName(locale))] Skipped — locale not found in current localizations for the app and \"name\" is required to create it."
        )
        continue
      }
      guard
        confirm(
          "  [\(localeName(locale))] Locale not found in current localizations for the app. Create it? [y/N] "
        )
      else {
        print("  [\(localeName(locale))] Skipped.")
        continue
      }
      let created = try await create(locale, name, fields.description)
      print("  [\(localeName(locale))] \(green("Created."))")
      if verbose { printLocalizationResponse(created) }
      continue
    }

    let updated = try await update(record.id, fields.name, fields.description)
    print("  [\(localeName(locale))] Updated.")
    if verbose { printLocalizationResponse(updated) }
  }

  print()
  print("Done.")
}

private func printLocalizationResponse(_ record: LocalizationRecord) {
  print("    Response:")
  print("      Locale:      \(record.locale.isEmpty ? "—" : localeName(record.locale))")
  if let v = record.name { print("      Name:        \(v)") }
  if let v = record.description {
    print("      Description: \(v.prefix(120))\(v.count > 120 ? "..." : "")")
  }
}

// MARK: - Shared Price Export/Import

/// Writes a product's prices to a JSON file keyed by territory (`PriceFile`: the base territory
/// is the auto-equalize anchor of app and in-app purchase schedules; subscription exports omit it).
func exportProductPrices(_ file: PriceFile, productID: String, output: String?) throws {
  let data = try file.encoded()

  let outputPath = expandPath(
    try confirmOutputPath(output ?? "\(productID)-prices.json", isDirectory: false))
  try data.write(to: URL(fileURLWithPath: outputPath))

  success("Exported", "prices for \(file.prices.count) territor\(file.prices.count == 1 ? "y" : "ies") to \(outputPath)")
}

extension Array {
  /// Splits the array into consecutive chunks of at most `size` elements.
  func chunked(into size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
  }
}

/// A price file (the pricing exports' format), read by the core's rule (`PriceFile.decode`):
/// territory codes in uppercase, "4,99" read as 4.99, and a price that isn't a plain number
/// ("1,300", "1e2", "-1", "nan", "4.99x") refused with every other one like it, before any request
/// (Kerem, 2026-11-26).
func loadPriceFile(_ file: String?) throws -> PriceFile {
  let filePath = try resolveFile(file, extension: "json", prompt: "Select a JSON file")
  let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
  do {
    return try PriceFile.decode(data)
  } catch let error as PriceFile.FileError {
    throw ValidationError("Can't use \((filePath as NSString).lastPathComponent): \(error.localizedDescription)")
  }
}

/// Every price of `file` matched to a tier with `PriceFile.resolve` (the file's base territory
/// anchors Apple's comparable prices; set it to choose the anchor), showing "N of M territories".
/// A price that isn't a tier: all of them are listed and nothing is returned, or with `snap` each
/// takes its nearest tier (the cheaper of two as close) and the snaps are listed.
func resolvePriceFile(
  _ file: PriceFile, snap: Bool, batchSize: Int,
  tiers: @escaping @Sendable ([String]) async throws -> [String: [AppPricing.PricePoint]],
  equalizations: @escaping @Sendable (String) async throws -> [AppPricing.PricePoint]
) async throws -> [String: AppPricing.PricePoint] {
  let total = file.prices.count
  let label = "Resolving price points"
  if !isTerminal { print("\(label) for \(total) territor\(total == 1 ? "y" : "ies")…") }
  let resolution = try await file.resolve(batchSize: batchSize, tiers: tiers, equalizations: equalizations) { done, total in
    guard isTerminal else { return }
    print("\r\(label): \(done) of \(total) territor\(total == 1 ? "y" : "ies")", terminator: "")
    fflush(stdout)
  }
  if isTerminal { print() }
  var points = resolution.points
  guard !resolution.mismatches.isEmpty else { return points }
  if snap {
    var snaps: [PriceSnapping.Snap] = []
    for mismatch in resolution.mismatches {
      guard let tier = mismatch.nearestTier else {
        throw ValidationError("No price tiers available for territory \(mismatch.territoryID).")
      }
      points[mismatch.territoryID] = tier
      snaps.append(.init(territoryID: mismatch.territoryID, price: mismatch.price, tier: tier.customerPrice))
    }
    PriceSnapping.report(snaps)
    return points
  }
  var message = "\(resolution.mismatches.count) price\(resolution.mismatches.count == 1 ? " isn't a tier" : "s aren't tiers") of this product, so nothing was sent:\n"
  for mismatch in resolution.mismatches {
    message += mismatch.nearest.isEmpty
      ? "  \(mismatch.territoryID) \(mismatch.price): no price tiers in this territory\n"
      : "  \(mismatch.territoryID) \(mismatch.price): nearest tiers \(mismatch.nearest.joined(separator: ", "))\n"
  }
  message += "Pass --snap to use the nearest tier (the cheaper of two as close)."
  throw ValidationError(message)
}

/// A price point reduced to the fields the shared tier renderer needs. Decouples the renderer
/// from the concrete IAP vs subscription price-point types.
struct PriceTier {
  let id: String
  let customerPrice: String?
  let proceeds: String?
}

/// Renders available price tiers for a territory as a sorted table (by customer price),
/// or a "no tiers" message when empty. Shared by `iap pricing tiers` and `sub pricing tiers`.
func printPriceTiers(_ tiers: [PriceTier], currency: String?, territoryID: String) {
  if tiers.isEmpty {
    print("No price tiers found for territory \(territoryID).")
    return
  }
  let cur = currency ?? ""
  let sorted = tiers.sorted {
    (Double($0.customerPrice ?? "0") ?? 0) < (Double($1.customerPrice ?? "0") ?? 0)
  }
  Table.print(
    headers: ["Tier ID", "Customer Price", "Proceeds", "Currency"],
    rows: sorted.map { [$0.id, $0.customerPrice ?? "—", $0.proceeds ?? "—", cur] }
  )
}

/// Parses a customer-facing price string (e.g. "4.99") to a Double, or throws ValidationError.
func parseCustomerPrice(_ price: String) throws -> Double {
  guard let value = Double(price.trimmingCharacters(in: .whitespaces)) else {
    throw ValidationError("Invalid price '\(price)'. Use a decimal number like 4.99.")
  }
  return value
}

/// Finds the price point whose customer price matches `target` (within 0.001) in `territoryID`.
/// Throws ValidationError for an empty tier list, or no match — listing the five nearest tiers
/// by price distance. `priceLabel` is the original price string, used only in error text. For a
/// single price given on the command line; the imports match with `PriceFile.resolve`.
func findPricePoint(
  in tiers: [AppPricing.PricePoint], target: Double, priceLabel: String, territoryID: String, currency: String?
) throws -> AppPricing.PricePoint {
  guard !tiers.isEmpty else {
    throw ValidationError("No price tiers available for territory \(territoryID).")
  }
  if let exact = tiers.first(where: {
    guard let v = Double($0.customerPrice) else { return false }
    return abs(v - target) < 0.001
  }) {
    return exact
  }
  // Compared as decimals, the cheaper first when two are as close (as Doubles, 2.49 − 1.99 and
  // 2.99 − 2.49 differ), as AscelerateCore's PriceFile does.
  let wanted = Decimal(string: priceLabel.trimmingCharacters(in: .whitespaces)) ?? Decimal(target)
  let nearest = tiers
    .compactMap { p -> (AppPricing.PricePoint, Decimal, Decimal)? in
      guard let v = Decimal(string: p.customerPrice) else { return nil }
      return (p, abs(v - wanted), v)
    }
    .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 < $1.2 }
    .prefix(5)
    .map(\.0)
  var msg = "No tier with customer price \(priceLabel) \(currency ?? "") in territory \(territoryID).\n"
  msg += "Nearest tiers: " + nearest.map(\.customerPrice).joined(separator: ", ")
  throw ValidationError(msg)
}

/// A price import's `--snap`: App Store Connect takes only its own tiers, so a file price that
/// isn't one takes the nearest tier (the cheaper when two are as close) instead of failing the
/// import; every snap is listed before the confirmation.
enum PriceSnapping {
  struct Snap: Sendable {
    let territoryID: String
    let price: String
    let tier: String
  }

  static func report(_ snaps: [Snap]) {
    guard !snaps.isEmpty else { return }
    print(yellow("Snapped to the nearest tier (\(snaps.count) territor\(snaps.count == 1 ? "y" : "ies")):"))
    for snap in snaps {
      let up = (Decimal(string: snap.tier) ?? 0) > (Decimal(string: snap.price) ?? 0)
      print("  \(snap.territoryID): \(snap.price) → \(up ? green(snap.tier) : red(snap.tier))")
    }
  }
}

enum Table {
  static func print(headers: [String], rows: [[String]]) {
    guard !rows.isEmpty else {
      Swift.print("No results.")
      return
    }

    let columnCount = headers.count
    var widths = headers.map(\.count)

    for row in rows {
      for (i, cell) in row.prefix(columnCount).enumerated() {
        widths[i] = max(widths[i], visibleLength(cell))
      }
    }

    let headerLine = headers.enumerated().map { i, h in
      h.padding(toLength: widths[i], withPad: " ", startingAt: 0)
    }.joined(separator: "  ")

    let separator = widths.map { String(repeating: "─", count: $0) }.joined(separator: "──")

    Swift.print(headerLine)
    Swift.print(separator)

    for row in rows {
      if row.allSatisfy({ $0.isEmpty }) {
        Swift.print()
        continue
      }
      let line = row.prefix(columnCount).enumerated().map { i, cell in
        padToVisible(cell, width: widths[i])
      }.joined(separator: "  ")
      Swift.print(line)
    }
  }
}

/// A `--limit` is 1 or more: 0 and negatives used to go to Apple (or crash a local cut).
func checkLimit(_ limit: Int, option: String = "--limit") throws {
  guard limit >= 1 else { throw ValidationError("\(option) must be 1 or more.") }
}

/// A file's JSON as `type`; a file that doesn't fit says so, naming the file and where it went
/// wrong (it used to read as an unexpected response from App Store Connect).
func decodeFile<T: Decodable>(_ type: T.Type, from data: Data, path: String) throws -> T {
  do {
    return try JSONDecoder().decode(type, from: data)
  } catch let error as DecodingError {
    throw ValidationError("Can't read \((path as NSString).lastPathComponent): \(describeDecodingError(error))")
  }
}

// MARK: - Localization files (the import and export commands of products, events and pages)

/// A localization file for an import, picked (`file`, else a list of the folder's JSON files)
/// and read by the core (`LocalizationFile.decode`, its wording: Kerem, 2026-11-26); an empty one
/// is refused.
func readLocalizationFile<Fields: Decodable>(_ file: String?, as type: Fields.Type) throws -> [String: Fields] {
  let filePath = try resolveFile(file, extension: "json", prompt: "Select a JSON file")
  let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
  do {
    return try LocalizationFile.decode(data, as: type)
  } catch let error as LocalizationFile.FileError {
    throw ValidationError(error.localizedDescription)
  }
}

/// Writes an export's localization file (`LocalizationFile.encode`: pretty, keys sorted) to
/// `output`, else `defaultName`, and says how many languages it holds.
func writeLocalizationFile<Fields: Encodable>(_ file: [String: Fields], defaultName: String, output: String?) throws {
  let data = try LocalizationFile.encode(file)
  let outputPath = expandPath(try confirmOutputPath(output ?? defaultName, isDirectory: false))
  try data.write(to: URL(fileURLWithPath: outputPath))
  success("Exported", "\(file.count) locale(s) to \(outputPath)")
}

/// A `--preview-frame` timecode, hh:mm:ss:frame (00:00:03:00): Apple refuses 00:00:03 and other
/// forms after the upload, so it's checked before.
func checkPreviewFrame(_ timecode: String?) throws {
  guard let timecode else { return }
  guard timecode.wholeMatch(of: /[0-9]{2}:[0-5][0-9]:[0-5][0-9]:[0-9]{2}/) != nil else {
    throw ValidationError("--preview-frame '\(timecode)' isn't a timecode: hh:mm:ss:frame, such as 00:00:03:00.")
  }
}

// MARK: - Change lists (what an update sends, shown before its confirmation)

/// "  Label: old → new" for a value given (`new` nil: not changing; an empty old shows as "—").
func changeLine(_ label: String, _ old: String?, _ new: String?) -> String? {
  guard let new else { return nil }
  return "  \(label): \(old.flatMap { $0.isEmpty ? nil : $0 } ?? "—") → \(new.isEmpty ? "—" : new)"
}

/// Prints the title and the changes, then a blank line.
func printChanges(_ title: String, _ lines: [String?]) {
  print(title)
  for line in lines.compactMap({ $0 }) { print(line) }
  print()
}

/// The App Review or beta review information an update changes, old → new (the password shown as
/// changed, not its value).
func reviewInformationChanges(from old: ReviewInformation?, to new: ReviewInformation) -> [String?] {
  func yesNo(_ value: Bool?) -> String? { value.map { $0 ? "Yes" : "No" } }
  return [
    changeLine("Contact first name", old?.contactFirstName, new.contactFirstName),
    changeLine("Contact last name", old?.contactLastName, new.contactLastName),
    changeLine("Phone", old?.contactPhone, new.contactPhone),
    changeLine("Email", old?.contactEmail, new.contactEmail),
    changeLine("Demo account required", yesNo(old?.demoAccountRequired), yesNo(new.demoAccountRequired)),
    changeLine("Demo account", old?.demoAccountName, new.demoAccountName),
    new.demoAccountPassword.map { _ in "  Demo password: changed" },
    changeLine("Notes", old?.notes, new.notes),
  ]
}

