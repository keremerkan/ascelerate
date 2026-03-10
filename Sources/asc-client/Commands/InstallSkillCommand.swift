import ArgumentParser
import Foundation

struct InstallSkillCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install-skill",
    abstract: "Install the asc-client skill for Claude Code."
  )

  @Flag(name: .long, help: "Remove the installed skill.")
  var uninstall = false

  func run() async throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let skillDir = home.appendingPathComponent(".claude/skills/asc-client")
    let skillFile = skillDir.appendingPathComponent("SKILL.md")
    let fm = FileManager.default

    if uninstall {
      guard fm.fileExists(atPath: skillFile.path) else {
        print("No skill installed at \(skillFile.path)")
        return
      }
      try fm.removeItem(at: skillDir)
      print(green("Removed") + " asc-client skill from \(skillDir.path)")
      return
    }

    print("Fetching latest skill from GitHub...")
    let url = URL(string: "https://raw.githubusercontent.com/keremerkan/asc-client/main/skills/asc-client/SKILL.md")!
    let (data, response) = try await URLSession.shared.data(from: url)

    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw ValidationError("Failed to fetch skill file from GitHub.")
    }

    guard let content = String(data: data, encoding: .utf8) else {
      throw ValidationError("Invalid skill file content.")
    }

    try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)

    let stamped = "<!-- asc-client v\(ASCClient.appVersion) -->\n" + content
    try stamped.write(to: skillFile, atomically: true, encoding: .utf8)

    print(green("Installed") + " asc-client skill v\(ASCClient.appVersion) for Claude Code.")
    print("  \(skillFile.path)")
    print()
    print("Claude Code will discover the skill automatically.")
    print()
    print("For other AI tools: npx asc-client-skill")
  }

  static let skillPath: String = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".claude/skills/asc-client/SKILL.md").path
  }()
}

func checkSkillVersion() {
  struct Once { nonisolated(unsafe) static var checked = false }
  guard !Once.checked else { return }
  Once.checked = true

  let path = InstallSkillCommand.skillPath
  guard FileManager.default.fileExists(atPath: path),
        let data = FileManager.default.contents(atPath: path),
        let contents = String(data: data, encoding: .utf8)
  else { return }

  let prefix = "<!-- asc-client v"
  guard let range = contents.range(of: prefix) else { return }
  let afterPrefix = contents[range.upperBound...]
  guard let endRange = afterPrefix.range(of: " -->") else { return }
  let stampedVersion = String(afterPrefix[..<endRange.lowerBound])

  let currentVersion = ASCClient.appVersion
  guard stampedVersion != currentVersion else { return }

  print("NOTE: Claude Code skill is outdated (v\(stampedVersion) → v\(currentVersion)). Run 'asc-client install-skill' to update.\n")
}
