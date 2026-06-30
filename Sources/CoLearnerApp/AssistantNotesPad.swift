import AppKit
import SwiftUI

struct AssistantNotesPad: View {
    @ObservedObject var viewModel: ReaderViewModel
    @Binding var isFocused: Bool
    let onClose: () -> Void
    @Environment(\.clInterfaceScale) private var interfaceScale
    @Environment(\.clChatFontSize) private var chatFontSize

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundStyle(CLColor.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes")
                        .font(.system(size: 13 * interfaceScale, weight: .semibold))
                        .foregroundStyle(CLColor.ink)
                    Text("Plain text note pad. Paste code, prompts, examples, or reading notes.")
                        .font(.system(size: 11.5 * interfaceScale))
                        .foregroundStyle(CLColor.ink3)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10 * interfaceScale, weight: .bold))
                        .foregroundStyle(CLColor.ink3)
                        .frame(width: 22 * interfaceScale, height: 22 * interfaceScale)
                }
                .buttonStyle(.plain)
                .help("Close notes")
            }

            ZStack(alignment: .topLeading) {
                ComposerTextView(
                    text: $viewModel.draftNote,
                    isFocused: $isFocused,
                    font: .monospacedSystemFont(ofSize: max(12.5, chatFontSize - 0.5), weight: .regular),
                    textColor: .labelColor,
                    returnKeyBehavior: .insertNewline
                ) {}
                .frame(minHeight: 94, maxHeight: 150)

                if viewModel.draftNote.isEmpty {
                    Text("Write notes, code snippets, questions, or examples...")
                        .font(.system(size: max(12.5, chatFontSize - 0.5), design: .monospaced))
                        .foregroundStyle(CLColor.ink4)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 8) {
                Button("Use context") {
                    viewModel.startNoteFromContext()
                    isFocused = true
                }
                .buttonStyle(CLGhostButtonStyle())
                .disabled(viewModel.resolvedChatContext() == nil)

                Spacer()

                Button("Save note") {
                    viewModel.saveDraftNote()
                    isFocused = true
                }
                .buttonStyle(CLPrimaryButtonStyle())
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.55)
            }
        }
        .padding(12)
        .background(CLColor.surface)
        .overlay(alignment: .top) {
            CLDivider(.horizontal)
        }
    }

    private var canSave: Bool {
        !viewModel.draftNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
