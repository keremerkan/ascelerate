import AppStoreConnect
import ArgumentParser
import Foundation

@main
struct ASC: AsyncParsableCommand {
  static let appVersion = "0.7.2"

  static let configuration = CommandConfiguration(
    commandName: "asc",
    abstract: "A Swift CLI for App Store Connect.",
    subcommands: [AppsCommand.self, BuildsCommand.self],
    groupedSubcommands: [
      CommandGroup(name: "Monetization", subcommands: [IAPCommand.self, SubCommand.self]),
      CommandGroup(name: "Provisioning", subcommands: [BundleIDsCommand.self, CertsCommand.self, DevicesCommand.self, ProfilesCommand.self]),
      CommandGroup(name: "Utilities", subcommands: [AliasCommand.self, RunWorkflowCommand.self, RateLimitCommand.self, VersionCommand.self]),
      CommandGroup(name: "Setup", subcommands: [ConfigureCommand.self, InstallCompletionsCommand.self, InstallSkillCommand.self]),
    ]
  )

  func run() async throws {
    migrateFromLegacyName()
    print("asc \(Self.appVersion)")
    let prompted = await checkForUpdatesInteractively()
    if prompted { print() }
    print(Self.boldHelpHeaders(Self.helpMessage()))
  }

  static func main() async {
    // Catch --version before ArgumentParser rejects it as unknown flag
    let args = Array(CommandLine.arguments.dropFirst())
    if args == ["--version"] || args == ["-v"] {
      print(appVersion)
      return
    }

    do {
      var command = try parseAsRoot()
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
      print(ASC.appVersion)
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
    if let responseError = error as? ResponseError {
      return formatResponseError(responseError)
    }
    if let urlError = error as? URLError {
      return formatURLError(urlError)
    }
    return nil
  }

  private static func formatResponseError(_ error: ResponseError) -> String {
    let tag = stderrRed("Error:")
    switch error {
    case .rateLimitExceeded(_, let rate, _):
      var msg = "\(tag) App Store Connect API rate limit exceeded (HTTP 429)."
      if let rate {
        msg += "\n  Hourly limit: \(rate.limit) requests"
        msg += "\n  Remaining:    \(rate.remaining) requests"
      }
      msg += "\n  Wait a few minutes before retrying."
      return msg

    case .requestFailure(let errorResponse, let statusCode, _):
      var msg = "\(tag) App Store Connect API returned HTTP \(statusCode)."
      if let errors = errorResponse?.errors {
        for e in errors {
          msg += "\n  \(e.title): \(e.detail)"
        }
      }
      if statusCode == 401 {
        msg += "\n  Check your API credentials (run 'asc configure')."
      } else if statusCode == 403 {
        msg += "\n  Your API key may lack the required permissions."
      } else if statusCode >= 500 {
        msg += "\n  This is a server-side issue. Try again later."
      }
      return msg

    case .dataAssertionFailed:
      return "\(tag) Unexpected empty response from App Store Connect API."
    }
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
