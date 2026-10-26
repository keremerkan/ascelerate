import AppleAdsClient
import AscelerateAds
import ArgumentParser
import AscelerateCore
import Foundation

extension AdsCommand {
  // MARK: - Product pages

  struct ProductPages: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "product-pages",
      abstract: "The app's product pages Apple Ads can send taps to (default, custom, optimization tests)."
    )

    @Option(name: .long, help: "The app (bundle ID or alias).")
    var app: String

    @OptionGroup var jsonOption: JSONOption

    private struct Entry: Encodable {
      let id: String
      let name: String?
      let state: String?
      let deepLink: String?
    }

    func run() async throws {
      jsonOption.activate()
      let ads = try Ads.config()
      let app = try await appStoreApp(bundleID: self.app)
      let pages = try await Ads.withClient(ads) { try await Ads.productPages(app: app.id, ads, client: $0) }
      let entries = pages.map { Entry(id: $0.id ?? "-", name: $0.name, state: $0.state, deepLink: $0.deepLink) }
      if jsonOption.json { try printJSON(entries); return }
      print("Product pages of \(app.name)")
      print()
      Table.print(
        headers: ["ID", "Name", "State"],
        rows: entries.map { [$0.id, $0.name ?? "-", $0.state.map { formatState($0) } ?? "-"] }
      )
      print("\nUse a page's name or ID with 'ascelerate ads ads create --product-page', or 'default' for the main listing.")
    }
  }

  // MARK: - Ads

  struct Ads_: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "ads",
      abstract: "Ads: which product page each ad group sends taps to (one serving ad per ad group).",
      subcommands: [List.self, Create.self, Pause.self, Resume.self],
      defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "List ads by campaign and ad group, with their product page and review state.")

      @OptionGroup var scope: Ads.ScopeOptions
      @OptionGroup var jsonOption: JSONOption

      private struct Entry: Encodable {
        let id: Int64
        let name: String
        let campaignId: Int64?
        let campaignName: String
        let adGroupId: Int64?
        let adGroupName: String?
        let status: String?
        let displayStatus: String?
        let systemStatusReasons: [String]?
        let creativeId: Int64?
        /// DEFAULT_PRODUCT_PAGE or CUSTOM_PRODUCT_PAGE.
        let creativeType: String?
        let productPageId: String?
        let productPageName: String?
      }

      func run() async throws {
        jsonOption.activate()
        let ads = try Ads.config()
        let scope = try await self.scope.resolve(ads)
        let entries = try await Ads.withClient(ads) { client in
          let creatives = try await Ads.creatives(ads, client: client)
          let appIDs = Set(scope.campaigns.compactMap(\.promotedObjectId))
          var pageNames: [String: String] = [:]
          for appID in appIDs {
            for page in try await Ads.productPages(app: appID, ads, client: client) {
              if let id = page.id { pageNames[id] = page.name }
            }
          }
          return try await Ads.perCampaign(scope) { campaignID in
            async let groups = Ads.adGroups(campaignID: campaignID, ads, client: client)
            async let campaignAds = Ads.ads(campaignID: campaignID, ads, client: client)
            let names = Dictionary(try await groups.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            return try await campaignAds.map { ad in (ad, names[ad.adGroupId] ?? nil) }
          }.map { (ad: Components.Schemas.Ad, groupName: String?) in
            let creative = creatives.first { $0.id == ad.creativeId }
            let pageID = creative?.destination?.value1.parameters?.value1.productPageId
            return Entry(
              id: ad.id ?? 0, name: ad.name ?? "-", campaignId: ad.campaignId,
              campaignName: scope.campaignName(ad.campaignId ?? 0), adGroupId: ad.adGroupId, adGroupName: groupName,
              status: ad.status?.value1.rawValue, displayStatus: ad.displayStatus?.value1.rawValue,
              systemStatusReasons: ad.systemStatusReasons?.map { $0.value1.rawValue },
              creativeId: ad.creativeId, creativeType: creative?.creativeType?.value1.rawValue,
              productPageId: pageID, productPageName: pageID.flatMap { pageNames[$0] }
            )
          }
        }

        if jsonOption.json { try printJSON(entries); return }
        var rows: [[String]] = []
        for (campaign, items) in Ads.grouped(entries, by: \.campaignName) {
          if !rows.isEmpty { rows.append(["", "", "", "", ""]) }
          rows.append([bold(campaign), "", "", "", ""])
          for e in items {
            let page: String = e.creativeType == "DEFAULT_PRODUCT_PAGE" ? "Default" : (e.productPageName ?? e.productPageId ?? "-")
            let status: String = e.displayStatus.map(Ads.formatStatus) ?? "-"
            let reasons: String = (e.systemStatusReasons ?? []).map { formatState($0) }.joined(separator: ", ")
            rows.append(["  " + e.name, e.adGroupName ?? "-", page, status, reasons])
          }
        }
        Table.print(headers: ["Ad", "Ad Group", "Product Page", "Status", "Why Not Running"], rows: rows)
      }
    }

    struct Create: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Create an ad that sends an ad group's taps to a product page (Apple reviews it before it serves).",
        discussion: """
          Only one ad per ad group can serve. With --enabled the ad group's serving ad is paused first; \\
          otherwise the new ad is created paused. To show a custom product page for some searches only, \\
          put their keywords in an ad group of their own ('ads adgroups create', 'ads keywords add').
          """
      )

      @Option(name: .long, help: "Campaign name or ID.")
      var campaign: String

      @Option(name: .long, help: "Ad group name or ID (needed when the campaign has more than one).")
      var adGroup: String?

      @Option(name: .long, help: "Custom product page name or ID (see 'ads product-pages'), or 'default'.")
      var productPage: String

      @Option(name: .long, help: "Ad name (default: the product page's name).")
      var name: String?

      @Flag(name: .long, help: "Serve it right away, pausing the ad group's current ad.")
      var enabled = false

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let ads = try Ads.config()
        try await Ads.withClient(ads) { client in
          let campaign = try await Ads.campaign(self.campaign, ads, client: client)
          guard let appID = campaign.promotedObjectId else { throw ValidationError("The campaign has no app.") }
          let group = try Ads.adGroup(adGroup, in: await Ads.adGroups(campaignID: campaign.id ?? 0, ads, client: client))

          // The product page and an existing creative for it (creatives are reusable account-wide).
          let isDefault = productPage.lowercased() == "default"
          var pageID: String?
          var pageName = "Default product page"
          if !isDefault {
            let pages = try await Ads.productPages(app: appID, ads, client: client)
            guard let page = pages.first(where: { $0.id == productPage || $0.name?.caseInsensitiveCompare(productPage) == .orderedSame }) else {
              guard !pages.isEmpty else {
                throw ValidationError("The app has no custom product pages; create them in App Store Connect ('ascelerate product-pages create').")
              }
              let names = pages.compactMap(\.name).sorted().map { "  - \($0)" }.joined(separator: "\n")
              throw ValidationError("No product page '\(productPage)'. Pages:\n\(names)")
            }
            pageID = page.id
            pageName = page.name ?? page.id ?? "-"
          }
          let creativeType: Components.Schemas.CreativeType = isDefault ? .defaultProductPage : .customProductPage
          let existing = try await Ads.creatives(ads, client: client).first { c in
            c.creativeType?.value1 == creativeType
              && c.destination?.value1.parameters?.value1.adamId == appID
              && c.destination?.value1.parameters?.value1.productPageId == pageID
          }
          let adName = name ?? pageName
          let groupAds = try await Ads.ads(campaignID: campaign.id ?? 0, ads, client: client).filter { $0.adGroupId == group.id }
          let serving = groupAds.filter { $0.status?.value1 == .enabled }

          print("Creating ad '\(adName)' in \(campaign.name ?? "-") › \(group.name ?? "-"), sending taps to \(pageName)"
            + (existing == nil ? " (new creative)" : "") + ".")
          if enabled, !serving.isEmpty {
            print("It will serve after Apple's review; pausing the current ad: \(serving.map { $0.name ?? "-" }.joined(separator: ", ")).")
          } else if !enabled {
            print("Created paused; resume it with 'ascelerate ads ads resume'.")
          }
          guard confirm("Create it? [y/N] ") else {
            print(yellow("Cancelled."))
            return
          }

          var creativeID = existing?.id
          if creativeID == nil {
            let created = try await unlessDryRunStopped {
              try await client.postCreatives(
                headers: .init(xApContext: Ads.context(ads)),
                body: .json(.init(
                  name: adName, creativeType: .init(value1: creativeType),
                  destination: .init(value1: .init(
                    destinationType: .init(value1: .appStoreProductPage),
                    parameters: .init(value1: .init(adamId: appID, productPageId: pageID))
                  ))
                ))
              ).ok.body.json.result
            }
            creativeID = created??.id
          }
          if enabled {
            for ad in serving { try await Ads.setAdStatus(ad, .paused, ads, client: client) }
          }
          let ad = try await unlessDryRunStopped {
            try await client.postAds(
              headers: .init(xApContext: Ads.context(ads)),
              body: .json(.init(
                adGroupId: group.id ?? 0, creativeId: creativeID ?? 0, name: adName,
                status: .init(value1: enabled ? .enabled : .paused)
              ))
            ).ok.body.json.result
          }
          if let ad { print(green("Created") + " ad '\(adName)' (ID \(ad?.id.map(String.init) ?? "-")).") }
        }
      }
    }

    struct Pause: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Pause an ad.")
      @Option(name: .long, help: "Campaign name or ID.") var campaign: String
      @Argument(help: "Ad name or ID.") var ad: String
      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.") var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        try await AdsCommand.Ads_.change(campaign: campaign, ad: ad, to: .paused)
      }
    }

    struct Resume: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Resume an ad (pausing the ad that serves in its ad group now).")
      @Option(name: .long, help: "Campaign name or ID.") var campaign: String
      @Argument(help: "Ad name or ID.") var ad: String
      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.") var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        try await AdsCommand.Ads_.change(campaign: campaign, ad: ad, to: .enabled)
      }
    }

    static func change(campaign ref: String, ad ref2: String, to status: Components.Schemas.AdStatus) async throws {
      let ads = try Ads.config()
      try await Ads.withClient(ads) { client in
        let campaign = try await Ads.campaign(ref, ads, client: client)
        let all = try await Ads.ads(campaignID: campaign.id ?? 0, ads, client: client)
        guard let ad = all.first(where: { $0.id.map(String.init) == ref2 || $0.name?.caseInsensitiveCompare(ref2) == .orderedSame }) else {
          let names = all.compactMap(\.name).sorted().map { "  - \($0)" }.joined(separator: "\n")
          throw ValidationError("No ad '\(ref2)' in \(campaign.name ?? "-"). Ads:\n\(names)")
        }
        guard ad.status?.value1 != status else {
          print("\(ad.name ?? "-") is already \(formatState(status.rawValue).lowercased()).")
          return
        }
        // Only one ad per ad group serves: resuming one pauses the other.
        let others = status == .enabled
          ? all.filter { $0.adGroupId == ad.adGroupId && $0.id != ad.id && $0.status?.value1 == .enabled } : []
        let pausing = others.isEmpty ? "" : ", pausing \(others.map { $0.name ?? "-" }.joined(separator: ", "))"
        let verb = status == .enabled ? "Resume" : "Pause"
        guard confirm("\(verb) \(ad.name ?? "-")\(pausing)? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        for other in others { try await Ads.setAdStatus(other, .paused, ads, client: client) }
        try await Ads.setAdStatus(ad, status, ads, client: client)
      }
    }
  }
}

extension Ads {
  /// The app's product pages (default, custom, optimization tests) as Apple Ads sees them.
  static func productPages(app: String, _ ads: AdsConfig, client: Client) async throws -> [Components.Schemas.ProductPageDetails] {
    try await query(Components.Schemas.ProductPageDetails.self) { pagination in
      try await client.queryProductPages(
        headers: .init(xApContext: context(ads)),
        body: .json(.init(filters: [filter("adamId", equals: Int64(app) ?? 0)], pagination: pagination))
      ).ok.body.json.value1
    }
  }

  /// The ad account's creatives (deleted ones left out).
  static func creatives(_ ads: AdsConfig, client: Client) async throws -> [Components.Schemas.Creative] {
    try await query(Components.Schemas.Creative.self) { pagination in
      try await client.postCreativesQuery(
        headers: .init(xApContext: context(ads)), body: .json(.init(pagination: pagination))
      ).ok.body.json.value1
    }.filter { $0.deleted != true }
  }

  /// The campaign's ads (deleted ones left out).
  static func ads(campaignID: Int64, _ ads: AdsConfig, client: Client) async throws -> [Components.Schemas.Ad] {
    try await query(Components.Schemas.Ad.self) { pagination in
      try await client.postAdsQuery(
        headers: .init(xApContext: context(ads)),
        body: .json(.init(filters: [filter("campaignId", equals: campaignID)], pagination: pagination))
      ).ok.body.json.value1
    }.filter { $0.deleted != true }
  }

  /// Sets an ad's status (one request; shown and skipped under dry run).
  static func setAdStatus(_ ad: Components.Schemas.Ad, _ status: Components.Schemas.AdStatus, _ ads: AdsConfig, client: Client) async throws {
    guard try await unlessDryRunStopped({
      try await client.putAdsId(
        path: .init(id: String(ad.id ?? 0)), headers: .init(xApContext: context(ads)),
        body: .json(.init(status: .init(value1: status)))
      ).ok
    }) != nil else { return }
    print(green(status == .enabled ? "Resumed" : "Paused") + " \(ad.name ?? "-").")
  }
}
