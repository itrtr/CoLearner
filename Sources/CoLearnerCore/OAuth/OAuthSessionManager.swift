import Foundation

public enum OAuthSessionError: Error, LocalizedError {
    case notSignedIn(OAuthProvider)
    case providerError(Error)
    case storageError(Error)

    public var errorDescription: String? {
        switch self {
        case let .notSignedIn(provider):
            "Sign in to \(provider.rawValue.capitalized) first."
        case let .providerError(error), let .storageError(error):
            error.localizedDescription
        }
    }
}

public actor OAuthSessionManager {
    private let store: any CredentialStoring
    private let anthropic: AnthropicOAuth
    private let openAI: OpenAIOAuth
    private let urlOpener: @Sendable (URL) -> Void

    private var cachedCredentials = [OAuthProvider: OAuthCredentials]()
    private var inFlightLogins = [OAuthProvider: Task<OAuthCredentials, Error>]()
    private var inFlightRefreshes = [OAuthProvider: Task<OAuthCredentials, Error>]()

    public init(
        store: any CredentialStoring,
        anthropic: AnthropicOAuth = AnthropicOAuth(),
        openAI: OpenAIOAuth = OpenAIOAuth(),
        urlOpener: @escaping @Sendable (URL) -> Void
    ) {
        self.store = store
        self.anthropic = anthropic
        self.openAI = openAI
        self.urlOpener = urlOpener
    }

    public func isSignedIn(_ provider: OAuthProvider) -> Bool {
        if cachedCredentials[provider] != nil {
            return true
        }
        let stored = try? store.load(for: provider)
        if let stored {
            cachedCredentials[provider] = stored
            return true
        }
        return false
    }

    public func signOut(_ provider: OAuthProvider) throws {
        cachedCredentials.removeValue(forKey: provider)
        do {
            try store.delete(for: provider)
        } catch {
            throw OAuthSessionError.storageError(error)
        }
    }

    public func currentAccessToken(for provider: OAuthProvider) async throws -> String {
        let credentials = try await currentCredentials(for: provider)
        return credentials.accessToken
    }

    public func currentCredentials(for provider: OAuthProvider) async throws -> OAuthCredentials {
        if let cached = cachedCredentials[provider] ?? (try? store.load(for: provider)) {
            cachedCredentials[provider] = cached
            if !cached.expiresWithin(60) {
                return cached
            }
            return try await refresh(provider, using: cached)
        }
        throw OAuthSessionError.notSignedIn(provider)
    }

    public func signIn(_ provider: OAuthProvider) async throws -> OAuthCredentials {
        if let task = inFlightLogins[provider] {
            return try await task.value
        }

        let task = Task { () throws -> OAuthCredentials in
            switch provider {
            case .anthropic:
                try await performAnthropicLogin()
            case .openai:
                try await performOpenAILogin()
            }
        }
        inFlightLogins[provider] = task
        defer { inFlightLogins[provider] = nil }

        do {
            let credentials = try await task.value
            cachedCredentials[provider] = credentials
            do {
                try store.save(credentials, for: provider)
            } catch {
                throw OAuthSessionError.storageError(error)
            }
            return credentials
        } catch let error as OAuthSessionError {
            throw error
        } catch {
            throw OAuthSessionError.providerError(error)
        }
    }

    private func refresh(_ provider: OAuthProvider, using credentials: OAuthCredentials) async throws -> OAuthCredentials {
        if let task = inFlightRefreshes[provider] {
            return try await task.value
        }

        let task = Task { () throws -> OAuthCredentials in
            switch provider {
            case .anthropic:
                try await anthropic.refresh(refreshToken: credentials.refreshToken)
            case .openai:
                try await openAI.refresh(refreshToken: credentials.refreshToken)
            }
        }
        inFlightRefreshes[provider] = task
        defer { inFlightRefreshes[provider] = nil }

        do {
            let refreshed = try await task.value
            cachedCredentials[provider] = refreshed
            do {
                try store.save(refreshed, for: provider)
            } catch {
                throw OAuthSessionError.storageError(error)
            }
            return refreshed
        } catch {
            cachedCredentials.removeValue(forKey: provider)
            throw OAuthSessionError.providerError(error)
        }
    }

    private func performAnthropicLogin() async throws -> OAuthCredentials {
        let session = try anthropic.startSession()
        let server = LocalCallbackServer(
            port: AnthropicOAuth.callbackPort,
            path: AnthropicOAuth.callbackPath
        )

        async let callbackTask = server.waitForCallback(
            successHTML: OAuthCallbackPage.success("CoLearner has your Anthropic sign-in. You can return to the app."),
            errorHTML: OAuthCallbackPage.failure("Try signing in again from CoLearner.")
        )

        urlOpener(session.authorizationURL)

        let result: LocalCallbackResult
        do {
            result = try await callbackTask
        } catch {
            await server.cancel()
            throw error
        }

        if let errorMessage = result.error {
            throw AnthropicOAuthError.callbackError(errorMessage)
        }

        guard let code = result.code else {
            throw AnthropicOAuthError.missingCode
        }

        let state = result.state ?? session.pkce.verifier

        return try await anthropic.exchange(
            code: code,
            state: state,
            pkce: session.pkce,
            redirectURI: session.redirectURI
        )
    }

    private func performOpenAILogin() async throws -> OAuthCredentials {
        let session = try openAI.startSession()
        let server = LocalCallbackServer(
            port: OpenAIOAuth.callbackPort,
            path: OpenAIOAuth.callbackPath
        )

        async let callbackTask = server.waitForCallback(
            successHTML: OAuthCallbackPage.success("CoLearner has your OpenAI sign-in. You can return to the app."),
            errorHTML: OAuthCallbackPage.failure("Try signing in again from CoLearner.")
        )

        urlOpener(session.authorizationURL)

        let result: LocalCallbackResult
        do {
            result = try await callbackTask
        } catch {
            await server.cancel()
            throw error
        }

        if let errorMessage = result.error {
            throw OpenAIOAuthError.callbackError(errorMessage)
        }

        guard let code = result.code else {
            throw OpenAIOAuthError.missingCode
        }

        return try await openAI.exchange(
            code: code,
            pkce: session.pkce,
            redirectURI: session.redirectURI
        )
    }
}
