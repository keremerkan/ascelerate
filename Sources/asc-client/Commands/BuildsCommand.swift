import AppStoreAPI
import AppStoreConnect
import ArgumentParser
import Foundation

struct BuildsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "builds",
    abstract: "Manage builds.",
    subcommands: [List.self]
  )

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List builds."
    )

    @Option(name: .long, help: "Filter by bundle identifier.")
    var bundleID: String?

    func run() async throws {
      let client = try ClientFactory.makeClient()

      var filterApp: [String]?
      if let bundleID {
        let app = try await findApp(bundleID: bundleID, client: client)
        filterApp = [app.id]
      }

      var allBuilds: [(String, String, String)] = []

      let request = Resources.v1.builds.get(
        filterApp: filterApp,
        sort: [.minusUploadedDate]
      )

      for try await page in client.pages(request) {
        for build in page.data {
          let version = build.attributes?.version ?? "—"
          let state = build.attributes?.processingState
            .map { "\($0)" } ?? "—"
          let uploaded = build.attributes?.uploadedDate
            .map { formatDate($0) } ?? "—"
          allBuilds.append((version, state, uploaded))
        }
      }

      Table.print(
        headers: ["Version", "State", "Uploaded"],
        rows: allBuilds.map { [$0.0, $0.1, $0.2] }
      )
    }
  }
}
