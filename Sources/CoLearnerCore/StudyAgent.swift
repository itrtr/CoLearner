import Foundation

public enum StudyMode: String, CaseIterable, Identifiable, Sendable {
    case explain
    case simplify
    case examples
    case quiz

    public var id: String {
        rawValue
    }

    public var label: String {
        switch self {
        case .explain:
            "Explain"
        case .simplify:
            "Simplify"
        case .examples:
            "Examples"
        case .quiz:
            "Quiz"
        }
    }
}

public enum StudyAgentProvider: String, CaseIterable, Identifiable, Sendable {
    case local
    case codex
    case claude
    case openCode
    case pi
    case hermes

    public var id: String {
        rawValue
    }

    public var label: String {
        switch self {
        case .local:
            "Local"
        case .codex:
            "Codex"
        case .claude:
            "Claude"
        case .openCode:
            "OpenCode"
        case .pi:
            "Pi"
        case .hermes:
            "Hermes"
        }
    }

    public var detail: String {
        switch self {
        case .local:
            "Offline deterministic helper"
        case .codex:
            "Direct ChatGPT API via your subscription sign-in"
        case .claude:
            "Direct Anthropic API via your Claude subscription sign-in"
        case .openCode:
            "Uses OpenCode auth and models"
        case .pi:
            "Uses Pi configured auth"
        case .hermes:
            "Uses Hermes configured auth"
        }
    }

    public var usesDirectAPI: Bool {
        switch self {
        case .claude, .codex:
            true
        case .local, .openCode, .pi, .hermes:
            false
        }
    }

    /// Build a study agent for CLI-backed providers. `.claude` and `.codex` now go through
    /// the direct API path in the app (see `DirectAnthropicStudyAgent` /
    /// `DirectOpenAIStudyAgent`) and must be constructed with an `OAuthSessionManager`,
    /// not via this factory.
    public func makeStudyAgent(commandRunner: any CommandRunning = ProcessCommandRunner()) -> any StudyAgent {
        switch self {
        case .local:
            LocalStudyAgent()
        case .openCode, .pi, .hermes:
            ExternalStudyAgent(provider: self, commandRunner: commandRunner)
        case .codex, .claude:
            preconditionFailure("Use DirectAnthropicStudyAgent or DirectOpenAIStudyAgent with an OAuthSessionManager for \(self.label).")
        }
    }
}

public struct StudyResponse: Equatable, Sendable {
    public let mode: StudyMode
    public let title: String
    public let summary: String
    public let keyIdeas: [String]
    public let examples: [String]
    public let nextQuestions: [String]
    public let highlights: [String]
    public let answerMarkdown: String?
    public let sourceExcerpt: String

    public init(
        mode: StudyMode,
        title: String,
        summary: String,
        keyIdeas: [String],
        examples: [String],
        nextQuestions: [String],
        highlights: [String] = [],
        answerMarkdown: String? = nil,
        sourceExcerpt: String
    ) {
        self.mode = mode
        self.title = title
        self.summary = summary
        self.keyIdeas = keyIdeas
        self.examples = examples
        self.nextQuestions = nextQuestions
        self.highlights = highlights
        self.answerMarkdown = answerMarkdown
        self.sourceExcerpt = sourceExcerpt
    }
}

public enum StudyAgentError: Error, Equatable, LocalizedError, Sendable {
    case emptySelection
    case providerUnavailable(String)
    case providerFailed(String)
    case invalidProviderResponse(String)

    public var errorDescription: String? {
        switch self {
        case .emptySelection:
            "Select text in the reader before asking the assistant."
        case let .providerUnavailable(message):
            message
        case let .providerFailed(message):
            message
        case let .invalidProviderResponse(message):
            message
        }
    }
}

public enum StudyResponseEvent: Sendable {
    /// Incremental markdown text to append to the visible chat answer.
    case textDelta(String)
    /// Final assembled response. Emitted exactly once at the end of a successful stream.
    case complete(StudyResponse)
}

public protocol StudyAgent: Sendable {
    func respond(
        to selection: ReadingSelection,
        mode: StudyMode,
        learnerQuestion: String?
    ) async throws -> StudyResponse

    func stream(
        to selection: ReadingSelection,
        mode: StudyMode,
        learnerQuestion: String?
    ) -> AsyncThrowingStream<StudyResponseEvent, Error>
}

public extension StudyAgent {
    func respond(to selection: ReadingSelection, mode: StudyMode) async throws -> StudyResponse {
        try await respond(to: selection, mode: mode, learnerQuestion: nil)
    }

    /// Default streaming implementation: runs the non-streaming `respond` and emits a single
    /// `.complete` event. Agents that natively stream override this.
    func stream(
        to selection: ReadingSelection,
        mode: StudyMode,
        learnerQuestion: String?
    ) -> AsyncThrowingStream<StudyResponseEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await respond(
                        to: selection,
                        mode: mode,
                        learnerQuestion: learnerQuestion
                    )
                    continuation.yield(.textDelta(response.answerMarkdown ?? response.summary))
                    continuation.yield(.complete(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
