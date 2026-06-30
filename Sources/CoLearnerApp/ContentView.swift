import CoLearnerCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @State private var isDropTargeted = false
    @State private var isLeftPaneVisible = true
    @State private var isRightPaneVisible = true
    @AppStorage("colearnerThemeMode") private var themeModeRaw = CLThemeMode.system.rawValue
    @AppStorage("colearnerInterfaceScale") private var interfaceScale = 1.0
    @AppStorage("colearnerChatFontSize") private var chatFontSize = 14.0
    @AppStorage("colearnerChatFontChoice") private var chatFontChoiceRaw = CLChatFontChoice.system.rawValue

    var body: some View {
        VStack(spacing: 0) {
            AppTitleBar(
                title: title,
                meta: meta,
                hasDocument: viewModel.hasDocument,
                isLeftPaneVisible: isLeftPaneVisible,
                isRightPaneVisible: isRightPaneVisible,
                readingMode: viewModel.readingMode,
                themeMode: themeMode,
                onToggleLeftPane: { withAnimation(.easeInOut(duration: 0.2)) { isLeftPaneVisible.toggle() } },
                onToggleRightPane: toggleRightPane,
                onSelectReadingMode: selectReadingMode(_:),
                onToggleTheme: toggleTheme
            )

            HSplitView {
                if viewModel.hasDocument, isLeftPaneVisible {
                    DocumentSidebar(viewModel: viewModel) {
                        isRightPaneVisible = true
                    }
                        .frame(
                            minWidth: CLMetric.leftPaneMinWidth,
                            idealWidth: CLMetric.leftPaneWidth,
                            maxWidth: CLMetric.leftPaneMaxWidth,
                            maxHeight: .infinity
                        )
                }

                ReaderPane(
                    viewModel: viewModel,
                    isDropTargeted: isDropTargeted,
                    onRequestCompanion: {
                        selectReadingMode(.companion)
                    }
                )
                .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)

                if viewModel.hasDocument, isRightPaneVisible, viewModel.readingMode == .companion {
                    AssistantPanel(viewModel: viewModel)
                        .frame(
                            minWidth: CLMetric.rightPaneMinWidth,
                            idealWidth: CLMetric.rightPaneWidth,
                            maxWidth: CLMetric.rightPaneMaxWidth,
                            maxHeight: .infinity
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: isRightPaneVisible)
            .animation(.easeInOut(duration: 0.2), value: viewModel.readingMode)
        }
        .background(CLColor.desk)
        .environment(\.clInterfaceScale, CGFloat(interfaceScale))
        .environment(\.clChatFontSize, CGFloat(chatFontSize))
        .environment(\.clChatFontChoice, chatFontChoice)
        .preferredColorScheme(themeMode.colorScheme)
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $isDropTargeted,
            perform: handleDrop(providers:)
        )
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let droppedURL: URL? = if let data = item as? Data {
                URL(dataRepresentation: data, relativeTo: nil)
            } else if let url = item as? URL {
                url
            } else {
                nil
            }

            Task { @MainActor in
                _ = viewModel.handleDroppedFileURLs(droppedURL.map { [$0] } ?? [])
            }
        }

        return true
    }

    private var title: String {
        viewModel.hasDocument ? viewModel.documentTitle : "CoLearner"
    }

    private var meta: String {
        viewModel.hasDocument
            ? "p. \(viewModel.currentPageIndex + 1) of \(max(viewModel.pageCount, 1))"
            : "no document open"
    }

    private func toggleTheme() {
        themeModeRaw = (themeMode == .dark ? CLThemeMode.light : .dark).rawValue
    }

    private func toggleRightPane() {
        if viewModel.readingMode == .companion {
            isRightPaneVisible.toggle()
            if !isRightPaneVisible {
                viewModel.setReadingMode(.selfStudy)
            }
            return
        }

        isRightPaneVisible = true
        viewModel.setReadingMode(.companion)
    }

    private func selectReadingMode(_ mode: ReaderMode) {
        viewModel.setReadingMode(mode)
        if mode == .companion {
            isRightPaneVisible = true
        }
    }

    private var themeMode: CLThemeMode {
        CLThemeMode(rawValue: themeModeRaw) ?? .system
    }

    private var chatFontChoice: CLChatFontChoice {
        CLChatFontChoice(rawValue: chatFontChoiceRaw) ?? .system
    }
}

private struct AppTitleBar: View {
    let title: String
    let meta: String
    let hasDocument: Bool
    let isLeftPaneVisible: Bool
    let isRightPaneVisible: Bool
    let readingMode: ReaderMode
    let themeMode: CLThemeMode
    let onToggleLeftPane: () -> Void
    let onToggleRightPane: () -> Void
    let onSelectReadingMode: (ReaderMode) -> Void
    let onToggleTheme: () -> Void
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        HStack(spacing: 0) {
            // Left cluster
            HStack(spacing: 6) {
                CLToolbarIconButton(
                    systemImage: "sidebar.left",
                    title: "Toggle outline",
                    isActive: isLeftPaneVisible,
                    isDisabled: !hasDocument,
                    action: onToggleLeftPane
                )
            }
            .frame(width: 130 * interfaceScale, alignment: .leading)

            Spacer()

            // Center: title + meta
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13 * interfaceScale, weight: .semibold))
                    .foregroundStyle(CLColor.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 11 * interfaceScale, design: .monospaced))
                        .foregroundStyle(CLColor.ink3)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()

            // Right cluster
            HStack(spacing: 6) {
                if hasDocument {
                    readerModePicker
                }
                CLToolbarIconButton(
                    systemImage: themeMode.iconName,
                    title: "Theme: \(themeMode.label)",
                    isActive: themeMode != .system,
                    action: onToggleTheme
                )
                CLToolbarIconButton(
                    systemImage: "sidebar.right",
                    title: "Toggle AI companion",
                    isActive: isRightPaneVisible && readingMode == .companion,
                    isDisabled: !hasDocument,
                    action: onToggleRightPane
                )
            }
            .frame(width: 130 * interfaceScale, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: CLMetric.titleBarHeight * interfaceScale)
        .clMaterialBar()
        .overlay(alignment: .bottom) {
            CLDivider(.horizontal)
        }
    }

    private var readerModePicker: some View {
        Picker(
            "Reader mode",
            selection: Binding(
                get: { readingMode },
                set: { onSelectReadingMode($0) }
            )
        ) {
            ForEach(ReaderMode.allCases) { mode in
                Label(mode.label, systemImage: mode.systemImage)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 170 * interfaceScale)
    }
}
