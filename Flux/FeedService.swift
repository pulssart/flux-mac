// FeedService.swift
// Gestion et ajout de flux RSS/Atom

import Foundation
import OSLog
import Observation
import SwiftData
extension Notification.Name {
    // NOTE: Removed duplicate web overlay names to avoid redeclaration
    // static let closeWebViewOverlay = Notification.Name("CloseWebViewOverlay")
    // static let openWebViewOverlay = Notification.Name("OpenWebViewOverlay")
}
#if canImport(AppKit)
import AppKit
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(UserNotifications)
@preconcurrency import UserNotifications
#endif
#if canImport(AVFoundation)
@preconcurrency import AVFoundation
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(WebKit)
import WebKit
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FeedKit)
import FeedKit
#endif

#if canImport(XMLKit)
import XMLKit
#endif

#if canImport(SwiftSoup)
import SwiftSoup
#endif

@Observable
@MainActor
final class FeedService {
    private enum WidgetSnapshotStore {
        static let appGroupId = "group.com.adriendonot.fluxapp"
        static let dataDirectory = "Library/Application Support/widget-data"
        static let feedsFileName = "feeds.json"
        static let latestByFeedFileName = "latestByFeed.json"
        static let feedDigestByFeedFileName = "feedDigestByFeed.json"
        static let wallArticlesFileName = "wallArticles.json"
        static let widgetKind = "DernierArticleWidgetSourceV2"
        static let feedDigestWidgetKind = "FeedDigestWidgetSourceV1"
        static let wallWidgetKind = "FluxWallWidgetV1"
        static let savedArticlesFileName = "savedArticles.json"
        static let readLaterWidgetKind = "ReadLaterWidgetV2"
        static let widgetKinds = [widgetKind, feedDigestWidgetKind, wallWidgetKind, readLaterWidgetKind]
        static let imageDirectory = "Library/Application Support/widget-data/images"
    }

    private struct WidgetFeedMeta: Codable {
        let id: UUID
        let title: String
    }

    private struct WidgetArticleSnapshot: Codable {
        let id: UUID
        let title: String
        let url: URL
        let imageURL: URL?
        let imageFileName: String?
        let feedTitle: String
        let publishedAt: Date?
        let isSaved: Bool
    }

    private struct WidgetFeedDigestSnapshot: Codable {
        let feedTitle: String
        let articles: [WidgetArticleSnapshot]
    }

    private struct WidgetImageJob: Sendable {
        let imageURL: URL
        let refererURL: URL
        let fileName: String
    }

    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "Flux", category: "FeedService")
#if canImport(WidgetKit)
    private var pendingWidgetReloadTask: Task<Void, Never>?
    private var lastWidgetReloadAt: Date?
#endif

    /// Cookie to bypass YouTube's GDPR consent screen (SOCS replaces the old CONSENT=YES+1)
    private static let youTubeConsentCookie = "SOCS=CAISEwgDEgk2MjcyOTU2NTQaAmVuIAEaBgiA_LiYBg"
    
    // Liste observable des flux
    var feeds: [Feed] = []
    // Liste observable des dossiers
    var folders: [Folder] = []
    // Liste observable des articles (tous flux confondus)
    var articles: [Article] = []
    // Liste observable des notes prises dans le lecteur
    var readerNotes: [ReaderNote] = []
    // Compteur de mise à jour pour forcer le re-render des badges (incrémenté à chaque changement de isRead)
    var badgeUpdateTrigger: Int = 0
    // Etat de chargement
    var isRefreshing: Bool = false
    private var suppressBadgeUpdates: Bool = false
    // Flux en cours de rafraîchissement (nil = tous)
    var refreshingFeedId: UUID? = nil
    // Permet d'interrompre un refresh global en cours quand un ajout de flux est prioritaire
    private var cancelGlobalRefresh: Bool = false
    // Verrou séparé pour le refresh ciblé (ajout de flux) — ne bloque pas / n'est pas bloqué par le global
    private var isSingleFeedRefreshing: Bool = false
    // Dernière actualisation (mur de flux)
    var lastRefreshAt: Date? = nil
    // Signal pour forcer la vue Découverte à se recalculer après ajout réel de nouveaux articles
    var discoveryRefreshTrigger: Int = 0
    // AI état
    var isGeneratingSummary: Bool = false
    // Newsletter (génération éditoriale)
    var isGeneratingNewsletter: Bool = false
    var newsletterContent: String? = nil
    var newsletterGeneratedAt: Date? = nil
    var newsletterHeroURL: URL? = nil
    var newsletterImageURLs: [URL] = []
    var newsletterArticleTitleImageMap: [String: URL] = [:] // articleTitle (keywords) -> imageURL
    var newsletterHeroIsAI: Bool = false
    // Envoi de newsletter supprimé
    // Article-level AI state
    var isGeneratingArticleSummary: Bool = false
    // UI binding pour ouvrir la feuille de réglages
    var showSettingsSheet: Bool = false
    // Message d'erreur AI pour l'UI
    var aiErrorMessage: String?
    #if canImport(AVFoundation)
    private var audioPlayer: AVAudioPlayer?
    // Overlay mini-player state
    var isAudioOverlayVisible: Bool = false
    var audioOverlayTitle: String? = nil
    var isAudioPlaying: Bool = false
    var audioOverlayIcon: URL? = nil
    var isAudioLoading: Bool = false
    var audioDuration: TimeInterval = 0
    var audioCurrentTime: TimeInterval = 0
    private var audioProgressTimer: Timer?
    private var refreshTimer: Timer?
    #endif
    // Lecture audio de la newsletter
    var isSpeakingNewsletter: Bool = false
    var isGeneratingNewsletterAudio: Bool = false
    var newsletterAudioURL: URL? = nil
    // Planification quotidienne (jusqu'à 3 créneaux)
    var showNewsletterScheduleSheet: Bool = false
    private var newsletterScheduleTimes: [DateComponents] = []
    private var newsletterTimers: [Timer] = []
    private var newsletterLastFiredSlots: Set<String> = []
    // Config AI décodée depuis Settings.aiProviderConfig
    private struct AIProviderConfig: Codable {
        let aiEnabled: Bool?
        let newsletterAudioEnabled: Bool?
    }
    
    init(context: ModelContext) {
        self.modelContext = context
        loadFeeds()
        loadFolders()
        loadArticles()
        loadReaderNotes()
        logger.info("FeedService init — feeds: \(self.feeds.count), articles: \(self.articles.count)")
        setupDefaultFeedsIfNeeded()
        scheduleAutoRefresh()
        Task { [weak self] in
            await self?.ensureFavicons()
        }
        loadNewsletterSchedule()
        scheduleNewsletterTimers()
    }
    
    /// Configure les flux par défaut lors de la première utilisation
    private func setupDefaultFeedsIfNeeded() {
        // Si des flux existent déjà, ne rien faire
        guard feeds.isEmpty else { return }
        
        appLog("[FeedService] First launch detected, adding default feeds...")
        
        // Flux par défaut
        let defaultFeeds = [
            ("The Verge", "https://www.theverge.com/rss/index.xml"),
            ("ScienceDaily", "https://www.sciencedaily.com/rss/all.xml"),
            ("Polygon", "https://www.polygon.com/rss/index.xml")
        ]
        
        Task {
            for (name, urlString) in defaultFeeds {
                do {
                    try await addFeed(from: urlString)
                    appLog("[FeedService] Added default feed: \(name)")
                } catch {
                    appLogWarning("[FeedService] Failed to add default feed '\(name)': \(error.localizedDescription)")
                }
            }
            appLog("[FeedService] Default feeds setup complete")
        }
    }
    
    private func loadFolders() {
        let byCreated = FetchDescriptor<Folder>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let raw = (try? modelContext.fetch(byCreated)) ?? []
        // Trier par sortIndex si présent, sinon par createdAt
        folders = raw.sorted { (a, b) in
            switch (a.sortIndex, b.sortIndex) {
            case let (la?, lb?): return la < lb
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt > b.createdAt
            }
        }
        logger.info("Loaded folders: \(self.folders.count)")
    }

    func addFolder(name: String) {
        let nextIndex = (folders.map { $0.sortIndex ?? Int.max }.compactMap { $0 }.max() ?? -1) + 1
        let folder = Folder(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Nouveau dossier" : name,
                            sortIndex: nextIndex,
                            createdAt: .now)
        modelContext.insert(folder)
        try? modelContext.save()
        loadFolders()
    }

    func renameFolder(_ folderId: UUID, to newName: String) {
        guard let folder = (try? modelContext.fetch(FetchDescriptor<Folder>()))?.first(where: { $0.id == folderId }) else { return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        folder.name = name
        try? modelContext.save()
        loadFolders()
    }

    func deleteFolder(_ folderId: UUID) {
        // Détacher les flux qui étaient dans ce dossier
        for f in feeds where f.folderId == folderId { f.folderId = nil }
        // Supprimer le dossier
        if let folder = (try? modelContext.fetch(FetchDescriptor<Folder>()))?.first(where: { $0.id == folderId }) {
            modelContext.delete(folder)
        }
        try? modelContext.save()
        loadFolders()
        loadFeeds()
    }

    func moveFeed(_ feedId: UUID, toFolder folderId: UUID?) {
        appLog("[FeedService] moveFeed called with feedId: \(feedId), toFolder: \(String(describing: folderId))")
        guard let feed = feeds.first(where: { $0.id == feedId }) else { appLogWarning("[FeedService] moveFeed: feed not found"); return }
        appLog("[FeedService] moveFeed: feed=\(feed.title)")
        // Empêcher de ranger des flux YouTube dans des dossiers (non affichés dans les dossiers)
        if let target = folderId {
            let host = (feed.siteURL?.host ?? feed.feedURL.host ?? "").lowercased()
            let isYouTube = host.contains("youtube.com") || host.contains("youtu.be")
            if isYouTube { appLogWarning("[FeedService] moveFeed: YouTube feed cannot be moved to folder"); return }
            // Assigner la cible et positionner en fin du groupe du dossier
            feed.folderId = target
            // Trouver l'index max actuel des flux de ce dossier
            let subset = feeds.filter { f in
                let h = (f.siteURL?.host ?? f.feedURL.host ?? "").lowercased()
                let isYT = h.contains("youtube.com") || h.contains("youtu.be")
                return f.folderId == target && !isYT
            }
            let maxIndex = subset.compactMap { $0.sortIndex }.max() ?? (feeds.compactMap { $0.sortIndex }.max() ?? -1)
            feed.sortIndex = maxIndex + 1
            appLog("[FeedService] moveFeed: moved to folder, new sortIndex=\(feed.sortIndex ?? -1)")
        } else {
            // Sortie du dossier: replacer en fin du groupe racine non-YouTube
            feed.folderId = nil
            let subset = feeds.filter { f in
                let h = (f.siteURL?.host ?? f.feedURL.host ?? "").lowercased()
                let isYT = h.contains("youtube.com") || h.contains("youtu.be")
                return f.folderId == nil && !isYT
            }
            let maxIndex = subset.compactMap { $0.sortIndex }.max() ?? (feeds.compactMap { $0.sortIndex }.max() ?? -1)
            feed.sortIndex = maxIndex + 1
            appLog("[FeedService] moveFeed: moved to root, new sortIndex=\(feed.sortIndex ?? -1)")
        }
        try? modelContext.save()
        loadFeeds()
    }

    func reorderFolders(fromOffsets: IndexSet, toOffset: Int) {
        guard !fromOffsets.isEmpty else { return }
        guard toOffset >= 0 && toOffset <= folders.count else { return }
        // Vérifier que tous les indices sont valides
        let maxIndex = folders.count - 1
        if fromOffsets.contains(where: { $0 < 0 || $0 > maxIndex }) { return }

        var newOrder = folders
        let sorted = fromOffsets.sorted()
        var target = toOffset
        target -= sorted.filter { $0 < toOffset }.count
        var movedItems: [Folder] = []
        for i in sorted.reversed() {
            let item = newOrder.remove(at: i)
            movedItems.insert(item, at: 0)
        }
        for (offset, item) in movedItems.enumerated() {
            newOrder.insert(item, at: target + offset)
        }
        for (idx, folder) in newOrder.enumerated() { folder.sortIndex = idx }
        folders = newOrder
        try? modelContext.save()
    }

    // Réordonne les flux à l'intérieur d'un dossier spécifique (hors YouTube)
    func reorderFeeds(inFolder folderId: UUID, fromOffsets: IndexSet, toOffset: Int) {
        // Construire le sous-ensemble: flux non-YouTube dans ce dossier
        let indicesAndFeeds: [(Int, Feed)] = feeds.enumerated().filter { index, feed in
            let host = (feed.siteURL?.host ?? feed.feedURL.host ?? "").lowercased()
            let isYouTube = host.contains("youtube.com") || host.contains("youtu.be")
            return feed.folderId == folderId && !isYouTube
        }
        guard !indicesAndFeeds.isEmpty else { return }

        var subsetFeeds: [Feed] = indicesAndFeeds.map { $0.1 }
        let maxIndex = subsetFeeds.count - 1
        if fromOffsets.contains(where: { $0 < 0 || $0 > maxIndex }) { return }
        guard toOffset >= 0 && toOffset <= subsetFeeds.count else { return }

        let sorted = fromOffsets.sorted()
        var target = toOffset
        target -= sorted.filter { $0 < toOffset }.count
        var moved: [Feed] = []
        for i in sorted.reversed() {
            let it = subsetFeeds.remove(at: i)
            moved.insert(it, at: 0)
        }
        for (offset, it) in moved.enumerated() {
            subsetFeeds.insert(it, at: target + offset)
        }

        // Reconstruire feeds en remplaçant uniquement les éléments de ce sous-ensemble
        let subsetPositions: [Int] = indicesAndFeeds.map { $0.0 }
        var result: [Feed] = []
        result.reserveCapacity(feeds.count)
        var subsetIterator = subsetFeeds.makeIterator()
        let subsetSet = Set(subsetPositions)
        for (idx, f) in feeds.enumerated() {
            if subsetSet.contains(idx) {
                if let next = subsetIterator.next() { result.append(next) } else { result.append(f) }
            } else {
                result.append(f)
            }
        }
        // Réassigner sortIndex global pour stabilité
        for (idx, feed) in result.enumerated() { feed.sortIndex = idx }
        feeds = result
        try? modelContext.save()
    }

    private func loadFeeds() {
        appLog("[FeedService] Loading feeds from database...")
        let byAdded = FetchDescriptor<Feed>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        let raw = (try? modelContext.fetch(byAdded)) ?? []
        appLog("[FeedService] Loaded \(raw.count) feeds")
        // Si sortIndex est présent, trier par celui-ci sinon retomber sur addedAt
        feeds = raw.sorted { (a, b) in
            switch (a.sortIndex, b.sortIndex) {
            case let (la?, lb?): return la < lb
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.addedAt > b.addedAt
            }
        }
        logger.info("Loaded feeds: \(self.feeds.count)")
        syncWidgetSnapshots()
    }

    func reorderFeeds(fromOffsets: IndexSet, toOffset: Int) {
        var newOrder = feeds
        let sorted = fromOffsets.sorted()
        var target = toOffset
        target -= sorted.filter { $0 < toOffset }.count
        var movedItems: [Feed] = []
        for i in sorted.reversed() {
            let item = newOrder.remove(at: i)
            movedItems.insert(item, at: 0)
        }
        for (offset, item) in movedItems.enumerated() {
            newOrder.insert(item, at: target + offset)
        }
        for (idx, feed) in newOrder.enumerated() { feed.sortIndex = idx }
        feeds = newOrder
        try? modelContext.save()
    }

    // Réordonne uniquement les flux NON-YouTube à la racine (Section "Mes Flux") en mappant correctement
    // les indices de section vers l'ordre global de `feeds`.
    func reorderNonYouTubeFeeds(fromOffsets: IndexSet, toOffset: Int) {
        // 1) Récupérer les indices globaux des items de la section "Mes Flux"
        let nonYouTubeIndicesAndFeeds: [(Int, Feed)] = feeds.enumerated().filter { index, feed in
            let host = (feed.siteURL?.host ?? feed.feedURL.host ?? "").lowercased()
            let isYouTube = host.contains("youtube.com") || host.contains("youtu.be")
            return !isYouTube && feed.folderId == nil
        }
        var subsetFeeds: [Feed] = nonYouTubeIndicesAndFeeds.map { $0.1 }

        // 2) Appliquer le déplacement à l'intérieur de ce sous-ensemble, en utilisant une logique stable
        let sorted = fromOffsets.sorted()
        var target = toOffset
        target -= sorted.filter { $0 < toOffset }.count
        var moved: [Feed] = []
        for i in sorted.reversed() {
            let it = subsetFeeds.remove(at: i)
            moved.insert(it, at: 0)
        }
        for (offset, it) in moved.enumerated() {
            subsetFeeds.insert(it, at: target + offset)
        }

        // 3) Reconstruire `feeds` en remplaçant uniquement les éléments de ce sous-ensemble
        let subsetPositions: [Int] = nonYouTubeIndicesAndFeeds.map { $0.0 }
        var result: [Feed] = []
        result.reserveCapacity(feeds.count)
        var subsetIterator = subsetFeeds.makeIterator()
        let subsetSet = Set(subsetPositions)
        for (idx, f) in feeds.enumerated() {
            if subsetSet.contains(idx) {
                if let next = subsetIterator.next() { result.append(next) } else { result.append(f) }
            } else {
                result.append(f)
            }
        }

        // 4) Réassigner des sortIndex contigus pour stabilité
        for (idx, feed) in result.enumerated() { feed.sortIndex = idx }
        feeds = result
        try? modelContext.save()
    }

    // Réordonne uniquement les flux YouTube en mappant correctement
    // les indices de section vers l'ordre global de `feeds`.
    func reorderYouTubeFeeds(fromOffsets: IndexSet, toOffset: Int) {
        // 1) Récupérer les indices globaux des items YouTube
        let ytIndicesAndFeeds: [(Int, Feed)] = feeds.enumerated().filter { index, feed in
            let host = (feed.siteURL?.host ?? feed.feedURL.host ?? "").lowercased()
            return host.contains("youtube.com") || host.contains("youtu.be")
        }
        var subsetFeeds: [Feed] = ytIndicesAndFeeds.map { $0.1 }

        // 2) Appliquer le déplacement à l'intérieur de ce sous-ensemble
        let sorted = fromOffsets.sorted()
        var target = toOffset
        target -= sorted.filter { $0 < toOffset }.count
        var moved: [Feed] = []
        for i in sorted.reversed() {
            let it = subsetFeeds.remove(at: i)
            moved.insert(it, at: 0)
        }
        for (offset, it) in moved.enumerated() {
            subsetFeeds.insert(it, at: target + offset)
        }

        // 3) Reconstruire `feeds` en remplaçant uniquement les éléments de ce sous-ensemble
        let subsetPositions: [Int] = ytIndicesAndFeeds.map { $0.0 }
        var result: [Feed] = []
        result.reserveCapacity(feeds.count)
        var subsetIterator = subsetFeeds.makeIterator()
        let subsetSet = Set(subsetPositions)
        for (idx, f) in feeds.enumerated() {
            if subsetSet.contains(idx) {
                if let next = subsetIterator.next() { result.append(next) } else { result.append(f) }
            } else {
                result.append(f)
            }
        }

        // 4) Réassigner des sortIndex contigus pour stabilité
        for (idx, feed) in result.enumerated() { feed.sortIndex = idx }
        feeds = result
        try? modelContext.save()
    }
    
    private func loadArticles() {
        let desc = FetchDescriptor<Article>(sortBy: [SortDescriptor(\.publishedAt, order: .reverse)])
        articles = (try? modelContext.fetch(desc)) ?? []
        logger.info("Loaded articles: \(self.articles.count)")
        if !suppressBadgeUpdates {
            updateAppBadge()
            syncWidgetSnapshots()
        }
    }

    private func loadReaderNotes() {
        let desc = FetchDescriptor<ReaderNote>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        readerNotes = (try? modelContext.fetch(desc)) ?? []
        logger.info("Loaded reader notes: \(self.readerNotes.count)")
    }

    private func syncWidgetSnapshots() {
        guard let dataDirectoryURL = Self.widgetDataDirectoryURL() else { return }

        let feedMeta = feeds.map { WidgetFeedMeta(id: $0.id, title: $0.title) }
        if let feedData = try? JSONEncoder().encode(feedMeta) {
            let feedsFileURL = dataDirectoryURL.appendingPathComponent(WidgetSnapshotStore.feedsFileName, isDirectory: false)
            try? feedData.write(to: feedsFileURL, options: .atomic)
        }

        let imageDirectoryURL = Self.widgetImagesDirectoryURL()
        var imageJobs: [WidgetImageJob] = []
        var latestByFeed: [String: WidgetArticleSnapshot] = [:]
        var digestByFeed: [String: WidgetFeedDigestSnapshot] = [:]
        for feed in feeds {
            let feedArticles = articles
                .filter({ $0.feedId == feed.id })
                .sorted(by: { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) })
            guard feedArticles.isEmpty == false else { continue }

            let articleSnapshots: [WidgetArticleSnapshot] = Array(feedArticles.prefix(4)).map { article in
                let imageFileName = article.imageURL.map { _ in "\(article.id.uuidString).jpg" }
                if
                    let imageURL = article.imageURL,
                    let imageFileName,
                    let imageDirectoryURL
                {
                    let fileURL = imageDirectoryURL.appendingPathComponent(imageFileName, isDirectory: false)
                    if FileManager.default.fileExists(atPath: fileURL.path) == false {
                        imageJobs.append(
                            WidgetImageJob(
                                imageURL: imageURL,
                                refererURL: article.url,
                                fileName: imageFileName
                            )
                        )
                    }
                }

                return WidgetArticleSnapshot(
                    id: article.id,
                    title: article.title,
                    url: article.url,
                    imageURL: article.imageURL,
                    imageFileName: imageFileName,
                    feedTitle: feed.title,
                    publishedAt: article.publishedAt,
                    isSaved: article.isSaved
                )
            }

            if let firstSnapshot = articleSnapshots.first {
                latestByFeed[feed.id.uuidString] = firstSnapshot
            }

            digestByFeed[feed.id.uuidString] = WidgetFeedDigestSnapshot(
                feedTitle: feed.title,
                articles: articleSnapshots
            )
        }

        if let latestData = try? JSONEncoder().encode(latestByFeed) {
            let latestFileURL = dataDirectoryURL.appendingPathComponent(
                WidgetSnapshotStore.latestByFeedFileName,
                isDirectory: false
            )
            try? latestData.write(to: latestFileURL, options: .atomic)
        }

        if let digestData = try? JSONEncoder().encode(digestByFeed) {
            let digestFileURL = dataDirectoryURL.appendingPathComponent(
                WidgetSnapshotStore.feedDigestByFeedFileName,
                isDirectory: false
            )
            try? digestData.write(to: digestFileURL, options: .atomic)
        }

        let musicFeedIDs = Set(
            feeds
                .filter { isMusicFeedURL($0.feedURL) || isMusicFeedURL($0.siteURL ?? $0.feedURL) }
                .map(\.id)
        )
        var seenWallURLs = Set<String>()
        let wallArticles: [WidgetArticleSnapshot] = articles
            .filter { !musicFeedIDs.contains($0.feedId) }
            .filter { article in
                let value = article.url.absoluteString.lowercased()
                return !(value.contains("youtube") && value.contains("/shorts/"))
            }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            .filter { article in
                seenWallURLs.insert(article.url.absoluteString).inserted
            }
            .prefix(10)
            .map { article in
                let feedTitle = feeds.first(where: { $0.id == article.feedId })?.title ?? ""
                let imageFileName = article.imageURL.map { _ in "\(article.id.uuidString).jpg" }
                if let imageURL = article.imageURL, let imageFileName, let imageDirectoryURL {
                    let fileURL = imageDirectoryURL.appendingPathComponent(imageFileName, isDirectory: false)
                    if !FileManager.default.fileExists(atPath: fileURL.path) {
                        imageJobs.append(WidgetImageJob(imageURL: imageURL, refererURL: article.url, fileName: imageFileName))
                    }
                }
                return WidgetArticleSnapshot(
                    id: article.id,
                    title: article.title,
                    url: article.url,
                    imageURL: article.imageURL,
                    imageFileName: imageFileName,
                    feedTitle: feedTitle,
                    publishedAt: article.publishedAt,
                    isSaved: article.isSaved
                )
            }
        if let wallData = try? JSONEncoder().encode(wallArticles) {
            let wallFileURL = dataDirectoryURL.appendingPathComponent(
                WidgetSnapshotStore.wallArticlesFileName,
                isDirectory: false
            )
            try? wallData.write(to: wallFileURL, options: .atomic)
        }

        // Saved articles (read later)
        let savedArticles: [WidgetArticleSnapshot] = articles
            .filter { $0.isSaved }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            .prefix(10)
            .map { article in
                let feedTitle = feeds.first(where: { $0.id == article.feedId })?.title ?? ""
                let imageFileName = article.imageURL.map { _ in "\(article.id.uuidString).jpg" }
                if let imageURL = article.imageURL, let imageFileName, let imageDirectoryURL {
                    let fileURL = imageDirectoryURL.appendingPathComponent(imageFileName, isDirectory: false)
                    if !FileManager.default.fileExists(atPath: fileURL.path) {
                        imageJobs.append(WidgetImageJob(imageURL: imageURL, refererURL: article.url, fileName: imageFileName))
                    }
                }
                return WidgetArticleSnapshot(
                    id: article.id, title: article.title, url: article.url,
                    imageURL: article.imageURL, imageFileName: imageFileName,
                    feedTitle: feedTitle, publishedAt: article.publishedAt, isSaved: true
                )
            }
        if let savedData = try? JSONEncoder().encode(savedArticles) {
            let savedFileURL = dataDirectoryURL.appendingPathComponent(WidgetSnapshotStore.savedArticlesFileName, isDirectory: false)
            try? savedData.write(to: savedFileURL, options: .atomic)
        }

        // Collect all image file names that are still referenced by widget snapshots
        var referencedFileNames = Set<String>()
        for snapshot in latestByFeed.values {
            if let name = snapshot.imageFileName { referencedFileNames.insert(name) }
        }
        for digest in digestByFeed.values {
            for article in digest.articles {
                if let name = article.imageFileName { referencedFileNames.insert(name) }
            }
        }
        for snapshot in wallArticles {
            if let name = snapshot.imageFileName { referencedFileNames.insert(name) }
        }
        for snapshot in savedArticles {
            if let name = snapshot.imageFileName { referencedFileNames.insert(name) }
        }

        // Purge orphaned widget images that are no longer used
        if let imageDirectoryURL {
            Self.purgeOrphanedWidgetImages(in: imageDirectoryURL, keeping: referencedFileNames)
        }

        appLog("[FeedService] Widget snapshots prepared: feeds=\(latestByFeed.count), digests=\(digestByFeed.count), wall=\(wallArticles.count), imageJobs=\(imageJobs.count)")
        scheduleWidgetTimelineReload(preferredDelay: 0.35)

        if imageJobs.isEmpty == false {
            // Download images FIRST, then reload once – avoids the race condition
            // where the widget wakes up before images are cached and the second
            // reloadTimelines call gets throttled by the system.
            scheduleWidgetImagePrefetch(imageJobs)
        }
    }

    private func scheduleWidgetImagePrefetch(_ jobs: [WidgetImageJob]) {
        guard jobs.isEmpty == false else { return }
        let uniqueJobs = Array(Dictionary(grouping: jobs, by: \.fileName).values.compactMap(\.first))
        Task(priority: .utility) {
            await Self.prefetchWidgetImages(uniqueJobs)
            scheduleWidgetTimelineReload(preferredDelay: 0.8)
        }
    }

    private func scheduleWidgetTimelineReload(preferredDelay: TimeInterval) {
#if canImport(WidgetKit)
        pendingWidgetReloadTask?.cancel()

        let minInterval: TimeInterval = 20
        let elapsed = Date().timeIntervalSince(lastWidgetReloadAt ?? .distantPast)
        let delay = max(preferredDelay, max(0, minInterval - elapsed))

        pendingWidgetReloadTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard let self, !Task.isCancelled else { return }
            for kind in WidgetSnapshotStore.widgetKinds {
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }
            lastWidgetReloadAt = Date()
            pendingWidgetReloadTask = nil
        }
#endif
    }

    private static func widgetImagesDirectoryURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroupId
        ) else {
            return nil
        }
        let directoryURL = containerURL.appendingPathComponent(
            WidgetSnapshotStore.imageDirectory,
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private static func widgetDataDirectoryURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroupId
        ) else {
            return nil
        }
        let directoryURL = containerURL.appendingPathComponent(
            WidgetSnapshotStore.dataDirectory,
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    /// Removes any cached widget image that is no longer referenced by current
    /// widget snapshots. Called every time snapshots are synced so only the
    /// images actually needed by today's widgets remain on disk.
    private static func purgeOrphanedWidgetImages(in directoryURL: URL, keeping referencedFileNames: Set<String>) {
        let fm = FileManager.default
        guard let allFiles = try? fm.contentsOfDirectory(atPath: directoryURL.path) else { return }

        var removedCount = 0
        for fileName in allFiles where !referencedFileNames.contains(fileName) {
            let fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
            try? fm.removeItem(at: fileURL)
            removedCount += 1
        }

        // Clean up legacy cache directory if it still exists
        if let containerURL = fm.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroupId) {
            let legacyDir = containerURL.appendingPathComponent("Library/Caches/widget-images", isDirectory: true)
            if fm.fileExists(atPath: legacyDir.path) {
                try? fm.removeItem(at: legacyDir)
                appLog("[FeedService] Removed legacy widget-images cache directory")
            }
        }

        if removedCount > 0 {
            appLog("[FeedService] Purged \(removedCount) orphaned widget images")
        }
    }

    private static let maxConcurrentImageDownloads = 6

    private static func prefetchWidgetImages(_ jobs: [WidgetImageJob]) async {
        guard let directoryURL = widgetImagesDirectoryURL() else { return }
        await withTaskGroup(of: Void.self) { group in
            for (index, job) in jobs.enumerated() {
                // Limit concurrency: wait for a slot before adding more
                if index >= maxConcurrentImageDownloads {
                    await group.next()
                }
                group.addTask {
                    guard !Task.isCancelled else { return }
                    await prefetchWidgetImage(job, directoryURL: directoryURL)
                }
            }
        }
    }

    private static func prefetchWidgetImage(_ job: WidgetImageJob, directoryURL: URL) async {
        guard let imageURL = normalizedWidgetImageURL(job.imageURL) else { return }

        var request = URLRequest(url: imageURL)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "image/avif,image/webp,image/jpeg,image/*;q=0.8,*/*;q=0.5",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(job.refererURL.absoluteString, forHTTPHeaderField: "Referer")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return
            }
            guard data.isEmpty == false else { return }
            let convertedData = convertWidgetImageToJPEGData(from: data) ?? data
            let fileURL = directoryURL.appendingPathComponent(job.fileName, isDirectory: false)
            try convertedData.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }

    private static func normalizedWidgetImageURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        guard url.scheme?.lowercased() == "http" else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url
    }

    private static func convertWidgetImageToJPEGData(from data: Data) -> Data? {
        #if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        if
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 800,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary
            )
        {
            let mutableData = NSMutableData()
            if let destination = CGImageDestinationCreateWithData(
                mutableData,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) {
                CGImageDestinationAddImage(
                    destination,
                    image,
                    [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
                )
                if CGImageDestinationFinalize(destination) {
                    return mutableData as Data
                }
            }
        }
        #endif

        #if canImport(AppKit)
        if
            let nsImage = NSImage(data: data),
            let tiff = nsImage.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        {
            return jpeg
        }
        #endif
        return data
    }

    // Télécharge des données de flux avec retry et délais plus tolérants (serveurs lents/CDN)
    // HTTPS uniquement (conforme ATS / Mac App Store)
    private func fetchFeedData(from url: URL) async throws -> Data {
        guard let targetURL = httpsOnlyURL(from: url) else {
            appLogWarning("[FeedService] Refused non-HTTPS URL: \(url.absoluteString)")
            throw FeedError.invalidURL
        }

        var request = URLRequest(url: targetURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.5", forHTTPHeaderField: "Accept")
        request.setValue(LocalizationManager.shared.currentLocale.identifier.replacingOccurrences(of: "_", with: "-"), forHTTPHeaderField: "Accept-Language")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)

        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    appLogWarning("[FeedService] HTTP \(http.statusCode) for \(targetURL.absoluteString)")
                    throw FeedError.invalidURL
                }
                appLog("[FeedService] Successfully fetched \(data.count) bytes from \(targetURL.absoluteString)")
                return data
            } catch {
                lastError = error
                // Retry seulement pour erreurs réseau temporaires (timeouts, perte de co, etc.)
                if let urlErr = error as? URLError,
                   [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .resourceUnavailable].contains(urlErr.code) {
                    let backoff: UInt64 = UInt64(800_000_000) * UInt64(1 << attempt) // 0.8s, 1.6s, 3.2s
                    try? await Task.sleep(nanoseconds: backoff)
                    continue
                }
                appLogWarning("[FeedService] Fetch error for \(targetURL.absoluteString): \(error.localizedDescription)")
                break
            }
        }

        if let error = lastError {
            appLogError("[FeedService] All fetch attempts failed: \(error.localizedDescription)")
        }
        throw lastError ?? FeedError.invalidURL
    }

    // Tente de découvrir l'URL d'un flux (RSS/Atom/JSON) à partir d'un domaine/page d'accueil
    private func discoverFeedURL(from site: URL) async -> URL? {
        guard let site = httpsOnlyURL(from: site) else { return nil }
        // 1) Télécharger la page d'accueil et inspecter les balises <link rel="alternate">
        do {
            var req = URLRequest(url: site)
            req.timeoutInterval = 15
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            if let html = String(data: data.prefix(1_200_000), encoding: .utf8) {
                #if canImport(SwiftSoup)
                do {
                    let doc = try SwiftSoup.parse(html)
                    // types courants: RSS/Atom/JSON Feed
                    let selectors = [
                        "link[rel=alternate][type=application/rss+xml]",
                        "link[rel=alternate][type=application/atom+xml]",
                        "link[rel=alternate][type=application/feed+json]",
                        "link[rel=alternate][type=application/json]"
                    ]
                    var candidates: [URL] = []
                    for sel in selectors {
                        for el in try doc.select(sel).array() {
                            if let href = try? el.attr("href"), !href.isEmpty,
                               let u = absolutizeURL(href, base: site) {
                                candidates.append(u)
                            }
                        }
                    }
                    if let u = await firstValidFeedURL(in: candidates) { return u }
                } catch { }
                #else
                do {
                    // Fallback sans SwiftSoup: extraction regex des <link rel="alternate" ... href="...">
                    let linkPattern = "<link[^>]*?rel\\s*=\\s*(?:\\\"alternate\\\"|'alternate')[^>]*?>"
                    let linkRegex = try NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive])
                    let hrefRegex = try NSRegularExpression(pattern: "href\\s*=\\s*(?:\\\"([^\\\"]+)\\\"|'([^']+)')", options: [.caseInsensitive])
                    let nsHTML = html as NSString
                    var rankedCandidates: [(url: URL, rank: Int)] = []
                    for match in linkRegex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length)) {
                        let tag = nsHTML.substring(with: match.range)
                        let nsTag = tag as NSString
                        if let m = hrefRegex.firstMatch(in: tag, options: [], range: NSRange(location: 0, length: nsTag.length)) {
                            let g1 = m.range(at: 1)
                            let g2 = m.range(at: 2)
                            if let r = Range(g1.location != NSNotFound ? g1 : g2, in: tag) {
                                let rawHref = String(tag[r])
                                if let u = absolutizeURL(htmlUnescape(rawHref), base: site) {
                                    let lowerTag = tag.lowercased()
                                    let rank: Int
                                    if lowerTag.contains("application/rss+xml") { rank = 0 }
                                    else if lowerTag.contains("application/atom+xml") { rank = 1 }
                                    else if lowerTag.contains("application/feed+json") || lowerTag.contains("application/json") { rank = 2 }
                                    else { rank = 3 }
                                    rankedCandidates.append((u, rank))
                                }
                            }
                        }
                    }
                    // Trier par préférence: RSS, Atom, JSON, puis autres
                    let candidates = rankedCandidates.sorted { $0.rank < $1.rank }.map { $0.url }
                    if let u = await firstValidFeedURL(in: candidates) { return u }
                } catch { }
                #endif
            }
        } catch { }

        // 2) Essayer des chemins connus (WordPress/Jekyll/Ghost/Hugo/Substack/Medium/etc.)
        let commonPaths: [String] = [
            // WordPress
            "/feed", "/feed/", "/rss", "/rss/", "/feed/rss", "/feed/rss/", "/feed/rss2", "/feed/atom",
            // Standards
            "/rss.xml", "/atom.xml", "/index.xml", "/feed.xml", "/rss/index.xml",
            // Jekyll/Hugo/Static
            "/blog/feed", "/blog/rss.xml", "/blog/atom.xml", "/blog/index.xml", "/blog/feed.xml",
            "/posts/feed", "/posts/rss.xml", "/articles/feed",
            // Substack
            "/feed",
            // Ghost
            "/rss/",
            // Medium
            "/feed/",
            // Autres variantes
            "/feeds", "/feeds/all.atom.xml", "/feeds/posts/default", "/feeds/rss",
            "/.rss", "/syndication.xml", "/news/feed", "/news/rss",
            "/actualites/feed", "/actualites/rss",
            // Feedburner
            "/feedburner.xml",
            // Variations additionnelles
            "/atom", "/atom/", "/main/rss", "/main/feed", "/rss2.xml"
        ]
        var urlComponents = URLComponents(url: site, resolvingAgainstBaseURL: false) ?? URLComponents()
        urlComponents.query = nil
        var origins: [URL] = []
        if let scheme = urlComponents.scheme, let host = urlComponents.host {
            origins.append(URL(string: "\(scheme)://\(host)")!)
            // ajouter www. variante si absente
            if !host.hasPrefix("www."), let u = URL(string: "\(scheme)://www.\(host)") { origins.append(u) }
        }
        var candidates: [URL] = []
        for origin in origins {
            for p in commonPaths {
                if let u = URL(string: p, relativeTo: origin)?.absoluteURL { candidates.append(u) }
            }
        }
        if let u = await firstValidFeedURL(in: candidates) { return u }
        return nil
    }

    private func isLikelyFeedURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        if isLegacyAppleRSSURL(url) { return true }
        if path.hasSuffix(".xml") || path.hasSuffix(".rss") || path.hasSuffix(".json") || path.hasSuffix("/xml") {
            return true
        }
        if path.contains("/feed/") || path.contains("/rss/") || path.contains("/atom/") || path.contains("/feeds/") {
            return true
        }
        let keywords = ["/feed", "/rss", "/atom", "/feeds"]
        return keywords.contains { path.hasSuffix($0) }
    }

    #if canImport(FeedKit)
    private func firstValidFeedURL(in candidates: [URL]) async -> URL? {
        for u in candidates {
            guard let candidate = httpsOnlyURL(from: u) else { continue }
            do {
                let data = try await fetchFeedData(from: candidate)
                _ = try FeedKit.Feed(data: data) // validation
                return candidate
            } catch {
                // Heuristique d'acceptation: RSS 1.0 (RDF) ou RSS plausible même si FeedKit échoue
                do {
                    let sample = try await fetchFeedData(from: candidate)
                    if let sniff = String(data: sample.prefix(4096), encoding: .utf8)
                        ?? String(data: sample.prefix(4096), encoding: .ascii)
                        ?? String(data: sample.prefix(4096), encoding: .isoLatin1) {
                        let lower = sniff.lowercased()
                        let looksLikeRSS10 = lower.contains("<rdf:rdf") || lower.contains("purl.org/rss/1.0")
                        let looksLikeRSS20 = lower.contains("<rss ") || lower.contains("<rss>")
                        let looksLikeAtom = lower.contains("<feed ") && lower.contains("xmlns=\"http://www.w3.org/2005/atom\"")
                        if looksLikeRSS10 || looksLikeRSS20 || looksLikeAtom {
                            return candidate
                        }
                    }
                } catch { }
                continue
            }
        }
        return nil
    }
    #else
    private func firstValidFeedURL(in candidates: [URL]) async -> URL? {
        // Sans FeedKit, retourner le premier candidat; l'appelant gérera ensuite
        return candidates.first.flatMap { httpsOnlyURL(from: $0) }
    }
    #endif

    // MARK: - YouTube helpers
    private func isYouTubeHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("youtube.com") || host.contains("youtu.be")
    }

    /// Result of YouTube URL resolution: RSS feed URL + optional channel title scraped from the page
    private struct YouTubeResolution {
        let feedURL: URL
        let channelTitle: String?
    }

    // Convertit une URL de chaîne YouTube (channel/user/@handle/\c) en URL de flux RSS officielle
    private func resolveYouTubeFeedURL(from url: URL) async -> YouTubeResolution? {
        guard isYouTubeHost(url) else { return nil }
        let path = url.path
        appLog("[FeedService] Resolving YouTube URL: \(url.absoluteString)")

        // Déjà un flux RSS
        if path.contains("/feeds/videos.xml") {
            appLogDebug("[FeedService] Already a RSS feed")
            return YouTubeResolution(feedURL: url, channelTitle: nil)
        }

        // Cas URLs vidéo/shorts/embed/youtu.be → passer par oEmbed pour retrouver la chaîne
        let lowerPath = path.lowercased()
        if lowerPath.contains("/watch") || lowerPath.contains("/shorts") || lowerPath.contains("/embed") || ((url.host ?? "").lowercased().contains("youtu.be")) {
            if let rss = await resolveYouTubeFeedViaOEmbed(from: url) {
                appLog("[FeedService] Resolved via oEmbed: \(rss.absoluteString)")
                return YouTubeResolution(feedURL: rss, channelTitle: nil)
            }
        }

        // /channel/UCxxxx
        if let range = path.range(of: "/channel/") {
            let id = String(path[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !id.isEmpty, let rss = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(id)") {
                appLog("[FeedService] Channel ID found: \(id), RSS URL: \(rss.absoluteString)")
                return YouTubeResolution(feedURL: rss, channelTitle: nil)
            }
        }

        // /user/username
        if let range = path.range(of: "/user/") {
            let user = String(path[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !user.isEmpty, let rss = URL(string: "https://www.youtube.com/feeds/videos.xml?user=\(user)") {
                appLog("[FeedService] User found: \(user), RSS URL: \(rss.absoluteString)")
                return YouTubeResolution(feedURL: rss, channelTitle: nil)
            }
        }

        // /@handle ou /c/customName -> récupérer UC id depuis la page
        if path.hasPrefix("/@") || path.hasPrefix("/c/") {
            // Nettoyer le path en retirant /videos, /about, etc.
            let cleanPath = path.replacingOccurrences(of: "/videos", with: "")
                .replacingOccurrences(of: "/about", with: "")
                .replacingOccurrences(of: "/live", with: "")
                .replacingOccurrences(of: "/shorts", with: "")
                .replacingOccurrences(of: "/community", with: "")
                .replacingOccurrences(of: "/playlists", with: "")

            appLog("[FeedService] Resolving handle/custom URL: \(cleanPath)")

            // Construire l'URL de base sans les suffixes
            let baseURL = URL(string: "https://www.youtube.com\(cleanPath)") ?? url

            // 1) Essai via redirection implicite vers /channel/UC…
            if let redirectedChannelId = await fetchYouTubeChannelIdFromRedirect(baseURL) {
                if let rss = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(redirectedChannelId)") {
                    appLog("[FeedService] Channel ID via redirect: \(redirectedChannelId)")
                    return YouTubeResolution(feedURL: rss, channelTitle: nil)
                }
            }

            // 2) Fallback: scraping robuste de la page
            let expectedHandle: String? = {
                if cleanPath.hasPrefix("/@") {
                    let after = String(cleanPath.dropFirst(2))
                    return after.split(separator: "/").first.map { String($0).lowercased() }
                }
                return nil
            }()
            let scrapeResult = await fetchYouTubeChannelId(from: baseURL, expectedHandle: expectedHandle)
            if let channelId = scrapeResult.channelId, let rss = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)") {
                appLog("[FeedService] Channel ID via scrape: \(channelId), RSS URL: \(rss.absoluteString), title: \(scrapeResult.channelTitle ?? "nil")")
                return YouTubeResolution(feedURL: rss, channelTitle: scrapeResult.channelTitle)
            } else {
                appLogWarning("[FeedService] Failed to resolve channel ID for handle/custom URL")
            }
        }

        appLogWarning("[FeedService] Could not resolve YouTube URL to RSS")
        return nil
    }

    private struct YouTubeScrapeResult {
        let channelId: String?
        let channelTitle: String?
    }

    // Scrape robuste des pages chaîne pour récupérer l'UC id et le titre
    private func fetchYouTubeChannelId(from pageURL: URL, expectedHandle: String? = nil) async -> YouTubeScrapeResult {
        let candidates: [URL] = [
            pageURL,
            pageURL.appendingPathComponent("about"),
            pageURL.appendingPathComponent("videos")
        ]
        appLogDebug("[FeedService] Trying to fetch channel ID from: \(pageURL.absoluteString)")

        for (index, u) in candidates.enumerated() {
            do {
                appLogDebug("[FeedService] Trying candidate \(index + 1): \(u.absoluteString)")
                var req = URLRequest(url: u)
                req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
                req.setValue(LocalizationManager.shared.currentLocale.identifier.replacingOccurrences(of: "_", with: "-") + ",en;q=0.8", forHTTPHeaderField: "Accept-Language")
                if let host = u.host?.lowercased(), host.contains("youtube.com") || host.contains("youtu.be") || host.contains("consent.youtube.com") {
                    req.setValue(Self.youTubeConsentCookie, forHTTPHeaderField: "Cookie")
                }
                req.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: req)
                if let httpResponse = response as? HTTPURLResponse {
                    appLogDebug("[FeedService] HTTP response: \(httpResponse.statusCode)")
                }
                guard let html = String(data: data, encoding: .utf8) else { continue }

                // Extraire le titre de la chaîne depuis le HTML
                let scrapedTitle = extractYouTubeChannelTitle(from: html)

                // Si handle attendu: motifs qui lient handle ↔ UC dans le même bloc JSON
                // Ces regex sont déjà ancrés au handle, pas besoin de vérification HTTP supplémentaire
                if let expected = expectedHandle?.lowercased() {
                    let handleEscaped = NSRegularExpression.escapedPattern(for: expected)
                    let anchored = [
                        #"\"channelMetadata\"\s*:\s*\{[\s\S]*?\"channelMetadataRenderer\"\s*:\s*\{[\s\S]*?\"vanityChannelUrl\"\s*:\s*\"/@"# + handleEscaped + #"\"[\s\S]*?\"externalId\"\s*:\s*\"(UC[0-9A-Za-z_-]{22})\""#,
                        #"\"c4TabbedHeaderRenderer\"\s*:\s*\{[\s\S]*?\"canonicalBaseUrl\"\s*:\s*\"/@"# + handleEscaped + #"\"[\s\S]*?\"channelId\"\s*:\s*\"(UC[0-9A-Za-z_-]{22})\""#
                    ]
                    for p in anchored {
                        if let id = firstRegexCapture(in: html, pattern: p) {
                            appLog("[FeedService] Found channel ID via anchored handle match (\(expected)): \(id)")
                            return YouTubeScrapeResult(channelId: id, channelTitle: scrapedTitle)
                        }
                    }
                }

                // externalId is the most reliable: it's unique per page and always represents the channel owner
                let externalIdPattern = #"\"externalId\":\"(UC[0-9A-Za-z_-]{22})\""#
                if let id = firstRegexCapture(in: html, pattern: externalIdPattern) {
                    appLog("[FeedService] Found channel ID via externalId: \(id)")
                    return YouTubeScrapeResult(channelId: id, channelTitle: scrapedTitle)
                }

                // Fallback to channelMetadata block (also reliable, scoped to the page owner)
                let metadataPattern = #"\"channelMetadata\":\{[^}]*\"externalId\":\"(UC[0-9A-Za-z_-]{22})\""#
                if let id = firstRegexCapture(in: html, pattern: metadataPattern) {
                    appLog("[FeedService] Found channel ID via channelMetadata: \(id)")
                    return YouTubeScrapeResult(channelId: id, channelTitle: scrapedTitle)
                }

                // Generic patterns - these may match IDs from recommended channels,
                // so we verify with HTTP when a handle is expected
                let patterns = [
                    #"\"channelId\":\"(UC[0-9A-Za-z_-]{22})\""#,
                    #"\"browseId\":\"(UC[0-9A-Za-z_-]{22})\""#,
                    #"CHANNEL_ID\":\"(UC[0-9A-Za-z_-]{22})\""#,
                    #"channel_id=(UC[0-9A-Za-z_-]{22})"#,
                    #"channel/(UC[0-9A-Za-z_-]{22})"#
                ]

                for (patternIndex, p) in patterns.enumerated() {
                    if let id = firstRegexCapture(in: html, pattern: p) {
                        if let expected = expectedHandle?.lowercased() {
                            if await verifyYouTubeChannelIdMatchesHandle(id, expectedHandle: expected) {
                                appLog("[FeedService] Found channel ID: \(id) with pattern \(patternIndex + 1)")
                                return YouTubeScrapeResult(channelId: id, channelTitle: scrapedTitle)
                            } else {
                                appLogDebug("[FeedService] Ignoring mismatched channel ID for handle @\(expected): \(id)")
                                continue
                            }
                        } else {
                            appLog("[FeedService] Found channel ID: \(id) with pattern \(patternIndex + 1)")
                            return YouTubeScrapeResult(channelId: id, channelTitle: scrapedTitle)
                        }
                    }
                }

                appLogDebug("[FeedService] No channel ID found in this candidate")
            } catch {
                appLogError("[FeedService] Error fetching candidate \(index + 1): \(error.localizedDescription)")
                continue
            }
        }

        appLogWarning("[FeedService] Failed to find channel ID in any candidate")
        return YouTubeScrapeResult(channelId: nil, channelTitle: nil)
    }

    /// Extracts the YouTube channel title from the page HTML
    private func extractYouTubeChannelTitle(from html: String) -> String? {
        // Try channelMetadataRenderer.title first (most reliable for the channel's own name)
        let titlePatterns = [
            #"\"channelMetadataRenderer\":\{\"title\":\"([^\"]+)\""#,
            #"\"c4TabbedHeaderRenderer\":\{[^}]*\"title\":\"([^\"]+)\""#,
            #"<meta property=\"og:title\" content=\"([^\"]+)\""#,
            #"<title>([^<]+?)(?:\s*[-–—]\s*YouTube)?\s*</title>"#
        ]
        for p in titlePatterns {
            if let title = firstRegexCapture(in: html, pattern: p)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty, title != "YouTube" {
                return title
            }
        }
        return nil
    }

    // Utilise l'endpoint oEmbed pour retrouver l'URL de la chaîne à partir d'une URL de vidéo/shorts/embed
    private func resolveYouTubeFeedViaOEmbed(from pageURL: URL) async -> URL? {
        guard var comps = URLComponents(string: "https://www.youtube.com/oembed") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "url", value: pageURL.absoluteString),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let oembedURL = comps.url else { return nil }
        var req = URLRequest(url: oembedURL)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("en-US,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        req.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return nil }
            struct OEmbed: Decodable { let author_url: String? }
            guard let obj = try? JSONDecoder().decode(OEmbed.self, from: data), let author = obj.author_url, let authorURL = URL(string: author) else {
                return nil
            }
            // Si on a déjà /channel/UC… → direct
            if let range = authorURL.path.range(of: "/channel/") {
                let id = String(authorURL.path[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !id.isEmpty, let rss = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(id)") { return rss }
            }
            // Sinon, tenter de récupérer l'UC id depuis la page auteur
            if let uc = await fetchYouTubeChannelId(from: authorURL).channelId {
                return URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(uc)")
            }
        } catch {
            return nil
        }
        return nil
    }

    private func firstRegexCapture(in text: String, pattern: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            if let m = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)), m.numberOfRanges >= 2 {
                if let r = Range(m.range(at: 1), in: text) { return String(text[r]) }
            }
        } catch { }
        return nil
    }
    
    // MARK: - Music helpers

    private func isAppleMusicHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "music.apple.com" || host == "itunes.apple.com"
    }

    private func isSpotifyHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "open.spotify.com" || host == "play.spotify.com"
    }

    /// Détecte si un feedURL est un flux Apple Music (music.apple.com ou rss.applemarketingtools.com)
    func isAppleMusicFeedURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "music.apple.com" || host == "itunes.apple.com" || host.hasSuffix(".itunes.apple.com") || host == "rss.applemarketingtools.com"
    }

    /// Détecte si un feedURL est un flux Spotify (open.spotify.com)
    func isSpotifyFeedURL(_ url: URL) -> Bool {
        isSpotifyHost(url)
    }

    /// Détecte si un feedURL est un flux musique géré nativement (Apple Music / Spotify)
    func isMusicFeedURL(_ url: URL) -> Bool {
        isAppleMusicFeedURL(url) || isSpotifyFeedURL(url)
    }

    /// Vérifie si un feed (par ID) est un flux Apple Music
    func isAppleMusicFeed(feedId: UUID) -> Bool {
        guard let feed = feeds.first(where: { $0.id == feedId }) else { return false }
        return isAppleMusicFeedURL(feed.feedURL) || isAppleMusicFeedURL(feed.siteURL ?? feed.feedURL)
    }

    /// Vérifie si un feed (par ID) est un flux musique (Apple Music / Spotify)
    func isMusicFeed(feedId: UUID) -> Bool {
        guard let feed = feeds.first(where: { $0.id == feedId }) else { return false }
        return isMusicFeedURL(feed.feedURL) || isMusicFeedURL(feed.siteURL ?? feed.feedURL)
    }

    private func canonicalSpotifyURL(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    private func spotifyEntityId(from url: URL, type: String) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let idx = parts.firstIndex(of: type), idx + 1 < parts.count else { return nil }
        let raw = parts[idx + 1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return raw.isEmpty ? nil : raw
    }

    private func spotifyTrackId(from url: URL) -> String? {
        spotifyEntityId(from: canonicalSpotifyURL(from: url), type: "track")
    }

    private func spotifyTrackId(from uri: String?) -> String? {
        guard let uri else { return nil }
        let prefix = "spotify:track:"
        guard uri.hasPrefix(prefix) else { return nil }
        let value = String(uri.dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }

#if canImport(WebKit)
    private struct SpotifyRenderedSongPayload: Decodable {
        let url: String
        let title: String
        let artist: String?
        let artwork: String?
    }

    private struct SpotifyRenderedPlaylistPayload: Decodable {
        let title: String?
        let totalTracks: Int?
        let songs: [SpotifyRenderedSongPayload]
    }

    private final class SpotifyPageNavigationDelegate: NSObject, WKNavigationDelegate {
        var onFinish: (() -> Void)?
        var onFail: ((Error) -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onFinish?()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onFail?(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onFail?(error)
        }
    }
#endif

    private func spotifyEntityType(from url: URL) -> String? {
        let parts = canonicalSpotifyURL(from: url).pathComponents.filter { $0 != "/" }
        guard let first = parts.first?.lowercased(), !first.isEmpty else { return nil }
        return first
    }

    private func spotifyFallbackTitle(from url: URL) -> String {
        switch spotifyEntityType(from: url) {
        case "playlist":
            return "Playlist Spotify"
        case "album":
            return "Album Spotify"
        case "track":
            return "Titre Spotify"
        case "artist":
            return "Artiste Spotify"
        case "show":
            return "Podcast Spotify"
        case "episode":
            return "Épisode Spotify"
        default:
            return "Lien Spotify"
        }
    }

    private func fetchHTMLPageData(from url: URL) async throws -> Data {
        guard let targetURL = httpsOnlyURL(from: url) else {
            appLogWarning("[FeedService] Refused non-HTTPS page URL: \(url.absoluteString)")
            throw FeedError.invalidURL
        }

        var request = URLRequest(url: targetURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(LocalizationManager.shared.currentLocale.identifier.replacingOccurrences(of: "_", with: "-") + ",en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            appLogWarning("[FeedService] HTML page HTTP \(http.statusCode) for \(targetURL.absoluteString)")
            throw FeedError.invalidURL
        }
        return data
    }

#if canImport(WebKit)
    private func loadWebPage(_ url: URL, in webView: WKWebView) async throws {
        let delegate = SpotifyPageNavigationDelegate()
        webView.navigationDelegate = delegate
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false

            delegate.onFinish = {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }

            delegate.onFail = { error in
                guard !resumed else { return }
                resumed = true
                continuation.resume(throwing: error)
            }

            webView.load(URLRequest(url: url))
        }
    }

    private func evaluateJavaScript(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private func intFromJavaScriptResult(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }

    private func scrapeSpotifyPageInWebView(from url: URL) async -> (title: String?, songs: [(url: URL, title: String, artist: String?, artwork: URL?)]) {
        let canonicalURL = canonicalSpotifyURL(from: url)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 900), configuration: config)

        do {
            try await loadWebPage(canonicalURL, in: webView)

            let rowCountScript = #"document.querySelectorAll('[data-testid="tracklist-row"]').length"#
            let snapshotScript = #"""
            (function() {
              const normalizeText = (value) => (value || "").replace(/\s+/g, " ").trim();
              const parseTotalTracks = () => {
                const meta = document.querySelector('meta[name="music:song_count"]');
                if (meta) {
                  const direct = parseInt((meta.getAttribute('content') || '').replace(/[^\d]/g, ''), 10);
                  if (Number.isFinite(direct) && direct > 0) return direct;
                }
                const text = document.body ? (document.body.innerText || "") : "";
                const match = text.match(/([0-9][0-9\s.,]*)\s*(titres|morceaux|songs|tracks)\b/i);
                if (!match) return null;
                const digits = match[1].replace(/[^\d]/g, "");
                const value = parseInt(digits, 10);
                return Number.isFinite(value) && value > 0 ? value : null;
              };
              const readTitle = () => {
                const og = normalizeText(document.querySelector('meta[property="og:title"]')?.getAttribute('content'));
                if (og) return og;
                const h1 = normalizeText(document.querySelector('h1')?.textContent);
                return h1 || null;
              };
              const playlistArtwork = document.querySelector('meta[property="og:image"]')?.getAttribute('content') || null;
              const songs = Array.from(document.querySelectorAll('[data-testid="tracklist-row"]')).map((row) => {
                const link = row.querySelector('[data-testid="internal-track-link"]');
                if (!link || !link.href) return null;

                const title = normalizeText(link.textContent);
                if (!title) return null;

                const artistLinks = Array.from(row.querySelectorAll('a[href*="/artist/"]'));
                const artists = artistLinks
                  .map((artistLink) => normalizeText(artistLink.textContent))
                  .filter(Boolean);
                const artist = Array.from(new Set(artists)).join(', ') || null;
                const artwork = row.querySelector('img')?.src || playlistArtwork || null;

                return { url: link.href, title, artist, artwork };
              }).filter(Boolean);

              return JSON.stringify({
                title: readTitle(),
                totalTracks: parseTotalTracks(),
                songs
              });
            })()
            """#
            let scrollScript = #"""
            (function() {
              const rows = Array.from(document.querySelectorAll('[data-testid="tracklist-row"]'));
              const lastRow = rows[rows.length - 1];
              if (!lastRow) return 0;
              lastRow.scrollIntoView({ block: 'end' });
              return rows.length;
            })()
            """#

            for _ in 0..<40 {
                let rowCount = intFromJavaScriptResult(try await evaluateJavaScript(rowCountScript, in: webView)) ?? 0
                if rowCount > 0 { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            var aggregatedSongsByURL: [String: SpotifyRenderedSongPayload] = [:]
            var orderedSongURLs: [String] = []
            var playlistTitle: String?
            var totalTracks: Int?
            var stableIterations = 0
            var lastCount = 0

            for _ in 0..<240 {
                if let jsonString = try await evaluateJavaScript(snapshotScript, in: webView) as? String,
                   let data = jsonString.data(using: .utf8),
                   let payload = try? JSONDecoder().decode(SpotifyRenderedPlaylistPayload.self, from: data) {
                    if playlistTitle == nil || playlistTitle?.isEmpty == true {
                        playlistTitle = payload.title
                    }
                    if totalTracks == nil || totalTracks == 0 {
                        totalTracks = payload.totalTracks
                    }
                    for song in payload.songs {
                        if aggregatedSongsByURL[song.url] == nil {
                            orderedSongURLs.append(song.url)
                        }
                        aggregatedSongsByURL[song.url] = song
                    }
                }

                let currentCount = aggregatedSongsByURL.count
                if currentCount == lastCount {
                    stableIterations += 1
                } else {
                    stableIterations = 0
                    lastCount = currentCount
                }

                if let totalTracks, totalTracks > 0, currentCount >= totalTracks {
                    break
                }
                if stableIterations >= 20 {
                    break
                }

                _ = try await evaluateJavaScript(scrollScript, in: webView)
                try? await Task.sleep(nanoseconds: 300_000_000)
            }

            let songs = orderedSongURLs.compactMap { urlString -> (url: URL, title: String, artist: String?, artwork: URL?)? in
                guard let item = aggregatedSongsByURL[urlString] else { return nil }
                guard let songURL = URL(string: item.url) else { return nil }
                let normalizedURL = canonicalSpotifyURL(from: songURL)
                guard spotifyTrackId(from: normalizedURL) != nil else { return nil }

                let title = item.title.decodedHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }

                let artist = item.artist?.decodedHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines)
                let artwork = item.artwork
                    .flatMap(URL.init(string:))
                    .flatMap { httpsOnlyImageURL($0) }

                return (url: normalizedURL, title: title, artist: artist?.isEmpty == true ? nil : artist, artwork: artwork)
            }

            guard !songs.isEmpty || playlistTitle != nil else {
                appLogWarning("[FeedService] Spotify WebView extraction returned no usable tracks")
                return (nil, [])
            }

            let title = playlistTitle?
                .replacingOccurrences(of: " | Spotify Playlist", with: "")
                .replacingOccurrences(of: " | Spotify", with: "")
                .decodedHTMLEntities
                .trimmingCharacters(in: .whitespacesAndNewlines)

            appLog("[FeedService] Spotify WebView extracted \(songs.count)/\(totalTracks ?? songs.count) tracks")
            return (title?.isEmpty == false ? title : nil, songs)
        } catch {
            appLogWarning("[FeedService] Spotify WebView extraction failed: \(error.localizedDescription)")
            return (nil, [])
        }
    }
#endif

    /// Scrape une page Spotify et retourne (titre, [(trackURL, titre, artiste, artworkURL)])
    /// Utilise les meta tags music:song pour l'ordre, puis le script initialState pour les métadonnées.
    private func scrapeSpotifyPage(from url: URL) async -> (title: String?, songs: [(url: URL, title: String, artist: String?, artwork: URL?)]) {
        let canonicalURL = canonicalSpotifyURL(from: url)
        let rawHTMLData = try? await fetchHTMLPageData(from: canonicalURL)
        guard let data = rawHTMLData,
              let html = String(data: data, encoding: .utf8) else {
            #if canImport(WebKit)
            let rendered = await scrapeSpotifyPageInWebView(from: canonicalURL)
            if !rendered.songs.isEmpty || rendered.title != nil {
                return rendered
            }
            #endif
            appLogWarning("[FeedService] Spotify page fetch failed for \(canonicalURL.absoluteString)")
            return (spotifyFallbackTitle(from: canonicalURL), [])
        }

        var playlistTitle: String?
        if let ogTitle = firstRegexCapture(in: html, pattern: #"<meta\s+property="og:title"\s+content="([^"]+)""#)?
            .decodedHTMLEntities
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !ogTitle.isEmpty {
            playlistTitle = ogTitle
        }

        let playlistArtworkURL = firstRegexCapture(in: html, pattern: #"<meta\s+property="og:image"\s+content="([^"]+)""#)
            .flatMap { URL(string: $0) }
            .flatMap { httpsOnlyImageURL($0) }

        let songCount = firstRegexCapture(in: html, pattern: #"<meta\s+name="music:song_count"\s+content="(\d+)""#)
            .flatMap(Int.init)

        let songPattern = #"<meta\s+name="music:song"\s+content="([^"]+)""#
        var songURLs: [(url: URL, id: String)] = []
        var seenSpotifyTrackIDs = Set<String>()
        do {
            let regex = try NSRegularExpression(pattern: songPattern, options: [.caseInsensitive])
            let nsHTML = html as NSString
            let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length))
            for match in matches {
                guard match.numberOfRanges >= 2,
                      let range = Range(match.range(at: 1), in: html),
                      let songURL = URL(string: String(html[range])) else { continue }
                let normalizedSongURL = canonicalSpotifyURL(from: songURL)
                guard let trackId = spotifyTrackId(from: normalizedSongURL) else { continue }
                if seenSpotifyTrackIDs.insert(trackId).inserted {
                    songURLs.append((url: normalizedSongURL, id: trackId))
                }
            }
        } catch {}

        var metadataByTrackID: [String: (title: String, artist: String?, artwork: URL?)] = [:]
        if let initialStateBase64 = firstRegexCapture(
            in: html,
            pattern: #"<script[^>]*id="initialState"[^>]*>([^<]+)</script>"#
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
           let decodedData = Data(base64Encoded: initialStateBase64, options: [.ignoreUnknownCharacters]),
           let jsonObject = try? JSONSerialization.jsonObject(with: decodedData),
           let initialState = jsonObject as? [String: Any],
           let entities = initialState["entities"] as? [String: Any],
           let itemsByURI = entities["items"] as? [String: Any] {
            for case let entity as [String: Any] in itemsByURI.values {
                if playlistTitle == nil,
                   let entityName = entity["name"] as? String,
                   !entityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    playlistTitle = entityName.decodedHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                if let content = entity["content"] as? [String: Any],
                   let items = content["items"] as? [[String: Any]] {
                    for item in items {
                        guard let itemV2 = item["itemV2"] as? [String: Any],
                              let trackData = itemV2["data"] as? [String: Any],
                              let trackID = spotifyTrackId(from: trackData["uri"] as? String) else { continue }

                        let title = ((trackData["name"] as? String) ?? "").decodedHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines)
                        if title.isEmpty { continue }

                        let artistNames = ((trackData["artists"] as? [String: Any])?["items"] as? [[String: Any]])?
                            .compactMap { ($0["profile"] as? [String: Any])?["name"] as? String }
                            .map { $0.decodedHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty } ?? []
                        let artist = artistNames.isEmpty ? nil : artistNames.joined(separator: ", ")

                        let coverSources = ((trackData["albumOfTrack"] as? [String: Any])?["coverArt"] as? [String: Any])?["sources"] as? [[String: Any]]
                        let artworkCandidates: [(Int, URL)] = (coverSources ?? []).compactMap { source in
                            guard let raw = source["url"] as? String,
                                  let url = URL(string: raw) else { return nil }
                            let width = source["width"] as? Int ?? source["height"] as? Int ?? 0
                            return (width, url)
                        }
                        let artworkURL: URL? = artworkCandidates
                            .max(by: { $0.0 < $1.0 })
                            .flatMap { httpsOnlyImageURL($0.1) }

                        metadataByTrackID[trackID] = (title: title, artist: artist, artwork: artworkURL)
                    }
                }
            }
        }

        appLog("[FeedService] Found \(songURLs.count) Spotify track URLs from page")
        if let songCount, songCount > songURLs.count {
            appLog("[FeedService] Spotify exposed \(songURLs.count)/\(songCount) tracks on the public page")
        }

        var songs: [(url: URL, title: String, artist: String?, artwork: URL?)] = []
        for entry in songURLs {
            if let meta = metadataByTrackID[entry.id] {
                songs.append((url: entry.url, title: meta.title, artist: meta.artist, artwork: meta.artwork ?? playlistArtworkURL))
            }
        }

        #if canImport(WebKit)
        if songs.isEmpty || (songCount != nil && songs.count < (songCount ?? 0)) {
            let rendered = await scrapeSpotifyPageInWebView(from: canonicalURL)
            if rendered.songs.count > songs.count {
                let title = rendered.title ?? playlistTitle ?? spotifyFallbackTitle(from: canonicalURL)
                return (title, rendered.songs)
            }
            if playlistTitle == nil, let renderedTitle = rendered.title {
                playlistTitle = renderedTitle
            }
        }
        #endif

        appLog("[FeedService] Scraped Spotify page: title=\(playlistTitle ?? "nil"), songs=\(songs.count)")
        return (playlistTitle, songs)
    }

    /// Scrape une page Apple Music et retourne (titre, [(songURL, titre, artiste, artworkURL)])
    /// Utilise les meta tags music:song pour les URLs, puis l'API iTunes Lookup pour les métadonnées
    private func scrapeAppleMusicPage(from url: URL) async -> (title: String?, songs: [(url: URL, title: String, artist: String?, artwork: URL?)]) {
        guard let data = try? await fetchFeedData(from: url),
              let html = String(data: data, encoding: .utf8) else { return (nil, []) }

        // Titre depuis og:title
        var playlistTitle: String?
        if let ogTitle = firstRegexCapture(in: html, pattern: #"<meta\s+property="og:title"\s+content="([^"]+)""#) {
            let cleaned = ogTitle
                .replacingOccurrences(of: " sur Apple Music", with: "")
                .replacingOccurrences(of: " on Apple Music", with: "")
                .replacingOccurrences(of: "&#x27;", with: "'")
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { playlistTitle = cleaned }
        }

        // Extraire les URLs des morceaux via <meta property="music:song">
        let songPattern = #"<meta\s+property="music:song"\s+content="([^"]+)""#
        var songURLs: [(url: URL, id: String)] = []
        do {
            let regex = try NSRegularExpression(pattern: songPattern, options: [.caseInsensitive])
            let nsHTML = html as NSString
            let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length))
            for match in matches {
                guard match.numberOfRanges >= 2,
                      let range = Range(match.range(at: 1), in: html),
                      let songURL = URL(string: String(html[range])) else { continue }
                // L'ID est le dernier composant du path : /song/name/12345
                if let songId = songURL.pathComponents.last, songId.allSatisfy(\.isNumber) {
                    songURLs.append((url: songURL, id: songId))
                }
            }
        } catch {}

        appLog("[FeedService] Found \(songURLs.count) song URLs from Apple Music page")

        guard !songURLs.isEmpty else { return (playlistTitle, []) }

        // Récupérer les métadonnées via l'API iTunes Lookup (batch par 150)
        var lookupMap: [String: (name: String, artist: String, artwork: URL?, releaseDate: String?)] = [:]

        let batches = stride(from: 0, to: songURLs.count, by: 150).map {
            Array(songURLs[$0..<min($0 + 150, songURLs.count)])
        }

        for batch in batches {
            let ids = batch.map(\.id).joined(separator: ",")
            guard let lookupURL = URL(string: "https://itunes.apple.com/lookup?id=\(ids)") else { continue }
            guard let lookupData = try? await fetchFeedData(from: lookupURL) else { continue }

            struct ITunesLookup: Decodable {
                let results: [ITunesTrack]?
            }
            struct ITunesTrack: Decodable {
                let trackId: Int?
                let trackName: String?
                let artistName: String?
                let artworkUrl100: String?
                let releaseDate: String?
            }

            if let lookup = try? JSONDecoder().decode(ITunesLookup.self, from: lookupData) {
                for track in (lookup.results ?? []) {
                    guard let trackId = track.trackId, let name = track.trackName else { continue }
                    let artworkURL: URL? = track.artworkUrl100
                        .flatMap { $0.replacingOccurrences(of: "100x100bb", with: "600x600bb") }
                        .flatMap { URL(string: $0) }
                    lookupMap[String(trackId)] = (name: name, artist: track.artistName ?? "", artwork: artworkURL, releaseDate: track.releaseDate)
                }
            }
        }

        appLog("[FeedService] iTunes Lookup resolved \(lookupMap.count)/\(songURLs.count) tracks")

        // Combiner URLs + métadonnées
        var songs: [(url: URL, title: String, artist: String?, artwork: URL?)] = []
        for entry in songURLs {
            if let meta = lookupMap[entry.id] {
                songs.append((url: entry.url, title: meta.name, artist: meta.artist, artwork: meta.artwork))
            } else {
                // Fallback : titre depuis le slug de l'URL
                let pathComponents = entry.url.pathComponents
                var songTitle = "Unknown"
                if let songIdx = pathComponents.firstIndex(of: "song"), songIdx + 1 < pathComponents.count {
                    songTitle = pathComponents[songIdx + 1]
                        .replacingOccurrences(of: "-", with: " ")
                        .capitalized
                }
                songs.append((url: entry.url, title: songTitle, artist: nil, artwork: nil))
            }
        }

        appLog("[FeedService] Scraped Apple Music page: title=\(playlistTitle ?? "nil"), songs=\(songs.count)")
        return (playlistTitle, songs)
    }

    /// Parse les morceaux scrapés d'une page Apple Music et crée des articles
    /// Extrait l'ID numérique d'une URL Apple Music song (le dernier composant numérique du path)
    private func appleMusicSongId(from url: URL) -> String? {
        url.pathComponents.last(where: { $0.allSatisfy(\.isNumber) && !$0.isEmpty })
    }

    private func parseSpotifySongs(songs: [(url: URL, title: String, artist: String?, artwork: URL?)], feed: Feed, seenKeys: inout Set<String>, titleToArticleByFeed: inout [UUID: [String: Article]], urlToArticle: inout [String: Article], stream: Bool) -> [Article] {
        var created: [Article] = []

        for song in songs {
            let trackId = spotifyTrackId(from: song.url)
            let key = trackId.map { "spotify://\(feed.id)/\($0)" } ?? "spotify://\(feed.id)/\(canonicalKey(for: song.url, guid: nil))"

            if seenKeys.contains(key) { continue }

            let displayTitle = if let artist = song.artist, !artist.isEmpty {
                "\(song.title) — \(artist)"
            } else {
                song.title
            }

            let article = Article(
                feedId: feed.id,
                title: displayTitle,
                url: song.url,
                author: song.artist,
                publishedAt: Date(),
                contentHTML: nil,
                contentText: nil,
                imageURL: song.artwork,
                summary: song.artist,
                readingTime: nil,
                lang: nil,
                score: nil
            )
            modelContext.insert(article)
            if stream { self.articles.append(article) }
            seenKeys.insert(key)
            urlToArticle[key] = article
            titleToArticleByFeed[feed.id, default: [:]][Self.normalizeTitle(song.title)] = article
            created.append(article)
        }

        appLog("[FeedService] Created \(created.count) Spotify articles for '\(feed.title)'")
        return created
    }

    private func removeSpotifyFallbackArticles(for feed: Feed) {
        let fallbackURL = canonicalSpotifyURL(from: feed.feedURL)
        let fallbackArticles = articles.filter { article in
            guard article.feedId == feed.id else { return false }
            guard article.summary == "Ouvrir dans Spotify" else { return false }
            guard article.author == "Spotify" else { return false }
            return canonicalSpotifyURL(from: article.url) == fallbackURL
        }

        guard !fallbackArticles.isEmpty else { return }

        for article in fallbackArticles {
            articles.removeAll { $0.id == article.id }
            modelContext.delete(article)
        }

        appLog("[FeedService] Removed \(fallbackArticles.count) Spotify fallback article(s) for '\(feed.title)'")
    }

    private func parseSpotifyFallbackArticle(feed: Feed, seenKeys: inout Set<String>, titleToArticleByFeed: inout [UUID: [String: Article]], urlToArticle: inout [String: Article], stream: Bool) -> [Article] {
        let fallbackURL = canonicalSpotifyURL(from: feed.feedURL)
        let key = "spotify://\(feed.id)/fallback/\(canonicalKey(for: fallbackURL, guid: nil))"
        if seenKeys.contains(key) { return [] }

        let title = feed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? spotifyFallbackTitle(from: fallbackURL)
            : feed.title

        if titleToArticleByFeed[feed.id]?[Self.normalizeTitle(title)] != nil {
            return []
        }

        let article = Article(
            feedId: feed.id,
            title: title,
            url: fallbackURL,
            author: "Spotify",
            publishedAt: Date(),
            contentHTML: nil,
            contentText: nil,
            imageURL: nil,
            summary: "Ouvrir dans Spotify",
            readingTime: nil,
            lang: nil,
            score: nil
        )
        modelContext.insert(article)
        if stream { self.articles.append(article) }
        seenKeys.insert(key)
        urlToArticle[key] = article
        titleToArticleByFeed[feed.id, default: [:]][Self.normalizeTitle(title)] = article
        appLog("[FeedService] Created Spotify fallback article for '\(feed.title)'")
        return [article]
    }

    private func parseAppleMusicSongs(songs: [(url: URL, title: String, artist: String?, artwork: URL?)], feed: Feed, seenKeys: inout Set<String>, titleToArticleByFeed: inout [UUID: [String: Article]], urlToArticle: inout [String: Article], stream: Bool) -> [Article] {
        var created: [Article] = []

        for song in songs {
            // Utiliser une clé stable basée sur l'ID de la chanson + feedId (indépendant de la locale de l'URL)
            // IMPORTANT: la clé DOIT inclure le feedId car le même morceau peut apparaître dans plusieurs playlists
            let songId = appleMusicSongId(from: song.url)
            let key = songId.map { "applemusic://\(feed.id)/\($0)" } ?? "applemusic://\(feed.id)/\(canonicalKey(for: song.url, guid: nil))"

            // Dédup uniquement par clé feed-specific (pas par URL globale, sinon les playlists partagent les morceaux)
            if seenKeys.contains(key) { continue }

            let displayTitle = if let artist = song.artist, !artist.isEmpty {
                "\(song.title) — \(artist)"
            } else {
                song.title
            }

            let article = Article(
                feedId: feed.id,
                title: displayTitle,
                url: song.url,
                author: song.artist,
                publishedAt: Date(),
                contentHTML: nil,
                contentText: nil,
                imageURL: song.artwork,
                summary: song.artist,
                readingTime: nil,
                lang: nil,
                score: nil
            )
            modelContext.insert(article)
            if stream { self.articles.append(article) }
            seenKeys.insert(key)
            urlToArticle[key] = article
            titleToArticleByFeed[feed.id, default: [:]][Self.normalizeTitle(song.title)] = article
            created.append(article)
        }

        appLog("[FeedService] Created \(created.count) Apple Music articles for '\(feed.title)'")
        return created
    }

    @discardableResult
    func addFeed(from urlString: String) async throws -> Feed {
        // Sanitize URL string: trim spaces/newlines, drop leading '@', ensure scheme
        let sanitized = sanitizeFeedURLString(urlString)
        guard let initialURL = URL(string: sanitized)?.absoluteURL ?? {
            var comps = URLComponents(string: sanitized)
            if comps?.scheme == nil { comps?.scheme = "https" }
            return comps?.url?.absoluteURL
        }() else {
            throw FeedError.invalidURL
        }
        guard let httpsURL = httpsOnlyURL(from: initialURL) else {
            throw FeedError.invalidURL
        }
        // Conversion éventuelle YouTube vers flux RSS
        let url: URL
        var youTubeChannelTitle: String?
        var appleMusicFeedTitle: String?
        var spotifyFeedTitle: String?
        if isYouTubeHost(httpsURL) {
            appLog("[FeedService] YouTube URL detected: \(httpsURL.absoluteString)")
            if let resolution = await resolveYouTubeFeedURL(from: httpsURL) {
                appLog("[FeedService] Resolved to RSS: \(resolution.feedURL.absoluteString)")
                url = resolution.feedURL
                youTubeChannelTitle = resolution.channelTitle
            } else {
                appLogWarning("[FeedService] Failed to resolve YouTube URL, using original")
                url = httpsURL
            }
        } else if isAppleMusicHost(httpsURL) {
            appLog("[FeedService] Apple Music URL detected: \(httpsURL.absoluteString)")
            // Stocker l'URL Apple Music directement comme feedURL
            url = httpsURL
            // Scraper le titre de la playlist
            let scraped = await scrapeAppleMusicPage(from: httpsURL)
            appleMusicFeedTitle = scraped.title
            appLog("[FeedService] Apple Music playlist: '\(appleMusicFeedTitle ?? "nil")' with \(scraped.songs.count) songs")
        } else if isSpotifyHost(httpsURL) {
            let normalizedSpotifyURL = canonicalSpotifyURL(from: httpsURL)
            appLog("[FeedService] Spotify URL detected: \(normalizedSpotifyURL.absoluteString)")
            url = normalizedSpotifyURL
            let scraped = await scrapeSpotifyPage(from: normalizedSpotifyURL)
            spotifyFeedTitle = scraped.title
            appLog("[FeedService] Spotify playlist: '\(spotifyFeedTitle ?? "nil")' with \(scraped.songs.count) songs")
        } else {
            // Pour toute URL de page (y compris /le-blog), tenter d'abord de découvrir un flux
            if isLikelyFeedURL(httpsURL) {
                url = httpsURL
            } else if let discovered = await discoverFeedURL(from: httpsURL) {
                url = discovered
            } else {
                throw FeedError.feedNotFound
            }
        }
        if feeds.contains(where: { $0.feedURL == url }) {
            throw FeedError.duplicate
        }

        // Enrichir le titre + siteURL via FeedKit si possible
        var resolvedTitle: String?
        var resolvedSiteURL: URL?

        // Flux musique: titre déjà récupéré, pas de parsing FeedKit
        if isAppleMusicFeedURL(url) {
            resolvedTitle = appleMusicFeedTitle
            resolvedSiteURL = httpsURL // garder l'URL Apple Music originale comme siteURL
        } else if isSpotifyFeedURL(url) {
            resolvedTitle = spotifyFeedTitle
            resolvedSiteURL = url
        }

        #if canImport(FeedKit)
        if !isMusicFeedURL(url) {
        do {
            appLog("[FeedService] Parsing feed: \(url.absoluteString)")
            let rawData = try await fetchFeedData(from: url)
            let data = sanitizeXMLDataForParsing(rawData)
            appLogDebug("[FeedService] Feed data size: \(data.count) bytes")
            do {
                let parsed = try FeedKit.Feed(data: data)
                appLog("[FeedService] Feed parsed successfully")
                switch parsed {
                case .rss(let rss):
                    appLogDebug("[FeedService] RSS feed detected")
                    resolvedTitle = rss.channel?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                    appLog("[FeedService] RSS title: \(resolvedTitle ?? "nil")")
                    appLog("[FeedService] RSS items count: \(rss.channel?.items?.count ?? 0)")
                    if let link = rss.channel?.link?.trimmingCharacters(in: .whitespacesAndNewlines), let su = URL(string: link) {
                        resolvedSiteURL = httpsOnlyURL(from: su)
                        appLogDebug("[FeedService] RSS site URL: \(su.absoluteString)")
                    }
                case .atom(let atom):
                    appLogDebug("[FeedService] Atom feed detected")
                    resolvedTitle = atom.title?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                    appLog("[FeedService] Atom title: \(resolvedTitle ?? "nil")")
                    appLog("[FeedService] Atom entries count: \(atom.entries?.count ?? 0)")
                    if let link = atom.links?.first(where: { $0.attributes?.rel == nil || $0.attributes?.rel == "alternate" })?.attributes?.href {
                        if let candidate = URL(string: link, relativeTo: url)?.absoluteURL {
                            resolvedSiteURL = httpsOnlyURL(from: candidate)
                        }
                        appLogDebug("[FeedService] Atom site URL: \(resolvedSiteURL?.absoluteString ?? "nil")")
                    }
                case .json(let json):
                    appLogDebug("[FeedService] JSON feed detected")
                    resolvedTitle = json.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                    appLog("[FeedService] JSON title: \(resolvedTitle ?? "nil")")
                    appLog("[FeedService] JSON items count: \(json.items?.count ?? 0)")
                    if let home = json.homePageURL, let su = URL(string: home) {
                        resolvedSiteURL = httpsOnlyURL(from: su)
                    }
                }
            } catch {
                if let xml = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .ascii)
                    ?? String(data: data, encoding: .isoLatin1) {
                    let lower = xml.lowercased()
                    if lower.contains("<rdf:rdf") || lower.contains("purl.org/rss/1.0") {
                        let info = extractRSS1ChannelInfo(from: xml, base: url)
                        resolvedTitle = info.title
                        resolvedSiteURL = info.link.flatMap { httpsOnlyURL(from: $0) }
                        appLog("[FeedService] RSS 1.0 (RDF) feed detected: \(resolvedTitle ?? "nil")")
                    } else {
                        appLogError("[FeedService] Feed parsing error: \(error.localizedDescription)")
                    }
                } else {
                    appLogError("[FeedService] Feed parsing error: \(error.localizedDescription)")
                }
                // on tombera sur le fallback
            }
        } catch {
            appLogError("[FeedService] Feed parsing error: \(error.localizedDescription)")
            // on tombera sur le fallback
        }
        } // end if !isMusicFeedURL
        #endif

        // Fallback: use YouTube channel title scraped during resolution, then host prettification
        if resolvedTitle == nil {
            resolvedTitle = appleMusicFeedTitle
                ?? spotifyFeedTitle
                ?? (isSpotifyFeedURL(url) ? spotifyFallbackTitle(from: url) : nil)
                ?? youTubeChannelTitle
        }
        if resolvedTitle == nil {
            let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host ?? url.host
            resolvedTitle = prettifyHost(host ?? url.absoluteString)
        }
        if resolvedSiteURL == nil, let scheme = url.scheme, let host = url.host {
            resolvedSiteURL = URL(string: "\(scheme)://\(host)")
        }
        // For YouTube feeds, preserve the original channel URL as siteURL
        if resolvedSiteURL == nil || resolvedSiteURL?.path == "/", isYouTubeHost(httpsURL) {
            resolvedSiteURL = httpsURL
        }

        let newFeed = Feed(
            title: resolvedTitle ?? url.absoluteString,
            siteURL: resolvedSiteURL,
            feedURL: url,
            faviconURL: nil,
            tags: [],
            addedAt: .now,
            sortIndex: (feeds.map { $0.sortIndex ?? Int.max }.compactMap { $0 }.max() ?? -1) + 1
        )

        modelContext.insert(newFeed)
        try modelContext.save()
        loadFeeds()
        
        #if os(macOS)
        HapticFeedback.success()
        #endif
        
        logger.info("Added feed: \(url.absoluteString, privacy: .public). Total feeds: \(self.feeds.count)")
        // Découvrir le favicon du nouveau flux en arrière-plan
        Task { [weak self] in
            await self?.ensureFavicons()
        }
        // Rafraîchir immédiatement après ajout pour peupler les articles du nouveau flux
        // Limite: 3 semaines maximum au premier fetch
        let initialCutoff = Calendar.current.date(byAdding: .day, value: -21, to: Date())
        try await refreshArticles(for: newFeed.id, earliestDate: initialCutoff, stream: true)
        updateAppBadge()
        return newFeed
    }

    private func sanitizeFeedURLString(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("@") { s.removeFirst() }
        // Retire guillemets, chevrons, parenthèses entourant
        let wrappers: [(String, String)] = [("<", ">"), ("(", ")"), ("\"", "\""), ("'", "'")]
        for (l, r) in wrappers {
            if s.hasPrefix(l) && s.hasSuffix(r) && s.count >= 2 { s = String(s.dropFirst().dropLast()) }
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Retire ponctuations finales fréquentes lors du copier/coller
        let trailingChars = CharacterSet(charactersIn: ".,;:!?)]}…")
        while let last = s.unicodeScalars.last, trailingChars.contains(last) { s = String(s.dropLast()) }
        // Retire ponctuations initiales parasites
        let leadingChars = CharacterSet(charactersIn: "([{")
        while let first = s.unicodeScalars.first, leadingChars.contains(first) { s = String(s.dropFirst()) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isLegacyAppleRSSURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        guard host == "ax.itunes.apple.com" || host == "itunes.apple.com" else { return false }
        return url.path.lowercased().contains("/webobjects/mzstoreservices.woa/ws/rss/")
    }

    private func httpsOnlyURL(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let scheme = components.scheme?.lowercased()
        let host = components.host?.lowercased()

        if host == "ax.itunes.apple.com" {
            // Ancienne URL Apple RSS: ce sous-domaine ne répond pas correctement en HTTPS.
            components.host = "itunes.apple.com"
        }

        if scheme == "https" {
            return components.url
        }
        if scheme == "http" {
            components.scheme = "https"
            return components.url
        }
        return nil
    }

    private func httpsOnlyImageURL(_ url: URL?) -> URL? {
        return url.flatMap { httpsOnlyURL(from: $0) }
    }

    private func upscaledAppleArtworkURL(_ url: URL?) -> URL? {
        guard let normalized = httpsOnlyImageURL(url) else { return nil }
        guard let host = normalized.host?.lowercased(), host.contains("mzstatic.com") else { return normalized }

        let absolute = normalized.absoluteString
        let pattern = #"/\d+x\d+bb(?:-\d+)?\.(png|jpg|jpeg|webp)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return normalized
        }
        let range = NSRange(location: 0, length: absolute.utf16.count)
        let replacement = "/1200x1200bb.$1"
        let rewritten = regex.stringByReplacingMatches(in: absolute, options: [], range: range, withTemplate: replacement)
        return URL(string: rewritten) ?? normalized
    }

    #if canImport(FeedKit)
    private func preferredAppleArtworkURL(from entry: FeedKit.AtomFeedEntry, articleURL: URL) -> URL? {
        let html = entry.content?.text ?? entry.summary?.text
        if let directArtwork = upscaledAppleArtworkURL(extractImageURL(fromHTML: html, baseURL: articleURL)) {
            return directArtwork
        }
        if let feedArtwork = upscaledAppleArtworkURL(extractAtomImage(entry)) {
            return feedArtwork
        }
        return nil
    }
    #endif

    func refreshArticles(for feedId: UUID? = nil, earliestDate: Date? = nil, stream: Bool = false) async throws {
        let isSingleFeed = feedId != nil

        if isSingleFeed {
            // Refresh ciblé (ajout de flux) : prioritaire, interrompt le global si en cours
            if isSingleFeedRefreshing { return }
            isSingleFeedRefreshing = true
            if isRefreshing {
                // Interrompre le refresh global en cours
                cancelGlobalRefresh = true
                appLog("[FeedService] Interrupting global refresh for priority single-feed refresh")
            }
            refreshingFeedId = feedId
            defer {
                isSingleFeedRefreshing = false
                refreshingFeedId = nil
                #if os(macOS)
                HapticFeedback.tap()
                #endif
            }
        } else {
            // Refresh global : ne lance pas si un refresh (global ou ciblé) est déjà en cours
            if isRefreshing || isSingleFeedRefreshing { return }
            cancelGlobalRefresh = false
            isRefreshing = true
            suppressBadgeUpdates = true
            refreshingFeedId = nil
            defer {
                isRefreshing = false
                suppressBadgeUpdates = false
                refreshingFeedId = nil
                cancelGlobalRefresh = false
                updateAppBadge()
                syncWidgetSnapshots()
                #if os(macOS)
                HapticFeedback.tap()
                #endif
            }
        }

        let targets = feedId != nil ? self.feeds.filter { $0.id == feedId } : self.feeds
        logger.info("Refresh start — feeds to fetch: \(targets.count)")
        appLog("[FeedService] Refresh start — feeds: \(targets.count)")
        
        // Compter les articles non lus AVANT le refresh pour calculer la différence (hors musique)
        let musicFeedIdsBeforeRefresh = Set(
            feeds
                .filter { isMusicFeedURL($0.feedURL) || isMusicFeedURL($0.siteURL ?? $0.feedURL) }
                .map(\.id)
        )
        let unreadCountBefore = articles.filter { !$0.isRead && !musicFeedIdsBeforeRefresh.contains($0.feedId) }.count
        
        #if canImport(FeedKit)
        var created: [Article] = []
        // Éviter les doublons par URL + permettre backfill d'images sur articles existants
        let existing = (try? modelContext.fetch(FetchDescriptor<Article>())) ?? []
        var existingURLs: Set<String> = .init(existing.map { canonicalKey(for: $0.url, guid: nil) })
        // Ajouter aussi les clés musique feed-specific pour éviter les doublons entre playlists.
        for art in existing {
            if let songId = appleMusicSongId(from: art.url) {
                existingURLs.insert("applemusic://\(art.feedId)/\(songId)")
            }
            if let trackId = spotifyTrackId(from: art.url) {
                existingURLs.insert("spotify://\(art.feedId)/\(trackId)")
            }
        }
        // Map pour retrouver rapidement un article existant par URL canonique (sans GUID)
        var urlToArticle: [String: Article] = [:]
        // Construire une map tolérante aux doublons d'URL (garde la première avec image si possible)
        for art in existing {
            let key = canonicalKey(for: art.url, guid: nil)
            if let current = urlToArticle[key] {
                // Préfère la version qui a déjà une image
                if current.imageURL == nil, art.imageURL != nil {
                    urlToArticle[key] = art
                }
            } else {
                urlToArticle[key] = art
            }
        }
        // Map secondaire: par (feedId, titre normalisé) pour éviter doublons quand l'URL varie (guid vs link)
        var titleToArticleByFeed: [UUID: [String: Article]] = [:]
        for art in existing {
            titleToArticleByFeed[art.feedId, default: [:]][Self.normalizeTitle(art.title)] = art
        }
        // Ensemble de clés déjà vues pendant ce rafraîchissement pour éviter toute insertion doublon
        var seenKeys: Set<String> = existingURLs

        func urlKey(for url: URL) -> String {
            canonicalKey(for: url, guid: nil)
        }

        func guidKey(for url: URL, guid: String?) -> String {
            canonicalKey(for: url, guid: guid)
        }

        func rememberArticle(_ article: Article, url: URL, guid: String?, title: String, feedId: UUID) {
            let normalizedURLKey = urlKey(for: url)
            let normalizedGUIDKey = guidKey(for: url, guid: guid)

            seenKeys.insert(normalizedURLKey)
            urlToArticle[normalizedURLKey] = article

            if normalizedGUIDKey != normalizedURLKey {
                seenKeys.insert(normalizedGUIDKey)
                urlToArticle[normalizedGUIDKey] = article
            }

            titleToArticleByFeed[feedId, default: [:]][Self.normalizeTitle(title)] = article
        }

        func existingArticle(for url: URL, guid: String?) -> Article? {
            let normalizedURLKey = urlKey(for: url)
            if let article = urlToArticle[normalizedURLKey] {
                return article
            }

            let normalizedGUIDKey = guidKey(for: url, guid: guid)
            if normalizedGUIDKey != normalizedURLKey {
                return urlToArticle[normalizedGUIDKey]
            }

            return nil
        }

        func hasSeenArticle(url: URL, guid: String?) -> Bool {
            let normalizedURLKey = urlKey(for: url)
            if seenKeys.contains(normalizedURLKey) {
                return true
            }

            let normalizedGUIDKey = guidKey(for: url, guid: guid)
            if normalizedGUIDKey != normalizedURLKey {
                return seenKeys.contains(normalizedGUIDKey)
            }

            return false
        }

        func parseRSSFallbackAndCreateArticles(xml: String, feed: Feed) async -> Int {
            appLogDebug("[FeedService] RSS fallback XML length: \(xml.count)")
            var createdCount = 0
            var createQuota = 35
            let items = extractRSS1Items(from: xml, base: feed.feedURL)
            appLogDebug("[FeedService] RSS fallback items extracted: \(items.count)")
            for it in items {
                if createQuota <= 0 { break }
                if let cutoff = earliestDate, let d = it.date, d < cutoff { continue }
                let url = it.link
                let title = it.title.isEmpty ? url.absoluteString : it.title
                let guid = url.absoluteString
                if hasSeenArticle(url: url, guid: guid) { continue }
                // Dédup par titre (même feed)
                if let existingByTitle = titleToArticleByFeed[feed.id]?[Self.normalizeTitle(title)] {
                    if existingByTitle.imageURL == nil, let img = extractBestImageURL(fromHTML: it.description, baseURL: url) { existingByTitle.imageURL = httpsOnlyImageURL(img) }
                    if existingByTitle.summary == nil, let s = extractPlainText(from: it.description) { existingByTitle.summary = s }
                    if existingByTitle.contentHTML == nil, let h = it.description { existingByTitle.contentHTML = h }
                    rememberArticle(existingByTitle, url: url, guid: guid, title: title, feedId: feed.id)
                    continue
                }
                var image: URL? = nil
                if image == nil { image = extractBestImageURL(fromHTML: it.description, baseURL: url) }
                if image == nil { image = youtubeThumbnailURL(for: url) }
                if image == nil { image = await fetchOgImage(from: url) }
                image = httpsOnlyImageURL(image)
                let rawHTML = it.description
                let cleanedText = extractPlainText(from: rawHTML)
                let cleanedSummary = extractPlainText(from: it.description) ?? cleanedText
                let article = Article(
                    feedId: feed.id,
                    title: title,
                    url: url,
                    author: it.author,
                    publishedAt: it.date,
                    contentHTML: rawHTML,
                    contentText: cleanedText,
                    imageURL: image,
                    summary: cleanedSummary,
                    readingTime: nil,
                    lang: nil,
                    score: nil
                )
                appLog("[FeedService] Creating RDF article: '\(title)' for feed '\(feed.title)' with feedId: \(feed.id)")
                modelContext.insert(article)
                createQuota -= 1
                if stream { self.articles.append(article) }
                rememberArticle(article, url: url, guid: guid, title: title, feedId: feed.id)
                created.append(article)
                createdCount += 1
            }
            return createdCount
        }
        for feed in targets {
            // Si un ajout de flux a demandé l'interruption du refresh global, on arrête
            if !isSingleFeed && cancelGlobalRefresh {
                appLog("[FeedService] Global refresh cancelled — priority single-feed refresh requested")
                break
            }
            logger.info("Fetching feed: \(feed.feedURL.absoluteString, privacy: .public)")
            appLog("[FeedService] Fetching: \(feed.feedURL.absoluteString)")
            do {
            if isAppleMusicFeedURL(feed.feedURL) {
                appLog("[FeedService] Apple Music feed detected: \(feed.feedURL.absoluteString)")
                let scraped = await scrapeAppleMusicPage(from: feed.feedURL)
                let appleMusicArticles = parseAppleMusicSongs(
                    songs: scraped.songs,
                    feed: feed,
                    seenKeys: &seenKeys,
                    titleToArticleByFeed: &titleToArticleByFeed,
                    urlToArticle: &urlToArticle,
                    stream: stream
                )
                created.append(contentsOf: appleMusicArticles)
                appLog("[FeedService] Apple Music created: \(appleMusicArticles.count) items")
                continue
            }

            if isSpotifyFeedURL(feed.feedURL) {
                appLog("[FeedService] Spotify feed detected: \(feed.feedURL.absoluteString)")
                let scraped = await scrapeSpotifyPage(from: feed.feedURL)
                var spotifyArticles = parseSpotifySongs(
                    songs: scraped.songs,
                    feed: feed,
                    seenKeys: &seenKeys,
                    titleToArticleByFeed: &titleToArticleByFeed,
                    urlToArticle: &urlToArticle,
                    stream: stream
                )
                if !spotifyArticles.isEmpty {
                    removeSpotifyFallbackArticles(for: feed)
                } else {
                    spotifyArticles = parseSpotifyFallbackArticle(
                        feed: feed,
                        seenKeys: &seenKeys,
                        titleToArticleByFeed: &titleToArticleByFeed,
                        urlToArticle: &urlToArticle,
                        stream: stream
                    )
                }
                created.append(contentsOf: spotifyArticles)
                appLog("[FeedService] Spotify created: \(spotifyArticles.count) items")
                continue
            }

            let rawData = try await fetchFeedData(from: feed.feedURL)
            let data = sanitizeXMLDataForParsing(rawData)
            let xmlString = decodeXMLString(from: data)
            if looksLikeRSS1(xmlString) {
                appLog("[FeedService] RSS 1.0 (RDF) feed detected: \(feed.feedURL.absoluteString)")
                    let createdCount = await parseRSSFallbackAndCreateArticles(xml: xmlString, feed: feed)
                if createdCount > 0 {
                    appLog("[FeedService] RSS 1.0 created: \(createdCount) items")
                } else {
                    appLogWarning("[FeedService] RSS 1.0 parsed but found 0 items")
                }
                continue
            }
            let parsed = try FeedKit.Feed(data: data)
            appLog("[FeedService] Successfully parsed feed: \(feed.feedURL.absoluteString)")
                        var createQuota = 35
                        switch parsed {
        case .rss(let rss):
            let items = rss.channel?.items ?? []
            logger.info("Parsed RSS items: \(items.count) for \(feed.feedURL.absoluteString, privacy: .public)")
            appLog("[FeedService] RSS items: \(items.count)")
            appLogDebug("[FeedService] RSS channel title: \(rss.channel?.title ?? "nil")")
            if feed.feedURL.host?.contains("youtube") == true {
                appLog("[FeedService] YouTube RSS feed - items: \(items.count)")
                for (index, item) in items.enumerated() {
                    appLogDebug("[FeedService] YouTube item \(index): \(item.title ?? "no title")")
                }
            }
                    for item in items {
                        if createQuota <= 0 { break }
                        if let cutoff = earliestDate {
                            let pub = item.pubDate ?? Date.distantPast
                            if pub < cutoff { continue }
                        }
                        let guidText = item.guid?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let linkString = (item.link ?? guidText)?.trimmingCharacters(in: .whitespacesAndNewlines), let url = URL(string: linkString) else { continue }
                        // Filtrer les YouTube Shorts
                        let title = item.title ?? (item.description ?? linkString)
                        let rawDesc = item.description
                        if isLikelyYouTubeShort(url: url, title: title, description: rawDesc) { continue }
                        // Dédup par titre (même feed) si l'URL varie entre rafraîchissements
                        if let existingByTitle = titleToArticleByFeed[feed.id]?[Self.normalizeTitle(title)] {
                            // Backfill basique
                            if existingByTitle.imageURL == nil, let img = extractRSSImage(item) { existingByTitle.imageURL = httpsOnlyImageURL(img) }
                            if existingByTitle.summary == nil, let s = extractPlainText(from: item.description) { existingByTitle.summary = s }
                            if existingByTitle.contentHTML == nil, let h = item.content?.encoded { existingByTitle.contentHTML = h }
                            rememberArticle(existingByTitle, url: url, guid: guidText, title: title, feedId: feed.id)
                            continue
                        }
                        
                        var image: URL? = nil
                        if image == nil { image = extractRSSImage(item) }
                        if image == nil { image = extractBestImageURL(fromHTML: item.content?.encoded ?? item.description, baseURL: url) }
                        if image == nil { image = youtubeThumbnailURL(for: url) }
                        if image == nil { image = await fetchOgImage(from: url) }
                        image = httpsOnlyImageURL(image)
                        // Préparer contenu nettoyé pour backfill et création
                        let rawHTML = item.content?.encoded ?? item.description
                        let cleanedText = extractPlainText(from: rawHTML)
                        let cleanedSummary = extractPlainText(from: item.description) ?? cleanedText
                        // Backfill si l'article existe déjà
                        if let existing = existingArticle(for: url, guid: guidText) {
                            if existing.imageURL == nil, let image { existing.imageURL = image }
                            if (existing.contentText == nil || existing.contentText?.isEmpty == true), let cleanedText { existing.contentText = cleanedText }
                            if existing.summary == nil || (existing.summary?.contains("<") == true) { existing.summary = cleanedSummary }
                            if existing.contentHTML == nil, let rawHTML { existing.contentHTML = rawHTML }
                            rememberArticle(existing, url: url, guid: guidText, title: title, feedId: feed.id)
                            continue
                        }
                        // Ne pas créer si déjà vu pendant ce refresh
                        if hasSeenArticle(url: url, guid: guidText) { continue }

                        let article = Article(
                            feedId: feed.id,
                            title: title,
                            url: url,
                            author: item.author ?? item.dublinCore?.creator,
                            publishedAt: item.pubDate,
                            contentHTML: rawHTML,
                            contentText: cleanedText,
                            imageURL: image,
                            summary: cleanedSummary,
                            readingTime: nil,
                            lang: nil,
                            score: nil
                        )
                        appLog("[FeedService] Creating RSS article: '\(title)' for feed '\(feed.title)' with feedId: \(feed.id)")
                        modelContext.insert(article)
                        createQuota -= 1
                        if stream { self.articles.append(article) }
                        rememberArticle(article, url: url, guid: guidText, title: title, feedId: feed.id)
                        created.append(article)
                    }
                case .atom(let atom):
                    let entries = atom.entries ?? []
                    let fallbackPublishedAt = isLegacyAppleRSSURL(feed.feedURL) ? Date() : nil
                    logger.info("Parsed Atom entries: \(entries.count) for \(feed.feedURL.absoluteString, privacy: .public)")
                    appLog("[FeedService] Atom entries: \(entries.count)")
                    appLogDebug("[FeedService] Atom feed title: \(atom.title?.text ?? "nil")")
                    for entry in entries {
                        if createQuota <= 0 { break }
                        let effectivePublishedAt = entry.published ?? entry.updated ?? fallbackPublishedAt
                        if let cutoff = earliestDate {
                            let pub = effectivePublishedAt ?? Date.distantPast
                            if pub < cutoff { continue }
                        }
                        let linkString = entry.links?.first(where: { link in
                            let rel = link.attributes?.rel
                            return rel == nil || rel == "alternate"
                        })?.attributes?.href ?? ""
                        guard let url = URL(string: (linkString.isEmpty ? (entry.id ?? "") : linkString).trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
                        // Filtrer les YouTube Shorts
                        let title = entry.title ?? entry.summary?.text ?? linkString
                        let rawDesc = entry.summary?.text
                        if isLikelyYouTubeShort(url: url, title: title, description: rawDesc) { continue }
                        let preferredAppleArtwork = isLegacyAppleRSSURL(feed.feedURL) ? preferredAppleArtworkURL(from: entry, articleURL: url) : nil
                        // Dédup par titre pour variations d'URL
                        if let existingByTitle = titleToArticleByFeed[feed.id]?[Self.normalizeTitle(title)] {
                            if let preferredAppleArtwork {
                                existingByTitle.imageURL = preferredAppleArtwork
                            } else if existingByTitle.imageURL == nil, let img = extractAtomImage(entry) {
                                existingByTitle.imageURL = upscaledAppleArtworkURL(img)
                            }
                            if existingByTitle.summary == nil || (existingByTitle.summary?.contains("<") == true), let s = extractPlainText(from: entry.summary?.text) { existingByTitle.summary = s }
                            if existingByTitle.contentHTML == nil, let h = entry.content?.text { existingByTitle.contentHTML = h }
                            if existingByTitle.publishedAt == nil, let effectivePublishedAt { existingByTitle.publishedAt = effectivePublishedAt }
                            rememberArticle(existingByTitle, url: url, guid: entry.id, title: title, feedId: feed.id)
                            continue
                        }
                        
                        var image: URL? = nil
                        if image == nil { image = preferredAppleArtwork }
                        if image == nil { image = upscaledAppleArtworkURL(extractAtomImage(entry)) }
                        if image == nil { image = upscaledAppleArtworkURL(extractImageURL(fromHTML: entry.content?.text ?? entry.summary?.text, baseURL: url)) }
                        if image == nil { image = extractBestImageURL(fromHTML: entry.content?.text ?? entry.summary?.text, baseURL: url) }
                        if image == nil { image = youtubeThumbnailURL(for: url) }
                        if image == nil { image = await fetchOgImage(from: url) }
                        image = upscaledAppleArtworkURL(image)
                        let guid = entry.id?.trimmingCharacters(in: .whitespacesAndNewlines)
                        // Préparer contenu nettoyé pour backfill et création
                        let rawHTML = entry.content?.text ?? entry.summary?.text
                        let cleanedText = extractPlainText(from: rawHTML)
                        let cleanedSummary = extractPlainText(from: entry.summary?.text) ?? cleanedText
                        if let existing = existingArticle(for: url, guid: guid) {
                            if let preferredAppleArtwork {
                                existing.imageURL = preferredAppleArtwork
                            } else if existing.imageURL == nil, let image {
                                existing.imageURL = image
                            }
                            if (existing.contentText == nil || existing.contentText?.isEmpty == true), let cleanedText { existing.contentText = cleanedText }
                            if existing.summary == nil || (existing.summary?.contains("<") == true) { existing.summary = cleanedSummary }
                            if existing.contentHTML == nil, let rawHTML { existing.contentHTML = rawHTML }
                            if existing.publishedAt == nil, let effectivePublishedAt { existing.publishedAt = effectivePublishedAt }
                            rememberArticle(existing, url: url, guid: guid, title: title, feedId: feed.id)
                            continue
                        }
                        if hasSeenArticle(url: url, guid: guid) { continue }

                        let article = Article(
                            feedId: feed.id,
                            title: title,
                            url: url,
                            author: entry.authors?.first?.name,
                            publishedAt: effectivePublishedAt,
                            contentHTML: rawHTML,
                            contentText: cleanedText,
                            imageURL: image,
                            summary: cleanedSummary,
                            readingTime: nil,
                            lang: nil,
                            score: nil
                        )
                        appLog("[FeedService] Creating Atom article: '\(title)' for feed '\(feed.title)' with feedId: \(feed.id)")
                        modelContext.insert(article)
                        createQuota -= 1
                        if stream { self.articles.append(article) }
                        rememberArticle(article, url: url, guid: guid, title: title, feedId: feed.id)
                        created.append(article)
                    }
                case .json(let json):
                    let items = json.items ?? []
                    logger.info("Parsed JSON items: \(items.count) for \(feed.feedURL.absoluteString, privacy: .public)")
                    appLog("[FeedService] JSON items: \(items.count)")
                    for item in items {
                        if createQuota <= 0 { break }
                        if let cutoff = earliestDate {
                            let pub = (item.datePublished ?? item.dateModified) ?? Date.distantPast
                            if pub < cutoff { continue }
                        }
                        let linkString = item.url ?? item.externalURL ?? item.id ?? ""
                        guard let url = URL(string: linkString.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
                        // Filtrer les YouTube Shorts
                        let title = item.title ?? (item.summary ?? linkString)
                        let rawDesc = item.summary
                        if isLikelyYouTubeShort(url: url, title: title, description: rawDesc) { continue }
                        if let existingByTitle = titleToArticleByFeed[feed.id]?[Self.normalizeTitle(title)] {
                            if existingByTitle.imageURL == nil, let imageURL = (item.image ?? item.bannerImage).flatMap({ URL(string: $0) }) { existingByTitle.imageURL = httpsOnlyImageURL(imageURL) }
                            if existingByTitle.summary == nil, let s = extractPlainText(from: item.summary) { existingByTitle.summary = s }
                            if existingByTitle.contentHTML == nil, let h = item.contentHtml { existingByTitle.contentHTML = h }
                            rememberArticle(existingByTitle, url: url, guid: item.id, title: title, feedId: feed.id)
                            continue
                        }
                        
                        var image: URL? = nil
                        if image == nil { image = (item.image ?? item.bannerImage).flatMap({ URL(string: $0) }) }
                        if image == nil { image = youtubeThumbnailURL(for: url) }
                        if image == nil { image = await fetchOgImage(from: url) }
                        image = httpsOnlyImageURL(image)
                        // Préparer contenu nettoyé pour backfill et création
                        let rawHTML = item.contentHtml
                        let cleanedText = extractPlainText(from: rawHTML) ?? item.contentText
                        let cleanedSummary = extractPlainText(from: item.summary) ?? cleanedText
                        if let existing = existingArticle(for: url, guid: item.id) {
                            if existing.imageURL == nil, let image { existing.imageURL = image }
                            if (existing.contentText == nil || existing.contentText?.isEmpty == true), let cleanedText { existing.contentText = cleanedText }
                            if existing.summary == nil || (existing.summary?.contains("<") == true) { existing.summary = cleanedSummary }
                            if existing.contentHTML == nil, let rawHTML { existing.contentHTML = rawHTML }
                            rememberArticle(existing, url: url, guid: item.id, title: title, feedId: feed.id)
                            continue
                        }
                        if hasSeenArticle(url: url, guid: item.id) { continue }

                        let article = Article(
                            feedId: feed.id,
                            title: title,
                            url: url,
                            author: item.author?.name,
                            publishedAt: item.datePublished ?? item.dateModified,
                            contentHTML: rawHTML,
                            contentText: cleanedText,
                            imageURL: image,
                            summary: cleanedSummary,
                            readingTime: nil,
                            lang: nil,
                            score: nil
                        )
                        appLog("[FeedService] Creating JSON article: '\(title)' for feed '\(feed.title)' with feedId: \(feed.id)")
                        modelContext.insert(article)
                        createQuota -= 1
                        if stream { self.articles.append(article) }
                        rememberArticle(article, url: url, guid: item.id, title: title, feedId: feed.id)
                        created.append(article)
                    }
                }
            } catch {
                // Fallback: essai d'un parseur minimal RSS 1.0 (RDF)
                logger.error("Failed to parse \(feed.feedURL.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)")
                appLogWarning("[FeedService] Parse error: \(error.localizedDescription). Trying RSS fallback…")
                do {
                    let rawData = try await fetchFeedData(from: feed.feedURL)
                    let data = sanitizeXMLDataForParsing(rawData)
                    let xml = decodeXMLString(from: data)
                    let createdCount = await parseRSSFallbackAndCreateArticles(xml: xml, feed: feed)
                    if createdCount > 0 {
                        appLog("[FeedService] RSS fallback created: \(createdCount) items")
                    } else {
                        appLogDebug("[FeedService] RSS fallback found 0 items")
                    }
                } catch {
                    // rien, on passe au flux suivant
                }
                continue
            }
        }
        try modelContext.save()
        // Nettoyage de sécurité: recharger puis supprimer les doublons stricts d'URL
        loadFeeds() // S'assurer que feeds est à jour
        loadArticles()
        let refreshedFeedIds = Set(targets.map { $0.id })
        await pruneUnavailableYouTubeArticles(for: refreshedFeedIds)
        removeDuplicateArticles()
        // Politique de rétention: supprimer >365 jours et limiter à 35 par flux
        enforceArticleRetentionPolicy(maxPerFeed: 35, maxAgeDays: 365)
        // Recharger après nettoyage pour avoir le compte exact
        loadArticles()
        logger.info("Refresh done — created: \(created.count), total stored: \(self.articles.count)")
        print("[FeedService] Refresh done — created: \(created.count), total: \(articles.count)")
        #else
        // Sans FeedKit, rien à faire
        loadArticles()
        logger.info("Refresh skipped — FeedKit not available")
        print("[FeedService] Refresh skipped — FeedKit not available")
        #endif
        // Enregistrer l'heure de dernière actualisation (utile pour le mur de flux)
        lastRefreshAt = Date()
        #if canImport(FeedKit)
        if created.isEmpty == false {
            discoveryRefreshTrigger += 1
        }
        #endif
        
        // Notifier nouveaux articles non lus : calculer la différence entre avant et après (hors musique)
        let musicFeedIdsForNotif = Set(
            feeds
                .filter { isMusicFeedURL($0.feedURL) || isMusicFeedURL($0.siteURL ?? $0.feedURL) }
                .map(\.id)
        )
        let unreadCountAfter = articles.filter { !$0.isRead && !musicFeedIdsForNotif.contains($0.feedId) }.count
        let newUnread = max(0, unreadCountAfter - unreadCountBefore)
        
        if newUnread > 0 {
            notifyNewArticles(count: newUnread)
        }
    }

    // MARK: - Notifications locales
    func requestNotificationPermissionIfNeeded() {
        #if canImport(UserNotifications)
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
        }
        #endif
    }

    /// Vérifie si les notifications sont activées dans les réglages
    private var notificationsEnabled: Bool {
        // Par défaut false si la clé n'existe pas (opt-in explicite)
        if UserDefaults.standard.object(forKey: "notificationsEnabled") == nil { return false }
        return UserDefaults.standard.bool(forKey: "notificationsEnabled")
    }
    
    /// Vérifie si les retours haptiques sont activés dans les réglages
    private var hapticsEnabled: Bool {
        // Par défaut true si la clé n'existe pas
        if UserDefaults.standard.object(forKey: "hapticsEnabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "hapticsEnabled")
    }

    private func notifyNewArticles(count: Int) {
        guard notificationsEnabled else { return }
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = count == 1 ? "1 nouvel article" : "\(count) nouveaux articles"
        content.body = Self.randomNewArticlesPhrase(count: count)
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.8, repeats: false)
        let req = UNNotificationRequest(identifier: "flux.new.articles.\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        #endif
    }

    private func notifyNewsletterReady() {
        guard notificationsEnabled else { return }
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = "Newsletter prête"
        content.body = "Votre newsletter a été générée."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.8, repeats: false)
        let req = UNNotificationRequest(identifier: "flux.newsletter.ready.\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        #endif
    }

    private func notifyNewsletterAudioReady() {
        guard notificationsEnabled else { return }
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = "Audio disponible"
        content.body = "La lecture de la newsletter est prête."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.8, repeats: false)
        let req = UNNotificationRequest(identifier: "flux.newsletter.audio.\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        #endif
    }

    // MARK: - Planning (3 créneaux par jour)
    private func loadNewsletterSchedule() {
        let d = UserDefaults.standard
        if let arr = d.array(forKey: "newsletter.schedule") as? [[String: Int]] {
            newsletterScheduleTimes = arr.compactMap { dict in
                guard let h = dict["h"], let m = dict["m"] else { return nil }
                var dc = DateComponents()
                dc.hour = h; dc.minute = m
                return dc
            }
        }
        if newsletterScheduleTimes.isEmpty {
            newsletterScheduleTimes = [
                DateComponents(hour: 9, minute: 0),
                DateComponents(hour: 12, minute: 0),
                DateComponents(hour: 19, minute: 0)
            ]
        }
    }

    func updateNewsletterSchedule(times: [DateComponents]) {
        newsletterScheduleTimes = Array(times.prefix(3))
        let save = newsletterScheduleTimes.compactMap { dc -> [String: Int]? in
            guard let h = dc.hour, let m = dc.minute else { return nil }
            return ["h": h, "m": m]
        }
        UserDefaults.standard.set(save, forKey: "newsletter.schedule")
        scheduleNewsletterTimers()
    }

    private func scheduleNewsletterTimers() {
        #if canImport(Foundation)
        for t in newsletterTimers { t.invalidate() }
        newsletterTimers.removeAll()
        // Reset des créneaux déjà déclenchés si on change de jour
        let todayKey = Self.newsletterDayKey(for: Date())
        let savedDay = UserDefaults.standard.string(forKey: "newsletter.lastFiredDay") ?? ""
        if savedDay != todayKey {
            newsletterLastFiredSlots.removeAll()
            UserDefaults.standard.set(todayKey, forKey: "newsletter.lastFiredDay")
            UserDefaults.standard.removeObject(forKey: "newsletter.firedSlots")
        } else {
            // Restaurer les créneaux déjà déclenchés aujourd'hui
            if let saved = UserDefaults.standard.array(forKey: "newsletter.firedSlots") as? [String] {
                newsletterLastFiredSlots = Set(saved)
            }
        }
        // Timer périodique qui vérifie toutes les 60 secondes si un créneau doit être déclenché
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.checkAndFireNewsletterSlots()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        newsletterTimers.append(timer)
        // Vérifier immédiatement au cas où un créneau a été manqué (réveil, lancement tardif)
        checkAndFireNewsletterSlots()
        // Observer le réveil du Mac pour rattraper les créneaux manqués
        #if canImport(AppKit)
        NotificationCenter.default.removeObserver(self, name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.checkAndFireNewsletterSlots()
            }
        }
        #endif
        #endif
    }

    private func checkAndFireNewsletterSlots() {
        let cal = Calendar.current
        let now = Date()
        let todayKey = Self.newsletterDayKey(for: now)
        // Nouveau jour : reset des créneaux déclenchés
        let savedDay = UserDefaults.standard.string(forKey: "newsletter.lastFiredDay") ?? ""
        if savedDay != todayKey {
            newsletterLastFiredSlots.removeAll()
            UserDefaults.standard.set(todayKey, forKey: "newsletter.lastFiredDay")
            UserDefaults.standard.removeObject(forKey: "newsletter.firedSlots")
        }
        for dc in newsletterScheduleTimes {
            let h = dc.hour ?? 9
            let m = dc.minute ?? 0
            let slotKey = "\(h):\(m)"
            // Déjà déclenché aujourd'hui ?
            guard !newsletterLastFiredSlots.contains(slotKey) else { continue }
            // Construire la date du créneau aujourd'hui
            guard let slotDate = cal.date(bySettingHour: h, minute: m, second: 0, of: now) else { continue }
            // Le créneau est passé (avec tolérance de 5 min max de retard accepté pour rattrapage)
            let elapsed = now.timeIntervalSince(slotDate)
            if elapsed >= 0 && elapsed < 5 * 60 * 60 {
                // Déclencher la génération
                newsletterLastFiredSlots.insert(slotKey)
                // Persister les créneaux déclenchés
                UserDefaults.standard.set(Array(newsletterLastFiredSlots), forKey: "newsletter.firedSlots")
                Task { await self.generateNewsletter() }
                // Un seul créneau à la fois
                break
            }
        }
    }

    private static func newsletterDayKey(for date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }

    // Quota IA supprimé: plus de suivi ni de limitation

    private static func randomNewArticlesPhrase(count: Int) -> String {
        let n = count
        let templates: [String] = [
            "\(n) actus toutes chaudes – servez-vous !",
            "J'ai rangé \(n) nouveaux onglets pour vous (sans pub).",
            "\(n) pépites d'info viennent d'arriver. À vos yeux !",
            "Breaking flux: \(n) articles ont franchi la douane du RSS.",
            "Le facteur a livré \(n) niouzes. Pas besoin de signature.",
            "\(n) nouveautés croustillantes, prêtes à être croquées.",
            "J'ai dépoussiéré \(n) titres rien que pour vous.",
            "La marée du web a laissé \(n) coquillages d'info.",
            "\(n) lectures fraîches – sans spoilers, promis.",
            "Flux en forme: +\(n) articles au compteur !"
        ]
        return templates.randomElement() ?? "\(n) nouveaux articles disponibles."
    }

    private func canonicalKey(for url: URL, guid: String?) -> String {
        // Normalise l'URL (supprime trailing slash, lowercasing host, supprime fragments, enlève utm_*, normalise http->https)
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        // Normaliser schéma http->https si possible
        if comps.scheme == "http" { comps.scheme = "https" }
        // Lowercase host
        var hostLowercased = comps.host?.lowercased()
        // Retirer sous-domaines mobiles/amp courants
        if let h = hostLowercased {
            for prefix in ["www.", "m.", "mobile.", "amp."] where h.hasPrefix(prefix) {
                hostLowercased = String(h.dropFirst(prefix.count))
                break
            }
        }
        comps.host = hostLowercased
        // Supprimer fragment
        comps.fragment = nil
        // Tri des query items et filtre tracking
        if let items = comps.queryItems, !items.isEmpty {
            let filtered = items.filter { name in
                let n = name.name.lowercased()
                // Supprime tracking et flags AMP
                if n.hasPrefix("utm_") { return false }
                if ["fbclid", "gclid", "mc_eid", "mc_cid", "amp", "amp_js_v", "usqp", "output", "outputtype"].contains(n) { return false }
                return true
            }
            comps.queryItems = filtered.sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
        }
        // Nettoyage de chemin: retirer suffixes AMP et index.html
        var normalizedPath = comps.path
        if normalizedPath.hasSuffix("/index.html") {
            normalizedPath.removeLast("/index.html".count)
        }
        if normalizedPath.hasSuffix("/amp/") { normalizedPath.removeLast(5) }
        else if normalizedPath.hasSuffix("/amp") { normalizedPath.removeLast(4) }
        comps.path = normalizedPath

        var normalized = comps.url?.absoluteString ?? url.absoluteString
        if normalized.hasSuffix("/") { normalized.removeLast() }
        // Utilise GUID si présent et stable
        if let g = guid?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
            return "guid://" + g
        }
        return normalized
    }

    private func removeDuplicateArticles() {
        print("[FeedService] Starting duplicate removal. Total articles: \(articles.count)")
        // 1) Debug: répartition par flux
        let articlesByFeed = Dictionary(grouping: articles) { $0.feedId }
        for (feedId, feedArticles) in articlesByFeed {
            let feedName = feeds.first(where: { $0.id == feedId })?.title ?? "Unknown"
            print("[FeedService] Feed '\(feedName)': \(feedArticles.count) articles")
        }

        let validFeedIds: Set<UUID> = Set(feeds.map { $0.id })
        var toDelete: [Article] = []

        // 2) Supprimer d'abord les articles dont le feedId n'existe plus
        for art in articles where !validFeedIds.contains(art.feedId) {
            print("[FeedService] INVALID FEED ID — Deleting: '\(art.title)' (feedId: \(art.feedId))")
            toDelete.append(art)
        }

        // 3) Déduplication par URL canonique, choisir le meilleur candidat à garder
        let remaining = articles.filter { validFeedIds.contains($0.feedId) }
        let groups = Dictionary(grouping: remaining) { article in
            let key = canonicalKey(for: article.url, guid: nil)
            let feed = feeds.first(where: { $0.id == article.feedId })
            let isMusic = feed.map { isMusicFeedURL($0.feedURL) || isMusicFeedURL($0.siteURL ?? $0.feedURL) } ?? false
            return isMusic ? "\(article.feedId.uuidString)::\(key)" : key
        }

        func isBetter(_ lhs: Article, than rhs: Article) -> Bool {
            // Meilleur si image présente
            let lhsHasImage = lhs.imageURL != nil
            let rhsHasImage = rhs.imageURL != nil
            if lhsHasImage != rhsHasImage { return lhsHasImage }
            // Ensuite le plus récent
            let lhsDate = lhs.publishedAt ?? Date.distantPast
            let rhsDate = rhs.publishedAt ?? Date.distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            // Sinon, garder le premier de manière déterministe via id
            return lhs.id.uuidString < rhs.id.uuidString
        }

        // 4) Deuxième passe: déduplication par similarité de titre dans un même feed (ex: variantes AMP)
        let byFeed: [UUID: [Article]] = Dictionary(grouping: articles.filter { validFeedIds.contains($0.feedId) }) { $0.feedId }
        for (feedId, items) in byFeed {
            if let feed = feeds.first(where: { $0.id == feedId }),
               isMusicFeedURL(feed.feedURL) || isMusicFeedURL(feed.siteURL ?? feed.feedURL) {
                continue
            }
            // Hash par titre normalisé (lowercased, collapse spaces)
            var map: [String: [Article]] = [:]
            for a in items {
                let key = a.title.lowercased()
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                map[key, default: []].append(a)
            }
            for (_, dupes) in map where dupes.count > 1 {
                let sorted = dupes.sorted { isBetter($0, than: $1) }
                for loser in sorted.dropFirst() { toDelete.append(loser) }
            }
        }

        for (key, items) in groups {
            guard items.count > 1 else { continue }
            // Choisir le meilleur article (image > date > id)
            let sorted = items.sorted { isBetter($0, than: $1) }
            // Le premier est le gagnant, supprimer les autres
            for loser in sorted.dropFirst() {
                let feedName = feeds.first(where: { $0.id == loser.feedId })?.title ?? "Unknown"
                print("[FeedService] DUPLICATE GROUP(\(key)) — Deleting: '\(loser.title)' from '\(feedName)'")
                toDelete.append(loser)
            }
        }

        print("[FeedService] Articles to delete: \(toDelete.count)")
        for art in Set(toDelete) { // éviter doublons d'effacement
            print("[FeedService] Deleting: '\(art.title)' from feed ID: \(art.feedId)")
            modelContext.delete(art)
        }

        if !toDelete.isEmpty {
            try? modelContext.save()
            loadArticles()
            logger.info("Removed duplicates: \(toDelete.count)")
            print("[FeedService] After deletion, total articles: \(articles.count)")
        }
    }

    // Supprime les articles trop anciens et limite le nombre d'articles conservés par flux
    private func enforceArticleRetentionPolicy(maxPerFeed: Int, maxAgeDays: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: Date()) ?? Date.distantPast
        var toDelete: Set<Article> = []

        // 1) Supprimer ceux plus vieux que cutoff
        for a in articles {
            if let feed = feeds.first(where: { $0.id == a.feedId }),
               isMusicFeedURL(feed.feedURL) || isMusicFeedURL(feed.siteURL ?? feed.feedURL) {
                continue
            }
            let pub = a.publishedAt ?? Date.distantPast
            if pub < cutoff {
                toDelete.insert(a)
            }
        }

        // 2) Pour chaque flux, garder seulement les plus récents (maxPerFeed)
        let byFeed: [UUID: [Article]] = Dictionary(grouping: articles) { $0.feedId }
        for (feedId, items) in byFeed {
            if let feed = feeds.first(where: { $0.id == feedId }),
               isMusicFeedURL(feed.feedURL) || isMusicFeedURL(feed.siteURL ?? feed.feedURL) {
                continue
            }
            // Trier par date décroissante (fallback distantPast)
            let sorted = items.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            if sorted.count > maxPerFeed {
                for old in sorted.suffix(from: maxPerFeed) { toDelete.insert(old) }
            }
        }

        guard !toDelete.isEmpty else { return }
        for a in toDelete { modelContext.delete(a) }
        do { try modelContext.save() } catch {}
        loadArticles()
        updateAppBadge()
        logger.info("Retention policy deleted: \(toDelete.count) articles")
    }

    // MARK: - App badge (macOS)
    private func updateAppBadge() {
        #if canImport(AppKit)
        let enabled = UserDefaults.standard.object(forKey: "badgeReadLaterEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "badgeReadLaterEnabled")
        if enabled {
            let saved = articles.filter { $0.isSaved }.count
            NSApplication.shared.dockTile.badgeLabel = saved > 0 ? String(saved) : ""
        } else {
            NSApplication.shared.dockTile.badgeLabel = ""
        }
        #endif
    }

    func refreshAppBadge() {
        updateAppBadge()
    }

    // MARK: - Auto refresh
    private func scheduleAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.refreshArticles(for: nil)
                } catch {
                    self.logger.error("Auto refresh failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
        // Débuter un premier refresh différé au démarrage
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            Task { try? await self?.refreshArticles(for: nil) }
        }
    }

    // MARK: - Audio résumé (GPT-5 + TTS) - DÉSACTIVÉ
    func toggleSpeakSummary(for feedId: UUID) {
        // Fonction désactivée - toutes les fonctions AI de lecture audio ont été supprimées
        return
    }

    // MARK: - Audio résumé d'un article (GPT + TTS) - DÉSACTIVÉ
    func toggleSpeakArticle(for article: Article) {
        // Fonction désactivée - toutes les fonctions AI de lecture audio ont été supprimées
        return
    }

    private func fetchArticleText(from url: URL) async -> String? {
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            // Limiter la taille pour éviter surconsommation mémoire
            let slice = data.prefix(1_500_000)
            let html = String(data: slice, encoding: .utf8) ?? String(data: slice, encoding: .isoLatin1) ?? ""
            if let text = extractPlainText(from: html), !text.isEmpty { return text }
            // Fallback basique: strip tags
            let stripped = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            let collapsed = stripped.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression, range: nil)
            let cleaned = htmlUnescape(collapsed).trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            return nil
        }
    }

    #if canImport(AVFoundation)
    func stopSpeaking() {
        // Stopper la lecture audio si en cours
        audioPlayer?.stop()
        audioPlayer = nil
        isAudioPlaying = false
        isAudioLoading = false
        isAudioOverlayVisible = false
    }
    #endif

    private func buildSummaryText(for feedId: UUID, limit: Int = 10) -> String {
        print("[DEBUG] buildSummaryText appelée pour feedId: \(feedId)")
        guard let feed = feeds.first(where: { $0.id == feedId }) else { return "" }
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let startOfYesterday = cal.date(byAdding: .day, value: -1, to: startOfToday) ?? Date.distantPast
        let items = articles
            .filter { $0.feedId == feedId && ($0.publishedAt ?? .distantPast) >= startOfYesterday }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            .prefix(limit)
        var lines: [String] = []
        lines.append("Résumé du flux \(feed.title):")
        for art in items {
            let base = art.summary ?? art.contentText ?? art.title
            let snippet = Self.firstSentences(from: base, maxCharacters: 240)
            lines.append("- \(art.title) — \(snippet)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - AI Features (Apple Foundation Models)
    
    // Fonctions IA activées ? (via Settings.aiProviderConfig.aiEnabled, défaut: true)
    func isAIFeaturesEnabled() -> Bool {
        if let data = (try? modelContext.fetch(FetchDescriptor<Settings>()))?.first?.aiProviderConfig,
           let cfg = try? JSONDecoder().decode(AIProviderConfig.self, from: data) {
            return cfg.aiEnabled ?? true
        }
        // Fallback UserDefaults si jamais on le stocke
        if UserDefaults.standard.object(forKey: "AI_ENABLED") != nil {
            return UserDefaults.standard.bool(forKey: "AI_ENABLED")
        }
        return true
    }

    // Activation de la génération audio de la newsletter ? (défaut: true)
    func isNewsletterAudioEnabled() -> Bool {
        if let data = (try? modelContext.fetch(FetchDescriptor<Settings>()))?.first?.aiProviderConfig,
           let cfg = try? JSONDecoder().decode(AIProviderConfig.self, from: data) {
            return cfg.newsletterAudioEnabled ?? true
        }
        return true
    }

    // Met à jour uniquement le flag de génération audio de la newsletter
    func updateNewsletterAudioEnabled(_ enabled: Bool) {
        do {
            let settings = (try modelContext.fetch(FetchDescriptor<Settings>()).first) ?? Settings()
            var existingAIEnabled: Bool? = nil
            if let data = settings.aiProviderConfig,
               let cfg = try? JSONDecoder().decode(AIProviderConfig.self, from: data) {
                existingAIEnabled = cfg.aiEnabled
            }
            let newCfg = AIProviderConfig(aiEnabled: existingAIEnabled, newsletterAudioEnabled: enabled)
            settings.aiProviderConfig = try JSONEncoder().encode(newCfg)
            if ((try? modelContext.fetch(FetchDescriptor<Settings>()))?.isEmpty ?? true) {
                modelContext.insert(settings)
            }
            try modelContext.save()
        } catch {
            logger.error("Failed to update newsletterAudioEnabled: \(error.localizedDescription)")
        }
    }

    private func currentTTSVoice() -> String {
        return "alloy"
    }

    #if canImport(AVFoundation)
    func playAudioData(_ data: Data, title: String?, icon: URL? = nil) throws {
        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
        // Update overlay
        audioOverlayTitle = title
        audioOverlayIcon = icon
        isAudioPlaying = true
        isAudioLoading = false
        isAudioOverlayVisible = true
        audioDuration = audioPlayer?.duration ?? 0
        audioCurrentTime = 0
        audioProgressTimer?.invalidate()
        audioProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.audioCurrentTime = self.audioPlayer?.currentTime ?? 0
            }
        }
    }

    // MARK: - Audio overlay controls
    func pauseAudio() {
        audioPlayer?.pause()
        isAudioPlaying = false
    }
    func resumeAudio() {
        audioPlayer?.play()
        isAudioPlaying = true
    }
    func stopAudio() {
        audioPlayer?.stop()
        isAudioPlaying = false
        isAudioLoading = false
        isAudioOverlayVisible = false
        audioProgressTimer?.invalidate()
        audioProgressTimer = nil
        audioOverlayIcon = nil
    }
    #endif
    
    private static func firstSentences(from text: String?, maxCharacters: Int) -> String {
        guard var t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return "" }
        if t.count > maxCharacters { t = String(t.prefix(maxCharacters)) + "…" }
        return t
    }

    // Génère une newsletter éditoriale (mur: tous flux), style article lisible
    func generateNewsletter() async {
        guard !isGeneratingNewsletter else { return }
        isGeneratingNewsletter = true
        
        #if os(macOS)
        if hapticsEnabled { HeartbeatHaptic.shared.start() }
        #endif
        
        // Effacer le contenu existant pour afficher le squelette de chargement
        newsletterContent = nil
        newsletterHeroURL = nil
        newsletterImageURLs = []
        newsletterArticleTitleImageMap = [:]
        defer {
            isGeneratingNewsletter = false
            #if os(macOS)
            if hapticsEnabled { HeartbeatHaptic.shared.stop() }
            #endif
        }

        // Sélection d'articles: aujourd'hui + hier
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? Date()
        // Ne garder que les articles du jour (minuit → minuit+1j)
        let musicIds = Set(
            feeds
                .filter { isMusicFeedURL($0.feedURL) || isMusicFeedURL($0.siteURL ?? $0.feedURL) }
                .map(\.id)
        )
        let wall = articles
            .filter { let d = $0.publishedAt ?? .distantPast; return d >= startOfToday && d < endOfToday && !musicIds.contains($0.feedId) }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        let deduped = deduplicateArticles(wall)
        guard !deduped.isEmpty else {
            aiErrorMessage = "Aucun article récent à synthétiser."
            return
        }

        // Images intercalées: sélectionner images valides non-YouTube
        // ET créer une map titre article (mots-clés) → image pour association correcte
        var titleImageMap: [String: URL] = [:]
        var withImages: [URL] = []
        for art in deduped {
            guard let imgURL = art.imageURL, !isYouTubeURL(art.url) else { continue }
            withImages.append(imgURL)
            // Extraire les mots-clés du titre (mots de 4+ caractères)
            let keywords = extractKeywords(from: art.title)
            for keyword in keywords {
                if titleImageMap[keyword] == nil {
                    titleImageMap[keyword] = imgURL
                }
            }
        }
        let fallbackHero = withImages.first
        // Exclure l'image hero par comparaison de string pour éviter les problèmes de comparaison d'URL
        let heroString = fallbackHero?.absoluteString ?? ""
        newsletterImageURLs = withImages.filter { $0.absoluteString != heroString }
        // Aussi exclure l'image hero du mapping mots-clés pour éviter les répétitions
        var filteredTitleImageMap: [String: URL] = [:]
        for (keyword, imageURL) in titleImageMap {
            if imageURL.absoluteString != heroString {
                filteredTitleImageMap[keyword] = imageURL
            }
        }
        newsletterArticleTitleImageMap = filteredTitleImageMap
        print("[Newsletter] Keywords-Image map: \(filteredTitleImageMap.count) entrées (après exclusion hero)")

        // Préparer les articles pour plusieurs sessions
        // Limite de 4096 tokens par session - on fait plusieurs sessions et on combine
        var articleBlocks: [String] = []
        for art in deduped.prefix(20) {
            let feedTitle = feeds.first(where: { $0.id == art.feedId })?.title ?? ""
            let snippet = Self.firstSentences(from: art.summary ?? art.contentText ?? art.title, maxCharacters: 180)
            articleBlocks.append("\(feedTitle): \(art.title) — \(snippet)")
        }
        let dateStr = Date().formatted(date: .complete, time: .omitted)

        func languageDirective() -> String {
            switch LocalizationManager.shared.currentLanguage {
            case .french: return "Réponds exclusivement en français."
            case .english: return "Answer exclusively in English."
            case .spanish: return "Responde exclusivamente en español."
            case .german: return "Antworte ausschließlich auf Deutsch."
            case .italian: return "Rispondi esclusivamente in italiano."
            case .portuguese: return "Responda exclusivamente em português."
            case .japanese: return "日本語でのみ回答してください。"
            case .chinese: return "请仅使用中文回答。"
            case .korean: return "한국어로만 답변하세요."
            case .russian: return "Отвечай исключительно на русском языке."
            }
        }

        // Instructions très courtes pour maximiser le contenu (limite 4096 tokens)
        func shortSystemPrompt() -> String {
            let lang = languageDirective()
            return "Rédacteur de newsletter. \(lang) Format: # Titre, ## Sections, paragraphes denses. Pas de ** dans titres."
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                // APPROCHE MULTI-SESSIONS: générer plusieurs sections puis combiner
                // Chaque session = 4096 tokens max, donc on fait plusieurs appels
                
                // Diviser les articles en groupes de 5
                let groups = stride(from: 0, to: articleBlocks.count, by: 5).map {
                    Array(articleBlocks[$0..<min($0 + 5, articleBlocks.count)])
                }
                
                var allSections: [String] = []
                var isFirst = true
                
                for group in groups.prefix(4) { // Max 4 groupes = 20 articles
                    let articlesText = group.joined(separator: "\n")
                    let prompt: String
                    if isFirst {
                        prompt = """
                        \(dateStr)
                        
                        Écris une newsletter avec # Titre puis des sections ## avec TOUJOURS un paragraphe de 2-3 phrases après chaque titre:
                        \(articlesText)
                        """
                    } else {
                        prompt = """
                        Écris UNIQUEMENT des sections ## (pas de # titre) avec TOUJOURS un paragraphe de 2-3 phrases après chaque titre:
                        \(articlesText)
                        """
                    }
                    
                    do {
                        // Nouvelle session pour chaque groupe
                        let session = LanguageModelSession(model: model, instructions: { shortSystemPrompt() })
                        let response = try await session.respond(to: prompt)
                        var content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // Pour les groupes suivants, supprimer tout H1 généré par erreur
                        if !isFirst {
                            content = content.components(separatedBy: "\n")
                                .filter { !$0.hasPrefix("# ") || $0.hasPrefix("## ") }
                                .joined(separator: "\n")
                        }
                        
                        if !content.isEmpty {
                            allSections.append(content)
                        }
                        isFirst = false
                    } catch {
                        print("[Newsletter] Erreur groupe: \(error.localizedDescription)")
                        // Continuer avec les autres groupes
                    }
                }
                
                guard !allSections.isEmpty else {
                    aiErrorMessage = "Erreur d'intelligence artificielle locale : aucun contenu généré"
                    return
                }
                
                // Combiner toutes les sections
                let combinedText = allSections.joined(separator: "\n\n")
                newsletterContent = normalizeNewsletterMarkdown(combinedText)
                
            case .unavailable(let reason):
                aiErrorMessage = "Intelligence artificielle locale indisponible : \(reason)"
                return
            @unknown default:
                aiErrorMessage = "Intelligence artificielle locale indisponible."
                return
            }
        } else {
            aiErrorMessage = "L'intelligence artificielle locale nécessite iOS/macOS 26."
            return
        }
        #else
        aiErrorMessage = "Intelligence artificielle locale indisponible sur cette version."
        return
        #endif
        newsletterGeneratedAt = Date()
        // Héro: image du mur (article le plus important/visible)
        newsletterHeroURL = fallbackHero
        newsletterHeroIsAI = false
        print("[Newsletter] Hero URL: \(fallbackHero?.absoluteString ?? "nil"), Images count: \(newsletterImageURLs.count)")
        
        #if os(macOS)
        HapticFeedback.success()
        #endif
        
        notifyNewsletterReady()
    }

    private func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("youtube.com") || host.contains("youtu.be")
    }

    private func extractYouTubeVideoId(from url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        if host.contains("youtube.com") {
            if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
               let videoId = items.first(where: { $0.name.lowercased() == "v" })?.value,
               !videoId.isEmpty {
                return videoId
            }
            let parts = url.pathComponents.filter { $0 != "/" }
            if let idx = parts.firstIndex(where: { $0 == "shorts" || $0 == "embed" || $0 == "live" }),
               idx + 1 < parts.count {
                let value = parts[idx + 1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return value.isEmpty ? nil : value
            }
        }
        if host.contains("youtu.be") {
            let value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private func isYouTubeVideoUnavailable(_ url: URL) async -> Bool {
        guard let videoId = extractYouTubeVideoId(from: url), !videoId.isEmpty else { return false }
        guard var comps = URLComponents(string: "https://www.youtube.com/oembed") else { return false }
        comps.queryItems = [
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(videoId)"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let oembedURL = comps.url else { return false }
        var req = URLRequest(url: oembedURL)
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            if (200...299).contains(http.statusCode) { return false }
            // Si YouTube ne renvoie pas 2xx (404/410/etc.), on considère la vidéo comme indisponible.
            return true
        } catch {
            // En cas d'erreur réseau locale, on ne supprime pas.
            return false
        }
    }

    private func pruneUnavailableYouTubeArticles(for feedIds: Set<UUID>) async {
        guard feedIds.isEmpty == false else { return }
        let candidates = articles.filter { feedIds.contains($0.feedId) && isYouTubeURL($0.url) }
        guard candidates.isEmpty == false else { return }

        var availabilityCache: [String: Bool] = [:]
        var removedCount = 0
        for article in candidates {
            let key = canonicalKey(for: article.url, guid: nil)
            let unavailable: Bool
            if let cached = availabilityCache[key] {
                unavailable = cached
            } else {
                let value = await isYouTubeVideoUnavailable(article.url)
                availabilityCache[key] = value
                unavailable = value
            }
            if unavailable {
                modelContext.delete(article)
                removedCount += 1
            }
        }
        guard removedCount > 0 else { return }
        do {
            try modelContext.save()
            loadArticles()
            appLog("[FeedService] Removed unavailable YouTube articles: \(removedCount)")
            logger.info("Removed unavailable YouTube articles: \(removedCount)")
        } catch {
            logger.error("Failed to delete unavailable YouTube articles: \(String(describing: error), privacy: .public)")
        }
    }

    // Envoi newsletter supprimé
    private func extractNewsletterTitle(from md: String) -> String? { return nil }

    private func normalizeNewsletterMarkdown(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        
        // Log pour debug
        let preview = result.prefix(300).replacingOccurrences(of: "\n", with: "\\n")
        print("[Newsletter Normalize] Input preview: \(preview)")
        
        // Nettoyer les ** des titres markdown existants: # **Titre** -> # Titre
        result = result.replacingOccurrences(of: #"(?m)^(#{1,6})\s*\*\*(.+?)\*\*\s*$"#, with: "$1 $2", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?m)^(#{1,6})\s*\*\*([^*]+)$"#, with: "$1 $2", options: .regularExpression)
        
        // IMPORTANT: Convertir ### en ## (newsletter n'a besoin que de 2 niveaux)
        result = result.replacingOccurrences(of: #"(?m)^###\s*"#, with: "## ", options: .regularExpression)
        
        // Convertir lignes en gras seules en H2: **Titre** -> ## Titre
        result = result.replacingOccurrences(of: #"(?m)^\*\*([^*\n]{3,100})\*\*\s*$"#, with: "## $1", options: .regularExpression)
        
        // Convertir lignes numérotées en H2: 1. Titre ou 1) Titre -> ## Titre
        result = result.replacingOccurrences(of: #"(?m)^\d{1,2}[\.\)]\s*([^\n]{3,100})$"#, with: "## $1", options: .regularExpression)
        
        // Assurer que # et ## ont un espace après
        result = result.replacingOccurrences(of: #"(?m)^##([^#\s])"#, with: "## $1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?m)^#([^#\s])"#, with: "# $1", options: .regularExpression)
        
        // Traitement ligne par ligne pour plus de contrôle
        let lines = result.components(separatedBy: "\n")
        var processedLines: [String] = []
        var foundH1 = false
        var prevLineEmpty = true
        
        for (idx, rawLine) in lines.enumerated() {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            let nextLineEmpty = idx + 1 < lines.count ? lines[idx + 1].trimmingCharacters(in: .whitespaces).isEmpty : true
            
            // Nettoyer ** dans les titres markdown
            if line.hasPrefix("#") {
                line = line.replacingOccurrences(of: "**", with: "")
            }
            
            // Heuristique: ligne courte (5-80 chars) entre lignes vides, commence par majuscule, sans ponctuation interne = probablement un titre
            let cleanLine = line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
            if !line.hasPrefix("#") && !line.hasPrefix("-") && !line.hasPrefix("*") && !line.isEmpty {
                let isShort = cleanLine.count >= 5 && cleanLine.count <= 80
                let startsWithUpper = cleanLine.first?.isUppercase == true
                let noInternalPunct = !cleanLine.dropLast().contains(".") && !cleanLine.dropLast().contains("!") && !cleanLine.dropLast().contains("?")
                let isIsolated = prevLineEmpty && nextLineEmpty
                
                if isShort && startsWithUpper && noInternalPunct && isIsolated {
                    if !foundH1 {
                        line = "# \(cleanLine)"
                        foundH1 = true
                    } else {
                        line = "## \(cleanLine)"
                    }
                }
            }
            
            // Tracker si on a trouvé un H1
            if line.hasPrefix("# ") && !line.hasPrefix("## ") && !line.hasPrefix("### ") {
                foundH1 = true
            }
            
            processedLines.append(line)
            prevLineEmpty = line.isEmpty
        }
        
        result = processedLines.joined(separator: "\n")
        
        // Supprimer les sections H2 vides (H2 suivi directement d'un autre titre ou de la fin)
        var finalLines: [String] = []
        let allLines = result.components(separatedBy: "\n")
        var i = 0
        while i < allLines.count {
            let line = allLines[i]
            if line.hasPrefix("## ") {
                // Vérifier s'il y a du contenu après ce H2 avant le prochain titre
                var hasContent = false
                var j = i + 1
                while j < allLines.count {
                    let nextLine = allLines[j].trimmingCharacters(in: .whitespaces)
                    if nextLine.hasPrefix("#") {
                        break // Prochain titre trouvé
                    }
                    if !nextLine.isEmpty && !nextLine.hasPrefix("SOURCES:") {
                        hasContent = true
                        break
                    }
                    j += 1
                }
                if hasContent {
                    finalLines.append(line)
                }
                // Sinon, on ignore ce H2 vide
            } else {
                finalLines.append(line)
            }
            i += 1
        }
        result = finalLines.joined(separator: "\n")
        
        // Log résultat
        let h1Count = result.components(separatedBy: "\n").filter { $0.hasPrefix("# ") && !$0.hasPrefix("## ") }.count
        let h2Count = result.components(separatedBy: "\n").filter { $0.hasPrefix("## ") && !$0.hasPrefix("### ") }.count
        print("[Newsletter Normalize] Output: H1=\(h1Count), H2=\(h2Count)")

        // Assurer un titre si l'IA n'en fournit pas ou si le titre est trop générique
        if h1Count == 0 {
            let fallbackTitle = fallbackNewsletterTitle()
            result = "# \(fallbackTitle)\n\n" + result
            print("[Newsletter Normalize] Injected fallback H1 title (missing)")
        } else {
            let lines = result.components(separatedBy: "\n")
            if let firstH1Index = lines.firstIndex(where: { $0.hasPrefix("# ") && !$0.hasPrefix("## ") }) {
                let rawTitle = String(lines[firstH1Index].dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                if isGenericNewsletterTitle(rawTitle) {
                    var newLines = lines
                    newLines[firstH1Index] = "# \(fallbackNewsletterTitle())"
                    result = newLines.joined(separator: "\n")
                    print("[Newsletter Normalize] Replaced generic H1 title")
                }
            }
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fallbackNewsletterTitle() -> String {
        let dateStr = Date().formatted(date: .abbreviated, time: .omitted)
        return LocalizationManager.shared.localizedString(.newsletterTitleWithDate, dateStr)
    }

    private func isGenericNewsletterTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let localizedBase = LocalizationManager.shared.localizedString(.newsletterTitle).lowercased()
        let generic = [
            "titre", "title", "newsletter", "ma newsletter", "my newsletter",
            "newsletter du jour", "daily newsletter"
        ]
        if generic.contains(t) { return true }
        if t == localizedBase { return true }
        if t.count < 4 { return true }
        return false
    }
    
    private func renderNewsletterHTML(title: String, markdown: String, heroCID: String) -> String {
        let styles = """
        body{margin:0;padding:0;background:#f5f6f8;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#111}
        .wrap{max-width:680px;margin:0 auto;padding:24px}
        .card{background:#fff;border-radius:14px;border:1px solid rgba(0,0,0,0.08);box-shadow:0 6px 18px rgba(0,0,0,0.08);overflow:hidden}
        .hero{width:100%;height:auto;display:block}
        h1{font-size:28px;line-height:1.2;margin:20px 20px 6px 20px}
        h2{font-size:20px;margin:18px 20px 8px 20px}
        p{font-size:15px;line-height:1.6;margin:0 20px 12px 20px}
        ul{margin:0 20px 12px 40px}
        .sources{margin:6px 20px 16px 20px;display:flex;gap:8px;flex-wrap:wrap}
        .sources img{width:18px;height:18px;border-radius:4px;border:1px solid rgba(0,0,0,0.08)}
        .footer{color:#6b7280;font-size:12px;padding:12px 20px 20px 20px}
        """
        var html = "<html><head><meta charset=\"utf-8\"><style>\(styles)</style></head><body><div class=\"wrap\"><div class=\"card\">"
        if newsletterHeroIsAI || (newsletterHeroURL != nil) {
            let hero = newsletterHeroIsAI ? "cid:\(heroCID)" : (newsletterHeroURL?.absoluteString ?? "")
            html += "<img class=\"hero\" src=\"\(hero)\" alt=\"\"/>"
        }
        // Convertir le markdown très simple (H1/H2/para/list)
        let lines = markdown.components(separatedBy: "\n")
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("# ") { html += "<h1>\(escapeHTML(String(line.dropFirst(2))))</h1>"; continue }
            if line.hasPrefix("## ") { html += "<h2>\(escapeHTML(String(line.dropFirst(3))))</h2>"; continue }
            if line.lowercased().hasPrefix("sources:") {
                let namesRaw = line.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
                let names = namesRaw.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if !names.isEmpty {
                    html += "<div class=\"sources\">"
                    for n in names {
                        let url = emailFaviconURL(for: n) ?? ""
                        let titleEsc = escapeHTML(n)
                        html += "<img src=\"\(url)\" alt=\"\(titleEsc)\" title=\"\(titleEsc)\"/>"
                    }
                    html += "</div>"
                }
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { html += "<ul><li>\(escapeHTML(String(line.dropFirst(2))))</li></ul>"; continue }
            if line.isEmpty { html += ""; continue }
            html += "<p>\(escapeHTML(line))</p>"
        }
        let footer = escapeHTML(localizedNewsletterFooterText())
        html += "<div class=\"footer\">\(footer)</div></div></div></body></html>"
        return html
    }

    // MARK: - Newsletter TTS
    func toggleSpeakNewsletter() {
        if isSpeakingNewsletter {
            stopAudio()
            isSpeakingNewsletter = false
            return
        }
        // Si audio prêt → jouer, sinon ignorer (génération asynchrone en tâche de fond)
        if let url = newsletterAudioURL, let data = try? Data(contentsOf: url) {
            #if canImport(AVFoundation)
            try? playAudioData(data, title: "Ma newsletter", icon: newsletterHeroURL)
            isSpeakingNewsletter = true
            #endif
        }
    }

    private func preGenerateNewsletterAudio() async {
        defer { isGeneratingNewsletterAudio = false; isAudioLoading = false }
        // Fonction désactivée - toutes les fonctions AI de lecture audio ont été supprimées
        return
    }

    private func markdownToPlain(_ md: String) -> String {
        let lines = md.components(separatedBy: "\n").map { l -> String in
            var s = l
            if s.hasPrefix("# ") { s.removeFirst(2) }
            if s.hasPrefix("## ") { s.removeFirst(3) }
            if s.lowercased().hasPrefix("sources:") { return "" }
            return s
        }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: "\\* ", with: "• ")
    }


    private func escapeHTML(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
        return t
    }

    private func localizedNewsletterFooterText() -> String {
        switch LocalizationManager.shared.currentLanguage {
        case .french:
            return "Généré par IA mais avec amour par Flux."
        case .english:
            return "Generated by AI, with love by Flux."
        case .spanish:
            return "Generado por IA, con amor por Flux."
        case .german:
            return "Von KI erstellt – mit Liebe von Flux."
        case .italian:
            return "Generato dall'IA, con amore da Flux."
        case .portuguese:
            return "Gerado por IA, com carinho pela Flux."
        case .japanese:
            return "AI によって生成、Flux の愛を込めて。"
        case .chinese:
            return "由 AI 生成，凝聚 Flux 的心意。"
        case .korean:
            return "AI가 생성했지만, Flux의 사랑을 담아."
        case .russian:
            return "Создано ИИ, с любовью от Flux."
        }
    }

    private func emailFaviconURL(for feedTitle: String) -> String? {
        if let feed = bestFeedMatch(forTitle: feedTitle) {
            if let f = feed.faviconURL { return f.absoluteString }
            if let site = feed.siteURL, let host = site.host, let scheme = site.scheme { return "\(scheme)://\(host)/favicon.ico" }
            if let host = feed.feedURL.host, let scheme = feed.feedURL.scheme { return "\(scheme)://\(host)/favicon.ico" }
            if let host = feed.siteURL?.host ?? feed.feedURL.host { return "https://icons.duckduckgo.com/ip3/\(host).ico" }
        }
        return nil
    }

    private func normalizeFeedTitle(_ s: String) -> String {
        return s.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private func bestFeedMatch(forTitle title: String) -> Feed? {
        let target = normalizeFeedTitle(title)
        if let exact = feeds.first(where: { normalizeFeedTitle($0.title) == target }) { return exact }
        if let contains = feeds.first(where: { normalizeFeedTitle($0.title).contains(target) || target.contains(normalizeFeedTitle($0.title)) }) { return contains }
        func dist(_ a: String, _ b: String) -> Int {
            let aChars = Array(a), bChars = Array(b)
            var dp = Array(repeating: Array(repeating: 0, count: bChars.count + 1), count: aChars.count + 1)
            for i in 0...aChars.count { dp[i][0] = i }
            for j in 0...bChars.count { dp[0][j] = j }
            if !aChars.isEmpty && !bChars.isEmpty {
                for i in 1...aChars.count {
                    for j in 1...bChars.count {
                        let cost = (aChars[i-1] == bChars[j-1]) ? 0 : 1
                        dp[i][j] = min(dp[i-1][j] + 1, dp[i][j-1] + 1, dp[i-1][j-1] + cost)
                    }
                }
            }
            return dp[aChars.count][bChars.count]
        }
        return feeds.min { a, b in dist(normalizeFeedTitle(a.title), target) < dist(normalizeFeedTitle(b.title), target) }
    }

    private func deduplicateArticles(_ items: [Article]) -> [Article] {
        // Déduplication naïve: clé = titre normalisé + host
        func key(for a: Article) -> String {
            let t = a.title.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            let host = a.url.host?.lowercased() ?? ""
            return "\(t)|\(host)"
        }
        var seen: Set<String> = []
        var out: [Article] = []
        for a in items {
            let k = key(for: a)
            if !seen.contains(k) {
                seen.insert(k)
                out.append(a)
            }
        }
        return out
    }

    // MARK: - Image helpers
    private func extractRSSImage(_ item: FeedKit.RSSFeedItem) -> URL? {
        // 1) media:thumbnail
        if let thumb = item.media?.thumbnails?.first?.attributes?.url, let u = URL(string: thumb) { return u }
        // 2) media:content (image medium)
        if let contents = item.media?.contents {
            for c in contents {
                if let type = c.attributes?.type, type.starts(with: "image/"), let s = c.attributes?.url, let u = URL(string: s) {
                    return u
                }
            }
        }
        // 3) enclosure type image
        if let e = item.enclosure?.attributes, let type = e.type, type.starts(with: "image/"), let s = e.url, let u = URL(string: s) {
            return u
        }
        return nil
    }

    private func extractAtomImage(_ entry: FeedKit.AtomFeedEntry) -> URL? {
        // 1) media:thumbnail
        if let thumb = entry.media?.thumbnails?.first?.attributes?.url, let u = URL(string: thumb) { return u }
        // 2) media:content image
        if let contents = entry.media?.contents {
            for c in contents {
                if let type = c.attributes?.type, type.starts(with: "image/"), let s = c.attributes?.url, let u = URL(string: s) {
                    return u
                }
            }
        }
        // 3) link rel=enclosure type image
        if let imageLink = entry.links?.first(where: { l in (l.attributes?.rel == "enclosure") && (l.attributes?.type?.starts(with: "image/") == true) })?.attributes?.href, let u = URL(string: imageLink) {
            return u
        }
        return nil
    }
    private func extractImageURL(fromHTML html: String?, baseURL: URL? = nil) -> URL? {
        guard let html, !html.isEmpty else { return nil }
        // Cherche <img src="..."> ou <img src='...'>
        do {
            let pattern = "<img[^>]*?src\\s*=\\s*(?:\\\"([^\\\"]+)\\\"|'([^']+)')"
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            if let m = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) {
                let group1 = m.range(at: 1)
                let group2 = m.range(at: 2)
                if let r = Range(group1.location != NSNotFound ? group1 : group2, in: html) {
                    let s = htmlUnescape(String(html[r]))
                    if let absolute = absolutizeURL(s, base: baseURL) { return absolute }
                }
            }
        } catch {}
        // Sinon, tenter srcset sur <img> ou <source>
        do {
            let pattern = "<(?:img|source)[^>]*?srcset\\s*=\\s*(?:\\\"([^\\\"]+)\\\"|'([^']+)')"
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            if let m = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) {
                let group1 = m.range(at: 1)
                let group2 = m.range(at: 2)
                if let r = Range(group1.location != NSNotFound ? group1 : group2, in: html) {
                    let raw = htmlUnescape(String(html[r]))
                    let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if let last = parts.last {
                        let urlString = last.split(separator: " ").first.map(String.init) ?? String(last)
                        if let absolute = absolutizeURL(urlString, base: baseURL) { return absolute }
                    }
                }
            }
        } catch {}
        return nil
    }
    
    private func fetchOgImage(from url: URL) async -> URL? {
        // Télécharge une petite portion de la page et cherche og:image/twitter:image
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            // User-Agent pour sites qui filtrent (The Verge, etc.)
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            let html = String(data: data.prefix(750_000), encoding: .utf8) ?? ""
            if let u = matchMeta(property: "og:image", in: html, base: url) { return u }
            if let u = matchMeta(property: "og:image:secure_url", in: html, base: url) { return u }
            if let u = matchMeta(property: "twitter:image", in: html, base: url) { return u }
            // <link rel="image_src" href="...">
            if let u = matchLinkRel(rel: "image_src", in: html, base: url) { return u }
            if let u = extractBestImageURL(fromHTML: html, baseURL: url) { return u }
            return extractImageURL(fromHTML: html, baseURL: url)
        } catch {
            return nil
        }
    }

    // Détection des URLs YouTube et génération d'une miniature (supporte watch/embed/live/shorts/youtu.be)
    private func youtubeThumbnailURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }
        // 1) watch?v=ID
        if host.contains("youtube.com"), let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let vid = items.first(where: { $0.name.lowercased() == "v" })?.value, !vid.isEmpty {
            return URL(string: "https://i.ytimg.com/vi/\(vid)/maxresdefault.jpg")
        }
        // 2) youtu.be/ID
        if host.contains("youtu.be") {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty { return URL(string: "https://i.ytimg.com/vi/\(path)/maxresdefault.jpg") }
        }
        // 3) embed/live/shorts
        if host.contains("youtube.com") {
            let comps = url.path.split(separator: "/").map(String.init)
            let keys = ["embed", "live", "shorts"]
            for key in keys {
                if let idx = comps.firstIndex(of: key), comps.count > idx+1 {
                    let id = comps[idx+1]
                    return URL(string: "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg")
                }
            }
        }
        return nil
    }

    // Détecte les URLs YouTube Shorts pour les exclure de l'affichage
    private func isLikelyYouTubeShort(url: URL, title: String?, description: String?) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()
        let full = url.absoluteString.lowercased()
        // 1) URL explicite contenant "/shorts" sur tout sous-domaine YouTube
        if host.contains("youtube") && (path.contains("/shorts") || full.contains("/shorts/")) { return true }
        // 2) youtu.be avec indices de short dans query
        if (host.contains("youtu.be") || host.contains("youtube")), let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            if items.contains(where: { ($0.name.lowercased() == "feature") && (($0.value ?? "").lowercased().contains("short")) }) { return true }
            if items.contains(where: { ($0.name.lowercased() == "si") && (($0.value ?? "").lowercased().contains("short")) }) { return true }
        }
        // 3) Heuristiques texte titre/description
        let hay = ((title ?? "") + " " + (description ?? "")).lowercased()
        if hay.contains("#shorts") || hay.contains(" shorts ") || hay.contains("shorts |") || hay.contains("| shorts") { return true }
        return false
    }
    
    private func matchMeta(property: String, in html: String, base: URL) -> URL? {
        do {
            // Accepte guillemets simples ou doubles sur property/name et content
            let pattern = "<meta[^>]*?(?:property|name)\\s*=\\s*(?:\\\"\(property)\\\"|'\(property)')[^>]*?content\\s*=\\s*(?:\\\"([^\\\"]+)\\\"|'([^']+)')"
                .replacingOccurrences(of: "\(property)", with: property)
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            if let m = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
               let r = Range(m.range(at: m.numberOfRanges > 2 && m.range(at: 1).location == NSNotFound ? 2 : 1), in: html) {
                let s = htmlUnescape(String(html[r]))
                return absolutizeURL(s, base: base)
            }
        } catch {}
        return nil
    }

    private func matchLinkRel(rel: String, in html: String, base: URL) -> URL? {
        do {
            let pattern = "<link[^>]*?rel\\s*=\\s*(?:\\\"\(rel)\\\"|'\(rel)')[^>]*?href\\s*=\\s*(?:\\\"([^\\\"]+)\\\"|'([^']+)')"
                .replacingOccurrences(of: "\(rel)", with: rel)
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            if let m = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) {
                let group1 = m.range(at: 1)
                let group2 = m.range(at: 2)
                if let r = Range(group1.location != NSNotFound ? group1 : group2, in: html) {
                    let s = htmlUnescape(String(html[r]))
                    return absolutizeURL(s, base: base)
                }
            }
        } catch {}
        return nil
    }

    private func htmlUnescape(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        return t
    }

    private func stripCData(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
        return t
    }

    private func sanitizeXMLDataForParsing(_ data: Data) -> Data {
        if var s = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(data: data, encoding: .ascii) {
            s = s.replacingOccurrences(of: "\u{FEFF}", with: "")
            if let idx = s.firstIndex(of: "<") {
                s = String(s[idx...])
            } else {
                s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return Data(s.utf8)
        }
        return data
    }

    private func decodeXMLString(from data: Data) -> String {
        if let s = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? String(data: data, encoding: .isoLatin1) {
            return s
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func looksLikeRSS1(_ xml: String) -> Bool {
        let lower = xml.lowercased()
        return lower.contains("<rdf:rdf") || lower.contains("<rdf:rdf ")
    }

    private func extractRSS1ChannelInfo(from xml: String, base: URL) -> (title: String?, link: URL?) {
        var title: String?
        var link: URL?
        do {
            let channelRegex = try NSRegularExpression(pattern: "<channel\\b[^>]*>([\\s\\S]*?)</channel>", options: [.caseInsensitive])
            let titleRegex = try NSRegularExpression(pattern: "<title[^>]*>([\\s\\S]*?)</title>", options: [.caseInsensitive])
            let prismTitleRegex = try NSRegularExpression(pattern: "<prism:publicationName[^>]*>([\\s\\S]*?)</prism:publicationName>", options: [.caseInsensitive])
            let linkRegex = try NSRegularExpression(pattern: "<link[^>]*>([^<]+)</link>", options: [.caseInsensitive])
            let rdfAboutRegex = try NSRegularExpression(pattern: "rdf:about\\s*=\\s*(?:\\\"([^\\\"]+)\\\"|'([^']+)')", options: [.caseInsensitive])
            let nsXML = xml as NSString
            if let cm = channelRegex.firstMatch(in: xml, options: [], range: NSRange(location: 0, length: nsXML.length)) {
                let block = nsXML.substring(with: cm.range(at: 1))
                let nsBlock = block as NSString
                if let tm = titleRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)),
                   let r = Range(tm.range(at: 1), in: block) {
                    title = htmlUnescape(String(block[r]).trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if title == nil,
                   let pm = prismTitleRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)),
                   let r = Range(pm.range(at: 1), in: block) {
                    title = htmlUnescape(String(block[r]).trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if let lm = linkRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)),
                   let r = Range(lm.range(at: 1), in: block) {
                    link = absolutizeURL(htmlUnescape(String(block[r]).trimmingCharacters(in: .whitespacesAndNewlines)), base: base)
                }
            }
            if link == nil {
                if let cm = channelRegex.firstMatch(in: xml, options: [], range: NSRange(location: 0, length: nsXML.length)) {
                    let openTag = nsXML.substring(with: NSRange(location: cm.range.location, length: cm.range.length))
                    let nsOpen = openTag as NSString
                    if let about = rdfAboutRegex.firstMatch(in: openTag, options: [], range: NSRange(location: 0, length: nsOpen.length)) {
                        let g1 = about.range(at: 1)
                        let g2 = about.range(at: 2)
                        if let r = Range(g1.location != NSNotFound ? g1 : g2, in: openTag) {
                            link = absolutizeURL(htmlUnescape(String(openTag[r])), base: base)
                        }
                    }
                }
            }
        } catch { }
        return (title, link)
    }

    // Fallback minimal pour RSS 1.0 (RDF)
    private func extractRSS1Items(from xml: String, base: URL) -> [(title: String, link: URL, description: String?, date: Date?, author: String?)] {
        var results: [(String, URL, String?, Date?, String?)] = []
        do {
            let itemRegex = try NSRegularExpression(pattern: "<item\\b[^>]*>([\\s\\S]*?)</item>", options: [.caseInsensitive])
            let openTagRegex = try NSRegularExpression(pattern: "<item\\b([^>]*)>", options: [.caseInsensitive])
            let linkRegex = try NSRegularExpression(pattern: "<link[^>]*>([^<]+)</link>", options: [.caseInsensitive])
            let titleRegex = try NSRegularExpression(pattern: "<title[^>]*>([\\s\\S]*?)</title>", options: [.caseInsensitive])
            let dcTitleRegex = try NSRegularExpression(pattern: "<dc:title[^>]*>([\\s\\S]*?)</dc:title>", options: [.caseInsensitive])
            let guidRegex = try NSRegularExpression(pattern: "<guid[^>]*>([^<]+)</guid>", options: [.caseInsensitive])
            let descRegex = try NSRegularExpression(pattern: "<description[^>]*>([\\s\\S]*?)</description>", options: [.caseInsensitive])
            let contentRegex = try NSRegularExpression(pattern: "<content:encoded[^>]*>([\\s\\S]*?)</content:encoded>", options: [.caseInsensitive])
            let pubDateRegex = try NSRegularExpression(pattern: "<pubDate[^>]*>([^<]+)</pubDate>", options: [.caseInsensitive])
            let dcDateRegex = try NSRegularExpression(pattern: "<(?:dc:)?date[^>]*>([^<]+)</(?:dc:)?date>", options: [.caseInsensitive])
            let dcCreatorRegex = try NSRegularExpression(pattern: "<(?:dc:)?creator[^>]*>([\\s\\S]*?)</(?:dc:)?creator>", options: [.caseInsensitive])
            let authorRegex = try NSRegularExpression(pattern: "<author[^>]*>([\\s\\S]*?)</author>", options: [.caseInsensitive])
            let rdfAboutRegex = try NSRegularExpression(pattern: "rdf:about\\s*=\\s*(?:\\\"([^\\\"]+)\\\"|'([^']+)')", options: [.caseInsensitive])
            let nsXML = xml as NSString
            var blocks: [String] = []
            let matches = itemRegex.matches(in: xml, options: [], range: NSRange(location: 0, length: nsXML.length))
            if !matches.isEmpty {
                appLogDebug("[FeedService] RSS 1.0 item regex matches: \(matches.count)")
                blocks = matches.map { nsXML.substring(with: $0.range) }
            } else {
                appLogDebug("[FeedService] RSS 1.0 item regex matches: 0, using scan fallback")
                blocks = extractRSS1ItemBlocks(from: xml)
                appLogDebug("[FeedService] RSS 1.0 scan blocks: \(blocks.count)")
            }
            for block in blocks {
                let nsBlock = block as NSString
                // Ouvrir le tag <item ...>
                var linkURL: URL? = nil
                if let open = openTagRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)) {
                    let openTag = nsBlock.substring(with: open.range(at: 0))
                    let nsOpen = openTag as NSString
                    if let about = rdfAboutRegex.firstMatch(in: openTag, options: [], range: NSRange(location: 0, length: nsOpen.length)) {
                        let g1 = about.range(at: 1)
                        let g2 = about.range(at: 2)
                        if let r = Range(g1.location != NSNotFound ? g1 : g2, in: openTag) {
                            linkURL = absolutizeURL(htmlUnescape(String(openTag[r])), base: base)
                        }
                    }
                }
                if linkURL == nil,
                   let lm = linkRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length))
                {
                    if let r = Range(lm.range(at: 1), in: block) {
                        linkURL = absolutizeURL(htmlUnescape(String(block[r]).trimmingCharacters(in: .whitespacesAndNewlines)), base: base)
                    }
                }
                if linkURL == nil,
                   let gm = guidRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)),
                   let r = Range(gm.range(at: 1), in: block) {
                    let g = htmlUnescape(String(block[r]).trimmingCharacters(in: .whitespacesAndNewlines))
                    if let u = absolutizeURL(g, base: base) { linkURL = u }
                }
                guard let finalLink = linkURL else { continue }
                var title: String = ""
                if let tm = titleRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)),
                   let r = Range(tm.range(at: 1), in: block) {
                    title = stripCData(htmlUnescape(String(block[r]).trimmingCharacters(in: .whitespacesAndNewlines)))
                }
                if title.isEmpty,
                   let tm = dcTitleRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)),
                   let r = Range(tm.range(at: 1), in: block) {
                    title = stripCData(htmlUnescape(String(block[r]).trimmingCharacters(in: .whitespacesAndNewlines)))
                }
                var desc: String? = nil
                if let dm = descRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)),
                   let r = Range(dm.range(at: 1), in: block) {
                    desc = stripCData(String(block[r]))
                }
                if desc == nil,
                   let dm = contentRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)),
                   let r = Range(dm.range(at: 1), in: block) {
                    desc = stripCData(String(block[r]))
                }
                var date: Date? = nil
                if let dm = pubDateRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)),
                   let r = Range(dm.range(at: 1), in: block) {
                    let ds = String(block[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                    date = parseISO8601OrRFC822(ds)
                }
                if date == nil,
                   let dm = dcDateRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)),
                   let r = Range(dm.range(at: 1), in: block) {
                    let ds = String(block[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                    date = parseISO8601OrRFC822(ds)
                }
                var author: String? = nil
                if let am = dcCreatorRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)),
                   let r = Range(am.range(at: 1), in: block) {
                    author = htmlUnescape(String(block[r]).trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if author == nil,
                   let am = authorRegex.firstMatch(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length)),
                   let r = Range(am.range(at: 1), in: block) {
                    author = htmlUnescape(String(block[r]).trimmingCharacters(in: .whitespacesAndNewlines))
                }
                results.append((title, finalLink, desc, date, author))
            }
        } catch { }
        return results
    }

    private func extractRSS1ItemBlocks(from xml: String) -> [String] {
        let lower = xml.lowercased()
        var blocks: [String] = []
        var searchRange = lower.startIndex..<lower.endIndex
        while let start = lower.range(of: "<item", range: searchRange) {
            guard let end = lower.range(of: "</item>", range: start.upperBound..<lower.endIndex) else { break }
            let block = String(xml[start.lowerBound..<end.upperBound])
            blocks.append(block)
            searchRange = end.upperBound..<lower.endIndex
        }
        return blocks
    }

    private func parseISO8601OrRFC822(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        if let d = iso2.date(from: s) { return d }
        let fmts = [
            "yyyy-MM-dd",
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm Z"
        ]
        for f in fmts {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = f
            if let d = df.date(from: s) { return d }
        }
        return nil
    }

    // Nettoie un HTML pour produire un texte lisible: supprime scripts/styles, normalise espaces, garde les sauts de ligne de base
    private func extractPlainText(from html: String?) -> String? {
        guard let html, !html.isEmpty else { return nil }
        #if canImport(SwiftSoup)
        do {
            let doc = try SwiftSoup.parse(html)
            // Supprime <script> et <style>
            try doc.select("script, style, noscript").remove()
            // Conserve les sauts sur <p>, <br>, <li>
            try doc.select("br").append("\n")
            try doc.select("p, li").prepend("\n")
            let text = try doc.text()
            let normalized = text.replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression, range: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = cleanMarkdownArtifacts(in: normalized)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            // Fallback: retire les tags via regex simple
            let stripped = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            let collapsed = stripped.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression, range: nil)
            let unescaped = htmlUnescape(collapsed).trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = cleanMarkdownArtifacts(in: unescaped)
            return cleaned.isEmpty ? nil : cleaned
        }
        #else
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let collapsed = stripped.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression, range: nil)
        let unescaped = htmlUnescape(collapsed).trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = cleanMarkdownArtifacts(in: unescaped)
        return cleaned.isEmpty ? nil : cleaned
        #endif
    }

    // Supprime les marqueurs markdown parasites dans les résumés/textes (ex: **, *, etc.)
    private func cleanMarkdownArtifacts(in text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        // Supprime les * de mise en emphase au milieu des phrases
        result = result.replacingOccurrences(of: #"(?<=\S)\*(?=\S)"#, with: "", options: .regularExpression)
        // Convertit les puces markdown en puces lisibles
        result = result.replacingOccurrences(of: #"(?m)^\s*[\*\-]\s+"#, with: "• ", options: .regularExpression)
        // Nettoie les étoiles restantes isolées
        result = result.replacingOccurrences(of: #"\s*\*\s*"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Extraction avancée: JSON-LD + plus grande entrée de srcset
    private func extractBestImageURL(fromHTML html: String?, baseURL: URL?) -> URL? {
        guard let html, !html.isEmpty else { return nil }
        // 1) JSON-LD (schema.org Article / NewsArticle)
        if let json = matchJsonLDBlock(in: html), let u = parseJsonLDForImage(json, base: baseURL) {
            return u
        }
        // 2) Plus grande image depuis srcset si multiple
        if let u = extractLargestFromSrcset(in: html, baseURL: baseURL) { return u }
        #if canImport(SwiftSoup)
        // 3) Scraping CSS pour The Verge et autres
        do {
            let doc = try SwiftSoup.parse(html)
            // The Verge: .duet--layout--entry-image img
            if let el = try doc.select(".duet--layout--entry-image img").first(), let srcset = try? el.attr("srcset"), !srcset.isEmpty {
                // prendre la plus grande du srcset
                var bestW = 0
                var best: String?
                for part in srcset.split(separator: ",") {
                    let tokens = part.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
                    guard let u = tokens.first else { continue }
                    var w = 0
                    if let wToken = tokens.dropFirst().first, wToken.hasSuffix("w") { w = Int(wToken.dropLast()) ?? 0 }
                    if w >= bestW { bestW = w; best = String(u) }
                }
                if let s = best, let absolute = absolutizeURL(s, base: baseURL) { return absolute }
            }
            if let el = try doc.select("picture source").first(), let ss = try? el.attr("srcset"), !ss.isEmpty {
                if let u = extractLargestFromSrcset(in: ss, baseURL: baseURL) { return u }
            }
            if let el = try doc.select("meta[property=og:image], meta[name=og:image], meta[name=twitter:image]").first(), let content = try? el.attr("content"), !content.isEmpty {
                if let u = absolutizeURL(htmlUnescape(content), base: baseURL) { return u }
            }
        } catch {}
        #endif
        return nil
    }

    private func matchJsonLDBlock(in html: String) -> String? {
        do {
            let pattern = "<script[^>]*type=\\\"application/ld\\+json\\\"[^>]*>([\\s\\S]*?)</script>"
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            if let m = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
               let r = Range(m.range(at: 1), in: html) {
                return String(html[r])
            }
        } catch {}
        return nil
    }

    private func parseJsonLDForImage(_ raw: String, base: URL?) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Recherche grossière d'un champ "image": peut être string ou objet/array
        do {
            if let data = text.data(using: .utf8),
               let jsonObj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let u = jsonLDImageURL(in: jsonObj) { return absolutizeURL(u, base: base) }
                if let graph = jsonObj["@graph"] as? [[String: Any]] {
                    for node in graph {
                        if let u = jsonLDImageURL(in: node) { return absolutizeURL(u, base: base) }
                    }
                }
            }
        } catch { }
        return nil
    }

    private func jsonLDImageURL(in obj: [String: Any]) -> String? {
        if let image = obj["image"] {
            if let s = image as? String { return s }
            if let dict = image as? [String: Any] {
                if let s = dict["url"] as? String { return s }
                if let s = dict["contentUrl"] as? String { return s }
            }
            if let arr = image as? [Any] {
                for it in arr {
                    if let s = it as? String { return s }
                    if let d = it as? [String: Any] {
                        if let s = d["url"] as? String { return s }
                        if let s = d["contentUrl"] as? String { return s }
                    }
                }
            }
        }
        if let primary = obj["primaryImageOfPage"] as? [String: Any], let s = primary["url"] as? String { return s }
        return nil
    }

    private func extractLargestFromSrcset(in html: String, baseURL: URL?) -> URL? {
        do {
            let pattern = "<(?:img|source)[^>]*?srcset\\s*=\\s*(?:\\\"([^\\\"]+)\\\"|'([^']+)')"
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            if let m = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) {
                let group1 = m.range(at: 1)
                let group2 = m.range(at: 2)
                if let r = Range(group1.location != NSNotFound ? group1 : group2, in: html) {
                    let raw = htmlUnescape(String(html[r]))
                    // Map (width -> url)
                    var bestWidth = 0
                    var bestURL: String?
                    for part in raw.split(separator: ",") {
                        let tokens = part.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
                        guard let u = tokens.first else { continue }
                        var width = 0
                        if let wToken = tokens.dropFirst().first, wToken.hasSuffix("w") {
                            width = Int(wToken.dropLast()) ?? 0
                        }
                        if width >= bestWidth { bestWidth = width; bestURL = String(u) }
                    }
                    if let s = bestURL, let absolute = absolutizeURL(s, base: baseURL) { return absolute }
                }
            }
        } catch {}
        return nil
    }

    private func absolutizeURL(_ raw: String, base: URL?) -> URL? {
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("//"), let scheme = base?.scheme { return URL(string: "\(scheme):\(raw)") }
        if let base { return URL(string: raw, relativeTo: base)?.absoluteURL }
        return URL(string: raw)
    }

    private func prettifyHost(_ host: String) -> String {
        // retire www.
        var h = host
        if h.hasPrefix("www.") { h.removeFirst(4) }
        // garder la partie avant le TLD (ex: theverge.com -> theverge)
        let core = h.split(separator: ".").first.map(String.init) ?? h
        // remplace tirets/underscores par espaces
        let spaced = core.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        // capitalise chaque mot
        return spaced.split(separator: " ").map { word in
            var w = String(word)
            if let first = w.first { w = String(first).uppercased() + String(w.dropFirst()) }
            return w
        }.joined(separator: " ")
    }
    
    /// Extrait les mots-clés significatifs d'un titre (mots de 4+ caractères, sans mots courants)
    private func extractKeywords(from title: String) -> [String] {
        let stopWords = Set(["pour", "avec", "dans", "this", "that", "from", "with", "have", "your", "more", "will", "about", "just", "like", "over", "such", "into", "than", "them", "some", "could", "been", "after", "which", "when", "there", "also", "what", "their", "only", "other", "then"])
        let words = title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !stopWords.contains($0) }
        return Array(Set(words)) // dédupliqué
    }
    
    private static func normalizeTitle(_ title: String) -> String {
        return title.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    #if canImport(FeedKit)
    // Build fallback: FeedKit non intégré ou API incompatible.
    private static func extractInfo(from _: FeedKit.Feed) -> (String, URL?, URL?) {
        return ("FeedKit non disponible", nil, nil)
    }
    #else
    private static func extractInfo(from _: Any) -> (String, URL?, URL?) {
        return ("Flux inconnu", nil, nil)
    }
    #endif

    func deleteFeed(_ feed: Feed) async throws {
        // Supprimer tous les articles associés à ce flux
        let articlesToDelete = articles.filter { $0.feedId == feed.id }
        for article in articlesToDelete {
            modelContext.delete(article)
        }
        
        // Supprimer le flux
        modelContext.delete(feed)
        
        #if os(macOS)
        HapticFeedback.tap()
        #endif
        
        // Sauvegarder les changements
        try modelContext.save()
        
        // Mettre à jour les listes locales
        loadFeeds()
        loadArticles()
        
        logger.info("Flux supprimé: \(feed.title), articles supprimés: \(articlesToDelete.count)")
    }

    private func defaultFaviconURL(for feed: Feed?) -> URL? {
        guard let feed else { return nil }
        if let explicit = feed.faviconURL { return explicit }
        if let site = feed.siteURL, let host = site.host, let scheme = site.scheme {
            return URL(string: "\(scheme)://\(host)/favicon.ico")
        }
        if let host = feed.feedURL.host, let scheme = feed.feedURL.scheme {
            return URL(string: "\(scheme)://\(host)/favicon.ico")
        }
        return nil
    }

    // Marque tous les articles comme lus (utilisé par le bouton global du mur de flux)
    func markAllFeedsVisited() async {
        var changed = false
        for article in articles where article.isRead == false {
            article.isRead = true
            changed = true
        }
        if changed {
            do {
                try modelContext.save()
                // Force une mise à jour observable des badges
                badgeUpdateTrigger += 1
                updateAppBadge()
                logger.info("Mark all feeds visited → all articles read")
            } catch {
                logger.error("Failed to mark all feeds visited: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // Marque tous les articles d'un flux comme lus (utilisé pour reset du badge à la visite)
    func markFeedVisited(feedId: UUID) async {
        var changed = false
        for article in articles where article.feedId == feedId {
            if article.isRead == false {
                article.isRead = true
                changed = true
            }
        }
        if changed {
            do {
                try modelContext.save()
                // Force une mise à jour observable des badges
                badgeUpdateTrigger += 1
                updateAppBadge()
                logger.info("Mark feed visited → all articles read for feedId: \(feedId)")
            } catch {
                logger.error("Failed to mark feed visited: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // Marque tous les articles d'un dossier comme lus
    func markFolderVisited(folderId: UUID) async {
        let feedIdsInFolder: Set<UUID> = Set(self.feeds.filter { $0.folderId == folderId }.map { $0.id })
        guard feedIdsInFolder.isEmpty == false else { return }
        var changed = false
        for article in articles where feedIdsInFolder.contains(article.feedId) {
            if article.isRead == false {
                article.isRead = true
                changed = true
            }
        }
        if changed {
            do {
                try modelContext.save()
                // Force une mise à jour observable des badges
                badgeUpdateTrigger += 1
                updateAppBadge()
                logger.info("Mark folder visited → all articles read for folderId: \(folderId)")
            } catch {
                logger.error("Failed to mark folder visited: \(String(describing: error), privacy: .public)")
            }
        }
    }

    enum FeedError: Error, LocalizedError {
        case invalidURL, duplicate, feedKitNotFound, feedNotFound, importVersionIncompatible, invalidImportData, invalidJSONFormat, invalidConfigurationFormat, filePermissionDenied
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "URL invalide"
            case .duplicate: return "Ce flux existe déjà"
            case .feedKitNotFound: return "FeedKit introuvable (SPM)"
            case .feedNotFound: return "Aucun flux RSS trouvé. Vérifiez que le site propose un flux RSS ou essayez avec l'URL directe du flux."
            case .importVersionIncompatible: return "Version de configuration incompatible"
            case .invalidImportData: return "Données d'import vides ou invalides"
            case .invalidJSONFormat: return "Format JSON invalide"
            case .invalidConfigurationFormat: return "Format de configuration incompatible"
            case .filePermissionDenied: return "Permission refusée pour lire le fichier. Veuillez sélectionner le fichier via le dialogue d'import."
            }
        }
    }

    private func ensureFavicons() async {
        for feed in feeds where feed.faviconURL == nil {
            if let url = await discoverFaviconURL(for: feed) {
                feed.faviconURL = url
                do { try modelContext.save() } catch {
                    logger.error("Failed to save favicon for feed: \(feed.title, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Gestion de la liste de lecture
    
    /// Bascule l'état favori d'un article
    func toggleFavorite(for article: Article) async {
        article.isSaved.toggle()
        do {
            try modelContext.save()
            loadArticles()
            updateAppBadge()
            #if os(macOS)
            HapticFeedback.tap()
            #endif
            logger.info("Article favori basculé: \(article.title), isSaved: \(article.isSaved)")
        } catch {
            logger.error("Failed to toggle favorite: \(String(describing: error), privacy: .public)")
        }
    }

    /// Supprime un article de la base de données
    func deleteArticle(_ article: Article) async {
        do {
            modelContext.delete(article)
            try modelContext.save()
            loadArticles()
            #if os(macOS)
            HapticFeedback.tap()
            #endif
            logger.info("Article supprimé: \(article.title)")
        } catch {
            logger.error("Failed to delete article: \(String(describing: error), privacy: .public)")
        }
    }

    /// Retourne tous les articles à lire plus tard
    var favoriteArticles: [Article] {
        return articles.filter { $0.isSaved }.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }
    
    /// Retourne le nombre d'articles à lire plus tard
    var favoriteArticlesCount: Int {
        return articles.filter { $0.isSaved }.count
    }

    var readerNotesCount: Int {
        readerNotes.count
    }

    @discardableResult
    func addReaderNote(
        selectedText rawText: String,
        articleTitle: String,
        articleURL: URL,
        articleImageURL: URL? = nil,
        articleSource: String? = nil,
        articlePublishedAt: Date? = nil,
        articleId: UUID? = nil,
        feedId: UUID? = nil
    ) -> Bool {
        let cleanedText = normalizeReaderNoteText(rawText)
        let cleanedTitle = articleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty, !cleanedTitle.isEmpty else { return false }

        let articleKey = canonicalReaderNoteArticleKey(for: articleURL)
        let normalizedTextKey = normalizeReaderNoteLookupKey(cleanedText)
        if readerNotes.contains(where: {
            canonicalReaderNoteArticleKey(for: $0.articleURL) == articleKey
            && normalizeReaderNoteLookupKey($0.selectedText) == normalizedTextKey
        }) {
            #if os(macOS)
            HapticFeedback.alignment()
            #endif
            return false
        }

        let note = ReaderNote(
            articleId: articleId,
            feedId: feedId,
            articleTitle: cleanedTitle,
            articleURL: articleURL,
            articleImageURL: articleImageURL,
            articleSource: articleSource,
            articlePublishedAt: articlePublishedAt,
            selectedText: cleanedText
        )
        modelContext.insert(note)

        do {
            try modelContext.save()
            loadReaderNotes()
            #if os(macOS)
            HapticFeedback.success()
            #endif
            logger.info("Reader note saved for article: \(cleanedTitle, privacy: .public)")
            return true
        } catch {
            logger.error("Failed to save reader note: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func deleteReaderNote(_ note: ReaderNote) {
        do {
            modelContext.delete(note)
            try modelContext.save()
            loadReaderNotes()
            #if os(macOS)
            HapticFeedback.tap()
            #endif
            logger.info("Reader note deleted: \(note.articleTitle, privacy: .public)")
        } catch {
            logger.error("Failed to delete reader note: \(String(describing: error), privacy: .public)")
        }
    }

    private func normalizeReaderNoteText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeReaderNoteLookupKey(_ text: String) -> String {
        normalizeReaderNoteText(text)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private func canonicalReaderNoteArticleKey(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        components?.query = nil
        return components?.url?.absoluteString ?? url.absoluteString
    }

    private func discoverFaviconURL(for feed: Feed) async -> URL? {
        let baseURL: URL? = feed.siteURL ?? URL(string: (feed.feedURL.scheme ?? "https") + "://" + (feed.feedURL.host ?? ""))
        guard let site = baseURL.flatMap({ httpsOnlyURL(from: $0) }), let host = site.host else {
            return nil
        }
        // Try HTML <link rel>
        do {
            var req = URLRequest(url: site)
            req.timeoutInterval = 10
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            if let html = String(data: data, encoding: .utf8) {
                if let u = matchLinkRel(rel: "apple-touch-icon", in: html, base: site), let https = httpsOnlyURL(from: u) { return https }
                if let u = matchLinkRel(rel: "icon", in: html, base: site), let https = httpsOnlyURL(from: u) { return https }
                if let u = matchLinkRel(rel: "shortcut icon", in: html, base: site), let https = httpsOnlyURL(from: u) { return https }
                if let u = matchLinkRel(rel: "mask-icon", in: html, base: site), let https = httpsOnlyURL(from: u) { return https }
            }
        } catch {
            // ignore
        }
        // Fallback /favicon.ico
        if let scheme = site.scheme, let url = URL(string: "\(scheme)://\(host)/favicon.ico") {
            return url
        }
        // DuckDuckGo ip3 fallback
        if let url = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico") {
            return url
        }
        return nil
    }
    
    // MARK: - Export/Import de configuration
    
    /// Exporte la configuration complète de l'application (flux, dossiers, paramètres)
    func exportConfiguration() async throws -> Data {
        logger.info("Starting configuration export...")
        
        // S'assurer que les données sont chargées
        let currentFeeds: [Feed]
        let currentFolders: [Folder]
        
        do {
            currentFeeds = try modelContext.fetch(FetchDescriptor<Feed>())
            logger.info("Loaded \(currentFeeds.count) feeds for export")
        } catch {
            logger.error("Failed to fetch feeds: \(error)")
            currentFeeds = feeds
        }
        
        do {
            currentFolders = try modelContext.fetch(FetchDescriptor<Folder>())
            logger.info("Loaded \(currentFolders.count) folders for export")
        } catch {
            logger.error("Failed to fetch folders: \(error)")
            currentFolders = folders
        }
        
        // Créer les données d'export
        let feedsData = currentFeeds.map { feed -> FeedExportData in
            FeedExportData(
                id: feed.id,
                title: feed.title,
                siteURL: feed.siteURL?.absoluteString,
                feedURL: feed.feedURL.absoluteString,
                faviconURL: feed.faviconURL?.absoluteString,
                tags: feed.tags,
                addedAt: feed.addedAt,
                sortIndex: feed.sortIndex,
                folderId: feed.folderId,
                isYouTube: isYouTubeFeed(feed)
            )
        }
        
        let foldersData = currentFolders.map { folder -> FolderExportData in
            FolderExportData(
                id: folder.id,
                name: folder.name,
                sortIndex: folder.sortIndex,
                createdAt: folder.createdAt
            )
        }
        
        // Paramètres (optionnel)
        let settingsData: SettingsExportData?
        do {
            if let settings = try modelContext.fetch(FetchDescriptor<Settings>()).first {
                settingsData = SettingsExportData(
                    theme: settings.theme,
                    ttsVoice: settings.ttsVoice,
                    ttsRate: settings.ttsRate,
                    preferredLangs: settings.preferredLangs,
                    aiProviderConfig: settings.aiProviderConfig,
                    imageScrapingEnabled: settings.imageScrapingEnabled,
                    windowBlurEnabled: settings.windowBlurEnabled,
                    hideTitleOnThumbnails: settings.hideTitleOnThumbnails,
                    filterAdsEnabled: settings.filterAdsEnabled
                )
                logger.info("Loaded settings for export")
            } else {
                settingsData = nil
                logger.info("No settings found for export")
            }
        } catch {
            logger.error("Failed to fetch settings: \(error)")
            settingsData = nil
        }
        
        // Créer la configuration
        let configuration = FluxConfiguration(
            version: "1.0",
            exportedAt: Date(),
            feeds: feedsData,
            folders: foldersData,
            settings: settingsData
        )
        
        logger.info("Created configuration with \(feedsData.count) feeds and \(foldersData.count) folders")
        
        // Encoder en JSON
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(configuration)
            logger.info("Successfully encoded configuration to JSON (\(data.count) bytes)")
            return data
        } catch {
            logger.error("Failed to encode configuration: \(error)")
            throw error
        }
    }
    
    /// Importe une configuration depuis des données JSON
    func importConfiguration(from data: Data) async throws -> ImportSummary {
        logger.info("Starting import of configuration (\(data.count) bytes)")
        
        // Vérifier que les données ne sont pas vides
        guard !data.isEmpty else {
            logger.error("Import failed: Empty data")
            throw FeedError.invalidImportData
        }
        
        // Vérifier que c'est du JSON valide
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [])
            logger.info("JSON format validation passed")
        } catch {
            logger.error("Import failed: Invalid JSON format - \(error)")
            throw FeedError.invalidJSONFormat
        }
        
        // Décoder la configuration
        let configuration: FluxConfiguration
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            configuration = try decoder.decode(FluxConfiguration.self, from: data)
            logger.info("Successfully decoded configuration")
        } catch {
            logger.error("Import failed: Failed to decode configuration - \(error)")
            throw FeedError.invalidConfigurationFormat
        }
        
        // Vérifier la version de compatibilité
        guard configuration.version == "1.0" || configuration.version == "1.1" else {
            throw FeedError.importVersionIncompatible
        }
        
        // Importer les dossiers d'abord (les flux peuvent y être associés)
        var newFolderMapping: [UUID: UUID] = [:]
        var importedFolders = 0
        var skippedFolders = 0
        
        for folderData in configuration.folders {
            // Vérifier si un dossier avec ce nom existe déjà
            let existingFolder = folders.first { $0.name == folderData.name }
            if let existing = existingFolder {
                newFolderMapping[folderData.id] = existing.id
                skippedFolders += 1
            } else {
                // Créer un nouveau dossier
                let newFolder = Folder(
                    id: UUID(),
                    name: folderData.name,
                    sortIndex: folderData.sortIndex,
                    createdAt: folderData.createdAt
                )
                modelContext.insert(newFolder)
                newFolderMapping[folderData.id] = newFolder.id
                importedFolders += 1
            }
        }
        
        // Importer les flux
        var importedFeeds = 0
        var skippedFeeds = 0
        
        for feedData in configuration.feeds {
            // Vérifier si ce flux existe déjà (par URL)
            guard let feedURL = URL(string: feedData.feedURL) else { continue }
            
            if !feeds.contains(where: { $0.feedURL == feedURL }) {
                let newFeed = Feed(
                    id: UUID(),
                    title: feedData.title,
                    siteURL: feedData.siteURL != nil ? URL(string: feedData.siteURL!) : nil,
                    feedURL: feedURL,
                    faviconURL: feedData.faviconURL != nil ? URL(string: feedData.faviconURL!) : nil,
                    tags: feedData.tags,
                    addedAt: feedData.addedAt,
                    sortIndex: feedData.sortIndex,
                    folderId: feedData.folderId != nil ? newFolderMapping[feedData.folderId!] : nil
                )
                modelContext.insert(newFeed)
                importedFeeds += 1
            } else {
                skippedFeeds += 1
            }
        }
        
        // Importer les paramètres (optionnel)
        if let settingsData = configuration.settings {
            if let existingSettings = try? modelContext.fetch(FetchDescriptor<Settings>()).first {
                // Mettre à jour les paramètres existants
                existingSettings.theme = settingsData.theme
                existingSettings.ttsVoice = settingsData.ttsVoice
                existingSettings.ttsRate = settingsData.ttsRate
                existingSettings.preferredLangs = settingsData.preferredLangs
                existingSettings.aiProviderConfig = settingsData.aiProviderConfig
                existingSettings.imageScrapingEnabled = settingsData.imageScrapingEnabled
                existingSettings.windowBlurEnabled = settingsData.windowBlurEnabled
                existingSettings.hideTitleOnThumbnails = settingsData.hideTitleOnThumbnails
                if let filterAds = settingsData.filterAdsEnabled {
                    existingSettings.filterAdsEnabled = filterAds
                }
            } else {
                // Créer de nouveaux paramètres
                let newSettings = Settings(
                    id: UUID(),
                    theme: settingsData.theme,
                    ttsVoice: settingsData.ttsVoice,
                    ttsRate: settingsData.ttsRate,
                    preferredLangs: settingsData.preferredLangs,
                    aiProviderConfig: settingsData.aiProviderConfig,
                    imageScrapingEnabled: settingsData.imageScrapingEnabled,
                    windowBlurEnabled: settingsData.windowBlurEnabled,
                    hideTitleOnThumbnails: settingsData.hideTitleOnThumbnails,
                    filterAdsEnabled: settingsData.filterAdsEnabled ?? false
                )
                modelContext.insert(newSettings)
            }
        }
        
        // Sauvegarder tous les changements
        try modelContext.save()

        // Recharger les données
        loadFeeds()
        loadFolders()

        let summary = ImportSummary(
            importedFeeds: importedFeeds,
            importedFolders: importedFolders,
            skippedFeeds: skippedFeeds,
            skippedFolders: skippedFolders
        )
        
        logger.info("Configuration importée avec succès: \(importedFeeds) flux, \(importedFolders) dossiers importés")
        
        return summary
    }
    
    /// Vérifie si un flux est un flux YouTube
    private func isYouTubeFeed(_ feed: Feed) -> Bool {
        let host = (feed.siteURL?.host ?? feed.feedURL.host ?? "").lowercased()
        return host.contains("youtube.com") || host.contains("youtu.be")
    }
    
    /// Supprime tout le contenu de l'application (flux, dossiers, paramètres)
    func deleteAllContent() async throws {
        logger.info("Starting deletion of all content...")
        
        // Supprimer tous les flux
        let feedsToDelete = try modelContext.fetch(FetchDescriptor<Feed>())
        for feed in feedsToDelete {
            modelContext.delete(feed)
        }
        logger.info("Deleted \(feedsToDelete.count) feeds")
        
        // Supprimer tous les dossiers
        let foldersToDelete = try modelContext.fetch(FetchDescriptor<Folder>())
        for folder in foldersToDelete {
            modelContext.delete(folder)
        }
        logger.info("Deleted \(foldersToDelete.count) folders")
        
        // Supprimer tous les articles
        let articlesToDelete = try modelContext.fetch(FetchDescriptor<Article>())
        for article in articlesToDelete {
            modelContext.delete(article)
        }
        logger.info("Deleted \(articlesToDelete.count) articles")
        
        // Supprimer toutes les suggestions
        let suggestionsToDelete = try modelContext.fetch(FetchDescriptor<Suggestion>())
        for suggestion in suggestionsToDelete {
            modelContext.delete(suggestion)
        }
        logger.info("Deleted \(suggestionsToDelete.count) suggestions")

        // Supprimer toutes les notes lecteur
        let notesToDelete = try modelContext.fetch(FetchDescriptor<ReaderNote>())
        for note in notesToDelete {
            modelContext.delete(note)
        }
        logger.info("Deleted \(notesToDelete.count) reader notes")
        
        // Supprimer les paramètres
        let settingsToDelete = try modelContext.fetch(FetchDescriptor<Settings>())
        for setting in settingsToDelete {
            modelContext.delete(setting)
        }
        logger.info("Deleted \(settingsToDelete.count) settings")
        
        // Sauvegarder les changements
        try modelContext.save()
        
        // Vider le cache URL
        URLCache.shared.removeAllCachedResponses()
        appLog("[FeedService] URL cache cleared")
        
        // Vider le cache WebKit (images, données de sites)
        #if os(macOS)
        await WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date.distantPast
        )
        appLog("[FeedService] WebKit data store cleared")
        #endif

        // Recharger les données (vide les tableaux)
        loadFeeds()
        loadFolders()
        loadArticles()
        loadReaderNotes()
        
        appLog("[FeedService] All content deleted successfully - feeds: \(feeds.count), folders: \(folders.count), articles: \(articles.count)")
        logger.info("All content deleted successfully")
    }

    private func fetchYouTubeChannelIdFromRedirect(_ url: URL) async -> String? {
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("en-US,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        req.setValue(Self.youTubeConsentCookie, forHTTPHeaderField: "Cookie")
        req.timeoutInterval = 12
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let finalURL = response.url, let r = finalURL.path.range(of: "/channel/") {
                let id = String(finalURL.path[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if id.hasPrefix("UC") { return id }
            }
        } catch { }
        return nil
    }

    private func verifyYouTubeChannelIdMatchesHandle(_ channelId: String, expectedHandle: String) async -> Bool {
        guard channelId.hasPrefix("UC") else { return false }
        let urls: [URL] = [
            URL(string: "https://www.youtube.com/channel/\(channelId)")!,
            URL(string: "https://www.youtube.com/channel/\(channelId)/about")!
        ]
        let needle1 = "/@" + expectedHandle.lowercased()
        for u in urls {
            var req = URLRequest(url: u)
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            req.setValue("en-US,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            req.setValue(Self.youTubeConsentCookie, forHTTPHeaderField: "Cookie")
            req.timeoutInterval = 12
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                if let html = String(data: data, encoding: .utf8)?.lowercased() {
                    // Chercher canonicalBaseUrl, vanityChannelUrl, ou rel=canonical pointant vers le handle
                    if html.contains("\"canonicalbaseurl\":\"" + needle1) ||
                       html.contains("\"vanitychannelurl\":\"" + needle1) ||
                       html.contains("rel=\"canonical\" href=\"https://www.youtube.com" + needle1 + "\"") ||
                       html.contains("rel=\\\"canonical\\\" href=\\\"https://www.youtube.com" + needle1 + "\\\"") {
                        return true
                    }
                }
            } catch { continue }
        }
        return false
    }
}
