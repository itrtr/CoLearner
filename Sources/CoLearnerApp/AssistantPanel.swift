import CoLearnerCore
import AppKit
import SwiftUI

struct AssistantPanel: View {
    @ObservedObject var viewModel: ReaderViewModel
    @AppStorage("colearnerAssistantGuideHidden") private var isGuideHidden = false
    @State private var isComposerFocused = false
    @State private var isNotesPadOpen = false
    @State private var isNotesFocused = false
    @Environment(\.clInterfaceScale) private var interfaceScale
    @Environment(\.clChatFontSize) private var chatFontSize
    @Environment(\.clChatFontChoice) private var chatFontChoice

    var body: some View {
        VStack(spacing: 0) {
            header
            CLDivider(.horizontal)
            companionTabs
            CLDivider(.horizontal)

            if viewModel.selectedCompanionTab == .notes {
                NotesWorkspace(viewModel: viewModel)
            } else {
                contextStrip
                CLDivider(.horizontal)
                messages
                if isNotesPadOpen {
                    AssistantNotesPad(
                        viewModel: viewModel,
                        isFocused: $isNotesFocused
                    ) {
                        isNotesPadOpen = false
                        isNotesFocused = false
                    }
                }
                CLDivider(.horizontal)
                composer
            }
        }
        .background(CLColor.chrome)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(CLColor.accent)
                .frame(width: 6, height: 6)

            Text("AI Companion")
                .font(uiFont(size: 13, weight: .semibold))
                .foregroundStyle(CLColor.ink)

            if viewModel.selectedContextScope == .fullDocument {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                    Text("full-doc")
                }
                .font(.system(size: 10.5 * interfaceScale, design: .monospaced))
                .foregroundStyle(CLColor.accentInk)
                .padding(.horizontal, 7)
                .frame(height: 20 * interfaceScale)
                .background(CLColor.selected)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Spacer()

            oauthBadge

            CLToolbarIconButton(systemImage: "plus", title: "New chat") {
                viewModel.resetChat()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: CLMetric.chatHeaderHeight * interfaceScale)
    }

    private var companionTabs: some View {
        HStack(spacing: 6) {
            ForEach([CompanionTab.chat, .notes]) { tab in
                Button {
                    viewModel.selectedCompanionTab = tab
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab == .chat ? "bubble.left.and.text.bubble.right" : "note.text")
                            .font(uiFont(size: 11.5, weight: .medium))
                        Text(tab.label)
                            .font(uiFont(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(viewModel.selectedCompanionTab == tab ? CLColor.accentInk : CLColor.ink2)
                    .padding(.horizontal, 9)
                    .frame(height: 26 * interfaceScale)
                    .background(viewModel.selectedCompanionTab == tab ? CLColor.selected : CLColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(viewModel.selectedCompanionTab == tab ? CLColor.accentEdge : CLColor.border2, lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(CLColor.window)
    }

    @ViewBuilder
    private var modelMenu: some View {
        if let label = viewModel.selectedModelLabel(for: viewModel.selectedProvider) {
            Menu {
                switch viewModel.selectedProvider {
                case .claude:
                    Picker(
                        "Claude model",
                        selection: Binding(
                            get: { viewModel.selectedClaudeModel },
                            set: { viewModel.selectClaudeModel($0) }
                        )
                    ) {
                        ForEach(DirectAnthropicStudyAgent.availableModels) { option in
                            Text("\(option.label)  ·  \(option.tierHint)").tag(option.id)
                        }
                    }
                case .codex:
                    Picker(
                        "Codex model",
                        selection: Binding(
                            get: { viewModel.selectedCodexModel },
                            set: { viewModel.selectCodexModel($0) }
                        )
                    ) {
                        ForEach(DirectOpenAIStudyAgent.availableModels) { option in
                            Text("\(option.label)  ·  \(option.tierHint)").tag(option.id)
                        }
                    }
                case .local, .openCode, .pi, .hermes:
                    EmptyView()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "cpu")
                        .font(uiFont(size: 11, weight: .medium))
                    Text(label)
                        .font(.system(size: 11 * interfaceScale, design: .monospaced))
                    Image(systemName: "chevron.down")
                        .font(uiFont(size: 8, weight: .semibold))
                }
                .foregroundStyle(CLColor.ink2)
                .padding(.horizontal, 8)
                .frame(height: 24 * interfaceScale)
                .background(CLColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(CLColor.border2, lineWidth: 0.5)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var oauthBadge: some View {
        if let oauthProvider = viewModel.providerRequiresOAuth(viewModel.selectedProvider) {
            let isSignedIn = viewModel.signedInProviders.contains(oauthProvider)
            let isPending = viewModel.pendingOAuthSignIn == oauthProvider

            if isPending {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Signing in…")
                        .font(.system(size: 11 * interfaceScale, design: .monospaced))
                        .foregroundStyle(CLColor.ink3)
                }
                .padding(.horizontal, 8)
                .frame(height: 24 * interfaceScale)
                .background(CLColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if isSignedIn {
                Menu {
                    Button("Sign out of \(oauthProvider.rawValue.capitalized)") {
                        viewModel.signOut(oauthProvider)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(uiFont(size: 10, weight: .semibold))
                            .foregroundStyle(CLColor.accent)
                        Text("Signed in")
                            .font(.system(size: 11 * interfaceScale, design: .monospaced))
                            .foregroundStyle(CLColor.ink2)
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
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Button {
                    viewModel.signIn(oauthProvider)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.badge.key")
                            .font(uiFont(size: 10, weight: .semibold))
                        Text("Sign in")
                            .font(.system(size: 11 * interfaceScale, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(CLColor.accentInk)
                    .padding(.horizontal, 10)
                    .frame(height: 24 * interfaceScale)
                    .background(CLColor.selected)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(CLColor.accentEdge, lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var providerMenu: some View {
        Menu {
            Picker(
                "Agent",
                selection: Binding(
                    get: { viewModel.selectedProvider },
                    set: { viewModel.selectProvider($0) }
                )
            ) {
                ForEach(StudyAgentProvider.allCases) { provider in
                    Text(provider.label).tag(provider)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "bolt.horizontal")
                    .font(uiFont(size: 11, weight: .medium))
                Text(viewModel.selectedProvider.label)
                    .font(.system(size: 11 * interfaceScale, design: .monospaced))
                Image(systemName: "chevron.down")
                    .font(uiFont(size: 8, weight: .semibold))
            }
            .foregroundStyle(CLColor.ink2)
            .padding(.horizontal, 8)
            .frame(height: 24 * interfaceScale)
            .background(CLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(CLColor.border2, lineWidth: 0.5)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var contextStrip: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Context for next message")
                .font(.system(size: 10 * interfaceScale, weight: .semibold, design: .monospaced))
                .foregroundStyle(CLColor.ink3)

            FlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(ChatContextScope.allCases) { scope in
                    CLContextChip(
                        systemImage: scope.systemImage,
                        title: scope.label,
                        meta: chipMeta(for: scope),
                        isActive: viewModel.selectedContextScope == scope,
                        isDisabled: !viewModel.canUseContext(scope)
                    ) {
                        viewModel.selectContextScope(scope)
                    }
                }
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(uiFont(size: 11, weight: .medium))
                    .foregroundStyle(CLColor.accent)
                Text(viewModel.activeContextExplanation)
                    .font(uiFont(size: 11.5))
                    .foregroundStyle(CLColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(CLColor.window)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if shouldShowGuide {
                        AssistantGuideCard(
                            viewModel: viewModel,
                            onDismiss: {
                                isGuideHidden = true
                            }
                        ) { prompt in
                            isGuideHidden = true
                            viewModel.sendChatMessage(text: prompt)
                        }
                    }

                    if viewModel.chatMessages.isEmpty {
                        EmptyCompanionState()
                    }

                    ForEach(viewModel.chatMessages) { message in
                        ChatMessageRow(
                            message: message,
                            statusText: viewModel.responseStatusText,
                            providerLabel: viewModel.selectedProviderDisplayName,
                            providerDetail: viewModel.assistantCapabilitySummary
                        )
                        .id(message.id)
                    }

                    if showSuggestedHighlights {
                        SuggestedHighlightsCard(viewModel: viewModel)
                            .id("suggested-highlights")
                    }
                }
                .padding(12)
            }
            .scrollIndicators(.automatic)
            .onChange(of: viewModel.chatMessages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.isResponding) { _, _ in
                scrollToBottom(proxy)
            }
        }
        .background(CLColor.window)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Model / provider row — replaces the header menus
            HStack(spacing: 6) {
                providerMenu
                modelMenu
                Spacer()
                Text(contextFooter)
                    .font(.system(size: 10 * interfaceScale, design: .monospaced))
                    .foregroundStyle(CLColor.ink3)
            }

            // Text input card — at the top so the user can type questions first.
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    ComposerTextView(
                        text: $viewModel.chatDraft,
                        isFocused: $isComposerFocused,
                        font: chatFontChoice.nsFont(size: chatFontSize),
                        textColor: .labelColor,
                        returnKeyBehavior: .submit
                    ) {
                        if canSend {
                            viewModel.sendChatMessage()
                        }
                    }
                    .frame(
                        minHeight: max(48, chatFontSize * 3.2),
                        maxHeight: max(88, chatFontSize * 5.8)
                    )

                    if viewModel.chatDraft.isEmpty {
                        Text(viewModel.selectedSelection == nil
                             ? "Ask about the document…"
                             : "Add your question — the selection below will be attached as context")
                            .font(chatFontChoice.swiftUIFont(size: chatFontSize))
                            .foregroundStyle(CLColor.ink4)
                            .padding(.top, 4)
                            .allowsHitTesting(false)
                    }
                }

                // Selection card — the attached context for the next message. Lives below the
                // text input so the user reads "my question + attached selection".
                if viewModel.selectedSelection != nil,
                   let preview = viewModel.selectedTextPreview {
                    selectionFollowUpCard(preview: preview)
                }

                HStack(spacing: 6) {
                    Button {
                        toggleNotesPad()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "note.text")
                                .font(uiFont(size: 10.5, weight: .medium))
                            Text("Notes")
                                .font(uiFont(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(isNotesPadOpen ? CLColor.accentInk : CLColor.ink3)
                        .padding(.horizontal, 7)
                        .frame(height: 22 * interfaceScale)
                        .background(isNotesPadOpen ? CLColor.selected : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(isNotesPadOpen ? "Close notes" : "Open notes")

                    Spacer()

                    if viewModel.isResponding {
                        Button {
                            viewModel.cancelChat()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "stop.fill")
                                    .font(uiFont(size: 10, weight: .bold))
                                Text("Stop")
                                    .font(uiFont(size: 11.5, weight: .semibold))
                            }
                            .foregroundStyle(CLColor.ink)
                            .padding(.horizontal, 9)
                            .frame(height: 26 * interfaceScale)
                            .background(CLColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(CLColor.border2, lineWidth: 0.5)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Stop response")
                    } else {
                        Button {
                            viewModel.sendChatMessage()
                        } label: {
                            HStack(spacing: 5) {
                                Text("Send")
                                    .font(uiFont(size: 11.5, weight: .semibold))
                                Image(systemName: "arrow.up")
                                    .font(uiFont(size: 10, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .frame(height: 26 * interfaceScale)
                            .background(canSend ? CLColor.accent : CLColor.ink4)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .help("Send  ↵")
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(CLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isComposerFocused ? CLColor.accentEdge : CLColor.border2, lineWidth: 0.5)
            }
        }
        .padding(12)
        .background(CLColor.window)
        .contentShape(Rectangle())
        .onTapGesture {
            isComposerFocused = true
        }
    }

    private var showSuggestedHighlights: Bool {
        guard !viewModel.isResponding,
              let response = viewModel.response else {
            return false
        }

        return !response.highlights.isEmpty
    }

    private var shouldShowGuide: Bool {
        !isGuideHidden && !viewModel.chatMessages.contains { $0.role == .user }
    }

    private var canSend: Bool {
        viewModel.resolvedChatContext() != nil
            && !viewModel.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isResponding
    }

    private var contextFooter: String {
        switch viewModel.selectedContextScope {
        case .selectedPassage:
            "selection"
        case .currentPage:
            "p.\(viewModel.currentPageIndex + 1)"
        case .currentSection:
            "section"
        case .fullDocument:
            "graph-rag"
        }
    }

    private func chipMeta(for scope: ChatContextScope) -> String? {
        switch scope {
        case .selectedPassage:
            viewModel.selectedTextPreview == nil ? "—" : nil
        case .currentPage:
            "\(viewModel.currentPageIndex + 1)"
        case .currentSection:
            viewModel.selectedMapItem.map { "§\($0.pageIndex + 1)" }
        case .fullDocument:
            "graph"
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastMessage = viewModel.chatMessages.last else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                if showSuggestedHighlights {
                    proxy.scrollTo("suggested-highlights", anchor: .bottom)
                } else {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }

    private func selectionFollowUpCard(preview: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "text.quote")
                    .font(uiFont(size: 11, weight: .medium))
                    .foregroundStyle(CLColor.accent)
                    .padding(.top, 2)

                Text(preview)
                    .font(.system(size: 11.5 * interfaceScale, design: .serif))
                    .foregroundStyle(CLColor.ink2)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    viewModel.clearSelection()
                } label: {
                    Image(systemName: "xmark")
                        .font(uiFont(size: 9, weight: .semibold))
                        .foregroundStyle(CLColor.ink3)
                        .frame(width: 18, height: 18)
                        .background(CLColor.surface.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Clear selection")
            }

            FlowLayout(spacing: 5, rowSpacing: 5) {
                SelectionActionChip(systemImage: "wand.and.stars", title: "Explain") {
                    viewModel.draftSelectionPrompt(mode: .explain)
                    isComposerFocused = true
                }
                SelectionActionChip(systemImage: "list.bullet", title: "Summarize") {
                    viewModel.draftSelectionPrompt(mode: .simplify)
                    isComposerFocused = true
                }
                SelectionActionChip(systemImage: "square.stack.3d.up", title: "Examples") {
                    viewModel.draftSelectionPrompt(mode: .examples)
                    isComposerFocused = true
                }
                SelectionActionChip(systemImage: "questionmark.circle", title: "Quiz me") {
                    viewModel.draftSelectionPrompt(mode: .quiz)
                    isComposerFocused = true
                }
                SelectionActionChip(systemImage: "pencil.line", title: "Key points") {
                    viewModel.draftSelectionKeyPoints()
                    isComposerFocused = true
                }
                SelectionActionChip(systemImage: "highlighter", title: "Highlight") {
                    viewModel.draftSelectionHighlights()
                    isComposerFocused = true
                }
            }
        }
        .padding(9)
        .background(CLColor.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(CLColor.accentEdge, lineWidth: 0.5)
        }
    }

    private func toggleNotesPad() {
        isNotesPadOpen.toggle()

        if isNotesPadOpen {
            isComposerFocused = false
            DispatchQueue.main.async {
                isNotesFocused = true
            }
        } else {
            isNotesFocused = false
        }
    }

    private func uiFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: size * interfaceScale, weight: weight, design: design)
    }
}

private struct SelectionActionChip: View {
    let systemImage: String
    let title: String
    let action: () -> Void
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5 * interfaceScale, weight: .medium))
                Text(title)
                    .font(.system(size: 11 * interfaceScale, weight: .medium))
            }
            .foregroundStyle(CLColor.accentInk)
            .padding(.horizontal, 8)
            .frame(height: 22 * interfaceScale)
            .background(CLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(CLColor.accentEdge, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessage
    let statusText: String
    let providerLabel: String
    let providerDetail: String
    @Environment(\.clInterfaceScale) private var interfaceScale
    @Environment(\.clChatFontSize) private var chatFontSize
    @Environment(\.clChatFontChoice) private var chatFontChoice

    var body: some View {
        switch message.role {
        case .user:
            userMessage
        case .assistant:
            assistantMessage
        }
    }

    private var userMessage: some View {
        VStack(alignment: .leading, spacing: 7) {
            messageHeader("you")

            MarkdownMessageView(
                text: message.text,
                baseFontSize: chatFontSize,
                fontChoice: chatFontChoice,
                foregroundColor: CLColor.ink,
                lineSpacing: 2
            )
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clCard(cornerRadius: 8)
    }

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            messageHeader(message.isError ? "error" : "◆ companion")
                .foregroundStyle(message.isError ? .red : CLColor.accentInk)

            if message.isPending {
                AssistantLoadingCard(
                    statusText: statusText,
                    providerLabel: providerLabel,
                    providerDetail: providerDetail
                )
            } else {
                MarkdownMessageView(
                    text: message.text,
                    baseFontSize: chatFontSize,
                    fontChoice: chatFontChoice,
                    foregroundColor: message.isError ? .red : CLColor.ink2,
                    lineSpacing: 3
                )
            }
        }
        .padding(.horizontal, message.isError ? 11 : 0)
        .padding(.vertical, message.isError ? 9 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.isError ? Color.red.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func messageHeader(_ role: String) -> some View {
        HStack(spacing: 6) {
            Text(role)
                .font(.system(size: 11 * interfaceScale, design: .monospaced))
            if let contextTitle = message.contextTitle {
                Text("·")
                Text(contextTitle)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 11 * interfaceScale, design: .monospaced))
        .foregroundStyle(CLColor.ink3)
    }
}

private struct AssistantLoadingCard: View {
    let statusText: String
    let providerLabel: String
    let providerDetail: String
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Working on it")
                    .font(.system(size: 12.5 * interfaceScale, weight: .semibold))
                    .foregroundStyle(CLColor.ink)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 7) {
                LoadingStep(isActive: false, title: "Context locked", detail: statusText)
                LoadingStep(isActive: true, title: "Asking \(providerLabel)", detail: providerDetail)
                LoadingStep(isActive: false, title: "Next", detail: "The answer will appear here. Suggested highlights wait for your approval.")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CLColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(CLColor.border2, lineWidth: 0.5)
        }
    }
}

private struct LoadingStep: View {
    let isActive: Bool
    let title: String
    let detail: String
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(isActive ? CLColor.accent : CLColor.borderStrong)
                .frame(width: 7, height: 7)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5 * interfaceScale, weight: .semibold))
                    .foregroundStyle(isActive ? CLColor.accentInk : CLColor.ink2)
                Text(detail)
                    .font(.system(size: 11 * interfaceScale))
                    .foregroundStyle(CLColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SuggestedHighlightsCard: View {
    @ObservedObject var viewModel: ReaderViewModel
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "highlighter")
                    .font(.system(size: 12 * interfaceScale, weight: .medium))
                Text("\(highlights.count) highlights suggested")
                    .font(.system(size: 10 * interfaceScale, weight: .semibold, design: .monospaced))
                Spacer()
            }
            .foregroundStyle(CLColor.accentInk)

            VStack(spacing: 6) {
                ForEach(Array(highlights.prefix(5).enumerated()), id: \.offset) { _, highlight in
                    Button {
                        viewModel.discussHighlight(highlight)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Capsule()
                                .fill(CLColor.accent)
                                .frame(width: 3, height: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("\"\(highlight)\"")
                                    .font(.system(size: 11.5 * interfaceScale, design: .serif))
                                    .foregroundStyle(CLColor.ink2)
                                    .lineLimit(3)

                                Text("Discuss why this matters")
                                    .font(.system(size: 10.5 * interfaceScale, design: .monospaced))
                                    .foregroundStyle(CLColor.accentInk)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .background(CLColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(CLColor.accentEdge, lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Button("Apply all") {
                    viewModel.setAIHighlightsVisible(true)
                }
                .buttonStyle(CLPrimaryButtonStyle())

                Button(viewModel.showsAIHighlights ? "Hide in PDF" : "Show in PDF") {
                    viewModel.setAIHighlightsVisible(!viewModel.showsAIHighlights)
                }
                .buttonStyle(CLGhostButtonStyle())

                Spacer()

                Button("Save as note") {
                    viewModel.saveCurrentInsight()
                }
                .buttonStyle(CLGhostButtonStyle())
            }
        }
        .padding(10)
        .background(CLColor.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(CLColor.accentEdge, lineWidth: 0.5)
        }
    }

    private var highlights: [String] {
        viewModel.response?.highlights ?? []
    }
}

private struct NotesWorkspace: View {
    @ObservedObject var viewModel: ReaderViewModel
    @State private var isNoteFocused = false
    @Environment(\.clInterfaceScale) private var interfaceScale
    @Environment(\.clChatFontSize) private var chatFontSize

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    workspaceHeader

                    if viewModel.savedNotes.isEmpty {
                        EmptyNotesState()
                    } else {
                        ForEach(viewModel.savedNotes) { note in
                            NoteWorkspaceRow(
                                note: note,
                                onJump: {
                                    viewModel.navigateToNote(note)
                                },
                                onDelete: {
                                    viewModel.deleteNote(note)
                                }
                            )
                        }
                    }
                }
                .padding(12)
            }
            .scrollIndicators(.automatic)

            CLDivider(.horizontal)

            noteEditor
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CLColor.window)
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "note.text")
                    .foregroundStyle(CLColor.accent)
                Text("Document Notes")
                    .font(.system(size: 14 * interfaceScale, weight: .semibold))
                    .foregroundStyle(CLColor.ink)
                Spacer()
                Text("\(viewModel.savedNotes.count)")
                    .font(.system(size: 11 * interfaceScale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CLColor.ink3)
            }

            Text("Notes and user highlights stay scoped to this PDF. Jump back to a note source from any saved item.")
                .font(.system(size: 12 * interfaceScale))
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .clCard(cornerRadius: 8)
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("New note")
                    .font(.system(size: 11 * interfaceScale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CLColor.ink3)
                Spacer()
                Button("Use current context") {
                    viewModel.startNoteFromContext()
                    isNoteFocused = true
                }
                .buttonStyle(CLGhostButtonStyle())
                .disabled(viewModel.resolvedChatContext() == nil)
            }

            ZStack(alignment: .topLeading) {
                ComposerTextView(
                    text: $viewModel.draftNote,
                    isFocused: $isNoteFocused,
                    font: .monospacedSystemFont(ofSize: max(12.5, chatFontSize - 0.5), weight: .regular),
                    textColor: .labelColor,
                    returnKeyBehavior: .insertNewline
                ) {}
                .frame(minHeight: 92, maxHeight: 142)

                if viewModel.draftNote.isEmpty {
                    Text("Write a document note...")
                        .font(.system(size: max(12.5, chatFontSize - 0.5), design: .monospaced))
                        .foregroundStyle(CLColor.ink4)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Spacer()
                Button("Save note") {
                    viewModel.saveDraftNote()
                    isNoteFocused = true
                }
                .buttonStyle(CLPrimaryButtonStyle())
                .disabled(viewModel.draftNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(CLColor.surface)
    }
}

private struct NoteWorkspaceRow: View {
    let note: LearningNote
    let onJump: () -> Void
    let onDelete: () -> Void
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Capsule()
                    .fill(CLColor.accent)
                    .frame(width: 3, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title)
                        .font(.system(size: 12.5 * interfaceScale, weight: .semibold))
                        .foregroundStyle(CLColor.ink)
                        .lineLimit(1)

                    Text(note.body)
                        .font(.system(size: 12 * interfaceScale, design: .serif))
                        .foregroundStyle(CLColor.ink2)
                        .lineLimit(6)

                    HStack(spacing: 6) {
                        if let sourcePageIndex = note.sourcePageIndex {
                            Text("p.\(sourcePageIndex + 1)")
                        }
                        Text(note.sourceExcerpt ?? note.sourceTitle)
                            .lineLimit(1)
                    }
                    .font(.system(size: 10.5 * interfaceScale, design: .monospaced))
                    .foregroundStyle(CLColor.ink3)
                }
            }

            HStack(spacing: 8) {
                Button("Jump to source", action: onJump)
                    .buttonStyle(CLGhostButtonStyle())
                    .disabled(note.sourcePageIndex == nil)

                Spacer()

                Button("Delete", action: onDelete)
                    .buttonStyle(CLGhostButtonStyle())
            }
        }
        .padding(10)
        .clCard(cornerRadius: 8)
    }
}

private struct EmptyNotesState: View {
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "highlighter")
                    .foregroundStyle(CLColor.accent)
                Text("No document notes yet")
                    .font(.system(size: 13 * interfaceScale, weight: .semibold))
                    .foregroundStyle(CLColor.ink)
            }

            Text("Select PDF text and use Highlight, or write a note below. Saved entries remain attached to this document.")
                .font(.system(size: 12 * interfaceScale))
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clCard(cornerRadius: 8)
    }
}

private struct EmptyCompanionState: View {
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(CLColor.accent)
                Text("Ask with document context")
                    .font(.system(size: 13 * interfaceScale, weight: .semibold))
                    .foregroundStyle(CLColor.ink)
            }

            Text("Select text, choose a page, section, or full document scope, then ask a question. Selecting text only changes context; it never starts chat by itself.")
                .font(.system(size: 12 * interfaceScale))
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clCard(cornerRadius: 8)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rows(in: width, subviews: subviews)
        let height = rows.reduce(CGFloat.zero) { result, row in
            result + row.height
        } + CGFloat(max(rows.count - 1, 0)) * rowSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [FlowRow] {
        guard width > 0 else {
            return []
        }

        var rows = [FlowRow]()
        var currentItems = [FlowItem]()
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = currentItems.isEmpty
                ? size.width
                : currentWidth + spacing + size.width

            if proposedWidth > width, !currentItems.isEmpty {
                rows.append(FlowRow(items: currentItems, height: currentHeight))
                currentItems = [FlowItem(index: index, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(FlowItem(index: index, size: size))
                currentWidth = proposedWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(items: currentItems, height: currentHeight))
        }

        return rows
    }

    private struct FlowItem {
        let index: Int
        let size: CGSize
    }

    private struct FlowRow {
        let items: [FlowItem]
        let height: CGFloat
    }
}
