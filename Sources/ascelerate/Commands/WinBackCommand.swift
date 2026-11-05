import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

/// Win-back offers: what the App Store offers people whose subscription ended (`Subscriptions.WinBackOffer`).
extension SubCommand {
  struct WinBackOffer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "win-back-offer",
      abstract: "Manage win-back offers: offers for people whose subscription ended.",
      discussion: "Only an approved subscription takes them.",
      subcommands: [List.self, Info.self, Create.self, Update.self, Delete.self],
      defaultSubcommand: List.self
    )

    struct Arguments: ParsableArguments {
      @Argument(help: "The bundle identifier of the app.", completion: appAliasCompletion)
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String
    }

    static func find(_ name: String, arguments: Arguments, client: ASCClient) async throws -> Subscriptions.WinBackOffer {
      let app = try await findApp(bundleID: arguments.bundleID, client: client)
      let (sub, _) = try await SubCommand.findSubscription(productID: arguments.productID, appID: app.id, client: client)
      let offers = try await Subscriptions.winBackOffers(subscriptionID: sub.id, client: client)
      guard let offer = offers.first(where: { $0.offerID == name || $0.id == name }) else {
        throw ValidationError("'\(arguments.productID)' has no win-back offer '\(name)'.")
      }
      return offer
    }

    /// `--since-months 3-12`: at least 3 and at most 12 months since they last subscribed.
    static func parseSince(_ text: String) throws -> ClosedRange<Int> {
      let parts = text.split(separator: "-").map { Int($0.trimmingCharacters(in: .whitespaces)) }
      guard parts.count == 2, let low = parts[0], let high = parts[1], low < high,
        Subscriptions.winBackSinceMinimum.contains(low), Subscriptions.winBackSinceMaximum.contains(high)
      else { throw ValidationError("--since-months takes a range like 3-12: from 1–23 to 2–24 months.") }
      return low...high
    }

    static func parseDate(_ text: String, name: String) throws -> String {
      guard (try? Date.ISO8601FormatStyle().year().month().day().dateSeparator(.dash).parse(text)) != nil else {
        throw ValidationError("--\(name) takes a date like 2026-12-01.")
      }
      return text
    }

    static func eligibility(_ offer: Subscriptions.WinBackOffer) -> String {
      var parts: [String] = []
      if let since = offer.sinceMonths { parts.append("ended \(since.lowerBound)–\(since.upperBound) months ago") }
      if let paid = offer.paidMonths { parts.append("paid \(paid) month\(paid == 1 ? "" : "s")") }
      if let wait = offer.waitMonths { parts.append("\(wait) months since the last offer") }
      return parts.isEmpty ? "—" : parts.joined(separator: ", ")
    }

    static func dates(_ offer: Subscriptions.WinBackOffer) -> String {
      "\(offer.startDate ?? "—")\(offer.endDate.map { " to \($0)" } ?? "")"
    }

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "List a subscription's win-back offers.")

      @OptionGroup var arguments: Arguments
      @OptionGroup var jsonOption: JSONOption

      struct Entry: Encodable {
        let id: String
        let offerID: String?
        let name: String?
        let mode: String?
        let duration: String?
        let periods: Int?
        let paidMonths: Int?
        let sinceMinimum: Int?
        let sinceMaximum: Int?
        let waitMonths: Int?
        let startDate: String?
        let endDate: String?
        let priority: String?
        let promotionIntent: String?
        let planType: String?
      }

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: arguments.bundleID, client: client)
        let (sub, _) = try await SubCommand.findSubscription(productID: arguments.productID, appID: app.id, client: client)
        let offers = try await Subscriptions.winBackOffers(subscriptionID: sub.id, client: client)
        if jsonOption.json {
          return try printJSON(offers.map {
            Entry(
              id: $0.id, offerID: $0.offerID, name: $0.name, mode: $0.mode, duration: $0.duration, periods: $0.periods,
              paidMonths: $0.paidMonths, sinceMinimum: $0.sinceMonths?.lowerBound, sinceMaximum: $0.sinceMonths?.upperBound,
              waitMonths: $0.waitMonths, startDate: $0.startDate, endDate: $0.endDate, priority: $0.priority,
              promotionIntent: $0.promotionIntent, planType: $0.planType)
          })
        }
        guard !offers.isEmpty else { return print("No win-back offers for \(arguments.productID).") }
        Table.print(
          headers: ["Offer ID", "Name", "Mode", "Duration", "Eligibility", "Dates", "Priority"],
          rows: offers.map { o in
            [
              o.offerID ?? "—", o.name ?? "—", o.mode.map(formatState) ?? "—",
              "\(o.periods.map(String.init) ?? "—") × \(o.duration.map(formatState) ?? "—")", eligibility(o), dates(o),
              o.priority.map(formatState) ?? "—",
            ]
          })
      }
    }

    struct Info: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Show a win-back offer.")

      @OptionGroup var arguments: Arguments

      @Argument(help: "The offer's offer ID (or its App Store Connect ID).")
      var offer: String

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let found = try await WinBackOffer.find(offer, arguments: arguments, client: client)
        let (offer, priceCount) = try await Subscriptions.winBackOffer(id: found.id, client: client)
        print("Win-Back Offer: \(offer.name ?? "—")")
        print("Offer ID:       \(offer.offerID ?? "—")")
        print("Mode:           \(offer.mode.map(formatState) ?? "—")")
        print("Duration:       \(offer.periods.map(String.init) ?? "—") × \(offer.duration.map(formatState) ?? "—")")
        print("Eligibility:    \(WinBackOffer.eligibility(offer))")
        print("Dates:          \(WinBackOffer.dates(offer))")
        print("Priority:       \(offer.priority.map(formatState) ?? "—")")
        print("Promotion:      \(offer.promotionIntent.map(formatState) ?? "—")")
        print("Plan:           \(offer.planType.map(formatState) ?? "—")")
        print("Prices:         \(priceCount) territor\(priceCount == 1 ? "y" : "ies")")
        print("ID:             \(offer.id)")
      }
    }

    struct Create: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Create a win-back offer.",
        discussion: """
          A paid offer takes --price in the first of --territories, and Apple's comparable prices in \
          the others; a free trial takes none. It starts on --start-date (tomorrow at the earliest) \
          and, with --end-date, ends at least 3 days later.
          """)

      @OptionGroup var arguments: Arguments

      @Option(name: .long, help: "The offer's reference name.")
      var name: String

      @Option(name: .customLong("offer-id"), help: "The offer's identifier (unique within the subscription).")
      var offerID: String

      @Option(name: .long, help: "FREE_TRIAL, PAY_AS_YOU_GO or PAY_UP_FRONT.")
      var mode: String

      @Option(name: .long, help: "How long a period lasts: THREE_DAYS, ONE_WEEK, TWO_WEEKS, ONE_MONTH, TWO_MONTHS, THREE_MONTHS, SIX_MONTHS, ONE_YEAR. PAY_AS_YOU_GO takes the subscription's own period.")
      var duration: String

      @Option(name: .long, help: "How many periods.")
      var periods: Int = 1

      @Option(name: .customLong("since-months"), help: "Who's eligible: their subscription ended this many months ago, as a range (e.g. 3-12; from 1–23 to 2–24).")
      var sinceMonths: String

      @Option(name: .customLong("paid-months"), help: "Who's eligible: they paid at least this many months (1–24, 36, 48 or 60).")
      var paidMonths: Int

      @Option(name: .customLong("wait-months"), help: "Who's eligible: at least this many months since their last offer (2–24).")
      var waitMonths: Int?

      @Option(name: .customLong("start-date"), help: "The first day (YYYY-MM-DD; default tomorrow).")
      var startDate: String?

      @Option(name: .customLong("end-date"), help: "The last day (YYYY-MM-DD), at least 3 days after the start.")
      var endDate: String?

      @Option(name: .long, help: "Which offer the App Store shows first: normal (default) or high.")
      var priority: String = "NORMAL"

      @Flag(name: .long, help: "Promote it on the App Store with assets Apple generates.")
      var promote = false

      @Option(name: .long, help: "The billing plan it's for: upfront (default) or monthly.")
      var plan: String?

      @Option(name: .long, help: "The price in the first territory (not for FREE_TRIAL).")
      var price: String?

      @Option(name: .long, help: "Territories (comma-separated, the first one's price is --price) or 'all' (the subscription's).")
      var territories: String = "all"

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let offerMode: ASCEnum.SubscriptionOfferMode = try parseEnum(mode, name: "mode")
        let offerDuration: ASCEnum.SubscriptionOfferDuration = try parseEnum(duration, name: "duration")
        let offerPriority: ASCEnum.WinBackOfferCreateRequestPriority = try parseEnum(priority, name: "priority")
        let planType: ASCEnum.SubscriptionPlanType? = try plan.map { try parseEnum($0, name: "plan") }
        guard periods > 0 else { throw ValidationError("--periods must be greater than 0.") }
        if offerMode == .freeTrial, price != nil { throw ValidationError("--price is not allowed for FREE_TRIAL.") }
        if offerMode != .freeTrial, price == nil { throw ValidationError("--price is required for \(offerMode.rawValue).") }
        let since = try WinBackOffer.parseSince(sinceMonths)
        try SubCommand.checkOfferEligibility(paidMonths: paidMonths, waitMonths: waitMonths)
        let tomorrow = (Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
          .formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let start = try startDate.map { try WinBackOffer.parseDate($0, name: "start-date") } ?? tomorrow
        let end = try endDate.map { try WinBackOffer.parseDate($0, name: "end-date") }

        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: arguments.bundleID, client: client)
        let (sub, _) = try await SubCommand.findSubscription(productID: arguments.productID, appID: app.id, client: client)
        let (listed, pricePoints, isAll) = try await SubCommand.offerTerritories(
          subscriptionID: sub.id, productID: arguments.productID, territories: territories, price: price, client: client)

        print()
        print("Create win-back offer:")
        print("  Subscription:  \(arguments.productID)")
        print("  Name:          \(name) (\(offerID))")
        print("  Mode:          \(formatState(offerMode.rawValue)), \(periods) × \(formatState(offerDuration.rawValue))")
        print("  Eligibility:   ended \(since.lowerBound)–\(since.upperBound) months ago, paid \(paidMonths) month\(paidMonths == 1 ? "" : "s")\(waitMonths.map { ", \($0) months since the last offer" } ?? "")")
        print("  Dates:         \(start)\(end.map { " to \($0)" } ?? "")")
        print("  Priority:      \(formatState(offerPriority.rawValue))\(promote ? ", promoted" : "")")
        if let planType { print("  Plan:          \(formatState(planType.rawValue))") }
        if let price { print("  Price:         \(price) in \(listed[0]), comparable prices elsewhere") }
        print("  Territories:   \(isAll ? "All (\(listed.count))" : listed.joined(separator: ", "))")
        print()
        guard confirm("Create this offer? [y/N] ") else { return cancelled() }
        let created = try await Subscriptions.createWinBackOffer(
          subscriptionID: sub.id, name: name, offerID: offerID, mode: offerMode.rawValue, duration: offerDuration.rawValue,
          periods: periods, paidMonths: paidMonths, sinceMonths: since, waitMonths: waitMonths, startDate: start, endDate: end,
          priority: offerPriority.rawValue, promotionIntent: promote ? "USE_AUTO_GENERATED_ASSETS" : "NOT_PROMOTED",
          planType: planType?.rawValue,
          prices: listed.map { Subscriptions.OfferPrice(territoryID: $0, pricePointID: pricePoints[$0]) }, client: client)
        success("Created", "win-back offer '\(name)' (offer ID \(created.offerID ?? offerID)).")
      }
    }

    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Change a win-back offer's eligibility, dates, priority or promotion.",
        discussion: "Its mode, duration and prices can't change; for those, delete the offer and create it again.")

      @OptionGroup var arguments: Arguments

      @Argument(help: "The offer's offer ID (or its App Store Connect ID).")
      var offer: String

      @Option(name: .customLong("since-months"), help: "Months since their subscription ended, as a range (e.g. 3-12).")
      var sinceMonths: String?

      @Option(name: .customLong("paid-months"), help: "Months they paid at least (1–24, 36, 48 or 60).")
      var paidMonths: Int?

      @Option(name: .customLong("wait-months"), help: "Months since their last offer (2–24).")
      var waitMonths: Int?

      @Option(name: .customLong("start-date"), help: "The first day (YYYY-MM-DD).")
      var startDate: String?

      @Option(name: .customLong("end-date"), help: "The last day (YYYY-MM-DD).")
      var endDate: String?

      @Option(name: .long, help: "normal or high.")
      var priority: String?

      @Option(name: .long, help: "Promote it on the App Store with assets Apple generates: true or false.")
      var promote: Bool?

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        try SubCommand.checkOfferEligibility(paidMonths: paidMonths, waitMonths: waitMonths)
        let offerPriority: ASCEnum.WinBackOfferUpdateRequestPriority? = try priority.map { try parseEnum($0, name: "priority") }
        let changes = Subscriptions.WinBackChanges(
          paidMonths: paidMonths, sinceMonths: try sinceMonths.map(WinBackOffer.parseSince), waitMonths: waitMonths,
          startDate: try startDate.map { try WinBackOffer.parseDate($0, name: "start-date") },
          endDate: try endDate.map { try WinBackOffer.parseDate($0, name: "end-date") }, priority: offerPriority?.rawValue,
          promotionIntent: promote.map { $0 ? "USE_AUTO_GENERATED_ASSETS" : "NOT_PROMOTED" })
        guard !changes.isEmpty else { throw ValidationError("Nothing to change.") }
        let client = try ClientFactory.makeClient()
        let found = try await WinBackOffer.find(offer, arguments: arguments, client: client)
        print("Change win-back offer '\(found.name ?? offer)':")
        if let since = changes.sinceMonths { print("  Ended:     \(found.sinceMonths.map { "\($0.lowerBound)–\($0.upperBound)" } ?? "—") → \(since.lowerBound)–\(since.upperBound) months ago") }
        if let paidMonths { print("  Paid:      \(found.paidMonths.map(String.init) ?? "—") → \(paidMonths) months") }
        if let waitMonths { print("  Wait:      \(found.waitMonths.map(String.init) ?? "—") → \(waitMonths) months") }
        if let start = changes.startDate { print("  Start:     \(found.startDate ?? "—") → \(start)") }
        if let end = changes.endDate { print("  End:       \(found.endDate ?? "—") → \(end)") }
        if let priority = changes.priority { print("  Priority:  \(found.priority.map(formatState) ?? "—") → \(formatState(priority))") }
        if let intent = changes.promotionIntent { print("  Promotion: \(found.promotionIntent.map(formatState) ?? "—") → \(formatState(intent))") }
        guard confirm("Save? [y/N] ") else { return cancelled() }
        try await Subscriptions.updateWinBackOffer(id: found.id, changes, client: client)
        success("Saved", found.offerID ?? offer)
      }
    }

    struct Delete: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Delete a win-back offer.")

      @OptionGroup var arguments: Arguments

      @Argument(help: "The offer's offer ID (or its App Store Connect ID).")
      var offer: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let found = try await WinBackOffer.find(offer, arguments: arguments, client: client)
        guard confirm("Delete win-back offer '\(found.name ?? offer)'? [y/N] ") else { return cancelled() }
        try await Subscriptions.deleteWinBackOffer(id: found.id, client: client)
        success("Deleted", "win-back offer '\(found.name ?? offer)'.")
      }
    }
  }
}
