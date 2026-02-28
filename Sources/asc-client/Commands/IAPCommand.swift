import AppStoreAPI
import AppStoreConnect
import ArgumentParser
import Foundation

struct IAPCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "iap",
    abstract: "View in-app purchases.",
    subcommands: [List.self, Info.self, Promoted.self]
  )

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List in-app purchases for an app."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Option(name: .long, help: "Filter by type (CONSUMABLE, NON_CONSUMABLE, NON_RENEWING_SUBSCRIPTION).")
    var type: String?

    @Option(name: .long, help: "Filter by state (APPROVED, MISSING_METADATA, READY_TO_SUBMIT, etc.).")
    var state: String?

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      typealias Params = Resources.V1.Apps.WithID.InAppPurchasesV2

      let filterType: [Params.FilterInAppPurchaseType]? = try parseFilter(type, name: "type")
      let filterState: [Params.FilterState]? = try parseFilter(state, name: "state")

      var rows: [[String]] = []
      let request = Resources.v1.apps.id(app.id).inAppPurchasesV2.get(
        filterState: filterState,
        filterInAppPurchaseType: filterType,
        limit: 200
      )

      for try await page in client.pages(request) {
        for iap in page.data {
          let attrs = iap.attributes
          rows.append([
            attrs?.name ?? "—",
            attrs?.productID ?? "—",
            attrs?.inAppPurchaseType.map { formatState($0) } ?? "—",
            attrs?.state.map { formatState($0) } ?? "—",
            attrs?.isFamilySharable == true ? "Yes" : "No",
          ])
        }
      }

      if rows.isEmpty {
        print("No in-app purchases found.")
      } else {
        Table.print(
          headers: ["Name", "Product ID", "Type", "State", "Family"],
          rows: rows
        )
      }
    }
  }

  struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Show details for an in-app purchase."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Argument(help: "The product identifier of the in-app purchase.")
    var productID: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let request = Resources.v1.apps.id(app.id).inAppPurchasesV2.get(
        filterProductID: [productID],
        include: [.inAppPurchaseLocalizations],
        limitInAppPurchaseLocalizations: 50
      )
      let response = try await client.send(request)

      guard let iap = response.data.first else {
        throw ValidationError("No in-app purchase found with product ID '\(productID)'.")
      }

      let attrs = iap.attributes
      print("Name:             \(attrs?.name ?? "—")")
      print("Product ID:       \(attrs?.productID ?? "—")")
      print("Type:             \(attrs?.inAppPurchaseType.map { formatState($0) } ?? "—")")
      print("State:            \(attrs?.state.map { formatState($0) } ?? "—")")
      print("Family Shareable: \(attrs?.isFamilySharable == true ? "Yes" : "No")")
      print("Content Hosting:  \(attrs?.isContentHosting == true ? "Yes" : "No")")
      print("Review Note:      \(attrs?.reviewNote ?? "—")")

      // Extract localizations from included items
      let locIDs = Set(
        iap.relationships?.inAppPurchaseLocalizations?.data?.map(\.id) ?? []
      )
      let localizations: [InAppPurchaseLocalization] = (response.included ?? []).compactMap {
        if case .inAppPurchaseLocalization(let loc) = $0,
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

  struct Promoted: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List promoted purchases for an app."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      var rows: [[String]] = []
      let request = Resources.v1.apps.id(app.id).promotedPurchases.get(
        limit: 200,
        include: [.inAppPurchaseV2, .subscription]
      )

      for try await page in client.pages(request) {
        // Build lookup for included items
        var iapInfo: [String: (String, String)] = [:]  // id -> (name, type)
        var subInfo: [String: (String, String)] = [:]   // id -> (name, period)

        for item in page.included ?? [] {
          switch item {
          case .inAppPurchaseV2(let iap):
            iapInfo[iap.id] = (
              iap.attributes?.name ?? "—",
              iap.attributes?.inAppPurchaseType.map { formatState($0) } ?? "—"
            )
          case .subscription(let sub):
            subInfo[sub.id] = (
              sub.attributes?.name ?? "—",
              sub.attributes?.subscriptionPeriod.map { formatState($0) } ?? "—"
            )
          }
        }

        for promo in page.data {
          let attrs = promo.attributes
          let promoState = attrs?.state.map { formatState($0) } ?? "—"
          let visible = attrs?.isVisibleForAllUsers == true ? "Yes" : "No"
          let enabled = attrs?.isEnabled == true ? "Yes" : "No"

          // Resolve product name and type from relationships
          var productName = "—"
          var productType = "—"

          if let iapID = promo.relationships?.inAppPurchaseV2?.data?.id,
             let info = iapInfo[iapID] {
            productName = "\(info.0) (IAP)"
            productType = info.1
          } else if let subID = promo.relationships?.subscription?.data?.id,
                    let info = subInfo[subID] {
            productName = "\(info.0) (Subscription)"
            productType = info.1
          }

          rows.append([productName, productType, promoState, visible, enabled])
        }
      }

      if rows.isEmpty {
        print("No promoted purchases found.")
      } else {
        Table.print(
          headers: ["Product", "Type", "State", "Visible", "Enabled"],
          rows: rows
        )
      }
    }
  }
}
