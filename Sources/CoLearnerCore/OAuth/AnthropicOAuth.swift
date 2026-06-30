import Foundation

public enum AnthropicOAuthError: Error, LocalizedError {
    case invalidAuthorizeURL
    case stateMismatch
    case missingCode
    case callbackError(String)
    case tokenExchangeFailed(String)
    case invalidTokenResponse(String)
    case refreshFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAuthorizeURL:
            "Could not build Anthropic authorize URL"
        case .stateMismatch:
            "Authorization response state did not match — please try signing in again"
        case .missingCode:
            "Anthropic did not return an authorization code"
        case let .callbackError(message):
            "Anthropic returned an error: \(message)"
        case let .tokenExchangeFailed(message):
            "Anthropic token exchange failed: \(message)"
        case let .invalidTokenResponse(message):
            "Anthropic token response was invalid: \(message)"
        case let .refreshFailed(message):
            "Anthropic token refresh failed: \(message)"
        }
    }
}

public struct AnthropicOAuthStartedSession: Sendable {
    public let authorizationURL: URL
    public let pkce: PKCEChallenge
    public let redirectURI: String

    public init(authorizationURL: URL, pkce: PKCEChallenge, redirectURI: String) {
        self.authorizationURL = authorizationURL
        self.pkce = pkce
        self.redirectURI = redirectURI
    }
}

/// Anthropic Claude Pro/Max OAuth (PKCE authorization-code).
/// Endpoints, client ID, scopes, and callback port match Claude Code's flow.
public struct AnthropicOAuth: Sendable {
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let authorizeURL = "https://claude.ai/oauth/authorize"
    public static let tokenURL = "https://platform.claude.com/v1/oauth/token"
    public static let callbackPort: UInt16 = 53692
    public static let callbackPath = "/callback"
    public static let scope = "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func startSession() throws -> AnthropicOAuthStartedSession {
        let pkce = PKCE.generate()
        let redirectURI = "http://localhost:\(Self.callbackPort)\(Self.callbackPath)"

        var components = URLComponents(string: Self.authorizeURL)
        components?.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "state", value: pkce.verifier)
        ]

        guard let url = components?.url else {
            throw AnthropicOAuthError.invalidAuthorizeURL
        }

        return AnthropicOAuthStartedSession(
            authorizationURL: url,
            pkce: pkce,
            redirectURI: redirectURI
        )
    }

    public func exchange(
        code: String,
        state: String,
        pkce: PKCEChallenge,
        redirectURI: String
    ) async throws -> OAuthCredentials {
        guard state == pkce.verifier else {
            throw AnthropicOAuthError.stateMismatch
        }

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": Self.clientID,
            "code": code,
            "state": state,
            "redirect_uri": redirectURI,
            "code_verifier": pkce.verifier
        ]

        let payload = try await postJSON(url: Self.tokenURL, json: body) { message in
            AnthropicOAuthError.tokenExchangeFailed(message)
        }

        return try Self.credentials(fromJSON: payload, scope: Self.scope, errorMap: AnthropicOAuthError.invalidTokenResponse)
    }

    public func refresh(refreshToken: String) async throws -> OAuthCredentials {
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": Self.clientID,
            "refresh_token": refreshToken
        ]

        let payload = try await postJSON(url: Self.tokenURL, json: body) { message in
            AnthropicOAuthError.refreshFailed(message)
        }

        return try Self.credentials(fromJSON: payload, scope: Self.scope, errorMap: AnthropicOAuthError.invalidTokenResponse)
    }

    private func postJSON(
        url: String,
        json: [String: String],
        errorMap: (String) -> Error
    ) async throws -> [String: Any] {
        guard let endpoint = URL(string: url) else {
            throw errorMap("invalid url: \(url)")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw errorMap("non-http response")
        }

        let bodyString = String(data: data, encoding: .utf8) ?? ""

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw errorMap("status \(httpResponse.statusCode): \(bodyString)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw errorMap("invalid JSON body: \(bodyString)")
        }
        return json
    }

    static func credentials(
        fromJSON json: [String: Any],
        scope: String?,
        errorMap: (String) -> Error
    ) throws -> OAuthCredentials {
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Double else {
            throw errorMap("missing required token fields in \(json)")
        }

        let expiresAt = Date().addingTimeInterval(expiresIn - 300)
        let resolvedScope = (json["scope"] as? String) ?? scope

        return OAuthCredentials(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: expiresAt,
            scope: resolvedScope
        )
    }
}
