import Foundation

enum StudyAgentDirectResponse {
    static func response(
        for learnerQuestion: String?,
        mode: StudyMode,
        provider: StudyAgentProvider,
        sourceExcerpt: String
    ) -> StudyResponse? {
        guard let normalizedQuestion = normalizedQuestion(from: learnerQuestion) else {
            return nil
        }

        if isAssistantIdentityQuestion(normalizedQuestion) {
            return identityResponse(
                mode: mode,
                provider: provider,
                sourceExcerpt: sourceExcerpt
            )
        }

        guard isGreeting(normalizedQuestion) else {
            return nil
        }

        return greetingResponse(
            mode: mode,
            provider: provider,
            sourceExcerpt: sourceExcerpt
        )
    }

    private static func normalizedQuestion(from learnerQuestion: String?) -> String? {
        guard let learnerQuestion else {
            return nil
        }

        let normalizedQuestion = learnerQuestion
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return normalizedQuestion.isEmpty ? nil : normalizedQuestion
    }

    private static func greetingResponse(
        mode: StudyMode,
        provider: StudyAgentProvider,
        sourceExcerpt: String
    ) -> StudyResponse {
        let providerPrefix = provider == .local
            ? "Local offline helper is ready."
            : "\(provider.label) is selected."

        return StudyResponse(
            mode: mode,
            title: provider == .local ? "Ready" : "Ready with \(provider.label)",
            summary: "Hi. \(providerPrefix) Ask a question about the active context, or use a quick action for a summary, explanation, quiz, examples, or highlights.",
            keyIdeas: [],
            examples: [],
            nextQuestions: [],
            highlights: [],
            sourceExcerpt: sourceExcerpt
        )
    }

    private static func identityResponse(
        mode: StudyMode,
        provider: StudyAgentProvider,
        sourceExcerpt: String
    ) -> StudyResponse {
        let title = provider == .local
            ? "Local offline helper"
            : "\(provider.label) provider"
        let summary = if provider == .local {
            "You are currently using CoLearner's Local offline helper, not Codex. It is a fast built-in helper for PDF context, summaries, quizzes, examples, and highlights. To use Codex, choose Codex from the provider menu at the top of AI Companion."
        } else {
            "You are currently using the \(provider.label) provider. CoLearner sends the active context to \(provider.label) through its local CLI integration. The exact model is controlled by that provider's CLI/account settings."
        }

        return StudyResponse(
            mode: mode,
            title: title,
            summary: summary,
            keyIdeas: [],
            examples: [],
            nextQuestions: [],
            highlights: [],
            sourceExcerpt: sourceExcerpt
        )
    }

    private static func isGreeting(_ normalizedQuestion: String) -> Bool {
        [
            "hi",
            "hello",
            "hey",
            "hey there",
            "good morning",
            "good afternoon",
            "good evening"
        ].contains(normalizedQuestion)
    }

    private static func isAssistantIdentityQuestion(_ normalizedQuestion: String) -> Bool {
        if normalizedQuestion == "who are you" {
            return true
        }

        let terms = Set(normalizedQuestion.split(separator: " ").map(String.init))
        let mentionsAssistant = terms.contains("you")
            || terms.contains("your")
            || terms.contains("assistant")
            || terms.contains("ai")
            || terms.contains("codex")
            || terms.contains("local")
            || terms.contains("provider")
        let asksModelOrProvider = terms.contains("model")
            || terms.contains("provider")
            || terms.contains("codex")
            || normalizedQuestion.contains("which ai")
            || normalizedQuestion.contains("what ai")

        return mentionsAssistant && asksModelOrProvider
    }
}
