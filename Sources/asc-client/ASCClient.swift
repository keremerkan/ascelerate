import AppStoreConnect
import ArgumentParser
import Foundation

@main
struct ASCClient: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "asc-client",
    abstract: "A command-line tool for the App Store Connect API.",
    version: "0.3.0",
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
      if let responseError = error as? ResponseError,
         case .rateLimitExceeded(_, let rate, _) = responseError {
        var message = "Error: App Store Connect API rate limit exceeded (HTTP 429)."
        if let rate {
          message += "\n  Hourly limit: \(rate.limit) requests"
          message += "\n  Remaining:    \(rate.remaining) requests"
        }
        message += "\n  Wait a few minutes before retrying."
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(withError: ExitCode.failure)
      }
      exit(withError: error)
    }
  }
}
