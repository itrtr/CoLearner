import AppKit
import SwiftUI

struct ReaderPane: View {
    @ObservedObject var viewModel: ReaderViewModel
    let isDropTargeted: Bool
    let onRequestCompanion: () -> Void
    @State private var pageEntry = ""
    @State private var selectionPulse = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.hasDocument {
                toolbar
                CLDivider(.horizontal)
            }

            ZStack {
                if viewModel.document != nil {
                    PDFReaderView(
                        document: viewModel.document,
                        navigationTarget: viewModel.navigationTarget,
                        searchNavigationTarget: viewModel.searchNavigationTarget,
                        highlightRequest: viewModel.highlightRequest,
                        userHighlightRequest: viewModel.userHighlightRequest,
                        displayState: viewModel.pdfDisplayState,
                        onSelectionChange: viewModel.updateSelection(text:),
                        onPageChange: viewModel.updateCurrentPage(index:)
                    )
                    .background(CLColor.paper)
                } else {
                    emptyState
                }

                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(CLColor.accent, style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
                        .padding(24)
                }

                if viewModel.readingMode == .selfStudy,
                   viewModel.selectedSelection != nil {
                    selfModeSelectionPrompt
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing)
                                    .combined(with: .opacity)
                                    .combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)),
                                removal: .opacity
                                    .combined(with: .move(edge: .trailing))
                                    .combined(with: .scale(scale: 0.92, anchor: .bottomTrailing))
                            )
                        )
                }
            }
            .background(CLColor.paper)
            .animation(.spring(response: 0.42, dampingFraction: 0.78), value: viewModel.selectedSelection != nil)
        }
        .background(CLColor.paper)
        .onAppear {
            syncPageEntry()
        }
        .onChange(of: viewModel.currentPageIndex) { _, _ in
            syncPageEntry()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                CLToolbarIconButton(systemImage: "folder", title: "Open file") {
                    viewModel.presentOpenPanel()
                }
                CLToolbarIconButton(systemImage: "square.and.arrow.down", title: "Save annotated copy") {
                    viewModel.exportAnnotatedPDF()
                }
            }

            CLDivider(.vertical)
                .frame(height: 20)

            HStack(spacing: 4) {
                CLToolbarIconButton(
                    systemImage: "chevron.left",
                    title: "Previous page",
                    isDisabled: viewModel.currentPageIndex <= 0
                ) {
                    viewModel.navigateRelativePage(by: -1)
                }

                TextField("Page", text: $pageEntry)
                    .textFieldStyle(.plain)
                    .font(CLFont.meta)
                    .foregroundStyle(CLColor.ink)
                    .multilineTextAlignment(.center)
                    .frame(width: 36, height: 24)
                    .background(CLColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(CLColor.border2, lineWidth: 0.5)
                    }
                    .onSubmit {
                        commitPageEntry()
                    }

                Text("/ \(max(viewModel.pageCount, 1))")
                    .font(CLFont.meta)
                    .foregroundStyle(CLColor.ink3)

                CLToolbarIconButton(
                    systemImage: "chevron.right",
                    title: "Next page",
                    isDisabled: viewModel.currentPageIndex >= max(viewModel.pageCount - 1, 0)
                ) {
                    viewModel.navigateRelativePage(by: 1)
                }
            }

            HStack(spacing: 4) {
                Menu {
                    ForEach(UserHighlightColor.allCases) { color in
                        Button {
                            viewModel.selectedUserHighlightColor = color
                        } label: {
                            Label(color.label, systemImage: color == viewModel.selectedUserHighlightColor ? "checkmark.circle.fill" : "circle")
                        }
                    }
                } label: {
                    Circle()
                        .fill(Color(nsColor: NSColor.clHex(viewModel.selectedUserHighlightColor.hexValue)))
                        .frame(width: 15, height: 15)
                        .overlay {
                            Circle()
                                .stroke(CLColor.borderStrong, lineWidth: 0.5)
                        }
                        .frame(width: 26, height: 26)
                        .background(CLColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(CLColor.border2, lineWidth: 0.5)
                        }
                }
                .menuStyle(.borderlessButton)
                .help("Highlight color")

                Button {
                    viewModel.applyUserHighlight()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "highlighter")
                            .font(.system(size: 12, weight: .medium))
                        Text("Highlight")
                            .font(.system(size: 11.5))
                    }
                    .foregroundStyle(viewModel.selectedSelection == nil ? CLColor.ink4 : CLColor.ink2)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(CLColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(CLColor.border2, lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.selectedSelection == nil)
                .opacity(viewModel.selectedSelection == nil ? 0.45 : 1)
                .help("Apply user highlight to selected text")
            }

            Button {
                viewModel.setAIHighlightsVisible(!viewModel.showsAIHighlights)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "highlighter")
                        .font(.system(size: 12, weight: .medium))
                    Text("AI highlights")
                        .font(.system(size: 11.5))
                }
                .foregroundStyle(viewModel.showsAIHighlights ? CLColor.accentInk : CLColor.ink2)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(viewModel.showsAIHighlights ? CLColor.selected : CLColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(viewModel.showsAIHighlights ? CLColor.accentEdge : CLColor.border2, lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.availableAIHighlights.isEmpty)
            .opacity(viewModel.availableAIHighlights.isEmpty ? 0.45 : 1)

            CLDivider(.vertical)
                .frame(height: 20)

            HStack(spacing: 4) {
                CLToolbarIconButton(systemImage: "minus.magnifyingglass", title: "Zoom out") {
                    viewModel.zoomPDF(by: -0.1)
                }

                Button("Fit") {
                    viewModel.resetPDFFit()
                }
                .buttonStyle(CLGhostButtonStyle())
                .frame(height: 26)

                CLToolbarIconButton(systemImage: "plus.magnifyingglass", title: "Zoom in") {
                    viewModel.zoomPDF(by: 0.1)
                }

                Menu {
                    ForEach(PDFLayoutMode.allCases) { mode in
                        Button {
                            viewModel.setPDFLayoutMode(mode)
                        } label: {
                            Label(mode.label, systemImage: mode.systemImage)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: viewModel.pdfDisplayState.layoutMode.systemImage)
                        Text(viewModel.pdfDisplayState.layoutMode.label)
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(CLColor.ink2)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(CLColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(CLColor.border2, lineWidth: 0.5)
                    }
                }
                .menuStyle(.borderlessButton)
            }

            Spacer()

            if let errorMessage = viewModel.errorMessage {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(errorMessage)
                }
                    .font(CLFont.meta)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: CLMetric.toolbarHeight)
        .background(CLColor.window)
    }

    private func syncPageEntry() {
        pageEntry = "\(viewModel.currentPageIndex + 1)"
    }

    private func commitPageEntry() {
        guard let pageNumber = Int(pageEntry.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            syncPageEntry()
            return
        }

        viewModel.navigateToPage(index: pageNumber - 1)
        syncPageEntry()
    }

    private var selfModeSelectionPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                ZStack {
                    // Pulsing halo behind the selection marker.
                    Circle()
                        .fill(CLColor.accent.opacity(0.35))
                        .frame(width: 18, height: 18)
                        .scaleEffect(selectionPulse ? 1.35 : 0.85)
                        .opacity(selectionPulse ? 0 : 0.8)
                        .animation(
                            .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                            value: selectionPulse
                        )
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CLColor.accent)
                        .frame(width: 16, height: 16)
                }
                .frame(width: 18, height: 18)

                Text("Selection ready")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(CLColor.ink)
                Spacer()
            }

            Text("Keep reading, or ask the companion about this selected text.")
                .font(CLFont.bodySmall)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Ask Companion") {
                    onRequestCompanion()
                }
                .buttonStyle(CLPrimaryButtonStyle())

                Button("Use as note source") {
                    viewModel.setReadingMode(.companion)
                    viewModel.startNoteFromContext()
                    onRequestCompanion()
                }
                .buttonStyle(CLGhostButtonStyle())
            }
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
        .background(CLColor.window)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(CLColor.border2, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(18)
        .onAppear { selectionPulse = true }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(CLColor.surface)
                    .frame(width: 108, height: 132)
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)

                VStack(spacing: 10) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(CLColor.accent)
                    Rectangle()
                        .fill(CLColor.border2)
                        .frame(width: 54, height: 2)
                    Rectangle()
                        .fill(CLColor.border)
                        .frame(width: 42, height: 2)
                }
            }

            VStack(spacing: 6) {
                Text("Open a PDF to start reading")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CLColor.ink)

                Text("Drop a paper, book, or notes PDF here. CoLearner will extract pages, outline context, and prepare the AI companion.")
                    .font(CLFont.body)
                    .foregroundStyle(CLColor.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            Button {
                viewModel.presentOpenPanel()
            } label: {
                Label("Choose PDF", systemImage: "folder")
            }
            .buttonStyle(CLPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CLColor.paper)
    }
}

