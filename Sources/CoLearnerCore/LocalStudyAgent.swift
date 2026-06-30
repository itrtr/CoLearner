import Foundation

public struct LocalStudyAgent: StudyAgent {
    public init() {}

    public func respond(
        to selection: ReadingSelection,
        mode: StudyMode,
        learnerQuestion: String? = nil
    ) async throws -> StudyResponse {
        guard !selection.isEmpty else {
            throw StudyAgentError.emptySelection
        }

        if let directResponse = StudyAgentDirectResponse.response(
            for: learnerQuestion,
            mode: mode,
            provider: .local,
            sourceExcerpt: selection.excerpt
        ) {
            return directResponse
        }

        let text = selection.text
        let sentences = Self.sentences(in: text)
        let keywords = Self.keywords(in: text)
        let keyIdeas = Self.keyIdeas(from: sentences, keywords: keywords)
        let directAnswer = Self.directAnswer(
            for: learnerQuestion,
            text: text,
            sentences: sentences,
            keywords: keywords
        )

        return StudyResponse(
            mode: mode,
            title: Self.title(
                for: mode,
                sourceTitle: selection.sourceTitle,
                learnerQuestion: learnerQuestion
            ),
            summary: Self.summary(
                for: mode,
                text: text,
                sentences: sentences,
                keywords: keywords,
                learnerQuestion: learnerQuestion,
                directAnswer: directAnswer
            ),
            keyIdeas: keyIdeas,
            examples: Self.examples(
                for: mode,
                question: learnerQuestion,
                keywords: keywords,
                sentences: sentences
            ),
            nextQuestions: Self.questions(
                for: mode,
                question: learnerQuestion,
                keywords: keywords
            ),
            highlights: Self.highlights(from: sentences, fallback: text),
            sourceExcerpt: selection.excerpt
        )
    }

    private static func title(
        for mode: StudyMode,
        sourceTitle: String?,
        learnerQuestion: String?
    ) -> String {
        if let learnerQuestion,
           !learnerQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let cleanedQuestion = learnerQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = cleanedQuestion.count > 48
                ? "\(cleanedQuestion.prefix(48))..."
                : cleanedQuestion
            return "Answer: \(prefix)"
        }

        let baseTitle: String = switch mode {
        case .explain:
            "Plain-language explanation"
        case .simplify:
            "Simplified version"
        case .examples:
            "Examples and analogies"
        case .quiz:
            "Self-check questions"
        }

        guard let sourceTitle, !sourceTitle.isEmpty else {
            return baseTitle
        }

        return "\(baseTitle) from \(sourceTitle)"
    }

    private static func summary(
        for mode: StudyMode,
        text: String,
        sentences: [String],
        keywords: [String],
        learnerQuestion: String?,
        directAnswer: String?
    ) -> String {
        let leadingSentence = sentences.first ?? text
        let mainTerms = keywords.prefix(3).joined(separator: ", ")
        if let learnerQuestion,
           !learnerQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let cleanedQuestion = learnerQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
            let answerSeed = directAnswer
                ?? (mainTerms.isEmpty
                    ? leadingSentence
                    : "The active context is mainly about \(mainTerms). \(leadingSentence)")
            return "Your question: \(cleanedQuestion) Short answer: \(answerSeed)"
        }

        switch mode {
        case .explain:
            if mainTerms.isEmpty {
                return "This passage is mainly saying: \(leadingSentence)"
            }

            return "This passage is mainly about \(mainTerms). In plain terms: \(leadingSentence)"
        case .simplify:
            return "Short version: \(Self.simplified(leadingSentence))"
        case .examples:
            if mainTerms.isEmpty {
                return "The selected idea can be understood by turning the abstract claim into a concrete situation."
            }

            return "The selected idea can be made concrete by looking for where \(mainTerms) show up in real situations."
        case .quiz:
            return "Use the questions below to check whether you can restate the selected idea without looking back at the text."
        }
    }

    private static func keyIdeas(from sentences: [String], keywords: [String]) -> [String] {
        let sentenceIdeas = sentences
            .prefix(3)
            .map { Self.simplified($0) }

        let keywordIdea = keywords.isEmpty
            ? []
            : ["Important terms to track: \(keywords.prefix(5).joined(separator: ", "))."]

        return Array(sentenceIdeas + keywordIdea).filter { !$0.isEmpty }
    }

    private static func highlights(from sentences: [String], fallback text: String) -> [String] {
        let exactSentences = sentences
            .prefix(4)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 20 }

        if !exactSentences.isEmpty {
            return Array(exactSentences)
        }

        let fallbackText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fallbackText.count >= 20 else {
            return []
        }

        return [String(fallbackText.prefix(180))]
    }

    private static func examples(
        for mode: StudyMode,
        question: String?,
        keywords: [String],
        sentences: [String]
    ) -> [String] {
        if Self.isCodeQuestion(question) {
            return [
                "To check for code, switch to full-document context and ask: \"Find any code, pseudocode, algorithms, or implementation steps.\"",
                "If the paper has no code, look for architecture diagrams, tables, algorithms, equations, or implementation best-practice sections instead."
            ]
        }

        let anchor = keywords.first ?? "the core idea"
        let secondAnchor = keywords.dropFirst().first ?? "the surrounding context"
        let concreteExample = "Example: imagine you are teaching \(anchor) to a classmate. Start with what changes, what stays the same, and why it matters."
        let analogy = "Analogy: treat \(anchor) as the signal and \(secondAnchor) as the background that helps explain the signal."
        let application = sentences.dropFirst().first.map { "Application: ask how this sentence would change a decision: \(Self.simplified($0))" }

        let baseExamples = [concreteExample, analogy] + [application].compactMap { $0 }

        switch mode {
        case .examples:
            return baseExamples
        case .quiz:
            return ["Try answering each question in one sentence, then compare it with the original passage."]
        case .explain, .simplify:
            return Array(baseExamples.prefix(2))
        }
    }

    private static func questions(
        for mode: StudyMode,
        question: String?,
        keywords: [String]
    ) -> [String] {
        if Self.isCodeQuestion(question) {
            return [
                "Does another page include pseudocode, an algorithm box, or a table of implementation steps?",
                "Should I search the full document for code-like terms such as API, algorithm, implementation, Kafka, RabbitMQ, or SQS?",
                "Do you want an implementation example based on the paper's concepts?"
            ]
        }

        let anchor = keywords.first ?? "this idea"
        let secondAnchor = keywords.dropFirst().first ?? "the evidence"
        let baseQuestions = [
            "What problem is \(anchor) trying to solve or describe?",
            "How does \(secondAnchor) support the main claim?",
            "What would be a simple counterexample or limitation?"
        ]

        switch mode {
        case .quiz:
            return baseQuestions + [
                "Can you explain the passage in two sentences without using the original wording?"
            ]
        case .examples:
            return [
                "Where have you seen \(anchor) outside this text?",
                "What everyday scenario would make the same relationship visible?"
            ]
        case .explain, .simplify:
            return baseQuestions
        }
    }

    private static func directAnswer(
        for learnerQuestion: String?,
        text: String,
        sentences: [String],
        keywords: [String]
    ) -> String? {
        guard let learnerQuestion,
              !learnerQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if isCodeQuestion(learnerQuestion) {
            return codeAnswer(in: text, keywords: keywords)
        }

        let questionTerms = Set(Self.keywords(in: learnerQuestion))
        let bestSentence = sentences.max { left, right in
            score(sentence: left, questionTerms: questionTerms) < score(sentence: right, questionTerms: questionTerms)
        }

        guard let bestSentence,
              score(sentence: bestSentence, questionTerms: questionTerms) > 0 else {
            let mainTerms = keywords.prefix(4).joined(separator: ", ")
            return mainTerms.isEmpty
                ? "I do not see a direct answer in the active context. Try switching to Page, Section, or Document context."
                : "I do not see a direct answer in the active context. The visible material is mostly about \(mainTerms)."
        }

        return simplified(bestSentence)
    }

    private static func isCodeQuestion(_ question: String?) -> Bool {
        guard let question else {
            return false
        }

        let normalizedQuestion = question.lowercased()
        return [
            "code",
            "pseudocode",
            "implementation",
            "algorithm",
            "api",
            "sample",
            "example code"
        ].contains { normalizedQuestion.contains($0) }
    }

    private static func codeAnswer(in text: String, keywords: [String]) -> String {
        let codeSignals = [
            "```", "func ", "class ", "struct ", "import ", "public ", "private ",
            "let ", "var ", "def ", "return ", "{", "};",
            "algorithm", "pseudocode", "procedure"
        ]
        let normalizedText = text.lowercased()
        let hasCodeLikeContent = codeSignals.contains { normalizedText.contains($0) }

        if hasCodeLikeContent {
            return "Yes, I see code-like or algorithmic material in the active context. Review the highlighted/key idea sections and switch to full-document context if you want me to find every instance."
        }

        let topic = keywords.prefix(5).joined(separator: ", ")
        if topic.isEmpty {
            return "No code or pseudocode is visible in the active context."
        }

        return "No code or pseudocode is visible in the active context. This part is prose about \(topic). Switch to Document context if you want me to search the whole PDF."
    }

    private static func score(sentence: String, questionTerms: Set<String>) -> Int {
        let sentenceTerms = Set(keywords(in: sentence))
        return questionTerms.intersection(sentenceTerms).count
    }

    private static func simplified(_ sentence: String) -> String {
        let replacements = [
            "utilize": "use",
            "approximately": "about",
            "therefore": "so",
            "demonstrates": "shows",
            "indicates": "shows",
            "subsequent": "later",
            "prior": "earlier",
            "methodology": "method",
            "objective": "goal"
        ]

        return replacements.reduce(sentence) { current, replacement in
            current.replacingOccurrences(
                of: replacement.key,
                with: replacement.value,
                options: [.caseInsensitive, .diacriticInsensitive]
            )
        }
    }

    private static func sentences(in text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map {
                $0
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
    }

    private static func keywords(in text: String) -> [String] {
        let stopWords: Set<String> = [
            "about", "after", "again", "against", "because", "before", "between",
            "could", "during", "first", "from", "their", "there", "these",
            "those", "through", "under", "using", "where", "which", "while",
            "would", "with", "without", "within"
        ]
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in
                word.count > 4 && !stopWords.contains(word)
            }

        let frequencies = words.reduce([String: Int]()) { current, word in
            var next = current
            next[word, default: 0] += 1
            return next
        }

        return frequencies
            .sorted { left, right in
                if left.value == right.value {
                    return left.key < right.key
                }

                return left.value > right.value
            }
            .map(\.key)
    }
}
