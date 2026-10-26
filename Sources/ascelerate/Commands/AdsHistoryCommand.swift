import AppleAdsClient
import AscelerateAds
import ArgumentParser
import AscelerateCore
import Foundation
import OpenAPIRuntime

extension AdsCommand {
  struct History: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Change history: who changed what in campaigns, ad groups and keywords, with old and new values.",
      discussion: """
        Includes changes made in the Apple Ads web interface ("UI"), through the API ("API", which is \
        ascelerate) and by Apple support. Range in the ad account's time zone; Apple keeps 6 months.
        """
    )

    @OptionGroup var range: Ads.DateRangeOptions
    @OptionGroup var scope: Ads.ScopeOptions
    @OptionGroup var jsonOption: JSONOption

    private struct Entry: Encodable {
      let time: Date?
      /// CREATE, UPDATE or DELETE.
      let eventType: String?
      /// Campaign, AdGroup, Keyword or NegativeKeyword.
      let entityType: String?
      let entityId: String?
      /// The keyword's text or the campaign's / ad group's name.
      let entity: String?
      let campaignId: String?
      let campaignName: String?
      /// CUSTOMER (web interface), CUSTOMER_API (API) or APPLE_SUPPORT.
      let userType: String?
      let userId: String?
      /// The entity's values after the change (keywords: match type, bid, status).
      let matchType: String?
      let bid: String?
      let status: String?
      let changes: [Change]?
    }

    private struct Change: Encodable {
      let field: String
      let old: [String]
      let new: [String]
    }

    /// One changed entity from a summary row's `metas` (shape not in Apple's spec).
    private struct Meta: Decodable {
      let detailId: String?
      let meta: [String: OpenAPIValueContainer]?

      func string(_ key: String) -> String? {
        guard let value = meta?[key]?.value else { return nil }
        return "\(value)"
      }
    }

    func run() async throws {
      jsonOption.activate()
      let ads = try Ads.config()
      let (start, end) = try range.resolved()
      let scope = try await self.scope.resolve(ads)
      let endExclusive = Ads.dayAfter(end)

      let entries = try await Ads.withClient(ads) { client in
        var filters: [Components.Schemas.AuditFilter] = [
          .init(field: "eventTime", _operator: .between, value: try .init(unvalidatedValue: ["\(start)T00:00:00.000", "\(endExclusive)T00:00:00.000"])),
          // Required by the API although its docs list it as optional.
          .init(field: "entityType", _operator: ._in, value: try .init(unvalidatedValue: ["Campaign", "AdGroup", "Keyword", "NegativeKeyword"])),
        ]
        if scope.isNarrowed {
          filters.append(.init(field: "campaignId", _operator: ._in, value: try .init(unvalidatedValue: scope.campaigns.compactMap(\.id).map(Int.init))))
        }
        var rows: [Components.Schemas.AuditSummary] = []
        while true {
          let page = try await client.queryAuditSummary(
            headers: .init(xApContext: Ads.context(ads)),
            body: .json(.init(
              filters: filters, pagination: .init(offset: rows.count, pageSize: 1000),
              options: .init(timeZone: .ortz, metadata: .latest)
            ))
          ).ok.body.json
          let result = page.value2.result ?? []
          rows += result
          if result.count < 1000 || rows.count >= (page.value1.pagination?.totalCount ?? 0) { break }
        }

        // One entry per changed entity; updates get their field-level changes.
        var pending: [(Components.Schemas.AuditSummary, Meta)] = []
        for row in rows {
          let metas = try (row.metas ?? []).map { try Ads.convert($0, to: Meta.self) }
          pending += metas.map { (row, $0) }
        }
        let updateIDs = pending.filter { $0.0.eventType?.rawValue == "UPDATE" }.compactMap(\.1.detailId)
        let details = try await Ads.detailChanges(updateIDs, ads, client: client)

        return pending.map { row, meta in
          let campaignID = meta.string("campaignId")
          return Entry(
            time: row.eventTime, eventType: row.eventType?.rawValue, entityType: row.entityType,
            entityId: meta.detailId?.split(separator: ".").dropFirst().first.map(String.init),
            entity: meta.string("text") ?? meta.string("name"), campaignId: campaignID,
            campaignName: campaignID.flatMap(Int64.init).map { scope.campaignName($0) },
            userType: row.userType?.rawValue, userId: row.modifiedBy,
            matchType: meta.string("matchType"), bid: meta.string("bidAmount"), status: meta.string("status"),
            changes: meta.detailId.flatMap { details[$0] }?.map { Change(field: $0.field, old: $0.old, new: $0.new) }
          )
        }.sorted { ($0.time ?? .distantPast) > ($1.time ?? .distantPast) }
      }

      if jsonOption.json { try printJSON(entries); return }
      guard !entries.isEmpty else {
        print("No changes \(start) – \(end).")
        return
      }
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd HH:mm"
      Table.print(
        headers: ["Time", "By", "Change", "Entity", "Campaign", "Details"],
        rows: entries.map { e in
          let by: String = switch e.userType {
          case "CUSTOMER": "UI"
          case "CUSTOMER_API": "API"
          case "APPLE_SUPPORT": "Apple"
          default: e.userType ?? "-"
          }
          let change = "\(formatState(e.eventType ?? "")) \(formatFieldName(e.entityType ?? ""))"
          // Updates: field changes. Creates (Apple also logs some bulk keyword updates as creates):
          // the resulting values.
          let details = e.eventType == "UPDATE"
            ? (e.changes ?? [])
              .filter { !Ads.historyNoise.contains($0.field) }
              .map { "\($0.field) \($0.old.joined(separator: ",")) → \($0.new.joined(separator: ","))" }
              .joined(separator: "; ")
            : [
              e.matchType.map { formatState($0).lowercased() },
              e.bid.map { "bid \($0)" },
              e.status == "PAUSED" ? "paused" : nil,
            ].compactMap { $0 }.joined(separator: ", ")
          return [
            e.time.map { formatter.string(from: $0) } ?? "-", by, change, e.entity ?? e.entityId ?? "-",
            e.campaignName ?? "-", details,
          ]
        }
      )
    }
  }
}

extension Ads {
  /// Bookkeeping fields every change touches; left out of the table (kept in JSON).
  static let historyNoise: Set<String> = [
    "modificationTime", "lastModifiedBy", "modifiedUserId", "txnId", "transactionId", "version",
  ]

  /// Field-level changes for change history detail IDs, four requests at a time.
  static func detailChanges(
    _ ids: [String], _ ads: AdsConfig, client: Client
  ) async throws -> [String: [(field: String, old: [String], new: [String])]] {
    var result: [String: [(field: String, old: [String], new: [String])]] = [:]
    try await withThrowingTaskGroup(of: (String, [(field: String, old: [String], new: [String])]).self) { group in
      var next = 0
      func addNext() {
        guard next < ids.count else { return }
        let id = ids[next]
        next += 1
        group.addTask {
          let details = try await client.getChangeDetails(
            path: .init(detailId: id), headers: .init(xApContext: context(ads))
          ).ok.body.json.value2.result ?? []
          let changes = details.flatMap { $0.details ?? [] }.flatMap { $0.changes ?? [] }.map {
            (field: $0.field ?? "-", old: $0.oldValues ?? [], new: $0.newValues ?? [])
          }
          return (id, changes)
        }
      }
      for _ in 0..<4 { addNext() }
      for try await (id, changes) in group {
        result[id] = changes
        addNext()
      }
    }
    return result
  }

  /// The day after a yyyy-MM-dd date, as yyyy-MM-dd.
  static func dayAfter(_ day: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    guard let date = formatter.date(from: day) else { return day }
    return formatter.string(from: date.addingTimeInterval(86_400))
  }
}
