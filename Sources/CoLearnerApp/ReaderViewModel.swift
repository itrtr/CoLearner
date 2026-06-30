import AppKit
import CoLearnerCore
import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published private(set) var document: PDFDocument?
    @Published private(set) var documentURL: URL?
    @Published private(set) var selectedSelection: ReadingSelection?
    @Published private(set) var response: StudyResponse?
    @Published private(set) var isResponding = false
    @Published private(set) var selectedProvider: StudyAgentProvider
    @Published private(set) var documentMapItems = [DocumentMapItem]()
    @Published private(set) var documentIndex = DocumentContextIndex.empty
    @Published private(set) var currentPageIndex = 0
    @Published private(set) var navigationTarget: PDFNavigationTarget?
    @Published private(set) var searchNavigationTarget: PDFSearchNavigationTarget?
    @Published private(set) var highlightRequest: PDFHighlightRequest?
    @Published private(set) var userHighlightRequest: PDFUserHighlightRequest?
    @Published private(set) var showsAIHighlights = false
    @Published private(set) var availableAIHighlights = [String]()
    @Published private(set) var readingMode: ReaderMode = .selfStudy
    @Published private(set) var pdfDisplayState = PDFDisplayState()
    @Published private(set) var documentSearchResults = [DocumentSearchResult]()
    @Published private(set) var selectedSearchResultID: DocumentSearchResult.ID?
    @Published var selectedMapItemID: DocumentMapItem.ID?
    @Published var selectedContextScope: ChatContextScope = .currentPage
    @Published var selectedMode: StudyMode = .explain
    @Published var selectedCompanionTab: CompanionTab = .chat
    @Published var chatDraft = ""
    @Published var draftNote = ""
    @Published var documentSearchQuery = ""
    @Published var searchFieldFocusToken = 0
    @Published var selectedUserHighlightColor: UserHighlightColor = .yellow
    @Published private(set) var chatMessages = [ChatMessage]()
    @Published private(set) var savedNotes = [LearningNote]()
    @Published var errorMessage: String?

    private let agentFactory: @Sendable (StudyAgentProvider) -> any StudyAgent
    private let sessionManager: OAuthSessionManager
    private var chatTask: Task<Void, Never>?
    private let providerDefaultsKey = "selectedStudyAgentProvider"
    private let notesDefaultsKeyPrefix = "savedLearningNotes"
    private let maxContextCharacters = 60_000

    @Published private(set) var signedInProviders = Set<OAuthProvider>()
    @Published var pendingOAuthSignIn: OAuthProvider?
    @Published private(set) var selectedClaudeModel: String = DirectAnthropicStudyAgent.defaultModel
    @Published private(set) var selectedCodexModel: String = DirectOpenAIStudyAgent.defaultModel

    private let claudeModelDefaultsKey = "selectedClaudeModelID"
    private let codexModelDefaultsKey = "selectedCodexModelID"
    private static let lastDocumentDefaultsKey = "lastOpenedDocumentPath"

    init(
        sessionManager: OAuthSessionManager? = nil,
        agentFactory: (@Sendable (StudyAgentProvider) -> any StudyAgent)? = nil
    ) {
        let resolvedSessionManager = sessionManager ?? OAuthSessionManager(
            store: FileCredentialStore(),
            urlOpener: { url in
                Task { @MainActor in
                    NSWorkspace.shared.open(url)
                }
            }
        )
        self.sessionManager = resolvedSessionManager
        self.agentFactory = agentFactory ?? { provider in
            provider.makeStudyAgent()
        }

        if let savedProvider = UserDefaults.standard.string(forKey: providerDefaultsKey),
           let provider = StudyAgentProvider(rawValue: savedProvider) {
            selectedProvider = provider
        } else {
            selectedProvider = .local
        }

        if let notesData = UserDefaults.standard.data(forKey: notesDefaultsKeyPrefix),
           let decodedNotes = try? JSONDecoder().decode([LearningNote].self, from: notesData) {
            savedNotes = decodedNotes
        }

        if let storedClaude = UserDefaults.standard.string(forKey: claudeModelDefaultsKey),
           DirectAnthropicStudyAgent.availableModels.contains(where: { $0.id == storedClaude }) {
            selectedClaudeModel = storedClaude
        }
        if let storedCodex = UserDefaults.standard.string(forKey: codexModelDefaultsKey),
           DirectOpenAIStudyAgent.availableModels.contains(where: { $0.id == storedCodex }) {
            selectedCodexModel = storedCodex
        }

        Task { [weak self] in
            await self?.refreshSignedInState()
        }

        reopenLastDocumentIfAvailable()
    }

    func selectClaudeModel(_ id: String) {
        guard DirectAnthropicStudyAgent.availableModels.contains(where: { $0.id == id }) else {
            return
        }
        selectedClaudeModel = id
        UserDefaults.standard.set(id, forKey: claudeModelDefaultsKey)
    }

    func selectCodexModel(_ id: String) {
        guard DirectOpenAIStudyAgent.availableModels.contains(where: { $0.id == id }) else {
            return
        }
        selectedCodexModel = id
        UserDefaults.standard.set(id, forKey: codexModelDefaultsKey)
    }

    func selectedModelLabel(for provider: StudyAgentProvider) -> String? {
        switch provider {
        case .claude:
            DirectAnthropicStudyAgent.availableModels
                .first { $0.id == selectedClaudeModel }?
                .label
        case .codex:
            DirectOpenAIStudyAgent.availableModels
                .first { $0.id == selectedCodexModel }?
                .label
        case .local, .openCode, .pi, .hermes:
            nil
        }
    }

    private func makeAgent(for provider: StudyAgentProvider) -> any StudyAgent {
        switch provider {
        case .claude:
            DirectAnthropicStudyAgent(
                sessionManager: sessionManager,
                model: selectedClaudeModel
            )
        case .codex:
            DirectOpenAIStudyAgent(
                sessionManager: sessionManager,
                model: selectedCodexModel
            )
        case .local, .openCode, .pi, .hermes:
            agentFactory(provider)
        }
    }

    func refreshSignedInState() async {
        var providers = Set<OAuthProvider>()
        for provider in OAuthProvider.allCases {
            if await sessionManager.isSignedIn(provider) {
                providers.insert(provider)
            }
        }
        signedInProviders = providers
    }

    func providerRequiresOAuth(_ provider: StudyAgentProvider) -> OAuthProvider? {
        switch provider {
        case .claude: .anthropic
        case .codex: .openai
        case .local, .openCode, .pi, .hermes: nil
        }
    }

    func signIn(_ provider: OAuthProvider) {
        pendingOAuthSignIn = provider
        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.pendingOAuthSignIn = nil } }
            do {
                _ = try await self.sessionManager.signIn(provider)
                await self.refreshSignedInState()
                await MainActor.run { self.errorMessage = nil }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func signOut(_ provider: OAuthProvider) {
        Task { [weak self] in
            guard let self else { return }
            try? await self.sessionManager.signOut(provider)
            await self.refreshSignedInState()
        }
    }

    var documentTitle: String {
        documentURL?.deletingPathExtension().lastPathComponent ?? "Untitled document"
    }

    var hasDocument: Bool {
        document != nil
    }

    var pageCount: Int {
        document?.pageCount ?? 0
    }

    var documentMeta: String {
        guard let document else {
            return "No document open"
        }

        let pageLabel = document.pageCount == 1 ? "1 page" : "\(document.pageCount) pages"
        let sectionLabel = documentMapItems.count == 1
            ? "1 outline item"
            : "\(documentMapItems.count) outline items"
        return "\(pageLabel) · \(sectionLabel)"
    }

    var selectedTextPreview: String? {
        selectedSelection?.excerpt
    }

    var selectedMapItem: DocumentMapItem? {
        documentMapItems.first { $0.id == selectedMapItemID }
    }

    var activeContextTitle: String {
        resolvedChatContext()?.title ?? "No context"
    }

    var responseStatusText: String {
        switch selectedContextScope {
        case .selectedPassage:
            "Reading selected text"
        case .currentPage:
            "Reading page \(currentPageIndex + 1)"
        case .currentSection:
            "Reading \(selectedMapItem?.title ?? "current section")"
        case .fullDocument:
            "Searching the document index"
        }
    }

    var assistantCapabilitySummary: String {
        switch selectedProvider {
        case .local:
            "Fast offline helper. Good for instant summaries, examples, quizzes, and highlight suggestions."
        case .codex:
            "Directly calls the ChatGPT API using your subscription sign-in. Good for deeper reasoning over the active PDF context."
        case .claude:
            "Directly calls the Anthropic API using your Claude subscription sign-in. Good for explanatory, tutor-style responses."
        case .openCode:
            "Uses your OpenCode setup. Good when OpenCode has your preferred model/account."
        case .pi:
            "Uses your Pi CLI setup. Good for quick conversational explanations."
        case .hermes:
            "Uses your Hermes setup. Good for local agent workflows if configured."
        }
    }

    var selectedProviderDisplayName: String {
        selectedProvider == .local ? "Local offline helper" : selectedProvider.label
    }

    var hasActiveConversation: Bool {
        chatMessages.contains { $0.role == .user }
    }

    var activeContextExplanation: String {
        switch selectedContextScope {
        case .selectedPassage:
            if let selectedSelection {
                return "Only the selected passage is sent. It is \(selectedSelection.text.count) characters long."
            }

            return "Select text in the PDF to use Selection. Selection never auto-starts AI."
        case .currentPage:
            return "The assistant will read page \(currentPageIndex + 1) only."
        case .currentSection:
            let title = selectedMapItem?.title ?? "the nearest outline section"
            return "The assistant will read \(title) and stop at the next peer section."
        case .fullDocument:
            return "The assistant searches the extracted document index and sends the most relevant chunks."
        }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a PDF to read with CoLearner."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        openPDF(at: url)
    }

    func exportAnnotatedPDF() {
        guard let document else {
            errorMessage = "Open a PDF before saving annotations."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(documentTitle)-annotated.pdf"
        panel.message = "Save a copy with the current PDF annotations."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        guard document.write(to: url) else {
            errorMessage = "Could not save annotated PDF."
            return
        }

        errorMessage = nil
    }

    func openPDF(at url: URL) {
        guard let loadedDocument = PDFDocument(url: url) else {
            errorMessage = "Could not open \(url.lastPathComponent)."
            return
        }

        chatTask?.cancel()
        document = loadedDocument
        documentURL = url
        UserDefaults.standard.set(url.path, forKey: Self.lastDocumentDefaultsKey)
        selectedSelection = nil
        response = nil
        isResponding = false
        showsAIHighlights = false
        availableAIHighlights = []
        readingMode = .selfStudy
        currentPageIndex = 0
        navigationTarget = nil
        searchNavigationTarget = nil
        pdfDisplayState = PDFDisplayState()
        documentSearchQuery = ""
        documentSearchResults = []
        selectedSearchResultID = nil
        documentMapItems = PDFDocumentContextExtractor.mapItems(from: loadedDocument)
        documentIndex = PDFDocumentContextExtractor.contextIndex(
            from: loadedDocument,
            mapItems: documentMapItems
        )
        highlightRequest = nil
        userHighlightRequest = nil
        loadNotesForCurrentDocument()
        selectedMapItemID = PDFDocumentContextExtractor
            .nearestMapItem(in: documentMapItems, pageIndex: 0)?
            .id
        selectedContextScope = .currentPage
        errorMessage = nil
        chatMessages = [
            ChatMessage(
                role: .assistant,
                text: "Document ready. Read in Self mode, or switch to Companion when you want to ask about a selection, page, section, or the whole document.",
                contextTitle: documentTitle
            )
        ]
    }

    func handleDroppedFileURLs(_ urls: [URL]) -> Bool {
        guard let pdfURL = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else {
            errorMessage = "Drop a PDF file to open it."
            return false
        }

        openPDF(at: pdfURL)
        return true
    }

    func updateSelection(text: String) {
        let selection = ReadingSelection(text: text, sourceTitle: documentTitle)
        guard !selection.isEmpty else {
            selectedSelection = nil
            // If scope was tied to a now-gone selection, restore a usable scope so Send stays enabled.
            if selectedContextScope == .selectedPassage {
                selectedContextScope = .currentPage
            }
            return
        }

        guard selection.text != selectedSelection?.text else {
            return
        }

        // Don't auto-switch scope. Selection is a follow-up affordance the user explicitly
        // opts into via the Selection chip or composer "Use selection" button.
        selectedSelection = selection
    }

    func updateCurrentPage(index: Int) {
        guard index >= 0, index != currentPageIndex else {
            return
        }

        currentPageIndex = index

        if selectedContextScope == .currentSection {
            selectedMapItemID = PDFDocumentContextExtractor
                .nearestMapItem(in: documentMapItems, pageIndex: index)?
                .id
        }
    }

    func selectProvider(_ provider: StudyAgentProvider) {
        guard provider != selectedProvider else {
            return
        }

        selectedProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: providerDefaultsKey)
    }

    func setReadingMode(_ mode: ReaderMode) {
        guard mode != readingMode else {
            return
        }

        readingMode = mode
        // Don't auto-switch scope when entering Companion mode either — preserve the user's last choice.
    }

    func setPDFLayoutMode(_ mode: PDFLayoutMode) {
        var nextState = pdfDisplayState
        nextState.layoutMode = mode
        pdfDisplayState = nextState
    }

    func zoomPDF(by delta: CGFloat) {
        var nextState = pdfDisplayState
        nextState.fitsToWidth = false
        nextState.scaleFactor = min(max(nextState.scaleFactor + delta, 0.55), 2.4)
        pdfDisplayState = nextState
    }

    func resetPDFFit() {
        var nextState = pdfDisplayState
        nextState.fitsToWidth = true
        nextState.scaleFactor = 1
        pdfDisplayState = nextState
    }

    func searchDocument() {
        let query = documentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let document, !query.isEmpty else {
            documentSearchResults = []
            selectedSearchResultID = nil
            return
        }

        let matches = document.findString(
            query,
            withOptions: [.caseInsensitive, .diacriticInsensitive]
        )

        documentSearchResults = matches.prefix(80).compactMap { selection in
            guard let page = selection.pages.first else {
                return nil
            }

            let pageIndex = document.index(for: page)
            guard pageIndex >= 0 else {
                return nil
            }

            return DocumentSearchResult(
                query: query,
                excerpt: Self.searchExcerpt(from: selection.string, query: query),
                pageIndex: pageIndex
            )
        }
        selectedSearchResultID = documentSearchResults.first?.id

        if let firstResult = documentSearchResults.first {
            navigateToSearchResult(firstResult)
        }
    }

    func clearDocumentSearch() {
        documentSearchQuery = ""
        documentSearchResults = []
        selectedSearchResultID = nil
        searchNavigationTarget = nil
    }

    /// Bump a token the sidebar observes to programmatically focus the search field (⌘F).
    func focusSearchField() {
        searchFieldFocusToken += 1
    }

    /// Reopen the document that was open when the app last quit, if it still exists.
    func reopenLastDocumentIfAvailable() {
        guard let path = UserDefaults.standard.string(forKey: Self.lastDocumentDefaultsKey),
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            return
        }
        openPDF(at: URL(fileURLWithPath: path))
    }

    func navigateToSearchResult(_ result: DocumentSearchResult) {
        selectedSearchResultID = result.id
        currentPageIndex = result.pageIndex
        searchNavigationTarget = PDFSearchNavigationTarget(
            snippet: result.query,
            pageIndex: result.pageIndex
        )
    }

    func applyUserHighlight() {
        guard selectedSelection != nil else {
            errorMessage = "Select text before applying a highlight."
            return
        }

        userHighlightRequest = PDFUserHighlightRequest(color: selectedUserHighlightColor)
        saveSelectionHighlightNote(color: selectedUserHighlightColor)
    }

    func selectContextScope(_ scope: ChatContextScope) {
        selectedContextScope = scope

        if scope == .currentSection, selectedMapItem == nil {
            selectedMapItemID = PDFDocumentContextExtractor
                .nearestMapItem(in: documentMapItems, pageIndex: currentPageIndex)?
                .id
        }
    }

    func selectMapItem(_ item: DocumentMapItem) {
        selectedMapItemID = item.id
        selectedContextScope = .currentSection
        currentPageIndex = item.pageIndex
        navigationTarget = PDFNavigationTarget(pageIndex: item.pageIndex)
    }

    func requestResponse(mode: StudyMode) {
        selectedMode = mode
        sendChatMessage(text: prompt(for: mode))
    }

    func requestKeyPoints() {
        selectedMode = .explain
        sendChatMessage(
            text: "Find the key points in this \(selectedContextScope.label.lowercased()). Suggest the most important parts to highlight."
        )
    }

    func requestImportantHighlights() {
        selectedMode = .explain
        sendChatMessage(
            text: "Highlight the most important parts of this \(selectedContextScope.label.lowercased()) and explain why they matter."
        )
    }

    /// Prefill the composer with a study-mode template targeted at the current selection,
    /// switch scope to selection, and leave it to the user to refine and send.
    func draftSelectionPrompt(mode: StudyMode) {
        guard selectedSelection != nil else { return }
        selectedContextScope = .selectedPassage
        selectedMode = mode
        chatDraft = prompt(for: mode)
    }

    func draftSelectionKeyPoints() {
        guard selectedSelection != nil else { return }
        selectedContextScope = .selectedPassage
        selectedMode = .explain
        chatDraft = "Find the key points in this selection. Suggest the most important parts to highlight."
    }

    func draftSelectionHighlights() {
        guard selectedSelection != nil else { return }
        selectedContextScope = .selectedPassage
        selectedMode = .explain
        chatDraft = "Highlight the most important parts of this selection and explain why they matter."
    }

    func clearSelection() {
        selectedSelection = nil
        if selectedContextScope == .selectedPassage {
            selectedContextScope = .currentPage
        }
    }

    func cancelChat() {
        chatTask?.cancel()
        chatTask = nil
        chatMessages.removeAll { $0.isPending }
        isResponding = false
    }

    func resetChat() {
        chatTask?.cancel()
        isResponding = false
        response = nil
        errorMessage = nil
        chatDraft = ""
        showsAIHighlights = false
        availableAIHighlights = []
        highlightRequest = PDFHighlightRequest(snippets: [])
        chatMessages = hasDocument ? [
            ChatMessage(
                role: .assistant,
                text: "New chat started. Pick a context, then ask a question or use a quick action.",
                contextTitle: documentTitle
            )
        ] : []
    }

    func navigateRelativePage(by offset: Int) {
        navigateToPage(index: currentPageIndex + offset)
    }

    func navigateToPage(index: Int) {
        guard let document else {
            return
        }

        let boundedIndex = min(max(index, 0), max(document.pageCount - 1, 0))
        guard boundedIndex != currentPageIndex else {
            return
        }

        currentPageIndex = boundedIndex
        navigationTarget = PDFNavigationTarget(pageIndex: boundedIndex)
    }

    func setAIHighlightsVisible(_ isVisible: Bool) {
        showsAIHighlights = isVisible

        if isVisible {
            applyAvailableAIHighlights()
        } else {
            highlightRequest = PDFHighlightRequest(snippets: [])
        }
    }

    func contextTitle(for scope: ChatContextScope) -> String {
        switch scope {
        case .selectedPassage:
            selectedSelection == nil ? "none" : "active"
        case .currentPage:
            pageCount == 0 ? "none" : "p.\(currentPageIndex + 1)"
        case .currentSection:
            selectedMapItem?.title ?? PDFDocumentContextExtractor
                .nearestMapItem(in: documentMapItems, pageIndex: currentPageIndex)?
                .title ?? "none"
        case .fullDocument:
            documentIndex.chunks.isEmpty ? "indexing" : "graph-rag"
        }
    }

    func canUseContext(_ scope: ChatContextScope) -> Bool {
        switch scope {
        case .selectedPassage:
            selectedSelection != nil
        case .currentPage, .currentSection, .fullDocument:
            hasDocument
        }
    }

    func sendChatMessage() {
        sendChatMessage(text: chatDraft)
    }

    func sendChatMessage(text rawText: String) {
        let question = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            return
        }

        // If a selection is visible in the composer, attach it as the context for this send.
        // The user dismisses with the ✕ button on the selection card when they don't want it.
        if selectedSelection != nil, selectedContextScope != .selectedPassage {
            selectedContextScope = .selectedPassage
        }

        guard let context = resolvedChatContext(question: question) else {
            errorMessage = "Choose a document context before asking."
            return
        }

        chatTask?.cancel()
        chatDraft = ""
        errorMessage = nil

        let userMessage = ChatMessage(
            role: .user,
            text: question,
            contextTitle: context.title
        )
        let pendingMessage = ChatMessage(
            role: .assistant,
            text: "",
            contextTitle: context.title,
            isPending: true
        )
        let pendingID = pendingMessage.id

        chatMessages.append(userMessage)
        chatMessages.append(pendingMessage)
        isResponding = true

        let provider = selectedProvider
        let mode = selectedMode
        let agent = makeAgent(for: provider)
        let selection = ReadingSelection(text: context.text, sourceTitle: context.title)

        chatTask = Task { [weak self, agent] in
            guard let self else { return }
            var hasStartedStreaming = false
            var finalResponse: StudyResponse?

            do {
                let events = agent.stream(
                    to: selection,
                    mode: mode,
                    learnerQuestion: question
                )

                for try await event in events {
                    guard !Task.isCancelled else {
                        return
                    }

                    switch event {
                    case let .textDelta(chunk):
                        await MainActor.run {
                            self.appendStreamingChunk(chunk, to: pendingID, contextTitle: context.title, startedStreaming: &hasStartedStreaming)
                        }
                    case let .complete(response):
                        finalResponse = response
                    }
                }

                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    if let finalResponse {
                        self.response = finalResponse
                        let finalText = Self.chatText(from: finalResponse)
                        self.finalizeStreamingMessage(
                            id: pendingID,
                            text: finalText,
                            contextTitle: context.title
                        )
                        self.captureAIHighlights(finalResponse)
                    } else if !hasStartedStreaming {
                        self.replacePendingMessage(
                            id: pendingID,
                            with: ChatMessage(
                                role: .assistant,
                                text: "No response received.",
                                contextTitle: context.title,
                                isError: true
                            )
                        )
                    }
                    isResponding = false
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    replacePendingMessage(
                        id: pendingID,
                        with: ChatMessage(
                            role: .assistant,
                            text: error.localizedDescription,
                            contextTitle: context.title,
                            isError: true
                        )
                    )
                    errorMessage = error.localizedDescription
                    isResponding = false
                }
            }
        }
    }

    private func appendStreamingChunk(
        _ chunk: String,
        to id: ChatMessage.ID,
        contextTitle: String,
        startedStreaming: inout Bool
    ) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }

        if !startedStreaming {
            chatMessages[index].isPending = false
            chatMessages[index].text = chunk
            startedStreaming = true
        } else {
            chatMessages[index].text += chunk
        }
    }

    private func finalizeStreamingMessage(
        id: ChatMessage.ID,
        text: String,
        contextTitle: String
    ) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }

        chatMessages[index].isPending = false
        chatMessages[index].text = text
    }

    func saveCurrentInsight() {
        if let response {
            let note = LearningNote(
                title: response.title,
                body: response.summary,
                sourceExcerpt: response.sourceExcerpt,
                sourceTitle: documentTitle,
                sourcePageIndex: currentPageIndex
            )
            savedNotes.insert(note, at: 0)
            persistNotes()
            return
        }

        guard let lastAssistantMessage = chatMessages.last(where: { $0.role == .assistant && !$0.isPending }) else {
            return
        }

        let note = LearningNote(
            title: "Chat insight",
            body: lastAssistantMessage.text,
            sourceExcerpt: resolvedChatContext()?.title,
            sourceTitle: documentTitle,
            sourcePageIndex: currentPageIndex
        )
        savedNotes.insert(note, at: 0)
        persistNotes()
    }

    func saveDraftNote() {
        let noteBody = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !noteBody.isEmpty else {
            return
        }

        let note = LearningNote(
            title: Self.noteTitle(from: noteBody),
            body: noteBody,
            sourceExcerpt: resolvedChatContext()?.title,
            sourceTitle: documentTitle,
            sourcePageIndex: currentPageIndex
        )
        savedNotes.insert(note, at: 0)
        persistNotes()
        draftNote = ""
    }

    func startNoteFromContext() {
        guard let context = resolvedChatContext() else {
            return
        }

        let contextLine = "Context: \(context.title)"
        let currentNote = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        draftNote = currentNote.isEmpty
            ? "\(contextLine)\n\n"
            : "\(currentNote)\n\n\(contextLine)\n"
    }

    func highlightLatestResponse() {
        applyAvailableAIHighlights()
    }

    func discussHighlight(_ highlight: String) {
        let selection = ReadingSelection(text: highlight, sourceTitle: documentTitle)
        guard !selection.isEmpty else {
            return
        }

        selectedSelection = selection
        selectedContextScope = .selectedPassage
        readingMode = .companion
        sendChatMessage(text: "Why is this highlight important?")
    }

    func navigateToNote(_ note: LearningNote) {
        readingMode = .companion
        selectedCompanionTab = .notes

        if let sourcePageIndex = note.sourcePageIndex {
            navigateToPage(index: sourcePageIndex)
        }
    }

    func deleteNote(_ note: LearningNote) {
        savedNotes.removeAll { $0.id == note.id }
        persistNotes()
    }

    func resolvedChatContext(question: String? = nil) -> ResolvedChatContext? {
        guard let document else {
            return nil
        }

        switch selectedContextScope {
        case .selectedPassage:
            guard let selectedSelection, !selectedSelection.isEmpty else {
                return nil
            }
            return limitedContext(
                title: "Selection in \(documentTitle)",
                text: selectedSelection.text
            )
        case .currentPage:
            return limitedContext(
                title: "Page \(currentPageIndex + 1) in \(documentTitle)",
                text: PDFDocumentContextExtractor.textForPage(
                    in: document,
                    pageIndex: currentPageIndex
                )
            )
        case .currentSection:
            guard let item = selectedMapItem
                ?? PDFDocumentContextExtractor.nearestMapItem(
                    in: documentMapItems,
                    pageIndex: currentPageIndex
                ) else {
                return nil
            }

            return limitedContext(
                title: "\(item.title) (\(item.pageLabel))",
                text: PDFDocumentContextExtractor.textForSection(
                    in: document,
                    item: item,
                    mapItems: documentMapItems
                )
            )
        case .fullDocument:
            if let question,
               let relevantContext = documentIndex.relevantContext(
                    for: question,
                    maxCharacters: maxContextCharacters
               ) {
                return relevantContext
            }

            return limitedContext(
                title: "Full document: \(documentTitle)",
                text: PDFDocumentContextExtractor.fullText(in: document)
            )
        }
    }

    private func captureAIHighlights(_ response: StudyResponse) {
        var snippets = response.highlights
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 12 }

        // Fallback: if the tool call didn't populate highlights, extract quoted phrases
        // from the markdown answer. Models often quote the very phrases they want surfaced
        // (e.g. "key piece of text") even when they skip the tool's `highlights` array.
        if snippets.isEmpty, let answer = response.answerMarkdown {
            snippets = Self.extractQuotedPhrases(from: answer)
        }

        availableAIHighlights = snippets

        guard !snippets.isEmpty else { return }

        // Always show AI highlights when the model returns them — user can toggle off via toolbar.
        showsAIHighlights = true
        highlightRequest = PDFHighlightRequest(snippets: snippets)
    }

    private static func extractQuotedPhrases(from markdown: String) -> [String] {
        // Match double-quoted phrases (straight " " and curly " "), 12–240 chars long.
        let pattern = #"["\u{201C}]([^"\u{201D}]{12,240})["\u{201D}]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(markdown.startIndex..., in: markdown)

        var seen = Set<String>()
        var results: [String] = []
        regex.enumerateMatches(in: markdown, range: range) { match, _, _ in
            guard let match,
                  match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: markdown) else { return }
            let phrase = markdown[r].trimmingCharacters(in: .whitespacesAndNewlines)
            let key = phrase.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            results.append(phrase)
        }
        return Array(results.prefix(8))
    }

    private func applyAvailableAIHighlights() {
        guard !availableAIHighlights.isEmpty else {
            return
        }

        highlightRequest = PDFHighlightRequest(snippets: availableAIHighlights)
    }

    private func saveSelectionHighlightNote(color: UserHighlightColor) {
        guard let selectedSelection else {
            return
        }

        let note = LearningNote(
            title: "\(color.label) highlight",
            body: selectedSelection.text,
            sourceExcerpt: "User highlight · page \(currentPageIndex + 1)",
            sourceTitle: documentTitle,
            sourcePageIndex: currentPageIndex
        )
        savedNotes.insert(note, at: 0)
        persistNotes()
    }

    private func limitedContext(title: String, text: String) -> ResolvedChatContext? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        guard trimmedText.count > maxContextCharacters else {
            return ResolvedChatContext(title: title, text: trimmedText)
        }

        let endIndex = trimmedText.index(trimmedText.startIndex, offsetBy: maxContextCharacters)
        let limitedText = """
        \(trimmedText[..<endIndex])

        [CoLearner included the first \(maxContextCharacters) characters because this PDF context is large.]
        """

        return ResolvedChatContext(title: "\(title), truncated", text: limitedText)
    }

    private func replacePendingMessage(id: ChatMessage.ID, with message: ChatMessage) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            chatMessages.append(message)
            return
        }

        chatMessages[index] = message
    }

    private func prompt(for mode: StudyMode) -> String {
        switch mode {
        case .explain:
            "Explain this \(selectedContextScope.label.lowercased()) in plain terms."
        case .simplify:
            "Summarize this \(selectedContextScope.label.lowercased()) in three concise bullets."
        case .examples:
            "Give concrete examples that make this \(selectedContextScope.label.lowercased()) easy to understand."
        case .quiz:
            "Quiz me on this \(selectedContextScope.label.lowercased()) with short answers."
        }
    }

    private static func chatText(from response: StudyResponse) -> String {
        if let answerMarkdown = response.answerMarkdown?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !answerMarkdown.isEmpty {
            return answerMarkdown
        }

        var sections = [
            "## \(response.title)",
            response.summary
        ]

        if !response.keyIdeas.isEmpty {
            sections.append("""
            ### Key ideas
            \(response.keyIdeas.map { "- \($0)" }.joined(separator: "\n"))
            """)
        }

        if !response.examples.isEmpty {
            sections.append("""
            ### Examples
            \(response.examples.map { "- \($0)" }.joined(separator: "\n"))
            """)
        }

        if !response.nextQuestions.isEmpty {
            sections.append("""
            ### Questions
            \(response.nextQuestions.map { "- \($0)" }.joined(separator: "\n"))
            """)
        }

        return sections.joined(separator: "\n\n")
    }

    private static func noteTitle(from body: String) -> String {
        let firstMeaningfulLine = body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        guard let firstMeaningfulLine else {
            return "Reading note"
        }

        let maxTitleLength = 54
        guard firstMeaningfulLine.count > maxTitleLength else {
            return firstMeaningfulLine
        }

        return "\(firstMeaningfulLine.prefix(maxTitleLength))..."
    }

    private static func searchExcerpt(from rawText: String?, query: String) -> String {
        let text = rawText?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            ?? query

        guard text.count > 160 else {
            return text
        }

        return "\(text.prefix(157))..."
    }

    private func persistNotes() {
        guard let encodedNotes = try? JSONEncoder().encode(savedNotes) else {
            return
        }

        UserDefaults.standard.set(encodedNotes, forKey: notesDefaultsKey)
    }

    private func loadNotesForCurrentDocument() {
        if let notesData = UserDefaults.standard.data(forKey: notesDefaultsKey),
           let decodedNotes = try? JSONDecoder().decode([LearningNote].self, from: notesData) {
            savedNotes = decodedNotes
        } else {
            savedNotes = []
        }
    }

    private var notesDefaultsKey: String {
        guard let documentURL else {
            return notesDefaultsKeyPrefix
        }

        let fingerprint = documentURL.path
            .lowercased()
            .data(using: .utf8)?
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            ?? documentTitle

        return "\(notesDefaultsKeyPrefix).\(fingerprint)"
    }
}
