import ArgumentParser
import Foundation

struct InstallSkillCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install-skill",
    abstract: "Install or update the ascelerate skill for your AI coding agents."
  )

  @Flag(name: .long, help: "Remove the installed skill from every agent.")
  var uninstall = false

  @Flag(name: .long, help: "Install for all supported agents, even those not auto-detected.")
  var all = false

  /// A supported AI coding agent and where its skill file lives (relative to home).
  struct Agent {
    let name: String
    let dir: String
    let file: String
    /// Config directories whose presence marks the agent as installed; empty = not auto-detectable.
    /// Grok Build reads the Claude Code skill path natively, so one entry serves both —
    /// detected via either `~/.claude` or `~/.grok`.
    let detects: [String]
  }

  static let agents: [Agent] = [
    .init(name: "Claude Code / Grok Build", dir: ".claude/skills/ascelerate", file: "SKILL.md", detects: [".claude", ".grok"]),
    .init(name: "Cursor", dir: ".cursor/rules", file: "ascelerate.md", detects: [".cursor"]),
    .init(name: "Windsurf", dir: ".windsurf/rules", file: "ascelerate.md", detects: [".windsurf"]),
    .init(name: "GitHub Copilot", dir: ".github/instructions", file: "ascelerate.md", detects: []),
  ]

  private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
  static func skillFileURL(_ a: Agent) -> URL {
    home.appendingPathComponent(a.dir).appendingPathComponent(a.file)
  }
  static func isInstalled(_ a: Agent) -> Bool {
    FileManager.default.fileExists(atPath: skillFileURL(a).path)
  }
  static func isDetected(_ a: Agent) -> Bool {
    a.detects.contains {
      FileManager.default.fileExists(atPath: home.appendingPathComponent($0).path)
    }
  }

  /// Paths of every agent that currently has the skill installed (used by the update check).
  static func installedSkillPaths() -> [String] {
    agents.filter { isInstalled($0) }.map { skillFileURL($0).path }
  }

  func run() async throws {
    let fm = FileManager.default

    if uninstall {
      let installed = Self.agents.filter { Self.isInstalled($0) }
      guard !installed.isEmpty else {
        print("No ascelerate skill is installed.")
        return
      }
      for agent in installed {
        try? fm.removeItem(at: Self.skillFileURL(agent))
        success("Removed", "\(agent.name) skill.")
      }
      return
    }

    // Target every agent that's detected or already has the skill (or all four with --all).
    let targets = Self.agents.filter { all || Self.isInstalled($0) || Self.isDetected($0) }
    guard !targets.isEmpty else {
      print("No supported AI coding agents detected (Claude Code, Grok Build, Cursor, Windsurf).")
      print("Use --all to install for every agent, or run: npx ascelerate-skill")
      return
    }

    print("Fetching latest skill from GitHub...")
    let url = URL(
      string:
        "https://raw.githubusercontent.com/keremerkan/ascelerate/main/skills/ascelerate/SKILL.md")!
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw ValidationError("Failed to fetch skill file from GitHub.")
    }
    guard let content = String(data: data, encoding: .utf8) else {
      throw ValidationError("Invalid skill file content.")
    }
    let stamped = "<!-- ascelerate v\(Ascelerate.appVersion) -->\n" + content

    print()
    for agent in targets {
      let fileURL = Self.skillFileURL(agent)
      let existed = Self.isInstalled(agent)
      try fm.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try stamped.write(to: fileURL, atomically: true, encoding: .utf8)
      success(
        existed ? "Updated" : "Installed",
        "\(agent.name) skill v\(Ascelerate.appVersion) (\(fileURL.path)).")
    }

    let targeted = Set(targets.map(\.name))
    let skipped = Self.agents.filter { !targeted.contains($0.name) }
    if !skipped.isEmpty {
      print()
      print(
        "Not installed for: \(skipped.map(\.name).joined(separator: ", ")) — pass --all to include them."
      )
    }
  }
}
