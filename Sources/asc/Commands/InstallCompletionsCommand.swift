import ArgumentParser
import Foundation

struct InstallCompletionsCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install-completions",
    abstract: "Install shell completions for asc."
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
    var completionScript = patchZshHelpCompletions(ASC.completionScript(for: .zsh))
    // Remove -V flag so zsh sorts completions alphabetically
    completionScript = completionScript.replacingOccurrences(
      of: "_describe -V ", with: "_describe ")
    // Fix _files -g in subcommand functions: ArgumentParser sets extendedglob+nullglob
    // which breaks _files -g (pattern:tag syntax conflicts with extendedglob modifiers).
    // Replace _files -g with _asc_files wrapper that uses zstyle file-patterns instead.
    completionScript = patchFileCompletions(completionScript)
    // Stamp version after the #compdef line (must remain first line for zsh to recognize)
    completionScript = completionScript.replacingOccurrences(
      of: "#compdef asc\n",
      with: "#compdef asc\n# asc v\(ASC.appVersion)\n")
    let completionFile = zfuncDir.appendingPathComponent("_asc")
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
      let block = "\n# asc completions\n\(fpathLine)\n\(compinitLine)\n"
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
    var completionScript = patchBashHelpCompletions(ASC.completionScript(for: .bash))
    // Stamp version so we can detect outdated completions after upgrades
    completionScript = "# asc v\(ASC.appVersion)\n" + completionScript
    let completionFile = completionsDir.appendingPathComponent("asc.bash")
    try completionScript.write(to: completionFile, atomically: true, encoding: .utf8)
    print("Installed completion script to \(completionFile.path)")

    // 3. Ensure ~/.bashrc_local sources the completion script
    let bashrcLocal = home.appendingPathComponent(".bashrc_local")
    var localContents = ""
    if fm.fileExists(atPath: bashrcLocal.path) {
      localContents = try String(contentsOf: bashrcLocal, encoding: .utf8)
    }

    let sourceLine = "source ~/.bash_completions/asc.bash"
    if !localContents.contains(sourceLine) {
      localContents += "\n# asc completions\n\(sourceLine)\n"
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

  /// Patches the zsh completion script so `asc help <tab>` lists subcommands.
  private func patchZshHelpCompletions(_ script: String) -> String {
    let entries = ASC.configuration.subcommands
      .map { sub in
        let name = sub._commandName
        let abstract = sub.configuration.abstract
        return "            '\(name):\(abstract)'"
      }
      .joined(separator: "\n")

    let broken = """
      _asc_help() {
          local -i ret=1
          local -ar arg_specs=(
              '*:subcommands:'
          )
          _arguments -w -s -S : "${arg_specs[@]}" && ret=0

          return "${ret}"
      }
      """

    let fixed = """
      _asc_help() {
          local -i ret=1
          local -ar arg_specs=(
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

  /// Patches the bash completion script so `asc help <tab>` lists subcommands.
  private func patchBashHelpCompletions(_ script: String) -> String {
    let subcommands = ASC.configuration.subcommands
      .map { $0._commandName }
      .joined(separator: " ")

    let broken = """
      _asc_help() {
          :
      }
      """

    let fixed = """
      _asc_help() {
          COMPREPLY+=($(compgen -W '\(subcommands)' -- "${cur}"))
      }
      """

    return script.replacingOccurrences(of: broken, with: fixed)
  }

  /// Fixes `_files -g` in subcommand completion functions.
  /// ArgumentParser's generated zsh completions set `extendedglob` + `nullglob` which breaks
  /// `_files -g` pattern filtering (the internal `pattern:tag` format conflicts with extendedglob).
  /// This adds a wrapper function that uses `zstyle file-patterns` instead of `-g`, which works
  /// correctly regardless of shell options, and replaces all `_files -g` calls with the wrapper.
  private func patchFileCompletions(_ script: String) -> String {
    // Wrapper function: converts -g args to zstyle file-patterns before calling _files
    let wrapper = """
    _asc_files() {
        local -a pats rest
        while (( $# )); do
            if [[ "$1" = -g ]]; then
                shift
                pats+=( "${1}:globbed-files" )
                shift
            else
                rest+=( "$1" )
                shift
            fi
        done
        if (( ${#pats} )); then
            pats+=( '*(-/):directories' )
            zstyle ':completion:*' file-patterns "${pats[@]}"
            _files "${rest[@]}"
            zstyle -d ':completion:*' file-patterns
        else
            _files "${rest[@]}"
        fi
    }

    """

    // Insert wrapper after the #compdef line (and any version stamp)
    var result = script
    if let range = result.range(of: "#compdef asc\n") {
      var insertPoint = range.upperBound
      // Skip past version stamp line if present
      if result[insertPoint...].hasPrefix("# asc v") {
        if let eol = result[insertPoint...].firstIndex(of: "\n") {
          insertPoint = result.index(after: eol)
        }
      }
      result.insert(contentsOf: "\n\(wrapper)", at: insertPoint)
    }

    // Replace _files with _asc_files wherever -g is used
    // Handle both single-extension and multi-extension (space-separated) patterns
    result = result.replacingOccurrences(of: "_files -g ", with: "_asc_files -g ")

    return result
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
