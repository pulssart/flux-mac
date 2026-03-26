// NotesWidgetSync.swift
// Exporte les notes vers l'App Group pour le widget et déclenche le rafraîchissement

import SwiftUI
import WidgetKit

// Snapshot JSON identique à celui lu par l'extension de widgets
private struct ReaderNoteSnapshot: Codable, Identifiable {
    let id: UUID
    let articleTitle: String
    let articleURL: URL
    let articleImageURL: URL?
    let articleSource: String?
    let articlePublishedAt: Date?
    let selectedText: String
    let createdAt: Date
}

private enum NotesWidgetShared {
    static let appGroupId = "group.com.adriendonot.fluxapp"
    static let dataDirectory = "Library/Application Support/widget-data"
    static let notesFileName = "notes.json"
    static let widgetKindV2 = "NotesWidgetV2"
    static let widgetKindV3 = "NotesWidgetV3"

    static func sharedDataDirectoryURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            return nil
        }
        return containerURL.appendingPathComponent(dataDirectory, isDirectory: true)
    }
}

struct NotesWidgetSyncView: View {
    @Environment(FeedService.self) private var feedService
    @State private var lastSignature: String = ""
    @State private var isWriting = false

    var body: some View {
        Color.clear
            .task { await exportIfNeeded(reason: "appear") }
            .onChange(of: feedService.readerNotesCount) { _, _ in
                Task { await exportIfNeeded(reason: "count-change") }
            }
    }

    private func exportIfNeeded(reason: String) async {
        // Capture snapshot des notes
        let notes = feedService.readerNotes
            .sorted { $0.createdAt > $1.createdAt }
        let signature = buildSignature(notes)
        guard signature != lastSignature else { return }
        await writeNotes(notes)
        await MainActor.run { lastSignature = signature }
        WidgetCenter.shared.reloadTimelines(ofKind: NotesWidgetShared.widgetKindV2)
        WidgetCenter.shared.reloadTimelines(ofKind: NotesWidgetShared.widgetKindV3)
    }

    private func buildSignature(_ notes: [ReaderNote]) -> String {
        guard let newest = notes.first else { return "empty" }
        return "c=\(notes.count)|t=\(newest.createdAt.timeIntervalSince1970)|id=\(newest.id.uuidString)"
    }

    private func writeNotes(_ notes: [ReaderNote]) async {
        guard isWriting == false else { return }
        isWriting = true
        defer { isWriting = false }

        do {
            let snapshots: [ReaderNoteSnapshot] = notes.map { n in
                ReaderNoteSnapshot(
                    id: n.id,
                    articleTitle: n.articleTitle,
                    articleURL: n.articleURL,
                    articleImageURL: n.articleImageURL,
                    articleSource: n.articleSource,
                    articlePublishedAt: n.articlePublishedAt,
                    selectedText: n.selectedText,
                    createdAt: n.createdAt
                )
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(snapshots)

            guard let dir = NotesWidgetShared.sharedDataDirectoryURL() else { return }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(NotesWidgetShared.notesFileName, isDirectory: false)
            try data.write(to: url, options: .atomic)
        } catch {
            // Silencieux: le widget affichera simplement un état vide si l'écriture échoue
            #if DEBUG
            print("[NotesWidgetSync] Failed to write notes: \(error)")
            #endif
        }
    }
}
