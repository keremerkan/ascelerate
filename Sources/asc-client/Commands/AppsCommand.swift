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
      CommandGroup(name: "Version", subcommands: [CreateVersion.self, AttachBuild.self, AttachLatestBuild.self, DetachBuild.self, PhasedRelease.self, AgeRating.self, RoutingCoverage.self]),
      CommandGroup(name: "Localization", subcommands: [Localizations.self, ExportLocalizations.self, UpdateLocalization.self, UpdateLocalizations.self]),
      CommandGroup(name: "Media", subcommands: [DownloadMedia.self, UploadMedia.self, VerifyMedia.self]),
      CommandGroup(name: "Review", subcommands: [ReviewStatus.self, SubmitForReview.self]),
      CommandGroup(name: "Configuration", subcommands: [AppInfoCommand.self, Availability.self, Encryption.self, EULACommand.self]),
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

      // Show details for active submissions with issues
      for submission in response.data {
        guard let state = submission.attributes?.state,
              state == .unresolvedIssues || state == .inReview || state == .waitingForReview
        else { continue }

        print()
        print("--- Submission \(submission.id) (\(state)) ---")

        // Fetch items for this submission
        let itemsResponse = try await client.send(
          Resources.v1.reviewSubmissions.id(submission.id).items.get()
        )

        if !itemsResponse.data.isEmpty {
          print()
          for item in itemsResponse.data {
            let itemState = item.attributes?.state.map { "\($0)" } ?? "—"
            print("  Item: \(item.id)  State: \(itemState)")
          }
        }

        // Try to get the version's review detail (notes from reviewer)
        if let versionRef = submission.relationships?.appStoreVersionForReview?.data {
          let reviewDetail = try? await client.send(
            Resources.v1.appStoreVersions.id(versionRef.id).appStoreReviewDetail.get()
          )
          if let notes = reviewDetail?.data.attributes?.notes, !notes.isEmpty {
            print()
            print("  Review notes:")
            for line in notes.components(separatedBy: .newlines) {
              print("    \(line)")
            }
          }
        }
      }
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

      // Check if version already exists
      let existingVersions = try await client.send(
        Resources.v1.apps.id(app.id).appStoreVersions.get(
          filterVersionString: [versionString]
        )
      )
      if let existing = existingVersions.data.first(where: { $0.attributes?.versionString == versionString }) {
        let state = existing.attributes?.appVersionState
        if state == .prepareForSubmission {
          print("Version \(versionString) already exists (PREPARE_FOR_SUBMISSION). Continuing.")
          return
        }
        throw ValidationError("Version \(versionString) already exists (state: \(state.map { "\($0)" } ?? "unknown")).")
      }

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

  struct PhasedRelease: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "phased-release",
      abstract: "View or manage phased release for an App Store version."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
    var version: String?

    @Flag(name: .long, help: "Enable phased release (starts inactive, activates when version goes live).")
    var enable = false

    @Flag(name: .long, help: "Pause an active phased release.")
    var pause = false

    @Flag(name: .long, help: "Resume a paused phased release.")
    var resume = false

    @Flag(name: .long, help: "Complete immediately — release to all users.")
    var complete = false

    @Flag(name: .long, help: "Remove phased release entirely.")
    var disable = false

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func validate() throws {
      let flags = [enable, pause, resume, complete, disable].filter { $0 }
      if flags.count > 1 {
        throw ValidationError("Only one action flag can be used at a time (--enable, --pause, --resume, --complete, --disable).")
      }
    }

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appVersion = try await findVersion(appID: app.id, versionString: version, client: client)

      let versionString = appVersion.attributes?.versionString ?? "unknown"
      let appName = app.attributes?.name ?? bundleID

      if enable {
        let request = Resources.v1.appStoreVersionPhasedReleases.post(
          AppStoreVersionPhasedReleaseCreateRequest(
            data: .init(
              attributes: .init(phasedReleaseState: .inactive),
              relationships: .init(
                appStoreVersion: .init(data: .init(id: appVersion.id))
              )
            )
          )
        )
        let response = try await client.send(request)
        let state = response.data.attributes?.phasedReleaseState.map { "\($0)" } ?? "—"
        print("Enabled phased release for version \(versionString).")
        print("  State: \(state)")
        return
      }

      // All other actions require an existing phased release
      let existing: AppStoreVersionPhasedRelease? = try? await client.send(
        Resources.v1.appStoreVersions.id(appVersion.id).appStoreVersionPhasedRelease.get()
      ).data

      if pause {
        guard let pr = existing else {
          throw ValidationError("No phased release configured for version \(versionString). Use --enable first.")
        }
        let request = Resources.v1.appStoreVersionPhasedReleases.id(pr.id).patch(
          AppStoreVersionPhasedReleaseUpdateRequest(
            data: .init(id: pr.id, attributes: .init(phasedReleaseState: .paused))
          )
        )
        let response = try await client.send(request)
        let state = response.data.attributes?.phasedReleaseState.map { "\($0)" } ?? "—"
        print("Paused phased release for version \(versionString).")
        print("  State: \(state)")
        return
      }

      if resume {
        guard let pr = existing else {
          throw ValidationError("No phased release configured for version \(versionString). Use --enable first.")
        }
        let request = Resources.v1.appStoreVersionPhasedReleases.id(pr.id).patch(
          AppStoreVersionPhasedReleaseUpdateRequest(
            data: .init(id: pr.id, attributes: .init(phasedReleaseState: .active))
          )
        )
        let response = try await client.send(request)
        let state = response.data.attributes?.phasedReleaseState.map { "\($0)" } ?? "—"
        print("Resumed phased release for version \(versionString).")
        print("  State: \(state)")
        return
      }

      if complete {
        guard let pr = existing else {
          throw ValidationError("No phased release configured for version \(versionString). Use --enable first.")
        }
        guard confirm("Complete phased release for version \(versionString)? This will release to all users immediately. [y/N] ") else {
          print("Cancelled.")
          return
        }
        let request = Resources.v1.appStoreVersionPhasedReleases.id(pr.id).patch(
          AppStoreVersionPhasedReleaseUpdateRequest(
            data: .init(id: pr.id, attributes: .init(phasedReleaseState: .complete))
          )
        )
        let response = try await client.send(request)
        let state = response.data.attributes?.phasedReleaseState.map { "\($0)" } ?? "—"
        print("Completed phased release for version \(versionString) — released to all users.")
        print("  State: \(state)")
        return
      }

      if disable {
        guard let pr = existing else {
          print("No phased release configured for version \(versionString).")
          return
        }
        guard confirm("Remove phased release for version \(versionString)? [y/N] ") else {
          print("Cancelled.")
          return
        }
        try await client.send(
          Resources.v1.appStoreVersionPhasedReleases.id(pr.id).delete
        )
        print("Removed phased release for version \(versionString).")
        return
      }

      // No flag — show current status
      guard let pr = existing else {
        print("App:            \(appName)")
        print("Version:        \(versionString)")
        print("Phased Release: Not configured")
        return
      }

      let attrs = pr.attributes
      let state = attrs?.phasedReleaseState.map { "\($0)" } ?? "—"
      let startDate = attrs?.startDate.map { formatDate($0) } ?? "—"
      let day = attrs?.currentDayNumber.map { "\($0)" } ?? "—"
      let pauseDuration = attrs?.totalPauseDuration ?? 0

      print("App:            \(appName)")
      print("Version:        \(versionString)")
      print("Phased Release: \(state)")
      print("  Start date:   \(startDate)")
      print("  Day:          \(day) of 7")
      print("  Paused:       \(pauseDuration) day\(pauseDuration == 1 ? "" : "s")")
    }
  }

  struct AgeRating: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "age-rating",
      abstract: "View or update age rating declaration for an App Store version."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
    var version: String?

    @Option(name: .long, help: "Path to a JSON file with age rating fields to update.")
    var file: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appVersion = try await findVersion(appID: app.id, versionString: version, client: client)

      let versionString = appVersion.attributes?.versionString ?? "unknown"
      let appName = app.attributes?.name ?? bundleID

      let response = try await client.send(
        Resources.v1.appStoreVersions.id(appVersion.id).ageRatingDeclaration.get()
      )
      let declaration = response.data
      let attrs = declaration.attributes

      if let filePath = file {
        // Update mode
        let expandedPath = expandPath(filePath)
        guard FileManager.default.fileExists(atPath: expandedPath) else {
          throw ValidationError("File not found at '\(expandedPath)'.")
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
        let fields: AgeRatingFields
        do {
          fields = try JSONDecoder().decode(AgeRatingFields.self, from: data)
        } catch let error as DecodingError {
          throw ValidationError("Invalid JSON: \(describeDecodingError(error))")
        }

        print("App:     \(appName)")
        print("Version: \(versionString)")
        print()
        print("Age rating updates:")
        var changeCount = 0
        if let v = fields.alcoholTobaccoOrDrugUseOrReferences { print("  Alcohol, Tobacco, or Drug Use: \(v)"); changeCount += 1 }
        if let v = fields.contests { print("  Contests: \(v)"); changeCount += 1 }
        if let v = fields.gamblingSimulated { print("  Gambling (simulated): \(v)"); changeCount += 1 }
        if let v = fields.gunsOrOtherWeapons { print("  Guns or Other Weapons: \(v)"); changeCount += 1 }
        if let v = fields.horrorOrFearThemes { print("  Horror or Fear Themes: \(v)"); changeCount += 1 }
        if let v = fields.matureOrSuggestiveThemes { print("  Mature or Suggestive Themes: \(v)"); changeCount += 1 }
        if let v = fields.profanityOrCrudeHumor { print("  Profanity or Crude Humor: \(v)"); changeCount += 1 }
        if let v = fields.sexualContentOrNudity { print("  Sexual Content or Nudity: \(v)"); changeCount += 1 }
        if let v = fields.sexualContentGraphicAndNudity { print("  Sexual Content (graphic): \(v)"); changeCount += 1 }
        if let v = fields.violenceCartoonOrFantasy { print("  Violence (cartoon/fantasy): \(v)"); changeCount += 1 }
        if let v = fields.violenceRealistic { print("  Violence (realistic): \(v)"); changeCount += 1 }
        if let v = fields.violenceRealisticProlongedGraphicOrSadistic { print("  Violence (graphic/sadistic): \(v)"); changeCount += 1 }
        if let v = fields.medicalOrTreatmentInformation { print("  Medical Information: \(v)"); changeCount += 1 }
        if let v = fields.isAdvertising { print("  Advertising: \(v)"); changeCount += 1 }
        if let v = fields.isGambling { print("  Gambling: \(v)"); changeCount += 1 }
        if let v = fields.isUnrestrictedWebAccess { print("  Unrestricted Web Access: \(v)"); changeCount += 1 }
        if let v = fields.isUserGeneratedContent { print("  User-Generated Content: \(v)"); changeCount += 1 }
        if let v = fields.isMessagingAndChat { print("  Messaging and Chat: \(v)"); changeCount += 1 }
        if let v = fields.isLootBox { print("  Loot Box: \(v)"); changeCount += 1 }
        if let v = fields.isHealthOrWellnessTopics { print("  Health/Wellness Topics: \(v)"); changeCount += 1 }
        if let v = fields.isParentalControls { print("  Parental Controls: \(v)"); changeCount += 1 }
        if let v = fields.isAgeAssurance { print("  Age Assurance: \(v)"); changeCount += 1 }
        if let v = fields.kidsAgeBand { print("  Kids Age Band: \(v)"); changeCount += 1 }
        if let v = fields.ageRatingOverride { print("  Age Rating Override: \(v)"); changeCount += 1 }

        if changeCount == 0 {
          throw ValidationError("JSON file contains no age rating fields.")
        }

        print()
        guard confirm("Update \(changeCount) age rating field\(changeCount == 1 ? "" : "s")? [y/N] ") else {
          print("Cancelled.")
          return
        }

        func parseIntensity<T: RawRepresentable>(_ value: String?, type: T.Type) -> T? where T.RawValue == String {
          guard let v = value else { return nil }
          return T(rawValue: v)
        }

        typealias Attrs = AgeRatingDeclarationUpdateRequest.Data.Attributes
        let updateRequest = Resources.v1.ageRatingDeclarations.id(declaration.id).patch(
          AgeRatingDeclarationUpdateRequest(
            data: .init(
              id: declaration.id,
              attributes: .init(
                isAdvertising: fields.isAdvertising,
                alcoholTobaccoOrDrugUseOrReferences: parseIntensity(fields.alcoholTobaccoOrDrugUseOrReferences, type: Attrs.AlcoholTobaccoOrDrugUseOrReferences.self),
                contests: parseIntensity(fields.contests, type: Attrs.Contests.self),
                isGambling: fields.isGambling,
                gamblingSimulated: parseIntensity(fields.gamblingSimulated, type: Attrs.GamblingSimulated.self),
                gunsOrOtherWeapons: parseIntensity(fields.gunsOrOtherWeapons, type: Attrs.GunsOrOtherWeapons.self),
                isHealthOrWellnessTopics: fields.isHealthOrWellnessTopics,
                kidsAgeBand: parseIntensity(fields.kidsAgeBand, type: KidsAgeBand.self),
                isLootBox: fields.isLootBox,
                medicalOrTreatmentInformation: parseIntensity(fields.medicalOrTreatmentInformation, type: Attrs.MedicalOrTreatmentInformation.self),
                isMessagingAndChat: fields.isMessagingAndChat,
                isParentalControls: fields.isParentalControls,
                profanityOrCrudeHumor: parseIntensity(fields.profanityOrCrudeHumor, type: Attrs.ProfanityOrCrudeHumor.self),
                isAgeAssurance: fields.isAgeAssurance,
                sexualContentGraphicAndNudity: parseIntensity(fields.sexualContentGraphicAndNudity, type: Attrs.SexualContentGraphicAndNudity.self),
                sexualContentOrNudity: parseIntensity(fields.sexualContentOrNudity, type: Attrs.SexualContentOrNudity.self),
                horrorOrFearThemes: parseIntensity(fields.horrorOrFearThemes, type: Attrs.HorrorOrFearThemes.self),
                matureOrSuggestiveThemes: parseIntensity(fields.matureOrSuggestiveThemes, type: Attrs.MatureOrSuggestiveThemes.self),
                isUnrestrictedWebAccess: fields.isUnrestrictedWebAccess,
                isUserGeneratedContent: fields.isUserGeneratedContent,
                violenceCartoonOrFantasy: parseIntensity(fields.violenceCartoonOrFantasy, type: Attrs.ViolenceCartoonOrFantasy.self),
                violenceRealisticProlongedGraphicOrSadistic: parseIntensity(fields.violenceRealisticProlongedGraphicOrSadistic, type: Attrs.ViolenceRealisticProlongedGraphicOrSadistic.self),
                violenceRealistic: parseIntensity(fields.violenceRealistic, type: Attrs.ViolenceRealistic.self),
                ageRatingOverride: parseIntensity(fields.ageRatingOverride, type: Attrs.AgeRatingOverride.self)
              )
            )
          )
        )

        _ = try await client.send(updateRequest)
        print()
        print("Updated age rating declaration for version \(versionString).")
        return
      }

      // View mode
      print("App:     \(appName)")
      print("Version: \(versionString)")
      print()
      print("Age Rating Declaration:")

      func intensityLabel(_ raw: String?) -> String {
        switch raw {
        case "NONE": return "None"
        case "INFREQUENT_OR_MILD": return "Infrequent or Mild"
        case "FREQUENT_OR_INTENSE": return "Frequent or Intense"
        case "INFREQUENT": return "Infrequent"
        case "FREQUENT": return "Frequent"
        default: return raw ?? "—"
        }
      }

      func boolLabel(_ value: Bool?) -> String {
        guard let v = value else { return "—" }
        return v ? "Yes" : "No"
      }

      // Intensity-based ratings
      let intensityRows: [(String, String)] = [
        ("Alcohol, Tobacco, or Drug Use", intensityLabel(attrs?.alcoholTobaccoOrDrugUseOrReferences?.rawValue)),
        ("Contests", intensityLabel(attrs?.contests?.rawValue)),
        ("Gambling (simulated)", intensityLabel(attrs?.gamblingSimulated?.rawValue)),
        ("Guns or Other Weapons", intensityLabel(attrs?.gunsOrOtherWeapons?.rawValue)),
        ("Horror or Fear Themes", intensityLabel(attrs?.horrorOrFearThemes?.rawValue)),
        ("Mature or Suggestive Themes", intensityLabel(attrs?.matureOrSuggestiveThemes?.rawValue)),
        ("Profanity or Crude Humor", intensityLabel(attrs?.profanityOrCrudeHumor?.rawValue)),
        ("Sexual Content or Nudity", intensityLabel(attrs?.sexualContentOrNudity?.rawValue)),
        ("Sexual Content (graphic)", intensityLabel(attrs?.sexualContentGraphicAndNudity?.rawValue)),
        ("Violence (cartoon/fantasy)", intensityLabel(attrs?.violenceCartoonOrFantasy?.rawValue)),
        ("Violence (realistic)", intensityLabel(attrs?.violenceRealistic?.rawValue)),
        ("Violence (graphic/sadistic)", intensityLabel(attrs?.violenceRealisticProlongedGraphicOrSadistic?.rawValue)),
        ("Medical Information", intensityLabel(attrs?.medicalOrTreatmentInformation?.rawValue)),
      ]

      // Boolean ratings
      let boolRows: [(String, String)] = [
        ("Advertising", boolLabel(attrs?.isAdvertising)),
        ("Gambling", boolLabel(attrs?.isGambling)),
        ("Unrestricted Web Access", boolLabel(attrs?.isUnrestrictedWebAccess)),
        ("User-Generated Content", boolLabel(attrs?.isUserGeneratedContent)),
        ("Messaging and Chat", boolLabel(attrs?.isMessagingAndChat)),
        ("Loot Box", boolLabel(attrs?.isLootBox)),
        ("Health/Wellness Topics", boolLabel(attrs?.isHealthOrWellnessTopics)),
        ("Parental Controls", boolLabel(attrs?.isParentalControls)),
        ("Age Assurance", boolLabel(attrs?.isAgeAssurance)),
      ]

      // Other
      let kidsAgeBand = attrs?.kidsAgeBand?.rawValue
        .replacingOccurrences(of: "_", with: " ")
        .capitalized ?? "—"
      let ageOverride = attrs?.ageRatingOverride?.rawValue
        .replacingOccurrences(of: "_", with: " ")
        .capitalized ?? "—"

      let maxLabel = max(
        intensityRows.max(by: { $0.0.count < $1.0.count })?.0.count ?? 0,
        boolRows.max(by: { $0.0.count < $1.0.count })?.0.count ?? 0,
        "Kids Age Band".count,
        "Age Rating Override".count
      )

      for (label, value) in intensityRows {
        print("  \(label.padding(toLength: maxLabel, withPad: " ", startingAt: 0))  \(value)")
      }
      for (label, value) in boolRows {
        print("  \(label.padding(toLength: maxLabel, withPad: " ", startingAt: 0))  \(value)")
      }
      print("  \("Kids Age Band".padding(toLength: maxLabel, withPad: " ", startingAt: 0))  \(kidsAgeBand)")
      print("  \("Age Rating Override".padding(toLength: maxLabel, withPad: " ", startingAt: 0))  \(ageOverride)")
    }
  }

  struct RoutingCoverage: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "routing-coverage",
      abstract: "View or upload routing app coverage (.geojson)."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Option(name: .long, help: "Version string (e.g. 2.1.0). Defaults to the latest version.")
    var version: String?

    @Option(name: .long, help: "Path to a .geojson file to upload.")
    var file: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appVersion = try await findVersion(appID: app.id, versionString: version, client: client)

      let versionString = appVersion.attributes?.versionString ?? "unknown"
      let appName = app.attributes?.name ?? bundleID

      guard let filePath = file else {
        // View mode
        let existing: RoutingAppCoverage? = try? await client.send(
          Resources.v1.appStoreVersions.id(appVersion.id).routingAppCoverage.get()
        ).data

        guard let coverage = existing else {
          print("App:              \(appName)")
          print("Version:          \(versionString)")
          print("Routing Coverage: Not configured")
          return
        }

        let attrs = coverage.attributes
        let fileName = attrs?.fileName ?? "—"
        let state = attrs?.assetDeliveryState?.state.map { "\($0)" } ?? "—"
        let fileSize = attrs?.fileSize.map { "\(formatBytes($0))" } ?? "—"

        print("App:              \(appName)")
        print("Version:          \(versionString)")
        print("Routing Coverage: \(fileName)")
        print("  Status:         \(state)")
        print("  Size:           \(fileSize)")
        return
      }

      // Upload mode
      let expandedPath = expandPath(filePath)
      let fm = FileManager.default

      guard fm.fileExists(atPath: expandedPath) else {
        throw ValidationError("File not found at '\(expandedPath)'.")
      }

      let fileAttrs = try fm.attributesOfItem(atPath: expandedPath)
      let fileSize = (fileAttrs[.size] as? Int) ?? 0
      let fileName = (expandedPath as NSString).lastPathComponent

      // Check for existing coverage
      let existing: RoutingAppCoverage? = try? await client.send(
        Resources.v1.appStoreVersions.id(appVersion.id).routingAppCoverage.get()
      ).data

      if let existingCoverage = existing {
        let existingName = existingCoverage.attributes?.fileName ?? "unknown"
        print("Existing routing coverage: \(existingName)")
        guard confirm("Replace existing routing coverage with '\(fileName)'? [y/N] ") else {
          print("Cancelled.")
          return
        }
        try await client.send(
          Resources.v1.routingAppCoverages.id(existingCoverage.id).delete
        )
        print("Deleted existing coverage.")
        print()
      }

      print("Uploading \(fileName) (\(formatBytes(fileSize)))...")
      fflush(stdout)

      // Reserve
      let reserveResponse = try await client.send(
        Resources.v1.routingAppCoverages.post(
          RoutingAppCoverageCreateRequest(
            data: .init(
              attributes: .init(fileSize: fileSize, fileName: fileName),
              relationships: .init(
                appStoreVersion: .init(data: .init(id: appVersion.id))
              )
            )
          )
        )
      )

      let coverageID = reserveResponse.data.id
      guard let operations = reserveResponse.data.attributes?.uploadOperations,
            !operations.isEmpty else {
        throw MediaUploadError.noUploadOperations
      }

      // Upload chunks
      try await uploadChunks(filePath: expandedPath, operations: operations)

      // Commit
      let checksum = try md5Hex(filePath: expandedPath)
      _ = try await client.send(
        Resources.v1.routingAppCoverages.id(coverageID).patch(
          RoutingAppCoverageUpdateRequest(
            data: .init(
              id: coverageID,
              attributes: .init(sourceFileChecksum: checksum, isUploaded: true)
            )
          )
        )
      )

      print("Uploaded routing coverage '\(fileName)' for version \(versionString).")
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

      // Check for existing active review submissions
      let existingSubmissions = try await client.send(
        Resources.v1.apps.id(app.id).reviewSubmissions.get(
          filterState: [.readyForReview, .waitingForReview, .inReview, .unresolvedIssues]
        )
      )

      let submissionID: String
      if let active = existingSubmissions.data.first {
        let activeState = active.attributes?.state

        switch activeState {
        case .waitingForReview, .inReview:
          print("Version is already submitted for review (state: \(activeState.map { "\($0)" } ?? "—")).")
          return
        case .readyForReview:
          print("Found existing review submission (state: readyForReview). Resubmitting...")
          submissionID = active.id
        case .unresolvedIssues:
          print("Found existing review submission with unresolved issues from a previous review.")
          guard confirm("Resubmit for review? [y/N] ") else {
            print("Cancelled.")
            return
          }
          submissionID = active.id
        default:
          submissionID = active.id
        }
      } else {
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
        submissionID = submission.data.id
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
      }

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

  // MARK: - Configuration Commands

  struct AppInfoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "app-info",
      abstract: "View or update app info and categories."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String?

    @Option(name: .long, help: "Primary category ID (e.g. UTILITIES, GAMES_ACTION).")
    var primaryCategory: String?

    @Option(name: .long, help: "Secondary category ID.")
    var secondaryCategory: String?

    @Flag(name: .long, help: "List available category IDs (iOS categories).")
    var listCategories = false

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func validate() throws {
      if !listCategories && bundleID == nil {
        throw ValidationError("Please provide a <bundle-id>, or use --list-categories.")
      }
    }

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()

      if listCategories {
        let response = try await client.send(
          Resources.v1.appCategories.get(
            filterPlatforms: [.iOS],
            isExistsParent: false,
            limit: 200,
            include: [.subcategories],
            limitSubcategories: 50
          )
        )

        print("Categories (iOS):")
        for cat in response.data.sorted(by: { $0.id < $1.id }) {
          print("  \(cat.id)")
          if let subs = cat.relationships?.subcategories?.data, !subs.isEmpty {
            for sub in subs.sorted(by: { $0.id < $1.id }) {
              print("    \(sub.id)")
            }
          }
        }
        return
      }

      guard let bundleID else {
        throw ValidationError("Please provide a <bundle-id>.")
      }

      let app = try await findApp(bundleID: bundleID, client: client)

      let response = try await client.send(
        Resources.v1.apps.id(app.id).appInfos.get(
          include: [.primaryCategory, .secondaryCategory, .appInfoLocalizations],
          limitAppInfoLocalizations: 50
        )
      )

      // Pick the most relevant AppInfo (prefer non-replaced)
      guard let appInfo = response.data.first(where: { $0.attributes?.state != .replacedWithNewInfo })
              ?? response.data.first else {
        throw ValidationError("No app info found.")
      }

      if primaryCategory != nil || secondaryCategory != nil {
        // Update mode
        typealias Rels = AppInfoUpdateRequest.Data.Relationships
        var relationships = Rels()
        if let cat = primaryCategory {
          relationships.primaryCategory = .init(data: .init(id: cat))
        }
        if let cat = secondaryCategory {
          relationships.secondaryCategory = .init(data: .init(id: cat))
        }

        let appName = app.attributes?.name ?? bundleID
        print("App: \(appName)")
        print()
        if let cat = primaryCategory {
          print("  Primary Category:   \(cat)")
        }
        if let cat = secondaryCategory {
          print("  Secondary Category: \(cat)")
        }
        print()

        guard confirm("Update categories? [y/N] ") else {
          print("Cancelled.")
          return
        }

        _ = try await client.send(
          Resources.v1.appInfos.id(appInfo.id).patch(
            AppInfoUpdateRequest(
              data: .init(id: appInfo.id, relationships: relationships)
            )
          )
        )
        print()
        print("Updated app info.")
        return
      }

      // View mode
      let appName = app.attributes?.name ?? bundleID
      let attrs = appInfo.attributes
      let state = attrs?.state.map { "\($0)" } ?? "—"
      let ageRating = attrs?.appStoreAgeRating.map { "\($0)" } ?? "—"
      let primaryCatID = appInfo.relationships?.primaryCategory?.data?.id ?? "—"
      let secondaryCatID = appInfo.relationships?.secondaryCategory?.data?.id ?? "—"

      print("App:                \(appName)")
      print("State:              \(state)")
      print("Age Rating:         \(ageRating)")
      print("Primary Category:   \(primaryCatID)")
      print("Secondary Category: \(secondaryCatID)")

      // Filter localizations to only those belonging to the selected AppInfo
      let locIDs = Set(appInfo.relationships?.appInfoLocalizations?.data?.map(\.id) ?? [])
      let localizations = response.included?.compactMap { item -> AppInfoLocalization? in
        if case .appInfoLocalization(let loc) = item, locIDs.contains(loc.id) {
          return loc
        }
        return nil
      } ?? []

      if !localizations.isEmpty {
        print()
        print("Localizations:")
        for loc in localizations {
          let locAttrs = loc.attributes
          let locale = locAttrs?.locale ?? "—"
          let name = locAttrs?.name ?? "—"
          let subtitle = locAttrs?.subtitle
          var line = "  [\(locale)] \(name)"
          if let sub = subtitle, !sub.isEmpty {
            line += " — \(sub)"
          }
          print(line)
          if let url = locAttrs?.privacyPolicyURL, !url.isEmpty {
            print("    Privacy Policy URL:  \(url)")
          }
          if let url = locAttrs?.privacyChoicesURL, !url.isEmpty {
            print("    Privacy Choices URL: \(url)")
          }
        }
      }
    }
  }

  struct Availability: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "availability",
      abstract: "View or update territory availability."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Option(name: .long, help: "Comma-separated territory codes to make available (e.g. CHN,RUS).")
    var add: String?

    @Option(name: .long, help: "Comma-separated territory codes to make unavailable (e.g. CHN,RUS).")
    var remove: String?

    @Flag(name: .long, help: "Show full country names.")
    var verbose = false

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appName = app.attributes?.name ?? bundleID

      // Get availability info (without includes — territory limit is only 50)
      let response = try await client.send(
        Resources.v1.apps.id(app.id).appAvailabilityV2.get()
      )

      let availableInNew = response.data.attributes?.isAvailableInNewTerritories
      let availabilityID = response.data.id

      // Paginate through all territory availabilities via the v2 sub-resource
      var territoryMap: [(code: String, id: String, isAvailable: Bool)] = []

      for try await page in client.pages(
        Resources.v2.appAvailabilities.id(availabilityID).territoryAvailabilities.get(
          limit: 50,
          include: [.territory]
        )
      ) {
        for ta in page.data {
          guard let code = ta.relationships?.territory?.data?.id else { continue }
          let isAvail = ta.attributes?.isAvailable ?? false
          territoryMap.append((code, ta.id, isAvail))
        }
      }

      // Edit mode
      if add != nil || remove != nil {
        let addCodes = Set(add?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() } ?? [])
        let removeCodes = Set(remove?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() } ?? [])

        let allCodes = Set(territoryMap.map(\.code))
        let invalidCodes = addCodes.union(removeCodes).subtracting(allCodes)
        if !invalidCodes.isEmpty {
          throw ValidationError("Unknown territory codes: \(invalidCodes.sorted().joined(separator: ", "))")
        }

        let overlap = addCodes.intersection(removeCodes)
        if !overlap.isEmpty {
          throw ValidationError("Territory codes in both --add and --remove: \(overlap.sorted().joined(separator: ", "))")
        }

        var changes: [(code: String, id: String, newValue: Bool)] = []
        for t in territoryMap {
          if addCodes.contains(t.code) && !t.isAvailable {
            changes.append((t.code, t.id, true))
          } else if removeCodes.contains(t.code) && t.isAvailable {
            changes.append((t.code, t.id, false))
          }
        }

        // Report codes already in the requested state
        let alreadyAvailable = addCodes.filter { code in territoryMap.first { $0.code == code }?.isAvailable == true }
        let alreadyUnavailable = removeCodes.filter { code in territoryMap.first { $0.code == code }?.isAvailable == false }
        let en = Locale(identifier: "en")

        if !alreadyAvailable.isEmpty {
          for code in alreadyAvailable.sorted() {
            let name = en.localizedString(forRegionCode: code) ?? code
            print("  Already available: \(code)  \(name)")
          }
        }
        if !alreadyUnavailable.isEmpty {
          for code in alreadyUnavailable.sorted() {
            let name = en.localizedString(forRegionCode: code) ?? code
            print("  Already unavailable: \(code)  \(name)")
          }
        }

        if changes.isEmpty {
          print("No changes needed.")
          return
        }

        print("App: \(appName)")
        print()
        for change in changes.sorted(by: { $0.code < $1.code }) {
          let name = en.localizedString(forRegionCode: change.code) ?? change.code
          let action = change.newValue ? "  Add:    " : "  Remove: "
          print("\(action)\(change.code)  \(name)")
        }
        print()

        guard confirm("Apply \(changes.count) change\(changes.count == 1 ? "" : "s")? [y/N] ") else {
          print("Cancelled.")
          return
        }

        var failed: [String] = []
        for change in changes {
          do {
            _ = try await client.send(
              Resources.v1.territoryAvailabilities.id(change.id).patch(
                TerritoryAvailabilityUpdateRequest(
                  data: .init(id: change.id, attributes: .init(isAvailable: change.newValue))
                )
              )
            )
          } catch {
            failed.append(change.code)
            print("  Failed to update \(change.code): \(error.localizedDescription)")
          }
        }

        print()
        let succeeded = changes.count - failed.count
        if succeeded > 0 {
          print("Updated \(succeeded) territory availability\(succeeded == 1 ? "" : " entries").")
        }
        if !failed.isEmpty {
          print("Failed: \(failed.joined(separator: ", "))")
        }
        return
      }

      // View mode
      let available = territoryMap.filter(\.isAvailable).map(\.code).sorted()
      let notAvailable = territoryMap.filter { !$0.isAvailable }.map(\.code).sorted()

      print("App:                          \(appName)")
      print("Available in new territories: \(availableInNew == true ? "Yes" : availableInNew == false ? "No" : "—")")
      print()

      if !available.isEmpty {
        print("Available (\(available.count)):")
        printTerritories(available)
      }

      if !notAvailable.isEmpty {
        if !available.isEmpty { print() }
        print("Not Available (\(notAvailable.count)):")
        printTerritories(notAvailable)
      }

      if available.isEmpty && notAvailable.isEmpty {
        print("No territory availability data found.")
      }
    }

    private func printTerritories(_ codes: [String]) {
      if verbose {
        let en = Locale(identifier: "en")
        for code in codes {
          let name = en.localizedString(forRegionCode: code) ?? code
          print("  \(code)  \(name)")
        }
      } else {
        for i in stride(from: 0, to: codes.count, by: 10) {
          let end = min(i + 10, codes.count)
          let row = codes[i..<end].joined(separator: "  ")
          print("  \(row)")
        }
      }
    }
  }

  struct Encryption: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "encryption",
      abstract: "View or create encryption declarations."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Flag(name: .long, help: "Create a new encryption declaration.")
    var create = false

    @Option(name: .customLong("description"), help: "Description of encryption use (required with --create).")
    var appDescription: String?

    @Flag(name: .long, inversion: .prefixedNo, help: "App uses proprietary cryptography.")
    var proprietaryCrypto: Bool = false

    @Flag(name: .long, inversion: .prefixedNo, help: "App uses third-party cryptography.")
    var thirdPartyCrypto: Bool = false

    @Flag(name: .long, inversion: .prefixedNo, help: "App is available on the French store.")
    var availableOnFrenchStore: Bool = true

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func validate() throws {
      if create && appDescription == nil {
        throw ValidationError("--description is required when using --create.")
      }
    }

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appName = app.attributes?.name ?? bundleID

      if create {
        let desc = appDescription!

        print("App: \(appName)")
        print()
        print("New encryption declaration:")
        print("  Description:            \(desc)")
        print("  Proprietary Crypto:     \(proprietaryCrypto ? "Yes" : "No")")
        print("  Third-Party Crypto:     \(thirdPartyCrypto ? "Yes" : "No")")
        print("  French Store Available: \(availableOnFrenchStore ? "Yes" : "No")")
        print()

        guard confirm("Create encryption declaration? [y/N] ") else {
          print("Cancelled.")
          return
        }

        let response = try await client.send(
          Resources.v1.appEncryptionDeclarations.post(
            AppEncryptionDeclarationCreateRequest(
              data: .init(
                attributes: .init(
                  appDescription: desc,
                  containsProprietaryCryptography: proprietaryCrypto,
                  containsThirdPartyCryptography: thirdPartyCrypto,
                  isAvailableOnFrenchStore: availableOnFrenchStore
                ),
                relationships: .init(
                  app: .init(data: .init(id: app.id))
                )
              )
            )
          )
        )

        let attrs = response.data.attributes
        let state = attrs?.appEncryptionDeclarationState.map { "\($0)" } ?? "—"
        let exempt = attrs?.isExempt.map { $0 ? "Yes" : "No" } ?? "—"
        print()
        print("Created encryption declaration.")
        print("  State:  \(state)")
        print("  Exempt: \(exempt)")
        return
      }

      // View mode
      print("App: \(appName)")
      print()

      var rows: [[String]] = []
      for try await page in client.pages(
        Resources.v1.appEncryptionDeclarations.get(filterApp: [app.id])
      ) {
        for decl in page.data {
          let attrs = decl.attributes
          let state = attrs?.appEncryptionDeclarationState.map { "\($0)" } ?? "—"
          let platform = attrs?.platform.map { "\($0)" } ?? "—"
          let proprietary = attrs?.containsProprietaryCryptography.map { $0 ? "Yes" : "No" } ?? "—"
          let thirdParty = attrs?.containsThirdPartyCryptography.map { $0 ? "Yes" : "No" } ?? "—"
          let exempt = attrs?.isExempt.map { $0 ? "Yes" : "No" } ?? "—"
          let created = attrs?.createdDate.map { formatDate($0) } ?? "—"
          rows.append([state, platform, proprietary, thirdParty, exempt, created])
        }
      }

      if rows.isEmpty {
        print("No encryption declarations found.")
        return
      }

      Table.print(
        headers: ["State", "Platform", "Proprietary", "Third-Party", "Exempt", "Created"],
        rows: rows
      )
    }
  }

  struct EULACommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "eula",
      abstract: "View or manage custom EULA."
    )

    @Argument(help: "The bundle identifier of the app.")
    var bundleID: String

    @Option(name: .long, help: "Path to a text file with EULA content.")
    var file: String?

    @Flag(name: .long, help: "Remove the custom EULA.")
    var delete = false

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func validate() throws {
      if file != nil && delete {
        throw ValidationError("Cannot use --file and --delete together.")
      }
    }

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let appName = app.attributes?.name ?? bundleID

      // Try to get existing EULA (API returns 404 or null data when none exists)
      let existing: EndUserLicenseAgreement?
      do {
        existing = try await client.send(
          Resources.v1.apps.id(app.id).endUserLicenseAgreement.get()
        ).data
      } catch let error as ResponseError {
        if case .requestFailure(_, let statusCode, _) = error, statusCode == 404 {
          existing = nil
        } else {
          throw error
        }
      } catch is DecodingError {
        existing = nil
      }

      if delete {
        guard let eula = existing else {
          print("No custom EULA to delete. The standard Apple EULA applies.")
          return
        }

        let textLen = eula.attributes?.agreementText?.count ?? 0
        print("App:  \(appName)")
        print("EULA: Custom (\(textLen) characters)")
        print()

        guard confirm("Delete custom EULA? This will revert to the standard Apple EULA. [y/N] ") else {
          print("Cancelled.")
          return
        }

        try await client.send(
          Resources.v1.endUserLicenseAgreements.id(eula.id).delete
        )
        print()
        print("Deleted custom EULA.")
        return
      }

      if let filePath = file {
        // Create or update EULA from file
        let expandedPath = expandPath(filePath)
        guard FileManager.default.fileExists(atPath: expandedPath) else {
          throw ValidationError("File not found at '\(expandedPath)'.")
        }

        let text = try String(contentsOfFile: expandedPath, encoding: .utf8)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw ValidationError("EULA file is empty.")
        }

        print("App:  \(appName)")
        print("EULA: \(text.count) characters from \((expandedPath as NSString).lastPathComponent)")
        print()
        let preview = String(text.prefix(200))
        print("  \(preview)\(text.count > 200 ? "..." : "")")
        print()

        if let eula = existing {
          // Update existing
          guard confirm("Update existing EULA? [y/N] ") else {
            print("Cancelled.")
            return
          }

          _ = try await client.send(
            Resources.v1.endUserLicenseAgreements.id(eula.id).patch(
              EndUserLicenseAgreementUpdateRequest(
                data: .init(id: eula.id, attributes: .init(agreementText: text))
              )
            )
          )
          print()
          print("Updated EULA.")
        } else {
          // Create new — need all territory IDs
          var allTerritoryIDs: [String] = []
          for try await page in client.pages(Resources.v1.territories.get(limit: 200)) {
            for territory in page.data {
              allTerritoryIDs.append(territory.id)
            }
          }

          guard confirm("Create custom EULA for all \(allTerritoryIDs.count) territories? [y/N] ") else {
            print("Cancelled.")
            return
          }

          _ = try await client.send(
            Resources.v1.endUserLicenseAgreements.post(
              EndUserLicenseAgreementCreateRequest(
                data: .init(
                  attributes: .init(agreementText: text),
                  relationships: .init(
                    app: .init(data: .init(id: app.id)),
                    territories: .init(data: allTerritoryIDs.map { .init(id: $0) })
                  )
                )
              )
            )
          )
          print()
          print("Created EULA for \(allTerritoryIDs.count) territories.")
        }
        return
      }

      // View mode
      print("App:  \(appName)")

      guard let eula = existing,
            let text = eula.attributes?.agreementText,
            !text.isEmpty else {
        print("EULA: No custom EULA. The standard Apple EULA applies.")
        return
      }

      print("EULA: Custom (\(text.count) characters)")
      print()
      let preview = String(text.prefix(500))
      print("  \(preview)\(text.count > 500 ? "\n  [truncated]" : "")")
    }
  }
}

struct AgeRatingFields: Codable {
  // Intensity-based (NONE, INFREQUENT_OR_MILD, FREQUENT_OR_INTENSE)
  var alcoholTobaccoOrDrugUseOrReferences: String?
  var contests: String?
  var gamblingSimulated: String?
  var gunsOrOtherWeapons: String?
  var horrorOrFearThemes: String?
  var matureOrSuggestiveThemes: String?
  var profanityOrCrudeHumor: String?
  var sexualContentOrNudity: String?
  var sexualContentGraphicAndNudity: String?
  var violenceCartoonOrFantasy: String?
  var violenceRealistic: String?
  var violenceRealisticProlongedGraphicOrSadistic: String?
  var medicalOrTreatmentInformation: String?

  // Boolean
  var isAdvertising: Bool?
  var isGambling: Bool?
  var isUnrestrictedWebAccess: Bool?
  var isUserGeneratedContent: Bool?
  var isMessagingAndChat: Bool?
  var isLootBox: Bool?
  var isHealthOrWellnessTopics: Bool?
  var isParentalControls: Bool?
  var isAgeAssurance: Bool?

  // Other
  var kidsAgeBand: String?
  var ageRatingOverride: String?
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
