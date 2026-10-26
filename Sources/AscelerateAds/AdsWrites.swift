import AppleAdsClient
import Foundation

// Changes to campaigns, ad groups, keywords and negative keywords. Keyword writes go through the
// bulk endpoints with partial success allowed: one request for many, each item answered on its own.
extension Ads {
  /// A bulk request that applies the items that can be applied, reporting the others.
  public static let bulkBase = Components.Schemas.BulkOperationRequest(value1: .init(allowPartialSuccess: true), value2: .init())

  /// Pauses (PAUSED) or resumes (ENABLED) a campaign.
  public static func setStatus(
    _ status: Components.Schemas.CampaignStatus, campaignID: Int64, context: String, client: Client
  ) async throws {
    _ = try await client.putCampaignsId(
      path: .init(id: String(campaignID)), headers: .init(xApContext: context),
      body: .json(.init(status: .init(value1: status)))
    ).ok
  }

  /// Renames a campaign; reports and attribution follow its ID, so the new name shows for earlier
  /// periods too.
  public static func setName(_ name: String, campaignID: Int64, context: String, client: Client) async throws {
    _ = try await client.putCampaignsId(
      path: .init(id: String(campaignID)), headers: .init(xApContext: context), body: .json(.init(name: name))
    ).ok
  }

  /// A campaign's daily budget, in the ad account's currency.
  public static func setDailyBudget(
    _ budget: Components.Schemas.Money, campaignID: Int64, context: String, client: Client
  ) async throws {
    _ = try await client.putCampaignsId(
      path: .init(id: String(campaignID)), headers: .init(xApContext: context),
      body: .json(.init(dailyBudget: .init(value1: .init(value: budget))))
    ).ok
  }

  /// Pauses (PAUSED) or resumes (ENABLED) an ad group.
  public static func setStatus(
    _ status: Components.Schemas.AdGroupStatus, adGroupID: Int64, context: String, client: Client
  ) async throws {
    _ = try await client.putAdgroupsId(
      path: .init(id: String(adGroupID)), headers: .init(xApContext: context),
      body: .json(.init(status: .init(value1: status)))
    ).ok
  }

  /// Renames an ad group or turns its Search Match on or off, by ID: neither needs the ad group's
  /// current settings (a default bid does, see the other `updateAdGroup`).
  public static func updateAdGroup(
    id: Int64, name: String? = nil, searchMatch: Bool? = nil, context: String, client: Client
  ) async throws {
    _ = try await client.putAdgroupsId(
      path: .init(id: String(id)), headers: .init(xApContext: context),
      body: .json(.init(name: name, automatedKeywordsOptIn: searchMatch))
    ).ok
  }

  /// Changes an ad group's name, Search Match, default bid or CPA goal; what's nil stays. A default
  /// bid goes with the ad group's bid strategy type and goal, which Apple requires with any bid
  /// strategy update.
  public static func updateAdGroup(
    _ group: Components.Schemas.AdGroup, name: String? = nil, searchMatch: Bool? = nil,
    defaultBid: Components.Schemas.Money? = nil, cpaGoal: Components.Schemas.Money? = nil, context: String, client: Client
  ) async throws {
    let bidStrategy: Components.Schemas.BidStrategyUpdate? = defaultBid.map {
      let current = group.bidStrategy?.value1
      return .init(
        bidStrategyType: current?.bidStrategyType.map { .init(value1: $0.value1) },
        bidStrategyGoal: current?.bidStrategyGoal.map { .init(value1: $0.value1) },
        bid: $0
      )
    }
    let cpaCap: Components.Schemas.CPAGoalUpdate? = cpaGoal.map { .init(value: $0) }
    _ = try await client.putAdgroupsId(
      path: .init(id: String(group.id ?? 0)), headers: .init(xApContext: context),
      body: .json(.init(
        name: name, automatedKeywordsOptIn: searchMatch,
        bidStrategy: bidStrategy.map { .init(value1: $0) }, cpaCap: cpaCap.map { .init(value1: $0) }
      ))
    ).ok
  }

  /// Adds keywords; each result matches its item by `correlationId` (its position, from 1).
  public static func createKeywords(
    _ keywords: [Components.Schemas.BulkKeywordCreate], context: String, client: Client
  ) async throws -> [BulkItem<Components.Schemas.Keyword>] {
    let items = keywords.enumerated().map { i, keyword in
      Components.Schemas.KeywordCreateBulkRequestItem(correlationId: Int64(i + 1), data: keyword)
    }
    return try await bulk(Components.Schemas.Keyword.self) {
      _ = try await client.postKeywordsBulkCreate(
        headers: .init(xApContext: context), body: .json(.init(value1: bulkBase, value2: .init(items: items))))
    }
  }

  /// Changes keywords (status, bid); each result matches its item by `correlationId` (its
  /// position, from 1).
  public static func updateKeywords(
    _ updates: [Components.Schemas.BulkKeywordUpdate], context: String, client: Client
  ) async throws -> [BulkItem<Components.Schemas.Keyword>] {
    let items = updates.enumerated().map { i, update in
      Components.Schemas.KeywordUpdateBulkRequestItem(correlationId: Int64(i + 1), data: update)
    }
    return try await bulk(Components.Schemas.Keyword.self) {
      _ = try await client.postKeywordsBulkUpdate(
        headers: .init(xApContext: context), body: .json(.init(value1: bulkBase, value2: .init(items: items))))
    }
  }

  /// Adds negative keywords; a campaign's own carry only `campaignId`, an ad group's only
  /// `adGroupId`. Each result matches its item by `correlationId` (its position, from 1).
  public static func createNegativeKeywords(
    _ keywords: [Components.Schemas.BulkNegativeKeywordCreate], context: String, client: Client
  ) async throws -> [BulkItem<Components.Schemas.NegativeKeyword>] {
    let items = keywords.enumerated().map { i, keyword in
      Components.Schemas.NegativeKeywordCreateBulkRequestItem(correlationId: Int64(i + 1), data: keyword)
    }
    return try await bulk(Components.Schemas.NegativeKeyword.self) {
      _ = try await client.postNegativeKeywordsBulkCreate(
        headers: .init(xApContext: context), body: .json(.init(value1: bulkBase, value2: .init(items: items))))
    }
  }

  /// Removes a negative keyword (the API has no bulk delete).
  public static func deleteNegativeKeyword(id: Int64, context: String, client: Client) async throws {
    _ = try await client.deleteNegativeKeywordsId(path: .init(id: String(id)), headers: .init(xApContext: context)).ok
  }
}
