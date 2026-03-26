import SwiftUI
import SwiftData

struct NotesView: View {
    @Environment(FeedService.self) private var feedService
    @State private var selectedNoteId: UUID?
    @State private var searchText: String = ""

    private var platformBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #elseif os(iOS)
        Color(uiColor: .systemBackground)
        #endif
    }

    private var notes: [ReaderNote] {
        feedService.readerNotes.sorted { $0.createdAt > $1.createdAt }
    }

    private var filteredNotes: [ReaderNote] {
        guard !searchText.isEmpty else { return notes }
        let query = searchText.lowercased()
        return notes.filter {
            $0.selectedText.lowercased().contains(query)
            || $0.articleTitle.lowercased().contains(query)
            || ($0.articleSource?.lowercased().contains(query) ?? false)
        }
    }

    private var selectedNote: ReaderNote? {
        guard let id = selectedNoteId else { return filteredNotes.first }
        return filteredNotes.first { $0.id == id }
    }

    var body: some View {
        notesRootView
            .background(platformBackgroundColor)
            #if os(macOS)
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            #endif
            .onAppear {
                if selectedNoteId == nil, let first = notes.first {
                    selectedNoteId = first.id
                }
            }
    }

    @ViewBuilder
    private var notesRootView: some View {
        #if os(macOS)
        HSplitView {
            noteListColumn
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)

            noteDetailColumn
                .frame(minWidth: 360)
        }
        #else
        NavigationSplitView {
            noteListColumn
                .navigationTitle("Notes")
        } detail: {
            noteDetailColumn
                .navigationTitle(selectedNote == nil ? "Notes" : "Detail")
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationSplitViewStyle(.balanced)
        #endif
    }

    private var canUseGlassSearchBackground: Bool {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            return true
        }
        #elseif os(iOS)
        if #available(iOS 26.0, *) {
            return true
        }
        #endif
        return false
    }

    @ViewBuilder
    private var searchBackground: some View {
        if canUseGlassSearchBackground {
            RoundedRectangle(cornerRadius: 10)
                .glassEffect(.regular.tint(.clear), in: RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var noteListContent: some View {
        if filteredNotes.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: searchText.isEmpty ? "note.text" : "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.quaternary)
                Text(searchText.isEmpty ? "No notes yet" : "No results")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(filteredNotes, selection: $selectedNoteId) { note in
                noteListRow(note)
                    .tag(note.id)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(platformBackgroundColor)
        }
    }

    // MARK: - Left Column

    private var noteListColumn: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                TextField("Search notes…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(searchBackground)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().padding(.horizontal, 14)

            noteListContent
        }
    }

    private func noteListRow(_ note: ReaderNote) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Small artwork
            if let imageURL = note.articleImageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        smallPlaceholder
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                smallPlaceholder
                    .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(note.selectedText)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Text(note.articleTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(note.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contextMenu {
            Button("Copy") {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(note.selectedText, forType: .string)
                #endif
            }
            Divider()
            Button("Delete", role: .destructive) {
                deleteNote(note)
            }
        }
    }

    private var smallPlaceholder: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(.quaternary.opacity(0.3))
            .overlay {
                Image(systemName: "note.text")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
    }

    // MARK: - Right Column

    private var noteDetailColumn: some View {
        Group {
            if let note = selectedNote {
                noteDetailView(note)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "note.text")
                        .font(.system(size: 44))
                        .foregroundStyle(.quaternary)
                    Text("Select a note")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func noteDetailView(_ note: ReaderNote) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Article image hero
                if let imageURL = note.articleImageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)
                                .clipped()
                        default:
                            detailImagePlaceholder
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                } else {
                    detailImagePlaceholder
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                }

                // Article title + source
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.articleTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)

                    if let source = note.articleSource, !source.isEmpty {
                        Text(source)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(note.createdAt, format: .dateTime.day().month(.wide).year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)

                Divider()
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)

                // The note text
                VStack(alignment: .leading, spacing: 0) {
                    Text("\u{201C}\(note.selectedText)\u{201D}")
                        .font(.system(size: 26))
                        .fontDesign(.serif)
                        .foregroundStyle(.primary)
                        .lineSpacing(8)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)

                Divider()
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        #if os(macOS)
                        NSWorkspace.shared.open(note.articleURL)
                        #endif
                    } label: {
                        Label("Open article", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        #if os(macOS)
                        let text = "\u{201C}\(note.selectedText)\u{201D}\n\n\u{2014} \(note.articleTitle)\n\(note.articleURL.absoluteString)"
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        if let window = NSApp.keyWindow {
                            let picker = NSSharingServicePicker(items: [text])
                            let buttonFrame = NSRect(x: window.frame.midX, y: window.frame.midY, width: 1, height: 1)
                            picker.show(relativeTo: buttonFrame, of: window.contentView!, preferredEdge: .minY)
                        }
                        #endif
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(role: .destructive) {
                        deleteNote(note)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }

    private var detailImagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(.quaternary.opacity(0.15))
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .overlay {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.quaternary)
            }
    }

    // MARK: - Actions

    private func deleteNote(_ note: ReaderNote) {
        let wasSelected = selectedNoteId == note.id
        withAnimation(.easeInOut(duration: 0.2)) {
            feedService.deleteReaderNote(note)
        }
        if wasSelected {
            selectedNoteId = filteredNotes.first(where: { $0.id != note.id })?.id
        }
    }
}
