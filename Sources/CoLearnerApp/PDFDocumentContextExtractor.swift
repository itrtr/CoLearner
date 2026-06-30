import PDFKit

enum PDFDocumentContextExtractor {
    static func mapItems(from document: PDFDocument) -> [DocumentMapItem] {
        if let outlineRoot = document.outlineRoot {
            let outlineItems = outlineChildren(
                of: outlineRoot,
                document: document,
                level: 0
            )

            if !outlineItems.isEmpty {
                return outlineItems
            }
        }

        return (0..<document.pageCount).map { pageIndex in
            DocumentMapItem(
                id: "page-\(pageIndex)",
                title: "Page \(pageIndex + 1)",
                pageIndex: pageIndex,
                level: 0
            )
        }
    }

    static func nearestMapItem(
        in items: [DocumentMapItem],
        pageIndex: Int
    ) -> DocumentMapItem? {
        items
            .filter { $0.pageIndex <= pageIndex }
            .sorted { left, right in
                if left.pageIndex == right.pageIndex {
                    return left.level < right.level
                }

                return left.pageIndex < right.pageIndex
            }
            .last
    }

    static func textForPage(in document: PDFDocument, pageIndex: Int) -> String {
        guard let page = document.page(at: pageIndex) else {
            return ""
        }

        return normalized(page.string ?? "")
    }

    static func fullText(in document: PDFDocument) -> String {
        let pageTexts = (0..<document.pageCount).map { pageIndex in
            textForPage(in: document, pageIndex: pageIndex)
        }

        return normalized(pageTexts.joined(separator: "\n\n"))
    }

    static func contextIndex(
        from document: PDFDocument,
        mapItems: [DocumentMapItem]
    ) -> DocumentContextIndex {
        let outlineItems = mapItems.filter { !$0.title.hasPrefix("Page ") }
        let chunks: [DocumentContextChunk]

        if !outlineItems.isEmpty {
            chunks = outlineItems.compactMap { item in
                let text = textForSection(in: document, item: item, mapItems: mapItems)
                guard !text.isEmpty else {
                    return nil
                }

                return DocumentContextChunk(
                    id: item.id,
                    title: item.title,
                    pageIndex: item.pageIndex,
                    text: text
                )
            }
        } else {
            chunks = (0..<document.pageCount).compactMap { pageIndex in
                let text = textForPage(in: document, pageIndex: pageIndex)
                guard !text.isEmpty else {
                    return nil
                }

                return DocumentContextChunk(
                    id: "page-\(pageIndex)",
                    title: "Page \(pageIndex + 1)",
                    pageIndex: pageIndex,
                    text: text
                )
            }
        }

        return DocumentContextIndex(chunks: chunks)
    }

    static func textForSection(
        in document: PDFDocument,
        item: DocumentMapItem,
        mapItems: [DocumentMapItem]
    ) -> String {
        let endPage = nextSectionStartPage(after: item, in: mapItems)
            .map { max(item.pageIndex, $0 - 1) }
            ?? max(item.pageIndex, document.pageCount - 1)

        let pageTexts = (item.pageIndex...endPage).map { pageIndex in
            textForPage(in: document, pageIndex: pageIndex)
        }

        return normalized(pageTexts.joined(separator: "\n\n"))
    }

    private static func outlineChildren(
        of outline: PDFOutline,
        document: PDFDocument,
        level: Int
    ) -> [DocumentMapItem] {
        (0..<outline.numberOfChildren).flatMap { childIndex -> [DocumentMapItem] in
            guard let child = outline.child(at: childIndex) else {
                return []
            }

            let title = child.label?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty ?? "Untitled"
            let pageIndex = pageIndex(for: child, document: document) ?? 0
            let item = DocumentMapItem(
                id: "outline-\(level)-\(childIndex)-\(pageIndex)-\(title)",
                title: title,
                pageIndex: pageIndex,
                level: level
            )

            return [item] + outlineChildren(
                of: child,
                document: document,
                level: level + 1
            )
        }
    }

    private static func pageIndex(
        for outline: PDFOutline,
        document: PDFDocument
    ) -> Int? {
        if let page = outline.destination?.page {
            return document.index(for: page)
        }

        if let goToAction = outline.action as? PDFActionGoTo,
           let page = goToAction.destination.page {
            return document.index(for: page)
        }

        return nil
    }

    private static func nextSectionStartPage(
        after item: DocumentMapItem,
        in mapItems: [DocumentMapItem]
    ) -> Int? {
        guard let currentIndex = mapItems.firstIndex(of: item) else {
            return nil
        }

        return mapItems
            .dropFirst(currentIndex + 1)
            .first { nextItem in
                nextItem.level <= item.level && nextItem.pageIndex > item.pageIndex
            }?
            .pageIndex
    }

    private static func normalized(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
