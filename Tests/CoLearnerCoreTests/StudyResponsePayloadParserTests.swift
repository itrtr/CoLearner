import CoLearnerCore
import Testing

@Suite("StudyResponsePayloadParser")
struct StudyResponsePayloadParserTests {
    @Test("parses a fenced JSON response")
    func fencedJSON() throws {
        let payload = try StudyResponsePayloadParser.parse(
            """
            ```json
            {"title":"Title","summary":"Summary","keyIdeas":["One"],"examples":["Two"],"nextQuestions":["Three?"]}
            ```
            """
        )

        #expect(payload.title == "Title")
        #expect(payload.nextQuestions == ["Three?"])
    }

    @Test("parses visible answer markdown when present")
    func answerMarkdown() throws {
        let payload = try StudyResponsePayloadParser.parse(
            """
            {"title":"Title","summary":"Summary","answerMarkdown":"## Title\\n\\nUse `queues` for async work.\\n\\n```swift\\nlet queue = Queue()\\n```","keyIdeas":["One"],"examples":["Two"],"nextQuestions":["Three?"],"highlights":[]}
            """
        )

        #expect(payload.answerMarkdown?.contains("```swift") == true)
        #expect(payload.answerMarkdown?.contains("`queues`") == true)
    }

    @Test("parses Codex JSONL agent message text")
    func codexJSONL() throws {
        let payload = try StudyResponsePayloadParser.parse(
            """
            {"type":"thread.started","thread_id":"thread"}
            {"type":"item.completed","item":{"type":"agent_message","text":"{\\"title\\":\\"Title\\",\\"summary\\":\\"Summary\\",\\"keyIdeas\\":[\\"One\\"],\\"examples\\":[\\"Two\\"],\\"nextQuestions\\":[\\"Three?\\"]}"}}
            {"type":"turn.completed"}
            """
        )

        #expect(payload.summary == "Summary")
        #expect(payload.keyIdeas == ["One"])
    }

    @Test("parses Claude structured output")
    func claudeStructuredOutput() throws {
        let payload = try StudyResponsePayloadParser.parse(
            """
            {"result":"ok","structured_output":{"title":"Title","summary":"Summary","keyIdeas":["One"],"examples":["Two"],"nextQuestions":["Three?"]}}
            """
        )

        #expect(payload.examples == ["Two"])
    }

    @Test("parses nested text from generic agent events")
    func nestedTextEvent() throws {
        let payload = try StudyResponsePayloadParser.parse(
            """
            {"event":"message","content":[{"type":"text","text":"{\\"title\\":\\"Nested\\",\\"summary\\":\\"Summary\\",\\"keyIdeas\\":[\\"One\\"],\\"examples\\":[\\"Two\\"],\\"nextQuestions\\":[\\"Three?\\"]}"}]}
            """
        )

        #expect(payload.title == "Nested")
    }
}
