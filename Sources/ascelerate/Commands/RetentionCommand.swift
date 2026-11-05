import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

/// Retention messaging: the message the App Store shows a subscriber going to cancel, and the
/// retention offers it can show (`RetentionMessages`).
extension SubCommand {
  /// Retention and win-back offers' eligibility, as Apple takes it.
  static func checkOfferEligibility(paidMonths: Int?, waitMonths: Int?) throws {
    if let paidMonths, !Subscriptions.offerPaidMonths.contains(paidMonths) {
      throw ValidationError("--paid-months takes 1–24, 36, 48 or 60.")
    }
    if let waitMonths, !Subscriptions.offerWaitMonths.contains(waitMonths) {
      throw ValidationError("--wait-months takes 2–24.")
    }
  }

  struct RetentionMessage: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "retention-message",
      abstract: "Manage retention messages: what the App Store shows subscribers who go to cancel.",
      discussion: """
        A message is the app's: a header (66 characters at most) and body (144) per language and an \
        optional 16:9 image, in versions that App Review approves (one unreleased at a time). Each \
        subscription shows one message, with any of its retention offers ('sub retention-offer').
        """,
      subcommands: [
        List.self, Info.self, Create.self, Delete.self, NewVersion.self, Localizations.self, Image.self, Assign.self,
        Submit.self,
      ],
      defaultSubcommand: List.self
    )

    /// Every message with its subscriptions' product IDs, for listing and naming.
    static func context(bundleID: String, client: ASCClient) async throws
      -> (app: Components.Schemas.App, messages: [RetentionMessages.Message], products: [String: String])
    {
      let app = try await findApp(bundleID: bundleID, client: client)
      async let messages = RetentionMessages.list(appID: app.id, client: client)
      async let groups = SubCommand.fetchGroups(appID: app.id, client: client)
      let products = Dictionary(
        try await groups.flatMap(\.subscriptions).map { ($0.id, $0.productID) }, uniquingKeysWith: { first, _ in first })
      return (app, try await messages, products)
    }

    static func find(_ nameOrID: String, in messages: [RetentionMessages.Message]) throws -> RetentionMessages.Message {
      guard
        let message = messages.first(where: { $0.id == nameOrID || $0.name.caseInsensitiveCompare(nameOrID) == .orderedSame })
      else { throw RetentionError.noMessage(nameOrID, known: messages.map(\.name)) }
      return message
    }

    /// The version that takes changes; an error naming the latest one's state otherwise.
    static func editableVersion(of message: RetentionMessages.Message) throws -> RetentionMessages.Version {
      guard let version = message.current, version.isEditable else {
        throw RetentionError.noEditableVersion(message.current?.state ?? "")
      }
      return version
    }

    static func checkFields(header: String, body: String) throws {
      let problems = RetentionMessages.problems(header: header, body: body)
      guard problems.isEmpty else { throw ValidationError(problems.joined(separator: " ")) }
    }

    struct Arguments: ParsableArguments {
      @Argument(help: "The bundle identifier of the app.", completion: appAliasCompletion)
      var bundleID: String

      @Argument(help: "The message's reference name or ID.")
      var message: String
    }

    // MARK: List

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "List the app's retention messages.")

      @Argument(help: "The bundle identifier of the app.", completion: appAliasCompletion)
      var bundleID: String

      @OptionGroup var jsonOption: JSONOption

      struct Entry: Encodable {
        let id: String
        let name: String
        let state: String?
        let subscriptions: [String]
      }

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let (_, messages, products) = try await RetentionMessage.context(bundleID: bundleID, client: client)
        let entries = messages.map {
          Entry(id: $0.id, name: $0.name, state: $0.current?.state, subscriptions: $0.subscriptionIDs.map { products[$0] ?? $0 })
        }
        if jsonOption.json { return try printJSON(entries) }
        guard !entries.isEmpty else {
          print("No retention messages. Create one with: ascelerate sub retention-message create \(bundleID) --name X")
          return
        }
        Table.print(
          headers: ["Name", "Version", "Subscriptions", "ID"],
          rows: entries.map { [$0.name, $0.state.map(formatState) ?? "—", $0.subscriptions.joined(separator: ", "), $0.id] })
      }
    }

    // MARK: Info

    struct Info: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Show a retention message: its versions, languages, image and the subscriptions showing it.")

      @OptionGroup var arguments: Arguments
      @OptionGroup var jsonOption: JSONOption

      struct Detail: Encodable {
        struct Version: Encodable {
          let id: String
          let state: String
        }
        struct Language: Encodable {
          let locale: String
          let header: String
          let body: String
        }
        struct Image: Encodable {
          let fileName: String?
          let state: String?
        }
        struct Subscription: Encodable {
          let productID: String
          let offers: [String]
        }
        let id: String
        let name: String
        let versions: [Version]
        let languages: [Language]
        let image: Image?
        let subscriptions: [Subscription]
      }

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let (_, messages, products) = try await RetentionMessage.context(bundleID: arguments.bundleID, client: client)
        let message = try RetentionMessage.find(arguments.message, in: messages)
        var languages: [RetentionMessages.Localization] = []
        var image: RetentionMessages.Image?
        if let version = message.current {
          async let readLanguages = RetentionMessages.localizations(versionID: version.id, client: client)
          async let readImage = RetentionMessages.image(versionID: version.id, client: client)
          (languages, image) = (try await readLanguages, try await readImage)
        }
        var subscriptions: [Detail.Subscription] = []
        for id in message.subscriptionIDs {
          let shown = try await RetentionMessages.shownOffers(subscriptionID: id, client: client)
          let offers = try await Subscriptions.retentionOffers(subscriptionID: id, client: client)
          let names = shown.map { id in offers.first { $0.id == id }.flatMap { $0.offerID ?? $0.name } ?? id }
          subscriptions.append(Detail.Subscription(productID: products[id] ?? id, offers: names))
        }
        let detail = Detail(
          id: message.id, name: message.name, versions: message.versions.map { .init(id: $0.id, state: $0.state) },
          languages: languages.map { .init(locale: $0.locale, header: $0.header, body: $0.body) },
          image: image.map { .init(fileName: $0.fileName, state: $0.state) }, subscriptions: subscriptions)
        if jsonOption.json { return try printJSON(detail) }

        print("Retention Message: \(detail.name)")
        print("ID:                \(detail.id)")
        print("Version:           \(message.current.map { formatState($0.state) } ?? "—")")
        print("Image:             \(image.map { "\($0.fileName ?? "—") (\(formatState($0.state ?? "")))" } ?? "—")")
        print()
        if languages.isEmpty {
          print("No languages yet. Add one with: ascelerate sub retention-message localizations set \(arguments.bundleID) \"\(message.name)\" --locale en-US --header X --body X")
        } else {
          for language in languages {
            print(bold(localeName(language.locale)))
            print("  \(language.header)")
            print("  \(language.body)")
          }
        }
        print()
        if subscriptions.isEmpty {
          print("No subscription shows it. Show it with: ascelerate sub retention-message assign \(arguments.bundleID) <product-id> \"\(message.name)\"")
        } else {
          Table.print(
            headers: ["Subscription", "Offers Shown"],
            rows: subscriptions.map { [$0.productID, $0.offers.isEmpty ? "—" : $0.offers.joined(separator: ", ")] })
        }
      }
    }

    // MARK: Create

    struct Create: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Create a retention message, optionally with its first language.")

      @Argument(help: "The bundle identifier of the app.", completion: appAliasCompletion)
      var bundleID: String

      @Option(name: .long, help: "The message's reference name (not shown to subscribers).")
      var name: String

      @Option(name: .long, help: "A first language (e.g. en-US), with --header and --body.")
      var locale: String?

      @Option(name: .long, help: "The header in that language (66 characters at most).")
      var header: String?

      @Option(name: .long, help: "The body in that language (144 characters at most).")
      var body: String?

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        guard (locale == nil) == (header == nil) && (header == nil) == (body == nil) else {
          throw ValidationError("--locale, --header and --body go together.")
        }
        if let header, let body { try RetentionMessage.checkFields(header: header, body: body) }
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: bundleID, client: client)
        print("Create retention message '\(name)'\(locale.map { " with \(localeName($0))" } ?? "").")
        guard confirm("Create it? [y/N] ") else { return cancelled() }
        let created = try await RetentionMessages.create(appID: app.id, name: name, client: client)
        if let locale, let header, let body {
          try await RetentionMessages.save(
            locale: locale, header: header, body: body, versionID: created.version, existing: nil, client: client)
        }
        success("Created", "retention message '\(name)' (id: \(created.message)).")
      }
    }

    // MARK: Delete

    struct Delete: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Delete a retention message.", discussion: "Subscriptions showing it then show none.")

      @OptionGroup var arguments: Arguments

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (_, messages, products) = try await RetentionMessage.context(bundleID: arguments.bundleID, client: client)
        let message = try RetentionMessage.find(arguments.message, in: messages)
        if !message.subscriptionIDs.isEmpty {
          print(yellow("Shown by: \(message.subscriptionIDs.map { products[$0] ?? $0 }.joined(separator: ", "))"))
        }
        guard confirm("Delete retention message '\(message.name)'? [y/N] ") else { return cancelled() }
        try await RetentionMessages.delete(message, client: client)
        success("Deleted", "retention message '\(message.name)'.")
      }
    }

    // MARK: New version

    struct NewVersion: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "new-version",
        abstract: "Start a new version of a retention message, to change it after App Review has the last one.")

      @OptionGroup var arguments: Arguments

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (_, messages, _) = try await RetentionMessage.context(bundleID: arguments.bundleID, client: client)
        let message = try RetentionMessage.find(arguments.message, in: messages)
        if let current = message.current, current.isEditable {
          throw ValidationError("'\(message.name)' already has a version that can change (\(formatState(current.state))).")
        }
        guard confirm("Start a new version of '\(message.name)'? [y/N] ") else { return cancelled() }
        let id = try await RetentionMessages.createVersion(messageID: message.id, client: client)
        success("Created", "a new version (id: \(id)). Add its languages with 'localizations set'.")
      }
    }

    // MARK: Languages

    struct Localizations: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "View or change a retention message's languages.",
        subcommands: [View.self, Set.self, Delete.self],
        defaultSubcommand: View.self
      )

      struct View: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show the header and body in each language.")

        @OptionGroup var arguments: Arguments

        func run() async throws {
          let client = try ClientFactory.makeClient()
          let (_, messages, _) = try await RetentionMessage.context(bundleID: arguments.bundleID, client: client)
          let message = try RetentionMessage.find(arguments.message, in: messages)
          guard let version = message.current else { return print("'\(message.name)' has no version.") }
          let languages = try await RetentionMessages.localizations(versionID: version.id, client: client)
          guard !languages.isEmpty else { return print("'\(message.name)' has no languages yet.") }
          Table.print(
            headers: ["Language", "Header", "Body"],
            rows: languages.map { [localeName($0.locale), $0.header, $0.body] })
        }
      }

      struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Set a language's header and body (adds the language when it's new).")

        @OptionGroup var arguments: Arguments

        @Option(name: .long, help: "The language (e.g. en-US).")
        var locale: String

        @Option(name: .long, help: "The header (66 characters at most).")
        var header: String

        @Option(name: .long, help: "The body (144 characters at most).")
        var body: String

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          try RetentionMessage.checkFields(header: header, body: body)
          let client = try ClientFactory.makeClient()
          let (_, messages, _) = try await RetentionMessage.context(bundleID: arguments.bundleID, client: client)
          let message = try RetentionMessage.find(arguments.message, in: messages)
          let version = try RetentionMessage.editableVersion(of: message)
          let existing = try await RetentionMessages.localizations(versionID: version.id, client: client)
            .first { $0.locale.caseInsensitiveCompare(locale) == .orderedSame }
          print("\(existing == nil ? "Add" : "Change") \(localeName(locale)) of '\(message.name)':")
          if let existing {
            print("  Header: \(existing.header) → \(header)")
            print("  Body:   \(existing.body) → \(body)")
          } else {
            print("  Header: \(header)")
            print("  Body:   \(body)")
          }
          guard confirm("Save? [y/N] ") else { return cancelled() }
          try await RetentionMessages.save(
            locale: existing?.locale ?? locale, header: header, body: body, versionID: version.id, existing: existing, client: client)
          success("Saved", localeName(locale))
        }
      }

      struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove a language.")

        @OptionGroup var arguments: Arguments

        @Option(name: .long, help: "The language (e.g. en-US).")
        var locale: String

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          let client = try ClientFactory.makeClient()
          let (_, messages, _) = try await RetentionMessage.context(bundleID: arguments.bundleID, client: client)
          let message = try RetentionMessage.find(arguments.message, in: messages)
          let version = try RetentionMessage.editableVersion(of: message)
          guard
            let existing = try await RetentionMessages.localizations(versionID: version.id, client: client)
              .first(where: { $0.locale.caseInsensitiveCompare(locale) == .orderedSame })
          else { throw ValidationError("'\(message.name)' has no \(localeName(locale)).") }
          guard confirm("Remove \(localeName(existing.locale)) from '\(message.name)'? [y/N] ") else { return cancelled() }
          try await RetentionMessages.deleteLocalization(id: existing.id, client: client)
          success("Removed", localeName(existing.locale))
        }
      }
    }

    // MARK: Image

    struct Image: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Upload or delete a retention message's image (one per version, 16:9).",
        subcommands: [Upload.self, Delete.self]
      )

      struct Upload: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Upload the image, replacing the current one: 3840×2160 PNG or JPEG, or 5244×2950 PNG, without transparency.")

        @OptionGroup var arguments: Arguments

        @Argument(help: "The image file.", completion: .file(extensions: ["png", "jpg", "jpeg"]))
        var file: String

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          let media = try MediaFile(readingFrom: file)
          try AssetLibrary.validateSize(of: media, slot: RetentionMessages.imageSlot)
          let client = try ClientFactory.makeClient()
          let (app, messages, _) = try await RetentionMessage.context(bundleID: arguments.bundleID, client: client)
          let message = try RetentionMessage.find(arguments.message, in: messages)
          let version = try RetentionMessage.editableVersion(of: message)
          let current = try await RetentionMessages.image(versionID: version.id, client: client)
          print("\(current == nil ? "Upload" : "Replace") the image of '\(message.name)' with \(media.fileName) (\(formatBytes(media.fileSize))).")
          guard confirm("Upload? [y/N] ") else { return cancelled() }
          let libraryID = try await AssetLibrary.libraryID(appID: app.id, client: client)
          _ = try await AssetLibrary.uploadAndPlace(
            media, slot: RetentionMessages.imageSlot, on: .retentionMessageVersion(version.id), libraryID: libraryID,
            replacing: current.map { [$0.placementID] } ?? [], client: client)
          success("Uploaded", media.fileName)
        }
      }

      struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove the image (and delete it from the library when unused).")

        @OptionGroup var arguments: Arguments

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
          if yes { autoConfirm = true }
          let client = try ClientFactory.makeClient()
          let (_, messages, _) = try await RetentionMessage.context(bundleID: arguments.bundleID, client: client)
          let message = try RetentionMessage.find(arguments.message, in: messages)
          let version = try RetentionMessage.editableVersion(of: message)
          guard let image = try await RetentionMessages.image(versionID: version.id, client: client) else {
            throw ValidationError("'\(message.name)' has no image.")
          }
          guard confirm("Remove the image \(image.fileName ?? "") from '\(message.name)'? [y/N] ") else { return cancelled() }
          try await AssetLibrary.removePlacement(id: image.placementID, client: client)
          success("Removed", "the image.")
        }
      }
    }

    // MARK: Assign

    struct Assign: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Set the retention message a subscription shows, and its retention offers in it.")

      @Argument(help: "The bundle identifier of the app.", completion: appAliasCompletion)
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String

      @Argument(help: "The message's reference name or ID, or 'none'.")
      var message: String

      @Option(name: .long, help: "The retention offers it shows, by offer ID (comma-separated), or 'none'. Left as they are when omitted.")
      var offers: String?

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (app, messages, _) = try await RetentionMessage.context(bundleID: bundleID, client: client)
        let (sub, _) = try await SubCommand.findSubscription(productID: productID, appID: app.id, client: client)
        let chosen = message.lowercased() == "none" ? nil : try RetentionMessage.find(message, in: messages)
        var offerIDs: [String]?
        if let offers {
          let available = try await Subscriptions.retentionOffers(subscriptionID: sub.id, client: client)
          offerIDs = try offers.lowercased() == "none" ? [] : offers.split(separator: ",").map { part in
            let name = part.trimmingCharacters(in: .whitespaces)
            guard let offer = available.first(where: { $0.offerID == name || $0.id == name }) else {
              throw ValidationError("'\(productID)' has no retention offer '\(name)'. Its offers: \(available.compactMap(\.offerID).joined(separator: ", ")).")
            }
            return offer.id
          }
        }
        print("\(productID): show \(chosen.map { "'\($0.name)'" } ?? "no retention message")\(offers.map { ", offers: \($0)" } ?? "").")
        guard confirm("Save? [y/N] ") else { return cancelled() }
        try await RetentionMessages.assign(chosen?.id, subscriptionID: sub.id, client: client)
        if let offerIDs { try await RetentionMessages.showOffers(offerIDs, subscriptionID: sub.id, client: client) }
        success("Saved", productID)
      }
    }

    // MARK: Submit

    struct Submit: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Add a retention message's version to the draft review submission.",
        discussion: "Submit the draft with 'apps review submit', with or without an app version.")

      @OptionGroup var arguments: Arguments

      @Option(name: .long, help: "The submission's platform: ios, macos, tvos, visionos (default ios).")
      var platform: String?

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let (app, messages, _) = try await RetentionMessage.context(bundleID: arguments.bundleID, client: client)
        let message = try RetentionMessage.find(arguments.message, in: messages)
        let version = try RetentionMessage.editableVersion(of: message)
        let platform = (try platform.map(parsePlatform) ?? .ios).rawValue
        guard confirm("Add '\(message.name)' to the \(formatState(platform)) draft submission? [y/N] ") else { return cancelled() }
        try await ReviewSubmissions.add(
          RetentionMessages.reviewItem(versionID: version.id), appID: app.id, platform: platform, client: client)
        guard !ClientFactory.isDryRun else { return print("Dry run: nothing was added.") }
        success("Added", "'\(message.name)' to the draft submission. Submit it with: ascelerate apps review submit \(arguments.bundleID)")
      }
    }
  }

  struct RetentionOffer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "retention-offer",
      abstract: "Manage retention offers: what a subscription's retention message can offer subscribers who go to cancel.",
      subcommands: [List.self, Info.self, Create.self, Update.self, Delete.self],
      defaultSubcommand: List.self
    )

    struct Arguments: ParsableArguments {
      @Argument(help: "The bundle identifier of the app.", completion: appAliasCompletion)
      var bundleID: String

      @Argument(help: "The product identifier of the subscription.")
      var productID: String
    }

    /// The subscription and its offers, and the one named (by offer ID or ID).
    static func find(_ name: String, arguments: Arguments, client: ASCClient) async throws -> Subscriptions.RetentionOffer {
      let app = try await findApp(bundleID: arguments.bundleID, client: client)
      let (sub, _) = try await SubCommand.findSubscription(productID: arguments.productID, appID: app.id, client: client)
      let offers = try await Subscriptions.retentionOffers(subscriptionID: sub.id, client: client)
      guard let offer = offers.first(where: { $0.offerID == name || $0.id == name }) else {
        throw ValidationError("'\(arguments.productID)' has no retention offer '\(name)'.")
      }
      return offer
    }

    static func eligibility(_ offer: Subscriptions.RetentionOffer) -> String {
      let paid = offer.paidMonths.map { "paid \($0) month\($0 == 1 ? "" : "s")" } ?? "—"
      return paid + (offer.waitMonths.map { ", \($0) months since the last offer" } ?? "")
    }


    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "List a subscription's retention offers.")

      @OptionGroup var arguments: Arguments
      @OptionGroup var jsonOption: JSONOption

      struct Entry: Encodable {
        let id: String
        let offerID: String?
        let name: String?
        let mode: String?
        let duration: String?
        let periods: Int?
        let paidMonths: Int?
        let waitMonths: Int?
        let planType: String?
      }

      func run() async throws {
        jsonOption.activate()
        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: arguments.bundleID, client: client)
        let (sub, _) = try await SubCommand.findSubscription(productID: arguments.productID, appID: app.id, client: client)
        let offers = try await Subscriptions.retentionOffers(subscriptionID: sub.id, client: client)
        if jsonOption.json {
          return try printJSON(offers.map {
            Entry(
              id: $0.id, offerID: $0.offerID, name: $0.name, mode: $0.mode, duration: $0.duration, periods: $0.periods,
              paidMonths: $0.paidMonths, waitMonths: $0.waitMonths, planType: $0.planType)
          })
        }
        guard !offers.isEmpty else { return print("No retention offers for \(arguments.productID).") }
        Table.print(
          headers: ["Offer ID", "Name", "Mode", "Duration", "Eligibility", "Plan"],
          rows: offers.map { o in
            [
              o.offerID ?? "—", o.name ?? "—", o.mode.map(formatState) ?? "—",
              "\(o.periods.map(String.init) ?? "—") × \(o.duration.map(formatState) ?? "—")", eligibility(o),
              o.planType.map(formatState) ?? "—",
            ]
          })
      }
    }

    struct Info: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Show a retention offer.")

      @OptionGroup var arguments: Arguments

      @Argument(help: "The offer's offer ID (or its App Store Connect ID).")
      var offer: String

      func run() async throws {
        let client = try ClientFactory.makeClient()
        let found = try await RetentionOffer.find(offer, arguments: arguments, client: client)
        let (offer, priceCount) = try await Subscriptions.retentionOffer(id: found.id, client: client)
        print("Retention Offer: \(offer.name ?? "—")")
        print("Offer ID:        \(offer.offerID ?? "—")")
        print("Mode:            \(offer.mode.map(formatState) ?? "—")")
        print("Duration:        \(offer.periods.map(String.init) ?? "—") × \(offer.duration.map(formatState) ?? "—")")
        print("Eligibility:     \(RetentionOffer.eligibility(offer))")
        print("Plan:            \(offer.planType.map(formatState) ?? "—")")
        print("Prices:          \(priceCount) territor\(priceCount == 1 ? "y" : "ies")")
        print("ID:              \(offer.id)")
      }
    }

    struct Create: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Create a retention offer.",
        discussion: """
          A paid offer takes --price in the first of --territories, and Apple's comparable prices \
          in the others; a free trial takes none. Show it in the subscription's retention message \
          with 'sub retention-message assign … --offers'.
          """)

      @OptionGroup var arguments: Arguments

      @Option(name: .long, help: "The offer's reference name.")
      var name: String

      @Option(name: .customLong("offer-id"), help: "The offer's identifier (unique within the subscription).")
      var offerID: String

      @Option(name: .long, help: "FREE_TRIAL, PAY_AS_YOU_GO or PAY_UP_FRONT.")
      var mode: String

      @Option(name: .long, help: "How long a period lasts: THREE_DAYS, ONE_WEEK, TWO_WEEKS, ONE_MONTH, TWO_MONTHS, THREE_MONTHS, SIX_MONTHS, ONE_YEAR.")
      var duration: String

      @Option(name: .long, help: "How many periods.")
      var periods: Int = 1

      @Option(name: .customLong("paid-months"), help: "Who's eligible: subscribers who paid at least this many months (1–24, 36, 48 or 60).")
      var paidMonths: Int

      @Option(name: .customLong("wait-months"), help: "Who's eligible: at least this many months since their last offer (2–24).")
      var waitMonths: Int?

      @Option(name: .long, help: "The billing plan it's for: upfront (default) or monthly.")
      var plan: String?

      @Option(name: .long, help: "The price in the first territory (not for FREE_TRIAL).")
      var price: String?

      @Option(name: .long, help: "Territories (comma-separated, the first one's price is --price) or 'all' (the subscription's).")
      var territories: String = "all"

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let offerMode: ASCEnum.SubscriptionOfferMode = try parseEnum(mode, name: "mode")
        let offerDuration: ASCEnum.SubscriptionOfferDuration = try parseEnum(duration, name: "duration")
        let planType: ASCEnum.SubscriptionPlanType? = try plan.map { try parseEnum($0, name: "plan") }
        guard periods > 0 else { throw ValidationError("--periods must be greater than 0.") }
        if offerMode == .freeTrial, price != nil { throw ValidationError("--price is not allowed for FREE_TRIAL.") }
        if offerMode != .freeTrial, price == nil { throw ValidationError("--price is required for \(offerMode.rawValue).") }
        try SubCommand.checkOfferEligibility(paidMonths: paidMonths, waitMonths: waitMonths)

        let client = try ClientFactory.makeClient()
        let app = try await findApp(bundleID: arguments.bundleID, client: client)
        let (sub, _) = try await SubCommand.findSubscription(productID: arguments.productID, appID: app.id, client: client)
        let (listed, pricePoints, isAll) = try await SubCommand.offerTerritories(
          subscriptionID: sub.id, productID: arguments.productID, territories: territories, price: price, client: client)

        print()
        print("Create retention offer:")
        print("  Subscription:  \(arguments.productID)")
        print("  Name:          \(name) (\(offerID))")
        print("  Mode:          \(formatState(offerMode.rawValue)), \(periods) × \(formatState(offerDuration.rawValue))")
        print("  Eligibility:   paid \(paidMonths) month\(paidMonths == 1 ? "" : "s")\(waitMonths.map { ", \($0) months since the last offer" } ?? "")")
        if let planType { print("  Plan:          \(formatState(planType.rawValue))") }
        if let price { print("  Price:         \(price) in \(listed[0]), comparable prices elsewhere") }
        print("  Territories:   \(isAll ? "All (\(listed.count))" : listed.joined(separator: ", "))")
        print()
        guard confirm("Create this offer? [y/N] ") else { return cancelled() }
        let created = try await Subscriptions.createRetentionOffer(
          subscriptionID: sub.id, name: name, offerID: offerID, mode: offerMode.rawValue, duration: offerDuration.rawValue,
          periods: periods, paidMonths: paidMonths, waitMonths: waitMonths, planType: planType?.rawValue,
          prices: listed.map { Subscriptions.OfferPrice(territoryID: $0, pricePointID: pricePoints[$0]) }, client: client)
        success("Created", "retention offer '\(name)' (offer ID \(created.offerID ?? offerID)).")
      }
    }

    struct Update: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Change a retention offer's eligibility.",
        discussion: """
          Only the eligibility can change; for anything else, delete the offer and create it again. A wait \
          between offers can't be removed once set (Apple fails the request).
          """)

      @OptionGroup var arguments: Arguments

      @Argument(help: "The offer's offer ID (or its App Store Connect ID).")
      var offer: String

      @Option(name: .customLong("paid-months"), help: "Subscribers who paid at least this many months (1–24, 36, 48 or 60).")
      var paidMonths: Int?

      @Option(name: .customLong("wait-months"), help: "Months since their last offer (2–24).")
      var waitMonths: Int?

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        guard paidMonths != nil || waitMonths != nil else { throw ValidationError("Nothing to change: pass --paid-months or --wait-months.") }
        try SubCommand.checkOfferEligibility(paidMonths: paidMonths, waitMonths: waitMonths)
        let client = try ClientFactory.makeClient()
        let found = try await RetentionOffer.find(offer, arguments: arguments, client: client)
        print("\(found.name ?? offer): \(RetentionOffer.eligibility(found)) → paid \(paidMonths ?? found.paidMonths ?? 0) months\((waitMonths ?? found.waitMonths).map { ", \($0) months since the last offer" } ?? "")")
        guard confirm("Save? [y/N] ") else { return cancelled() }
        try await Subscriptions.updateRetentionOffer(id: found.id, paidMonths: paidMonths, waitMonths: waitMonths, client: client)
        success("Saved", found.offerID ?? offer)
      }
    }

    struct Delete: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Delete a retention offer.")

      @OptionGroup var arguments: Arguments

      @Argument(help: "The offer's offer ID (or its App Store Connect ID).")
      var offer: String

      @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
      var yes = false

      func run() async throws {
        if yes { autoConfirm = true }
        let client = try ClientFactory.makeClient()
        let found = try await RetentionOffer.find(offer, arguments: arguments, client: client)
        guard confirm("Delete retention offer '\(found.name ?? offer)'? [y/N] ") else { return cancelled() }
        try await Subscriptions.deleteRetentionOffer(id: found.id, client: client)
        success("Deleted", "retention offer '\(found.name ?? offer)'.")
      }
    }
  }
}
