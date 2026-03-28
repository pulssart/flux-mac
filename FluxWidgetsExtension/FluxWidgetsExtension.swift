import SwiftUI
import WidgetKit
import AppIntents
import OSLog
import ImageIO
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#elseif os(iOS)
import UIKit
typealias PlatformImage = UIImage
#endif

private func copyTextToPlatformPasteboard(_ text: String) {
    #if os(macOS)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    #elseif os(iOS)
    UIPasteboard.general.string = text
    #endif
}

private func openURLOnCurrentPlatform(_ url: URL) {
    #if os(macOS)
    NSWorkspace.shared.open(url)
    #endif
}

private func platformImageFromCGImage(_ cgImage: CGImage) -> PlatformImage {
    #if os(macOS)
    NSImage(cgImage: cgImage, size: .zero)
    #elseif os(iOS)
    UIImage(cgImage: cgImage)
    #endif
}

private func platformImageFromFileURL(_ fileURL: URL) -> PlatformImage? {
    #if os(macOS)
    NSImage(contentsOf: fileURL)
    #elseif os(iOS)
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return UIImage(data: data)
    #endif
}

private extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #elseif os(iOS)
        self.init(uiImage: platformImage)
        #endif
    }
}



// MARK: - Notes widget actions (run without launching the app UI)

struct NotesWidgetNavigateIntent: AppIntent {
    static var title: LocalizedStringResource = "Navigate notes widget"
    static var description = IntentDescription("Move to the previous/next note in the Notes widget.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Delta")
    var delta: Int

    init() {}
    init(delta: Int) { self.delta = delta }

    func perform() async throws -> some IntentResult {
        let notes = WidgetShared.loadNotes()
        let total = notes.count
        guard total > 0 else { return .result() }

        let defaults = UserDefaults(suiteName: WidgetShared.appGroupId)
        let key = "notesWidget.selectedIndex"
        let current = defaults?.integer(forKey: key) ?? 0
        let next = (current + delta) % total
        let wrapped = next < 0 ? (next + total) : next
        defaults?.set(wrapped, forKey: key)

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.notesWidgetKind)
        return .result()
    }
}

struct NotesWidgetCopyIntent: AppIntent {
    static var title: LocalizedStringResource = "Copy note text"
    static var description = IntentDescription("Copy the current note text from the Notes widget.")
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        let notes = WidgetShared.loadNotes()
        let total = notes.count
        guard total > 0 else { return .result() }

        let defaults = UserDefaults(suiteName: WidgetShared.appGroupId)
        let key = "notesWidget.selectedIndex"
        let idx = defaults?.integer(forKey: key) ?? 0
        let normalized = ((idx % total) + total) % total
        let text = notes[normalized].selectedText

        copyTextToPlatformPasteboard(text)

        return .result()
    }
}

struct NotesWidgetOpenInBrowserIntent: AppIntent {
    static var title: LocalizedStringResource = "Open note in browser"
    static var description = IntentDescription("Open the note's article URL in the default browser.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "URL")
    var urlString: String

    init() { self.urlString = "" }
    init(url: URL) { self.urlString = url.absoluteString }

    func perform() async throws -> some IntentResult {
        if let url = URL(string: urlString) {
            openURLOnCurrentPlatform(url)
        }
        return .result()
    }
}

struct ReadLaterOpenInBrowserIntent: AppIntent {
    static var title: LocalizedStringResource = "Open read later article in browser"
    static var description = IntentDescription("Open the saved article URL in the default browser.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "URL")
    var urlString: String

    init() { self.urlString = "" }
    init(url: URL) { self.urlString = url.absoluteString }

    func perform() async throws -> some IntentResult {
        if let url = URL(string: urlString) {
            openURLOnCurrentPlatform(url)
        }
        return .result()
    }
}

enum WidgetShared {
    static let appGroupId = "group.com.adriendonot.fluxapp"
    static let dataDirectory = "Library/Application Support/widget-data"
    static let feedsFileName = "feeds.json"
    static let latestByFeedFileName = "latestByFeed.json"
    static let feedDigestByFeedFileName = "feedDigestByFeed.json"
    static let wallArticlesFileName = "wallArticles.json"
    // New kind to bypass stale macOS WidgetKit cache entries (CHSErrorDomain 1103).
    static let widgetKind = "DernierArticleWidgetSourceV2"
    static let feedDigestWidgetKind = "FeedDigestWidgetSourceV1"
    static let wallWidgetKind = "FluxWallWidgetV1"
    static let wallWidgetSelectionKey = "wallWidget.selectedIndex"
    static let wallWidgetAutoplayKey = "wallWidget.isAutoplaying"
    static let wallWidgetAutoplayAnchorDateKey = "wallWidget.autoplayAnchorDate"
    static let wallWidgetAutoplayAnchorIndexKey = "wallWidget.autoplayAnchorIndex"
    static let wallWidgetAutoplayInterval: TimeInterval = 15
    static let imageDirectory = "Library/Application Support/widget-data/images"
    static let legacyImageDirectory = "Library/Caches/widget-images"
    static let notesFileName = "notes.json"
    static let notesWidgetKind = "NotesWidgetV2"      // keep existing widgets working
    static let savedArticlesFileName = "savedArticles.json"
    static let readLaterWidgetKind = "ReadLaterWidgetV2"
    static let favoriteSignalsFileName = "favoriteSignals.json"
    static let favoriteSignalWidgetKind = "FavoriteSignalWidgetV2"

    static func sharedDataDirectoryURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else {
            return nil
        }
        return containerURL.appendingPathComponent(dataDirectory, isDirectory: true)
    }
}

struct ArticleSnapshot: Codable {
    let id: UUID
    let title: String
    let url: URL
    let imageURL: URL?
    let imageFileName: String?
    let feedTitle: String
    let publishedAt: Date?
    let isSaved: Bool
}

struct FeedMeta: Codable {
    let id: UUID
    let title: String
}

struct FeedDigestSnapshot: Codable {
    let feedTitle: String
    let articles: [ArticleSnapshot]
}

struct ReaderNoteSnapshot: Codable, Identifiable {
    let id: UUID
    let articleTitle: String
    let articleURL: URL
    let articleImageURL: URL?
    let articleSource: String?
    let articlePublishedAt: Date?
    let selectedText: String
    let createdAt: Date
}

struct FavoriteSignalSnapshot: Codable, Identifiable {
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

extension WidgetShared {
    static func wallWidgetDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    static func normalizedWallWidgetIndex(_ index: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        let modulo = index % total
        return modulo < 0 ? modulo + total : modulo
    }

    static func wallWidgetAutoplayEnabled(defaults: UserDefaults? = wallWidgetDefaults()) -> Bool {
        defaults?.bool(forKey: wallWidgetAutoplayKey) ?? false
    }

    static func currentWallWidgetIndex(
        total: Int,
        now: Date = .now,
        defaults: UserDefaults? = wallWidgetDefaults()
    ) -> Int {
        guard total > 0 else { return 0 }

        let selectedIndex = normalizedWallWidgetIndex(
            defaults?.integer(forKey: wallWidgetSelectionKey) ?? 0,
            total: total
        )

        guard wallWidgetAutoplayEnabled(defaults: defaults) else {
            return selectedIndex
        }

        let anchorIndex = normalizedWallWidgetIndex(
            defaults?.integer(forKey: wallWidgetAutoplayAnchorIndexKey) ?? selectedIndex,
            total: total
        )
        let anchorDate = defaults?.object(forKey: wallWidgetAutoplayAnchorDateKey) as? Date ?? now
        let elapsed = max(0, now.timeIntervalSince(anchorDate))
        let steps = Int(elapsed / wallWidgetAutoplayInterval)
        return normalizedWallWidgetIndex(anchorIndex + steps, total: total)
    }

    static func setWallWidgetSelection(
        index: Int,
        total: Int,
        defaults: UserDefaults? = wallWidgetDefaults()
    ) {
        defaults?.set(normalizedWallWidgetIndex(index, total: total), forKey: wallWidgetSelectionKey)
    }

    static func setWallWidgetAutoplay(
        enabled: Bool,
        currentIndex: Int,
        total: Int,
        now: Date = .now,
        defaults: UserDefaults? = wallWidgetDefaults()
    ) {
        let normalizedIndex = normalizedWallWidgetIndex(currentIndex, total: total)
        defaults?.set(normalizedIndex, forKey: wallWidgetSelectionKey)
        defaults?.set(enabled, forKey: wallWidgetAutoplayKey)

        if enabled {
            defaults?.set(normalizedIndex, forKey: wallWidgetAutoplayAnchorIndexKey)
            defaults?.set(now, forKey: wallWidgetAutoplayAnchorDateKey)
        } else {
            defaults?.removeObject(forKey: wallWidgetAutoplayAnchorIndexKey)
            defaults?.removeObject(forKey: wallWidgetAutoplayAnchorDateKey)
        }
    }

    static func fluxAppIconImage() -> Image? {
        #if os(macOS)
        guard let appBundleURL = hostAppBundleURL() else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: appBundleURL.path)
        icon.size = NSSize(width: 64, height: 64)
        return Image(platformImage: icon)
        #elseif os(iOS)
        return Image("FluxIcon").renderingMode(.original)
        #endif
    }

    private static func hostAppBundleURL() -> URL? {
        var currentURL = Bundle.main.bundleURL

        while currentURL.path != "/" {
            if currentURL.pathExtension == "app" {
                return currentURL
            }
            currentURL.deleteLastPathComponent()
        }

        return nil
    }

    static func loadFeedMetas() -> [FeedMeta] {
        guard
            let feedsFileURL = sharedDataDirectoryURL()?
                .appendingPathComponent(feedsFileName, isDirectory: false),
            let data = try? Data(contentsOf: feedsFileURL),
            let decoded = try? JSONDecoder().decode([FeedMeta].self, from: data)
        else {
            return []
        }
        return decoded
    }

    static func loadFeedDigests() -> [String: FeedDigestSnapshot] {
        guard
            let digestFileURL = sharedDataDirectoryURL()?
                .appendingPathComponent(feedDigestByFeedFileName, isDirectory: false),
            let data = try? Data(contentsOf: digestFileURL),
            let decoded = try? JSONDecoder().decode([String: FeedDigestSnapshot].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    static func loadWallArticles() -> [ArticleSnapshot] {
        guard
            let wallFileURL = sharedDataDirectoryURL()?
                .appendingPathComponent(wallArticlesFileName, isDirectory: false),
            let data = try? Data(contentsOf: wallFileURL),
            let decoded = try? JSONDecoder().decode([ArticleSnapshot].self, from: data)
        else {
            return []
        }
        return decoded
    }
    
    static func loadSavedArticles() -> [ArticleSnapshot] {
        guard
            let savedFileURL = sharedDataDirectoryURL()?
                .appendingPathComponent(savedArticlesFileName, isDirectory: false),
            let data = try? Data(contentsOf: savedFileURL),
            let decoded = try? JSONDecoder().decode([ArticleSnapshot].self, from: data)
        else {
            return []
        }
        return decoded
    }

    static func loadNotes() -> [ReaderNoteSnapshot] {
        guard
            let notesFileURL = sharedDataDirectoryURL()?
                .appendingPathComponent(notesFileName, isDirectory: false),
            let data = try? Data(contentsOf: notesFileURL),
            let decoded = try? JSONDecoder().decode([ReaderNoteSnapshot].self, from: data)
        else {
            return []
        }
        return decoded
    }

    static func loadFavoriteSignals() -> [FavoriteSignalSnapshot] {
        guard
            let fileURL = sharedDataDirectoryURL()?
                .appendingPathComponent(favoriteSignalsFileName, isDirectory: false),
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([FavoriteSignalSnapshot].self, from: data)
        else {
            return []
        }
        return decoded
    }
}

struct WallWidgetNavigateIntent: AppIntent {
    static var title: LocalizedStringResource = "Navigate wall widget"
    static var description = IntentDescription("Move to the previous or next article in the Flux wall widget.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Delta")
    var delta: Int

    init() {}
    init(delta: Int) { self.delta = delta }

    func perform() async throws -> some IntentResult {
        let articles = WidgetShared.loadWallArticles()
        let total = articles.count
        guard total > 0 else { return .result() }

        let defaults = WidgetShared.wallWidgetDefaults()
        let now = Date()
        let current = WidgetShared.currentWallWidgetIndex(total: total, now: now, defaults: defaults)
        let next = WidgetShared.normalizedWallWidgetIndex(current + delta, total: total)

        if WidgetShared.wallWidgetAutoplayEnabled(defaults: defaults) {
            WidgetShared.setWallWidgetAutoplay(
                enabled: true,
                currentIndex: next,
                total: total,
                now: now,
                defaults: defaults
            )
        } else {
            WidgetShared.setWallWidgetSelection(index: next, total: total, defaults: defaults)
        }

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.wallWidgetKind)
        return .result()
    }
}

struct WallWidgetAutoplayIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle wall autoplay"
    static var description = IntentDescription("Start or stop automatic article rotation in the Flux wall widget.")
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        let articles = WidgetShared.loadWallArticles()
        let total = articles.count
        guard total > 0 else { return .result() }

        let defaults = WidgetShared.wallWidgetDefaults()
        let now = Date()
        let current = WidgetShared.currentWallWidgetIndex(total: total, now: now, defaults: defaults)
        let shouldEnable = WidgetShared.wallWidgetAutoplayEnabled(defaults: defaults) == false

        WidgetShared.setWallWidgetAutoplay(
            enabled: shouldEnable,
            currentIndex: current,
            total: total,
            now: now,
            defaults: defaults
        )

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.wallWidgetKind)
        return .result()
    }
}

struct FeedEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Flux")
    static var defaultQuery = FeedEntityQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: title))
    }
}

struct FeedEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FeedEntity] {
        let all = WidgetShared.loadFeedMetas().map { meta in
            FeedEntity(id: meta.id.uuidString, title: meta.title)
        }
        let lookup = Set(identifiers)
        return all.filter { lookup.contains($0.id) }
    }

    func suggestedEntities() async throws -> [FeedEntity] {
        WidgetShared.loadFeedMetas().map { meta in
            FeedEntity(id: meta.id.uuidString, title: meta.title)
        }
    }
}

struct SelectFeedIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choisir un flux"
    static var description = IntentDescription("Choisis le flux affiché par le widget.")
    static var parameterSummary: some ParameterSummary {
        Summary("Source : \(\.$feed)")
    }

    @Parameter(title: "Flux")
    var feed: FeedEntity?

    init() {
        self.feed = nil
    }

    init(feed: FeedEntity?) {
        self.feed = feed
    }
}

struct FavoriteSignalEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Signal favori")
    static var defaultQuery = FavoriteSignalEntityQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: title))
    }
}

struct FavoriteSignalEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FavoriteSignalEntity] {
        let all = WidgetShared.loadFavoriteSignals().map {
            FavoriteSignalEntity(id: $0.id, title: $0.title)
        }
        let lookup = Set(identifiers)
        return all.filter { lookup.contains($0.id) }
    }

    func suggestedEntities() async throws -> [FavoriteSignalEntity] {
        WidgetShared.loadFavoriteSignals().map {
            FavoriteSignalEntity(id: $0.id, title: $0.title)
        }
    }
}

struct SelectFavoriteSignalIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choisir un signal"
    static var description = IntentDescription("Choisis le signal favori affiché par le widget.")
    static var parameterSummary: some ParameterSummary {
        Summary("Signal : \(\.$signal)")
    }

    @Parameter(title: "Signal")
    var signal: FavoriteSignalEntity?

    init() {
        self.signal = nil
    }

    init(signal: FavoriteSignalEntity?) {
        self.signal = signal
    }
}

// MARK: - Timeline entry & provider

struct DernierArticleEntry: TimelineEntry {
    let date: Date
    let article: ArticleSnapshot?
    let imageData: Data?
}

struct DernierArticleProvider: TimelineProvider {
    private let logger = Logger(subsystem: "FluxWidgetsExtension", category: "DernierArticleProvider")

    func placeholder(in context: Context) -> DernierArticleEntry {
        DernierArticleEntry(
            date: .now,
            article: ArticleSnapshot(
                id: UUID(),
                title: "Article d'exemple",
                url: URL(string: "https://example.com")!,
                imageURL: nil,
                imageFileName: nil,
                feedTitle: "Mon flux",
                publishedAt: .now,
                isSaved: false
            ),
            imageData: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DernierArticleEntry) -> Void) {
        Task {
            completion(await loadEntry(for: nil))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DernierArticleEntry>) -> Void) {
        Task {
            let entry = await loadEntry(for: nil)
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    fileprivate func loadEntry(for selectedFeedID: String?) async -> DernierArticleEntry {
        guard
            let latestFileURL = WidgetShared.sharedDataDirectoryURL()?
                .appendingPathComponent(WidgetShared.latestByFeedFileName, isDirectory: false),
            let data = try? Data(contentsOf: latestFileURL)
        else {
            return DernierArticleEntry(date: .now, article: nil, imageData: nil)
        }

        let snapshotsByFeed: [String: ArticleSnapshot] = {
            guard let decoded = try? JSONDecoder().decode([String: ArticleSnapshot].self, from: data) else { return [:] }
            return decoded
        }()

        let latestAvailableArticle = snapshotsByFeed.values
            .sorted(by: { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) })
            .first

        let article: ArticleSnapshot? = {
            if let selectedFeedID, let selected = snapshotsByFeed[selectedFeedID] {
                return selected
            }
            return latestAvailableArticle
        }()

        guard let article else {
            return DernierArticleEntry(date: .now, article: nil, imageData: nil)
        }

        let cachedFileName = article.imageFileName ?? "\(article.id.uuidString).jpg"
        if let cachedImageData = loadCachedImageData(fileName: cachedFileName) {
            logger.info("Widget image loaded from cache: \(cachedFileName, privacy: .public), bytes=\(cachedImageData.count)")
            print("[WidgetDebug] cache image OK \(cachedFileName) bytes=\(cachedImageData.count)")
            return DernierArticleEntry(date: .now, article: article, imageData: cachedImageData)
        }
        logger.notice("Widget cache miss: \(cachedFileName, privacy: .public)")

        let imageData = await fetchImageData(for: article)
        if let imageData {
            _ = cacheImageData(imageData, fileName: cachedFileName)
            logger.info("Widget image loaded from network for article: \(article.id.uuidString, privacy: .public), bytes=\(imageData.count)")
            print("[WidgetDebug] network image OK \(article.id.uuidString) bytes=\(imageData.count)")
            return DernierArticleEntry(date: .now, article: article, imageData: imageData)
        }

        logger.error("Widget image unavailable for article: \(article.id.uuidString, privacy: .public)")
        print("[WidgetDebug] image unavailable \(article.id.uuidString)")
        return DernierArticleEntry(date: .now, article: article, imageData: imageData)
    }

    private func loadCachedImageData(fileName: String?) -> Data? {
        guard let fileName else {
            logger.error("[ImageLoad] loadCachedImageData: fileName is nil")
            return nil
        }
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetShared.appGroupId
        ) else {
            logger.error("[ImageLoad] loadCachedImageData: containerURL is nil for appGroupId=\(WidgetShared.appGroupId, privacy: .public)")
            return nil
        }
        let preferredURL = containerURL
            .appendingPathComponent(WidgetShared.imageDirectory, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        let fileExists = FileManager.default.fileExists(atPath: preferredURL.path)
        logger.info("[ImageLoad] preferredURL=\(preferredURL.path, privacy: .public) exists=\(fileExists)")
        if let data = try? Data(contentsOf: preferredURL) {
            logger.info("[ImageLoad] loaded \(data.count) bytes from preferred path")
            return data
        }
        logger.error("[ImageLoad] Data(contentsOf:) failed for \(preferredURL.path, privacy: .public)")

        // Compat: lire aussi l'ancien emplacement (Caches) le temps de migrer.
        let legacyURL = containerURL
            .appendingPathComponent(WidgetShared.legacyImageDirectory, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        if let data = try? Data(contentsOf: legacyURL) {
            logger.info("[ImageLoad] loaded \(data.count) bytes from legacy path")
            return data
        }
        logger.error("[ImageLoad] Data(contentsOf:) also failed for legacy path \(legacyURL.path, privacy: .public)")
        return nil
    }

    private func cacheImageData(_ data: Data, fileName: String) -> Bool {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetShared.appGroupId
        ) else {
            logger.error("[ImageLoad] cacheImageData: containerURL is nil")
            return false
        }
        let imageDirectoryURL = containerURL.appendingPathComponent(
            WidgetShared.imageDirectory,
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: imageDirectoryURL,
                withIntermediateDirectories: true
            )
            let targetURL = imageDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
            try data.write(to: targetURL, options: .atomic)
            logger.info("[ImageLoad] cacheImageData: wrote \(data.count) bytes to \(targetURL.path, privacy: .public)")
            return true
        } catch {
            logger.error("[ImageLoad] cacheImageData failed for \(fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func fetchImageData(for article: ArticleSnapshot) async -> Data? {
        guard let imageURL = normalizedImageURL(article.imageURL) else { return nil }

        var request = URLRequest(url: imageURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("image/avif,image/webp,image/jpeg,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
        request.setValue(article.url.absoluteString, forHTTPHeaderField: "Referer")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                logger.error("Image HTTP status \(http.statusCode) for \(imageURL.absoluteString, privacy: .public)")
                return nil
            }
            return downsampledJPEGData(from: data)
        } catch {
            logger.error("Image fetch failed for \(imageURL.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func normalizedImageURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        guard url.scheme?.lowercased() == "http" else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url
    }

    private func downsampledJPEGData(from data: Data) -> Data? {
        #if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1400,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return data
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return data
        }

        let destinationOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.82
        ]
        CGImageDestinationAddImage(destination, image, destinationOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return data }
        return mutableData as Data
        #else
        return data
        #endif
    }
}

struct DernierArticleIntentProvider: AppIntentTimelineProvider {
    typealias Intent = SelectFeedIntent

    func recommendations() -> [AppIntentRecommendation<SelectFeedIntent>] {
        [
            AppIntentRecommendation(
                intent: SelectFeedIntent(feed: nil),
                description: "Dernier article Flux"
            )
        ]
    }

    func placeholder(in context: Context) -> DernierArticleEntry {
        DernierArticleProvider().placeholder(in: context)
    }

    func snapshot(for configuration: SelectFeedIntent, in context: Context) async -> DernierArticleEntry {
        await DernierArticleProvider().loadEntry(for: configuration.feed?.id)
    }

    func timeline(for configuration: SelectFeedIntent, in context: Context) async -> Timeline<DernierArticleEntry> {
        let entry = await DernierArticleProvider().loadEntry(for: configuration.feed?.id)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        return Timeline(entries: [entry], policy: .after(next))
    }
}

struct FeedDigestEntry: TimelineEntry {
    let date: Date
    let digest: FeedDigestSnapshot?
}

struct FeedDigestIntentProvider: AppIntentTimelineProvider {
    typealias Intent = SelectFeedIntent

    func recommendations() -> [AppIntentRecommendation<SelectFeedIntent>] {
        [
            AppIntentRecommendation(
                intent: SelectFeedIntent(feed: nil),
                description: "Revue du flux"
            )
        ]
    }

    func placeholder(in context: Context) -> FeedDigestEntry {
        FeedDigestEntry(
            date: .now,
            digest: FeedDigestSnapshot(
                feedTitle: "Daily Edition",
                articles: [
                    ArticleSnapshot(
                        id: UUID(),
                        title: "Trump and Starmer discuss Strait of Hormuz",
                        url: URL(string: "https://example.com/1")!,
                        imageURL: nil,
                        imageFileName: nil,
                        feedTitle: "Daily Edition",
                        publishedAt: .now,
                        isSaved: false
                    ),
                    ArticleSnapshot(
                        id: UUID(),
                        title: "Long security lines form at airports as TSA agents miss first full paychecks",
                        url: URL(string: "https://example.com/2")!,
                        imageURL: nil,
                        imageFileName: nil,
                        feedTitle: "Daily Edition",
                        publishedAt: .now.addingTimeInterval(-3600),
                        isSaved: false
                    ),
                    ArticleSnapshot(
                        id: UUID(),
                        title: "One Battle After Another wins best picture at the Oscars",
                        url: URL(string: "https://example.com/3")!,
                        imageURL: nil,
                        imageFileName: nil,
                        feedTitle: "Daily Edition",
                        publishedAt: .now.addingTimeInterval(-7200),
                        isSaved: false
                    ),
                    ArticleSnapshot(
                        id: UUID(),
                        title: "Bill Cassidy faces another MAHA fight with his reelection on the line",
                        url: URL(string: "https://example.com/4")!,
                        imageURL: nil,
                        imageFileName: nil,
                        feedTitle: "Daily Edition",
                        publishedAt: .now.addingTimeInterval(-10800),
                        isSaved: false
                    )
                ]
            )
        )
    }

    func snapshot(for configuration: SelectFeedIntent, in context: Context) async -> FeedDigestEntry {
        loadEntry(for: configuration.feed?.id)
    }

    func timeline(for configuration: SelectFeedIntent, in context: Context) async -> Timeline<FeedDigestEntry> {
        let entry = loadEntry(for: configuration.feed?.id)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func loadEntry(for selectedFeedID: String?) -> FeedDigestEntry {
        let digestsByFeed = WidgetShared.loadFeedDigests()
        let digest: FeedDigestSnapshot? = {
            if let selectedFeedID, let selected = digestsByFeed[selectedFeedID] {
                return selected
            }

            return digestsByFeed.values.sorted {
                ($0.articles.first?.publishedAt ?? .distantPast) > ($1.articles.first?.publishedAt ?? .distantPast)
            }.first
        }()

        return FeedDigestEntry(date: .now, digest: digest)
    }
}

// MARK: - Notes Widget (browse recent notes)

struct NotesDigestEntry: TimelineEntry {
    let date: Date
    let notes: [ReaderNoteSnapshot]
}

struct NotesDigestProvider: AppIntentTimelineProvider {
    typealias Intent = SelectFeedIntent

    func placeholder(in context: Context) -> NotesDigestEntry {
        NotesDigestEntry(
            date: .now,
            notes: [
                ReaderNoteSnapshot(
                    id: UUID(),
                    articleTitle: "Un article passionnant",
                    articleURL: URL(string: "https://example.com/1")!,
                    articleImageURL: nil,
                    articleSource: "Example.com",
                    articlePublishedAt: .now.addingTimeInterval(-3600),
                    selectedText: "\"Un extrait marquant de l'article pour illustrer la note.\"",
                    createdAt: .now
                ),
                ReaderNoteSnapshot(
                    id: UUID(),
                    articleTitle: "Autre lecture utile",
                    articleURL: URL(string: "https://example.com/2")!,
                    articleImageURL: nil,
                    articleSource: "Example.org",
                    articlePublishedAt: .now.addingTimeInterval(-7200),
                    selectedText: "\"Deuxième extrait court pour donner envie de poursuivre.\"",
                    createdAt: .now.addingTimeInterval(-4000)
                )
            ]
        )
    }

    func snapshot(for configuration: SelectFeedIntent, in context: Context) async -> NotesDigestEntry {
        let notes = WidgetShared.loadNotes()
        return NotesDigestEntry(date: .now, notes: Array(notes.prefix(4)))
    }

    func timeline(for configuration: SelectFeedIntent, in context: Context) async -> Timeline<NotesDigestEntry> {
        let notes = WidgetShared.loadNotes()
        let entry = NotesDigestEntry(date: .now, notes: Array(notes.prefix(4)))
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        return Timeline(entries: [entry], policy: .after(next))
    }
}

struct NotesWidget: Widget {
    let kind: String = WidgetShared.notesWidgetKind
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectFeedIntent.self,
            provider: NotesDigestProvider()
        ) { entry in
            NotesDigestWidgetView(entry: entry, showsVersionBadge: false)
        }
        .configurationDisplayName("Notes Flux")
        .description("Affiche une note et navigation.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}


// MARK: - Widget view

private struct NotesDigestRow: View {
    let note: ReaderNoteSnapshot
    let showsDivider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    // Extrait
                    Text("\"\(note.selectedText)\"")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.black.opacity(0.86))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Titre + source/date
                    Text(note.articleTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        if let src = sourceLabel { Text(src) }
                        if let d = note.articlePublishedAt ?? note.createdAt as Date? {
                            Text("·")
                            Text(d, style: .relative)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                NotesDigestThumbnail(url: note.articleImageURL)
            }

            if showsDivider {
                Divider().overlay(Color.black.opacity(0.08))
            }
        }
    }

    private var sourceLabel: String? {
        if let src = note.articleSource, !src.isEmpty { return src }
        return note.articleURL.host?.replacingOccurrences(of: "www.", with: "")
    }
}

private struct NotesDigestThumbnail: View {
    let url: URL?
    var body: some View {
        Group {
            if let u = url {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let image):
                        ZStack {
                            Color.gray
                            image.renderingMode(.original).resizable().scaledToFill()
                        }
                        .compositingGroup()
                    default:
                        LinearGradient(colors: [Color.black.opacity(0.85), Color.gray.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .overlay { Image(systemName: "photo").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7)) }
                    }
                }
            } else {
                LinearGradient(colors: [Color.black.opacity(0.85), Color.gray.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay { Image(systemName: "photo").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7)) }
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct NotesDigestWidgetView: View {
    let entry: NotesDigestEntry
    let showsVersionBadge: Bool
    @Environment(\.widgetFamily) private var widgetFamily
    private let titleColor = Color(red: 0.52, green: 0.16, blue: 0.86)
    private let notesIndexKey = "notesWidget.selectedIndex"

    var body: some View {
        if entry.notes.isEmpty == false {
            let visibleNotes = Array(entry.notes.prefix(4))
            let selectedIndex = normalizedSelectedIndex(maxCount: visibleNotes.count)
            let note = visibleNotes[selectedIndex]

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Text("NOTES")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                    if showsVersionBadge {
                        Text("V3")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(titleColor.opacity(0.75))
                            .padding(.top, 4)
                    }
                    Spacer(minLength: 8)
                    FeedDigestAppIcon(titleColor: titleColor)
                }

                Text(note.selectedText)
                    .font(noteTextFont)
                    .foregroundStyle(Color.black.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                    .layoutPriority(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                HStack(spacing: 10) {
                    Button(intent: NotesWidgetNavigateIntent(delta: -1)) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.55))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .widgetURL(nil)

                    Text("\(selectedIndex + 1)/\(visibleNotes.count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .widgetURL(nil)

                    Button(intent: NotesWidgetNavigateIntent(delta: 1)) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.55))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .widgetURL(nil)

                    Button(intent: NotesWidgetCopyIntent()) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.55))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .widgetURL(nil)

                    Button(intent: NotesWidgetOpenInBrowserIntent(url: note.articleURL)) {
                        Image(systemName: "safari")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.55))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
                .widgetURL(nil)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(note.articleURL)
            .tint(titleColor)
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("NOTES")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(titleColor)
                Text("Aucune note. Ouvrez Flux et créez une note depuis le lecteur.")
                    .font(.headline)
                    .foregroundStyle(.black.opacity(0.82))
                    .lineLimit(4)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) { Color.white }
        }
    }

    private var noteTextFont: Font {
        let size: CGFloat = widgetFamily == .systemLarge ? 30 : 24
        return .custom("New York", size: size)
    }

    private func normalizedSelectedIndex(maxCount: Int) -> Int {
        guard maxCount > 0 else { return 0 }
        let defaults = UserDefaults(suiteName: WidgetShared.appGroupId)
        let raw = defaults?.integer(forKey: notesIndexKey) ?? 0
        let m = raw % maxCount
        return m < 0 ? (m + maxCount) : m
    }

}

// MARK: - Widget view

struct DernierArticleWidgetView: View {
    var entry: DernierArticleProvider.Entry
    private let viewLogger = Logger(subsystem: "FluxWidgetsExtension", category: "DernierArticleWidgetView")
    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.widgetContentMargins) private var widgetContentMargins

    var body: some View {
        if let article = entry.article {
            VStack(alignment: .leading, spacing: widgetFamily == .systemLarge ? 8 : 6) {
                Spacer()
                Text(article.feedTitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.92))
                Text(article.title)
                    .font(widgetFamily == .systemLarge ? .title3 : .headline)
                    .foregroundStyle(.white)
                    .lineLimit(widgetFamily == .systemLarge ? 6 : 3)
                if let date = article.publishedAt {
                    Text(date, style: .relative)
                        .font(widgetFamily == .systemLarge ? .caption : .caption2)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, widgetFamily == .systemLarge ? 22 : 18)
            .padding(.bottom, widgetFamily == .systemLarge ? 28 : 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    widgetBackground(data: entry.imageData, article: article)
                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.15),
                            .black.opacity(0.55)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .clipped()
            .widgetURL(widgetLink(for: article.url))
            .containerBackground(for: .widget) { Color.black }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Flux")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Aucune donnée.\nOuvre Flux et rafraîchis tes flux.")
                    .font(.headline)
                    .lineLimit(widgetFamily == .systemLarge ? 5 : 3)
            }
            .padding(widgetFamily == .systemLarge ? 16 : 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) { Color.black }
        }
    }

    private func widgetImage(from data: Data?) -> Image? {
        guard let data, !data.isEmpty else {
            viewLogger.error("[ImageLoad] widgetImage: data is nil or empty")
            return nil
        }
        viewLogger.info("[ImageLoad] widgetImage: data.count=\(data.count)")
        // Decode via ImageIO so we get explicit error logging, then bridge to
        // NSImage (a stable ObjC ref-counted object) before handing to SwiftUI.
        // Passing a raw CGImage directly to Image(decorative:scale:) causes a
        // double-release crash in swift_cvw_destroyImpl on macOS 26 Tahoe when
        // the @ViewBuilder conditional result type is torn down.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            viewLogger.error("[ImageLoad] CGImageSourceCreateWithData failed for \(data.count) bytes")
            return nil
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            viewLogger.error("[ImageLoad] CGImageSourceCreateImageAtIndex failed, count=\(CGImageSourceGetCount(source))")
            return nil
        }
        viewLogger.info("[ImageLoad] CGImage created: \(cgImage.width)x\(cgImage.height)")
        let platformImage = platformImageFromCGImage(cgImage)
        return Image(platformImage: platformImage).renderingMode(.original)
    }

    private func widgetLink(for articleURL: URL) -> URL {
        articleURL
    }

    @ViewBuilder
    private func widgetBackground(data: Data?, article: ArticleSnapshot) -> some View {
        if let image = widgetImage(from: data) {
            ZStack {
                Color.black
                image
                    .resizable()
                    .scaledToFill()
            }
            .compositingGroup()
            .widgetAccentable(false)
        } else if let cachedData = loadCachedImageDataForView(fileName: article.imageFileName ?? "\(article.id.uuidString).jpg"),
                  let image = widgetImage(from: cachedData) {
            ZStack {
                Color.black
                image
                    .resizable()
                    .scaledToFill()
            }
            .compositingGroup()
            .widgetAccentable(false)
        } else if let remoteURL = normalizedImageURL(article.imageURL) {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let image):
                    ZStack {
                        Color.black
                        image
                            .resizable()
                            .scaledToFill()
                    }
                    .compositingGroup()
                    .widgetAccentable(false)
                default:
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.9),
                            Color.black.opacity(0.65),
                            Color.gray.opacity(0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        } else {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.9),
                    Color.black.opacity(0.65),
                    Color.gray.opacity(0.45)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func loadCachedImageDataForView(fileName: String?) -> Data? {
        guard let fileName else { return nil }
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetShared.appGroupId
        ) else {
            return nil
        }

        let preferredURL = containerURL
            .appendingPathComponent(WidgetShared.imageDirectory, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        if let data = try? Data(contentsOf: preferredURL), !data.isEmpty {
            return data
        }

        let legacyURL = containerURL
            .appendingPathComponent(WidgetShared.legacyImageDirectory, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        if let data = try? Data(contentsOf: legacyURL), !data.isEmpty {
            return data
        }

        return nil
    }

    private func normalizedImageURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        guard url.scheme?.lowercased() == "http" else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url
    }
}

// MARK: - Widget

struct DernierArticleWidget: Widget {
    let kind: String = WidgetShared.widgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectFeedIntent.self,
            provider: DernierArticleIntentProvider()
        ) { entry in
            DernierArticleWidgetView(entry: entry)
        }
        .configurationDisplayName("Dernier article Flux")
        .description("Choisis la source du widget.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .promptsForUserConfiguration()
        .contentMarginsDisabled()
    }
}

private struct FeedDigestWidgetView: View {
    let entry: FeedDigestEntry
    private let titleColor = Color(red: 0.11, green: 0.38, blue: 0.95)

    var body: some View {
        if let digest = entry.digest, digest.articles.isEmpty == false {
            let visibleArticles = Array(digest.articles.prefix(4))

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                Text(digest.feedTitle.uppercased())
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    FeedDigestAppIcon(titleColor: titleColor)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(visibleArticles.enumerated()), id: \.element.id) { index, article in
                        Link(destination: article.url) {
                            FeedDigestArticleRow(
                                article: article,
                                showsDivider: index < visibleArticles.count - 1
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [
                        Color.white,
                        Color(red: 0.97, green: 0.98, blue: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("REVUE DU FLUX")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(titleColor)
                Text("Aucune donnée.\nOuvre Flux puis rafraîchis tes flux.")
                    .font(.headline)
                    .foregroundStyle(.black.opacity(0.82))
                    .lineLimit(4)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) {
                Color.white
            }
        }
    }
}

private struct FeedDigestAppIcon: View {
    let titleColor: Color

    var body: some View {
        Image("FluxIcon")
            .renderingMode(.original)
            .resizable()
            .scaledToFill()
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .compositingGroup()
            .widgetAccentable(false)
    }
}

private struct FeedDigestArticleRow: View {
    let article: ArticleSnapshot
    let showsDivider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(article.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(sourceLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.46))
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                FeedDigestThumbnail(article: article)
            }

            if showsDivider {
                Divider()
                    .overlay(Color.black.opacity(0.08))
            }
        }
    }

    private var sourceLabel: String {
        let host = article.url.host?.replacingOccurrences(of: "www.", with: "")
        return host ?? article.feedTitle
    }
}

private struct FeedDigestThumbnail: View {
    let article: ArticleSnapshot

    var body: some View {
        Group {
            if let localImage = cachedImage {
                ZStack {
                    Color.gray
                    localImage
                        .resizable()
                        .scaledToFill()
                }
                .compositingGroup()
            } else if let remoteURL = remoteImageURL {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case .success(let image):
                        ZStack {
                            Color.gray
                            image
                                .renderingMode(.original)
                                .resizable()
                                .scaledToFill()
                        }
                        .compositingGroup()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 74, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .widgetAccentable(false)
    }

    private var cachedImage: Image? {
        guard let fileURL = cachedImageURL else { return nil }
        guard let platformImage = platformImageFromFileURL(fileURL) else { return nil }
        return Image(platformImage: platformImage).renderingMode(.original)
    }

    private var cachedImageURL: URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetShared.appGroupId
        ) else {
            return nil
        }

        if let imageFileName = article.imageFileName {
            let preferredURL = containerURL
                .appendingPathComponent(WidgetShared.imageDirectory, isDirectory: true)
                .appendingPathComponent(imageFileName, isDirectory: false)
            if FileManager.default.fileExists(atPath: preferredURL.path) {
                return preferredURL
            }

            let legacyURL = containerURL
                .appendingPathComponent(WidgetShared.legacyImageDirectory, isDirectory: true)
                .appendingPathComponent(imageFileName, isDirectory: false)
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                return legacyURL
            }
        }

        return nil
    }

    private var remoteImageURL: URL? {
        guard let url = article.imageURL else { return nil }
        guard url.scheme?.lowercased() == "http" else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.85),
                Color.gray.opacity(0.55)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "photo")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

struct FeedDigestWidget: Widget {
    let kind: String = WidgetShared.feedDigestWidgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectFeedIntent.self,
            provider: FeedDigestIntentProvider()
        ) { entry in
            FeedDigestWidgetView(entry: entry)
        }
        .configurationDisplayName("Revue du flux")
        .description("Affiche les 4 derniers articles du flux choisi.")
        .supportedFamilies([.systemLarge])
        .promptsForUserConfiguration()
        .contentMarginsDisabled()
    }
}

// MARK: - Wall Widget

struct WallArticlesEntry: TimelineEntry {
    let date: Date
    let articles: [ArticleSnapshot]
    let selectedIndex: Int
    let isAutoplaying: Bool
}

struct WallArticlesProvider: TimelineProvider {
    func placeholder(in context: Context) -> WallArticlesEntry {
        WallArticlesEntry(
            date: .now,
            articles: [
                ArticleSnapshot(
                    id: UUID(),
                    title: "Le grand article du moment sur votre mur de Flux",
                    url: URL(string: "https://example.com/wall-1")!,
                    imageURL: nil,
                    imageFileName: nil,
                    feedTitle: "Flux Daily",
                    publishedAt: .now,
                    isSaved: false
                ),
                ArticleSnapshot(
                    id: UUID(),
                    title: "Deuxième sujet pour illustrer la navigation du widget",
                    url: URL(string: "https://example.com/wall-2")!,
                    imageURL: nil,
                    imageFileName: nil,
                    feedTitle: "Actualités",
                    publishedAt: .now.addingTimeInterval(-3600),
                    isSaved: false
                )
            ],
            selectedIndex: 0,
            isAutoplaying: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WallArticlesEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WallArticlesEntry>) -> Void) {
        let now = Date()
        let articles = WidgetShared.loadWallArticles()
        let defaults = WidgetShared.wallWidgetDefaults()
        let isAutoplaying = WidgetShared.wallWidgetAutoplayEnabled(defaults: defaults)

        if isAutoplaying, articles.count > 1 {
            let entries = (0..<24).map { step in
                let entryDate = now.addingTimeInterval(Double(step) * WidgetShared.wallWidgetAutoplayInterval)
                return loadEntry(at: entryDate, articles: articles, defaults: defaults)
            }
            let reloadDate = entries.last?.date.addingTimeInterval(WidgetShared.wallWidgetAutoplayInterval)
                ?? now.addingTimeInterval(WidgetShared.wallWidgetAutoplayInterval)
            completion(Timeline(entries: entries, policy: .after(reloadDate)))
            return
        }

        let entry = loadEntry(at: now, articles: articles, defaults: defaults)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry(
        at date: Date = .now,
        articles: [ArticleSnapshot]? = nil,
        defaults: UserDefaults? = WidgetShared.wallWidgetDefaults()
    ) -> WallArticlesEntry {
        let allArticles = articles ?? WidgetShared.loadWallArticles()
        let normalizedIndex = WidgetShared.currentWallWidgetIndex(
            total: allArticles.count,
            now: date,
            defaults: defaults
        )
        return WallArticlesEntry(
            date: date,
            articles: allArticles,
            selectedIndex: normalizedIndex,
            isAutoplaying: WidgetShared.wallWidgetAutoplayEnabled(defaults: defaults)
        )
    }
}

private struct WallArticleWidgetView: View {
    let entry: WallArticlesEntry
    @Environment(\.widgetFamily) private var widgetFamily

    private var autoplayButtonSize: CGFloat {
        widgetFamily == .systemLarge ? 40 : 36
    }

    private var articleTextTrailingInset: CGFloat {
        autoplayButtonSize + (widgetFamily == .systemLarge ? 18 : 14)
    }

    private var currentArticle: ArticleSnapshot? {
        guard entry.articles.isEmpty == false else { return nil }
        let index = min(max(entry.selectedIndex, 0), entry.articles.count - 1)
        return entry.articles[index]
    }

    var body: some View {
        if let article = currentArticle {
            GeometryReader { geometry in
                ZStack {
                    articleBackground(for: article)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()

                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.16),
                            .black.opacity(0.60)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)

                    VStack(alignment: .leading, spacing: widgetFamily == .systemLarge ? 12 : 10) {
                        HStack {
                            Spacer()
                            articleCounter
                        }

                        Spacer()

                        VStack(alignment: .leading, spacing: 6) {
                            Text(article.feedTitle.uppercased())
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(1)

                            Text(article.title)
                                .font(widgetFamily == .systemLarge ? .title3.weight(.semibold) : .headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(widgetFamily == .systemLarge ? 5 : 3)

                            if let publishedAt = article.publishedAt {
                                Text(publishedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.82))
                            }
                        }
                        .padding(.trailing, articleTextTrailingInset)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(widgetFamily == .systemLarge ? 22 : 18)

                    HStack {
                        widgetArrow(delta: -1, systemImage: "chevron.left")
                        Spacer()
                        widgetArrow(delta: 1, systemImage: "chevron.right")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, widgetFamily == .systemLarge ? 18 : 14)

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            autoplayButton
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(widgetFamily == .systemLarge ? 18 : 14)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(article.url)
            .containerBackground(for: .widget) { Color.black }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("MUR DE FLUX")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Aucun article disponible.\nOuvre Flux puis rafraîchis tes flux.")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(4)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [Color.black, Color.gray.opacity(0.65)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var articleCounter: some View {
        Text("\(entry.articles.isEmpty ? 0 : entry.selectedIndex + 1)/\(entry.articles.count)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.25), in: Capsule())
            .widgetURL(nil)
    }

    private func widgetArrow(delta: Int, systemImage: String) -> some View {
        Button(intent: WallWidgetNavigateIntent(delta: delta)) {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.28))
                    .frame(width: widgetFamily == .systemLarge ? 38 : 34, height: widgetFamily == .systemLarge ? 38 : 34)
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .widgetURL(nil)
    }

    private var autoplayButton: some View {
        Button(intent: WallWidgetAutoplayIntent()) {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.36))
                    .frame(width: autoplayButtonSize, height: autoplayButtonSize)

                Image(systemName: entry.isAutoplaying ? "pause.fill" : "play.fill")
                    .font(.system(size: widgetFamily == .systemLarge ? 15 : 14, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: entry.isAutoplaying ? 0 : 1)
            }
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .opacity(entry.articles.count > 1 ? 1 : 0.55)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(entry.articles.count < 2)
        .widgetURL(nil)
    }

    @ViewBuilder
    private func articleBackground(for article: ArticleSnapshot) -> some View {
        if let image = wallWidgetImage(from: wallWidgetImageData(for: article)) {
            ZStack {
                Color.black
                image
                    .resizable()
                    .scaledToFill()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .compositingGroup()
            .widgetAccentable(false)
        } else if let remoteURL = normalizedWallImageURL(article.imageURL) {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let image):
                    ZStack {
                        Color.black
                        image
                            .resizable()
                            .scaledToFill()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .compositingGroup()
                    .widgetAccentable(false)
                default:
                    wallPlaceholderBackground
                }
            }
        } else {
            wallPlaceholderBackground
        }
    }

    private var wallPlaceholderBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.10, blue: 0.16),
                Color(red: 0.12, green: 0.20, blue: 0.33),
                Color(red: 0.18, green: 0.28, blue: 0.47)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func wallWidgetImageData(for article: ArticleSnapshot) -> Data? {
        let fileName = article.imageFileName ?? "\(article.id.uuidString).jpg"
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetShared.appGroupId
        ) else {
            return nil
        }

        let preferredURL = containerURL
            .appendingPathComponent(WidgetShared.imageDirectory, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        if let data = try? Data(contentsOf: preferredURL), !data.isEmpty {
            return data
        }

        let legacyURL = containerURL
            .appendingPathComponent(WidgetShared.legacyImageDirectory, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        if let data = try? Data(contentsOf: legacyURL), !data.isEmpty {
            return data
        }

        return nil
    }

    private func wallWidgetImage(from data: Data?) -> Image? {
        guard let data, !data.isEmpty else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let platformImage = platformImageFromCGImage(cgImage)
        return Image(platformImage: platformImage).renderingMode(.original)
    }

    private func normalizedWallImageURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        guard url.scheme?.lowercased() == "http" else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url
    }
}

struct WallArticlesWidget: Widget {
    let kind: String = WidgetShared.wallWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: WallArticlesProvider()
        ) { entry in
            WallArticleWidgetView(entry: entry)
        }
        .configurationDisplayName("Mur Flux")
        .description("Affiche les articles récents du mur avec navigation.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Read Later Widget

struct ReadLaterEntry: TimelineEntry {
    let date: Date
    let articles: [ArticleSnapshot]
}

struct ReadLaterProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadLaterEntry {
        ReadLaterEntry(date: .now, articles: [
            ArticleSnapshot(id: UUID(), title: "Example article to read later", url: URL(string: "https://example.com")!, imageURL: nil, imageFileName: nil, feedTitle: "My Feed", publishedAt: .now, isSaved: true),
            ArticleSnapshot(id: UUID(), title: "Another saved article", url: URL(string: "https://example.com/2")!, imageURL: nil, imageFileName: nil, feedTitle: "Tech", publishedAt: .now.addingTimeInterval(-3600), isSaved: true),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (ReadLaterEntry) -> Void) {
        let articles = WidgetShared.loadSavedArticles()
        completion(ReadLaterEntry(date: .now, articles: articles))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadLaterEntry>) -> Void) {
        let articles = WidgetShared.loadSavedArticles()
        let entry = ReadLaterEntry(date: .now, articles: articles)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

private struct ReadLaterWidgetView: View {
    let entry: ReadLaterEntry
    private let titleColor = Color.orange

    private var widgetTitle: String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        switch lang {
        case "fr": return "À LIRE PLUS TARD"
        case "es": return "LEER MÁS TARDE"
        case "de": return "SPÄTER LESEN"
        case "it": return "DA LEGGERE"
        case "pt": return "LER DEPOIS"
        case "ja": return "あとで読む"
        case "zh": return "稍后阅读"
        case "ko": return "나중에 읽기"
        case "ru": return "ПРОЧИТАТЬ ПОЗЖЕ"
        default: return "READ LATER"
        }
    }

    private var emptyMessage: String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        switch lang {
        case "fr": return "Aucun article sauvegardé.\nAjoute des articles à ta liste de lecture."
        case "es": return "Sin artículos guardados.\nAñade artículos a tu lista de lectura."
        case "de": return "Keine gespeicherten Artikel.\nFüge Artikel zu deiner Leseliste hinzu."
        case "it": return "Nessun articolo salvato.\nAggiungi articoli alla lista di lettura."
        case "pt": return "Sem artigos salvos.\nAdicione artigos à sua lista de leitura."
        case "ja": return "保存された記事はありません。\n記事をリーディングリストに追加してください。"
        case "zh": return "没有保存的文章。\n将文章添加到阅读列表中。"
        case "ko": return "저장된 기사가 없습니다.\n기사를 읽기 목록에 추가하세요."
        case "ru": return "Нет сохранённых статей.\nДобавьте статьи в список чтения."
        default: return "No saved articles.\nAdd articles to your reading list."
        }
    }

    var body: some View {
        if entry.articles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(widgetTitle)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(titleColor)
                Text(emptyMessage)
                    .font(.headline)
                    .foregroundStyle(.black.opacity(0.82))
                    .lineLimit(4)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) {
                Color.white
            }
        } else {
            let visibleArticles = Array(entry.articles.prefix(4))

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Text(widgetTitle)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text("\(entry.articles.count)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(titleColor, in: Capsule())
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(visibleArticles.enumerated()), id: \.element.id) { index, article in
                        Button(intent: ReadLaterOpenInBrowserIntent(url: article.url)) {
                            ReadLaterArticleRow(
                                article: article,
                                showsDivider: index < visibleArticles.count - 1
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [
                        Color.white,
                        Color(red: 1.0, green: 0.97, blue: 0.93)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

private struct ReadLaterArticleRow: View {
    let article: ArticleSnapshot
    let showsDivider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(article.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(sourceLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.46))
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                FeedDigestThumbnail(article: article)
            }

            if showsDivider {
                Divider()
                    .overlay(Color.black.opacity(0.08))
            }
        }
    }

    private var sourceLabel: String {
        let host = article.url.host?.replacingOccurrences(of: "www.", with: "")
        return host ?? article.feedTitle
    }
}

struct ReadLaterWidget: Widget {
    let kind: String = WidgetShared.readLaterWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: ReadLaterProvider()
        ) { entry in
            ReadLaterWidgetView(entry: entry)
        }
        .configurationDisplayName("Read Later")
        .description("Your saved articles at a glance.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

struct FavoriteSignalEntry: TimelineEntry {
    let date: Date
    let signal: FavoriteSignalSnapshot?
}

struct FavoriteSignalProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FavoriteSignalEntry {
        FavoriteSignalEntry(
            date: .now,
            signal: FavoriteSignalSnapshot(
                id: "example",
                title: "Bitcoin au-dessus de 120k avant la fin de l'année ?",
                subtitle: "Marché prédictif Polymarket",
                category: "Crypto",
                volume: "$1.2M",
                commentCount: 128,
                endDate: .now.addingTimeInterval(86_400 * 90),
                url: URL(string: "https://polymarket.com")!,
                imageURL: URL(string: "https://polymarket-upload.s3.us-east-2.amazonaws.com/ethereum.png"),
                isBinary: true,
                outcomes: [
                    .init(label: "Oui", percentage: 62),
                    .init(label: "Non", percentage: 38)
                ]
            )
        )
    }

    func snapshot(for configuration: SelectFavoriteSignalIntent, in context: Context) async -> FavoriteSignalEntry {
        loadEntry(for: configuration)
    }

    func timeline(for configuration: SelectFavoriteSignalIntent, in context: Context) async -> Timeline<FavoriteSignalEntry> {
        let entry = loadEntry(for: configuration)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    func recommendations() -> [AppIntentRecommendation<SelectFavoriteSignalIntent>] {
        var recommendations: [AppIntentRecommendation<SelectFavoriteSignalIntent>] = [
            AppIntentRecommendation(
                intent: SelectFavoriteSignalIntent(signal: nil),
                description: "Signal favori"
            )
        ]

        recommendations += WidgetShared.loadFavoriteSignals()
            .prefix(6)
            .map { signal in
                AppIntentRecommendation(
                    intent: SelectFavoriteSignalIntent(
                        signal: FavoriteSignalEntity(id: signal.id, title: signal.title)
                    ),
                    description: signal.title
                )
            }

        return recommendations
    }

    private func loadEntry(for configuration: SelectFavoriteSignalIntent) -> FavoriteSignalEntry {
        let signals = WidgetShared.loadFavoriteSignals()
        let selectedId = configuration.signal?.id
        let signal = signals.first { $0.id == selectedId } ?? signals.first
        return FavoriteSignalEntry(date: .now, signal: signal)
    }
}

private struct FavoriteSignalWidgetView: View {
    let entry: FavoriteSignalEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let signal = entry.signal {
                Link(destination: signal.url) {
                    content(for: signal)
                }
                .buttonStyle(.plain)
            } else {
                emptyState
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.98, blue: 1.0),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private func content(for signal: FavoriteSignalSnapshot) -> some View {
        switch family {
        case .systemSmall:
            smallView(signal)
        case .systemMedium:
            mediumView(signal)
        default:
            largeView(signal)
        }
    }

    private func smallView(_ signal: FavoriteSignalSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(signal)
            Text(signal.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(4)
            Spacer(minLength: 0)
            compactOutcome(signal)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func mediumView(_ signal: FavoriteSignalSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                header(signal)
                Text(signal.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                if !signal.subtitle.isEmpty {
                    Text(signal.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
                footer(signal)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            outcomePanel(signal)
                .frame(width: 118)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func largeView(_ signal: FavoriteSignalSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(signal)
            Text(signal.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(3)

            if !signal.subtitle.isEmpty {
                Text(signal.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if signal.isBinary, signal.outcomes.count >= 2 {
                HStack(spacing: 12) {
                    spotlightOutcome(signal.outcomes[0], tint: Color.green)
                    spotlightOutcome(signal.outcomes[1], tint: Color.red)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(signal.outcomes.prefix(4)), id: \.self) { outcome in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(outcome.label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(outcome.percentage)%")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.primary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.black.opacity(0.08))
                                    Capsule()
                                        .fill(Color.blue)
                                        .frame(width: geo.size.width * CGFloat(outcome.percentage) / 100)
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
            footer(signal)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ signal: FavoriteSignalSnapshot) -> some View {
        HStack(alignment: .center, spacing: 10) {
            signalIcon(signal, size: family == .systemSmall ? 22 : 28)

            Text(signal.category.uppercased())
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(Color.blue)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("Flux")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func signalIcon(_ signal: FavoriteSignalSnapshot, size: CGFloat) -> some View {
        if let imageURL = signal.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    fallbackSignalIcon
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        } else {
            fallbackSignalIcon
                .frame(width: size, height: size)
        }
    }

    private var fallbackSignalIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.18),
                            Color.green.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.blue)
        }
    }

    private func compactOutcome(_ signal: FavoriteSignalSnapshot) -> some View {
        let first = signal.outcomes.first
        let second = signal.outcomes.dropFirst().first
        return VStack(alignment: .leading, spacing: 6) {
            if let first {
                Text("\(first.label) \(first.percentage)%")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            if let second {
                Text("\(second.label) \(second.percentage)%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func outcomePanel(_ signal: FavoriteSignalSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(signal.outcomes.prefix(3)), id: \.self) { outcome in
                VStack(alignment: .leading, spacing: 4) {
                    Text(outcome.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(outcome.percentage)%")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.04))
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func spotlightOutcome(_ outcome: FavoriteSignalSnapshot.Outcome, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(outcome.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(outcome.percentage)%")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }

    private func footer(_ signal: FavoriteSignalSnapshot) -> some View {
        HStack(spacing: 10) {
            Label(signal.volume, systemImage: "chart.bar.fill")
            Label("\(signal.commentCount)", systemImage: "bubble.left.fill")
            if let endDate = signal.endDate {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(endDate, style: .date)
                }
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SIGNAUX")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Color.blue)
            Text("Ajoute un signal en favoris dans Flux pour l'afficher ici.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(4)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct FavoriteSignalWidget: Widget {
    let kind: String = WidgetShared.favoriteSignalWidgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectFavoriteSignalIntent.self,
            provider: FavoriteSignalProvider()
        ) { entry in
            FavoriteSignalWidgetView(entry: entry)
        }
        .configurationDisplayName("Signal favori")
        .description("Affiche un signal Polymarket parmi tes favoris.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct FluxWidgetsExtensionBundle: WidgetBundle {
    var body: some Widget {
        DernierArticleWidget()
        FeedDigestWidget()
        WallArticlesWidget()
        NotesWidget()
        ReadLaterWidget()
        FavoriteSignalWidget()
    }
}
