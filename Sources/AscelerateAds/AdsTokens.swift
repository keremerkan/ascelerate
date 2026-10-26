import AppleAdsClient
import CryptoKit
import Foundation

extension Ads {
  /// Access tokens by API user, shared by every client in the process: a token lasts an hour, so
  /// a new client reuses it instead of signing in again (a request to appleid.apple.com, which can
  /// be slow). Fetched with URLSession, so a client needs no HTTP client of its own for signing in.
  actor TokenStore {
    static let shared = TokenStore()

    private struct Token {
      let value: String
      let expires: Date
    }

    private var tokens: [String: Token] = [:]
    /// Fetches under way, so clients made at once share one sign-in.
    private var fetches: [String: Task<Token, any Error>] = [:]

    private static func key(_ credentials: Credentials) -> String {
      "\(credentials.clientID) \(credentials.keyID)"
    }

    /// A token valid for at least another minute.
    func token(for credentials: Credentials) async throws -> String {
      let key = Self.key(credentials)
      if let token = tokens[key], token.expires.timeIntervalSinceNow > 60 { return token.value }
      let fetch = fetches[key] ?? Task { try await Self.fetch(credentials) }
      fetches[key] = fetch
      defer { fetches[key] = nil }
      let token = try await fetch.value
      tokens[key] = token
      return token.value
    }

    /// Forgets a token Apple refused, so the next client signs in again.
    func invalidate(_ credentials: Credentials) {
      tokens[Self.key(credentials)] = nil
    }

    /// Signs in with a client secret: a JWT the private key signs (ES256; issuer the team ID,
    /// subject the client ID), exchanged for an access token (client credentials, scope
    /// searchadsorg).
    private static func fetch(_ credentials: Credentials) async throws -> Token {
      let key = try P256.Signing.PrivateKey(pemRepresentation: credentials.privateKeyPEM)
      func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
          .replacingOccurrences(of: "=", with: "")
      }
      let now = Int(Date().timeIntervalSince1970)
      let header = base64URL(try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": credentials.keyID]))
      let claims = base64URL(try JSONSerialization.data(withJSONObject: [
        "iss": credentials.teamID, "sub": credentials.clientID, "aud": "https://appleid.apple.com", "iat": now,
        "exp": now + 3600,
      ]))
      let signature = base64URL(try key.signature(for: Data("\(header).\(claims)".utf8)).rawRepresentation)

      var form = URLComponents()
      form.queryItems = [
        URLQueryItem(name: "grant_type", value: "client_credentials"),
        URLQueryItem(name: "client_id", value: credentials.clientID),
        URLQueryItem(name: "client_secret", value: "\(header).\(claims).\(signature)"),
        URLQueryItem(name: "scope", value: "searchadsorg"),
      ]
      var request = URLRequest(url: URL(string: "https://appleid.apple.com/auth/oauth2/token")!, timeoutInterval: 30)
      request.httpMethod = "POST"
      request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
      request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)

      let data: Data
      let response: URLResponse
      do {
        (data, response) = try await URLSession.shared.data(for: request)
      } catch {
        throw AdsError(status: nil, code: nil, message: "Network error: \(error.localizedDescription)", details: [])
      }
      struct Body: Decodable {
        let access_token: String?
        let expires_in: Int?
        let error: String?
        let error_description: String?
      }
      let body = try? JSONDecoder().decode(Body.self, from: data)
      guard (response as? HTTPURLResponse)?.statusCode == 200, let value = body?.access_token else {
        // Apple's OAuth errors, such as invalid_client for a client secret it doesn't accept.
        let message = [body?.error, body?.error_description].compactMap(\.self).joined(separator: ": ")
        throw AdsError(status: nil, code: nil, message: message.isEmpty ? nil : message, details: [])
      }
      return Token(value: value, expires: Date().addingTimeInterval(TimeInterval(body?.expires_in ?? 3600)))
    }
  }

  /// The client's tokens, from the shared store.
  struct SharedTokenProvider: TokenProvider {
    let credentials: Credentials

    nonisolated(nonsending) func token() async throws -> String {
      try await TokenStore.shared.token(for: credentials)
    }
  }
}
