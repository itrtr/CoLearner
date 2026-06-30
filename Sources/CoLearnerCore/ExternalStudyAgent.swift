import Foundation

public struct ExternalStudyAgent: StudyAgent {
    private let provider: StudyAgentProvider
    private let commandRunner: any CommandRunning

    public init(provider: StudyAgentProvider, commandRunner: any CommandRunning = ProcessCommandRunner()) {
        self.provider = provider
        self.commandRunner = commandRunner
    }

    public func respond(
        to selection: ReadingSelection,
        mode: StudyMode,
        learnerQuestion: String? = nil
    ) async throws -> StudyResponse {
        guard !selection.isEmpty else {
            throw StudyAgentError.emptySelection
        }

        let prompt = ExternalStudyAgentPrompt.build(
            selection: selection,
            mode: mode,
            provider: provider,
            learnerQuestion: learnerQuestion
        )
        let result = try await commandRunner.run(provider.commandInvocation(prompt: prompt))

        guard result.exitCode == 0 else {
            throw Self.error(for: provider, result: result)
        }

        let payload = try StudyResponsePayloadParser.parse(result.standardOutput)
        return payload.studyResponse(mode: mode, selection: selection)
    }

    private static func error(for provider: StudyAgentProvider, result: CommandResult) -> StudyAgentError {
        let output = result.combinedOutput
        let installHint = switch provider {
        case .local, .codex, .claude:
            ""
        case .openCode:
            "Install OpenCode and connect a supported provider."
        case .pi:
            "Install Pi and configure a model/provider."
        case .hermes:
            "Install Hermes and run `hermes login` or `hermes setup` first."
        }

        if output.localizedCaseInsensitiveContains("no such file")
            || output.localizedCaseInsensitiveContains("not found")
            || output.localizedCaseInsensitiveContains("enoent") {
            return .providerUnavailable("\(provider.label) is not available. \(installHint)")
        }

        let message = output.isEmpty
            ? "\(provider.label) exited with code \(result.exitCode)."
            : output

        return .providerFailed(message)
    }
}

public enum ExternalStudyAgentPrompt {
    public static let responseSchema = """
    {"type":"object","properties":{"title":{"type":"string"},"summary":{"type":"string"},"answerMarkdown":{"type":"string"},"keyIdeas":{"type":"array","items":{"type":"string"},"maxItems":5},"examples":{"type":"array","items":{"type":"string"},"maxItems":4},"nextQuestions":{"type":"array","items":{"type":"string"},"maxItems":4},"highlights":{"type":"array","items":{"type":"string"},"maxItems":5}},"required":["title","summary","answerMarkdown","keyIdeas","examples","nextQuestions","highlights"],"additionalProperties":false}
    """

    public static func build(
        selection: ReadingSelection,
        mode: StudyMode,
        provider: StudyAgentProvider,
        learnerQuestion: String? = nil
    ) -> String {
        let cleanedQuestion = learnerQuestion?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "None"

        return """
        You are the learning companion inside CoLearner, a macOS reader for papers, PDFs, notes, and books.

        Help the learner in CoLearner. Do not mention that you are a coding agent. Do not use tools, browse, inspect files, edit files, or run commands.

        Intent priority:
        1. Honor the learner's latest request first.
        2. Treat the active context as supporting PDF context, not as a task by itself.
        3. Use the active context when the learner asks about the document, asks for a quick action, or asks what to highlight.
        4. If the learner only greets the assistant, answer briefly and do not explain the active context.
        5. If the learner asks which assistant, model, or provider is answering, answer from the Provider field. If the exact model is not provided, say it is controlled by the provider's local CLI/account settings.
        6. If the learner asks something that the active context cannot answer, say that directly and suggest a better document-grounded question.
        7. For greetings, provider/model questions, and non-document questions, use empty arrays for keyIdeas, examples, nextQuestions, and highlights.

        Provider: \(provider.label)
        Source: \(selection.sourceTitle ?? "Untitled document")
        Study mode: \(mode.label)
        Learner request: \(cleanedQuestion)

        Return one valid JSON object matching this schema exactly:
        \(responseSchema)

        Field rules:
        - title: short and specific.
        - summary: plain-language explanation for the chosen study mode.
        - answerMarkdown: the final visible chat answer in GitHub-flavored Markdown. Use headings, bullet lists, emphasis, inline code, and fenced code blocks when useful. Keep it consistent with summary, keyIdeas, examples, and nextQuestions. Do not include PDF highlight suggestions here unless the learner explicitly asks what to highlight.
        - keyIdeas: the most important concepts or claims.
        - examples: concrete examples or analogies. In quiz mode, include one short usage tip instead.
        - nextQuestions: questions the learner should answer next.
        - highlights: exact short snippets copied verbatim from the active context that should be highlighted in the PDF. Include highlights only when they help the learner's request. Do not paraphrase highlight snippets.

        Active context:
        \"\"\"
        \(selection.text)
        \"\"\"
        """
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

extension StudyAgentProvider {
    fileprivate func commandInvocation(prompt: String) -> CommandInvocation {
        switch self {
        case .local:
            preconditionFailure("Local provider does not use an external command.")
        case .codex, .claude:
            preconditionFailure("\(label) uses the direct API path (DirectAnthropicStudyAgent / DirectOpenAIStudyAgent), not a CLI subprocess.")
        case .openCode:
            CommandInvocation(
                executable: "/usr/bin/env",
                arguments: [
                    "opencode",
                    "run",
                    "--format",
                    "json",
                    "--title",
                    "CoLearner"
                ] + Self.openCodeAttachArguments() + [prompt],
                environment: Self.subscriptionEnvironment(removing: []),
                currentDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
        case .pi:
            CommandInvocation(
                executable: "/usr/bin/env",
                arguments: [
                    "pi",
                    "--print",
                    "--mode",
                    "text",
                    "--no-tools",
                    "--no-skills",
                    "--no-prompt-templates",
                    "--no-themes",
                    "--no-context-files",
                    "--no-session",
                    prompt
                ],
                environment: Self.subscriptionEnvironment(removing: []),
                currentDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
        case .hermes:
            CommandInvocation(
                executable: "/usr/bin/env",
                arguments: [
                    "hermes",
                    "--oneshot",
                    prompt,
                    "--ignore-rules"
                ],
                environment: Self.subscriptionEnvironment(removing: []),
                currentDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
        }
    }

    private static func openCodeAttachArguments() -> [String] {
        guard let url = ProcessInfo.processInfo.environment["COLEARNER_OPENCODE_ATTACH_URL"],
              !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return ["--attach", url]
    }

    private static func subscriptionEnvironment(removing removedKeys: Set<String>) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        removedKeys.forEach { environment.removeValue(forKey: $0) }

        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existingPath = environment["PATH"], !existingPath.isEmpty {
            environment["PATH"] = "\(defaultPath):\(existingPath)"
        } else {
            environment["PATH"] = defaultPath
        }

        return environment
    }
}
