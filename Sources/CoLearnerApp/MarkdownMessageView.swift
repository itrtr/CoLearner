import SwiftUI

struct MarkdownMessageView: View {
    let text: String
    let baseFontSize: CGFloat
    let fontChoice: CLChatFontChoice
    let foregroundColor: Color
    var lineSpacing: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .paragraph(markdown):
                    paragraph(markdown)
                case let .heading(level, markdown):
                    heading(markdown, level: level)
                case let .bullets(items):
                    bulletList(items)
                case let .code(language, code):
                    codeBlock(language: language, code: code)
                case let .blockquote(lines):
                    blockquote(lines)
                case .horizontalRule:
                    horizontalRule
                case let .table(table):
                    tableView(table)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.blocks(from: text)
    }

    private func paragraph(_ markdown: String) -> some View {
        Text(attributedString(from: markdown))
            .font(fontChoice.swiftUIFont(size: baseFontSize))
            .foregroundStyle(foregroundColor)
            .lineSpacing(lineSpacing)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func heading(_ markdown: String, level: Int) -> some View {
        Text(attributedString(from: markdown))
            .font(fontChoice.swiftUIFont(size: headingFontSize(for: level), weight: .semibold))
            .foregroundStyle(CLColor.ink)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, level == 2 ? 2 : 0)
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(fontChoice.swiftUIFont(size: baseFontSize, weight: .semibold))
                        .foregroundStyle(CLColor.accent)
                        .padding(.top, 1)

                    Text(attributedString(from: item))
                        .font(fontChoice.swiftUIFont(size: baseFontSize))
                        .foregroundStyle(foregroundColor)
                        .lineSpacing(lineSpacing)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func blockquote(_ lines: [String]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(CLColor.accent.opacity(0.55))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(attributedString(from: line))
                        .font(fontChoice.swiftUIFont(size: baseFontSize))
                        .foregroundStyle(foregroundColor.opacity(0.85))
                        .lineSpacing(lineSpacing)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, 2)
    }

    private var horizontalRule: some View {
        Rectangle()
            .fill(CLColor.border2)
            .frame(height: 1)
            .padding(.vertical, 2)
    }

    private func tableView(_ table: MarkdownTable) -> some View {
        let columnCount = max(table.header.count, table.rows.map(\.count).max() ?? 0)

        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                tableRow(cells: padded(table.header, to: columnCount), isHeader: true, alignments: table.alignments)
                Rectangle()
                    .fill(CLColor.border2)
                    .frame(height: 1)

                ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                    tableRow(
                        cells: padded(row, to: columnCount),
                        isHeader: false,
                        alignments: table.alignments
                    )
                    .background(index.isMultiple(of: 2) ? Color.clear : CLColor.surface.opacity(0.4))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(CLColor.border2, lineWidth: 0.5)
            }
        }
    }

    private func tableRow(cells: [String], isHeader: Bool, alignments: [MarkdownTableAlignment]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                let alignment = index < alignments.count ? alignments[index] : .leading
                Text(attributedString(from: cell))
                    .font(fontChoice.swiftUIFont(size: baseFontSize, weight: isHeader ? .semibold : .regular))
                    .foregroundStyle(isHeader ? CLColor.ink : foregroundColor)
                    .lineSpacing(lineSpacing)
                    .textSelection(.enabled)
                    .frame(minWidth: 80, alignment: alignment.swiftUIAlignment)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)

                if index < cells.count - 1 {
                    Rectangle()
                        .fill(CLColor.border2.opacity(0.6))
                        .frame(width: 0.5)
                }
            }
        }
    }

    private func padded(_ cells: [String], to count: Int) -> [String] {
        guard cells.count < count else {
            return cells
        }
        return cells + Array(repeating: "", count: count - cells.count)
    }

    private func codeBlock(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let language, !language.isEmpty {
                Text(language.uppercased())
                    .font(.system(size: max(baseFontSize - 4, 10), weight: .semibold, design: .monospaced))
                    .foregroundStyle(CLColor.ink3)
            }

            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(size: max(baseFontSize - 1, 11), design: .monospaced))
                    .foregroundStyle(foregroundColor)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CLColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(CLColor.border2, lineWidth: 0.5)
        }
    }

    private func attributedString(from markdown: String) -> AttributedString {
        return (try? AttributedString(markdown: markdown))
            ?? AttributedString(markdown)
    }

    private func headingFontSize(for level: Int) -> CGFloat {
        switch level {
        case 1:
            baseFontSize + 4
        case 2:
            baseFontSize + 2
        default:
            baseFontSize + 1
        }
    }
}

private enum MarkdownBlock {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bullets([String])
    case code(language: String?, code: String)
    case blockquote([String])
    case horizontalRule
    case table(MarkdownTable)
}

enum MarkdownTableAlignment {
    case leading
    case center
    case trailing

    var swiftUIAlignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

struct MarkdownTable {
    let header: [String]
    let alignments: [MarkdownTableAlignment]
    let rows: [[String]]
}

private enum MarkdownBlockParser {
    static func blocks(from text: String) -> [MarkdownBlock] {
        var blocks = [MarkdownBlock]()
        var paragraphLines = [String]()
        var bulletItems = [String]()
        var quoteLines = [String]()
        var codeLines = [String]()
        var codeLanguage: String?
        var isInCodeBlock = false

        let rawLines = text.components(separatedBy: .newlines)
        var index = 0
        while index < rawLines.count {
            let line = rawLines[index]

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if isInCodeBlock {
                    blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    codeLanguage = nil
                    isInCodeBlock = false
                } else {
                    flushPending(
                        paragraphLines: &paragraphLines,
                        bulletItems: &bulletItems,
                        quoteLines: &quoteLines,
                        blocks: &blocks
                    )
                    codeLanguage = language(fromFenceLine: line)
                    isInCodeBlock = true
                }
                index += 1
                continue
            }

            if isInCodeBlock {
                codeLines.append(line)
                index += 1
                continue
            }

            if let consumed = consumeTable(starting: index, in: rawLines) {
                flushPending(
                    paragraphLines: &paragraphLines,
                    bulletItems: &bulletItems,
                    quoteLines: &quoteLines,
                    blocks: &blocks
                )
                blocks.append(.table(consumed.table))
                index = consumed.endIndex
                continue
            }

            appendMarkdownLine(
                line,
                paragraphLines: &paragraphLines,
                bulletItems: &bulletItems,
                quoteLines: &quoteLines,
                blocks: &blocks
            )
            index += 1
        }

        if isInCodeBlock {
            blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        }
        flushPending(
            paragraphLines: &paragraphLines,
            bulletItems: &bulletItems,
            quoteLines: &quoteLines,
            blocks: &blocks
        )

        return blocks.isEmpty ? [.paragraph(text)] : blocks
    }

    private static func appendMarkdownLine(
        _ line: String,
        paragraphLines: inout [String],
        bulletItems: inout [String],
        quoteLines: inout [String],
        blocks: inout [MarkdownBlock]
    ) {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        if trimmedLine.isEmpty {
            flushPending(
                paragraphLines: &paragraphLines,
                bulletItems: &bulletItems,
                quoteLines: &quoteLines,
                blocks: &blocks
            )
            return
        }

        if isHorizontalRule(trimmedLine) {
            flushPending(
                paragraphLines: &paragraphLines,
                bulletItems: &bulletItems,
                quoteLines: &quoteLines,
                blocks: &blocks
            )
            blocks.append(.horizontalRule)
            return
        }

        if let heading = heading(from: trimmedLine) {
            flushPending(
                paragraphLines: &paragraphLines,
                bulletItems: &bulletItems,
                quoteLines: &quoteLines,
                blocks: &blocks
            )
            blocks.append(.heading(level: heading.level, text: heading.text))
            return
        }

        if let quote = blockquote(from: trimmedLine) {
            appendParagraph(from: &paragraphLines, to: &blocks)
            appendBullets(from: &bulletItems, to: &blocks)
            quoteLines.append(quote)
            return
        }

        if let bullet = bullet(from: trimmedLine) {
            appendParagraph(from: &paragraphLines, to: &blocks)
            appendQuotes(from: &quoteLines, to: &blocks)
            bulletItems.append(bullet)
            return
        }

        appendBullets(from: &bulletItems, to: &blocks)
        appendQuotes(from: &quoteLines, to: &blocks)
        paragraphLines.append(line)
    }

    private static func flushPending(
        paragraphLines: inout [String],
        bulletItems: inout [String],
        quoteLines: inout [String],
        blocks: inout [MarkdownBlock]
    ) {
        appendParagraph(from: &paragraphLines, to: &blocks)
        appendBullets(from: &bulletItems, to: &blocks)
        appendQuotes(from: &quoteLines, to: &blocks)
    }

    private static func appendParagraph(
        from lines: inout [String],
        to blocks: inout [MarkdownBlock]
    ) {
        let markdown = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        lines.removeAll()

        guard !markdown.isEmpty else {
            return
        }

        blocks.append(.paragraph(markdown))
    }

    private static func appendBullets(
        from items: inout [String],
        to blocks: inout [MarkdownBlock]
    ) {
        guard !items.isEmpty else {
            return
        }

        blocks.append(.bullets(items))
        items.removeAll()
    }

    private static func appendQuotes(
        from lines: inout [String],
        to blocks: inout [MarkdownBlock]
    ) {
        guard !lines.isEmpty else {
            return
        }

        blocks.append(.blockquote(lines))
        lines.removeAll()
    }

    private static func blockquote(from line: String) -> String? {
        guard line.hasPrefix(">") else {
            return nil
        }
        let dropped = line.dropFirst()
        if dropped.first == " " {
            return String(dropped.dropFirst())
        }
        return String(dropped)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        guard line.count >= 3 else {
            return false
        }
        let allowed: Set<Character> = ["-", "*", "_"]
        guard let first = line.first, allowed.contains(first) else {
            return false
        }
        return line.allSatisfy { $0 == first }
    }

    private static func consumeTable(starting startIndex: Int, in lines: [String]) -> (table: MarkdownTable, endIndex: Int)? {
        guard startIndex + 1 < lines.count else {
            return nil
        }

        let headerLine = lines[startIndex]
        let separatorLine = lines[startIndex + 1]

        guard let header = parseTableRow(headerLine), !header.isEmpty else {
            return nil
        }

        guard let alignments = parseTableSeparator(separatorLine), alignments.count == header.count else {
            return nil
        }

        var rows = [[String]]()
        var cursor = startIndex + 2
        while cursor < lines.count {
            guard let row = parseTableRow(lines[cursor]) else {
                break
            }
            rows.append(row)
            cursor += 1
        }

        let table = MarkdownTable(header: header, alignments: alignments, rows: rows)
        return (table, cursor)
    }

    private static func parseTableRow(_ rawLine: String) -> [String]? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else {
            return nil
        }
        var working = trimmed
        if working.hasPrefix("|") {
            working.removeFirst()
        }
        if working.hasSuffix("|") {
            working.removeLast()
        }
        let cells = working
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return cells.isEmpty ? nil : cells
    }

    private static func parseTableSeparator(_ rawLine: String) -> [MarkdownTableAlignment]? {
        guard let cells = parseTableRow(rawLine) else {
            return nil
        }

        var alignments = [MarkdownTableAlignment]()
        for cell in cells {
            let stripped = cell.replacingOccurrences(of: " ", with: "")
            guard !stripped.isEmpty,
                  stripped.allSatisfy({ $0 == "-" || $0 == ":" }),
                  stripped.contains("-") else {
                return nil
            }

            let startsWithColon = stripped.first == ":"
            let endsWithColon = stripped.last == ":"
            switch (startsWithColon, endsWithColon) {
            case (true, true): alignments.append(.center)
            case (false, true): alignments.append(.trailing)
            default: alignments.append(.leading)
            }
        }
        return alignments
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else {
            return nil
        }

        let level = line.prefix(while: { $0 == "#" }).count
        guard level <= 3 else {
            return nil
        }

        let remainder = line.dropFirst(level)
        guard remainder.first == " " else {
            return nil
        }

        let text = remainder.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (level, text)
    }

    private static func bullet(from line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return String(line.dropFirst(2))
        }

        guard let firstCharacter = line.first,
              firstCharacter.isNumber,
              let dotIndex = line.firstIndex(of: ".") else {
            return nil
        }

        let numberPrefix = line[..<dotIndex]
        let afterDot = line[line.index(after: dotIndex)...]
        guard numberPrefix.allSatisfy(\.isNumber),
              afterDot.first == " " else {
            return nil
        }

        return String(afterDot.dropFirst())
    }

    private static func language(fromFenceLine line: String) -> String? {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        let language = trimmedLine
            .dropFirst(3)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return language.isEmpty ? nil : language
    }
}
