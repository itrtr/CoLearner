import SwiftUI

struct DocumentSidebar: View {
    @ObservedObject var viewModel: ReaderViewModel
    var onOpenCompanion: () -> Void = {}
    @Environment(\.clInterfaceScale) private var interfaceScale
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            CLDivider(.horizontal)
            search
            CLDivider(.horizontal)
            ScrollView {
                VStack(spacing: 0) {
                    searchResultsSection
                    outlineSection
                    notesSection
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            DisplaySettingsPanel()
        }
        .background(CLColor.window)
        .onChange(of: viewModel.searchFieldFocusToken) { _, _ in
            isSearchFocused = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.documentTitle)
                .font(.system(size: 13 * interfaceScale, weight: .semibold))
                .foregroundStyle(CLColor.ink)
                .lineLimit(2)

            Text(viewModel.documentMeta)
                .font(.system(size: 11 * interfaceScale, design: .monospaced))
                .foregroundStyle(CLColor.ink3)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var search: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12 * interfaceScale, weight: .medium))
                .foregroundStyle(CLColor.ink3)

            TextField("Search document", text: searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12 * interfaceScale))
                .foregroundStyle(CLColor.ink)
                .focused($isSearchFocused)
                .onSubmit {
                    viewModel.searchDocument()
                }

            if viewModel.documentSearchQuery.isEmpty {
                Text("⌘F")
                    .font(.system(size: 10 * interfaceScale, design: .monospaced))
                    .foregroundStyle(CLColor.ink4)
                    .padding(.horizontal, 5)
                    .frame(height: 16 * interfaceScale)
                    .background(CLColor.hover)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Button {
                    viewModel.clearDocumentSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12 * interfaceScale, weight: .medium))
                        .foregroundStyle(CLColor.ink3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26 * interfaceScale)
        .background(CLColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(CLColor.border2, lineWidth: 0.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var searchText: Binding<String> {
        Binding(
            get: { viewModel.documentSearchQuery },
            set: { viewModel.documentSearchQuery = $0 }
        )
    }

    private var searchResultsSection: some View {
        VStack(spacing: 0) {
            if !viewModel.documentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                CLSectionHeader(
                    title: "Search results",
                    trailing: "\(viewModel.documentSearchResults.count)"
                )

                if viewModel.documentSearchResults.isEmpty {
                    EmptySidebarRow(
                        systemImage: "doc.text.magnifyingglass",
                        title: "Press Return to search"
                    )
                } else {
                    ForEach(viewModel.documentSearchResults.prefix(20)) { result in
                        SidebarSearchResultRow(
                            result: result,
                            isSelected: result.id == viewModel.selectedSearchResultID
                        ) {
                            viewModel.navigateToSearchResult(result)
                        }
                    }
                }
            }
        }
    }

    private var outlineSection: some View {
        VStack(spacing: 0) {
            CLSectionHeader(title: "Outline", trailing: "\(viewModel.documentMapItems.count) items")

            if viewModel.documentMapItems.isEmpty {
                EmptySidebarRow(
                    systemImage: "doc.text.magnifyingglass",
                    title: "No outline found"
                )
            } else {
                ForEach(viewModel.documentMapItems) { item in
                    SidebarOutlineRow(
                        item: item,
                        isSelected: item.id == viewModel.selectedMapItemID
                    ) {
                        viewModel.selectMapItem(item)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(spacing: 0) {
            CLSectionHeader(title: "Highlights & Notes", trailing: "\(viewModel.savedNotes.count)")

            if viewModel.savedNotes.isEmpty {
                EmptySidebarRow(systemImage: "note.text", title: "Document notes appear here")
            } else {
                ForEach(viewModel.savedNotes.prefix(6)) { note in
                    SidebarNoteRow(note: note) {
                        onOpenCompanion()
                        viewModel.navigateToNote(note)
                    }
                }
            }
        }
    }
}

private struct SidebarSearchResultRow: View {
    let result: DocumentSearchResult
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10.5 * interfaceScale, weight: .medium))
                    Text("p.\(result.pageIndex + 1)")
                        .font(.system(size: 10.5 * interfaceScale, weight: .semibold, design: .monospaced))
                    Spacer()
                }
                .foregroundStyle(isSelected ? CLColor.accentInk : CLColor.ink3)

                Text(result.excerpt)
                    .font(.system(size: 11.5 * interfaceScale))
                    .foregroundStyle(isSelected ? CLColor.accentInk : CLColor.ink2)
                    .lineLimit(3)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? CLColor.selected : CLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? CLColor.accentEdge : CLColor.border, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}

private struct SidebarOutlineRow: View {
    let item: DocumentMapItem
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(sectionNumber)
                    .font(.system(size: 11 * interfaceScale, design: .monospaced))
                    .foregroundStyle(CLColor.ink3)
                    .frame(width: 30, alignment: .leading)

                Text(item.title)
                    .font(.system(size: 12 * interfaceScale, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? CLColor.accentInk : CLColor.ink2)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text("\(item.pageIndex + 1)")
                    .font(.system(size: 11 * interfaceScale, design: .monospaced))
                    .foregroundStyle(CLColor.ink3)
            }
            .frame(height: CLMetric.rowHeight * interfaceScale)
            .padding(.leading, CGFloat(8 + item.level * 12))
            .padding(.trailing, 8)
            .background(isSelected ? CLColor.selected : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var sectionNumber: String {
        let firstWord = item.title.split(separator: " ").first.map(String.init) ?? ""
        return firstWord.range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) == nil
            ? ""
            : firstWord
    }
}

private struct SidebarNoteRow: View {
    let note: LearningNote
    let action: () -> Void
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Capsule()
                        .fill(CLColor.accent)
                        .frame(width: 3, height: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\"\(note.body)\"")
                            .font(.system(size: 11.5 * interfaceScale, design: .serif))
                            .foregroundStyle(CLColor.ink2)
                            .lineLimit(3)

                        HStack(spacing: 5) {
                            if let sourcePageIndex = note.sourcePageIndex {
                                Text("p.\(sourcePageIndex + 1)")
                            }
                            Text(note.sourceExcerpt ?? note.sourceTitle)
                                .lineLimit(1)
                        }
                        .font(.system(size: 11 * interfaceScale, design: .monospaced))
                        .foregroundStyle(CLColor.ink3)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(CLColor.border, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .help("Jump to the note source")
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}

private struct EmptySidebarRow: View {
    let systemImage: String
    let title: String
    @Environment(\.clInterfaceScale) private var interfaceScale

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12 * interfaceScale))
                .foregroundStyle(CLColor.ink3)
            Text(title)
                .font(.system(size: 12 * interfaceScale))
                .foregroundStyle(CLColor.ink3)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
