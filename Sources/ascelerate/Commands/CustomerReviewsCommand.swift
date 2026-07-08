import AppStoreAPI
import AppStoreConnect
import ArgumentParser
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

  /// Fetches a review by ID along with its developer response (if any).
  static func fetchReview(
    reviewID: String, client: AppStoreConnectClient
  ) async throws -> (review: CustomerReview, response: CustomerReviewResponseV1?) {
    let resp = try await client.send(
      Resources.v1.customerReviews.id(reviewID).get(include: [.response]))
    let response = resp.included?.compactMap { item -> CustomerReviewResponseV1? in
      if case .customerReviewResponseV1(let r) = item { return r }
      return nil
    }.first
    return (resp.data, response)
  }

  /// Prints a review (and its response, if present). `full` shows the complete body.
  static func printReview(
    _ review: CustomerReview, response: CustomerReviewResponseV1?, full: Bool = false
  ) {
    let a = review.attributes
    print("\(ratingStars(a?.rating))  \(a?.title ?? "—")")
    print("  By:        \(a?.reviewerNickname ?? "—")")
    print("  Territory: \(a?.territory?.rawValue ?? "—")")
    print("  Date:      \(a?.createdDate.map { formatDate($0) } ?? "—")")
    print("  Review ID: \(review.id)")
    if let body = a?.body, !body.isEmpty {
      print()
      let text = full ? body : String(body.prefix(280)) + (body.count > 280 ? "…" : "")
      print("  " + text.replacingOccurrences(of: "\n", with: "\n  "))
    }
    if let response, let attrs = response.attributes {
      let meta = "\(attrs.state.map { formatState($0) } ?? "—"), \(attrs.lastModifiedDate.map { formatDate($0) } ?? "—")"
      print()
      print("  \(green("Developer response")) (\(meta)):")
      print("  " + (attrs.responseBody ?? "").replacingOccurrences(of: "\n", with: "\n  "))
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

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let app = try await findApp(bundleID: bundleID, client: client)

      let sortValue: [Resources.V1.Apps.WithID.CustomerReviews.Sort]
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

      let resp = try await client.send(
        Resources.v1.apps.id(app.id).customerReviews.get(
          filterRating: rating.map { ["\($0)"] },
          filterReviewTerritory: territory.map { [$0.uppercased()] },
          isExistsPublishedResponse: unanswered ? false : nil,
          sort: sortValue,
          limit: min(max(limit, 1), 200),
          include: [.response]
        ))

      if resp.data.isEmpty {
        print("No reviews found.")
        return
      }

      var rows: [[String]] = []
      for review in resp.data {
        let a = review.attributes
        let replied = review.relationships?.response?.data != nil ? green("✓") : red("✗")
        let title = a?.title ?? "—"
        rows.append([
          review.id,
          CustomerReviewsCommand.ratingStars(a?.rating),
          a?.createdDate.map { formatDate($0) } ?? "—",
          a?.territory?.rawValue ?? "—",
          replied,
          title.count > 50 ? String(title.prefix(49)) + "…" : title,
        ])
      }

      Table.print(
        headers: ["Review ID", "Rating", "Date", "Terr", "Replied", "Title"],
        rows: rows
      )
      print()
      print("\(resp.data.count) review(s). Use 'reviews info <review-id>' for full text.")
    }
  }

  // MARK: - Info

  struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Show full text of a review and its response."
    )

    @Argument(help: "The review ID (from `reviews list`).")
    var reviewID: String

    func run() async throws {
      let client = try ClientFactory.makeClient()
      let (review, response) = try await CustomerReviewsCommand.fetchReview(
        reviewID: reviewID, client: client)
      CustomerReviewsCommand.printReview(review, response: response, full: true)
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
      CustomerReviewsCommand.printReview(review, response: existing)
      print()

      let replacedBody = existing?.attributes?.responseBody
      if let existing {
        guard confirm("This review already has a response. Replace it? [y/N] ") else {
          cancelled()
          return
        }
        _ = try await client.send(Resources.v1.customerReviewResponses.id(existing.id).delete)
      }

      let resp: CustomerReviewResponseV1Response
      do {
        resp = try await client.send(
          Resources.v1.customerReviewResponses.post(
            CustomerReviewResponseV1CreateRequest(
              data: .init(
                attributes: .init(responseBody: body),
                relationships: .init(review: .init(data: .init(id: reviewID)))
              )
            )
          ))
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

      CustomerReviewsCommand.printReview(review, response: existing)
      print()
      guard confirm("Delete this response? [y/N] ") else {
        cancelled()
        return
      }

      _ = try await client.send(Resources.v1.customerReviewResponses.id(existing.id).delete)
      print()
      success("Deleted", "developer response.")
    }
  }
}
