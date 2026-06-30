import Foundation

public struct OAuthCredentials: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let scope: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, scope: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }

    public var isExpired: Bool {
        Date() >= expiresAt
    }

    public func expiresWithin(_ interval: TimeInterval) -> Bool {
        Date().addingTimeInterval(interval) >= expiresAt
    }
}

public enum OAuthProvider: String, Sendable, CaseIterable {
    case anthropic
    case openai
}
