import Foundation

public struct StudyResponsePayload: Codable, Equatable, Sendable {
    public let title: String
    public let summary: String
    public let keyIdeas: [String]
    public let examples: [String]
    public let nextQuestions: [String]
    public let highlights: [String]?
    public let answerMarkdown: String?

    public init(
        title: String,
        summary: String,
        keyIdeas: [String],
        examples: [String],
        nextQuestions: [String],
        highlights: [String]? = nil,
        answerMarkdown: String? = nil
    ) {
        self.title = title
        self.summary = summary
        self.keyIdeas = keyIdeas
        self.examples = examples
        self.nextQuestions = nextQuestions
        self.highlights = highlights
        self.answerMarkdown = answerMarkdown
    }

    public func studyResponse(mode: StudyMode, selection: ReadingSelection) -> StudyResponse {
        StudyResponse(
            mode: mode,
            title: title,
            summary: summary,
            keyIdeas: keyIdeas,
            examples: examples,
            nextQuestions: nextQuestions,
            highlights: highlights ?? [],
            answerMarkdown: answerMarkdown,
            sourceExcerpt: selection.excerpt
        )
    }
}

public enum StudyResponsePayloadParser {
    public static func parse(_ output: String) throws -> StudyResponsePayload {
        for candidate in candidates(from: output) {
            if let payload = decodePayload(from: candidate) {
                return payload
            }
        }

        throw StudyAgentError.invalidProviderResponse("The selected agent did not return a usable study response.")
    }

    private static func candidates(from output: String) -> [String] {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = [trimmedOutput]

        for line in output.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else {
                continue
            }

            candidates.append(trimmedLine)

            guard let data = trimmedLine.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let structuredOutput = object["structured_output"] as? [String: Any],
               let structuredData = try? JSONSerialization.data(withJSONObject: structuredOutput),
               let structuredText = String(data: structuredData, encoding: .utf8) {
                candidates.append(structuredText)
            }

            if let result = object["result"] as? String {
                candidates.append(result)
            }

            if let item = object["item"] as? [String: Any],
               item["type"] as? String == "agent_message",
               let text = item["text"] as? String {
                candidates.append(text)
            }

            candidates.append(contentsOf: nestedCandidates(in: object))
        }

        candidates.append(contentsOf: fencedJSONBlocks(in: output))
        return candidates
    }

    private static func decodePayload(from text: String) -> StudyResponsePayload? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        for json in [trimmedText] + fencedJSONBlocks(in: trimmedText) + objectJSONFragments(in: trimmedText) {
            guard let data = json.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(StudyResponsePayload.self, from: data) else {
                continue
            }

            return payload
        }

        return nil
    }

    private static func fencedJSONBlocks(in text: String) -> [String] {
        let pattern = #"```(?:json)?\s*([\s\S]*?)\s*```"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let captureRange = Range(match.range(at: 1), in: text) else {
                return nil
            }

            return String(text[captureRange])
        }
    }

    private static func objectJSONFragments(in text: String) -> [String] {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else {
            return []
        }

        return [String(text[start...end])]
    }

    private static func nestedCandidates(in value: Any) -> [String] {
        if let string = value as? String {
            return [string]
        }

        if let dictionary = value as? [String: Any] {
            let serialized = (try? JSONSerialization.data(withJSONObject: dictionary))
                .flatMap { String(data: $0, encoding: .utf8) }

            return [serialized].compactMap { $0 } + dictionary.values.flatMap { nestedCandidates(in: $0) }
        }

        if let array = value as? [Any] {
            return array.flatMap { nestedCandidates(in: $0) }
        }

        return []
    }
}
