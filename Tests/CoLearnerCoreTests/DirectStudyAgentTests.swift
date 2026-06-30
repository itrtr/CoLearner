@testable import CoLearnerCore
import Foundation
import Testing

@Suite("Direct study agents")
struct DirectStudyAgentTests {
    // MARK: - OpenAI JWT account-id extraction

    @Test("extracts the ChatGPT account id from a JWT payload")
    func accountIDFromJWT() throws {
        let payload: [String: Any] = [
            OpenAIResponsesClient.chatgptAuthClaim: ["chatgpt_account_id": "acc_12345"]
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let payloadB64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        // {"alg":"none"} base64url — synthetic test fixture, not a real credential.
        let headerB64 = "eyJhbGciOiJub25lIn0"
        let jwt = [headerB64, payloadB64, "sig"].joined(separator: ".")

        #expect(OpenAIResponsesClient.accountID(fromJWT: jwt) == "acc_12345")
    }

    @Test("returns nil for malformed or claim-less JWTs")
    func malformedJWT() {
        #expect(OpenAIResponsesClient.accountID(fromJWT: "not-a-jwt") == nil)
        #expect(OpenAIResponsesClient.accountID(fromJWT: "only.two") == nil)

        // Well-formed JWT without the auth claim.
        let payloadB64 = "eyJzdWIiOiJub3JlbWFuIn0" // {"sub":"noreman"}
        #expect(OpenAIResponsesClient.accountID(fromJWT: "h.\(payloadB64).s") == nil)
    }

    // MARK: - Anthropic fallback title

    @Test("fallback title falls back to the mode label when there is no question")
    func fallbackTitleNoQuestion() {
        #expect(DirectAnthropicStudyAgent.fallbackTitle(for: .explain, question: nil) == "Explain")
        #expect(DirectAnthropicStudyAgent.fallbackTitle(for: .quiz, question: "   ") == "Quiz")
    }

    @Test("fallback title uses a short question verbatim")
    func fallbackTitleShortQuestion() {
        #expect(
            DirectAnthropicStudyAgent.fallbackTitle(for: .explain, question: "What is attention?")
                == "What is attention?"
        )
    }

    @Test("fallback title truncates a long question with an ellipsis")
    func fallbackTitleLongQuestion() {
        let longQuestion = String(repeating: "Why does this matter for learning? ", count: 4)
        let title = DirectAnthropicStudyAgent.fallbackTitle(for: .explain, question: longQuestion)
        #expect(title.count == 51) // 48 chars + "..."
        #expect(title.hasSuffix("..."))
    }

    // MARK: - Metadata tool definitions

    @Test("metadata tools are named record_metadata")
    func metadataToolNames() {
        #expect(DirectAnthropicStudyAgent.metadataTool().name == "record_metadata")
        #expect(DirectOpenAIStudyAgent.metadataTool().name == "record_metadata")
    }

    // MARK: - Available model lists

    @Test("default models are present in the available model lists")
    func defaultModelsAreListed() {
        #expect(DirectAnthropicStudyAgent.availableModels.contains { $0.id == DirectAnthropicStudyAgent.defaultModel })
        #expect(!DirectAnthropicStudyAgent.availableModels.isEmpty)

        #expect(DirectOpenAIStudyAgent.availableModels.contains { $0.id == DirectOpenAIStudyAgent.defaultModel })
        #expect(!DirectOpenAIStudyAgent.availableModels.isEmpty)
    }
}
