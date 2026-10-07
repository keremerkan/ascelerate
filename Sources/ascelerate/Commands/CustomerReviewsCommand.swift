import ArgumentParser
import ASCKit
import Foundation

struct CustomerReviewsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "reviews",
    abstract: "View customer reviews and manage developer responses.",
    subcommands: [List.self, Info.self, Respond.self, DeleteResponse.self]
  )

  // MARK: - Shared helpers

  /// Renders a 1–5 star rating as filled/empty stars.
  static func ratingStars(_ rating: Int?) -> String {
    let r = max(0, min(5, rating ?? 0))
    return String(repeating: "★", count: r) + String(repeating: "☆", count: 5 - r)
  }

  /// JSON shape shared by `reviews list` (array element) and `reviews info` (top-level object).
  struct ReviewEntry: Encodable {
    struct Response: Encodable {
      let state: String?
      let lastModifiedDate: Date?
      let body: String?
    }
    let id: String
    let rating: Int?
    let title: String?
    let body: String?
    let reviewerNickname: String?
    let territory: String?
    let createdDate: Date?
    let response: Response?

    init(review: Components.Schemas.CustomerReview, response resp: Components.Schemas.CustomerReviewResponseV1?) {
      let a = review.attributes
      id = review.id
      rating = a?.rating
      title = a?.title
      body = a?.body
      reviewerNickname = a?.reviewerNickname
      territory = a?.territory
      createdDate = a?.createdDate
      response = resp.map {
        Response(state: $0.attributes?.state, lastModifiedDate: $0.attributes?.lastModifiedDate, body: $0.attributes?.responseBody)
      }
    }
  }

  /// Fetches a review by ID along with its developer response (if any).
  static func fetchReview(
    reviewID: String, client: ASCClient
  ) async throws -> (review: Components.Schemas.CustomerReview, response: Components.Schemas.CustomerReviewResponseV1?) {
    let resp = try await client.customerReviewsGetInstance(
      path: .init(id: reviewID), query: .init(include: [.response])
    ).ok.body.json
    let response = resp.included?.compactMap { item -> Components.Schemas.CustomerReviewResponseV1? in
      if case .customerReviewResponses(let r) = item { return r }
      return nil
    }.first
    return (resp.data, response)
  }

  /// Prints a review (and its response, if present). `full` shows the complete body.
  static func printReview(_ review: ReviewEntry, full: Bool = false) {
    print("\(ratingStars(review.rating))  \(review.title ?? "—")")
    print("  By:        \(review.reviewerNickname ?? "—")")
    print("  Territory: \(review.territory ?? "—")")
    print("  Date:      \(review.createdDate.map { formatDate($0) } ?? "—")")
    print("  Review ID: \(review.id)")
    if let body = review.body, !body.isEmpty {
      print()
      let text = full ? body : String(body.prefix(280)) + (body.count > 280 ? "…" : "")
      print("  " + text.replacingOccurrences(of: "\n", with: "\n  "))
    }
    if let response = review.response {
      let meta = "\(response.state.map { formatState($0) } ?? "—"), \(response.lastModifiedDate.map { formatDate($0) } ?? "—")"
      print()
      print("  \(green("Developer response")) (\(meta)):")
      print("  " + (response.body ?? "").replacingOccurrences(of: "\n", with: "\n  "))
    } else if full {
      print()
      print("  " + yellow("No developer response."))
    }
  }

  // MARK: - List

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List customer reviews for an app."
    )

    @Argument(help: "The bundle identifier of the app.",
              completion: .shellCommand("grep -o '\"[^\"]*\" *:' ~/.ascelerate/aliases.json 2>/dev/null | sed 's/\" *://' | tr -d '\"'"))
    var bundleID: String

    @Option(name: .long, help: "Filter by star rating (1–5).")
    var rating: Int?

    @Option(name: .long, help: "Filter by review territory code (e.g. USA).")
    var territory: String?

    @Option(name: .long, help: "Sort order: recent, oldest, critical, best (default: recent).")
    var sort: String = "recent"

    @Flag(name: .long, help: "Only reviews without a published response.")
    var unanswered = false

    @Option(name: .long, help: "Maximum number of reviews to show (default: 50, max: 200).")
    var limit: Int = 50

    @OptionGroup var jsonOption: JSONOption

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let sortValue: [Operations.AppsCustomerReviewsGetToManyRelated.Input.Query.SortPayloadPayload]
      switch sort.lowercased() {
      case "recent": sortValue = [.minusCreatedDate]
      case "oldest": sortValue = [.createdDate]
      case "critical": sortValue = [.rating]
      case "best": sortValue = [.minusRating]
      default:
        throw ValidationError("Invalid --sort '\(sort)'. Use: recent, oldest, critical, best.")
      }

      if let rating, !(1...5).contains(rating) {
        throw ValidationError("--rating must be between 1 and 5.")
      }

      let resp = try await client.appsCustomerReviewsGetToManyRelated(
        path: .init(id: app.id),
        query: .init(
          filterRating: rating.map { ["\($0)"] },
          filterReviewTerritory: territory.map { [$0.uppercased()] },
          existsPublishedResponse: unanswered ? false : nil,
          sort: sortValue,
          limit: min(max(limit, 1), 200),
          include: [.response]
        )
      ).ok.body.json

      let responsesByID = Dictionary(
        uniqueKeysWithValues: (resp.included ?? []).compactMap { item -> (String, Components.Schemas.CustomerReviewResponseV1)? in
          if case .customerReviewResponses(let r) = item { return (r.id, r) }
          return nil
        })

      let entries = resp.data.map { review in
        ReviewEntry(
          review: review,
          response: review.relationships?.response?.data.flatMap { responsesByID[$0.id] }
        )
      }

      if jsonOption.json {
        try printJSON(entries)
        return
      }

      if entries.isEmpty {
        print("No reviews found.")
        return
      }

      let rows = entries.map { e -> [String] in
        let title = e.title ?? "—"
        return [
          e.id,
          CustomerReviewsCommand.ratingStars(e.rating),
          e.createdDate.map { formatDate($0) } ?? "—",
          e.territory ?? "—",
          e.response != nil ? green("✓") : red("✗"),
          title.count > 50 ? String(title.prefix(49)) + "…" : title,
        ]
      }

      Table.print(
        headers: ["Review ID", "Rating", "Date", "Terr", "Replied", "Title"],
        rows: rows
      )
      print()
      print("\(entries.count) review(s). Use 'reviews info <review-id>' for full text.")
    }
  }

  // MARK: - Info

  struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Show full text of a review and its response."
    )

    @Argument(help: "The review ID (from `reviews list`).")
    var reviewID: String

    @OptionGroup var jsonOption: JSONOption

    func run() async throws {
      jsonOption.activate()
      let client = try ClientFactory.makeClient()
      let (review, response) = try await CustomerReviewsCommand.fetchReview(
        reviewID: reviewID, client: client)
      let entry = ReviewEntry(review: review, response: response)
      if jsonOption.json {
        try printJSON(entry)
        return
      }
      CustomerReviewsCommand.printReview(entry, full: true)
    }
  }

  // MARK: - Respond

  struct Respond: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Publish a developer response to a review (replaces any existing response)."
    )

    @Argument(help: "The review ID (from `reviews list`).")
    var reviewID: String

    @Option(name: .long, help: "The response text.")
    var body: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { throw ValidationError("--body cannot be empty.") }

      let client = try ClientFactory.makeClient()
      let (review, existing) = try await CustomerReviewsCommand.fetchReview(
        reviewID: reviewID, client: client)
      CustomerReviewsCommand.printReview(ReviewEntry(review: review, response: existing))
      print()

      let replacedBody = existing?.attributes?.responseBody
      if let existing {
        guard confirm("This review already has a response. Replace it? [y/N] ") else {
          cancelled()
          return
        }
        _ = try await client.customerReviewResponsesDeleteInstance(path: .init(id: existing.id)).noContent
      }

      let resp: Components.Schemas.CustomerReviewResponseV1Response
      do {
        resp = try await client.customerReviewResponsesCreateInstance(body: .json(.init(data: .init(
          attributes: .init(responseBody: body),
          relationships: .init(review: .init(data: .init(id: reviewID, _type: "customerReviews"))),
          _type: "customerReviewResponses"
        )))).created.body.json
      } catch {
        // The old response is already deleted at this point — the API only allows
        // one response per review, so replace works as delete-then-create.
        if let replacedBody {
          print()
          print(red("The previous response was deleted but publishing the new one failed."))
          print("Previous response text (for recovery):")
          print("  \(replacedBody)")
        }
        throw error
      }

      let state = resp.data.attributes?.state.map { formatState($0) } ?? "—"
      print()
      success("Responded", "to review (state: \(state)).")
    }
  }

  // MARK: - Delete Response

  struct DeleteResponse: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "delete-response",
      abstract: "Delete the developer response on a review."
    )

    @Argument(help: "The review ID (from `reviews list`).")
    var reviewID: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes = false

    func run() async throws {
      if yes { autoConfirm = true }
      let client = try ClientFactory.makeClient()
      let (review, existing) = try await CustomerReviewsCommand.fetchReview(
        reviewID: reviewID, client: client)

      guard let existing else {
        print("No developer response on this review.")
        return
      }

      CustomerReviewsCommand.printReview(ReviewEntry(review: review, response: existing))
      print()
      guard confirm("Delete this response? [y/N] ") else {
        cancelled()
        return
      }

      _ = try await client.customerReviewResponsesDeleteInstance(path: .init(id: existing.id)).noContent
      print()
      success("Deleted", "developer response.")
    }
  }
}
