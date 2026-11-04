import ArgumentParser
import Foundation

/// The tool's own settings (`ascelerate settings`), in `~/.ascelerate/settings.json`: apart from
/// `config.json`, which holds the API key and exists only once one is configured.
struct CLISettings: Codable {
  /// How much of xcodebuild's output `builds archive` shows: `quiet` (warnings and errors) or
  /// `full`; unset, full in a terminal and quiet for a program following events.
  var xcodebuildOutput: String?

  static let file = Config.configDirectory.appendingPathComponent("settings.json")

  /// The saved settings; none saved (or unreadable) reads as defaults.
  static func load() -> CLISettings {
    guard let data = try? Data(contentsOf: file) else { return CLISettings() }
    return (try? JSONDecoder().decode(CLISettings.self, from: data)) ?? CLISettings()
  }

  func save() throws {
    try Config.createDirectory()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(self).write(to: Self.file, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.file.path)
  }
}

/// How much of xcodebuild's output to pass on: everything, or only warnings and errors
/// (`xcodebuild -quiet`), whose full output (every compile command, kilobytes a line) is more than
/// a log view can follow.
enum XcodebuildOutput: String, CaseIterable, ExpressibleByArgument {
  case quiet, full

  /// Set while `run-workflow --json-events` runs its steps: a program follows them, so their
  /// xcodebuild output defaults to quiet.
  @TaskLocal static var followedByProgram = false

  static let environmentKey = "ASCELERATE_XCODEBUILD_OUTPUT"

  /// The command's own choice, else `ASCELERATE_XCODEBUILD_OUTPUT`, else the setting, else quiet
  /// for a program following events (`followed`) and full otherwise.
  static func resolve(_ option: XcodebuildOutput?, followed: Bool) -> XcodebuildOutput {
    if let option { return option }
    if let value = ProcessInfo.processInfo.environment[environmentKey], let output = XcodebuildOutput(rawValue: value.lowercased()) {
      return output
    }
    if let saved = CLISettings.load().xcodebuildOutput.flatMap(XcodebuildOutput.init(rawValue:)) { return saved }
    return followed || followedByProgram ? .quiet : .full
  }
}

struct SettingsCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "settings",
    abstract: "The tool's settings: how much of xcodebuild's output builds archive shows.",
    discussion: """
      Saved in ~/.ascelerate/settings.json. --xcodebuild-output quiet shows only xcodebuild's \
      warnings and errors, full everything, default goes back to the default: full in a terminal, \
      quiet for a program following --json-events. ASCELERATE_XCODEBUILD_OUTPUT overrides it for \
      one run, and builds archive --xcodebuild-output for one command.
      """
  )

  @Option(name: .long, help: "quiet, full or default.")
  var xcodebuildOutput: String?

  func run() throws {
    var settings = CLISettings.load()
    if let value = xcodebuildOutput?.lowercased() {
      if value == "default" {
        settings.xcodebuildOutput = nil
      } else {
        guard XcodebuildOutput(rawValue: value) != nil else { throw ValidationError("--xcodebuild-output is quiet, full or default.") }
        settings.xcodebuildOutput = value
      }
      try settings.save()
    }
    print("xcodebuild output: \(settings.xcodebuildOutput ?? "default (full in a terminal, quiet for a program following events)")")
    if let value = ProcessInfo.processInfo.environment[XcodebuildOutput.environmentKey] {
      print("  \(XcodebuildOutput.environmentKey)=\(value) overrides it in this shell.")
    }
  }
}
