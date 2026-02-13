import AppStoreAPI
import AppStoreConnect
import ArgumentParser
import Foundation

struct AppsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "apps",
    abstract: "Manage apps.",
    subcommands: [List.self, Info.self, Versions.self],
    groupedSubcommands: [
      CommandGroup(name: "Version", subcommands: [CreateVersion.self, AttachBuild.self, AttachLatestBuild.self, DetachBuild.self]),
      CommandGroup(name: "Localization", subcommands: [Localizations.self, ExportLocalizations.self, UpdateLocalization.self, UpdateLocalizations.self]),
      CommandGroup(name: "Media", subcommands: [DownloadMedia.self, UploadMedia.self, VerifyMedia.self]),
      CommandGroup(name: "Review", subcommands: [ReviewStatus.self, SubmitForReview.self]),
    ]
  )

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List all apps."
    )

    func run() async throws {
      let client = try ClientFactory.makeClient()
      var allApps: [(String, String, String)] = []

      for try await page in client.pages(Resources.v1.apps.get()) {
        for app in page.data {
          let name = app.attributes?.name ?? "—"
          let bundleID = app.attributes?.bundleID ?? "—"
          let sku = app.attributes?.sku ?? "—"
          allApps.append((bundleID, name, sku))
        }
      }

      Table.print(
        headers: ["Bundle ID", "Name", "SKU"],
        rows: allApps.map { [$0.0, $0.1, $0.2] }
      )
    }
  }

  struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Show info for an app."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let attrs = app.attributes
      print("Name:            \(attrs?.name ?? "—")")
      print("Bundle ID:       \(attrs?.bundleID ?? "—")")
      print("SKU:             \(attrs?.sku ?? "—")")
      print("Primary Locale:  \(attrs?.primaryLocale ?? "—")")
    }
  }

  struct Versions: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List App Store versions."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let response = try await client.send(
        Resources.v1.apps.id(app.id).appStoreVersions.get()
      )

      var rows: [[String]] = []
      for version in response.data {
        let attrs = version.attributes
        let versionString = attrs?.versionString ?? "—"
        let platform = attrs?.platform.map { "\($0)" } ?? "—"
        let state = attrs?.appVersionState.map { "\($0)" } ?? "—"
        let releaseType = attrs?.releaseType.map { "\($0)" } ?? "—"
        let created = attrs?.createdDate.map { formatDate($0) } ?? "—"
        rows.append([versionString, platform, state, releaseType, created])
      }

      Table.print(
        headers: ["Version", "Platform", "State", "Release Type", "Created"],
        rows: rows
      )
    }
  }

  struct Localizations: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List localizations for an App Store version."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
    var version: String?

    @Option(name: .long, help: "Filter by locale (e.g. en-US).")
    var locale: String?

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let version = try await findVersion(appID: app.id, versionString: version, client: client)

      let versionString = version.attributes?.versionString ?? "unknown"
      print("Version: \(versionString)")
      print()

      let request = Resources.v1.appStoreVersions.id(version.id)
        .appStoreVersionLocalizations.get(
          filterLocale: locale.map { [$0] }
        )

      let response = try await client.send(request)

      for loc in response.data {
        let attrs = loc.attributes
        let localeStr = attrs?.locale ?? "—"
        print("[\(localeStr)]")
        if let desc = attrs?.description, !desc.isEmpty {
          print("  Description:      \(desc.prefix(80))\(desc.count > 80 ? "..." : "")")
        }
        if let whatsNew = attrs?.whatsNew, !whatsNew.isEmpty {
          print("  What's New:       \(whatsNew.prefix(80))\(whatsNew.count > 80 ? "..." : "")")
        }
        if let keywords = attrs?.keywords, !keywords.isEmpty {
          print("  Keywords:         \(keywords.prefix(80))\(keywords.count > 80 ? "..." : "")")
        }
        if let promo = attrs?.promotionalText, !promo.isEmpty {
          print("  Promotional Text: \(promo.prefix(80))\(promo.count > 80 ? "..." : "")")
        }
        if let url = attrs?.marketingURL {
          print("  Marketing URL:    \(url)")
        }
        if let url = attrs?.supportURL {
          print("  Support URL:      \(url)")
        }
        print()
      }
    }
  }

  struct ReviewStatus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "review-status",
      abstract: "Show review submission status."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let response = try await client.send(
        Resources.v1.apps.id(app.id).reviewSubmissions.get()
      )

      if response.data.isEmpty {
        print("No review submissions found.")
        return
      }

      var rows: [[String]] = []
      for submission in response.data {
        let attrs = submission.attributes
        let platform = attrs?.platform.map { "\($0)" } ?? "—"
        let state = attrs?.state.map { "\($0)" } ?? "—"
        let submitted = attrs?.submittedDate.map { formatDate($0) } ?? "—"
        rows.append([platform, state, submitted])
      }

      Table.print(
        headers: ["Platform", "State", "Submitted"],
        rows: rows
      )
    }
  }

  struct CreateVersion: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "create-version",
      abstract: "Create a new App Store version."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Argument(help: "The version string (e.g. 2.1.0).")
    var versionString: String

    @Option(name: .long, help: "Platform: ios, macos, tvos, visionos (default: ios).")
    var platform: String = "ios"

    @Option(name: .long, help: "Release type: manual, after-approval, scheduled. Defaults to previous version's setting.")
    var releaseType: String?

    @Option(name: .long, help: "Copyright notice (e.g. \"2026 Your Name\").")
    var copyright: String?

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let platformValue: Platform = switch platform.lowercased() {
      case "ios": .iOS
      case "macos": .macOS
      case "tvos": .tvOS
      case "visionos": .visionOS
      default: throw ValidationError("Invalid platform '\(platform)'. Use: ios, macos, tvos, visionos.")
      }

      let releaseTypeValue: AppStoreVersionCreateRequest.Data.Attributes.ReleaseType?
      if let releaseType {
        releaseTypeValue = switch releaseType.lowercased() {
        case "manual": .manual
        case "after-approval": .afterApproval
        case "scheduled": .scheduled
        default: throw ValidationError("Invalid release type '\(releaseType)'. Use: manual, after-approval, scheduled.")
        }
      } else {
        releaseTypeValue = nil
      }

      let request = Resources.v1.appStoreVersions.post(
        AppStoreVersionCreateRequest(
          data: .init(
            attributes: .init(
              platform: platformValue,
              versionString: versionString,
              copyright: copyright,
              releaseType: releaseTypeValue
            ),
            relationships: .init(
              app: .init(data: .init(id: app.id))
            )
          )
        )
      )

      let response = try await client.send(request)
      let attrs = response.data.attributes
      print("Created version \(attrs?.versionString ?? versionString)")
      print("  Platform:     \(attrs?.platform.map { "\($0)" } ?? "—")")
      print("  State:        \(attrs?.appVersionState.map { "\($0)" } ?? "—")")
      print("  Release Type: \(attrs?.releaseType.map { "\($0)" } ?? "—")")
    }
  }

  struct AttachBuild: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "attach-build",
      abstract: "Interactively select and attach a build to an App Store version."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
    var version: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appVersion = try await findVersion(appID: app.id, versionString: version, client: client)

      let versionString = appVersion.attributes?.versionString ?? "unknown"
      print("Version: \(versionString)")
      print()

      let build = try await selectBuild(appID: app.id, versionID: appVersion.id, versionString: versionString, client: client)
      let buildNumber = build.attributes?.version ?? "unknown"
      let uploaded = build.attributes?.uploadedDate.map { formatDate($0) } ?? "—"
      print()
      print("Attached build \(buildNumber) (uploaded \(uploaded)) to version \(versionString).")
    }
  }

  struct AttachLatestBuild: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "attach-latest-build",
      abstract: "Attach the most recent build to an App Store version."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
    var version: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appVersion = try await findVersion(appID: app.id, versionString: version, client: client)

      let versionString = appVersion.attributes?.versionString ?? "unknown"

      // If a build was just uploaded in this workflow, wait for it to appear and process
      if let pendingBuild = lastUploadedBuildVersion {
        print("Waiting for uploaded build \(pendingBuild) to become available...")
        print()
        let awaitedBuild = try await awaitBuildProcessing(
          appID: app.id,
          buildVersion: pendingBuild,
          client: client
        )
        let uploaded = awaitedBuild.attributes?.uploadedDate.map { formatDate($0) } ?? "—"
        print()
        print("Version: \(versionString)")
        print("Build:   \(pendingBuild)  VALID  \(uploaded)")
        print()

        guard confirm("Attach this build? [y/N] ") else {
          print("Cancelled.")
          return
        }

        try await client.send(
          Resources.v1.appStoreVersions.id(appVersion.id).relationships.build.patch(
            AppStoreVersionBuildLinkageRequest(
              data: .init(id: awaitedBuild.id)
            )
          )
        )

        print()
        print("Attached build \(pendingBuild) (uploaded \(uploaded)) to version \(versionString).")
        return
      }

      let buildsResponse = try await client.send(
        Resources.v1.builds.get(
          filterPreReleaseVersionVersion: [versionString],
          filterApp: [app.id],
          sort: [.minusUploadedDate],
          limit: 1
        )
      )

      guard let build = buildsResponse.data.first else {
        throw ValidationError("No builds found for version \(versionString). Upload a build first via Xcode or Transporter.")
      }

      var latestBuild = build
      let buildNumber = latestBuild.attributes?.version ?? "unknown"
      let state = latestBuild.attributes?.processingState
      let uploaded = latestBuild.attributes?.uploadedDate.map { formatDate($0) } ?? "—"

      print("Version: \(versionString)")
      print("Build:   \(buildNumber)  \(state.map { "\($0)" } ?? "—")  \(uploaded)")
      print()

      if state == .processing {
        if confirm("Build \(buildNumber) is still processing. Wait for it to finish? [y/N] ") {
          print()
          latestBuild = try await awaitBuildProcessing(
            appID: app.id,
            buildVersion: buildNumber,
            client: client
          )
          print()
        } else {
          print("Cancelled.")
          return
        }
      } else if state == .failed || state == .invalid {
        print("Build \(buildNumber) has state \(state.map { "\($0)" } ?? "—") and cannot be attached.")
        throw ExitCode.failure
      }

      guard confirm("Attach this build? [y/N] ") else {
        print("Cancelled.")
        return
      }

      try await client.send(
        Resources.v1.appStoreVersions.id(appVersion.id).relationships.build.patch(
          AppStoreVersionBuildLinkageRequest(
            data: .init(id: build.id)
          )
        )
      )

      print()
      print("Attached build \(buildNumber) (uploaded \(uploaded)) to version \(versionString).")
    }
  }

  struct DetachBuild: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "detach-build",
      abstract: "Remove the attached build from an App Store version."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
    var version: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appVersion = try await findVersion(appID: app.id, versionString: version, client: client)

      let versionString = appVersion.attributes?.versionString ?? "unknown"

      // Check if a build is attached
      guard let existingBuild: Build = try? await client.send(
        Resources.v1.appStoreVersions.id(appVersion.id).build.get()
      ).data, existingBuild.attributes?.version != nil else {
        print("No build attached to version \(versionString).")
        return
      }

      let buildNumber = existingBuild.attributes?.version ?? "unknown"
      let uploaded = existingBuild.attributes?.uploadedDate.map { formatDate($0) } ?? "—"

      print("Version: \(versionString)")
      print("Build:   \(buildNumber) (uploaded \(uploaded))")
      print()

      guard confirm("Detach this build from version \(versionString)? [y/N] ") else {
        print("Cancelled.")
        return
      }

      // The API uses PATCH with {"data": null} to detach a build.
      // The typed AppStoreVersionBuildLinkageRequest requires non-null data,
      // so we construct the request manually using Request<Void>.
      let request = Request<Void>.patch(
        "/v1/appStoreVersions/\(appVersion.id)/relationships/build",
        body: NullRelationship()
      )
      try await client.send(request)

      print()
      print("Detached build \(buildNumber) from version \(versionString).")
    }
  }

  struct SubmitForReview: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "submit-for-review",
      abstract: "Submit an App Store version for review."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
    var version: String?

    @Option(name: .long, help: "Platform: ios, macos, tvos, visionos (default: ios).")
    var platform: String = "ios"

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appVersion = try await findVersion(appID: app.id, versionString: version, client: client)

      let versionString = appVersion.attributes?.versionString ?? "unknown"
      let versionState = appVersion.attributes?.appVersionState.map { "\($0)" } ?? "unknown"

      let platformValue: Platform = switch platform.lowercased() {
      case "ios": .iOS
      case "macos": .macOS
      case "tvos": .tvOS
      case "visionos": .visionOS
      default: throw ValidationError("Invalid platform '\(platform)'. Use: ios, macos, tvos, visionos.")
      }

      // Check if a build is already attached
      // The API returns {"data": null} when no build is attached, which fails
      // to decode since BuildWithoutIncludesResponse.data is non-optional.
      let existingBuild: Build? = try? await client.send(
        Resources.v1.appStoreVersions.id(appVersion.id).build.get()
      ).data

      if let build = existingBuild, build.attributes?.version != nil {
        let buildNumber = build.attributes?.version ?? "unknown"
        let uploaded = build.attributes?.uploadedDate.map { formatDate($0) } ?? "—"
        print("App:      \(app.attributes?.name ?? bundleID)")
        print("Version:  \(versionString)")
        print("Build:    \(buildNumber) (uploaded \(uploaded))")
        print("State:    \(versionState)")
        print("Platform: \(platformValue)")
        print()
        guard confirm("Submit this version for App Review? [y/N] ") else {
          print("Cancelled.")
          return
        }
      } else {
        print("App:      \(app.attributes?.name ?? bundleID)")
        print("Version:  \(versionString)")
        print("State:    \(versionState)")
        print("Platform: \(platformValue)")
        print()
        print("No build attached to this version. Select a build first:")
        print()
        let selected = try await selectBuild(appID: app.id, versionID: appVersion.id, versionString: versionString, client: client)
        let buildNumber = selected.attributes?.version ?? "unknown"
        print()
        print("Build \(buildNumber) attached. Continuing with submission...")
        print()
        guard confirm("Submit this version for App Review? [y/N] ") else {
          print("Cancelled.")
          return
        }
      }
      print()

      // Step 1: Create a review submission
      let createSubmission = Resources.v1.reviewSubmissions.post(
        ReviewSubmissionCreateRequest(
          data: .init(
            attributes: .init(platform: platformValue),
            relationships: .init(
              app: .init(data: .init(id: app.id))
            )
          )
        )
      )
      let submission = try await client.send(createSubmission)
      let submissionID = submission.data.id
      print("Created review submission (\(submissionID))")

      // Step 2: Add the app store version as a review item
      let createItem = Resources.v1.reviewSubmissionItems.post(
        ReviewSubmissionItemCreateRequest(
          data: .init(
            relationships: .init(
              reviewSubmission: .init(data: .init(id: submissionID)),
              appStoreVersion: .init(data: .init(id: appVersion.id))
            )
          )
        )
      )
      _ = try await client.send(createItem)
      print("Added version \(versionString) to submission")

      // Step 3: Submit for review
      let submitRequest = Resources.v1.reviewSubmissions.id(submissionID).patch(
        ReviewSubmissionUpdateRequest(
          data: .init(
            id: submissionID,
            attributes: .init(isSubmitted: true)
          )
        )
      )
      let result = try await client.send(submitRequest)
      let state = result.data.attributes?.state.map { "\($0)" } ?? "unknown"
      print()
      print("Submitted for review.")
      print("  State: \(state)")
    }
  }

  struct UpdateLocalization: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "update-localization",
      abstract: "Update localization metadata for the latest App Store version."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Option(name: .long, help: "The locale to update (e.g. en-US). Defaults to the app's primary locale.")
    var locale: String?

    @Option(name: .long, help: "App description.")
    var description: String?

    @Option(name: .long, help: "What's new in this version.")
    var whatsNew: String?

    @Option(name: .long, help: "Comma-separated keywords.")
    var keywords: String?

    @Option(name: .long, help: "Promotional text.")
    var promotionalText: String?

    @Option(name: .long, help: "Marketing URL.")
    var marketingURL: String?

    @Option(name: .long, help: "Support URL.")
    var supportURL: String?

    func run() async throws {
      guard description != nil || whatsNew != nil || keywords != nil
              || promotionalText != nil || marketingURL != nil || supportURL != nil else {
        throw ValidationError("Provide at least one field to update (--description, --whats-new, --keywords, --promotional-text, --marketing-url, --support-url).")
      }

      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let version = try await findVersion(appID: app.id, versionString: nil, client: client)

      // Find the localization
      let locsResponse = try await client.send(
        Resources.v1.appStoreVersions.id(version.id)
          .appStoreVersionLocalizations.get(
            filterLocale: locale.map { [$0] }
          )
      )
      guard let localization = locsResponse.data.first else {
        let localeDesc = locale ?? "primary"
        throw ValidationError("No localization found for locale '\(localeDesc)'.")
      }

      let request = Resources.v1.appStoreVersionLocalizations.id(localization.id).patch(
        AppStoreVersionLocalizationUpdateRequest(
          data: .init(
            id: localization.id,
            attributes: .init(
              description: description,
              keywords: keywords,
              marketingURL: marketingURL.flatMap { URL(string: $0) },
              promotionalText: promotionalText,
              supportURL: supportURL.flatMap { URL(string: $0) },
              whatsNew: whatsNew
            )
          )
        )
      )

      let response = try await client.send(request)
      let attrs = response.data.attributes
      let versionString = version.attributes?.versionString ?? "unknown"
      print("Updated localization for version \(versionString) [\(attrs?.locale ?? "—")]")

      if let d = attrs?.description, !d.isEmpty { print("  Description:      \(d.prefix(80))\(d.count > 80 ? "..." : "")") }
      if let w = attrs?.whatsNew, !w.isEmpty { print("  What's New:       \(w.prefix(80))\(w.count > 80 ? "..." : "")") }
      if let k = attrs?.keywords, !k.isEmpty { print("  Keywords:         \(k.prefix(80))\(k.count > 80 ? "..." : "")") }
      if let p = attrs?.promotionalText, !p.isEmpty { print("  Promotional Text: \(p.prefix(80))\(p.count > 80 ? "..." : "")") }
      if let u = attrs?.marketingURL { print("  Marketing URL:    \(u)") }
      if let u = attrs?.supportURL { print("  Support URL:      \(u)") }
    }
  }

  struct UpdateLocalizations: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "update-localizations",
      abstract: "Update localizations from a JSON file for the latest App Store version."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Option(name: .long, help: "Path to the JSON file with localization data.")
    var file: String?

    @Flag(name: .long, help: "Show full API response for each locale update.")
    var verbose = false

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      // Get file path from argument or prompt
      let filePath: String
      if let f = file {
        filePath = f
      } else {
        print("Path to localizations JSON file: ", terminator: "")
        guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !line.isEmpty else {
          throw ValidationError("No file path provided.")
        }
        filePath = line
      }

      let expandedPath = expandPath(filePath)

      guard FileManager.default.fileExists(atPath: expandedPath) else {
        throw ValidationError("File not found at '\(expandedPath)'.")
      }

      // Parse JSON
      let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
      let localeUpdates: [String: LocaleFields]
      do {
        localeUpdates = try JSONDecoder().decode([String: LocaleFields].self, from: data)
      } catch let error as DecodingError {
        throw ValidationError("Invalid JSON: \(describeDecodingError(error))")
      }

      if localeUpdates.isEmpty {
        throw ValidationError("JSON file contains no locale entries.")
      }

      // Show summary and confirm
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let version = try await findVersion(appID: app.id, versionString: nil, client: client)

      let versionString = version.attributes?.versionString ?? "unknown"
      let versionState = version.attributes?.appVersionState.map { "\($0)" } ?? "unknown"
      print("App:     \(app.attributes?.name ?? bundleID)")
      print("Version: \(versionString)")
      print("State:   \(versionState)")
      print()

      for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
        print("[\(locale)]")
        if let d = fields.description { print("  Description:      \(d.prefix(80))\(d.count > 80 ? "..." : "")") }
        if let w = fields.whatsNew { print("  What's New:       \(w.prefix(80))\(w.count > 80 ? "..." : "")") }
        if let k = fields.keywords { print("  Keywords:         \(k.prefix(80))\(k.count > 80 ? "..." : "")") }
        if let p = fields.promotionalText { print("  Promotional Text: \(p.prefix(80))\(p.count > 80 ? "..." : "")") }
        if let u = fields.marketingURL { print("  Marketing URL:    \(u)") }
        if let u = fields.supportURL { print("  Support URL:      \(u)") }
        print()
      }

      guard confirm("Send updates for \(localeUpdates.count) locale(s)? [y/N] ") else {
        print("Cancelled.")
        return
      }
      print()

      // Fetch all localizations for this version
      let locsResponse = try await client.send(
        Resources.v1.appStoreVersions.id(version.id)
          .appStoreVersionLocalizations.get()
      )

      let locByLocale = Dictionary(
        locsResponse.data.compactMap { loc in
          loc.attributes?.locale.map { ($0, loc) }
        },
        uniquingKeysWith: { first, _ in first }
      )

      // Send updates
      for (locale, fields) in localeUpdates.sorted(by: { $0.key < $1.key }) {
        guard let localization = locByLocale[locale] else {
          print("  [\(locale)] Skipped — locale not found on this version.")
          continue
        }

        let request = Resources.v1.appStoreVersionLocalizations.id(localization.id).patch(
          AppStoreVersionLocalizationUpdateRequest(
            data: .init(
              id: localization.id,
              attributes: .init(
                description: fields.description,
                keywords: fields.keywords,
                marketingURL: fields.marketingURL.flatMap { URL(string: $0) },
                promotionalText: fields.promotionalText,
                supportURL: fields.supportURL.flatMap { URL(string: $0) },
                whatsNew: fields.whatsNew
              )
            )
          )
        )

        let response = try await client.send(request)
        print("  [\(locale)] Updated.")

        if verbose {
          let attrs = response.data.attributes
          print("    Response:")
          print("      Locale:           \(attrs?.locale ?? "—")")
          if let d = attrs?.description { print("      Description:      \(d.prefix(120))\(d.count > 120 ? "..." : "")") }
          if let w = attrs?.whatsNew { print("      What's New:       \(w.prefix(120))\(w.count > 120 ? "..." : "")") }
          if let k = attrs?.keywords { print("      Keywords:         \(k.prefix(120))\(k.count > 120 ? "..." : "")") }
          if let p = attrs?.promotionalText { print("      Promotional Text: \(p.prefix(120))\(p.count > 120 ? "..." : "")") }
          if let u = attrs?.marketingURL { print("      Marketing URL:    \(u)") }
          if let u = attrs?.supportURL { print("      Support URL:      \(u)") }
        }
      }

      print()
      print("Done.")
    }
  }

  struct ExportLocalizations: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "export-localizations",
      abstract: "Export localizations to a JSON file from an App Store version."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
    var version: String?

    @Option(name: .long, help: "Output file path (default: <bundle-id>-localizations.json).")
    var output: String?

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let version = try await findVersion(appID: app.id, versionString: version, client: client)

      let locsResponse = try await client.send(
        Resources.v1.appStoreVersions.id(version.id)
          .appStoreVersionLocalizations.get()
      )

      var result: [String: LocaleFields] = [:]
      for loc in locsResponse.data {
        guard let locale = loc.attributes?.locale else { continue }
        let attrs = loc.attributes
        result[locale] = LocaleFields(
          description: attrs?.description,
          whatsNew: attrs?.whatsNew,
          keywords: attrs?.keywords,
          promotionalText: attrs?.promotionalText,
          marketingURL: attrs?.marketingURL?.absoluteString,
          supportURL: attrs?.supportURL?.absoluteString
        )
      }

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)

      let outputPath = expandPath(
        confirmOutputPath(output ?? "\(bundleID)-localizations.json", isDirectory: false))
      try data.write(to: URL(fileURLWithPath: outputPath))

      let versionString = version.attributes?.versionString ?? "unknown"
      print("Exported \(result.count) locale(s) for version \(versionString) to \(outputPath)")
    }
  }
}

struct LocaleFields: Codable {
  var description: String?
  var whatsNew: String?
  var keywords: String?
  var promotionalText: String?
  var marketingURL: String?
  var supportURL: String?
}

/// Encodes as `{"data": null}` for clearing a to-one relationship.
private struct NullRelationship: Encodable, Sendable {
  enum CodingKeys: String, CodingKey { case data }
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeNil(forKey: .data)
  }
}

private func describeDecodingError(_ error: DecodingError) -> String {
  switch error {
  case .typeMismatch(let type, let context):
    return "Type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
  case .valueNotFound(let type, let context):
    return "Missing value for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
  case .keyNotFound(let key, _):
    return "Unknown key '\(key.stringValue)'"
  case .dataCorrupted(let context):
    return context.debugDescription
  @unknown default:
    return "\(error)"
  }
}

func findApp(bundleID: String, client: AppStoreConnectClient) async throws -> App {
  let response = try await client.send(
    Resources.v1.apps.get(filterBundleID: [bundleID])
  )
  // filterBundleID can return prefix matches, so find the exact match
  guard let app = response.data.first(where: { $0.attributes?.bundleID == bundleID }) else {
    throw AppLookupError.notFound(bundleID)
  }
  return app
}

func findVersion(appID: String, versionString: String?, client: AppStoreConnectClient) async throws -> AppStoreVersion {
  let request = Resources.v1.apps.id(appID).appStoreVersions.get(
    filterVersionString: versionString.map { [$0] },
    limit: 1
  )
  let response = try await client.send(request)
  guard let version = response.data.first else {
    if let v = versionString {
      throw AppLookupError.versionNotFound(v)
    }
    throw AppLookupError.noVersions
  }
  return version
}

/// Polls until a build finishes processing. Returns the final build.
/// Throws on timeout or if the build ends in a non-valid state.
func awaitBuildProcessing(
  appID: String,
  buildVersion: String?,
  client: AppStoreConnectClient,
  interval: Int = 30,
  timeout: Int = 30
) async throws -> Build {
  let deadline = Date().addingTimeInterval(Double(timeout * 60))
  var waitingElapsed = 0
  var waitingStarted = false

  while Date() < deadline {
    let request = Resources.v1.builds.get(
      filterVersion: buildVersion.map { [$0] },
      filterApp: [appID],
      sort: [.minusUploadedDate],
      limit: 1
    )
    let response = try await client.send(request)

    if let build = response.data.first,
       let state = build.attributes?.processingState {
      let version = build.attributes?.version ?? "?"

      // End the "not found" line if we were waiting
      if waitingStarted {
        print()
        waitingStarted = false
      }

      switch state {
      case .valid:
        print("Build \(version) is ready (VALID).")
        return build
      case .failed, .invalid:
        print("Build \(version) processing ended with state: \(state)")
        throw ExitCode.failure
      case .processing:
        print("Build \(version): still processing...")
      }
    } else {
      waitingElapsed += interval
      if !waitingStarted {
        print("Build not found yet", terminator: "")
        waitingStarted = true
      }
      print("...\(waitingElapsed)s", terminator: "")
      fflush(stdout)
    }

    try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
  }

  if waitingStarted { print() }
  print("\nTimed out after \(timeout) minutes.")
  throw ExitCode.failure
}

/// Fetches builds for the app matching the given version, prompts the user to pick one, and attaches it.
/// Returns the selected build.
@discardableResult
private func selectBuild(appID: String, versionID: String, versionString: String?, client: AppStoreConnectClient) async throws -> Build {
  let buildsResponse = try await client.send(
    Resources.v1.builds.get(
      filterPreReleaseVersionVersion: versionString.map { [$0] },
      filterApp: [appID],
      sort: [.minusUploadedDate],
      limit: 10
    )
  )

  let builds = buildsResponse.data
  guard !builds.isEmpty else {
    if let v = versionString {
      throw ValidationError("No builds found for version \(v). Upload a build first via Xcode or Transporter.")
    }
    throw ValidationError("No builds found for this app. Upload a build first via Xcode or Transporter.")
  }

  print("Builds for version \(versionString ?? "all"):")
  for (i, build) in builds.enumerated() {
    let number = build.attributes?.version ?? "—"
    let state = build.attributes?.processingState.map { "\($0)" } ?? "—"
    let uploaded = build.attributes?.uploadedDate.map { formatDate($0) } ?? "—"
    print("  [\(i + 1)] \(number)  \(state)  \(uploaded)")
  }
  print()

  let selected: Build
  if autoConfirm {
    selected = builds[0]
    let number = selected.attributes?.version ?? "—"
    print("Auto-selected build \(number) (most recent).")
  } else {
    print("Select a build (1-\(builds.count)): ", terminator: "")
    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
          let choice = Int(input),
          choice >= 1, choice <= builds.count else {
      throw ValidationError("Invalid selection.")
    }
    selected = builds[choice - 1]
  }

  // Attach the build to the version
  try await client.send(
    Resources.v1.appStoreVersions.id(versionID).relationships.build.patch(
      AppStoreVersionBuildLinkageRequest(
        data: .init(id: selected.id)
      )
    )
  )

  return selected
}

enum AppLookupError: LocalizedError {
  case notFound(String)
  case versionNotFound(String)
  case noVersions

  var errorDescription: String? {
    switch self {
    case .notFound(let bundleID):
      return "No app found with bundle ID '\(bundleID)'."
    case .versionNotFound(let version):
      return "No App Store version '\(version)' found."
    case .noVersions:
      return "No App Store versions found."
    }
  }
}
