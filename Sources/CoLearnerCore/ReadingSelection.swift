import Foundation

public struct ReadingSelection: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let text: String
    public let sourceTitle: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        sourceTitle: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = Self.normalized(text)
        self.sourceTitle = sourceTitle
        self.createdAt = createdAt
    }

    public var isEmpty: Bool {
        text.isEmpty
    }

    public var excerpt: String {
        let maximumLength = 360
        guard text.count > maximumLength else {
            return text
        }

        let endIndex = text.index(text.startIndex, offsetBy: maximumLength)
        return "\(text[..<endIndex])..."
    }

    private static func normalized(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
