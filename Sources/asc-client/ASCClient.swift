import ArgumentParser

@main
struct ASCClient: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "asc-client",
    abstract: "A command-line tool for the App Store Connect API.",
    version: "0.3.0",
    subcommands: [ConfigureCommand.self, AppsCommand.self, BuildsCommand.self, IAPCommand.self, SubCommand.self, RunWorkflowCommand.self, InstallCompletionsCommand.self]
  )

  func run() async throws {
    print("asc-client \(Self.configuration.version)")
    print(Self.helpMessage())
  }
}
