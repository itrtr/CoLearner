import CoLearnerCore
import Testing

@Suite("LocalStudyAgent")
struct LocalStudyAgentTests {
    @Test("normalizes selected text before generating a response")
    func normalizedSelection() async throws {
        let agent = LocalStudyAgent()
        let selection = ReadingSelection(
            text: """
            Neural networks     learn representations.

            These representations support classification.
            """,
            sourceTitle: "Paper"
        )

        let response = try await agent.respond(to: selection, mode: .explain)

        #expect(response.sourceExcerpt == "Neural networks learn representations. These representations support classification.")
        #expect(response.title == "Plain-language explanation from Paper")
        #expect(response.keyIdeas.contains("Important terms to track: representations, classification, learn, networks, neural."))
    }

    @Test("throws a useful error for an empty selection")
    func emptySelection() async {
        let agent = LocalStudyAgent()
        let selection = ReadingSelection(text: "   \n  ")

        await #expect(throws: StudyAgentError.emptySelection) {
            _ = try await agent.respond(to: selection, mode: .explain)
        }
    }

    @Test("quiz mode creates self-check questions")
    func quizMode() async throws {
        let agent = LocalStudyAgent()
        let selection = ReadingSelection(
            text: "Retrieval augmented generation connects a language model to external evidence before it answers."
        )

        let response = try await agent.respond(to: selection, mode: .quiz)

        #expect(response.mode == .quiz)
        #expect(response.summary.contains("Use the questions below"))
        #expect(response.nextQuestions.count == 4)
    }

    @Test("answers code availability questions directly")
    func codeAvailabilityQuestion() async throws {
        let agent = LocalStudyAgent()
        let selection = ReadingSelection(
            text: "Message queues support cloud-based applications by improving scalability, fault tolerance, and asynchronous communication.",
            sourceTitle: "Message Queue Paper"
        )

        let response = try await agent.respond(
            to: selection,
            mode: .explain,
            learnerQuestion: "Any code in this paper?"
        )

        #expect(response.summary.contains("No code or pseudocode is visible"))
        #expect(response.nextQuestions.contains { $0.contains("full document") || $0.contains("whole PDF") })
    }

    @Test("answers greetings without dumping document context")
    func greetingQuestion() async throws {
        let agent = LocalStudyAgent()
        let selection = ReadingSelection(
            text: "Message queues support asynchronous communication across distributed systems.",
            sourceTitle: "Message Queue Paper"
        )

        let response = try await agent.respond(
            to: selection,
            mode: .explain,
            learnerQuestion: "Hi"
        )

        #expect(response.title == "Ready")
        #expect(response.summary.hasPrefix("Hi."))
        #expect(response.keyIdeas.isEmpty)
        #expect(response.examples.isEmpty)
        #expect(response.nextQuestions.isEmpty)
        #expect(response.highlights.isEmpty)
    }

    @Test("answers assistant identity questions without searching the document")
    func assistantIdentityQuestion() async throws {
        let agent = LocalStudyAgent()
        let selection = ReadingSelection(
            text: "Message queues support asynchronous communication across distributed systems.",
            sourceTitle: "Message Queue Paper"
        )

        let response = try await agent.respond(
            to: selection,
            mode: .explain,
            learnerQuestion: "Which model are you?"
        )

        #expect(response.title == "Local offline helper")
        #expect(response.summary.contains("not Codex"))
        #expect(response.summary.contains("provider menu"))
        #expect(response.keyIdeas.isEmpty)
        #expect(response.examples.isEmpty)
        #expect(response.nextQuestions.isEmpty)
        #expect(response.highlights.isEmpty)
    }
}
