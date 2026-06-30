import CoreGraphics
import Foundation

enum ReaderMode: String, CaseIterable, Identifiable {
    case selfStudy
    case companion

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .selfStudy:
            "Self"
        case .companion:
            "Companion"
        }
    }

    var systemImage: String {
        switch self {
        case .selfStudy:
            "book"
        case .companion:
            "sparkles"
        }
    }
}

enum CompanionTab: String, CaseIterable, Identifiable {
    case chat
    case map
    case notes

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .chat:
            "Chat"
        case .map:
            "Map"
        case .notes:
            "Notes"
        }
    }
}

enum ChatContextScope: String, CaseIterable, Identifiable {
    case selectedPassage
    case currentPage
    case currentSection
    case fullDocument

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .selectedPassage:
            "Selection"
        case .currentPage:
            "Page"
        case .currentSection:
            "Section"
        case .fullDocument:
            "Document"
        }
    }

    var systemImage: String {
        switch self {
        case .selectedPassage:
            "text.viewfinder"
        case .currentPage:
            "doc.text"
        case .currentSection:
            "list.bullet.rectangle"
        case .fullDocument:
            "doc.on.doc"
        }
    }
}

struct ChatMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String
    let contextTitle: String?
    let createdAt: Date
    var isPending: Bool
    var isError: Bool

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        contextTitle: String? = nil,
        createdAt: Date = Date(),
        isPending: Bool = false,
        isError: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.contextTitle = contextTitle
        self.createdAt = createdAt
        self.isPending = isPending
        self.isError = isError
    }
}

struct DocumentMapItem: Identifiable, Equatable {
    let id: String
    let title: String
    let pageIndex: Int
    let level: Int

    var pageLabel: String {
        "p. \(pageIndex + 1)"
    }
}

struct PDFNavigationTarget: Equatable {
    let id = UUID()
    let pageIndex: Int
}

struct PDFSearchNavigationTarget: Equatable {
    let id = UUID()
    let snippet: String
    let pageIndex: Int
}

struct PDFHighlightRequest: Equatable {
    let id = UUID()
    let snippets: [String]
}

enum UserHighlightColor: String, CaseIterable, Identifiable, Codable {
    case yellow
    case green
    case blue
    case pink
    case orange

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .yellow:
            "Yellow"
        case .green:
            "Green"
        case .blue:
            "Blue"
        case .pink:
            "Pink"
        case .orange:
            "Orange"
        }
    }

    var hexValue: UInt32 {
        switch self {
        case .yellow:
            0xF7D154
        case .green:
            0x76C893
        case .blue:
            0x7DB7F0
        case .pink:
            0xE98AB0
        case .orange:
            0xF4A261
        }
    }
}

struct PDFUserHighlightRequest: Equatable {
    let id = UUID()
    let color: UserHighlightColor
}

enum PDFLayoutMode: String, CaseIterable, Identifiable {
    case continuous
    case singlePage
    case twoUp

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .continuous:
            "Continuous"
        case .singlePage:
            "Single"
        case .twoUp:
            "Two-up"
        }
    }

    var systemImage: String {
        switch self {
        case .continuous:
            "rectangle.stack"
        case .singlePage:
            "doc"
        case .twoUp:
            "square.split.2x1"
        }
    }
}

struct PDFDisplayState: Equatable {
    var layoutMode: PDFLayoutMode = .continuous
    var scaleFactor: CGFloat = 1
    var fitsToWidth = true
}

struct ResolvedChatContext: Equatable {
    let title: String
    let text: String
}

struct DocumentSearchResult: Identifiable, Equatable {
    let id: UUID
    let query: String
    let excerpt: String
    let pageIndex: Int

    init(
        id: UUID = UUID(),
        query: String,
        excerpt: String,
        pageIndex: Int
    ) {
        self.id = id
        self.query = query
        self.excerpt = excerpt
        self.pageIndex = pageIndex
    }
}

struct DocumentContextChunk: Identifiable, Equatable {
    let id: String
    let title: String
    let pageIndex: Int
    let text: String

    var normalizedTerms: Set<String> {
        Set(Self.terms(in: "\(title) \(text)"))
    }

    static func terms(in text: String) -> [String] {
        let stopWords: Set<String> = [
            "about", "after", "again", "because", "before", "between", "could",
            "during", "first", "from", "their", "there", "these", "those",
            "through", "under", "using", "where", "which", "while", "would",
            "with", "without", "within"
        ]

        return text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !stopWords.contains($0) }
    }
}

struct DocumentContextIndex: Equatable {
    let chunks: [DocumentContextChunk]

    static let empty = DocumentContextIndex(chunks: [])

    func relevantContext(
        for question: String,
        maxCharacters: Int
    ) -> ResolvedChatContext? {
        let queryTerms = Set(DocumentContextChunk.terms(in: question))
        let rankedChunks: [(chunk: DocumentContextChunk, score: Int)] = chunks
            .map { chunk in
                let score = queryTerms.intersection(chunk.normalizedTerms).reduce(0) { count, _ in
                    count + 1
                }
                return (chunk: chunk, score: score)
            }
            .sorted { left, right in
                if left.score == right.score {
                    return left.chunk.pageIndex < right.chunk.pageIndex
                }

                return left.score > right.score
            }

        let selectedChunks = rankedChunks
            .filter { $0.score > 0 }
            .prefix(8)
            .map { $0.chunk }

        let fallbackChunks = chunks.prefix(6)
        let contextChunks = selectedChunks.isEmpty ? Array(fallbackChunks) : Array(selectedChunks)
        guard !contextChunks.isEmpty else {
            return nil
        }

        var usedCharacters = 0
        let sections = contextChunks.compactMap { chunk -> String? in
            guard usedCharacters < maxCharacters else {
                return nil
            }

            let remaining = maxCharacters - usedCharacters
            let text = chunk.text.count > remaining
                ? String(chunk.text.prefix(remaining))
                : chunk.text
            usedCharacters += text.count

            return """
            [\(chunk.title), p. \(chunk.pageIndex + 1)]
            \(text)
            """
        }

        return ResolvedChatContext(
            title: selectedChunks.isEmpty ? "Document overview" : "Relevant document context",
            text: sections.joined(separator: "\n\n")
        )
    }
}

struct LearningNote: Identifiable, Equatable, Codable {
    let id: UUID
    let title: String
    let body: String
    let sourceExcerpt: String?
    let sourceTitle: String
    let sourcePageIndex: Int?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        sourceExcerpt: String?,
        sourceTitle: String,
        sourcePageIndex: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.sourceExcerpt = sourceExcerpt
        self.sourceTitle = sourceTitle
        self.sourcePageIndex = sourcePageIndex
        self.createdAt = createdAt
    }
}
