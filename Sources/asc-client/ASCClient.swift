import ArgumentParser

@main
struct ASCClient: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "asc-client",
    abstract: "A command-line tool for the App Store Connect API.",
    version: "0.1.0",
    subcommands: [ConfigureCommand.self, AppsCommand.self, BuildsCommand.self]
  )
}
