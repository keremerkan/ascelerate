import ArgumentParser
import ASCKit
import Foundation

@main
struct Ascelerate: AsyncParsableCommand {
  static let appVersion = "0.22.0"

  static let configuration = CommandConfiguration(
    commandName: "ascelerate",
    abstract: "A Swift CLI for App Store Connect.",
    discussion: """
      Global option: --dry-run (anywhere on the command line, or ASCELERATE_DRY_RUN=1) sends \
      reads as usual but prints every write instead of sending it.
      """,
    subcommands: [AppsCommand.self, AppEventsCommand.self, BuildsCommand.self, CustomerReviewsCommand.self, ProductPagesCommand.self, ScreenshotCommand.self, TestFlightCommand.self],
    groupedSubcommands: [
      CommandGroup(name: "Monetization", subcommands: [IAPCommand.self, SubCommand.self]),
      CommandGroup(name: "Reporting", subcommands: [ReportsCommand.self]),
      CommandGroup(name: "Provisioning", subcommands: [BundleIDsCommand.self, CertsCommand.self, DevicesCommand.self, ProfilesCommand.self]),
      CommandGroup(name: "Utilities", subcommands: [AliasCommand.self, RunWorkflowCommand.self, RateLimitCommand.self, VersionCommand.self]),
      CommandGroup(name: "Setup", subcommands: [ConfigureCommand.self, InstallCompletionsCommand.self, InstallSkillCommand.self]),
    ]
  )

  func run() async throws {
    print("ascelerate \(Self.appVersion)")
    let prompted = await checkForUpdatesInteractively()
    if prompted { print() }
    print(Self.boldHelpHeaders(Self.helpMessage()))
  }

  static func main() async {
    // Ignore SIGPIPE so a downstream reader that closes the pipe early (e.g. `ascelerate ... | head`)
    // can't terminate us mid-operation — which for write commands could leave changes half-applied.
    // Writes to the broken stdout then fail silently instead of killing the process.
    signal(SIGPIPE, SIG_IGN)

    // Catch --version before ArgumentParser rejects it as unknown flag
    let args = extractDryRunFlag(Array(CommandLine.arguments.dropFirst()))
    if args == ["--version"] || args == ["-v"] {
      print(appVersion)
      return
    }

    do {
      var command = try parseAsRoot(args)
      if var asyncCommand = command as? AsyncParsableCommand {
        try await asyncCommand.run()
      } else {
        try command.run()
      }
    } catch {
      // Bold section headers in help output
      let message = fullMessage(for: error)
      if exitCode(for: error) == .success, !message.isEmpty {
        print(boldHelpHeaders(message))
        return
      }
      if let formatted = formatError(error) {
        FileHandle.standardError.write(Data((formatted + "\n").utf8))
        exit(withError: ExitCode.failure)
      }
      exit(withError: error)
    }
  }

  struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "version",
      abstract: "Print the version number."
    )

    func run() {
      print(Ascelerate.appVersion)
    }
  }

  static func boldHelpHeaders(_ text: String) -> String {
    guard isatty(STDOUT_FILENO) != 0 else { return text }
    return text.replacingOccurrences(
      of: #"(?m)^([A-Z][A-Z &]+(?:SUBCOMMANDS)?:)"#,
      with: "\u{1B}[1m$1\u{1B}[0m",
      options: .regularExpression
    )
  }

  private static func formatError(_ error: Error) -> String? {
    if let stop = ASCDryRunStop.from(error) {
      return yellow(stop.description)
    }
    if let ascError = ASCError.from(error) {
      return ascError.statusCode == 429
        ? formatRateLimit(ascError.rateLimit)
        : formatRequestFailure(statusCode: ascError.statusCode, errors: ascError.errors.map { ($0.title, $0.detail) })
    }
    let wrapped = ascUnderlyingError(error)
    let underlying = wrapped ?? error
    if let urlError = underlying as? URLError {
      return formatURLError(urlError)
    }
    if underlying is DecodingError {
      return "\(stderrRed("Error:")) Unexpected response from App Store Connect API: \(underlying)"
    }
    // Any other failure the runtime wrapped: report the cause, not the wrapper's request dump.
    if let wrapped {
      return "\(stderrRed("Error:")) \(wrapped.localizedDescription)"
    }
    return nil
  }

  private static func formatRateLimit(_ rate: (limit: Int, remaining: Int)?) -> String {
    var msg = "\(stderrRed("Error:")) App Store Connect API rate limit exceeded (HTTP 429)."
    if let rate {
      msg += "\n  Hourly limit: \(rate.limit) requests"
      msg += "\n  Remaining:    \(rate.remaining) requests"
    }
    msg += "\n  Wait a few minutes before retrying."
    return msg
  }

  private static func formatRequestFailure(statusCode: Int, errors: [(title: String, detail: String)]) -> String {
    var msg = "\(stderrRed("Error:")) App Store Connect API returned HTTP \(statusCode)."
    for e in errors {
      msg += "\n  \(e.title): \(e.detail)"
    }
    if statusCode == 401 {
      msg += "\n  Check your API credentials (run 'ascelerate configure')."
    } else if statusCode == 403 {
      msg += "\n  Your API key may lack the required permissions."
    } else if statusCode >= 500 {
      msg += "\n  This is a server-side issue. Try again later."
    }
    return msg
  }

  private static func formatURLError(_ error: URLError) -> String {
    let tag = stderrRed("Error:")
    switch error.code {
    case .notConnectedToInternet:
      return "\(tag) No internet connection."
    case .timedOut:
      return "\(tag) Request timed out. Check your connection and try again."
    case .cannotFindHost, .dnsLookupFailed:
      return "\(tag) Could not reach App Store Connect API (DNS lookup failed)."
    case .cannotConnectToHost:
      return "\(tag) Could not connect to App Store Connect API."
    case .networkConnectionLost:
      return "\(tag) Network connection was lost during the request. Try again."
    case .secureConnectionFailed:
      return "\(tag) Secure connection failed. Check your network settings."
    default:
      return "\(tag) Network error — \(error.localizedDescription)"
    }
  }
}
