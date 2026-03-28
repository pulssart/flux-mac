import SwiftUI
import WidgetKit

private struct SignalWidgetSnapshot: Codable, Identifiable {
    struct Outcome: Codable, Hashable {
        let label: String
        let percentage: Int
    }

    let id: String
    let title: String
    let subtitle: String
    let category: String
    let volume: String
    let commentCount: Int
    let endDate: Date?
    let url: URL
    let imageURL: URL?
    let isBinary: Bool
    let outcomes: [Outcome]
}

private enum SignalWidgetShared {
    static let appGroupId = "group.com.adriendonot.fluxapp"
    static let dataDirectory = "Library/Application Support/widget-data"
    static let favoritesFileName = "favoriteSignals.json"
    static let widgetKind = "FavoriteSignalWidgetV2"

    static func sharedDataDirectoryURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else {
            return nil
        }
        return containerURL.appendingPathComponent(dataDirectory, isDirectory: true)
    }
}

struct SignalWidgetSyncView: View {
    @Environment(FeedService.self) private var feedService
    @Environment(PolymarketService.self) private var polymarket
    @State private var lastSignature: String = ""
    @State private var isWriting = false

    var body: some View {
        Color.clear
            .task { await exportIfNeeded(reason: "appear") }
            .onChange(of: polymarket.events) { _, _ in
                Task { await exportIfNeeded(reason: "events-change") }
            }
            .onChange(of: polymarket.favoriteEventIds) { _, _ in
                Task { await exportIfNeeded(reason: "favorites-change") }
            }
            .onChange(of: polymarket.lastFetchedAt) { _, _ in
                Task { await exportIfNeeded(reason: "refresh-date-change") }
            }
    }

    private func exportIfNeeded(reason: String) async {
        let favoriteIds = Set(feedService.syncedSignalFavoriteEventIds())
        let favoriteSignals = polymarket.favoriteEvents
            .filter { favoriteIds.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.volume == rhs.volume {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.volume > rhs.volume
            }

        let signature = buildSignature(signals: favoriteSignals, favoriteIds: favoriteIds)
        guard signature != lastSignature else { return }
        await writeSignals(favoriteSignals)
        await MainActor.run { lastSignature = signature }
        WidgetCenter.shared.reloadTimelines(ofKind: SignalWidgetShared.widgetKind)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func buildSignature(signals: [PolymarketEvent], favoriteIds: Set<String>) -> String {
        let signalPart = signals.map { signal in
            let topOutcomes = signal.topOutcomes.prefix(3).map { "\($0.name):\($0.percentage)" }.joined(separator: ",")
            let imagePart = signal.imageURL?.absoluteString ?? ""
            let endDatePart = signal.endDate?.timeIntervalSince1970 ?? 0
            return "\(signal.id)|\(signal.volume)|\(signal.commentCount)|\(topOutcomes)|\(imagePart)|\(endDatePart)"
        }
        .joined(separator: "||")
        let datePart = polymarket.lastFetchedAt?.timeIntervalSince1970 ?? 0
        let favoritesPart = favoriteIds.sorted().joined(separator: ",")
        return "d=\(datePart)|f=\(favoritesPart)|s=\(signalPart)"
    }

    private func writeSignals(_ signals: [PolymarketEvent]) async {
        guard isWriting == false else { return }
        isWriting = true
        defer { isWriting = false }

        do {
            let snapshots = signals.map(makeSnapshot)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(snapshots)

            guard let dir = SignalWidgetShared.sharedDataDirectoryURL() else { return }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(SignalWidgetShared.favoritesFileName, isDirectory: false)
            try data.write(to: url, options: .atomic)
        } catch {
            #if DEBUG
            print("[SignalWidgetSync] Failed to write signals: \(error)")
            #endif
        }
    }

    private func makeSnapshot(from event: PolymarketEvent) -> SignalWidgetSnapshot {
        let outcomes: [SignalWidgetSnapshot.Outcome]
        if event.isBinary, let market = event.leadMarket {
            outcomes = [
                .init(label: "Oui", percentage: market.yesPercentage),
                .init(label: "Non", percentage: market.noPercentage)
            ]
        } else {
            outcomes = Array(event.topOutcomes.prefix(4)).map {
                .init(label: $0.name, percentage: $0.percentage)
            }
        }

        return SignalWidgetSnapshot(
            id: event.id,
            title: event.title,
            subtitle: event.description,
            category: event.primaryTag ?? "Signal",
            volume: event.formattedVolume,
            commentCount: event.commentCount,
            endDate: event.endDate,
            url: event.polymarketURL,
            imageURL: event.imageURL,
            isBinary: event.isBinary,
            outcomes: outcomes
        )
    }
}
