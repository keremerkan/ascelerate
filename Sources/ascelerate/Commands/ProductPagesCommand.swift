import AppStoreAPI
import AppStoreConnect
import ArgumentParser
import Foundation

struct ProductPagesCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "product-pages",
    abstract: "Manage custom product pages.",
    subcommands: [List.self, Info.self, Create.self, Update.self, Delete.self, Localizations.self]
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

  /// Picks the editable version of a page (prefers prepareForSubmission, skips replaced).
  static func activeVersionID(
    pageID: String, client: AppStoreConnectClient
  ) async throws -> String {
    let versions = try await client.send(
      Resources.v1.appCustomProductPages.id(pageID).appCustomProductPageVersions.get(limit: 50))
    guard !versions.data.isEmpty else {
      throw ValidationError("This custom product page has no versions.")
    }
    if let editable = versions.data.first(where: {
      $0.attributes?.state == .prepareForSubmission
    }) {
      return editable.id
    }
    if let live = versions.data.first(where: {
      $0.attributes?.state != .replacedWithNewVersion
    }) {
      return live.id
    }
    return versions.data[0].id
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

  // MARK: - Localizations

  /// JSON schema for custom product page localizations.
  struct ProductPageLocaleFields: Codable {
    var promotionalText: String?
  }

  struct Localizations: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "localizations",
      abstract: "View, export, and import custom product page localizations (promotional text).",
      subcommands: [View.self, Export.self, Import.self]
    )

    struct View: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "View localizations for a custom product page."
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
        let versionID = try await ProductPagesCommand.activeVersionID(
          pageID: productPage.id, client: client)

        let resp = try await client.send(
          Resources.v1.appCustomProductPageVersions.id(versionID)
            .appCustomProductPageLocalizations.get(limit: 50))
        if resp.data.isEmpty {
          print("No localizations found.")
          return
        }

        print("Localizations for '\(productPage.attributes?.name ?? page)':")
        print()
        for loc in resp.data.sorted(by: {
          ($0.attributes?.locale ?? "") < ($1.attributes?.locale ?? "")
        }) {
          print("[\(localeName(loc.attributes?.locale ?? "?"))]")
          print("  Promotional Text: \(loc.attributes?.promotionalText ?? "—")")
          print()
        }
      }
    }

    struct Export: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Export custom product page localizations to a JSON file."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The page name or ID.")
      var page: String

      @Option(name: .long, help: "Output file path.",
              completion: .file(extensions: ["json"]))
      var output: String?

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let productPage = try await ProductPagesCommand.findProductPage(
          ref: page, appID: app.id, client: client)
        let versionID = try await ProductPagesCommand.activeVersionID(
          pageID: productPage.id, client: client)

        let resp = try await client.send(
          Resources.v1.appCustomProductPageVersions.id(versionID)
            .appCustomProductPageLocalizations.get(limit: 50))

        var result: [String: ProductPageLocaleFields] = [:]
        for loc in resp.data {
          guard let locale = loc.attributes?.locale else { continue }
          result[locale] = ProductPageLocaleFields(
            promotionalText: loc.attributes?.promotionalText)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)

        let pageName = productPage.attributes?.name ?? "page"
        let outputPath = expandPath(
          confirmOutputPath(output ?? "\(pageName)-localizations.json", isDirectory: false))
        try data.write(to: URL(fileURLWithPath: outputPath))

        print(green("Exported") + " \(result.count) locale(s) to \(outputPath)")
      }
    }

    struct Import: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Import custom product page localizations from a JSON file."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The page name or ID.")
      var page: String

      @Option(name: .long, help: "Path to JSON file.",
              completion: .file(extensions: ["json"]))
      var file: String?

      @Flag(name: .long, help: "Show detailed API responses.")
      var verbose: Bool = false

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes: Bool = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let productPage = try await ProductPagesCommand.findProductPage(
          ref: page, appID: app.id, client: client)
        let versionID = try await ProductPagesCommand.activeVersionID(
          pageID: productPage.id, client: client)

        let filePath = try resolveFile(file, extension: "json", prompt: "Select a JSON file")
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let localeUpdates = try JSONDecoder().decode(
          [String: ProductPageLocaleFields].self, from: data)

        guard !localeUpdates.isEmpty else {
          throw ValidationError("JSON file contains no locale data.")
        }

        print("Importing \(localeUpdates.count) locale(s) for '\(productPage.attributes?.name ?? page)':")
        for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
          print("  [\(localeName(locale))] \(fields.promotionalText ?? "—")")
        }
        print()

        guard confirm("Send updates for \(localeUpdates.count) locale(s)? [y/N] ") else {
          cancelled()
          return
        }
        print()

        let existing = try await client.send(
          Resources.v1.appCustomProductPageVersions.id(versionID)
            .appCustomProductPageLocalizations.get(limit: 50))
        let byLocale = Dictionary(
          existing.data.compactMap { loc in loc.attributes?.locale.map { ($0, loc) } },
          uniquingKeysWith: { first, _ in first })

        for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
          if let loc = byLocale[locale] {
            let response = try await client.send(
              Resources.v1.appCustomProductPageLocalizations.id(loc.id).patch(
                AppCustomProductPageLocalizationUpdateRequest(
                  data: .init(
                    id: loc.id,
                    attributes: .init(promotionalText: fields.promotionalText)
                  )
                )))
            print("  [\(localeName(locale))] Updated.")
            if verbose {
              print("    Promotional Text: \(response.data.attributes?.promotionalText ?? "—")")
            }
          } else {
            guard confirm("  [\(localeName(locale))] Locale not present. Create it? [y/N] ") else {
              print("  [\(localeName(locale))] Skipped.")
              continue
            }
            let response = try await client.send(
              Resources.v1.appCustomProductPageLocalizations.post(
                AppCustomProductPageLocalizationCreateRequest(
                  data: .init(
                    attributes: .init(locale: locale, promotionalText: fields.promotionalText),
                    relationships: .init(
                      appCustomProductPageVersion: .init(data: .init(id: versionID)))
                  )
                )))
            print("  [\(localeName(locale))] \(green("Created."))")
            if verbose {
              print("    Promotional Text: \(response.data.attributes?.promotionalText ?? "—")")
            }
          }
        }

        print()
        print("Done.")
      }
    }
  }
}
