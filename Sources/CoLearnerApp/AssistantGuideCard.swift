import SwiftUI

struct AssistantGuideCard: View {
    @ObservedObject var viewModel: ReaderViewModel
    let onDismiss: () -> Void
    let onPrompt: (String) -> Void
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(CLColor.accent)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("How the AI companion helps")
                            .font(.system(size: 13 * interfaceScale, weight: .semibold))
                            .foregroundStyle(CLColor.ink)

                        Text(viewModel.assistantCapabilitySummary)
                            .font(.system(size: 12 * interfaceScale))
                            .foregroundStyle(CLColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10 * interfaceScale, weight: .bold))
                            .foregroundStyle(CLColor.ink3)
                            .frame(width: 22 * interfaceScale, height: 22 * interfaceScale)
                            .background(CLColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(CLColor.border2, lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Close guide")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                GuideRow(
                    systemImage: "1.circle",
                    title: "Choose source",
                    detail: "Use Selection, Page, Section, or Document. Only the active context is sent."
                )
                GuideRow(
                    systemImage: "2.circle",
                    title: "Ask or click an action",
                    detail: "Explain, summarize, examples, quiz, key points, and highlight are all explicit actions."
                )
                GuideRow(
                    systemImage: "3.circle",
                    title: "Review response",
                    detail: "You see your question, the answer, and suggested highlights you can apply or discuss."
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Try")
                    .font(.system(size: 10 * interfaceScale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CLColor.ink3)

                GuidePromptButton("Explain the main idea in simple language") {
                    onPrompt("Explain the main idea in simple language.")
                }
                GuidePromptButton("What are the 3 most important points?") {
                    onPrompt("What are the 3 most important points here?")
                }
                GuidePromptButton("Highlight what I should remember") {
                    onPrompt("Highlight what I should remember and explain why.")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CLColor.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(CLColor.accentEdge, lineWidth: 0.5)
        }
    }
}

private struct GuideRow: View {
    let systemImage: String
    let title: String
    let detail: String
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12 * interfaceScale, weight: .medium))
                .foregroundStyle(CLColor.accent)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12 * interfaceScale, weight: .semibold))
                    .foregroundStyle(CLColor.ink)
                Text(detail)
                    .font(.system(size: 11.5 * interfaceScale))
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct GuidePromptButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.clInterfaceScale) private var interfaceScale

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10 * interfaceScale, weight: .semibold))
                    .foregroundStyle(CLColor.accent)
                Text(title)
                    .font(.system(size: 11.5 * interfaceScale))
                    .foregroundStyle(CLColor.ink2)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 24 * interfaceScale)
            .background(CLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(CLColor.border2, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}
