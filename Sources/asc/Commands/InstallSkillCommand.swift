import ArgumentParser
import Foundation

struct InstallSkillCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install-skill",
    abstract: "Install the asc skill for Claude Code."
  )

  @Flag(name: .long, help: "Remove the installed skill.")
  var uninstall = false

  func run() async throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let skillDir = home.appendingPathComponent(".claude/skills/asc")
    let skillFile = skillDir.appendingPathComponent("SKILL.md")
    let fm = FileManager.default

    if uninstall {
      guard fm.fileExists(atPath: skillFile.path) else {
        print("No skill installed at \(skillFile.path)")
        return
      }
      try fm.removeItem(at: skillDir)
      print(green("Removed") + " asc skill from \(skillDir.path)")
      return
    }

    print("Fetching latest skill from GitHub...")
    let url = URL(string: "https://raw.githubusercontent.com/keremerkan/asc-cli/main/skills/asc/SKILL.md")!
    let (data, response) = try await URLSession.shared.data(from: url)

    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw ValidationError("Failed to fetch skill file from GitHub.")
    }

    guard let content = String(data: data, encoding: .utf8) else {
      throw ValidationError("Invalid skill file content.")
    }

    try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)

    let stamped = "<!-- asc v\(ASC.appVersion) -->\n" + content
    try stamped.write(to: skillFile, atomically: true, encoding: .utf8)

    print(green("Installed") + " asc skill v\(ASC.appVersion) for Claude Code.")
    print("  \(skillFile.path)")
    print()
    print("Claude Code will discover the skill automatically.")
    print()
    print("For other AI tools: npx asc-skill")
  }

  static let skillPath: String = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".claude/skills/asc/SKILL.md").path
  }()
}
