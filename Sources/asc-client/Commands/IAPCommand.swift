import AppStoreAPI
import AppStoreConnect
import ArgumentParser
import Foundation

struct IAPCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "iap",
    abstract: "Manage in-app purchases.",
    subcommands: [List.self, Info.self, Promoted.self, Create.self, Update.self, Delete.self, Submit.self, Localizations.self]
  )

  // MARK: - Helpers

  static func findIAP(
    productID: String, appID: String, client: AppStoreConnectClient
  ) async throws -> InAppPurchaseV2 {
    let response = try await client.send(
      Resources.v1.apps.id(appID).inAppPurchasesV2.get(filterProductID: [productID])
    )
    guard let iap = response.data.first else {
      throw ValidationError("No in-app purchase found with product ID '\(productID)'.")
    }
    return iap
  }

  // MARK: - List

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

  // MARK: - Info

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

  // MARK: - Promoted

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
        var iapInfo: [String: (String, String)] = [:]
        var subInfo: [String: (String, String)] = [:]

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

  // MARK: - Create

  struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Create a new in-app purchase."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Option(name: .long, help: "IAP type (CONSUMABLE, NON_CONSUMABLE, NON_RENEWING_SUBSCRIPTION).")
    var type: String?

    @Option(name: .long, help: "Product identifier (e.g. com.example.premium).")
    var productID: String?

    @Option(name: .long, help: "Reference name.")
    var name: String?

    @Option(name: .long, help: "Review note for App Review.")
    var reviewNote: String?

    @Flag(name: .long, help: "Enable Family Sharing.")
    var familySharable: Bool = false

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes: Bool = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let iapType: InAppPurchaseType
      if let t = type {
        iapType = try parseEnum(t, name: "type")
      } else {
        iapType = try promptSelection(
          "Type",
          items: Array(InAppPurchaseType.allCases),
          display: { formatState($0) }
        )
      }

      let pid = productID ?? promptText("Product ID: ")
      let refName = name ?? promptText("Reference Name: ")

      var note: String? = reviewNote
      if note == nil && !autoConfirm {
        print("Review Note (optional, press Enter to skip): ", terminator: "")
        let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !input.isEmpty { note = input }
      }

      print()
      print("Type:             \(formatState(iapType))")
      print("Product ID:       \(pid)")
      print("Name:             \(refName)")
      print("Family Shareable: \(familySharable ? "Yes" : "No")")
      if let n = note { print("Review Note:      \(n)") }
      print()

      guard confirm("Create this in-app purchase? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

      let response = try await client.send(
        Resources.v2.inAppPurchases.post(
          InAppPurchaseV2CreateRequest(
            data: .init(
              attributes: .init(
                name: refName,
                productID: pid,
                inAppPurchaseType: iapType,
                reviewNote: note,
                isFamilySharable: familySharable ? true : nil
              ),
              relationships: .init(
                app: .init(data: .init(id: app.id))
              )
            )
          )
        )
      )

      print(green("Created") + " in-app purchase '\(response.data.attributes?.name ?? refName)'.")
    }
  }

  // MARK: - Update

  struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Update an in-app purchase."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Argument(help: "The product identifier of the in-app purchase.")
    var productID: String

    @Option(name: .long, help: "New reference name.")
    var name: String?

    @Option(name: .long, help: "New review note.")
    var reviewNote: String?

    @Option(name: .long, help: "Enable or disable Family Sharing (true/false).")
    var familySharable: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes: Bool = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let iap = try await findIAP(productID: productID, appID: app.id, client: client)

      let familyVal: Bool? = try familySharable.map {
        guard let val = Bool($0.lowercased()) else {
          throw ValidationError("Invalid value for --family-sharable. Use 'true' or 'false'.")
        }
        return val
      }

      guard name != nil || reviewNote != nil || familyVal != nil else {
        throw ValidationError("No updates specified. Use --name, --review-note, or --family-sharable.")
      }

      var changes: [String] = []
      if let v = name { changes.append("Name: \(v)") }
      if let v = reviewNote { changes.append("Review Note: \(v)") }
      if let v = familyVal { changes.append("Family Shareable: \(v ? "Yes" : "No")") }
      print("Updates for '\(iap.attributes?.name ?? productID)':")
      for c in changes { print("  \(c)") }
      print()

      guard confirm("Apply updates? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

      _ = try await client.send(
        Resources.v2.inAppPurchases.id(iap.id).patch(
          InAppPurchaseV2UpdateRequest(
            data: .init(
              id: iap.id,
              attributes: .init(
                name: name,
                reviewNote: reviewNote,
                isFamilySharable: familyVal
              )
            )
          )
        )
      )

      print(green("Updated") + " '\(name ?? iap.attributes?.name ?? productID)'.")
    }
  }

  // MARK: - Delete

  struct Delete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Delete an in-app purchase."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Argument(help: "The product identifier of the in-app purchase.")
    var productID: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes: Bool = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let iap = try await findIAP(productID: productID, appID: app.id, client: client)

      guard confirm("Delete in-app purchase '\(iap.attributes?.name ?? productID)'? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

      _ = try await client.send(Resources.v2.inAppPurchases.id(iap.id).delete)

      print(green("Deleted") + " '\(iap.attributes?.name ?? productID)'.")
    }
  }

  // MARK: - Submit

  struct Submit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Submit an in-app purchase for review."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Argument(help: "The product identifier of the in-app purchase.")
    var productID: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes: Bool = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let iap = try await findIAP(productID: productID, appID: app.id, client: client)

      let state = iap.attributes?.state
      guard state == .readyToSubmit else {
        let stateStr = state.map { formatState($0) } ?? "unknown"
        throw ValidationError("In-app purchase '\(iap.attributes?.name ?? productID)' is in state '\(stateStr)'. Only items in 'Ready to Submit' state can be submitted.")
      }

      print("In-app purchase: \(iap.attributes?.name ?? productID)")
      print("Product ID:      \(productID)")
      print("State:           \(formatState(state!))")
      print()
      print(yellow("Note:") + " In-app purchases are reviewed together with the app version.")
      print("Make sure you also submit a new app version for review.")
      print()

      guard confirm("Submit for review? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }

      _ = try await client.send(
        Resources.v1.inAppPurchaseSubmissions.post(
          InAppPurchaseSubmissionCreateRequest(
            data: .init(
              relationships: .init(
                inAppPurchaseV2: .init(data: .init(id: iap.id))
              )
            )
          )
        )
      )

      print(green("Submitted") + " '\(iap.attributes?.name ?? productID)' for review.")
    }
  }

  // MARK: - Localizations

  struct Localizations: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Manage in-app purchase localizations.",
      subcommands: [View.self, Export.self, Import.self]
    )

    // MARK: View

    struct View: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "View localizations for an in-app purchase."
      )

      @Argument(help: "The bundle identifier of the app.")
      var bundleID: String

      @Argument(help: "The product identifier of the in-app purchase.")
      var productID: String

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let iap = try await findIAP(productID: productID, appID: app.id, client: client)

        let locsResponse = try await client.send(
          Resources.v2.inAppPurchases.id(iap.id).inAppPurchaseLocalizations.get(limit: 50)
        )

        if locsResponse.data.isEmpty {
          print("No localizations found.")
          return
        }

        print("Localizations for '\(iap.attributes?.name ?? productID)':")
        print()

        for loc in locsResponse.data.sorted(by: { ($0.attributes?.locale ?? "") < ($1.attributes?.locale ?? "") }) {
          let locale = loc.attributes?.locale ?? "?"
          print("[\(localeName(locale))]")
          print("  Name:        \(loc.attributes?.name ?? "—")")
          print("  Description: \(loc.attributes?.description ?? "—")")
          print()
        }
      }
    }

    // MARK: Export

    struct Export: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Export in-app purchase localizations to a JSON file."
      )

      @Argument(help: "The bundle identifier of the app.")
      var bundleID: String

      @Argument(help: "The product identifier of the in-app purchase.")
      var productID: String

      @Option(name: .long, help: "Output file path.")
      var output: String?

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let iap = try await findIAP(productID: productID, appID: app.id, client: client)

        let locsResponse = try await client.send(
          Resources.v2.inAppPurchases.id(iap.id).inAppPurchaseLocalizations.get(limit: 50)
        )

        var result: [String: ProductLocaleFields] = [:]
        for loc in locsResponse.data {
          guard let locale = loc.attributes?.locale else { continue }
          result[locale] = ProductLocaleFields(
            name: loc.attributes?.name,
            description: loc.attributes?.description
          )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)

        let outputPath = expandPath(
          confirmOutputPath(output ?? "\(productID)-localizations.json", isDirectory: false))
        try data.write(to: URL(fileURLWithPath: outputPath))

        print(green("Exported") + " \(result.count) locale(s) to \(outputPath)")
      }
    }

    // MARK: Import

    struct Import: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Import in-app purchase localizations from a JSON file."
      )

      @Argument(help: "The bundle identifier of the app.")
      var bundleID: String

      @Argument(help: "The product identifier of the in-app purchase.")
      var productID: String

      @Option(name: .long, help: "Path to JSON file.")
      var file: String?

      @Flag(name: .long, help: "Show detailed API responses.")
      var verbose: Bool = false

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes: Bool = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let iap = try await findIAP(productID: productID, appID: app.id, client: client)

        let filePath = try resolveFile(file, extension: "json", prompt: "Select a JSON file")
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let localeUpdates = try JSONDecoder().decode([String: ProductLocaleFields].self, from: data)

        guard !localeUpdates.isEmpty else {
          throw ValidationError("JSON file contains no locale data.")
        }

        print("Importing \(localeUpdates.count) locale(s) for '\(iap.attributes?.name ?? productID)':")
        for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
          print("  [\(localeName(locale))] \(fields.name ?? "—") — \(fields.description?.prefix(60) ?? "—")\(fields.description.map { $0.count > 60 ? "..." : "" } ?? "")")
        }
        print()

        guard confirm("Send updates for \(localeUpdates.count) locale(s)? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        print()

        // Fetch existing localizations
        let locsResponse = try await client.send(
          Resources.v2.inAppPurchases.id(iap.id).inAppPurchaseLocalizations.get(limit: 50)
        )

        let locByLocale = Dictionary(
          locsResponse.data.compactMap { loc in
            loc.attributes?.locale.map { ($0, loc) }
          },
          uniquingKeysWith: { first, _ in first }
        )

        for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
          guard let localization = locByLocale[locale] else {
            guard let name = fields.name else {
              print("  [\(localeName(locale))] Skipped — locale not found in current localizations for the app and \"name\" is required to create it.")
              continue
            }

            guard confirm("  [\(localeName(locale))] Locale not found in current localizations for the app. Create it? [y/N] ") else {
              print("  [\(localeName(locale))] Skipped.")
              continue
            }

            let response = try await client.send(
              Resources.v1.inAppPurchaseLocalizations.post(
                InAppPurchaseLocalizationCreateRequest(
                  data: .init(
                    attributes: .init(
                      name: name,
                      locale: locale,
                      description: fields.description
                    ),
                    relationships: .init(
                      inAppPurchaseV2: .init(data: .init(id: iap.id))
                    )
                  )
                )
              )
            )
            print("  [\(localeName(locale))] \(green("Created."))")

            if verbose {
              let attrs = response.data.attributes
              print("    Response:")
              print("      Locale:      \(attrs?.locale.map { localeName($0) } ?? "—")")
              if let v = attrs?.name { print("      Name:        \(v)") }
              if let v = attrs?.description { print("      Description: \(v.prefix(120))\(v.count > 120 ? "..." : "")") }
            }
            continue
          }

          let response = try await client.send(
            Resources.v1.inAppPurchaseLocalizations.id(localization.id).patch(
              InAppPurchaseLocalizationUpdateRequest(
                data: .init(
                  id: localization.id,
                  attributes: .init(
                    name: fields.name,
                    description: fields.description
                  )
                )
              )
            )
          )
          print("  [\(localeName(locale))] Updated.")

          if verbose {
            let attrs = response.data.attributes
            print("    Response:")
            print("      Locale:      \(attrs?.locale.map { localeName($0) } ?? "—")")
            if let v = attrs?.name { print("      Name:        \(v)") }
            if let v = attrs?.description { print("      Description: \(v.prefix(120))\(v.count > 120 ? "..." : "")") }
          }
        }

        print()
        print("Done.")
      }
    }
  }
}
