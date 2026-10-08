import ArgumentParser
import ASCKit
import Foundation

struct ProductPagesCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "product-pages",
    abstract: "Manage custom product pages.",
    subcommands: [List.self, Info.self, Create.self, Update.self, Delete.self, Localizations.self, Media.self]
  )

  // MARK: - Shared helpers

  /// Resolves a page name or ID to an AppCustomProductPage for the given app.
  static func findProductPage(ref: String, appID: String, client: ASCClient) async throws -> Components.Schemas.AppCustomProductPage {
    let pages = try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.appsAppCustomProductPagesGetToManyRelated(path: .init(id: appID), query: .init(limit: 200)).ok.body.json
    }.flatMap(\.data)
    if let match = pages.first(where: { $0.attributes?.name == ref || $0.id == ref }) {
      return match
    }
    throw ValidationError("No custom product page '\(ref)' found for this app.")
  }

  /// Picks the editable version of a page (prefers prepareForSubmission, skips replaced).
  static func activeVersionID(pageID: String, client: ASCClient) async throws -> String {
    let versions = try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.appCustomProductPagesAppCustomProductPageVersionsGetToManyRelated(
        path: .init(id: pageID), query: .init(limit: 50)
      ).ok.body.json
    }.flatMap(\.data)
    guard !versions.isEmpty else {
      throw ValidationError("This custom product page has no versions.")
    }
    return (versions.first { $0.attributes?.state == "PREPARE_FOR_SUBMISSION" }
      ?? versions.first { $0.attributes?.state != "REPLACED_WITH_NEW_VERSION" }
      ?? versions[0]).id
  }

  /// Resolves a locale to its localization ID on the page's editable version.
  static func localizationID(
    forLocale locale: String, pageID: String, client: ASCClient
  ) async throws -> String {
    let versionID = try await activeVersionID(pageID: pageID, client: client)
    let locs = try await client.appCustomProductPageVersionsAppCustomProductPageLocalizationsGetToManyRelated(
      path: .init(id: versionID), query: .init(limit: 50)
    ).ok.body.json
    guard let loc = locs.data.first(where: { $0.attributes?.locale == locale }) else {
      throw ValidationError(
        "No '\(locale)' localization on this page. Add it first with 'product-pages localizations import'.")
    }
    return loc.id
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

      let pages = try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.appsAppCustomProductPagesGetToManyRelated(path: .init(id: app.id), query: .init(limit: 200)).ok.body.json
      }.flatMap(\.data)

      if pages.isEmpty {
        print("No custom product pages found.")
        return
      }

      var rows: [[String]] = []
      for page in pages.sorted(by: { ($0.attributes?.name ?? "") < ($1.attributes?.name ?? "") }) {
        let a = page.attributes
        rows.append([
          a?.name ?? "—",
          a?.visible == true ? green("Visible") : yellow("Hidden"),
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
      print("Visibility: \(a?.visible == true ? "Visible" : "Hidden")")
      print("URL:        \(a?.url.map { "\($0)" } ?? "—")")
      print("Page ID:    \(productPage.id)")

      let versions = try await client.appCustomProductPagesAppCustomProductPageVersionsGetToManyRelated(
        path: .init(id: productPage.id), query: .init(limit: 50)
      ).ok.body.json
      for version in versions.data {
        print()
        print("Version \(version.attributes?.version ?? "—") (\(version.attributes?.state.map { formatState($0) } ?? "—"))")
        print("  Version ID: \(version.id)")
        if let deepLink = version.attributes?.deepLink { print("  Deep Link:  \(deepLink)") }

        let locs = try await client.appCustomProductPageVersionsAppCustomProductPageLocalizationsGetToManyRelated(
          path: .init(id: version.id), query: .init(limit: 50)
        ).ok.body.json
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

      let response = try await client.appCustomProductPagesCreateInstance(body: .json(.init(
        data: .init(
          attributes: .init(name: name),
          relationships: .init(
            app: .init(data: .init(id: app.id, _type: "apps")),
            appCustomProductPageVersions: .init(data: [.init(id: versionLID, _type: "appCustomProductPageVersions")])
          ),
          _type: "appCustomProductPages"
        ),
        included: [
          .AppCustomProductPageVersionInlineCreate(.init(
            id: versionLID,
            relationships: .init(
              appCustomProductPageLocalizations: .init(
                data: [.init(id: localizationLID, _type: "appCustomProductPageLocalizations")])
            ),
            _type: "appCustomProductPageVersions"
          )),
          .AppCustomProductPageLocalizationInlineCreate(.init(
            attributes: .init(locale: locale, promotionalText: promotionalText),
            id: localizationLID,
            _type: "appCustomProductPageLocalizations"
          )),
        ]
      ))).created.body.json

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

      _ = try await client.appCustomProductPagesUpdateInstance(
        path: .init(id: productPage.id),
        body: .json(.init(data: .init(
          attributes: .init(name: name, visible: visible), id: productPage.id, _type: "appCustomProductPages")))
      ).ok

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

      _ = try await client.appCustomProductPagesDeleteInstance(path: .init(id: productPage.id)).noContent
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

        let resp = try await client.appCustomProductPageVersionsAppCustomProductPageLocalizationsGetToManyRelated(
          path: .init(id: versionID), query: .init(limit: 50)
        ).ok.body.json
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

        let resp = try await client.appCustomProductPageVersionsAppCustomProductPageLocalizationsGetToManyRelated(
          path: .init(id: versionID), query: .init(limit: 50)
        ).ok.body.json

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

        let existing = try await client.appCustomProductPageVersionsAppCustomProductPageLocalizationsGetToManyRelated(
          path: .init(id: versionID), query: .init(limit: 50)
        ).ok.body.json
        let byLocale = Dictionary(
          existing.data.compactMap { loc in loc.attributes?.locale.map { ($0, loc) } },
          uniquingKeysWith: { first, _ in first })

        for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
          if let loc = byLocale[locale] {
            let response = try await client.appCustomProductPageLocalizationsUpdateInstance(
              path: .init(id: loc.id),
              body: .json(.init(data: .init(
                attributes: .init(promotionalText: fields.promotionalText), id: loc.id,
                _type: "appCustomProductPageLocalizations")))
            ).ok.body.json
            print("  [\(localeName(locale))] Updated.")
            if verbose {
              print("    Promotional Text: \(response.data.attributes?.promotionalText ?? "—")")
            }
          } else {
            guard confirm("  [\(localeName(locale))] Locale not present. Create it? [y/N] ") else {
              print("  [\(localeName(locale))] Skipped.")
              continue
            }
            let response = try await client.appCustomProductPageLocalizationsCreateInstance(body: .json(.init(data: .init(
              attributes: .init(locale: locale, promotionalText: fields.promotionalText),
              relationships: .init(
                appCustomProductPageVersion: .init(data: .init(id: versionID, _type: "appCustomProductPageVersions"))),
              _type: "appCustomProductPageLocalizations"
            )))).created.body.json
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

        let locs = try await client.appCustomProductPageVersionsAppCustomProductPageLocalizationsGetToManyRelated(
          path: .init(id: versionID), query: .init(limit: 50)
        ).ok.body.json

        var rows: [[String]] = []
        for loc in locs.data.sorted(by: {
          ($0.attributes?.locale ?? "") < ($1.attributes?.locale ?? "")
        }) {
          let locale = loc.attributes?.locale ?? "?"
          let sets = try await client.appCustomProductPageLocalizationsAppScreenshotSetsGetToManyRelated(
            path: .init(id: loc.id), query: .init(limit: 50)
          ).ok.body.json
          for set in sets.data {
            // Raw, as `--display-type` takes it and the media commands print it.
            let displayType = set.attributes?.screenshotDisplayType ?? "—"
            let shots = try await client.appScreenshotSetsAppScreenshotsGetToManyRelated(
              path: .init(id: set.id), query: .init(limit: 50)
            ).ok.body.json
            for s in shots.data {
              rows.append([
                locale, "Screenshot", displayType,
                s.attributes?.assetDeliveryState?.state.map { formatState($0) } ?? "—", s.id,
              ])
            }
          }
          let previewSets = try await client.appCustomProductPageLocalizationsAppPreviewSetsGetToManyRelated(
            path: .init(id: loc.id), query: .init(limit: 50)
          ).ok.body.json
          for set in previewSets.data {
            let previewType = set.attributes?.previewType ?? "—"
            let previews = try await client.appPreviewSetsAppPreviewsGetToManyRelated(
              path: .init(id: set.id), query: .init(limit: 50)
            ).ok.body.json
            for p in previews.data {
              rows.append([
                locale, "Preview", previewType,
                p.attributes?.assetDeliveryState?.state.map { formatState($0) } ?? "—", p.id,
              ])
            }
          }
          // Asset library placements: header, search results, iPhone Duo.
          for (kind, placement) in try await AssetLibrary.slotPlacements(on: .productPageLocalization(loc.id), client: client) {
            rows.append([
              locale, placement.attributes?.mediaType == "VIDEO" ? "Video" : "Image", kind,
              placement.attributes?.state.map { formatState($0) } ?? "—", placement.id,
            ])
          }
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
        discussion: """
          --display-type or --preview-type can also name an asset library slot:
          PRODUCT_PAGE_HEADER or APP_STORE_SEARCH_RESULTS (one image or video, replacing
          the current one) or APP_IPHONE_DUO (a screenshot or app preview, added after the
          existing ones). Sizes are checked against Apple's specs before uploading.
          """
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

      @Option(name: .long, help: "Preview frame timecode for app previews (e.g. 00:00:03).")
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

        let media = try MediaFile(readingFrom: file)
        let ext = (media.fileName as NSString).pathExtension.lowercased()
        let isImage = ["png", "jpg", "jpeg"].contains(ext)
        let isVideo = videoExtensions.contains(ext)

        if let slotName = [displayType, previewType].compactMap({ $0?.uppercased() }).first(where: { AssetLibrary.slots[$0] != nil }),
          let slot = AssetLibrary.slots[slotName] {
          try await uploadToLibrary(media, slot: slot, slotName: slotName, isVideo: isVideo, page: productPage, localizationID: locID, appID: app.id, client: client)
          return
        }
        guard isImage || isVideo else {
          throw ValidationError(
            "Unsupported file type '.\(ext)'. Use png/jpg for screenshots or mp4/mov for previews.")
        }
        if isImage && displayType == nil {
          throw ValidationError("--display-type is required for screenshots (e.g. APP_IPHONE_67).")
        }
        if isVideo && previewType == nil {
          throw ValidationError("--preview-type is required for app previews (e.g. APP_IPHONE_67).")
        }

        let typeLabel = (isImage ? displayType : previewType)?.uppercased() ?? "—"
        print("Upload \(isImage ? "screenshot" : "app preview"):")
        print("  Page:   \(productPage.attributes?.name ?? page)")
        print("  Locale: \(localeName(locale))")
        print("  Type:   \(typeLabel)")
        print("  File:   \(media.fileName) (\(formatBytes(media.fileSize)))")
        print()
        guard confirm("Upload? [y/N] ") else {
          cancelled()
          return
        }

        let mediaID: String
        if isImage {
          let display: ASCEnum.ScreenshotDisplayType = try parseEnum(displayType!, name: "display-type")
          let setID = try await Self.screenshotSetID(
            localizationID: locID, displayType: display, client: client)
          mediaID = try await ClassicMedia.uploadScreenshot(media, setID: setID, client: client)
        } else {
          let preview: ASCEnum.PreviewType = try parseEnum(previewType!, name: "preview-type")
          let setID = try await Self.previewSetID(
            localizationID: locID, previewType: preview, client: client)
          mediaID = try await ClassicMedia.uploadPreview(media, setID: setID, previewFrame: previewFrame, client: client)
        }

        print()
        success("Uploaded", "\(isImage ? "screenshot" : "app preview") (id: \(mediaID)).")
      }

      /// Uploads to an asset library slot: a single slot's current image or video is replaced, an
      /// iPhone Duo screenshot or preview is added after the existing ones.
      private func uploadToLibrary(
        _ media: MediaFile, slot: AssetLibrary.Slot, slotName: String, isVideo: Bool,
        page productPage: Components.Schemas.AppCustomProductPage, localizationID: String, appID: String, client: ASCClient
      ) async throws {
        guard !isVideo || slot.videoPlacementType != nil else {
          throw ValidationError("\(slotName) takes images only.")
        }
        let owner = AssetLibrary.Owner.productPageLocalization(localizationID)
        let current = slot.isSingle
          ? try await AssetLibrary.placements(on: owner, type: slot.placementType, group: slot.group, client: client).map(\.id)
          : []
        print("Upload \(isVideo ? "video" : "image") to the asset library:")
        print("  Page:   \(productPage.attributes?.name ?? page)")
        print("  Locale: \(localeName(locale))")
        print("  Slot:   \(slotName)\(current.isEmpty ? "" : " (replaces the current one)")")
        print("  File:   \(media.fileName) (\(formatBytes(media.fileSize)))")
        print()
        guard confirm("Upload? [y/N] ") else {
          cancelled()
          return
        }
        let libraryID = try await AssetLibrary.libraryID(appID: appID, client: client)
        let placementID = try await AssetLibrary.uploadAndPlace(
          media, slot: slot, on: owner, libraryID: libraryID, replacing: current, client: client)
        print()
        success("Uploaded", "\(isVideo ? "video" : "image") (placement id: \(placementID)).")
      }

      /// Finds the screenshot set with `displayType`, creating it under the localization if absent.
      private static func screenshotSetID(
        localizationID: String, displayType: ASCEnum.ScreenshotDisplayType, client: ASCClient
      ) async throws -> String {
        let sets = try await client.appCustomProductPageLocalizationsAppScreenshotSetsGetToManyRelated(
          path: .init(id: localizationID), query: .init(limit: 50)
        ).ok.body.json
        if let existing = sets.data.first(where: {
          $0.attributes?.screenshotDisplayType == displayType.rawValue
        }) {
          return existing.id
        }
        return try await ClassicMedia.createScreenshotSet(
          displayType, owner: .productPageLocalization(localizationID), client: client)
      }

      /// Finds the preview set with `previewType`, creating it under the localization if absent.
      private static func previewSetID(
        localizationID: String, previewType: ASCEnum.PreviewType, client: ASCClient
      ) async throws -> String {
        let sets = try await client.appCustomProductPageLocalizationsAppPreviewSetsGetToManyRelated(
          path: .init(id: localizationID), query: .init(limit: 50)
        ).ok.body.json
        if let existing = sets.data.first(where: { $0.attributes?.previewType == previewType.rawValue }) {
          return existing.id
        }
        return try await ClassicMedia.createPreviewSet(
          previewType, owner: .productPageLocalization(localizationID), client: client)
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

        let locs = try await client.appCustomProductPageVersionsAppCustomProductPageLocalizationsGetToManyRelated(
          path: .init(id: versionID), query: .init(limit: 50)
        ).ok.body.json

        var kind: String?
        outer: for loc in locs.data {
          let sets = try await client.appCustomProductPageLocalizationsAppScreenshotSetsGetToManyRelated(
            path: .init(id: loc.id), query: .init(limit: 50)
          ).ok.body.json
          for set in sets.data {
            let shots = try await client.appScreenshotSetsAppScreenshotsGetToManyRelated(
              path: .init(id: set.id), query: .init(limit: 50)
            ).ok.body.json
            if shots.data.contains(where: { $0.id == mediaID }) { kind = "screenshot"; break outer }
          }
          let previewSets = try await client.appCustomProductPageLocalizationsAppPreviewSetsGetToManyRelated(
            path: .init(id: loc.id), query: .init(limit: 50)
          ).ok.body.json
          for set in previewSets.data {
            let previews = try await client.appPreviewSetsAppPreviewsGetToManyRelated(
              path: .init(id: set.id), query: .init(limit: 50)
            ).ok.body.json
            if previews.data.contains(where: { $0.id == mediaID }) { kind = "preview"; break outer }
          }
        }

        if kind == nil {
          // An asset library placement: removing it also deletes its image or video from the
          // library when nothing else uses it.
          for loc in locs.data {
            let placements = try await AssetLibrary.slotPlacements(on: .productPageLocalization(loc.id), client: client)
            guard let match = placements.first(where: { $0.placement.id == mediaID }) else { continue }
            guard confirm("Remove this \(match.kind) placement? [y/N] ") else {
              cancelled()
              return
            }
            let deleted = try await AssetLibrary.removePlacement(id: mediaID, client: client)
            print()
            success("Removed", "\(match.kind) placement \(mediaID)\(deleted ? " and its unused library file" : "").")
            return
          }
        }
        guard let kind else {
          throw ValidationError("Media '\(mediaID)' not found on this page.")
        }

        guard confirm("Delete this \(kind)? [y/N] ") else {
          cancelled()
          return
        }

        if kind == "screenshot" {
          try await ClassicMedia.deleteScreenshot(mediaID, client: client)
        } else {
          try await ClassicMedia.deletePreview(mediaID, client: client)
        }
        print()
        success("Deleted", "\(kind) \(mediaID).")
      }
    }
  }
}
