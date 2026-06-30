import AppKit
import SwiftUI

struct ComposerTextView: NSViewRepresentable {
    enum ReturnKeyBehavior {
        case insertNewline
        case submit
    }

    @Binding var text: String
    @Binding var isFocused: Bool
    var font: NSFont = .systemFont(ofSize: 13)
    var textColor: NSColor = .labelColor
    var insertionPointColor: NSColor = .clHex(0xC96442)
    var returnKeyBehavior: ReturnKeyBehavior = .submit
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = KeyHandlingTextView()
        textView.delegate = context.coordinator
        textView.returnKeyBehavior = returnKeyBehavior
        textView.onSubmit = onSubmit
        textView.onFocusChange = { isActive in
            isFocused = isActive
        }
        textView.string = text
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = insertionPointColor
        textView.alignment = .left
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? KeyHandlingTextView else {
            return
        }

        textView.returnKeyBehavior = returnKeyBehavior
        textView.onSubmit = onSubmit
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = insertionPointColor
        textView.alignment = .left
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: textColor
        ]

        if textView.string != text {
            let selectedRanges = textView.validSelectionRangesAfterReplacingText(with: text)
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        guard let window = scrollView.window else {
            return
        }

        if isFocused, window.firstResponder !== textView {
            DispatchQueue.main.async {
                window.makeFirstResponder(textView)
            }
        } else if !isFocused, window.firstResponder === textView {
            DispatchQueue.main.async {
                window.makeFirstResponder(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        fileprivate weak var textView: KeyHandlingTextView?

        init(_ parent: ComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            parent.text = textView.string
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }
    }
}

fileprivate final class KeyHandlingTextView: NSTextView {
    var returnKeyBehavior: ComposerTextView.ReturnKeyBehavior = .submit
    var onSubmit: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.charactersIgnoringModifiers == "\r"
            || event.charactersIgnoringModifiers == "\n"
        let wantsNewline = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.shift)

        if returnKeyBehavior == .submit, isReturn, !wantsNewline {
            onSubmit?()
            return
        }

        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onFocusChange?(true)
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            onFocusChange?(false)
        }
        return didResignFirstResponder
    }

    func validSelectionRangesAfterReplacingText(with nextText: String) -> [NSValue] {
        let replacementLength = (nextText as NSString).length
        guard replacementLength > 0 else {
            return [NSValue(range: NSRange(location: 0, length: 0))]
        }

        let currentSelectedRanges = self.selectedRanges.compactMap { value -> NSValue? in
            let range = value.rangeValue
            guard range.location <= replacementLength else {
                return nil
            }

            let clampedLength = min(range.length, replacementLength - range.location)
            return NSValue(range: NSRange(location: range.location, length: clampedLength))
        }

        if currentSelectedRanges.isEmpty {
            return [NSValue(range: NSRange(location: replacementLength, length: 0))]
        }

        return currentSelectedRanges
    }
}
