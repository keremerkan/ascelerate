import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

/// Product page optimization: A/B tests of the App Store product page (screenshots, previews, app
/// icon) against the live version's page, with up to three treatments.
struct ExperimentsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "experiments",
    abstract: "Product page optimization (A/B tests of screenshots, previews and app icons).",
    subcommands: [List.self, Info.self, Create.self, Update.self, Delete.self, Submit.self, Start.self, Stop.self, Treatments.self, Media.self],
    defaultSubcommand: List.self
  )

  typealias Experiment = Experiments.Experiment
  typealias Treatment = Experiments.Treatment

  /// The app and experiment every subcommand but `list`/`create` starts from.
  struct Target: ParsableArguments {
    @Argument(help: "Bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Argument(help: "Experiment name or ID.")
    var experiment: String

    func resolve(_ client: ASCClient) async throws -> (app: Components.Schemas.App, experiment: Experiment) {
      let app = try await findApp(bundleID: bundleID, client: client)
      do {
        return (app, try await Experiments.find(experiment, appID: app.id, client: client))
      } catch let error as Experiments.LookupError {
        throw ValidationError(error.localizedDescription)
      }
    }
  }

  static func treatment(_ ref: String, experimentID: String, client: ASCClient) async throws -> Treatment {
    do {
      return try await Experiments.treatment(ref, experimentID: experimentID, client: client)
    } catch let error as Experiments.LookupError {
      throw ValidationError(error.localizedDescription)
    }
  }

  // MARK: - Experiments

  struct Entry: Encodable {
    let id: String
    let name: String?
    let platform: String?
    let state: String?
    let trafficProportion: Int?
    let reviewRequired: Bool?
    let startDate: Date?
    let endDate: Date?
    var treatments: [TreatmentEntry]?

    init(_ e: Experiment) {
      id = e.id; name = e.name; platform = e.platform; state = e.state; trafficProportion = e.trafficProportion
      reviewRequired = e.reviewRequired; startDate = e.startDate; endDate = e.endDate
    }
  }

  struct TreatmentEntry: Encodable {
    let id: String
    let name: String?
    let appIconName: String?
    let localizations: [LocalizationEntry]
  }

  struct LocalizationEntry: Encodable {
    let id: String
    let locale: String?
    /// Every screenshot, preview and library placement.
    let media: [MediaEntry]
  }

  struct MediaEntry: Encodable {
    let id: String
    let kind: String
    let type: String
    let state: String
  }

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the app's product page optimization tests.")

    @Argument(help: "Bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @OptionGroup var jsonOption: JSONOption

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let entries = try await Experiments.list(appID: app.id, client: client).map(Entry.init)
      if jsonOption.json { try printJSON(entries); return }
      guard !entries.isEmpty else {
        print("No product page optimization tests. Create one with 'ascelerate experiments create'.")
        return
      }
      let rows: [[String]] = entries.map { e in
        let traffic = e.trafficProportion.map { "\($0)%" } ?? "-"
        let dates = [e.startDate, e.endDate].map { $0.map { formatDate($0) } ?? "" }.filter { !$0.isEmpty }.joined(separator: " – ")
        return [e.id, e.name ?? "-", formatState(e.platform ?? "-"), formatState(e.state ?? "-"), traffic, dates]
      }
      Table.print(headers: ["ID", "Name", "Platform", "State", "Traffic", "Running"], rows: rows)
    }
  }

  struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show a test with its treatments, localizations and media.")

    @OptionGroup var target: Target
    @OptionGroup var jsonOption: JSONOption

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let (_, experiment) = try await target.resolve(client)
      var entry = Entry(experiment)
      var treatments: [TreatmentEntry] = []
      for t in try await Experiments.treatments(experimentID: experiment.id, client: client) {
        var localizations: [LocalizationEntry] = []
        for loc in try await Experiments.localizations(treatmentID: t.id, client: client) {
          let media = try await LocalizationMedia.rows(locale: "", on: .treatmentLocalization(loc.id), client: client)
            .map { MediaEntry(id: $0[4], kind: $0[1], type: $0[2], state: $0[3]) }
          localizations.append(LocalizationEntry(id: loc.id, locale: loc.locale, media: media))
        }
        treatments.append(TreatmentEntry(id: t.id, name: t.name, appIconName: t.appIconName, localizations: localizations))
      }
      entry.treatments = treatments
      if jsonOption.json { try printJSON(entry); return }

      print(bold(entry.name ?? "-") + " (\(entry.id))")
      print("  Platform: \(formatState(entry.platform ?? "-"))")
      print("  State:    \(formatState(entry.state ?? "-"))")
      print("  Traffic:  \(entry.trafficProportion.map { "\($0)% of visitors see a treatment" } ?? "-")")
      if let start = entry.startDate { print("  Started:  \(formatDate(start))") }
      if let end = entry.endDate { print("  Ended:    \(formatDate(end))") }
      if entry.reviewRequired == true { print("  Needs App Review before it can start ('ascelerate experiments submit').") }
      print()
      guard !treatments.isEmpty else {
        print("No treatments yet. Add one with 'ascelerate experiments treatments add'.")
        return
      }
      for t in treatments {
        print(bold(t.name ?? "-") + " (\(t.id))" + (t.appIconName.map { ", app icon \($0)" } ?? ""))
        if t.localizations.isEmpty { print("  No localizations yet: upload media with 'ascelerate experiments media upload'.") }
        for loc in t.localizations {
          let counts = Dictionary(grouping: loc.media, by: \.type).sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value.count)" }
          print("  \(localeName(loc.locale ?? "-")): \(counts.isEmpty ? "no media" : counts.joined(separator: ", "))")
        }
      }
    }
  }

  struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Create a test, optionally with its treatments.",
      discussion: "Then upload each treatment's media ('experiments media upload'), submit it for review if needed, and start it."
    )

    @Argument(help: "Bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .long, help: "Test name.")
    var name: String

    @Option(name: .long, help: "Share of App Store visitors who see one of the treatments, in percent.")
    var traffic: Int

    @Option(name: .long, help: "Platform: ios, macos, tvos, visionos (default ios).")
    var platform = "ios"

    @Option(name: .long, help: "Treatment name (repeat for up to three).")
    var treatment: [String] = []

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func validate() throws {
      guard (1...100).contains(traffic) else { throw ValidationError("--traffic is a percentage (1-100).") }
      guard treatment.count <= 3 else { throw ValidationError("A test has at most three treatments.") }
    }

    func run() async throws {
      if yes { autoConfirm = true }
      let platform = try parsePlatform(platform)
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      print("Test '\(name)' for \(app.attributes?.name ?? bundleID) (\(formatState(platform.rawValue))), \(traffic)% of visitors")
      if !treatment.isEmpty { print("  Treatments: \(treatment.joined(separator: ", "))") }
      guard confirm("Create it? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      let created = try await unlessDryRunStopped {
        try await Experiments.create(appID: app.id, name: name, platform: platform.rawValue, trafficProportion: traffic, client: client)
      }
      if let created { print(green("Created") + " test \(created.id).") }
      for name in treatment {
        try await Treatments.add(name: name, appIcon: nil, experimentID: created?.id ?? "DRY-RUN-EXPERIMENT", client: client)
      }
    }
  }

  struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Rename a test or change its traffic share.")

    @OptionGroup var target: Target

    @Option(name: .long, help: "New name.")
    var name: String?

    @Option(name: .long, help: "Share of visitors who see a treatment, in percent.")
    var traffic: Int?

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func validate() throws {
      guard name != nil || traffic != nil else { throw ValidationError("Pass --name and/or --traffic.") }
      if let traffic, !(1...100).contains(traffic) { throw ValidationError("--traffic is a percentage (1-100).") }
    }

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let (_, experiment) = try await target.resolve(client)
      guard confirm("Update test '\(experiment.name)'? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      try await Experiments.update(id: experiment.id, name: name, trafficProportion: traffic, client: client)
      print(green("Updated") + " test '\(name ?? experiment.name)'.")
    }
  }

  struct Delete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Delete a test that hasn't run.")

    @OptionGroup var target: Target

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let (_, experiment) = try await target.resolve(client)
      guard confirm("Delete test '\(experiment.name)' and its treatments? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      try await Experiments.delete(id: experiment.id, state: experiment.state, client: client)
      print(green("Deleted") + " test '\(experiment.name)'.")
    }
  }

  struct Start: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Start a test (after App Review approved it, when it needed review).")

    @OptionGroup var target: Target

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let (_, experiment) = try await target.resolve(client)
      guard confirm("Start test '\(experiment.name)'? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      try await Experiments.start(id: experiment.id, client: client)
      print(green("Started") + " test '\(experiment.name)'.")
    }
  }

  struct Stop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop a running test.")

    @OptionGroup var target: Target

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let (_, experiment) = try await target.resolve(client)
      guard confirm("Stop test '\(experiment.name)'? It can't be restarted. [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      try await Experiments.stop(id: experiment.id, client: client)
      print(green("Stopped") + " test '\(experiment.name)'.")
    }
  }

  struct Submit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Submit a test's new media for App Review.",
      discussion: """
        Without an open submission for the platform, this creates one with just the test and submits it.
        With a draft submission that holds other items (an app version), the test is added to it and goes
        to review with them ('ascelerate apps review submit').
        """
    )

    @OptionGroup var target: Target

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let (app, experiment) = try await target.resolve(client)
      let platform = experiment.platform ?? "IOS"
      let open = try await client.appsReviewSubmissionsGetToManyRelated(
        path: .init(id: app.id), query: .init(filterState: [.readyForReview, .waitingForReview, .inReview, .unresolvedIssues])
      ).ok.body.json.data.first { $0.attributes?.platform == platform }
      if let state = open?.attributes?.state, ["WAITING_FOR_REVIEW", "IN_REVIEW"].contains(state) {
        throw ValidationError("A \(formatState(platform)) submission is already \(formatState(state).lowercased()); submit the test once it's done.")
      }
      var otherItems = 0
      if let open {
        otherItems = try await client.reviewSubmissionsItemsGetToManyRelated(path: .init(id: open.id), query: .init()).ok.body.json.data.count
      }

      let plan = open == nil || otherItems == 0
        ? "Submit test '\(experiment.name)' for App Review?"
        : "Add test '\(experiment.name)' to the draft \(formatState(platform)) submission (\(otherItems) other item(s))?"
      guard confirm("\(plan) [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      // Without an open submission, a new one (a placeholder ID under dry run).
      let submission = try await ReviewSubmissions.add(
        .experiment(experiment.id), appID: app.id, platform: platform, draftID: open?.id, client: client)
      guard otherItems == 0 else {
        print(green("Added") + " the test to the draft submission. It goes to review with the submission's other items ('ascelerate apps review submit').")
        return
      }
      try await ReviewSubmissions.submit(id: submission, client: client)
      print(green("Submitted") + " test '\(experiment.name)' for App Review. Start it once it's approved ('ascelerate experiments start').")
    }
  }

  // MARK: - Treatments

  struct Treatments: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "treatments",
      abstract: "Add, change or delete a test's treatments.",
      subcommands: [Add.self, Update.self, Delete.self, RemoveLocale.self]
    )

    static func add(name: String, appIcon: String?, experimentID: String, client: ASCClient) async throws {
      let created = try await unlessDryRunStopped {
        try await Experiments.createTreatment(experimentID: experimentID, name: name, appIconName: appIcon, client: client)
      }
      if let created { print(green("Added") + " treatment '\(name)' (\(created.id)).") }
    }

    struct Add: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Add a treatment (up to three per test).")

      @OptionGroup var target: Target

      @Option(name: .long, help: "Treatment name.")
      var name: String

      @Option(name: .long, help: "Alternate app icon to test (its name in the build's asset catalog).")
      var appIcon: String?

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (_, experiment) = try await target.resolve(client)
        guard confirm("Add treatment '\(name)' to '\(experiment.name)'? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        try await Treatments.add(name: name, appIcon: appIcon, experimentID: experiment.id, client: client)
      }
    }

    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Rename a treatment or change its app icon.")

      @OptionGroup var target: Target

      @Argument(help: "Treatment name or ID.")
      var treatment: String

      @Option(name: .long, help: "New name.")
      var name: String?

      @Option(name: .long, help: "Alternate app icon name.")
      var appIcon: String?

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func validate() throws {
        guard name != nil || appIcon != nil else { throw ValidationError("Pass --name and/or --app-icon.") }
      }

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (_, experiment) = try await target.resolve(client)
        let t = try await ExperimentsCommand.treatment(treatment, experimentID: experiment.id, client: client)
        guard confirm("Update treatment '\(t.name)'? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        try await Experiments.updateTreatment(id: t.id, name: name, appIconName: appIcon.map { .some($0) }, client: client)
        print(green("Updated") + " treatment '\(name ?? t.name)'.")
      }
    }

    struct Delete: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Delete a treatment and its media.")

      @OptionGroup var target: Target

      @Argument(help: "Treatment name or ID.")
      var treatment: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (_, experiment) = try await target.resolve(client)
        let t = try await ExperimentsCommand.treatment(treatment, experimentID: experiment.id, client: client)
        guard confirm("Delete treatment '\(t.name)'? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        try await Experiments.deleteTreatment(id: t.id, client: client)
        print(green("Deleted") + " treatment '\(t.name)'.")
      }
    }

    struct RemoveLocale: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Remove a locale (and its media) from a treatment; that locale then shows the original page.")

      @OptionGroup var target: Target

      @Argument(help: "Treatment name or ID.")
      var treatment: String

      @Option(name: .long, help: "Locale to remove (e.g. de-DE).")
      var locale: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (_, experiment) = try await target.resolve(client)
        let t = try await ExperimentsCommand.treatment(treatment, experimentID: experiment.id, client: client)
        guard let loc = try await Experiments.localizations(treatmentID: t.id, client: client)
          .first(where: { $0.locale.lowercased() == locale.lowercased() })
        else { throw ValidationError("Treatment '\(t.name)' has no \(locale) localization.") }
        guard confirm("Remove \(localeName(locale)) from treatment '\(t.name)'? [y/N] ") else {
          print(yellow("Cancelled."))
          return
        }
        try await Experiments.deleteLocalization(id: loc.id, client: client)
        print(green("Removed") + " \(localeName(locale)).")
      }
    }
  }

  // MARK: - Media

  struct Media: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "media",
      abstract: "Treatment screenshots, app previews and library images.",
      subcommands: [List.self, Upload.self, Delete.self]
    )

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "List the media of every treatment (or one).")

      @OptionGroup var target: Target

      @Option(name: .long, help: "Only this treatment (name or ID).")
      var treatment: String?

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let (_, experiment) = try await target.resolve(client)
        var treatments = try await Experiments.treatments(experimentID: experiment.id, client: client)
        if let treatment { treatments = [try await ExperimentsCommand.treatment(treatment, experimentID: experiment.id, client: client)] }
        var rows: [[String]] = []
        for t in treatments {
          for loc in try await Experiments.localizations(treatmentID: t.id, client: client) {
            rows += try await LocalizationMedia.rows(locale: loc.locale.isEmpty ? "?" : loc.locale, on: .treatmentLocalization(loc.id), client: client)
              .map { [t.name] + $0 }
          }
        }
        guard !rows.isEmpty else {
          print("No media yet.")
          return
        }
        Table.print(headers: ["Treatment", "Locale", "Kind", "Type", "State", "Media ID"], rows: rows)
      }
    }

    struct Upload: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Upload a screenshot (.png/.jpg) or app preview (.mp4/.mov) to a treatment's locale.",
        discussion: LocalizationMedia.uploadDiscussion + "\nThe treatment's localization is created when it doesn't exist yet."
      )

      @OptionGroup var target: Target

      @Argument(help: "Treatment name or ID.")
      var treatment: String

      @Option(name: .long, help: "Locale (e.g. en-US).")
      var locale: String

      @Option(name: .long, help: "Screenshot display type for images (e.g. APP_IPHONE_67).")
      var displayType: String?

      @Option(name: .long, help: "Preview type for videos (e.g. APP_IPHONE_67).")
      var previewType: String?

      @Option(name: .long, help: "Preview frame timecode for app previews, hh:mm:ss:frame (e.g. 00:00:03:00).")
      var previewFrame: String?

      @Argument(help: "Path to the media file.", completion: .file(extensions: ["png", "jpg", "jpeg", "mp4", "mov"]))
      var file: String

      @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (app, experiment) = try await target.resolve(client)
        let t = try await ExperimentsCommand.treatment(treatment, experimentID: experiment.id, client: client)
        let existing = try await Experiments.localizations(treatmentID: t.id, client: client)
          .first { $0.locale.lowercased() == locale.lowercased() }
        try await LocalizationMedia.upload(
          file: file, displayType: displayType, previewType: previewType, previewFrame: previewFrame, appID: app.id,
          context: [
            ("Test", experiment.name), ("Treatment", t.name),
            ("Locale", localeName(locale) + (existing == nil ? " (new)" : "")),
          ],
          client: client, owner: existing.map { .treatmentLocalization($0.id) },
          createOwner: {
            let created = try await unlessDryRunStopped {
              try await Experiments.createLocalization(treatmentID: t.id, locale: locale, client: client).id
            }
            return .treatmentLocalization(created ?? "DRY-RUN-LOCALIZATION")
          })
      }
    }

    struct Delete: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Delete a screenshot, app preview or library image (IDs from 'experiments media list').")

      @OptionGroup var target: Target

      @Argument(help: "Media ID.")
      var mediaID: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (_, experiment) = try await target.resolve(client)
        var owners: [AssetLibrary.Owner] = []
        for t in try await Experiments.treatments(experimentID: experiment.id, client: client) {
          owners += try await Experiments.localizations(treatmentID: t.id, client: client).map { .treatmentLocalization($0.id) }
        }
        try await LocalizationMedia.delete(mediaID: mediaID, among: owners, client: client)
      }
    }
  }
}
