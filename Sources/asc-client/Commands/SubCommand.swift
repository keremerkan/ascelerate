import AppStoreAPI
import AppStoreConnect
import ArgumentParser
import Foundation

struct SubCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "sub",
    abstract: "View subscriptions.",
    subcommands: [Groups.self, List.self, Info.self]
  )

  private static func fetchGroups(
    appID: String, client: AppStoreConnectClient
  ) async throws -> [(name: String, subscriptions: [Subscription])] {
    var result: [(name: String, subscriptions: [Subscription])] = []
    let request = Resources.v1.apps.id(appID).subscriptionGroups.get(
      include: [.subscriptions],
      limitSubscriptions: 50
    )
    for try await page in client.pages(request) {
      var subsByID: [String: Subscription] = [:]
      for item in page.included ?? [] {
        if case .subscription(let sub) = item {
          subsByID[sub.id] = sub
        }
      }
      for group in page.data {
        let name = group.attributes?.referenceName ?? "—"
        let subIDs = group.relationships?.subscriptions?.data?.map(\.id) ?? []
        let subs = subIDs.compactMap { subsByID[$0] }
        result.append((name: name, subscriptions: subs))
      }
    }
    return result
  }

  struct Groups: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List subscription groups with their subscriptions."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let groups = try await SubCommand.fetchGroups(appID: app.id, client: client)

      if groups.isEmpty {
        print("No subscription groups found.")
        return
      }

      for group in groups {
        let sorted = group.subscriptions.sorted { ($0.attributes?.groupLevel ?? 0) < ($1.attributes?.groupLevel ?? 0) }
        print("\(group.name) (\(sorted.count) subscription\(sorted.count == 1 ? "" : "s"))")

        if sorted.isEmpty {
          print("  (no subscriptions)")
        } else {
          Table.print(
            headers: ["Name", "Product ID", "Period", "State", "Level", "Family"],
            rows: sorted.map { sub in
              let attrs = sub.attributes
              return [
                attrs?.name ?? "—",
                attrs?.productID ?? "—",
                attrs?.subscriptionPeriod.map { formatState($0) } ?? "—",
                attrs?.state.map { formatState($0) } ?? "—",
                attrs?.groupLevel.map { "\($0)" } ?? "—",
                attrs?.isFamilySharable == true ? "Yes" : "No",
              ]
            }
          )
        }
        print()
      }
    }
  }

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List all subscriptions across groups."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let groups = try await SubCommand.fetchGroups(appID: app.id, client: client)

      var rows: [[String]] = []
      for group in groups {
        for sub in group.subscriptions.sorted(by: { ($0.attributes?.groupLevel ?? 0) < ($1.attributes?.groupLevel ?? 0) }) {
          let attrs = sub.attributes
          rows.append([
            group.name,
            attrs?.name ?? "—",
            attrs?.productID ?? "—",
            attrs?.subscriptionPeriod.map { formatState($0) } ?? "—",
            attrs?.state.map { formatState($0) } ?? "—",
            attrs?.groupLevel.map { "\($0)" } ?? "—",
          ])
        }
      }

      if rows.isEmpty {
        print("No subscriptions found.")
      } else {
        Table.print(
          headers: ["Group", "Name", "Product ID", "Period", "State", "Level"],
          rows: rows
        )
      }
    }
  }

  struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Show details for a subscription."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Argument(help: "The product identifier of the subscription.")
    var productID: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let groups = try await SubCommand.fetchGroups(appID: app.id, client: client)

      // Find the subscription by product ID
      var foundSub: Subscription?
      var foundGroupName: String?
      for group in groups {
        if let match = group.subscriptions.first(where: { $0.attributes?.productID == productID }) {
          foundSub = match
          foundGroupName = group.name
          break
        }
      }

      guard let sub = foundSub else {
        throw ValidationError("No subscription found with product ID '\(productID)'.")
      }

      // Fetch full details with localizations
      let detailResponse = try await client.send(
        Resources.v1.subscriptions.id(sub.id).get(
          include: [.subscriptionLocalizations],
          limitSubscriptionLocalizations: 50
        )
      )
      let detail = detailResponse.data
      let attrs = detail.attributes

      print("Name:             \(attrs?.name ?? "—")")
      print("Product ID:       \(attrs?.productID ?? "—")")
      print("Group:            \(foundGroupName ?? "—")")
      print("Period:           \(attrs?.subscriptionPeriod.map { formatState($0) } ?? "—")")
      print("State:            \(attrs?.state.map { formatState($0) } ?? "—")")
      print("Group Level:      \(attrs?.groupLevel.map { "\($0)" } ?? "—")")
      print("Family Shareable: \(attrs?.isFamilySharable == true ? "Yes" : "No")")
      print("Review Note:      \(attrs?.reviewNote ?? "—")")

      // Extract localizations from included items
      let locIDs = Set(
        detail.relationships?.subscriptionLocalizations?.data?.map(\.id) ?? []
      )
      let localizations: [SubscriptionLocalization] = (detailResponse.included ?? []).compactMap {
        if case .subscriptionLocalization(let loc) = $0,
           locIDs.isEmpty || locIDs.contains(loc.id) {
          return loc
        }
        return nil
      }

      if !localizations.isEmpty {
        print()
        print("Localizations:")
        for loc in localizations.sorted(by: { ($0.attributes?.locale ?? "") < ($1.attributes?.locale ?? "") }) {
          let locale = loc.attributes?.locale ?? "?"
          let name = loc.attributes?.name ?? "—"
          let desc = loc.attributes?.description ?? "—"
          print("  [\(localeName(locale))] \(name) — \(desc)")
        }
      }
    }
  }
}
