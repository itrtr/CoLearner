import AppKit
import PDFKit
import SwiftUI

struct PDFReaderView: NSViewRepresentable {
    let document: PDFDocument?
    let navigationTarget: PDFNavigationTarget?
    let searchNavigationTarget: PDFSearchNavigationTarget?
    let highlightRequest: PDFHighlightRequest?
    let userHighlightRequest: PDFUserHighlightRequest?
    let displayState: PDFDisplayState
    let onSelectionChange: (String) -> Void
    let onPageChange: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSelectionChange: onSelectionChange,
            onPageChange: onPageChange
        )
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
                pdfView.backgroundColor = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor.clHex(isDark ? 0x0E0C0A : 0xECE5D6)
        }
        pdfView.displayDirection = .vertical
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = true
        pdfView.document = document

        context.coordinator.pdfView = pdfView
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }

        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onPageChange = onPageChange
        context.coordinator.applyDisplayState(displayState, to: nsView)

        if let navigationTarget,
           navigationTarget.id != context.coordinator.lastNavigationTargetID,
           let page = nsView.document?.page(at: navigationTarget.pageIndex) {
            context.coordinator.lastNavigationTargetID = navigationTarget.id
            nsView.go(to: page)
        }

        if let searchNavigationTarget,
           searchNavigationTarget.id != context.coordinator.lastSearchNavigationTargetID {
            context.coordinator.lastSearchNavigationTargetID = searchNavigationTarget.id
            context.coordinator.navigateToSearchResult(searchNavigationTarget, in: nsView)
        }

        if let highlightRequest,
           highlightRequest.id != context.coordinator.lastHighlightRequestID {
            context.coordinator.lastHighlightRequestID = highlightRequest.id
            context.coordinator.applyHighlights(
                snippets: highlightRequest.snippets,
                in: nsView
            )
        }

        if let userHighlightRequest,
           userHighlightRequest.id != context.coordinator.lastUserHighlightRequestID {
            context.coordinator.lastUserHighlightRequestID = userHighlightRequest.id
            context.coordinator.applyUserHighlight(color: userHighlightRequest.color, in: nsView)
        }
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: .PDFViewSelectionChanged,
            object: nsView
        )
        NotificationCenter.default.removeObserver(
            coordinator,
            name: .PDFViewPageChanged,
            object: nsView
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSelectionChange: (String) -> Void
        var onPageChange: (Int) -> Void
        weak var pdfView: PDFView?
        var lastNavigationTargetID: UUID?
        var lastSearchNavigationTargetID: UUID?
                var lastHighlightRequestID: UUID?
        var lastUserHighlightRequestID: UUID?
        /// When true, selection-change notifications triggered by our own programmatic
        /// `setCurrentSelection`/restore calls are ignored so they don't clobber the
        /// learner's real selection or flip the chat context scope.
        var isProgrammaticSelectionChange = false

        init(
            onSelectionChange: @escaping (String) -> Void,
            onPageChange: @escaping (Int) -> Void
        ) {
            self.onSelectionChange = onSelectionChange
            self.onPageChange = onPageChange
        }

                @objc func selectionChanged(_ notification: Notification) {
            guard !isProgrammaticSelectionChange else { return }

            let selectedText = pdfView?
                .currentSelection?
                .string?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            onSelectionChange(selectedText)
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView,
                  let page = pdfView.currentPage,
                  let document = pdfView.document else {
                return
            }

            let pageIndex = document.index(for: page)
            guard pageIndex >= 0 else {
                return
            }

            onPageChange(pageIndex)
        }

        func applyHighlights(snippets: [String], in pdfView: PDFView) {
            guard let document = pdfView.document else {
                return
            }

            removeExistingCoLearnerHighlights(from: document)

            guard !snippets.isEmpty else {
                return
            }

                        let preservedSelection = pdfView.currentSelection
            isProgrammaticSelectionChange = true
            defer { isProgrammaticSelectionChange = false }

                        for (snippetIndex, snippet) in snippets.enumerated() {
                let matches = matches(for: snippet, in: document)
                for (matchIndex, match) in matches.prefix(4).enumerated() {
                    // Cascade: each highlight starts a little later so they sweep in sequence.
                    let delay = TimeInterval(snippetIndex) * 0.12 + TimeInterval(matchIndex) * 0.06
                    applySquigglyHighlight(
                        for: match,
                        contents: Self.paperHighlightContents,
                        in: pdfView,
                        delay: delay
                    )
                }
            }

            // Restore the learner's text selection instead of clearing it — applying AI
            // highlights should not destroy an active selection the learner is working with.
            pdfView.currentSelection = preservedSelection
            pdfView.needsDisplay = true
            pdfView.documentView?.needsDisplay = true
            pdfView.layoutDocumentView()
        }

        func applyDisplayState(_ displayState: PDFDisplayState, to pdfView: PDFView) {
            switch displayState.layoutMode {
            case .continuous:
                pdfView.displayMode = .singlePageContinuous
            case .singlePage:
                pdfView.displayMode = .singlePage
            case .twoUp:
                pdfView.displayMode = .twoUpContinuous
            }

            if displayState.fitsToWidth {
                pdfView.autoScales = true
            } else {
                pdfView.autoScales = false
                pdfView.scaleFactor = displayState.scaleFactor
            }
        }

        func navigateToSearchResult(_ target: PDFSearchNavigationTarget, in pdfView: PDFView) {
            guard let document = pdfView.document,
                  let page = document.page(at: target.pageIndex) else {
                return
            }

            pdfView.go(to: page)

            let matchesOnPage = document
                .findString(target.snippet, withOptions: [.caseInsensitive, .diacriticInsensitive])
                .filter { selection in
                    selection.pages.contains(page)
                }

            guard let selection = matchesOnPage.first else {
                return
            }

                        isProgrammaticSelectionChange = true
            defer { isProgrammaticSelectionChange = false }
            pdfView.setCurrentSelection(selection, animate: true)
            pdfView.scrollSelectionToVisible(nil)
        }

        func applyUserHighlight(color: UserHighlightColor, in pdfView: PDFView) {
            guard let selection = pdfView.currentSelection,
                  !(selection.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else {
                return
            }

            applyHighlight(
                for: selection,
                color: NSColor.clHex(color.hexValue, alpha: 0.46),
                contents: "\(Self.userHighlightContentsPrefix): \(color.rawValue)"
            )

            pdfView.needsDisplay = true
            pdfView.documentView?.needsDisplay = true
        }

        private func matches(for snippet: String, in document: PDFDocument) -> [PDFSelection] {
            // Normalize: collapse all whitespace (including hyphenated line-breaks) to single spaces
            let cleaned = snippet
                .replacingOccurrences(of: "-\n", with: "")  // unhyphenate
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            guard !cleaned.isEmpty else { return [] }

            let opts: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

            // Try progressively shorter prefixes: full → 70 → 50 → 35 chars
            for length in [cleaned.count, 70, 50, 35] {
                guard length <= cleaned.count else { continue }
                let probe = String(cleaned.prefix(length))
                guard probe.count >= 20 else { break }
                let found = document.findString(probe, withOptions: opts)
                if !found.isEmpty { return found }
            }

            return []
        }

                private func applySquigglyHighlight(for selection: PDFSelection, contents: String, in pdfView: PDFView, delay: TimeInterval = 0) {
            for lineSelection in selection.selectionsByLine() {
                for page in lineSelection.pages {
                    let bounds = lineSelection.bounds(for: page)
                    guard !bounds.isEmpty else { continue }
                    let annotation = SquigglyAnnotation(
                        bounds: bounds.insetBy(dx: -0.5, dy: 0),
                        contents: contents,
                        displayView: pdfView
                    )
                    page.addAnnotation(annotation)
                    annotation.animateDrawIn(delay: delay)
                }
            }
        }

        private func applyHighlight(
            for selection: PDFSelection,
            color: NSColor,
            contents: String
        ) {
            for lineSelection in selection.selectionsByLine() {
                for page in lineSelection.pages {
                    let bounds = lineSelection.bounds(for: page)
                    guard !bounds.isEmpty else { continue }
                    let markerBounds = bounds.insetBy(dx: -0.8, dy: -1.1)
                    let annotation = PopInHighlightAnnotation(
                        bounds: markerBounds,
                        color: color,
                        contents: contents
                    )
                    page.addAnnotation(annotation)
                    annotation.animatePopIn(finalBounds: markerBounds, finalColor: color)
                }
            }
        }

        private func removeExistingCoLearnerHighlights(from document: PDFDocument) {
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else {
                    continue
                }

                for annotation in page.annotations where Self.isCoLearnerHighlight(annotation) {
                    page.removeAnnotation(annotation)
                }
            }
        }

        private static let paperHighlightContents = "CoLearner AI Highlight"
        private static let previousPaperHighlightContents = "CoLearner Paper Highlight"
        private static let userHighlightContentsPrefix = "CoLearner User Highlight"

        private static func isCoLearnerHighlight(_ annotation: PDFAnnotation) -> Bool {
            guard let contents = annotation.contents else {
                return false
            }

            return contents == paperHighlightContents
                || contents == previousPaperHighlightContents
        }
    }
}

// MARK: - Squiggly underline annotation (with draw-in animation)

private extension NSColor {
    /// The warm amber used for AI squiggly highlights.
    static let coLearnerSquiggleAmber = NSColor(calibratedRed: 0.82, green: 0.38, blue: 0.15, alpha: 0.85)
}

private final class SquigglyAnnotation: PDFAnnotation, @unchecked Sendable {
    /// 0…1 — fraction of the wave drawn. Drives the left-to-right "marker sweep".
    private var progress: CGFloat = 1
    private weak var displayView: PDFView?
    private var animationTimer: Timer?

    init(bounds: CGRect, contents: String, displayView: PDFView? = nil) {
        super.init(bounds: bounds, forType: .ink, withProperties: nil)
        self.contents = contents
        self.color = .coLearnerSquiggleAmber
        self.shouldDisplay = true
        self.shouldPrint = false
        self.displayView = displayView
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        animationTimer?.invalidate()
    }

    /// Animate the underline drawing itself in from left to right, like a marker
    /// sweeping across the text. `delay` staggers the start so several highlights
    /// cascade across a page instead of all firing at once.
    func animateDrawIn(duration: TimeInterval = 0.6, delay: TimeInterval = 0) {
        progress = 0
        // Start transparent; ramp alpha alongside the sweep for a soft intro.
        color = NSColor.coLearnerSquiggleAmber.withAlphaComponent(0)
        let start = CACurrentMediaTime() + delay

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed = max(0, CACurrentMediaTime() - start)
            let t = min(1, elapsed / duration)
            self.progress = Self.easeOutCubic(t)
            // Color mutations on a displayed annotation reliably trigger a redraw in PDFView,
            // which re-invokes draw(with:in:) so the sweep is actually painted each frame.
            self.color = NSColor.coLearnerSquiggleAmber.withAlphaComponent(0.85 * min(1, t * 1.6))

            if t >= 1 {
                self.progress = 1
                self.color = .coLearnerSquiggleAmber
                timer.invalidate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let rect = self.bounds
        let sweptWidth = rect.width * progress
        guard sweptWidth > 0 else { return }

        let y = rect.minY + 1.0
        let amplitude: CGFloat = 1.2
        let half: CGFloat = 4.0
        let drawMaxX = rect.minX + sweptWidth

        context.saveGState()
        // Clip to the swept region so the wave "draws in" from the left edge.
        context.clip(to: CGRect(x: rect.minX, y: rect.minY, width: sweptWidth, height: rect.height))
                context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.1)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let path = CGMutablePath()
        var x = rect.minX
        var goingUp = true
        path.move(to: CGPoint(x: x, y: y))

        while x < drawMaxX {
            let nextX = min(x + half, drawMaxX)
            let controlX = (x + nextX) * 0.5
            let controlY = goingUp ? y + amplitude : y - amplitude
            path.addQuadCurve(
                to: CGPoint(x: nextX, y: y),
                control: CGPoint(x: controlX, y: controlY)
            )
            x = nextX
            goingUp.toggle()
        }

        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

        private static func easeOutCubic(_ t: CGFloat) -> CGFloat {
        let t = max(0, min(1, t))
        return 1 - pow(1 - t, 3)
    }
}

// MARK: - Highlight pop-in animation

private final class PopInHighlightAnnotation: PDFAnnotation, @unchecked Sendable {
    private var animationTimer: Timer?

    init(bounds: CGRect, color: NSColor, contents: String) {
        super.init(bounds: bounds, forType: .highlight, withProperties: nil)
        self.contents = contents
        self.color = color.withAlphaComponent(0)
        self.shouldDisplay = true
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        animationTimer?.invalidate()
    }

    /// Pop in: start slightly larger and transparent, overshoot, then settle to the
    /// target bounds and color. Bounds/color mutations on a displayed annotation
    /// reliably trigger redraws in PDFView.
    func animatePopIn(finalBounds: CGRect, finalColor: NSColor, duration: TimeInterval = 0.45) {
        let startBounds = finalBounds.insetBy(dx: -3, dy: -1.5)
        let start = CACurrentMediaTime()

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let t = min(1, (CACurrentMediaTime() - start) / duration)
            let eased = Self.easeOutBack(t)

            self.bounds = Self.interpolate(from: startBounds, to: finalBounds, eased)
            // Overshoot the alpha a touch for a soft flash, then settle.
            self.color = finalColor.withAlphaComponent(min(1, finalColor.alphaComponent * eased))

            if t >= 1 {
                self.bounds = finalBounds
                self.color = finalColor
                timer.invalidate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private static func easeOutBack(_ t: CGFloat) -> CGFloat {
        let t = max(0, min(1, t))
        let c1: CGFloat = 1.70158
        let c3 = c1 + 1
        let u = t - 1
        return 1 + c3 * u * u * u + c1 * u * u
    }

    private static func interpolate(from a: CGRect, to b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(
            x: a.minX + (b.minX - a.minX) * t,
            y: a.minY + (b.minY - a.minY) * t,
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t
        )
    }
}
