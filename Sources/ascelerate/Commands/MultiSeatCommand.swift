import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

/// Display names of a multiseat subscription's markets, and the CLI's names for them.
private let multiSeatMarkets: [(cli: String, raw: String, name: String)] = [
  ("app-store", "APP_STORE", "App Store"),
  ("apple-business", "APPLE_BUSINESS", "Apple Business Manager"),
  ("apple-school", "APPLE_SCHOOL", "Apple School Manager"),
]

private func marketNames(_ raw: [String]) -> String {
  raw.isEmpty ? "None" : raw.map { value in multiSeatMarkets.first { $0.raw == value }?.name ?? formatState(value) }.joined(separator: ", ")
}

// MARK: - apps group-purchase-invitations

extension AppsCommand {
  struct GroupPurchaseInvitations: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "group-purchase-invitations",
      abstract: "View or change who hosts seat invitations for multiseat App Store purchases.",
      discussion: """
        A customer who buys several seats of a subscription on the App Store invites others to them.
        Apple hosts the invitations by default; with --host developer, the app runs its own invitation
        and seat acceptance flow (members then need no Apple Account) and must verify invited members'
        ages and get any parental consent itself. Applies to every multiseat subscription of the app,
        for purchases made after the change; needs no App Review.
        """
    )

    @Argument(help: "The bundle identifier of the app.", completion: appAliasCompletion)
    var bundleID: String

    @Option(name: .long, help: "apple or developer.")
    var host: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    private static func label(_ mode: String) -> String {
      mode == "DEVELOPER_HOSTED" ? "the app (developer-hosted)" : "Apple (Apple-hosted)"
    }

    func run() async throws {
      if yes { autoConfirm = true }
      let newMode: String? = try host.map {
        switch $0.lowercased() {
          case "apple": return "APPLE_HOSTED"
          case "developer": return "DEVELOPER_HOSTED"
          default: throw ValidationError("Invalid value for --host. Use 'apple' or 'developer'.")
        }
      }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let current = try await Subscriptions.groupPurchaseInvitationMode(appID: app.id, client: client)
      guard let newMode else {
        print("Seat invitations are hosted by \(Self.label(current)).")
        return
      }
      guard newMode != current else {
        print("Seat invitations are already hosted by \(Self.label(current)).")
        return
      }
      if newMode == "DEVELOPER_HOSTED" {
        print(yellow("Note:") + " the app then verifies invited members' ages and gets any parental consent before they accept a seat.")
      }
      guard confirm("Have seat invitations hosted by \(Self.label(newMode)) for new purchases? [y/N] ") else {
        cancelled()
        return
      }
      let saved = try await Subscriptions.setGroupPurchaseInvitationMode(appID: app.id, mode: newMode, client: client)
      success("Changed", "seat invitations to be hosted by \(Self.label(saved)).")
    }
  }
}

// MARK: - sub multiseat

extension SubCommand {
  struct MultiSeatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "multiseat",
      abstract: "View or change whether a subscription can be bought for several people, and where.",
      discussion: """
        On by default for every auto-renewable subscription: organizations buy seats through Apple
        Business Manager or Apple School Manager, and App Store customers invite others to theirs
        (see 'apps group-purchase-invitations'). Turning it off stops new multiseat purchases;
        existing ones renew at their seat count but can't add seats. Turning on Family Sharing turns
        it off. Markets: app-store, apple-business, apple-school (comma-separated, or none).
        """
    )

    @Argument(help: "The bundle identifier of the app.", completion: appAliasCompletion)
    var bundleID: String

    @Argument(help: "The product identifier of the subscription.")
    var productID: String

    @Option(name: .long, help: "Turn multiseat purchasing on or off (true/false).")
    var enabled: String?

    @Option(name: .long, help: "Where it's offered: app-store, apple-business, apple-school (comma-separated), or none.")
    var markets: String?

    @OptionGroup var jsonOption: JSONOption

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      jsonOption.activate()
      if yes { autoConfirm = true }
      let newEnabled: Bool? = try enabled.map {
        guard let value = Bool($0.lowercased()) else { throw ValidationError("Invalid value for --enabled. Use 'true' or 'false'.") }
        return value
      }
      let newMarkets: [String]? = try markets.map { list in
        if list.lowercased() == "none" { return [] }
        return try list.split(separator: ",").map { item in
          let name = item.trimmingCharacters(in: .whitespaces).lowercased()
          guard let market = multiSeatMarkets.first(where: { $0.cli == name }) else {
            throw ValidationError("Unknown market '\(name)'. Use: \(multiSeatMarkets.map(\.cli).joined(separator: ", ")), or none.")
          }
          return market.raw
        }
      }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let (sub, _) = try await SubCommand.findSubscription(productID: productID, appID: app.id, client: client)
      let current = try await Subscriptions.multiSeat(subscriptionID: sub.id, client: client)

      guard newEnabled != nil || newMarkets != nil else {
        if jsonOption.json { return try printJSON(current) }
        print("Multiseat: \(current.enabled ? "On" : "Off")")
        print("Markets:   \(marketNames(current.markets))\(current.enabled ? "" : " (not offered while off)")")
        return
      }
      if jsonOption.json { throw ValidationError("--json shows the setting; leave it out to change it.") }
      var changes: [String] = []
      if let newEnabled, newEnabled != current.enabled { changes.append("Multiseat: \(current.enabled ? "On" : "Off") → \(newEnabled ? "On" : "Off")") }
      if let newMarkets, Swift.Set(newMarkets) != Swift.Set(current.markets) {
        changes.append("Markets: \(marketNames(current.markets)) → \(marketNames(newMarkets))")
      }
      guard !changes.isEmpty else {
        print("Nothing to change.")
        return
      }
      print("\(sub.name) (\(sub.productID)):")
      for change in changes { print("  \(change)") }
      if newEnabled == true, sub.familySharable == true {
        print(yellow("Note:") + " with Family Sharing on, it then applies only when a single seat is bought.")
      }
      guard confirm("Save? [y/N] ") else {
        cancelled()
        return
      }
      let saved = try await Subscriptions.setMultiSeat(
        subscriptionID: sub.id, enabled: newEnabled, markets: newMarkets, client: client)
      success("Saved", "multiseat \(saved.enabled ? "on" : "off"), markets: \(marketNames(saved.markets)).")
    }
  }
}

// MARK: - sub pricing volume / volume-set / cancel

extension SubCommand.Pricing {
  /// "2:8.99,10:7.99" → [(2, "8.99"), (10, "7.99")]; "none" → [].
  static func parseTiers(_ value: String) throws -> [(minQuantity: Int, price: String)] {
    if value.lowercased() == "none" { return [] }
    return try value.split(separator: ",").map { item in
      let parts = item.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
      guard parts.count == 2, let quantity = Int(parts[0]), Double(parts[1]) != nil else {
        throw ValidationError("Invalid tier '\(item)'. Use SEATS:PRICE, e.g. 2:8.99,10:7.99, or none.")
      }
      return (quantity, parts[1])
    }
  }

  static func tierText(_ tiers: [Subscriptions.VolumeTier]) -> String {
    tiers.isEmpty ? "—" : tiers.map { "\($0.minQuantity)+: \($0.customerPrice ?? "?")" }.joined(separator: ", ")
  }

  struct Volume: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "volume",
      abstract: "Show a subscription's volume pricing: lower per-seat prices from a number of seats on.",
      discussion: """
        Lists the territories whose current or planned price has tiers (--territory: that one, with
        or without). Each seat costs its own tier's price: with 9.99 for one seat and 2+: 8.99, 10+:
        7.99, twelve seats cost 9.99 + 8 × 8.99 + 3 × 7.99.
        """
    )

    @Argument(help: "The bundle identifier of the app.", completion: appAliasCompletion)
    var bundleID: String

    @Argument(help: "The product identifier of the subscription.")
    var productID: String

    @Option(name: .long, help: "One territory (e.g. USA).")
    var territory: String?

    @OptionGroup var jsonOption: JSONOption

    private struct Entry: Encodable {
      let id: String
      let territory: String
      let startDate: String?
      let preserved: Bool
      let planned: Bool
      let price: String
      let currency: String?
      let tiers: [Subscriptions.VolumeTier]
    }

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let (sub, _) = try await SubCommand.findSubscription(productID: productID, appID: app.id, client: client)
      async let pricesTask = Subscriptions.prices(subscriptionID: sub.id, client: client)
      async let tiersTask = Subscriptions.volumeTiers(subscriptionID: sub.id, client: client)
      let (prices, tiers) = try await (pricesTask, tiersTask)
      let wanted = territory?.uppercased()
      let shown = Array(prices.current.values) + prices.planned
      let entries = shown
        .filter { price in wanted.map { price.territoryID == $0 } ?? !(tiers[price.id] ?? []).isEmpty }
        .sorted { ($0.territoryID, $0.startDate ?? "") < ($1.territoryID, $1.startDate ?? "") }
        .map { price in
          Entry(
            id: price.id, territory: price.territoryID, startDate: price.startDate, preserved: price.preserved,
            planned: (price.startDate ?? "") > AppPricing.today, price: price.customerPrice,
            currency: prices.currencies[price.territoryID], tiers: tiers[price.id] ?? [])
        }
      if jsonOption.json { return try printJSON(entries) }
      guard !entries.isEmpty else {
        print(wanted.map { "No price in \($0)." } ?? "No volume pricing: every price is for any number of seats.")
        return
      }
      Table.print(
        headers: ["Territory", "From", "1 Seat", "Per Seat From", "Currency"],
        rows: entries.map {
          [$0.territory, ($0.startDate ?? "—") + ($0.planned ? " (planned)" : ""), $0.price, SubCommand.Pricing.tierText($0.tiers), $0.currency ?? ""]
        })
    }
  }

  struct VolumeSet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "volume-set",
      abstract: "Set a subscription's price with volume tiers in a territory, or in every territory.",
      discussion: """
        --tiers lists up to four per-seat prices, each from a number of seats (2 or more), each
        cheaper than the one before: --tiers 2:8.99,10:7.99,50:6.99. --tiers none sets a price for
        any number of seats, the way to remove tiers from a price in effect. The single-seat price is
        --price, or the territory's current price. With --equalize-all-territories, Apple converts the
        price and tiers into every other territory with the same seat counts.

        Apple compares the new price with the current one at every seat count first: a raise
        everywhere needs --preserve-current or --no-preserve-current, as 'pricing set' does; a cut,
        or one that's higher for some seat counts and lower for others, moves existing subscribers at
        their next renewal (with --yes, add --confirm-decrease). A territory with a planned price
        takes no other until it's removed ('pricing cancel').

        A price and its tiers can't be edited once made. While a subscription has a price with tiers,
        planned or in effect, App Store Connect's web pages can't change its pricing, preserved
        prices included: delete the planned price, or replace the one in effect with a price without
        tiers. Upfront billing only.
        """
    )

    @Argument(help: "The bundle identifier of the app.", completion: appAliasCompletion)
    var bundleID: String

    @Argument(help: "The product identifier of the subscription.")
    var productID: String

    @Option(name: .long, help: "Per-seat prices from a number of seats: SEATS:PRICE,… (e.g. 2:8.99,10:7.99), or none.")
    var tiers: String

    @Option(name: .long, help: "The single-seat price (default: the territory's current price).")
    var price: String?

    @Option(name: .long, help: "Territory code (default: USA); the base territory with --equalize-all-territories.")
    var territory: String = "USA"

    @Flag(name: .customLong("equalize-all-territories"), help: "Set Apple's equivalent price and tiers in every other territory too.")
    var equalizeAllTerritories = false

    @Option(name: .long, help: "Start date in YYYY-MM-DD format (default: immediate).")
    var startDate: String?

    @Flag(name: .customLong("preserve-current"), inversion: .prefixedNo,
          help: "Required when the new price is a raise: --preserve-current keeps existing subscribers on their price; --no-preserve-current moves them after Apple's notice.")
    var preserveCurrent: Bool?

    @Flag(name: .customLong("confirm-decrease"), help: "Required with --yes when existing subscribers would pay less, or more for some seat counts and less for others.")
    var confirmDecrease = false

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    private struct Target {
      let proposed: Subscriptions.ProposedPrice
      var singleSeatPrice: String?
      var tiers: [Subscriptions.VolumeTier]
      var change: String?
    }

    func run() async throws {
      if yes { autoConfirm = true }
      let wantedTiers = try SubCommand.Pricing.parseTiers(tiers)
      let baseTerritory = territory.uppercased()
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let (sub, _) = try await SubCommand.findSubscription(productID: productID, appID: app.id, client: client)
      let prices = try await Subscriptions.prices(subscriptionID: sub.id, client: client)

      // The base territory's price points: the single seat and each tier.
      let points = try await Subscriptions.pricePoints(subscriptionID: sub.id, territoryID: baseTerritory, client: client)
      let currency = prices.currencies[baseTerritory]
      let singleSeat: AppPricing.PricePoint
      if let price {
        singleSeat = try findPricePoint(
          in: points, target: try parseCustomerPrice(price), priceLabel: price, territoryID: baseTerritory, currency: currency)
      } else if let current = prices.current[baseTerritory], let point = points.first(where: { $0.id == current.pricePointID }) {
        singleSeat = point
      } else {
        throw ValidationError("\(sub.productID) has no price in \(baseTerritory) yet. Give the single-seat price with --price.")
      }
      let baseTiers = try wantedTiers.map { tier in
        let point = try findPricePoint(
          in: points, target: try parseCustomerPrice(tier.price), priceLabel: tier.price, territoryID: baseTerritory, currency: currency)
        return Subscriptions.VolumeTier(minQuantity: tier.minQuantity, pricePointID: point.id, customerPrice: point.customerPrice)
      }
      try Subscriptions.validate(singleSeatPrice: singleSeat.customerPrice, tiers: baseTiers)

      var targets = [Target(
        proposed: .init(territoryID: baseTerritory, pricePointID: singleSeat.id, tiers: baseTiers, startDate: startDate),
        singleSeatPrice: singleSeat.customerPrice, tiers: baseTiers)]
      if equalizeAllTerritories {
        print("Equalizing in every territory...")
        let equalized = try await Subscriptions.equalizeVolumeTiers(
          subscriptionID: sub.id, basePricePointID: singleSeat.id, tiers: baseTiers, client: client)
        // Their customer prices, for the summary: a few territories' tiers a request.
        var pricesByPoint: [String: String] = [:]
        for chunk in equalized.map(\.territoryID).chunked(into: 9) {
          let tiersByTerritory = try await Subscriptions.pricePoints(subscriptionID: sub.id, territoryIDs: chunk, client: client)
          for point in tiersByTerritory.values.joined() { pricesByPoint[point.id] = point.customerPrice }
        }
        targets += equalized.sorted { $0.territoryID < $1.territoryID }.map { price in
          let tiers = price.tiers.map {
            Subscriptions.VolumeTier(minQuantity: $0.minQuantity, pricePointID: $0.pricePointID, customerPrice: pricesByPoint[$0.pricePointID])
          }
          return Target(
            proposed: .init(territoryID: price.territoryID, pricePointID: price.pricePointID, tiers: tiers, startDate: startDate),
            singleSeatPrice: pricesByPoint[price.pricePointID], tiers: tiers)
        }
      }

      // A territory with a planned price takes no other (409).
      let plannedTerritories = Swift.Set(prices.planned.map(\.territoryID))
      let blocked = targets.map(\.proposed.territoryID).filter(plannedTerritories.contains).sorted()
      guard blocked.isEmpty else {
        throw ValidationError(
          "These territories already have a planned price: \(blocked.joined(separator: ", ")). Remove it first with 'sub pricing cancel \(bundleID) \(productID) --territories \(blocked.joined(separator: ","))'.")
      }

      // How each territory's existing subscribers fare, by Apple's comparison at every seat count.
      let priced = targets.filter { prices.current[$0.proposed.territoryID] != nil }
      let changes = priced.isEmpty ? [:] : try await Subscriptions.previewPriceChanges(
        subscriptionID: sub.id, prices: priced.map(\.proposed), client: client)
      for index in targets.indices {
        let territoryID = targets[index].proposed.territoryID
        targets[index].change = prices.current[territoryID] == nil ? "NEW" : (changes[territoryID] ?? "UNKNOWN")
      }
      let byChange = Dictionary(grouping: targets, by: { $0.change ?? "" })
      let raises = byChange["INCREASE_PRESERVABLE"] ?? []
      let cuts = (byChange["DECREASE_NOT_PRESERVABLE"] ?? []) + (byChange["MIXED_NOT_PRESERVABLE"] ?? [])
      if !raises.isEmpty && preserveCurrent == nil {
        throw ValidationError("""
          \(raises.count) territor\(raises.count == 1 ? "y gets" : "ies get") a raise for existing subscribers (\(raises.prefix(5).map(\.proposed.territoryID).joined(separator: ", "))\(raises.count > 5 ? ", …" : "")).
          Choose how: --preserve-current keeps them on their price; --no-preserve-current moves them after Apple's notice.
          """)
      }
      if !cuts.isEmpty && autoConfirm && !confirmDecrease {
        throw ValidationError(
          "\(cuts.count) territor\(cuts.count == 1 ? "y moves" : "ies move") existing subscribers to a lower price, or a lower price for some seat counts and a higher one for others, at their next renewal. Plain --yes is not enough: add --confirm-decrease.")
      }
      let toApply = targets.filter { $0.change != "NO_CHANGE" }
      guard !toApply.isEmpty else {
        print("Every territory already has this price and these tiers. Nothing to do.")
        return
      }

      print()
      print("\(sub.name) (\(sub.productID)), from \(startDate ?? "now"):")
      Table.print(
        headers: ["Territory", "1 Seat", "Per Seat From", "Existing Subscribers"],
        rows: toApply.prefix(equalizeAllTerritories ? 8 : toApply.count).map {
          [$0.proposed.territoryID, $0.singleSeatPrice ?? "?", SubCommand.Pricing.tierText($0.tiers), Self.changeLabel($0.change)]
        })
      if toApply.count > 8 && equalizeAllTerritories { print("  … and \(toApply.count - 8) more territories") }
      let counts = ["NEW", "INCREASE_PRESERVABLE", "DECREASE_NOT_PRESERVABLE", "MIXED_NOT_PRESERVABLE"].compactMap { key -> String? in
        guard let count = byChange[key]?.count, count > 0 else { return nil }
        return "\(Self.changeLabel(key)): \(count)"
      }
      print("  " + counts.joined(separator: ", ") + ((byChange["NO_CHANGE"]?.count).map { ", unchanged (skipped): \($0)" } ?? ""))
      if !raises.isEmpty, let preserveCurrent { print("  Raises: existing subscribers \(preserveCurrent ? "keep their price" : "move after Apple's notice")") }
      if !wantedTiers.isEmpty {
        print(yellow("Note:") + " while the subscription has a price with tiers, App Store Connect's web pages can't change its pricing.")
      }
      guard confirm("Set \(toApply.count) price\(toApply.count == 1 ? "" : "s")? [y/N] ") else {
        cancelled()
        return
      }

      var failed: [String] = []
      var notSent = 0
      for target in toApply {
        do {
          let sent: Void? = try await unlessDryRunStopped {
            try await Subscriptions.setPrice(
              subscriptionID: sub.id, territoryID: target.proposed.territoryID, pricePointID: target.proposed.pricePointID,
              tiers: target.tiers, startDate: startDate,
              preserveCurrent: target.change == "INCREASE_PRESERVABLE" ? preserveCurrent : nil, client: client)
          }
          if sent == nil { notSent += 1 }
        } catch {
          print("  FAIL \(target.proposed.territoryID) — \(describeError(error))")
          failed.append(target.proposed.territoryID)
        }
      }
      if notSent > 0 {
        print("Dry run complete. \(notSent) price\(notSent == 1 ? "" : "s") would be set.")
        return
      }
      let done = toApply.count - failed.count
      success("Set", "\(done) price\(done == 1 ? "" : "s")\(failed.isEmpty ? "." : ", \(failed.count) failed: \(failed.joined(separator: ", ")).")")
      if !failed.isEmpty { throw ExitCode.failure }
    }

    private static func changeLabel(_ change: String?) -> String {
      switch change {
        case "NEW": "new territory"
        case "INCREASE_PRESERVABLE": "raise"
        case "DECREASE_NOT_PRESERVABLE": "cut"
        case "MIXED_NOT_PRESERVABLE": "higher for some seats, lower for others"
        case "NO_CHANGE": "unchanged"
        default: formatState(change ?? "")
      }
    }
  }

  struct Cancel: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "cancel",
      abstract: "Remove planned prices (ones that haven't started) from territories.",
      discussion: "A price in effect can't be removed: set a later one instead."
    )

    @Argument(help: "The bundle identifier of the app.", completion: appAliasCompletion)
    var bundleID: String

    @Argument(help: "The product identifier of the subscription.")
    var productID: String

    @Option(name: .long, help: "Territory codes (comma-separated), or all.")
    var territories: String

    @Option(name: .long, help: "Only the planned prices starting on this day (YYYY-MM-DD).")
    var startDate: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let (sub, _) = try await SubCommand.findSubscription(productID: productID, appID: app.id, client: client)
      let prices = try await Subscriptions.prices(subscriptionID: sub.id, client: client)
      let wanted = territories.lowercased() == "all"
        ? nil : Swift.Set(territories.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() })
      let planned = prices.planned.filter { price in
        (wanted?.contains(price.territoryID) ?? true) && (startDate.map { $0 == price.startDate } ?? true)
      }
      guard !planned.isEmpty else {
        print("No planned prices to remove.")
        return
      }
      Table.print(
        headers: ["Territory", "From", "Price", "Currency"],
        rows: planned.map { [$0.territoryID, $0.startDate ?? "—", $0.customerPrice, prices.currencies[$0.territoryID] ?? ""] })
      guard confirm("Remove \(planned.count) planned price\(planned.count == 1 ? "" : "s")? [y/N] ") else {
        cancelled()
        return
      }
      for price in planned {
        try await Subscriptions.deletePrice(id: price.id, client: client)
      }
      success("Removed", "\(planned.count) planned price\(planned.count == 1 ? "" : "s").")
    }
  }
}
