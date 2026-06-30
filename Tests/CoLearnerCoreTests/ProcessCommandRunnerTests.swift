import CoLearnerCore
import Testing

@Suite("ProcessCommandRunner")
struct ProcessCommandRunnerTests {
    @Test("does not terminate parent when child exits before reading stdin")
    func earlyChildExitWithStandardInput() async throws {
        let runner = ProcessCommandRunner()
        let result = try await runner.run(
            CommandInvocation(
                executable: "/usr/bin/false",
                arguments: [],
                standardInput: String(repeating: "selected text ", count: 10_000)
            )
        )

        #expect(result.exitCode != 0)
    }
}
