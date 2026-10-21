import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

extension AppPricing.PricePoint: ResolvablePricePoint {
  var resolverCustomerPrice: String? { customerPrice }
}

extension AppsCommand {
  /// The app's own price: its base territory and price, prices set by hand, planned and temporary
  /// changes, and Apple's prices everywhere else.
  struct PricingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "pricing",
      abstract: "View or change the app's price schedule.",
      discussion: """
        An app's price is set in a base territory; Apple derives comparable prices for the other
        territories and may adjust them for tax and exchange rate changes. A price set by hand in a
        territory stays as it is. Changes can start on a later date, and a temporary change (a sale)
        ends on one. Every change sends the whole schedule again.
        """,
      subcommands: [Show.self, Tiers.self, Set.self, Override.self, Keep.self, Remove.self, Sale.self, Cancel.self, Export.self, Import.self],
      defaultSubcommand: Show.self
    )

    // MARK: Shared

    /// The app with its price schedule (nil when it has none yet).
    static func load(_ bundleID: String, client: ASCClient) async throws -> (app: Components.Schemas.App, schedule: AppPricing.Schedule?) {
      let app = try await findApp(bundleID: bundleID, client: client)
      return (app, try await AppPricing.schedule(appID: app.id, client: client))
    }

    static func requireSchedule(_ schedule: AppPricing.Schedule?) throws -> AppPricing.Schedule {
      guard let schedule else {
        throw ValidationError("The app has no price yet. Set one with 'ascelerate apps pricing set'.")
      }
      return schedule
    }

    /// A territory's tier with that customer price.
    static func resolve(price: String, territoryID: String, appID: String, client: ASCClient) async throws -> AppPricing.PricePoint {
      let tiers = try await AppPricing.pricePoints(appID: appID, territoryID: territoryID, client: client)
      return try findPricePoint(
        in: tiers, target: try parseCustomerPrice(price), priceLabel: price, territoryID: territoryID, currency: nil)
    }

    /// Territory codes from a comma-separated list, or every territory for `all`.
    static func territories(_ value: String, client: ASCClient) async throws -> Swift.Set<String> {
      let known = Swift.Set(try await AppPricing.currencies(client: client).keys)
      if value.lowercased() == "all" { return known }
      let codes = Swift.Set(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() })
      let unknown = codes.subtracting(known)
      guard unknown.isEmpty else {
        throw ValidationError("Unknown territory codes: \(unknown.sorted().joined(separator: ", ")).")
      }
      return codes
    }

    /// A day after today (yyyy-MM-dd): price changes can't start in the past.
    static func laterDay(_ value: String, option: String) throws -> String {
      guard value.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil else {
        throw ValidationError("\(option) must be a date in YYYY-MM-DD format.")
      }
      guard value > AppPricing.today else {
        throw ValidationError("\(option) must be after today (\(AppPricing.today), UTC).")
      }
      return value
    }

    static func describe(_ point: AppPricing.PricePoint, currency: String?) -> String {
      "\(point.customerPrice) \(currency ?? "")".trimmingCharacters(in: .whitespaces)
    }

    /// Prints what changes, asks, and sends the schedule.
    static func save(
      appID: String, appName: String, base: String, prices: [AppPricing.NewPrice], summary: [String], client: ASCClient
    ) async throws {
      print("Change the price schedule of \(appName):")
      for line in summary { print("  \(line)") }
      print()
      guard confirm("Apply? [y/N] ") else {
        cancelled()
        return
      }
      try await AppPricing.setSchedule(appID: appID, baseTerritoryID: base, manualPrices: prices, client: client)
      success("Updated", "the price schedule of \(appName).")
    }

    // MARK: Show

    struct Show: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Show the base price, prices set by hand and planned changes.")

      @Argument(help: "Bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Flag(name: .long, help: "Also list Apple's prices in every other territory.")
      var all = false

      @OptionGroup var jsonOption: JSONOption

      private struct Entry: Encodable {
        let territory: String
        let price: String
        let proceeds: String
        let currency: String?
        let manual: Bool
        let startDate: String?
        let endDate: String?
      }

      private struct Result: Encodable {
        let baseTerritory: String?
        let prices: [Entry]
      }

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let (_, schedule) = try await PricingCommand.load(bundleID, client: client)
        guard let schedule else {
          if jsonOption.json { try printJSON(Result(baseTerritory: nil, prices: [])); return }
          print("The app has no price yet. Set one with 'ascelerate apps pricing set'.")
          return
        }
        let today = AppPricing.today
        let current = schedule.manualPrices.filter { $0.applies(on: today) }
        let manualTerritories = Swift.Set(current.map(\.territoryID))
        let automatic = schedule.automaticPrices.filter { $0.applies(on: today) && !manualTerritories.contains($0.territoryID) }
        let planned = schedule.manualPrices.filter { ($0.startDate ?? "") > today }
          .sorted { ($0.startDate ?? "", $0.territoryID) < ($1.startDate ?? "", $1.territoryID) }

        if jsonOption.json {
          let entries = (schedule.manualPrices.filter(\.isCurrentOrLater) + automatic).map {
            Entry(
              territory: $0.territoryID, price: $0.point.customerPrice, proceeds: $0.point.proceeds,
              currency: schedule.currencies[$0.territoryID], manual: $0.manual, startDate: $0.startDate, endDate: $0.endDate)
          }
          try printJSON(Result(baseTerritory: schedule.baseTerritoryID, prices: entries))
          return
        }

        func price(_ price: AppPricing.Price) -> String {
          PricingCommand.describe(price.point, currency: schedule.currencies[price.territoryID])
        }
        let base = current.first { $0.territoryID == schedule.baseTerritoryID }
        print("Base territory: \(schedule.baseTerritoryID)")
        print("Price:          \(base.map(price) ?? "-")\(base.map { "  (proceeds \($0.point.proceeds))" } ?? "")")
        let byHand = current.filter { $0.territoryID != schedule.baseTerritoryID }.sorted { $0.territoryID < $1.territoryID }
        print("Set by hand:    \(byHand.count) other territor\(byHand.count == 1 ? "y" : "ies")")
        if !byHand.isEmpty && !all {
          print()
          Table.print(headers: ["Territory", "Price", "Proceeds"], rows: byHand.map { [$0.territoryID, price($0), $0.point.proceeds] })
        }
        if !planned.isEmpty {
          print()
          print(bold("Planned changes"))
          Table.print(
            headers: ["Start", "End", "Territory", "Price"],
            rows: planned.map { [$0.startDate ?? "-", $0.endDate ?? "-", $0.territoryID, price($0)] })
        }
        if all {
          print()
          let rows = (current + automatic).sorted {
            ($0.territoryID == schedule.baseTerritoryID ? 0 : 1, $0.territoryID) < ($1.territoryID == schedule.baseTerritoryID ? 0 : 1, $1.territoryID)
          }
          Table.print(
            headers: ["Territory", "Price", "Proceeds", "Set By"],
            rows: rows.map {
              [$0.territoryID, price($0), $0.point.proceeds,
               $0.territoryID == schedule.baseTerritoryID ? "Base" : $0.manual ? "You" : "Apple"]
            })
        }
      }
    }

    // MARK: Tiers

    struct Tiers: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "List a territory's price tiers.")

      @Argument(help: "Bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Territory code (default: USA).")
      var territory: String = "USA"

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let territoryID = territory.uppercased()
        async let tiers = AppPricing.pricePoints(appID: app.id, territoryID: territoryID, client: client)
        async let currencies = AppPricing.currencies(client: client)
        printPriceTiers(
          try await tiers.map { PriceTier(id: $0.id, customerPrice: $0.customerPrice, proceeds: $0.proceeds) },
          currency: try await currencies[territoryID], territoryID: territoryID)
      }
    }

    // MARK: Set

    struct Set: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Set the base price, now or from a date.",
        discussion: """
          Apple derives the other territories' prices from the base price. Prices set by hand in
          other territories stay unless --drop-manual. With --start-date the current price applies
          until that day; a new base territory always applies now.
          """)

      @Argument(help: "Bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Customer price in the base territory's currency (e.g. 0.99; 0 for free).")
      var price: String

      @Option(name: .customLong("base-territory"), help: "Base territory code (default: the current one, or USA).")
      var baseTerritory: String?

      @Option(name: .long, help: "The day the price starts (YYYY-MM-DD, after today; default: now).")
      var startDate: String?

      @Flag(name: .customLong("drop-manual"), help: "Give the other territories' prices set by hand back to Apple.")
      var dropManual = false

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (app, schedule) = try await PricingCommand.load(bundleID, client: client)
        let base = (baseTerritory ?? schedule?.baseTerritoryID ?? "USA").uppercased()
        let day = try startDate.map { try PricingCommand.laterDay($0, option: "--start-date") }
        if day != nil, schedule.map({ $0.baseTerritoryID != base }) ?? true {
          throw ValidationError(schedule == nil
            ? "The app's first price applies now; leave out --start-date."
            : "A new base territory applies now; leave out --start-date.")
        }
        let point = try await PricingCommand.resolve(price: price, territoryID: base, appID: app.id, client: client)
        let currency = try await AppPricing.currencies(client: client)[base]
        let prices = schedule?.changingBase(to: base, pricePointID: point.id, from: day, keepingOthers: !dropManual)
          ?? [AppPricing.NewPrice(pricePointID: point.id)]
        var summary = [
          "Base territory: \(base)", "Price:          \(PricingCommand.describe(point, currency: currency))",
          "Starts:         \(day ?? "now")",
        ]
        if let old = schedule?.baseTerritoryID, old != base { summary.append("Old base:       \(old) (Apple's price from now on)") }
        if dropManual { summary.append("Prices set by hand in other territories go back to Apple's.") }
        try await PricingCommand.save(
          appID: app.id, appName: app.attributes?.name ?? bundleID, base: base, prices: prices, summary: summary, client: client)
      }
    }

    // MARK: Override

    struct Override: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Set a territory's price by hand (from now on).",
        discussion: "Apple doesn't adjust a price set by hand. 'apps pricing remove' gives it back to Apple.")

      @Argument(help: "Bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Territory code (e.g. FRA).")
      var territory: String

      @Option(name: .long, help: "Customer price in the territory's currency.")
      var price: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (app, loaded) = try await PricingCommand.load(bundleID, client: client)
        let schedule = try PricingCommand.requireSchedule(loaded)
        let territoryID = territory.uppercased()
        guard territoryID != schedule.baseTerritoryID else {
          throw ValidationError("\(territoryID) is the base territory; change its price with 'ascelerate apps pricing set'.")
        }
        let point = try await PricingCommand.resolve(price: price, territoryID: territoryID, appID: app.id, client: client)
        let currency = try await AppPricing.currencies(client: client)[territoryID]
        try await PricingCommand.save(
          appID: app.id, appName: app.attributes?.name ?? bundleID, base: schedule.baseTerritoryID,
          prices: schedule.settingManual(territoryID: territoryID, pricePointID: point.id),
          summary: ["\(territoryID): \(PricingCommand.describe(point, currency: currency)), set by hand"], client: client)
      }
    }

    // MARK: Keep

    struct Keep: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Keep territories' current prices by hand, so Apple no longer adjusts them.",
        discussion: "App Store Connect's \"manually manage prices\". Territories already priced by hand stay as they are.")

      @Argument(help: "Bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Comma-separated territory codes, or 'all'.")
      var territories: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (app, loaded) = try await PricingCommand.load(bundleID, client: client)
        let schedule = try PricingCommand.requireSchedule(loaded)
        let chosen = try await PricingCommand.territories(territories, client: client)
        let today = AppPricing.today
        let byApple = schedule.automaticPrices.filter { $0.applies(on: today) && chosen.contains($0.territoryID) }
          .map(\.territoryID)
        let byHand = Swift.Set(schedule.manualPrices.filter { $0.applies(on: today) }.map(\.territoryID))
        let kept = byApple.filter { !byHand.contains($0) }
        guard !kept.isEmpty else {
          print("Those territories' prices are already set by hand.")
          return
        }
        try await PricingCommand.save(
          appID: app.id, appName: app.attributes?.name ?? bundleID, base: schedule.baseTerritoryID,
          prices: schedule.keepingCurrent(territoryIDs: Swift.Set(kept)),
          summary: ["Keep the current prices by hand in \(kept.count) territor\(kept.count == 1 ? "y" : "ies"): \(kept.count <= 10 ? kept.sorted().joined(separator: ", ") : "")"],
          client: client)
      }
    }

    // MARK: Remove

    struct Remove: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Give territories' prices set by hand back to Apple.",
        discussion: "The base territory's price stays; change it with 'apps pricing set'.")

      @Argument(help: "Bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Comma-separated territory codes, or 'all'.")
      var territories: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (app, loaded) = try await PricingCommand.load(bundleID, client: client)
        let schedule = try PricingCommand.requireSchedule(loaded)
        let chosen = try await PricingCommand.territories(territories, client: client)
        let removed = Swift.Set(schedule.manualPrices.filter(\.isCurrentOrLater).map(\.territoryID))
          .intersection(chosen).subtracting([schedule.baseTerritoryID])
        guard !removed.isEmpty else {
          print("None of those territories has a price set by hand.")
          return
        }
        try await PricingCommand.save(
          appID: app.id, appName: app.attributes?.name ?? bundleID, base: schedule.baseTerritoryID,
          prices: schedule.removingManual(territoryIDs: removed),
          summary: ["Apple's prices in \(removed.count) territor\(removed.count == 1 ? "y" : "ies"): \(removed.count <= 10 ? removed.sorted().joined(separator: ", ") : "")"],
          client: client)
      }
    }

    // MARK: Sale

    struct Sale: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Change territories' prices temporarily (a sale).",
        discussion: """
          For one territory --price is in its own currency; for several it's in the base territory's,
          and the others get Apple's comparable prices. Afterwards each territory's earlier price
          applies again. Apple doesn't adjust the prices during the change.
          """)

      @Argument(help: "Bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Comma-separated territory codes, or 'all'.")
      var territories: String

      @Option(name: .long, help: "Customer price (see the discussion for the currency).")
      var price: String

      @Option(name: .long, help: "The first day (YYYY-MM-DD, after today).")
      var startDate: String

      @Option(name: .long, help: "The day the earlier prices apply again (YYYY-MM-DD).")
      var endDate: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let start = try PricingCommand.laterDay(startDate, option: "--start-date")
        let end = try PricingCommand.laterDay(endDate, option: "--end-date")
        guard end > start else { throw ValidationError("--end-date must be after --start-date.") }
        let client = try ClientFactory.makeClient()
        let (app, loaded) = try await PricingCommand.load(bundleID, client: client)
        let schedule = try PricingCommand.requireSchedule(loaded)
        let chosen = try await PricingCommand.territories(territories, client: client)
        let pricedIn = chosen.count == 1 ? chosen.first! : schedule.baseTerritoryID
        let point = try await PricingCommand.resolve(price: price, territoryID: pricedIn, appID: app.id, client: client)
        var points: [String: String] = chosen.contains(pricedIn) ? [pricedIn: point.id] : [:]
        if chosen.count > 1 {
          for equalized in try await AppPricing.equalizations(of: point.id, client: client).points where chosen.contains(equalized.territoryID) {
            points[equalized.territoryID] = equalized.id
          }
        }
        let currency = try await AppPricing.currencies(client: client)[pricedIn]
        try await PricingCommand.save(
          appID: app.id, appName: app.attributes?.name ?? bundleID, base: schedule.baseTerritoryID,
          prices: schedule.addingTemporary(pricePointIDs: points, from: start, until: end),
          summary: [
            "Territories: \(points.count <= 10 ? points.keys.sorted().joined(separator: ", ") : "\(points.count)")",
            "Price:       \(PricingCommand.describe(point, currency: currency)) in \(pricedIn)\(chosen.count > 1 ? " (Apple's comparable prices elsewhere)" : "")",
            "From \(start) until \(end)",
          ],
          client: client)
      }
    }

    // MARK: Cancel

    struct Cancel: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Remove a planned price change.",
        discussion: "The price before it goes on until the one after it, or for good.")

      @Argument(help: "Bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Territory code of the planned price.")
      var territory: String

      @Option(name: .long, help: "The day it starts (YYYY-MM-DD), as 'apps pricing show' lists it.")
      var startDate: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (app, loaded) = try await PricingCommand.load(bundleID, client: client)
        let schedule = try PricingCommand.requireSchedule(loaded)
        let territoryID = territory.uppercased()
        guard let planned = schedule.manualPrices.first(where: {
          $0.territoryID == territoryID && $0.startDate == startDate && startDate > AppPricing.today
        }) else {
          throw ValidationError("No planned price in \(territoryID) starting \(startDate). See 'ascelerate apps pricing show'.")
        }
        try await PricingCommand.save(
          appID: app.id, appName: app.attributes?.name ?? bundleID, base: schedule.baseTerritoryID,
          prices: schedule.removingPlanned(planned),
          summary: ["Remove the planned price in \(territoryID) from \(startDate): \(PricingCommand.describe(planned.point, currency: schedule.currencies[territoryID]))"],
          client: client)
      }
    }

    // MARK: Export

    struct Export: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Export the base territory and the current prices set by hand to a JSON file.",
        discussion: "The format of 'iap pricing export'; 'apps pricing import' applies it to this or another app.")

      @Argument(help: "Bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Output file path.", completion: .file(extensions: ["json"]))
      var output: String?

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let (app, loaded) = try await PricingCommand.load(bundleID, client: client)
        let schedule = try PricingCommand.requireSchedule(loaded)
        let today = AppPricing.today
        let prices = Dictionary(
          schedule.manualPrices.filter { $0.applies(on: today) }.map { ($0.territoryID, $0.point.customerPrice) },
          uniquingKeysWith: { first, _ in first })
        try exportProductPrices(
          ProductPricesFile(baseTerritory: schedule.baseTerritoryID, prices: prices),
          productID: app.attributes?.bundleId ?? bundleID, output: output)
      }
    }

    // MARK: Import

    struct Import: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Apply a price file from 'apps pricing export' (or 'iap pricing export').",
        discussion: """
          The base territory and one price set by hand per listed territory, matched to this app's
          tiers by customer price. The schedule is replaced as a whole, from now on: territories not
          in the file get Apple's prices, and planned changes are dropped.
          """)

      @Argument(help: "Bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Option(name: .long, help: "Path to the JSON file.", completion: .file(extensions: ["json"]))
      var file: String?

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let priceFile = try loadProductPricesFile(file)
        let (app, schedule) = try await PricingCommand.load(bundleID, client: client)
        let base = priceFile.baseTerritory ?? schedule?.baseTerritoryID ?? "USA"
        guard let basePrice = priceFile.prices[base] else {
          throw ValidationError("The file has no price for the base territory \(base).")
        }
        let basePoint = try await PricingCommand.resolve(price: basePrice, territoryID: base, appID: app.id, client: client)
        // Territories whose price is Apple's comparable price for the base tier resolve from one
        // request; the rest read their own tier lists (four requests each).
        let equalized = try await AppPricing.equalizations(of: basePoint.id, client: client).points
        var points = [base: basePoint.id]
        var others: [(territoryID: String, price: String)] = []
        for (territoryID, price) in priceFile.prices where territoryID != base {
          if let match = equalized.first(where: { $0.territoryID == territoryID }),
             let value = Double(match.customerPrice), abs(value - (try parseCustomerPrice(price))) < 0.001 {
            points[territoryID] = match.id
          } else {
            others.append((territoryID, price))
          }
        }
        if !others.isEmpty {
          print("Reading the tiers of \(others.count) territor\(others.count == 1 ? "y" : "ies")…")
          let appID = app.id
          let resolved = try await boundedConcurrentMap(others, maxConcurrent: 4) { entry in
            (entry.territoryID, try await PricingCommand.resolve(price: entry.price, territoryID: entry.territoryID, appID: appID, client: client).id)
          }
          for (territoryID, pointID) in resolved { points[territoryID] = pointID }
        }
        let dropped = Swift.Set(schedule?.manualPrices.filter(\.isCurrentOrLater).map(\.territoryID) ?? [])
          .subtracting(points.keys)
        var summary = ["Base territory: \(base) at \(basePrice)", "Set by hand:    \(points.count - 1) other territor\(points.count == 2 ? "y" : "ies")"]
        if !dropped.isEmpty { summary.append("Apple's prices: \(dropped.sorted().joined(separator: ", ")) (not in the file)") }
        try await PricingCommand.save(
          appID: app.id, appName: app.attributes?.name ?? bundleID, base: base,
          prices: points.sorted { $0.key < $1.key }.map { AppPricing.NewPrice(pricePointID: $0.value) },
          summary: summary, client: client)
      }
    }
  }
}
