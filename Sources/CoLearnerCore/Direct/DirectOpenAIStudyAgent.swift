import Foundation

public struct OpenAIModelOption: Sendable, Identifiable, Equatable {
    public let id: String
    public let label: String
    public let tierHint: String

    public init(id: String, label: String, tierHint: String) {
        self.id = id
        self.label = label
        self.tierHint = tierHint
    }
}

public struct DirectOpenAIStudyAgent: StudyAgent {
    /// Codex backend (`chatgpt.com/backend-api/codex/responses`) only accepts the model IDs
    /// the Codex CLI itself advertises. Anything else is rejected with
    /// `400 The '<id>' model is not supported when using Codex with a ChatGPT account.`
    public static let defaultModel = "gpt-5.5"
    public static let metadataToolName = "record_metadata"

    /// Models accepted by the Codex backend with a ChatGPT subscription OAuth token.
    /// Mirrors the list shown by `codex` (`/models`) — Frontier on top, coding-tuned below.
    public static let availableModels: [OpenAIModelOption] = [
        OpenAIModelOption(id: "gpt-5.5", label: "GPT-5.5", tierHint: "Frontier · default"),
        OpenAIModelOption(id: "gpt-5.4", label: "GPT-5.4", tierHint: "Everyday"),
        OpenAIModelOption(id: "gpt-5.4-mini", label: "GPT-5.4 Mini", tierHint: "Fast · low-cost"),
        OpenAIModelOption(id: "gpt-5.3-codex", label: "GPT-5.3 Codex", tierHint: "Coding-tuned"),
        OpenAIModelOption(id: "gpt-5.3-codex-spark", label: "GPT-5.3 Codex Spark", tierHint: "Coding · ultra-fast"),
        OpenAIModelOption(id: "gpt-5.2", label: "GPT-5.2", tierHint: "Long-running agents")
    ]

    private let model: String
    private let sessionManager: OAuthSessionManager
    private let client: OpenAIResponsesClient

    public init(
        sessionManager: OAuthSessionManager,
        model: String = DirectOpenAIStudyAgent.defaultModel,
        client: OpenAIResponsesClient = OpenAIResponsesClient()
    ) {
        self.sessionManager = sessionManager
        self.model = model
        self.client = client
    }

    public func respond(
        to selection: ReadingSelection,
        mode: StudyMode,
        learnerQuestion: String?
    ) async throws -> StudyResponse {
        var collected: StudyResponse?
        var collectedText = ""
        for try await event in stream(to: selection, mode: mode, learnerQuestion: learnerQuestion) {
            switch event {
            case let .textDelta(chunk):
                collectedText += chunk
            case let .complete(response):
                collected = response
            }
        }
        if let collected {
            return collected
        }
        return StudyResponse(
            mode: mode,
            title: "Response",
            summary: collectedText,
            keyIdeas: [],
            examples: [],
            nextQuestions: [],
            highlights: [],
            answerMarkdown: collectedText,
            sourceExcerpt: selection.excerpt
        )
    }

    public func stream(
        to selection: ReadingSelection,
        mode: StudyMode,
        learnerQuestion: String?
    ) -> AsyncThrowingStream<StudyResponseEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(
                        selection: selection,
                        mode: mode,
                        learnerQuestion: learnerQuestion,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        selection: ReadingSelection,
        mode: StudyMode,
        learnerQuestion: String?,
        continuation: AsyncThrowingStream<StudyResponseEvent, Error>.Continuation
    ) async throws {
        guard !selection.isEmpty else {
            throw StudyAgentError.emptySelection
        }

        let accessToken = try await sessionManager.currentAccessToken(for: .openai)
        let prompt = DirectAnthropicStudyAgent.buildPrompt(
            selection: selection,
            mode: mode,
            learnerQuestion: learnerQuestion
        )

        let request = OpenAIResponsesRequest(
            model: model,
            instructions: DirectAnthropicStudyAgent.systemPrompt,
            input: [OpenAIResponsesInputMessage(role: "user", text: prompt)],
            tools: [Self.metadataTool()],
            stream: true,
            store: false,
            parallelToolCalls: false,
            reasoning: OpenAIReasoningOptions(effort: "low"),
            text: OpenAITextOptions(verbosity: "medium")
        )

        var collectedAnswer = ""
        var metadataArguments: String?

        for try await event in client.stream(request: request, accessToken: accessToken) {
            try Task.checkCancellation()

            switch event {
            case let .textDelta(chunk):
                collectedAnswer += chunk
                continuation.yield(.textDelta(chunk))

            case .toolCallStart, .toolCallDelta:
                break

            case let .toolCallComplete(name, _, arguments):
                if name == Self.metadataToolName {
                    metadataArguments = arguments
                }

            case .completed:
                break
            }
        }

        let metadata = metadataArguments.flatMap { Self.parseMetadata(from: $0) } ?? ParsedMetadata()
        let trimmedAnswer = collectedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = metadata.summary?.nonEmpty ?? trimmedAnswer

        let response = StudyResponse(
            mode: mode,
            title: metadata.title?.nonEmpty ?? DirectAnthropicStudyAgent.fallbackTitle(for: mode, question: learnerQuestion),
            summary: summary.isEmpty ? trimmedAnswer : summary,
            keyIdeas: metadata.keyIdeas,
            examples: metadata.examples,
            nextQuestions: metadata.nextQuestions,
            highlights: metadata.highlights,
            answerMarkdown: trimmedAnswer.isEmpty ? summary : trimmedAnswer,
            sourceExcerpt: selection.excerpt
        )

        continuation.yield(.complete(response))
    }

    static func metadataTool() -> OpenAIResponsesTool {
        let stringArray: AnyJSON = .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")])
        ])

        let parameters: [String: AnyJSON] = [
            "type": .string("object"),
            "properties": .object([
                "title": .object(["type": .string("string"), "description": .string("Short, specific headline for the answer.")]),
                "summary": .object(["type": .string("string"), "description": .string("One-paragraph plain-language summary of the answer.")]),
                "keyIdeas": stringArray,
                "examples": stringArray,
                "nextQuestions": stringArray,
                "highlights": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Short verbatim phrases to underline in the PDF. Rules: (1) copy the phrase character-for-character from the 'Active context' block above — no paraphrasing; (2) each phrase must be 4–12 words long; (3) pick the most distinctive multi-word run that uniquely pinpoints the sentence — avoid starting with common words like 'The' or 'A'; (4) return 3–5 phrases maximum; (5) if no meaningful phrases exist, return an empty array.")
                ])
            ]),
            "required": .array([
                .string("title"),
                .string("summary"),
                .string("keyIdeas"),
                .string("examples"),
                .string("nextQuestions"),
                .string("highlights")
            ]),
            "additionalProperties": .bool(false)
        ]

        return OpenAIResponsesTool(
            name: metadataToolName,
            description: "Record structured metadata for the answer the assistant just wrote. Call exactly once at the end.",
            parameters: parameters,
            strict: false
        )
    }

    private struct ParsedMetadata {
        var title: String?
        var summary: String?
        var keyIdeas: [String] = []
        var examples: [String] = []
        var nextQuestions: [String] = []
        var highlights: [String] = []
    }

    private static func parseMetadata(from rawJSON: String) -> ParsedMetadata? {
        guard let data = rawJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var metadata = ParsedMetadata()
        metadata.title = object["title"] as? String
        metadata.summary = object["summary"] as? String
        metadata.keyIdeas = (object["keyIdeas"] as? [String]) ?? []
        metadata.examples = (object["examples"] as? [String]) ?? []
        metadata.nextQuestions = (object["nextQuestions"] as? [String]) ?? []
        metadata.highlights = (object["highlights"] as? [String]) ?? []
        return metadata
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
