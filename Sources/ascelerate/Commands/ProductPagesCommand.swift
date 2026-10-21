import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

struct ProductPagesCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "product-pages",
    abstract: "Manage custom product pages.",
    subcommands: [List.self, Info.self, Create.self, Update.self, Delete.self, Localizations.self, Media.self]
  )

  // MARK: - Shared helpers

  /// Resolves a page name or ID to a page of the app (without its versions).
  static func findProductPage(ref: String, appID: String, client: ASCClient) async throws -> CustomProductPages.Page {
    do {
      return try await CustomProductPages.find(ref, appID: appID, client: client)
    } catch let error as CustomProductPages.LookupError {
      throw ValidationError(error.localizedDescription)
    }
  }

  /// The page's current version (prefers prepareForSubmission, skips replaced).
  static func activeVersionID(pageID: String, client: ASCClient) async throws -> String {
    do {
      return try await CustomProductPages.currentVersion(pageID: pageID, client: client).id
    } catch let error as CustomProductPages.LookupError {
      throw ValidationError(error.localizedDescription)
    }
  }

  /// Resolves a locale to its localization ID on the page's current version.
  static func localizationID(
    forLocale locale: String, pageID: String, client: ASCClient
  ) async throws -> String {
    let versionID = try await activeVersionID(pageID: pageID, client: client)
    guard let localization = try await CustomProductPages.localization(locale: locale, versionID: versionID, client: client)
    else {
      throw ValidationError(
        "No '\(locale)' localization on this page. Add it first with 'product-pages localizations import'.")
    }
    return localization.id
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

      let pages = try await CustomProductPages.list(appID: app.id, client: client)

      if pages.isEmpty {
        print("No custom product pages found.")
        return
      }

      var rows: [[String]] = []
      for page in pages.sorted(by: { $0.name < $1.name }) {
        rows.append([
          page.name.isEmpty ? "—" : page.name,
          page.visible ? green("Visible") : yellow("Hidden"),
          page.url ?? "—",
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

      print("Name:       \(productPage.name.isEmpty ? "—" : productPage.name)")
      print("Visibility: \(productPage.visible ? "Visible" : "Hidden")")
      print("URL:        \(productPage.url ?? "—")")
      print("Page ID:    \(productPage.id)")

      for version in try await CustomProductPages.versions(pageID: productPage.id, client: client) {
        print()
        print("Version \(version.version ?? "—") (\(version.state.map { formatState($0) } ?? "—"))")
        print("  Version ID: \(version.id)")
        if let deepLink = version.deepLink { print("  Deep Link:  \(deepLink)") }

        let localizations = try await CustomProductPages.localizations(versionID: version.id, client: client)
        if !localizations.isEmpty {
          print("  Localizations:")
          for localization in localizations.sorted(by: { $0.locale < $1.locale }) {
            print("    [\(localization.locale.isEmpty ? "—" : localeName(localization.locale))] \(localization.promotionalText ?? "—")")
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

      let created = try await CustomProductPages.create(
        appID: app.id, name: name, locales: [locale], promotionalText: promotionalText, client: client)

      print()
      success("Created", "custom product page '\(name)' (id: \(created.id)).")
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

      guard confirm("Update page '\(productPage.name)'? [y/N] ") else {
        cancelled()
        return
      }

      try await CustomProductPages.update(id: productPage.id, name: name, visible: visible, client: client)

      print()
      success("Updated", "custom product page '\(name ?? productPage.name)'.")
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
      let name = productPage.name

      print("Custom product page: \(name)")
      print()
      guard confirm("Delete this page? [y/N] ") else {
        cancelled()
        return
      }

      try await CustomProductPages.delete(id: productPage.id, client: client)
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

        let localizations = try await CustomProductPages.localizations(versionID: versionID, client: client)
        if localizations.isEmpty {
          print("No localizations found.")
          return
        }

        print("Localizations for '\(productPage.name)':")
        print()
        for localization in localizations.sorted(by: { $0.locale < $1.locale }) {
          print("[\(localeName(localization.locale.isEmpty ? "?" : localization.locale))]")
          print("  Promotional Text: \(localization.promotionalText ?? "—")")
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

        var result: [String: ProductPageLocaleFields] = [:]
        for localization in try await CustomProductPages.localizations(versionID: versionID, client: client) {
          result[localization.locale] = ProductPageLocaleFields(promotionalText: localization.promotionalText)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)

        let pageName = productPage.name
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

        print("Importing \(localeUpdates.count) locale(s) for '\(productPage.name)':")
        for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
          print("  [\(localeName(locale))] \(fields.promotionalText ?? "—")")
        }
        print()

        guard confirm("Send updates for \(localeUpdates.count) locale(s)? [y/N] ") else {
          cancelled()
          return
        }
        print()

        let byLocale = Dictionary(
          try await CustomProductPages.localizations(versionID: versionID, client: client).map { ($0.locale, $0) },
          uniquingKeysWith: { first, _ in first })

        for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
          if let existing = byLocale[locale] {
            // A locale without promotional text in the file is left as it is.
            guard let text = fields.promotionalText else {
              print("  [\(localeName(locale))] Unchanged (no promotional text in the file).")
              continue
            }
            let updated = try await CustomProductPages.updateLocalization(id: existing.id, promotionalText: text, client: client)
            print("  [\(localeName(locale))] Updated.")
            if verbose {
              print("    Promotional Text: \(updated.promotionalText ?? "—")")
            }
          } else {
            guard confirm("  [\(localeName(locale))] Locale not present. Create it? [y/N] ") else {
              print("  [\(localeName(locale))] Skipped.")
              continue
            }
            let created = try await CustomProductPages.createLocalization(
              versionID: versionID, locale: locale, promotionalText: fields.promotionalText, client: client)
            print("  [\(localeName(locale))] \(green("Created."))")
            if verbose {
              print("    Promotional Text: \(created.promotionalText ?? "—")")
            }
          }
        }

        print()
        print("Done.")
      }
    }
  }

  // MARK: - Media

  struct Media: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "media",
      abstract: "Manage custom product page screenshots and app previews.",
      subcommands: [List.self, Upload.self, Delete.self]
    )

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "List screenshots and app previews across the page's localizations."
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

        var rows: [[String]] = []
        for localization in try await CustomProductPages.localizations(versionID: versionID, client: client)
          .sorted(by: { $0.locale < $1.locale }) {
          rows += try await LocalizationMedia.rows(
            locale: localization.locale.isEmpty ? "?" : localization.locale,
            on: .productPageLocalization(localization.id), client: client)
        }

        if rows.isEmpty {
          print("No screenshots or previews found.")
          return
        }
        Table.print(headers: ["Locale", "Kind", "Type", "State", "Media ID"], rows: rows)
      }
    }

    struct Upload: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Upload a screenshot (.png/.jpg) or app preview (.mp4/.mov) to a localization.",
        discussion: LocalizationMedia.uploadDiscussion
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The page name or ID.")
      var page: String

      @Option(name: .long, help: "Locale to attach media to (e.g. en-US).")
      var locale: String

      @Option(name: .long, help: "Screenshot display type for images (e.g. APP_IPHONE_67).")
      var displayType: String?

      @Option(name: .long, help: "Preview type for videos (e.g. APP_IPHONE_67).")
      var previewType: String?

      @Option(name: .long, help: "Preview frame timecode for app previews, hh:mm:ss:frame (e.g. 00:00:03:00).")
      var previewFrame: String?

      @Argument(help: "Path to the media file.",
                completion: .file(extensions: ["png", "jpg", "jpeg", "mp4", "mov"]))
      var file: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let productPage = try await ProductPagesCommand.findProductPage(
          ref: page, appID: app.id, client: client)
        let locID = try await ProductPagesCommand.localizationID(
          forLocale: locale, pageID: productPage.id, client: client)

        try await LocalizationMedia.upload(
          file: file, displayType: displayType, previewType: previewType, previewFrame: previewFrame, appID: app.id,
          context: [("Page", productPage.name), ("Locale", localeName(locale))], client: client,
          owner: .productPageLocalization(locID))
      }
    }

    struct Delete: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Delete a screenshot or app preview."
      )

      @Argument(help: "The bundle identifier of the app.",
                completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
      var bundleID: String

      @Argument(help: "The page name or ID.")
      var page: String

      @Argument(help: "The media ID (from `product-pages media list`).")
      var mediaID: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        let productPage = try await ProductPagesCommand.findProductPage(
          ref: page, appID: app.id, client: client)
        let versionID = try await ProductPagesCommand.activeVersionID(
          pageID: productPage.id, client: client)

        let localizations = try await CustomProductPages.localizations(versionID: versionID, client: client)
        try await LocalizationMedia.delete(
          mediaID: mediaID, among: localizations.map { .productPageLocalization($0.id) }, client: client)
      }
    }
  }
}
