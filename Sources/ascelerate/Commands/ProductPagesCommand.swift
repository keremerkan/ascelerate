import AppStoreAPI
import AppStoreConnect
import ArgumentParser
import Foundation

struct ProductPagesCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "product-pages",
    abstract: "Manage custom product pages.",
    subcommands: [List.self, Info.self, Create.self, Update.self, Delete.self]
  )

  // MARK: - Shared helpers

  /// Resolves a page name or ID to an AppCustomProductPage for the given app.
  static func findProductPage(
    ref: String, appID: String, client: AppStoreConnectClient
  ) async throws -> AppCustomProductPage {
    var pages: [AppCustomProductPage] = []
    for try await page in client.pages(
      Resources.v1.apps.id(appID).appCustomProductPages.get(limit: 200)
    ) {
      pages.append(contentsOf: page.data)
    }
    if let match = pages.first(where: { $0.attributes?.name == ref || $0.id == ref }) {
      return match
    }
    throw ValidationError("No custom product page '\(ref)' found for this app.")
  }

  // MARK: - List

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List custom product pages for an app."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      var pages: [AppCustomProductPage] = []
      for try await page in client.pages(
        Resources.v1.apps.id(app.id).appCustomProductPages.get(limit: 200)
      ) {
        pages.append(contentsOf: page.data)
      }

      if pages.isEmpty {
        print("No custom product pages found.")
        return
      }

      var rows: [[String]] = []
      for page in pages.sorted(by: { ($0.attributes?.name ?? "") < ($1.attributes?.name ?? "") }) {
        let a = page.attributes
        rows.append([
          a?.name ?? "—",
          a?.isVisible == true ? green("Visible") : yellow("Hidden"),
          a?.url.map { "\($0)" } ?? "—",
          page.id,
        ])
      }

      Table.print(headers: ["Name", "Visibility", "URL", "Page ID"], rows: rows)
    }
  }

  // MARK: - Info

  struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Show a custom product page's versions and localizations."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Argument(help: "The page name or ID.")
    var page: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let productPage = try await ProductPagesCommand.findProductPage(
        ref: page, appID: app.id, client: client)
      let a = productPage.attributes

      print("Name:       \(a?.name ?? "—")")
      print("Visibility: \(a?.isVisible == true ? "Visible" : "Hidden")")
      print("URL:        \(a?.url.map { "\($0)" } ?? "—")")
      print("Page ID:    \(productPage.id)")

      let versions = try await client.send(
        Resources.v1.appCustomProductPages.id(productPage.id).appCustomProductPageVersions.get(
          limit: 50))
      for version in versions.data {
        print()
        print("Version \(version.attributes?.version ?? "—") (\(version.attributes?.state.map { formatState($0) } ?? "—"))")
        print("  Version ID: \(version.id)")
        if let deepLink = version.attributes?.deepLink { print("  Deep Link:  \(deepLink)") }

        let locs = try await client.send(
          Resources.v1.appCustomProductPageVersions.id(version.id)
            .appCustomProductPageLocalizations.get(limit: 50))
        if !locs.data.isEmpty {
          print("  Localizations:")
          for loc in locs.data.sorted(by: {
            ($0.attributes?.locale ?? "") < ($1.attributes?.locale ?? "")
          }) {
            let promo = loc.attributes?.promotionalText
            print("    [\(loc.attributes?.locale.map { localeName($0) } ?? "—")] \(promo ?? "—")")
          }
        }
      }
    }
  }

  // MARK: - Create

  struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Create a custom product page with an initial localization.",
      discussion: """
        The App Store Connect API requires a page to be created together with a first
        version and at least one localization, so --locale is required. Add more locales
        afterward with `product-pages localizations import`.
        """
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .long, help: "Name for the custom product page (required).")
    var name: String

    @Option(name: .long, help: "Locale for the initial localization (e.g. en-US, required).")
    var locale: String

    @Option(name: .long, help: "Promotional text for the initial localization.")
    var promotionalText: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      print("Create custom product page:")
      print("  Name:   \(name)")
      print("  Locale: \(localeName(locale))")
      print()
      guard confirm("Create this page? [y/N] ") else {
        cancelled()
        return
      }

      // Compound create: the page references an inline version, which references an inline
      // localization. Local IDs (the API requires the `${local-id}` format) link them within
      // the single request.
      let versionLID = "${ascelerate-version}"
      let localizationLID = "${ascelerate-localization}"

      let response = try await client.send(
        Resources.v1.appCustomProductPages.post(
          AppCustomProductPageCreateRequest(
            data: .init(
              attributes: .init(name: name),
              relationships: .init(
                app: .init(data: .init(id: app.id)),
                appCustomProductPageVersions: .init(data: [.init(id: versionLID)])
              )
            ),
            included: [
              .appCustomProductPageVersionInlineCreate(
                .init(
                  id: versionLID,
                  relationships: .init(
                    appCustomProductPageLocalizations: .init(data: [.init(id: localizationLID)])
                  )
                )),
              .appCustomProductPageLocalizationInlineCreate(
                .init(
                  id: localizationLID,
                  attributes: .init(locale: locale, promotionalText: promotionalText)
                )),
            ]
          )
        ))

      print()
      success("Created", "custom product page '\(name)' (id: \(response.data.id)).")
    }
  }

  // MARK: - Update

  struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Rename a custom product page or toggle its visibility."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Argument(help: "The page name or ID.")
    var page: String

    @Option(name: .long, help: "New name.")
    var name: String?

    @Option(name: .long, help: "Visibility on the App Store (true/false).")
    var visible: Bool?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      guard name != nil || visible != nil else {
        throw ValidationError("Provide --name and/or --visible to update.")
      }

      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let productPage = try await ProductPagesCommand.findProductPage(
        ref: page, appID: app.id, client: client)

      guard confirm("Update page '\(productPage.attributes?.name ?? page)'? [y/N] ") else {
        cancelled()
        return
      }

      _ = try await client.send(
        Resources.v1.appCustomProductPages.id(productPage.id).patch(
          AppCustomProductPageUpdateRequest(
            data: .init(
              id: productPage.id,
              attributes: .init(name: name, isVisible: visible)
            )
          )
        ))

      print()
      success("Updated", "custom product page '\(name ?? productPage.attributes?.name ?? page)'.")
    }
  }

  // MARK: - Delete

  struct Delete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Delete a custom product page."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Argument(help: "The page name or ID.")
    var page: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let productPage = try await ProductPagesCommand.findProductPage(
        ref: page, appID: app.id, client: client)
      let name = productPage.attributes?.name ?? page

      print("Custom product page: \(name)")
      print()
      guard confirm("Delete this page? [y/N] ") else {
        cancelled()
        return
      }

      _ = try await client.send(Resources.v1.appCustomProductPages.id(productPage.id).delete)
      print()
      success("Deleted", "custom product page '\(name)'.")
    }
  }
}
