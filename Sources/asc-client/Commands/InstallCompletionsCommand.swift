import ArgumentParser
import Foundation

struct InstallCompletionsCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install-completions",
    abstract: "Install shell completions for asc-client."
  )

  func run() throws {
    guard let shell = ProcessInfo.processInfo.environment["SHELL"] else {
      throw ValidationError("Cannot detect shell. Set the SHELL environment variable.")
    }

    let home = FileManager.default.homeDirectoryForCurrentUser
    let fm = FileManager.default

    if shell.hasSuffix("/zsh") {
      try installZsh(home: home, fm: fm)
    } else if shell.hasSuffix("/bash") {
      try installBash(home: home, fm: fm)
    } else {
      throw ValidationError(
        "Only zsh and bash are supported. Detected: \(shell)")
    }

    print()
    print("Done. Restart your shell or run: source ~/.\(shell.hasSuffix("/zsh") ? "zshrc" : "bashrc")")
  }

  private func installZsh(home: URL, fm: FileManager) throws {
    // 1. Create ~/.zfunc if needed
    let zfuncDir = home.appendingPathComponent(".zfunc")
    if !fm.fileExists(atPath: zfuncDir.path) {
      try fm.createDirectory(at: zfuncDir, withIntermediateDirectories: true)
      print("Created \(zfuncDir.path)/")
    } else {
      print("\(zfuncDir.path)/ already exists.")
    }

    // 2. Write completion script (with patched help completions and alphabetical sorting)
    var completionScript = patchZshHelpCompletions(ASCClient.completionScript(for: .zsh))
    // Remove -V flag so zsh sorts subcommands alphabetically (reliable across environments)
    completionScript = completionScript.replacingOccurrences(
      of: "_describe -V subcommand subcommands", with: "_describe subcommand subcommands")
    // Stamp version so we can detect outdated completions after upgrades
    completionScript = "# asc-client v\(ASCClient.configuration.version)\n" + completionScript
    let completionFile = zfuncDir.appendingPathComponent("_asc-client")
    try completionScript.write(to: completionFile, atomically: true, encoding: .utf8)
    print("Installed completion script to \(completionFile.path)")

    // 3. Ensure ~/.zshrc_local has fpath and compinit
    let zshrcLocal = home.appendingPathComponent(".zshrc_local")
    var localContents = ""
    if fm.fileExists(atPath: zshrcLocal.path) {
      localContents = try String(contentsOf: zshrcLocal, encoding: .utf8)
    }

    let fpathLine = "fpath=(~/.zfunc $fpath)"
    let compinitLine = "autoload -Uz compinit && compinit"
    var localModified = false

    if !localContents.contains(fpathLine) {
      let block = "\n# asc-client completions\n\(fpathLine)\n\(compinitLine)\n"
      localContents += block
      localModified = true
    } else if !localContents.contains(compinitLine) {
      localContents = localContents.replacingOccurrences(
        of: fpathLine, with: "\(fpathLine)\n\(compinitLine)")
      localModified = true
    }

    if localModified {
      try localContents.write(to: zshrcLocal, atomically: true, encoding: .utf8)
      print("Updated \(zshrcLocal.path)")
    } else {
      print("\(zshrcLocal.path) already configured.")
    }

    // 4. Ensure ~/.zshrc sources ~/.zshrc_local
    try ensureSourceLine(
      rcFile: home.appendingPathComponent(".zshrc"),
      sourceLine: "source ~/.zshrc_local",
      fm: fm
    )
  }

  private func installBash(home: URL, fm: FileManager) throws {
    // 1. Create ~/.bash_completions if needed
    let completionsDir = home.appendingPathComponent(".bash_completions")
    if !fm.fileExists(atPath: completionsDir.path) {
      try fm.createDirectory(at: completionsDir, withIntermediateDirectories: true)
      print("Created \(completionsDir.path)/")
    } else {
      print("\(completionsDir.path)/ already exists.")
    }

    // 2. Write completion script (with patched help completions)
    var completionScript = patchBashHelpCompletions(ASCClient.completionScript(for: .bash))
    // Stamp version so we can detect outdated completions after upgrades
    completionScript = "# asc-client v\(ASCClient.configuration.version)\n" + completionScript
    let completionFile = completionsDir.appendingPathComponent("asc-client.bash")
    try completionScript.write(to: completionFile, atomically: true, encoding: .utf8)
    print("Installed completion script to \(completionFile.path)")

    // 3. Ensure ~/.bashrc_local sources the completion script
    let bashrcLocal = home.appendingPathComponent(".bashrc_local")
    var localContents = ""
    if fm.fileExists(atPath: bashrcLocal.path) {
      localContents = try String(contentsOf: bashrcLocal, encoding: .utf8)
    }

    let sourceLine = "source ~/.bash_completions/asc-client.bash"
    if !localContents.contains(sourceLine) {
      localContents += "\n# asc-client completions\n\(sourceLine)\n"
      try localContents.write(to: bashrcLocal, atomically: true, encoding: .utf8)
      print("Updated \(bashrcLocal.path)")
    } else {
      print("\(bashrcLocal.path) already configured.")
    }

    // 4. Ensure ~/.bashrc sources ~/.bashrc_local
    try ensureSourceLine(
      rcFile: home.appendingPathComponent(".bashrc"),
      sourceLine: "[ -f ~/.bashrc_local ] && source ~/.bashrc_local",
      fm: fm
    )
  }

  /// Patches the zsh completion script so `asc-client help <tab>` lists subcommands.
  private func patchZshHelpCompletions(_ script: String) -> String {
    let entries = ASCClient.configuration.subcommands
      .map { sub in
        let name = sub._commandName
        let abstract = sub.configuration.abstract
        return "            '\(name):\(abstract)'"
      }
      .joined(separator: "\n")

    let broken = """
      _asc-client_help() {
          local -i ret=1
          local -ar arg_specs=(
              '*:subcommands:'
              '--version[Show the version.]'
          )
          _arguments -w -s -S : "${arg_specs[@]}" && ret=0

          return "${ret}"
      }
      """

    let fixed = """
      _asc-client_help() {
          local -i ret=1
          local -ar arg_specs=(
              '--version[Show the version.]'
          )
          _arguments -w -s -S : "${arg_specs[@]}" && ret=0
          local -ar subcommands=(
      \(entries)
          )
          _describe -V subcommand subcommands && ret=0

          return "${ret}"
      }
      """

    return script.replacingOccurrences(of: broken, with: fixed)
  }

  /// Patches the bash completion script so `asc-client help <tab>` lists subcommands.
  private func patchBashHelpCompletions(_ script: String) -> String {
    let subcommands = ASCClient.configuration.subcommands
      .map { $0._commandName }
      .joined(separator: " ")

    let broken = """
      _asc-client_help() {
          repeating_flags=()
          non_repeating_flags=(--version)
          repeating_options=()
          non_repeating_options=()
          __asc-client_offer_flags_options -1
      }
      """

    let fixed = """
      _asc-client_help() {
          repeating_flags=()
          non_repeating_flags=(--version)
          repeating_options=()
          non_repeating_options=()
          __asc-client_offer_flags_options -1
          COMPREPLY+=($(compgen -W '\(subcommands)' -- "${cur}"))
      }
      """

    return script.replacingOccurrences(of: broken, with: fixed)
  }

  private func ensureSourceLine(rcFile: URL, sourceLine: String, fm: FileManager) throws {
    if fm.fileExists(atPath: rcFile.path) {
      let contents = try String(contentsOf: rcFile, encoding: .utf8)
      if !contents.contains(sourceLine) {
        let newContents = sourceLine + "\n" + contents
        try newContents.write(to: rcFile, atomically: true, encoding: .utf8)
        print("Updated \(rcFile.path)")
      } else {
        print("\(rcFile.path) already configured.")
      }
    } else {
      try (sourceLine + "\n").write(to: rcFile, atomically: true, encoding: .utf8)
      print("Created \(rcFile.path)")
    }
  }
}
