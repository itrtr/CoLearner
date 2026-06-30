import Foundation

public enum OpenAIOAuthError: Error, LocalizedError {
    case invalidAuthorizeURL
    case missingCode
    case callbackError(String)
    case tokenExchangeFailed(String)
    case invalidTokenResponse(String)
    case refreshFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAuthorizeURL:
            "Could not build OpenAI authorize URL"
        case .missingCode:
            "OpenAI did not return an authorization code"
        case let .callbackError(message):
            "OpenAI returned an error: \(message)"
        case let .tokenExchangeFailed(message):
            "OpenAI token exchange failed: \(message)"
        case let .invalidTokenResponse(message):
            "OpenAI token response was invalid: \(message)"
        case let .refreshFailed(message):
            "OpenAI token refresh failed: \(message)"
        }
    }
}

public struct OpenAIOAuthStartedSession: Sendable {
    public let authorizationURL: URL
    public let pkce: PKCEChallenge
    public let state: String
    public let redirectURI: String
}

/// OpenAI ChatGPT (Plus/Pro/Team) OAuth (PKCE authorization-code).
/// Endpoints, client ID, and callback port match the Codex CLI flow.
public struct OpenAIOAuth: Sendable {
    public static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    public static let authorizeURL = "https://auth.openai.com/oauth/authorize"
    public static let tokenURL = "https://auth.openai.com/oauth/token"
    public static let callbackPort: UInt16 = 1455
    public static let callbackPath = "/auth/callback"
    public static let scope = "openid profile email offline_access"

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func startSession() throws -> OpenAIOAuthStartedSession {
        let pkce = PKCE.generate()
        let state = Self.randomState()
        let redirectURI = "http://localhost:\(Self.callbackPort)\(Self.callbackPath)"

        var components = URLComponents(string: Self.authorizeURL)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = components?.url else {
            throw OpenAIOAuthError.invalidAuthorizeURL
        }

        return OpenAIOAuthStartedSession(
            authorizationURL: url,
            pkce: pkce,
            state: state,
            redirectURI: redirectURI
        )
    }

    public func exchange(
        code: String,
        pkce: PKCEChallenge,
        redirectURI: String
    ) async throws -> OAuthCredentials {
        let body: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": Self.clientID,
            "code": code,
            "code_verifier": pkce.verifier,
            "redirect_uri": redirectURI
        ]

        return try await postForm(
            url: Self.tokenURL,
            form: body,
            error: OpenAIOAuthError.tokenExchangeFailed
        )
    }

    public func refresh(refreshToken: String) async throws -> OAuthCredentials {
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": Self.clientID,
            "refresh_token": refreshToken,
            "scope": Self.scope
        ]

        return try await postForm(
            url: Self.tokenURL,
            form: body,
            error: OpenAIOAuthError.refreshFailed
        )
    }

    private func postForm(
        url: String,
        form: [String: String],
        error errorMap: (String) -> Error
    ) async throws -> OAuthCredentials {
        guard let endpoint = URL(string: url) else {
            throw errorMap("invalid url: \(url)")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded(form).data(using: .utf8)

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

        return try AnthropicOAuth.credentials(
            fromJSON: json,
            scope: Self.scope,
            errorMap: OpenAIOAuthError.invalidTokenResponse
        )
    }

    private static func formEncoded(_ pairs: [String: String]) -> String {
        pairs
            .map { key, value in
                let escapedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let escapedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(escapedKey)=\(escapedValue)"
            }
            .joined(separator: "&")
    }

    private static func randomState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}
