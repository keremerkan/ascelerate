import ArgumentParser
import ASCKit
import AscelerateCore
import Foundation

/// App Store Connect webhooks: Apple POSTs an app's events (version state, build uploads, TestFlight feedback, …)
/// to your URL, signed with the webhook's secret.
struct WebhooksCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "webhooks",
    abstract: "Manage App Store Connect webhooks (event notifications sent to your server).",
    subcommands: [List.self, Create.self, Update.self, Delete.self, Ping.self, Deliveries.self, Redeliver.self],
    defaultSubcommand: List.self
  )

  static let bundleIDHelp = ArgumentHelp("Bundle identifier of the app.")
  static let aliasCompletion = CompletionKind.shellCommand(
    "grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'")

  static func webhooks(appID: String, client: ASCClient) async throws -> [Components.Schemas.Webhook] {
    try await ASCPaging.allPages(next: { $0.links.next }) {
      try await client.appsWebhooksGetToManyRelated(path: .init(id: appID), query: .init(limit: 200)).ok.body.json
    }.flatMap(\.data)
  }

  /// Resolves a webhook name (case-insensitive) or ID among the app's webhooks.
  static func find(_ ref: String, bundleID: String, client: ASCClient) async throws -> Components.Schemas.Webhook {
    let app = try await findApp(bundleID: bundleID, client: client)
    let hooks = try await webhooks(appID: app.id, client: client)
    if let match = hooks.first(where: { $0.id == ref || $0.attributes?.name?.lowercased() == ref.lowercased() }) {
      return match
    }
    let names = hooks.compactMap { $0.attributes?.name }
    throw ValidationError("No webhook '\(ref)' found for \(bundleID)." + (names.isEmpty ? "" : " Webhooks: \(names.joined(separator: ", "))."))
  }

  /// `all`, or a comma list of event types (`build-upload-state-updated` or the API value).
  static func eventTypes(_ value: String) throws -> [String] {
    if value.lowercased() == "all" { return ASCEnum.WebhookEventType.allCases.map(\.rawValue) }
    return try value.split(separator: ",").map { item in
      let raw = item.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "-", with: "_")
      let type: ASCEnum.WebhookEventType = try parseEnum(raw, name: "event type")
      return type.rawValue
    }
  }

  static func name(_ hook: Components.Schemas.Webhook) -> String { hook.attributes?.name ?? hook.id }

  static let eventsHelp = ArgumentHelp(
    "Event types, comma-separated, or 'all': \(ASCEnum.WebhookEventType.allCases.map { $0.rawValue.lowercased().replacingOccurrences(of: "_", with: "-") }.joined(separator: ", ")).")

  struct Entry: Encodable {
    let id: String
    let name: String?
    let url: String?
    let enabled: Bool?
    let eventTypes: [String]?
  }

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the app's webhooks.")

    @Argument(help: WebhooksCommand.bundleIDHelp, completion: WebhooksCommand.aliasCompletion)
    var bundleID: String

    @OptionGroup var jsonOption: JSONOption

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      let entries = try await WebhooksCommand.webhooks(appID: app.id, client: client).map { h in
        Entry(id: h.id, name: h.attributes?.name, url: h.attributes?.url, enabled: h.attributes?.enabled, eventTypes: h.attributes?.eventTypes)
      }
      if jsonOption.json { try printJSON(entries); return }
      guard !entries.isEmpty else {
        print("No webhooks. Create one with 'ascelerate webhooks create'.")
        return
      }
      for e in entries {
        print(bold(e.name ?? "-") + " (\(e.id))" + (e.enabled == false ? yellow(" disabled") : ""))
        print("  URL:    \(e.url ?? "-")")
        print("  Events: \((e.eventTypes ?? []).map { formatState($0) }.joined(separator: ", "))")
      }
    }
  }

  struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Create a webhook.")

    @Argument(help: WebhooksCommand.bundleIDHelp, completion: WebhooksCommand.aliasCompletion)
    var bundleID: String

    @Option(name: .long, help: "Webhook name.")
    var name: String

    @Option(name: .long, help: "HTTPS URL Apple sends the events to.")
    var url: String

    @Option(name: .long, help: WebhooksCommand.eventsHelp)
    var events: String

    @Option(name: .long, help: "Signing secret (default: a random one, printed once).")
    var secret: String?

    @Flag(name: .long, help: "Create it disabled.")
    var disabled = false

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let types = try WebhooksCommand.eventTypes(events)
      let secret = secret ?? (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)
      print("Webhook '\(name)' for \(app.attributes?.name ?? bundleID) → \(url)\(disabled ? " (disabled)" : "")")
      print("  Events: \(types.map { formatState($0) }.joined(separator: ", "))")
      guard confirm("Create it? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      let created = try await client.webhooksCreateInstance(body: .json(.init(data: .init(
        attributes: .init(enabled: !disabled, eventTypes: types, name: name, secret: secret, url: url),
        relationships: .init(app: .init(data: .init(id: app.id, _type: "apps"))),
        _type: "webhooks"
      )))).created.body.json.data
      print(green("Created") + " webhook \(created.id).")
      if self.secret == nil {
        print("Signing secret (save it now; App Store Connect won't show it again): \(secret)")
      }
    }
  }

  struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Change a webhook's name, URL, events, secret or enabled state.")

    @Argument(help: WebhooksCommand.bundleIDHelp, completion: WebhooksCommand.aliasCompletion)
    var bundleID: String

    @Argument(help: "Webhook name or ID.")
    var webhook: String

    @Option(name: .long, help: "New name.")
    var name: String?

    @Option(name: .long, help: "New URL.")
    var url: String?

    @Option(name: .long, help: "Replace the event types (comma-separated, or 'all').")
    var events: String?

    @Option(name: .long, help: "New signing secret.")
    var secret: String?

    @Option(name: .long, help: "Enable or disable (true/false).")
    var enabled: Bool?

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func validate() throws {
      guard name != nil || url != nil || events != nil || secret != nil || enabled != nil else {
        throw ValidationError("Pass at least one of --name, --url, --events, --secret, --enabled.")
      }
    }

    func run() async throws {
      if yes { autoConfirm = true }
      let types = try events.map(WebhooksCommand.eventTypes)
      let client = try ClientFactory.makeClient()
      let hook = try await WebhooksCommand.find(webhook, bundleID: bundleID, client: client)
      guard confirm("Update webhook '\(WebhooksCommand.name(hook))'? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      _ = try await client.webhooksUpdateInstance(path: .init(id: hook.id), body: .json(.init(data: .init(
        attributes: .init(enabled: enabled, eventTypes: types, name: name, secret: secret, url: url),
        id: hook.id, _type: "webhooks"
      )))).ok
      print(green("Updated") + " webhook '\(name ?? WebhooksCommand.name(hook))'.")
    }
  }

  struct Delete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Delete a webhook.")

    @Argument(help: WebhooksCommand.bundleIDHelp, completion: WebhooksCommand.aliasCompletion)
    var bundleID: String

    @Argument(help: "Webhook name or ID.")
    var webhook: String

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let hook = try await WebhooksCommand.find(webhook, bundleID: bundleID, client: client)
      guard confirm("Delete webhook '\(WebhooksCommand.name(hook))'? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      _ = try await client.webhooksDeleteInstance(path: .init(id: hook.id)).noContent
      print(green("Deleted") + " webhook '\(WebhooksCommand.name(hook))'.")
    }
  }

  struct Ping: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Send a test event to the webhook's URL (see the result with 'webhooks deliveries').")

    @Argument(help: WebhooksCommand.bundleIDHelp, completion: WebhooksCommand.aliasCompletion)
    var bundleID: String

    @Argument(help: "Webhook name or ID.")
    var webhook: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let hook = try await WebhooksCommand.find(webhook, bundleID: bundleID, client: client)
      _ = try await client.webhookPingsCreateInstance(body: .json(.init(data: .init(
        relationships: .init(webhook: .init(data: .init(id: hook.id, _type: "webhooks"))),
        _type: "webhookPings"
      )))).created
      print(green("Sent") + " a ping to '\(WebhooksCommand.name(hook))'. Check it with 'ascelerate webhooks deliveries \(bundleID) \"\(WebhooksCommand.name(hook))\"'.")
    }
  }

  struct DeliveryEntry: Encodable {
    let id: String
    let createdDate: Date?
    let sentDate: Date?
    let state: String?
    let httpStatusCode: Int?
    let eventType: String?
    let ping: Bool?
    let redelivery: Bool?
    let errorMessage: String?
  }

  struct Deliveries: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the webhook's recent deliveries (newest first).")

    @Argument(help: WebhooksCommand.bundleIDHelp, completion: WebhooksCommand.aliasCompletion)
    var bundleID: String

    @Argument(help: "Webhook name or ID.")
    var webhook: String

    @Option(name: .long, help: "Only this state: succeeded, failed or pending.")
    var state: String?

    @Option(name: .long, help: "Maximum number of deliveries (default 25).")
    var limit = 25

    @OptionGroup var jsonOption: JSONOption

    func run() async throws {
      jsonOption.activate()
      let states: [Operations.WebhooksDeliveriesGetToManyRelated.Input.Query.FilterDeliveryStatePayloadPayload]? = try state.map { value in
        guard let state = Operations.WebhooksDeliveriesGetToManyRelated.Input.Query.FilterDeliveryStatePayloadPayload(rawValue: value.uppercased()) else {
          throw ValidationError("Invalid state '\(value)'. Valid values: succeeded, failed, pending.")
        }
        return [state]
      }
      let client = try ClientFactory.makeClient()
      let hook = try await WebhooksCommand.find(webhook, bundleID: bundleID, client: client)
      let response = try await client.webhooksDeliveriesGetToManyRelated(
        path: .init(id: hook.id), query: .init(filterDeliveryState: states, limit: min(limit, 200), include: [.event])
      ).ok.body.json
      let events = Dictionary((response.included ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
      let entries = response.data.map { d in
        let a = d.attributes
        let event = d.relationships?.event?.data.flatMap { events[$0.id] }
        return DeliveryEntry(
          id: d.id, createdDate: a?.createdDate, sentDate: a?.sentDate, state: a?.deliveryState,
          httpStatusCode: a?.response?.httpStatusCode, eventType: event?.attributes?.eventType, ping: event?.attributes?.ping,
          redelivery: a?.redelivery, errorMessage: a?.errorMessage
        )
      }.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
      if jsonOption.json { try printJSON(entries); return }
      let rows: [[String]] = entries.map { e in
        let state = e.state.map { $0 == "FAILED" ? red(formatState($0)) : formatState($0) } ?? "-"
        let event = e.ping == true ? "Ping" : e.eventType.map { formatState($0) } ?? "-"
        return [e.id, e.createdDate.map { formatDate($0) } ?? "-", event, state, e.httpStatusCode.map(String.init) ?? "-", e.errorMessage ?? ""]
      }
      Table.print(headers: ["ID", "Created", "Event", "State", "HTTP", "Error"], rows: rows)
    }
  }

  struct Redeliver: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Send a delivery's event again (delivery IDs from 'webhooks deliveries').")

    @Argument(help: "Delivery ID.")
    var deliveryID: String

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      guard confirm("Redeliver \(deliveryID)? [y/N] ") else {
        print(yellow("Cancelled."))
        return
      }
      let created = try await ClientFactory.makeClient().webhookDeliveriesCreateInstance(body: .json(.init(data: .init(
        relationships: .init(template: .init(data: .init(id: deliveryID, _type: "webhookDeliveries"))),
        _type: "webhookDeliveries"
      )))).created.body.json.data
      print(green("Queued") + " redelivery \(created.id).")
    }
  }
}
