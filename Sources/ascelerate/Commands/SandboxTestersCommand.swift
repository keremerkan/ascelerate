import ArgumentParser
import AscelerateCore
import Foundation

struct SandboxTestersCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "sandbox-testers",
    abstract: "Sandbox testers: storefront, interrupted purchases, renewal rate, purchase history.",
    discussion: """
      The Apple Accounts that buy in-app purchases and subscriptions in the sandbox. A tester is \
      named by its Apple Account (email) or ID. Creating and deleting testers is done in App Store \
      Connect (Users and Access > Sandbox); the API doesn't offer it.
      """,
    subcommands: [List.self, Update.self, ClearHistory.self],
    defaultSubcommand: List.self
  )

  /// The renewal rates by their short names, fastest last.
  static let rates: [(short: String, raw: String)] = [
    ("1h", "MONTHLY_RENEWAL_EVERY_ONE_HOUR"), ("30m", "MONTHLY_RENEWAL_EVERY_THIRTY_MINUTES"),
    ("15m", "MONTHLY_RENEWAL_EVERY_FIFTEEN_MINUTES"), ("5m", "MONTHLY_RENEWAL_EVERY_FIVE_MINUTES"),
    ("3m", "MONTHLY_RENEWAL_EVERY_THREE_MINUTES"),
  ]

  /// "every 5 minutes": how often a monthly subscription renews.
  static func rate(_ raw: String?) -> String {
    switch raw {
      case "MONTHLY_RENEWAL_EVERY_ONE_HOUR": "every hour"
      case "MONTHLY_RENEWAL_EVERY_THIRTY_MINUTES": "every 30 minutes"
      case "MONTHLY_RENEWAL_EVERY_FIFTEEN_MINUTES": "every 15 minutes"
      case "MONTHLY_RENEWAL_EVERY_FIVE_MINUTES": "every 5 minutes"
      case "MONTHLY_RENEWAL_EVERY_THREE_MINUTES": "every 3 minutes"
      case let raw?: formatState(raw)
      case nil: "-"
    }
  }

  static func yesNo(_ value: Bool?) -> String {
    value.map { $0 ? "Yes" : "No" } ?? "-"
  }

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the team's sandbox testers.")

    @OptionGroup var jsonOption: JSONOption

    func run() async throws {
      jsonOption.activate()
      let testers = try await SandboxTesters.list(client: ClientFactory.makeClient())
      if jsonOption.json { try printJSON(testers); return }
      guard !testers.isEmpty else {
        print("No sandbox testers. Add them in App Store Connect: Users and Access > Sandbox.")
        return
      }
      Table.print(
        headers: ["Apple Account", "Name", "Storefront", "Renews", "Interrupts Purchases", "Apple Pay"],
        rows: testers.map { t in
          [
            t.account ?? "-", t.name.isEmpty ? "-" : t.name, t.territory ?? "-", SandboxTestersCommand.rate(t.renewalRate),
            SandboxTestersCommand.yesNo(t.interruptPurchases), SandboxTestersCommand.yesNo(t.applePayCompatible),
          ]
        })
    }
  }

  struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Change a sandbox tester's storefront, interrupted purchases or renewal rate.",
      discussion: """
        --renewal-rate sets how fast a monthly subscription renews for the tester: 1h, 30m, 15m, \
        5m or 3m (yearly and other durations renew in proportion).
        """
    )

    @Argument(help: "The tester's Apple Account (email) or ID.")
    var tester: String

    @Option(name: .long, help: "The storefront, as a territory code (USA, TUR, DEU).")
    var territory: String?

    @Option(name: .long, help: "Stop purchases for an extra step (payment, terms): true or false.")
    var interruptPurchases: Bool?

    @Option(name: .long, help: "How fast a monthly subscription renews: 1h, 30m, 15m, 5m or 3m.")
    var renewalRate: String?

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      guard territory != nil || interruptPurchases != nil || renewalRate != nil else {
        throw ValidationError("Give --territory, --interrupt-purchases or --renewal-rate.")
      }
      let rate = try renewalRate.map { value in
        guard let match = SandboxTestersCommand.rates.first(where: { $0.short == value.lowercased() || $0.raw == value.uppercased() }) else {
          throw ValidationError("No renewal rate '\(value)'. Rates: \(SandboxTestersCommand.rates.map(\.short).joined(separator: ", ")).")
        }
        return match.raw
      }
      let territory = territory?.uppercased()
      if let territory, territory.count != 3 || !territory.allSatisfy(\.isLetter) {
        throw ValidationError("A storefront is a three-letter territory code, like USA or TUR.")
      }
      let client = try ClientFactory.makeClient()
      let current = try SandboxTesters.find(tester, in: try await SandboxTesters.list(client: client))
      var lines: [String] = []
      if let territory, territory != current.territory { lines.append("Storefront: \(current.territory ?? "-") → \(territory)") }
      if let interruptPurchases, interruptPurchases != current.interruptPurchases {
        lines.append("Interrupts purchases: \(SandboxTestersCommand.yesNo(current.interruptPurchases)) → \(SandboxTestersCommand.yesNo(interruptPurchases))")
      }
      if let rate, rate != current.renewalRate {
        lines.append("Renews: \(SandboxTestersCommand.rate(current.renewalRate)) → \(SandboxTestersCommand.rate(rate))")
      }
      guard !lines.isEmpty else {
        print("Nothing to change.")
        return
      }
      print("Sandbox tester \(current.account ?? current.id):")
      for line in lines { print("  \(line)") }
      guard confirm("Save? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      _ = try await SandboxTesters.update(
        id: current.id, territory: territory == current.territory ? nil : territory,
        interruptPurchases: interruptPurchases == current.interruptPurchases ? nil : interruptPurchases,
        renewalRate: rate == current.renewalRate ? nil : rate, client: client)
      print(green("Updated") + " \(current.account ?? current.id).")
    }
  }

  struct ClearHistory: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "clear-history",
      abstract: "Clear sandbox testers' purchase history, so their purchases can be made again from the start."
    )

    @Argument(help: "The testers' Apple Accounts (emails) or IDs.")
    var testers: [String] = []

    @Flag(name: .long, help: "Every sandbox tester of the team.")
    var all = false

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      guard all != !testers.isEmpty else { throw ValidationError("Name the testers, or pass --all.") }
      let client = try ClientFactory.makeClient()
      let everyone = try await SandboxTesters.list(client: client)
      let chosen = all ? everyone : try testers.map { try SandboxTesters.find($0, in: everyone) }
      guard !chosen.isEmpty else {
        print("No sandbox testers.")
        return
      }
      print("Clear the purchase history of:")
      for tester in chosen { print("  \(tester.account ?? tester.id)") }
      print("Their in-app purchases and subscriptions are forgotten, and can be bought again.")
      guard confirm("Clear? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      try await SandboxTesters.clearPurchaseHistory(testerIDs: chosen.map(\.id), client: client)
      print(green("Cleared") + " the purchase history of \(chosen.count == 1 ? "1 tester" : "\(chosen.count) testers").")
    }
  }
}
