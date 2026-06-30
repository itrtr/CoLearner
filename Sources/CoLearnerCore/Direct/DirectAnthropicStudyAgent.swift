import Foundation

public struct AnthropicModelOption: Sendable, Identifiable, Equatable {
    public let id: String
    public let label: String
    public let tierHint: String

    public init(id: String, label: String, tierHint: String) {
        self.id = id
        self.label = label
        self.tierHint = tierHint
    }
}

public struct DirectAnthropicStudyAgent: StudyAgent {
    public static let defaultModel = "claude-sonnet-4-6"
    public static let metadataToolName = "record_metadata"

    /// Models available via the Claude subscription (Pro / Max) OAuth path. Actual access
    /// depends on the signed-in account's tier — Pro gets Sonnet + Haiku, Max also gets Opus.
    public static let availableModels: [AnthropicModelOption] = [
        AnthropicModelOption(id: "claude-opus-4-7", label: "Opus 4.7", tierHint: "Max only"),
        AnthropicModelOption(id: "claude-sonnet-4-6", label: "Sonnet 4.6", tierHint: "Pro or Max"),
        AnthropicModelOption(id: "claude-haiku-4-5-20251001", label: "Haiku 4.5", tierHint: "Pro or Max · fastest")
    ]

    private let model: String
    private let maxTokens: Int
    private let sessionManager: OAuthSessionManager
    private let client: AnthropicMessagesClient

    public init(
        sessionManager: OAuthSessionManager,
        model: String = DirectAnthropicStudyAgent.defaultModel,
        maxTokens: Int = 4096,
        client: AnthropicMessagesClient = AnthropicMessagesClient()
    ) {
        self.sessionManager = sessionManager
        self.model = model
        self.maxTokens = maxTokens
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

        let accessToken = try await sessionManager.currentAccessToken(for: .anthropic)
        let prompt = Self.buildPrompt(selection: selection, mode: mode, learnerQuestion: learnerQuestion)

        let request = AnthropicMessagesRequest(
            model: model,
            maxTokens: maxTokens,
            system: [
                // Required identity block for OAuth subscription requests. Without it Anthropic
                // throttles the request as third-party impersonation, returning 429 even when
                // the account still has subscription quota.
                AnthropicSystemBlock(text: "You are Claude Code, Anthropic's official CLI for Claude."),
                AnthropicSystemBlock(text: Self.systemPrompt)
            ],
            messages: [AnthropicMessage(role: "user", content: prompt)],
            tools: [Self.metadataTool()],
            toolChoice: nil,
            stream: true
        )

        var collectedAnswer = ""
        var collectedMetadataJSON: String?

        for try await event in client.stream(request: request, accessToken: accessToken) {
            try Task.checkCancellation()

            switch event {
            case let .textDelta(text):
                collectedAnswer += text
                continuation.yield(.textDelta(text))

            case .toolUseStart, .toolUseDelta:
                break

            case let .toolUseComplete(name, inputJSON):
                if name == Self.metadataToolName {
                    collectedMetadataJSON = inputJSON
                }

            case .messageDone:
                break
            }
        }

        let metadata = collectedMetadataJSON.flatMap { Self.parseMetadata(from: $0) } ?? ParsedMetadata()
        let trimmedAnswer = collectedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = metadata.summary?.nonEmpty ?? trimmedAnswer

        let response = StudyResponse(
            mode: mode,
            title: metadata.title?.nonEmpty ?? Self.fallbackTitle(for: mode, question: learnerQuestion),
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

    // MARK: - Prompt

    static let systemPrompt = """
    You are the learning companion inside CoLearner, a macOS reader for papers, PDFs, notes, and books.

    Behaviour rules:
    1. Honor the learner's latest request first.
    2. Treat the supplied document context as supporting material, not a task by itself.
    3. Use the context when the learner asks about the document or asks what to highlight.
    4. If the learner only greets you, answer briefly and do not explain the context.
    5. If the learner asks something the context cannot answer, say so directly and suggest a better grounded question.
    6. Do not mention that you are a coding agent. Do not browse, inspect files, edit files, or run commands.

    Formatting:
    - Write the chat answer in GitHub-flavored Markdown: headings, bullet lists, emphasis, inline code, fenced code blocks, blockquotes, tables — whatever helps the learner.
    - Keep it focused and skimmable.
    - After your written answer, ALWAYS call the record_metadata tool exactly once with structured metadata for the answer.
    - When the question is a greeting or a non-document question, still call record_metadata but use empty arrays for keyIdeas, examples, nextQuestions, and highlights.

    Highlights are special — they drive PDF marker rendering:
    - If the learner asks anything about "highlight", "mark", "underline", "important parts", "key phrases", or "top N highlights", you MUST populate the `highlights` array in the tool call with the actual phrases you want underlined. Do not only put them in the chat text — the chat text is for explanation, the tool's `highlights` array is what the renderer reads.
    - Every phrase in `highlights` MUST appear verbatim inside the 'Active context' block — character-for-character, including the same word order. Do not summarize or rephrase.
    """

    static func buildPrompt(
        selection: ReadingSelection,
        mode: StudyMode,
        learnerQuestion: String?
    ) -> String {
        let cleanedQuestion = learnerQuestion?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "None"

        return """
        Source: \(selection.sourceTitle ?? "Untitled document")
        Study mode: \(mode.label)
        Learner request: \(cleanedQuestion)

        Active context:
        \"\"\"
        \(selection.text)
        \"\"\"
        """
    }

    static func metadataTool() -> AnthropicToolDefinition {
        let stringArray: AnyJSON = .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")])
        ])

        let schema: [String: AnyJSON] = [
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
            ])
        ]

        return AnthropicToolDefinition(
            name: metadataToolName,
            description: "Record structured metadata for the answer the assistant just wrote. Call exactly once at the end.",
            inputSchema: schema
        )
    }

    static func fallbackTitle(for mode: StudyMode, question: String?) -> String {
        if let question = question?.trimmingCharacters(in: .whitespacesAndNewlines), !question.isEmpty {
            return question.count > 48 ? "\(question.prefix(48))..." : question
        }
        return mode.label
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
