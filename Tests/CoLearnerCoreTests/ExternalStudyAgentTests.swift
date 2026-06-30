import CoLearnerCore
import Foundation
import Testing

@Suite("ExternalStudyAgent")
struct ExternalStudyAgentTests {
    @Test("reports missing external provider with setup hint")
    func missingProvider() async {
        let runner = RecordingCommandRunner(
            result: CommandResult(
                exitCode: 127,
                standardOutput: "",
                standardError: "env: pi: No such file or directory"
            )
        )
        let agent = ExternalStudyAgent(provider: .pi, commandRunner: runner)
        let selection = ReadingSelection(text: "A useful selected passage.")

        await #expect(throws: StudyAgentError.providerUnavailable("Pi is not available. Install Pi and configure a model/provider.")) {
            _ = try await agent.respond(to: selection, mode: .examples)
        }
    }

    @Test("opencode provider uses its run command")
    func openCodeInvocation() async throws {
        let runner = RecordingCommandRunner(
            result: CommandResult(
                exitCode: 0,
                standardOutput: """
                ```json
                {"title":"OpenCode","summary":"Summary","keyIdeas":["Idea"],"examples":["Example"],"nextQuestions":["Question?"]}
                ```
                """,
                standardError: ""
            )
        )
        let agent = ExternalStudyAgent(provider: .openCode, commandRunner: runner)
        let selection = ReadingSelection(text: "Learners build mental models by connecting examples to claims.")

        _ = try await agent.respond(to: selection, mode: .examples)
        let invocation = try #require(await runner.invocations.first)

        #expect(invocation.arguments.prefix(5) == [
            "opencode",
            "run",
            "--format",
            "json",
            "--title"
        ])
        #expect(invocation.arguments.last?.contains("Learners build mental models") == true)
    }

    @Test("pi provider disables tools and sessions for learning answers")
    func piInvocation() async throws {
        let runner = RecordingCommandRunner(
            result: CommandResult(
                exitCode: 0,
                standardOutput: """
                {"title":"Pi","summary":"Summary","keyIdeas":["Idea"],"examples":["Example"],"nextQuestions":["Question?"]}
                """,
                standardError: ""
            )
        )
        let agent = ExternalStudyAgent(provider: .pi, commandRunner: runner)
        let selection = ReadingSelection(text: "Spacing practice improves recall.")

        _ = try await agent.respond(to: selection, mode: .quiz, learnerQuestion: "Why does this matter?")
        let invocation = try #require(await runner.invocations.first)

        #expect(invocation.arguments.contains("pi"))
        #expect(invocation.arguments.contains("--no-tools"))
        #expect(invocation.arguments.contains("--no-session"))
        #expect(invocation.arguments.last?.contains("Learner request: Why does this matter?") == true)
    }

    @Test("hermes provider uses one-shot mode")
    func hermesInvocation() async throws {
        let runner = RecordingCommandRunner(
            result: CommandResult(
                exitCode: 0,
                standardOutput: """
                {"title":"Hermes","summary":"Summary","keyIdeas":["Idea"],"examples":["Example"],"nextQuestions":["Question?"]}
                """,
                standardError: ""
            )
        )
        let agent = ExternalStudyAgent(provider: .hermes, commandRunner: runner)
        let selection = ReadingSelection(text: "A theorem links assumptions to a conclusion.")

        _ = try await agent.respond(to: selection, mode: .explain)
        let invocation = try #require(await runner.invocations.first)

        #expect(invocation.arguments.prefix(2) == ["hermes", "--oneshot"])
        #expect(invocation.arguments.contains("--ignore-rules"))
    }
}

private actor RecordingCommandRunner: CommandRunning {
    private(set) var invocations = [CommandInvocation]()
    private let result: CommandResult

    init(result: CommandResult) {
        self.result = result
    }

    func run(_ invocation: CommandInvocation) async throws -> CommandResult {
        invocations.append(invocation)
        return result
    }
}
