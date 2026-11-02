import Foundation
import Testing
@testable import ASCKit

@Suite struct ErrorDecodingTests {
  @Test func associatedErrorsAreDecoded() throws {
    // The shape of a 409 from adding a version to a review submission.
    let json = """
      {"errors": [{"status": "409", "code": "STATE_ERROR.ENTITY_STATE_INVALID",
        "title": "appStoreVersions with id 'abc' is not in valid state.",
        "detail": "This resource cannot be reviewed, please check associated errors to see why.",
        "meta": {"associatedErrors": {"/v1/appStoreVersions/abc": [
          {"code": "ENTITY_ERROR.ATTRIBUTE.REQUIRED", "title": "A required field is missing.", "detail": "whatsNew is required."},
          {"code": "ENTITY_ERROR.ATTRIBUTE.REQUIRED", "title": "A required field is missing.", "detail": "whatsNew is required."}
        ], "/v1/appInfos/def": [{"title": "Age rating is incomplete."}]}}}]}
      """
    struct Document: Decodable { let errors: [ASCError.Entry] }
    let entry = try JSONDecoder().decode(Document.self, from: Data(json.utf8)).errors[0]
    #expect(entry.title.hasPrefix("appStoreVersions"))
    // Repeats removed, sorted by resource path.
    #expect(entry.reasons.map(\.detail) == ["", "whatsNew is required."])
    #expect(entry.reasons.map(\.title) == ["Age rating is incomplete.", "A required field is missing."])
  }

  @Test func entriesWithoutMetaStillDecode() throws {
    struct Document: Decodable { let errors: [ASCError.Entry] }
    let entry = try JSONDecoder().decode(Document.self, from: Data(#"{"errors": [{"title": "Not found", "detail": "Gone"}]}"#.utf8)).errors[0]
    #expect(entry.reasons.isEmpty)
    #expect(entry.detail == "Gone")
  }

  @Test func onlyARoleForbiddenIsMissingPermission() throws {
    struct Document: Decodable { let errors: [ASCError.Entry] }
    func error(_ status: Int, _ json: String) throws -> ASCError {
      ASCError(statusCode: status, errors: try JSONDecoder().decode(Document.self, from: Data(json.utf8)).errors, rateLimit: nil)
    }
    // The key's role.
    #expect(try error(403, #"{"errors": [{"code": "FORBIDDEN_ERROR", "title": "The request cannot be fulfilled because of permission issues.", "detail": "The API key in use does not allow this request"}]}"#).isMissingPermission)
    // The request itself, whatever the role (seen 2026-11-02).
    #expect(try !error(403, #"{"errors": [{"code": "FORBIDDEN_ERROR", "title": "This request is forbidden for security reasons", "detail": "UNIVERSAL AppId 'ABC123' does not allow changes to the 'In-App Purchase' feature."}]}"#).isMissingPermission)
    #expect(ASCError(statusCode: 403, errors: [], rateLimit: nil).isMissingPermission)
    #expect(!ASCError(statusCode: 409, errors: [], rateLimit: nil).isMissingPermission)
  }
}
