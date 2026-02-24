import AppStoreConnect
import ArgumentParser
import Foundation

@main
struct ASCClient: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "asc-client",
    abstract: "A command-line tool for the App Store Connect API.",
    version: "0.3.1",
    subcommands: [ConfigureCommand.self, AppsCommand.self, BuildsCommand.self, IAPCommand.self, SubCommand.self, RunWorkflowCommand.self, InstallCompletionsCommand.self, RateLimitCommand.self]
  )

  func run() async throws {
    print("asc-client \(Self.configuration.version)")
    checkCompletionsVersion()
    print(Self.helpMessage())
  }

  static func main() async {
    do {
      var command = try parseAsRoot()
      if var asyncCommand = command as? AsyncParsableCommand {
        try await asyncCommand.run()
      } else {
        try command.run()
      }
    } catch {
      if let message = formatError(error) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(withError: ExitCode.failure)
      }
      exit(withError: error)
    }
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
    switch error {
    case .rateLimitExceeded(_, let rate, _):
      var msg = "Error: App Store Connect API rate limit exceeded (HTTP 429)."
      if let rate {
        msg += "\n  Hourly limit: \(rate.limit) requests"
        msg += "\n  Remaining:    \(rate.remaining) requests"
      }
      msg += "\n  Wait a few minutes before retrying."
      return msg

    case .requestFailure(let errorResponse, let statusCode, _):
      var msg = "Error: App Store Connect API returned HTTP \(statusCode)."
      if let errors = errorResponse?.errors {
        for e in errors {
          msg += "\n  \(e.title): \(e.detail)"
        }
      }
      if statusCode == 401 {
        msg += "\n  Check your API credentials (run 'asc-client configure')."
      } else if statusCode == 403 {
        msg += "\n  Your API key may lack the required permissions."
      } else if statusCode >= 500 {
        msg += "\n  This is a server-side issue. Try again later."
      }
      return msg

    case .dataAssertionFailed:
      return "Error: Unexpected empty response from App Store Connect API."
    }
  }

  private static func formatURLError(_ error: URLError) -> String {
    switch error.code {
    case .notConnectedToInternet:
      return "Error: No internet connection."
    case .timedOut:
      return "Error: Request timed out. Check your connection and try again."
    case .cannotFindHost, .dnsLookupFailed:
      return "Error: Could not reach App Store Connect API (DNS lookup failed)."
    case .cannotConnectToHost:
      return "Error: Could not connect to App Store Connect API."
    case .networkConnectionLost:
      return "Error: Network connection was lost during the request. Try again."
    case .secureConnectionFailed:
      return "Error: Secure connection failed. Check your network settings."
    default:
      return "Error: Network error — \(error.localizedDescription)"
    }
  }
}
