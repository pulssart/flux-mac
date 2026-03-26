// ArticlesView.swift
import SwiftUI
import SwiftData
import SwiftSoup
import OSLog
import Combine

#if canImport(FoundationModels)
import FoundationModels
#endif

#if os(macOS)
import WebKit
#elseif os(iOS)
import SafariServices
import UIKit
#endif

struct ArticlesView: View {
    @Environment(FeedService.self) private var feedService
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let feedId: UUID?
    let folderId: UUID?
    let showOnlyFavorites: Bool
    @Binding private var deepLinkRequest: ArticleOpenRequest?
    @State private var webURL: URL? = nil
    @State private var webStartInReaderMode: Bool = true
    @Environment(iPadSheetState.self) private var sheetState: iPadSheetState?
    @State private var loadingPhrase: String? = nil
    @State private var phraseIndex: Int = 0
    @State private var loadingTicker = Timer.publish(every: 1.6, on: .main, in: .common).autoconnect()
    @State private var isWindowLiveResizing = false
    // Cached sorted articles — updated only when data changes, not on geometry changes
    @State private var cachedArticlesSorted: [Article] = []
    @State private var cachedMusicFeedIds: Set<UUID> = []
    @AppStorage("reader.alwaysOpenInBrowser") private var alwaysOpenInBrowser: Bool = false
    // Filtre temporel global (mur et vues par flux): Aujourd'hui, Hier, Tous
    enum TimeFilter: String, CaseIterable, Identifiable { case today, yesterday, all; var id: String { rawValue } }
    @State private var timeFilter: TimeFilter = .all
    @AppStorage("filterAdsEnabled") private var filterAdsEnabled: Bool = false

    // Détermine rapidement portrait/paysage (utile ailleurs mais pas suffisant pour iPad Split View)
    private var isPortrait: Bool {
        verticalSizeClass == .regular
    }

    // iPhone: petit padding latéral pour une lecture plus confortable.
    private var fullWidthSidePadding: CGFloat {
        #if os(iOS)
        12
        #else
        24
        #endif
    }

    private var feedWallSidePadding: CGFloat {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 24
        }
        #endif
        return fullWidthSidePadding
    }

    private var isIPadDevice: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    private var heroHorizontalInset: CGFloat {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 0
        }
        return isFeedWall ? 0 : -feedWallSidePadding
        #else
        return 0
        #endif
    }

    private var topContentPadding: CGFloat {
        #if os(iOS)
        0
        #else
        16
        #endif
    }

    private var isFeedWall: Bool {
        feedId == nil && !showOnlyFavorites
    }

    private var isMusicFeed: Bool {
        guard let fid = feedId else { return false }
        return feedService.isMusicFeed(feedId: fid)
    }

    private var shouldUseUniformCardsLayout: Bool {
        guard showOnlyFavorites == false, folderId == nil, let fid = feedId else { return false }
        guard let feed = feedService.feeds.first(where: { $0.id == fid }) else { return false }

        if isTwitterURL(feed.siteURL) || isTwitterURL(feed.feedURL) {
            return true
        }

        return feedService.articles.contains { article in
            article.feedId == fid && isTwitterURL(article.url)
        }
    }

    private var scrollIdentity: String {
        "\(feedId?.uuidString ?? "all-feeds")::\(folderId?.uuidString ?? "no-folder")::\(showOnlyFavorites)"
    }

    private func regularGridRowSpacing(for availableWidth: CGFloat) -> CGFloat {
        availableWidth < 700 ? 12 : 16
    }

    private func sectionSpacing(for availableWidth: CGFloat, wallLayout: FeedWallGridLayout) -> CGFloat {
        return wallLayout.rowSpacing
    }

    private func feedWallLayout(for availableWidth: CGFloat) -> FeedWallGridLayout {
        let spacing: CGFloat = 24
        let minCardWidth: CGFloat = 280
        let maxColumnCount = 5
        let rawColumnCount = Int((availableWidth + spacing) / (minCardWidth + spacing))
        let columnCount = max(1, min(maxColumnCount, rawColumnCount))

        return FeedWallGridLayout(
            columnCount: columnCount,
            minCardWidth: minCardWidth,
            columnSpacing: spacing,
            rowSpacing: spacing
        )
    }
    
    init(
        feedId: UUID? = nil,
        folderId: UUID? = nil,
        showOnlyFavorites: Bool = false,
        deepLinkRequest: Binding<ArticleOpenRequest?> = .constant(nil)
    ) {
        self.feedId = feedId
        self.folderId = folderId
        self.showOnlyFavorites = showOnlyFavorites
        self._deepLinkRequest = deepLinkRequest
    }
    
    /// IDs des flux musique (Apple Music / Spotify) à exclure des vues agrégées
    private var musicFeedIds: Set<UUID> { cachedMusicFeedIds }

    private var articlesSorted: [Article] { cachedArticlesSorted }

    private var musicPlaylistTracks: [(url: URL, artworkURL: URL?)] {
        guard let feedId, feedService.isAppleMusicFeed(feedId: feedId) else { return [] }
        return orderedAppleMusicTracks(for: feedId, from: feedService.articles)
    }

    /// Recompute articles — called only when data/filter changes, NOT on geometry changes
    private func recomputeArticles() {
        let newMusicIds = Set(
            feedService.feeds
                .filter { feedService.isMusicFeedURL($0.feedURL) || feedService.isMusicFeedURL($0.siteURL ?? $0.feedURL) }
                .map(\.id)
        )
        cachedMusicFeedIds = newMusicIds

        let base: [Article]
        if showOnlyFavorites {
            base = feedService.favoriteArticles
        } else if let folderId = folderId {
            let folderFeedIds: Set<UUID> = Set(feedService.feeds.filter { $0.folderId == folderId }.map { $0.id })
            base = feedService.articles.filter { folderFeedIds.contains($0.feedId) }
        } else if let feedId = feedId {
            base = feedService.articles.filter { $0.feedId == feedId }
        } else {
            base = feedService.articles.filter { !newMusicIds.contains($0.feedId) }
        }
        let effectiveFilter = isMusicFeed ? .all : timeFilter
        let filteredBase: [Article] = {
            let start = startDate(for: effectiveFilter)
            let end = endDate(for: effectiveFilter)
            return base.filter { article in
                let date = article.publishedAt ?? .distantPast
                if let s = start, date < s { return false }
                if let e = end, date >= e { return false }
                return true
            }
        }()

        let articles = filteredBase.filter { article in
            let s = article.url.absoluteString.lowercased()
            if s.contains("youtube") && s.contains("/shorts/") { return false }
            if filterAdsEnabled && AdKeywordFilter.isAd(article) { return false }
            return true
        }
        // Déduplication par URL pour éviter les doublons visuels
        var seenURLs = Set<String>()
        let deduped = articles
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            .filter { seenURLs.insert($0.url.absoluteString).inserted }
        cachedArticlesSorted = deduped
    }

    // Calcule la date de début en fonction du filtre
    private func startDate(for filter: TimeFilter) -> Date? {
        let cal = Calendar.current
        let now = Date()
        switch filter {
        case .today:
            return cal.startOfDay(for: now)
        case .yesterday:
            let startToday = cal.startOfDay(for: now)
            return cal.date(byAdding: .day, value: -1, to: startToday)
        case .all:
            return nil
        }
    }

    private func endDate(for filter: TimeFilter) -> Date? {
        let cal = Calendar.current
        let now = Date()
        switch filter {
        case .today:
            // Fin: début du jour suivant
            let startToday = cal.startOfDay(for: now)
            return cal.date(byAdding: .day, value: 1, to: startToday)
        case .yesterday:
            // Fin: début d'aujourd'hui (exclu)
            return cal.startOfDay(for: now)
        case .all:
            return nil
        }
    }
    
    // New computed property exporting the reader control buttons
    public var readerControlButtons: some View {
        Group {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.28)) { webURL = nil }
            }) {
                Image(systemName: "arrow.left")
                    .font(.title2)
            }
            .help(LocalizationManager.shared.localizedString(.back))
            
            Button(action: {
                if let currentWebURL = webURL {
                    #if os(macOS)
                    NSWorkspace.shared.open(currentWebURL)
                    #elseif os(iOS)
                    UIApplication.shared.open(currentWebURL)
                    #endif
                }
            }) {
                Image(systemName: "safari")
                    .font(.title2)
            }
            .help(LocalizationManager.shared.localizedString(.openInBrowser))
            
            Button(action: {}) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.title2)
            }
            .help(LocalizationManager.shared.localizedString(.readerMode))
        }
    }
    
    private let lm = LocalizationManager.shared
    
    private var headerView: some View {
        HStack(spacing: 10) {
            if showOnlyFavorites {
                Text(lm.localizedString(.readLater))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            } else if let fid = feedId, let feed = feedService.feeds.first(where: { $0.id == fid }) {
                Text(feed.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lm.localizedString(.allArticles))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if let last = feedService.lastRefreshAt {
                        Text("\(LocalizationManager.shared.localizedString(.lastUpdate)): \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            headerControls
                .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    
    private var headerControls: some View {
        HStack(spacing: 8) {
            refreshControlStack
        }
    }
    
    // MARK: - Loading Phrases
    private static func randomLoadingPhrase() -> String {
        let phrases = [
            "🤖 L'IA réfléchit intensément...",
            "🧠 Analyse en cours, patience...",
            "📚 Lecture approfondie en cours...",
            "🔍 Extraction des points clés...",
            "💭 Synthèse en préparation...",
            "⚡ Traitement accéléré...",
            "🎯 Focus sur l'essentiel...",
            "📝 Rédaction du résumé..."
        ]
        return phrases.randomElement() ?? "🤖 Traitement en cours..."
    }

    @ViewBuilder
    private var refreshControlStack: some View {
        let isFeedRefreshing =
            feedService.isRefreshing &&
            (feedService.refreshingFeedId == feedId || (feedId == nil && feedService.refreshingFeedId == nil)) &&
            !showOnlyFavorites
        
        if isFeedRefreshing {
            HStack(spacing: 8) {
                Text(loadingPhrase ?? "Je compresse l'actualité…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id(phraseIndex)
                
                Button(action: {
                    loadingPhrase = Self.randomLoadingPhrase()
                    phraseIndex = 0
                    Task {
                        URLCache.shared.removeAllCachedResponses()
                        if showOnlyFavorites {
                            try await feedService.refreshArticles(for: nil)
                        } else {
                            try await feedService.refreshArticles(for: feedId)
                        }
                    }
                }) {
                    ProgressView().controlSize(.small)
                }
                .buttonStyle(.plain)
                .help(LocalizationManager.shared.localizedString(.loading))
            }
            .frame(maxWidth: 320, alignment: .trailing)
        } else {
            Button(action: {
                loadingPhrase = Self.randomLoadingPhrase()
                phraseIndex = 0
                Task {
                    URLCache.shared.removeAllCachedResponses()
                    if showOnlyFavorites {
                        try await feedService.refreshArticles(for: nil)
                    } else {
                        try await feedService.refreshArticles(for: feedId)
                    }
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.title2)
            }
            .disabled(showOnlyFavorites)
        }
    }
    
    var body: some View {
        Group {
            if let u = webURL {
                WebDrawer(url: u, startInReaderMode: webStartInReaderMode) {
                    withAnimation(.easeInOut(duration: 0.28)) { webURL = nil }
                }
            } else {
                baseScrollView
                    .id(scrollIdentity)
                    .toolbar { toolbarContent }
                    #if os(macOS)
                    .toolbarBackground(.hidden, for: .windowToolbar)
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                    #endif
                    .overlay { emptyFavoritesOverlay }
            }
        }
        .onAppear {
            recomputeArticles()
            consumeDeepLinkRequestIfNeeded()
        }
        .onChange(of: feedId) { _, _ in recomputeArticles() }
        .onChange(of: folderId) { _, _ in recomputeArticles() }
        .onChange(of: showOnlyFavorites) { _, _ in recomputeArticles() }
        .onChange(of: feedService.articles.count) { _, _ in recomputeArticles() }
        .onChange(of: feedService.feeds.count) { _, _ in recomputeArticles() }
        .onChange(of: timeFilter) { _, _ in recomputeArticles() }
        .onChange(of: feedService.favoriteArticles.count) { _, _ in recomputeArticles() }
        .onChange(of: deepLinkRequest?.id) { _, _ in
            consumeDeepLinkRequestIfNeeded()
        }
    }

    private var baseScrollView: some View {
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width - (feedWallSidePadding * 2), 0)
            let wallLayout = feedWallLayout(for: availableWidth)
            ScrollView {
                #if os(iOS)
                if isIPadDevice {
                    ipadScrollContent(availableWidth: availableWidth, wallLayout: wallLayout)
                } else {
                    standardScrollContent(availableWidth: availableWidth, wallLayout: wallLayout)
                }
                #else
                standardScrollContent(availableWidth: availableWidth, wallLayout: wallLayout)
                #endif
            }
            #if os(iOS)
            .contentMargins(.top, isIPadDevice ? 0 : nil, for: .scrollContent)
            .ignoresSafeArea(.container, edges: isIPadDevice ? .top : [])
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeWebViewOverlay)) { _ in
            withAnimation(.easeInOut(duration: 0.28)) { webURL = nil }
        }
        .onReceive(loadingTicker) { _ in
            handleLoadingTicker()
        }
        .onChange(of: feedService.isGeneratingSummary) { _, newVal in
            if newVal == false { loadingPhrase = nil }
        }
        .onChange(of: webURL) { _, newVal in
            handleWebURLChange(newVal)
        }
        .onChange(of: feedService.isRefreshing) { _, newVal in
            if newVal == false { loadingPhrase = nil }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willStartLiveResizeNotification)) { notification in
            guard shouldTrackLiveResize(notification) else { return }
            isWindowLiveResizing = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification)) { notification in
            guard shouldTrackLiveResize(notification) else { return }
            isWindowLiveResizing = false
        }
        #endif
    }

    @ViewBuilder
    private func standardScrollContent(availableWidth: CGFloat, wallLayout: FeedWallGridLayout) -> some View {
        VStack(spacing: 16) {
            mainContentView(availableWidth: availableWidth, wallLayout: wallLayout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, feedWallSidePadding)
        .padding(.top, topContentPadding)
    }

    #if os(iOS)
    @ViewBuilder
    private func ipadScrollContent(availableWidth: CGFloat, wallLayout: FeedWallGridLayout) -> some View {
        let gridSpacing = sectionSpacing(for: availableWidth, wallLayout: wallLayout)
        let heroHeight: CGFloat = 667
        VStack(spacing: gridSpacing) {
            // Stretchable header: GeometryReader inline, zero @State
            if !articlesSorted.isEmpty && shouldUseUniformCardsLayout == false {
                if let first = articlesSorted.first {
                    GeometryReader { geo in
                        let minY = geo.frame(in: .global).minY
                        let stretch = max(0, minY)
                        ArticleHeroCard(article: first, isLiveResizing: isWindowLiveResizing, isFullBleedHeader: true) { url in
                            openArticle(url)
                        }
                        .frame(width: geo.size.width, height: heroHeight + stretch)
                        .clipped()
                        .offset(y: -stretch)
                    }
                    .frame(height: heroHeight)
                    .id("hero-\(scrollIdentity)-\(first.id.uuidString)")
                }
            }

            VStack(spacing: 16) {
                mainContentView(availableWidth: availableWidth, wallLayout: wallLayout, skipHero: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, feedWallSidePadding)
        }
    }
    #endif

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if webURL == nil {
            #if os(iOS)
            if !isMusicFeed {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        timeScopePickerView
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                toolbarActionItems
            }
            #else
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarItems
            }
            #endif
        }
    }

    @ViewBuilder
    private var toolbarItems: some View {
        if !isMusicFeed {
            timeScopePickerView
        }

        toolbarActionItems
    }

    private var timeScopePickerView: some View {
        let lm = LocalizationManager.shared
        let isWall = (feedId == nil && !showOnlyFavorites)
        let labels = computeToolbarLabels(isWall: isWall, lm: lm)

        return TimeScopePicker(
            selection: $timeFilter,
            todayLabel: labels.0,
            yesterdayLabel: labels.1,
            allLabel: labels.2
        )
    }

    @ViewBuilder
    private var toolbarActionItems: some View {
        let lm = LocalizationManager.shared
        let isWall = (feedId == nil && !showOnlyFavorites)
        let isNewsWall = isWall && folderId == nil
        let hasUnreadArticles = feedService.articles.contains(where: { $0.isRead == false })
        let markAllAsSeenText = lm.localizedString(.markAllAsSeen)

        if isNewsWall {
            Button(action: {
                Task { await feedService.markAllFeedsVisited() }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                    Text(markAllAsSeenText)
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.glassProminent)
            .disabled(hasUnreadArticles == false)
            .help(lm.localizedString(.markAllAsSeenHelp))
        }

        if let fid = feedId, !showOnlyFavorites {
            // Bouton "Ouvrir dans Apple Music" pour les flux Apple Music
            if feedService.isAppleMusicFeed(feedId: fid),
               let feed = feedService.feeds.first(where: { $0.id == fid }),
               let feedURL = feed.siteURL ?? URL(string: feed.feedURL.absoluteString) {
                Button(action: {
                    #if os(macOS)
                    NSWorkspace.shared.open(feedURL)
                    #elseif os(iOS)
                    UIApplication.shared.open(feedURL)
                    #endif
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right")
                        Text("Apple Music")
                    }
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.glassProminent)
            }

            Button(action: {
                Task { try? await feedService.refreshArticles(for: fid) }
            }) {
                if feedService.isRefreshing && feedService.refreshingFeedId == fid {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(feedService.isRefreshing)
            .help(lm.localizedString(.loading))
        }
    }

    @ViewBuilder
    private var emptyFavoritesOverlay: some View {
        if showOnlyFavorites && articlesSorted.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "bookmark")
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.orange)
                    Text(LocalizationManager.shared.localizedString(.emptyReadLaterHint))
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
        }
    }

    private func handleLoadingTicker() {
        if feedService.isGeneratingSummary || (feedService.isRefreshing && !showOnlyFavorites) {
            withAnimation(.easeInOut(duration: 0.35)) {
                loadingPhrase = Self.randomLoadingPhrase()
                phraseIndex += 1
            }
        }
    }

    private func handleWebURLChange(_ newVal: URL?) {
        if newVal == nil {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .closeWebViewOverlay, object: nil)
            }
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .openWebViewOverlay, object: nil)
            }
        }
    }

    private func computeToolbarLabels(isWall: Bool, lm: LocalizationManager) -> (String, String, String) {
        if isWall {
            return (
                lm.localizedString(.today),
                lm.localizedString(.yesterday),
                lm.localizedString(.all)
            )
        }

        let base: [Article] = {
            if showOnlyFavorites { return feedService.favoriteArticles }
            if let fid = feedId { return feedService.articles.filter { $0.feedId == fid } }
            return feedService.articles
        }()

        func count(from start: Date?) -> Int {
            guard let start else { return base.count }
            return base.reduce(0) { $0 + ((($1.publishedAt ?? .distantPast) >= start) ? 1 : 0) }
        }

        let todayC = count(from: startDate(for: .today))
        return ("\(lm.localizedString(.today)) (\(todayC))", lm.localizedString(.yesterday), lm.localizedString(.all))
    }

    @ViewBuilder
    private func mainContentView(availableWidth: CGFloat, wallLayout: FeedWallGridLayout, skipHero: Bool = false) -> some View {
        if !articlesSorted.isEmpty {
            let contentSpacing = sectionSpacing(for: availableWidth, wallLayout: wallLayout)
            let content = VStack(alignment: .leading, spacing: contentSpacing) {
                if shouldUseUniformCardsLayout == false && !skipHero {
                    heroSectionView()
                }
                gridSectionView(
                    fixedLayout: wallLayout,
                    includeFirstArticle: shouldUseUniformCardsLayout
                )
            }
            Group {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .transaction { transaction in
                if isWindowLiveResizing {
                    transaction.animation = nil
                }
            }
        } else if feedService.isRefreshing && !showOnlyFavorites {
            loadingView()
        } else {
            emptyView()
        }
    }

    @ViewBuilder
    private func heroSectionView() -> some View {
        if let first = articlesSorted.first {
            ArticleHeroCard(article: first, isLiveResizing: isWindowLiveResizing, isFullBleedHeader: isIPadDevice) { url in
                openArticle(url)
            }
            .id("hero-\(scrollIdentity)-\(first.id.uuidString)")
            .padding(.horizontal, heroHorizontalInset)
            .zIndex(0)
        }
    }

    @ViewBuilder
    private func gridSectionView(
        fixedLayout: FeedWallGridLayout,
        includeFirstArticle: Bool = false
    ) -> some View {
        let gridArticles = includeFirstArticle ? articlesSorted : Array(articlesSorted.dropFirst(1))
        Group {
            if gridArticles.isEmpty {
                EmptyView()
            } else {
                GridSection(articles: gridArticles, isFeedWall: isFeedWall, isLiveResizing: isWindowLiveResizing, layout: fixedLayout) { url in
                    openArticle(url)
                }
            }
        }
        .overlay(alignment: .bottom) {
            AudioGlassPill()
                .environment(feedService)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .zIndex(10)
        }
    }

    @ViewBuilder
    private func loadingView() -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(LocalizationManager.shared.localizedString(.loading))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    @ViewBuilder
    private func emptyView() -> some View {
        if showOnlyFavorites {
            EmptyView()
        } else {
            VStack(spacing: 16) {
                Image(systemName: "newspaper")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary.opacity(0.6))
                Text(LocalizationManager.shared.localizedString(.noArticles))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(action: {
                    Task {
                        try? await feedService.refreshArticles(for: feedId)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                        Text(LocalizationManager.shared.localizedString(.reload))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .glassEffect()
                    )
                }
                .buttonStyle(.plain)
                .disabled(feedService.isRefreshing)
            }
            .frame(maxWidth: .infinity, minHeight: 360)
        }
    }

    private func isYouTubeURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("youtube.com") || host.contains("youtu.be")
    }

    private func isAppleMusicURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "music.apple.com" || host == "itunes.apple.com"
    }

    private func isSpotifyURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "open.spotify.com" || host == "play.spotify.com"
    }

    private func openExternally(_ url: URL) {
        #if os(macOS)
        if
            isAppleMusicURL(url),
            let musicAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music")
        {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: musicAppURL, configuration: configuration) { _, _ in }
            return
        }
        if
            isSpotifyURL(url),
            let spotifyAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client")
        {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: spotifyAppURL, configuration: configuration) { _, _ in }
            return
        }
        NSWorkspace.shared.open(url)
        #elseif os(iOS)
        UIApplication.shared.open(url)
        #endif
    }

    private func openArticle(_ url: URL, forceReaderFirst: Bool = true) {
        if isAppleMusicURL(url) {
            Task { await MusicKitService.shared.play(from: url) }
            return
        }
        if isSpotifyURL(url) {
            openExternally(url)
            return
        }
        #if os(iOS)
        if isIPadDevice && isYouTubeURL(url) {
            sheetState?.youtubeURL = url
            return
        }
        #endif

        if isYouTubeURL(url) || alwaysOpenInBrowser {
            openExternally(url)
            return
        }

        #if os(iOS)
        if isIPadDevice {
            // iPad: open summary sheet instead of WebDrawer
            if let article = articlesSorted.first(where: { $0.url == url }) {
                sheetState?.article = article
            } else {
                // Fallback: open in Safari if article not found
                openExternally(url)
            }
            return
        }
        #endif

        NotificationCenter.default.post(name: .collapseSidebar, object: nil)

        withAnimation(.easeInOut(duration: 0.28)) {
            webStartInReaderMode = forceReaderFirst
            webURL = url
        }
    }

    private func consumeDeepLinkRequestIfNeeded() {
        guard let request = deepLinkRequest else { return }
        deepLinkRequest = nil
        openArticle(request.url, forceReaderFirst: request.forceReaderFirst)
    }

    #if os(macOS)
    private func shouldTrackLiveResize(_ notification: Notification) -> Bool {
        guard let window = notification.object as? NSWindow else { return false }
        return window == NSApp.keyWindow || window == NSApp.mainWindow || window.isKeyWindow || window.isMainWindow
    }
    #endif
}

#if os(macOS) || os(iOS)
struct AudioGlassPill: View {
    @Environment(FeedService.self) private var feedService
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var glassNamespace
    var body: some View {
        Group {
            if feedService.isAudioOverlayVisible {
                if #available(macOS 26.0, *) {
                    HStack(spacing: 4) {
                        if let icon = feedService.audioOverlayIcon {
                            AsyncImage(url: icon) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Color.gray.opacity(0)
                            }
                            .frame(width: 38, height: 38)
                        } else {
                            Image(systemName: "globe").font(.callout).foregroundStyle(.secondary)
                                .frame(width: 38, height: 38)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feedService.audioOverlayTitle ?? "")
                                .font(.callout)
                                .lineLimit(1)
                            Text(timeString(feedService.audioCurrentTime) + " / " + timeString(feedService.audioDuration))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 4) {
                            Button(action: {
                                if feedService.isAudioLoading { return }
                                if feedService.isAudioPlaying { feedService.pauseAudio() } else { feedService.resumeAudio() }
                            }) {
                                Group {
                                    if feedService.isAudioLoading { ProgressView().controlSize(.small) }
                                    else { Image(systemName: feedService.isAudioPlaying ? "pause.fill" : "play.fill") }
                                }
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            Button(action: { if !feedService.isAudioLoading { feedService.stopAudio() } }) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(2)
                        .background(
                            Capsule(style: .continuous)
                                .glassEffect()
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 840)
                    .background(
                        Capsule(style: .continuous)
                            .glassEffect()
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    // Fallback on earlier versions
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.2), value: feedService.isAudioOverlayVisible)
    }
    private var controlFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
    }
    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
#endif

// Liquid glass natif non utilisé pour compatibilité Xcode/SDK; fallback via Material.

private struct TimeScopePicker: View {
    @Binding var selection: ArticlesView.TimeFilter
    let todayLabel: String
    let yesterdayLabel: String
    let allLabel: String
    var body: some View {
        Picker("", selection: $selection) {
            SegLabel(text: todayLabel).tag(ArticlesView.TimeFilter.today)
            SegLabel(text: yesterdayLabel).tag(ArticlesView.TimeFilter.yesterday)
            SegLabel(text: allLabel).tag(ArticlesView.TimeFilter.all)
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .frame(maxWidth: 520)
        .padding(.horizontal, 4)
    }
}

private struct SegLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
    }
}

private struct SkeletonHero: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("windowBlurEnabled") private var windowBlurEnabled: Bool = false
    private var cardBaseColor: Color { colorScheme == .dark ? .black : .white }
    private var cardBackgroundStyle: AnyShapeStyle { windowBlurEnabled ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(cardBaseColor) }
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.gray.opacity(0.15))
                .frame(height: 480)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.0),
                            Color.black.opacity(0.25),
                            Color.black.opacity(0.55)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                )
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 16, height: 16)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 80, height: 8)
                }
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 420, height: 18)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 520, height: 16)
            }
            .padding(24)
            .blendMode(.plusLighter)
        }
        .frame(height: 500)
        .background(cardBackgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.15), lineWidth: 1)
        )
        .compositingGroup()
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.14 : 0.09), radius: 8, x: 0, y: 3)
        .skeletonPulse()
    }
}

private struct SkeletonCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("windowBlurEnabled") private var windowBlurEnabled: Bool = false
    private var cardBaseColor: Color { colorScheme == .dark ? .black : .white }
    private var cardBackgroundStyle: AnyShapeStyle { windowBlurEnabled ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(cardBaseColor) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.gray.opacity(0.15))
                .frame(height: 180)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 16, height: 16)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.22))
                        .frame(width: 70, height: 8)
                }
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: 220, height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.20))
                    .frame(width: 260, height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.18))
                    .frame(width: 200, height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.16))
                    .frame(width: 240, height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.14))
                    .frame(width: 120, height: 8)
            }
            .padding(8)
            .background(cardBackgroundStyle)
        }
        .background(cardBackgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.15), lineWidth: 1)
        )
        .frame(height: 335)
        .compositingGroup()
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.14 : 0.09), radius: 8, x: 0, y: 3)
        .skeletonPulse()
    }
}

private struct Shimmer: ViewModifier {
    @State private var animate = false
    func body(content: Content) -> some View {
        content
            .opacity(animate ? 0.25 : 0.05)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    animate.toggle()
                }
            }
    }
}

private extension View {
    func shimmer() -> some View {
        self.modifier(Shimmer())
    }
    func skeletonPulse() -> some View {
        self.modifier(Shimmer())
    }
    @ViewBuilder
    func compositingGroupIfNeeded(_ enabled: Bool) -> some View {
        if enabled {
            self.compositingGroup()
        } else {
            self
        }
    }
    @ViewBuilder
    func shadowIfNeeded(_ enabled: Bool, color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        if enabled {
            self.shadow(color: color, radius: radius, x: x, y: y)
        } else {
            self
        }
    }
}


private let standardCardVerticalPadding: CGFloat = 6

private func faviconURL(for feed: Feed) -> URL? {
    if let explicit = feed.faviconURL { return explicit }
    if let site = feed.siteURL, let host = site.host, let scheme = site.scheme {
        return URL(string: "\(scheme)://\(host)/favicon.ico")
    }
    let hostFromFeed = feed.feedURL.host
    let schemeFromFeed = feed.feedURL.scheme
    if let hostFromFeed, let schemeFromFeed {
        return URL(string: "\(schemeFromFeed)://\(hostFromFeed)/favicon.ico")
    }
    return nil
}

private struct ArticleHeroCard: View {
    let article: Article
    let isLiveResizing: Bool
    var isFullBleedHeader: Bool = false
    let onOpenURL: (URL) -> Void
    @AppStorage("reader.alwaysOpenInBrowser") private var alwaysOpenInBrowser: Bool = false
    @Environment(FeedService.self) private var feedService
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("hideTitleOnThumbnails") private var hideTitleOnThumbnails: Bool = false
    @State private var isHovering = false

    private var shouldShowOverlay: Bool { !hideTitleOnThumbnails || isHovering }
    private var isAppleMusicArticle: Bool { isAppleMusic(article.url) }
    private var heroArtworkURL: URL? { isYouTube(article.url) ? nil : article.imageURL }
    private var heroBlurScale: CGFloat { isAppleMusicArticle ? 2.2 : 1.28 }
    private var heroBlurRadius: CGFloat { isAppleMusicArticle ? 140 : 85 }
    private var heroForegroundScale: CGFloat { isAppleMusicArticle ? 1.16 : 1.0 }

    @ViewBuilder
    private func heroArtworkFill(in geometry: GeometryProxy) -> some View {
        if isLiveResizing {
            // During resize: skip expensive blur, show simple fill
            HeroImage(url: heroArtworkURL, pageURL: article.url, referer: article.url)
                .scaleEffect(heroForegroundScale)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay(heroBackdropShade)
        } else {
            HeroImage(url: heroArtworkURL, pageURL: article.url, referer: article.url)
                .scaleEffect(heroBlurScale)
                .blur(radius: heroBlurRadius)
                .saturation(isAppleMusicArticle ? 1.18 : 1.0)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay(heroBackdropShade)
                .allowsHitTesting(false)

            HeroImage(url: heroArtworkURL, pageURL: article.url, referer: article.url)
                .scaleEffect(heroForegroundScale)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
    }

    private var heroBackdropShade: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(colorScheme == .dark ? 0.16 : 0.06),
                Color.black.opacity(colorScheme == .dark ? 0.30 : 0.12),
                Color.black.opacity(colorScheme == .dark ? 0.44 : 0.18)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var heroContentShade: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.0),
                Color.black.opacity(0.25),
                Color.black.opacity(0.55)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var heroTextContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let feed = feedService.feeds.first(where: { $0.id == article.feedId }), let icon = faviconURL(for: feed) {
                    AsyncImage(url: icon) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.white.opacity(0.15)
                    }
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                } else {
                    Image(systemName: "globe")
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.9))
                        .frame(width: 16, height: 16)
                }
                if let date = article.publishedAt {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                Spacer()
            }

            Text(article.title.decodedHTMLEntities)
                .font(.largeTitle)
                .fontWeight(.regular)
                .lineLimit(2)
                .foregroundStyle(Color.white)

            if let summary = article.summary {
                Text(cleanDisplaySummary(summary.decodedHTMLEntities))
                    .font(.title3)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineSpacing(2)
                    .lineLimit(2)
            }
        }
        .padding(24)
    }
    
    var body: some View {
        Button(action: {
            if !isAppleMusicArticle {
                onOpenURL(article.url)
            }
        }) {
            ZStack(alignment: .bottomLeading) {
                GeometryReader { geometry in
                    heroArtworkFill(in: geometry)
                }

                if shouldShowOverlay {
                    heroContentShade
                    heroTextContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: isFullBleedHeader ? .infinity : .none)
            .frame(height: isFullBleedHeader ? nil : 500)
            .animation(isLiveResizing ? nil : .easeInOut(duration: 0.2), value: shouldShowOverlay)
        }
        .buttonStyle(.plain)
        .onDrag {
            return NSItemProvider(object: article.url as NSURL)
        }
        #if os(macOS)
        .overlay(NonMovableWindowArea().allowsHitTesting(false))
        #endif
        .background(Color.black.opacity(colorScheme == .dark ? 0.34 : 0.12))
        .clipShape(RoundedRectangle(cornerRadius: isFullBleedHeader ? 0 : 14, style: .continuous))
        .overlay(alignment: .topLeading) {
            if isHovering {
                ReadLaterButton(article: article)
                    .padding(16)
            }
        }
        .overlay {
            if isAppleMusicArticle {
                AppleMusicPlayButton(article: article)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isAppleMusicArticle && MusicKitService.shared.isPlaying && MusicKitService.shared.currentArticleURL == article.url {
                MusicEqualizerBars()
                    .padding(16)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: isFullBleedHeader ? 0 : 14, style: .continuous)
                .stroke(Color.black.opacity(isHovering ? 0.50 : 0.15), lineWidth: isFullBleedHeader ? 0 : 1)
        )
        .compositingGroupIfNeeded(!isLiveResizing && !isFullBleedHeader)
        .shadowIfNeeded(!isLiveResizing && !isFullBleedHeader, color: .black.opacity(colorScheme == .dark ? 0.14 : 0.09), radius: 8, x: 0, y: 3)
        .onHover { hover in
            isHovering = hover
        }
        .onChange(of: isLiveResizing) { _, newValue in
            if newValue {
                isHovering = false
            }
        }
        .contextMenu {
            let lm = LocalizationManager.shared
            if !alwaysOpenInBrowser && !isAppleMusicArticle && !isYouTube(article.url) {
                Button(action: {
                    #if os(macOS)
                    NSWorkspace.shared.open(article.url)
                    #elseif os(iOS)
                    UIApplication.shared.open(article.url)
                    #endif
                }) {
                    Label(lm.localizedString(.openInBrowser), systemImage: "safari")
                }
                Divider()
            }
            Button(action: {
                #if os(macOS)
                if let service = NSSharingService(named: .composeEmail) {
                    service.subject = article.title
                    service.perform(withItems: [article.url])
                }
                #elseif os(iOS)
                let subject = article.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let body = article.url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let u = URL(string: "mailto:?subject=\(subject)&body=\(body)") { UIApplication.shared.open(u) }
                #endif
            }) {
                Label(lm.localizedString(.shareByEmail), systemImage: "envelope")
            }
            Button(action: {
                #if os(macOS)
                if let service = NSSharingService(named: .composeMessage) {
                    service.perform(withItems: [article.url])
                }
                #elseif os(iOS)
                let body = article.url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let u = URL(string: "sms:&body=\(body)") { UIApplication.shared.open(u) }
                #endif
            }) {
                Label(lm.localizedString(.shareByMessage), systemImage: "message")
            }
            Button(action: {
                let text = article.title + "\n" + article.url.absoluteString
                let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let u = URL(string: "https://x.com/intent/post?text=\(encoded)") {
                    #if os(macOS)
                    NSWorkspace.shared.open(u)
                    #elseif os(iOS)
                    Task { await UIApplication.shared.open(u) }
                    #endif
                }
            }) {
                Label(lm.localizedString(.writeXPost), systemImage: "xmark")
            }
            Divider()
            Button(action: {
                Task { await feedService.toggleFavorite(for: article) }
            }) {
                Label(article.isSaved ? LocalizationManager.shared.localizedString(.removeFromFavorites) : LocalizationManager.shared.localizedString(.addToFavorites), systemImage: "clock")
            }
            Button(action: {
                #if os(macOS)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(article.url.absoluteString, forType: .string)
                #elseif os(iOS)
                UIPasteboard.general.string = article.url.absoluteString
                #endif
            }) {
                Label(lm.localizedString(.copyURL), systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive, action: {
                Task {
                    await feedService.deleteArticle(article)
                }
            }) {
                Label(lm.localizedString(.delete), systemImage: "trash")
            }
        }
    }
}

private struct ArticleGridCard: View {
    let article: Article
    let isFeedWall: Bool
    let isLiveResizing: Bool
    let onOpenURL: (URL) -> Void
    let onOversized: ((UUID) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(FeedService.self) private var feedService
    @AppStorage("windowBlurEnabled") private var windowBlurEnabled: Bool = false
    @AppStorage("hideTitleOnThumbnails") private var hideTitleOnThumbnails: Bool = false
    @AppStorage("reader.alwaysOpenInBrowser") private var alwaysOpenInBrowser: Bool = false
    @State private var isHovering = false
    private let maxAspectRatio: CGFloat = 2.0
    private var cardBaseColor: Color { colorScheme == .dark ? .black : .white }
    private var cardBackgroundStyle: AnyShapeStyle { windowBlurEnabled && !isLiveResizing ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(cardBaseColor) }
    private let gridImageHeight: CGFloat = 180
    private let gridAspectRatio: CGFloat = 1.0
    private let compactAspectRatio: CGFloat = 4.0/3.0
    // Aspect ratio for editorial wall cards (portrait-ish) — replaces fixed 320px height
    private let editorialCardRatio: CGFloat = 1.0
    
    private var descriptionText: String? {
        if let summary = article.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return cleanDisplaySummary(summary)
        }
        if let content = article.contentText?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
            return cleanDisplaySummary(content)
        }
        return nil
    }
    private var hasDescription: Bool { descriptionText != nil || isAppleMusicArticle }
    private var isYouTubeArticle: Bool { isYouTube(article.url) }
    private var isAppleMusicArticle: Bool { isAppleMusic(article.url) }
    private var shouldShowOverlay: Bool { !hideTitleOnThumbnails || isHovering }
    private var gridArtworkScale: CGFloat { isAppleMusicArticle ? 1.38 : 1.0 }

    @ViewBuilder
    private func feedSourceLabel(_ feed: Feed) -> some View {
        HStack(spacing: 6) {
            if let icon = faviconURL(for: feed) {
                AsyncImage(url: icon) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.white.opacity(0.14)
                }
                .frame(width: 13, height: 13)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 13, height: 13)
            }

            Text(feed.title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
    }
    
    var body: some View {
        Button(action: {
            if !isAppleMusicArticle {
                onOpenURL(article.url)
            }
        }) {
            ZStack(alignment: .bottomLeading) {
                GeometryReader { geometry in
                    ArticleImage(
                        url: isYouTubeArticle ? nil : article.imageURL,
                        pageURL: article.url,
                        referer: article.url,
                        onSizeKnown: nil
                    )
                    .scaledToFill()
                    .scaleEffect(gridArtworkScale)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                }

                if shouldShowOverlay {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.0),
                            Color.black.opacity(0.18),
                            Color.black.opacity(0.42),
                            Color.black.opacity(0.58)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 8) {
                        Spacer()

                        Text(article.title.decodedHTMLEntities)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.white)

                        if let feed = feedService.feeds.first(where: { $0.id == article.feedId }) {
                            feedSourceLabel(feed)
                        }
                    }
                    .padding(12)
                }

                if isYouTubeArticle {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.58))
                        Circle()
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                        Image(systemName: "play.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(x: 2)
                    }
                    .frame(width: 58, height: 58)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1.0, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .onDrag {
            return NSItemProvider(object: article.url as NSURL)
        }
        #if os(macOS)
        .overlay(NonMovableWindowArea().allowsHitTesting(false))
        #endif
        .background(cardBackgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topLeading) {
            if isHovering {
                ReadLaterButton(article: article)
                    .padding(10)
            }
        }
        .overlay {
            if isAppleMusicArticle {
                AppleMusicPlayButton(article: article)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isAppleMusicArticle && MusicKitService.shared.isPlaying && MusicKitService.shared.currentArticleURL == article.url {
                MusicEqualizerBars()
                    .padding(16)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(isHovering ? 0.50 : 0.15), lineWidth: 1)
        )
        .compositingGroupIfNeeded(!isLiveResizing)
        .padding(.vertical, isFeedWall ? 0 : standardCardVerticalPadding)
        .onHover { hover in
            isHovering = hover
        }
        .onChange(of: isLiveResizing) { _, newValue in
            if newValue {
                isHovering = false
            }
        }
        .contextMenu {
            let lm = LocalizationManager.shared
            if !alwaysOpenInBrowser && !isAppleMusicArticle && !isYouTube(article.url) {
                Button(action: {
                    #if os(macOS)
                    NSWorkspace.shared.open(article.url)
                    #elseif os(iOS)
                    UIApplication.shared.open(article.url)
                    #endif
                }) {
                    Label(lm.localizedString(.openInBrowser), systemImage: "safari")
                }
                Divider()
            }
            Button(action: {
                #if os(macOS)
                if let service = NSSharingService(named: .composeEmail) {
                    service.subject = article.title
                    service.perform(withItems: [article.url])
                }
                #elseif os(iOS)
                let subject = article.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let body = article.url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let u = URL(string: "mailto:?subject=\(subject)&body=\(body)") { UIApplication.shared.open(u) }
                #endif
            }) {
                Label(lm.localizedString(.shareByEmail), systemImage: "envelope")
            }
            Button(action: {
                #if os(macOS)
                if let service = NSSharingService(named: .composeMessage) {
                    service.perform(withItems: [article.url])
                }
                #elseif os(iOS)
                let body = article.url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let u = URL(string: "sms:&body=\(body)") { UIApplication.shared.open(u) }
                #endif
            }) {
                Label(lm.localizedString(.shareByMessage), systemImage: "message")
            }
            Button(action: {
                let text = article.title + "\n" + article.url.absoluteString
                let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let u = URL(string: "https://x.com/intent/post?text=\(encoded)") {
                    #if os(macOS)
                    NSWorkspace.shared.open(u)
                    #elseif os(iOS)
                    Task { await UIApplication.shared.open(u) }
                    #endif
                }
            }) {
                Label(lm.localizedString(.writeXPost), systemImage: "xmark")
            }
            Divider()
            Button(action: {
                Task { await feedService.toggleFavorite(for: article) }
            }) {
                Label(article.isSaved ? LocalizationManager.shared.localizedString(.removeFromFavorites) : LocalizationManager.shared.localizedString(.addToFavorites), systemImage: "clock")
            }
            Button(action: {
                #if os(macOS)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(article.url.absoluteString, forType: .string)
                #elseif os(iOS)
                UIPasteboard.general.string = article.url.absoluteString
                #endif
            }) {
                Label(lm.localizedString(.copyURL), systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive, action: {
                Task {
                    await feedService.deleteArticle(article)
                }
            }) {
                Label(lm.localizedString(.delete), systemImage: "trash")
            }
        }
    }
}

private func cleanDisplaySummary(_ text: String) -> String {
    var result = text
    // Strip CDATA wrappers
    result = result.replacingOccurrences(of: #"<!\[CDATA\[|\]\]>"#, with: "", options: .regularExpression)
    // Strip HTML tags
    result = result.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    // Strip markdown bold/italic
    result = result.replacingOccurrences(of: "**", with: "")
    result = result.replacingOccurrences(of: "__", with: "")
    result = result.replacingOccurrences(of: #"(?<=\S)\*(?=\S)"#, with: "", options: .regularExpression)
    result = result.replacingOccurrences(of: #"\s*\*\s*"#, with: " ", options: .regularExpression)
    // Strip section headers like [Résumé], [Summary], ## Résumé, etc.
    result = result.replacingOccurrences(of: #"\[(?:Résumé|Summary|Resumen|Zusammenfassung|Riassunto|Resumo|概要|摘要|요약|Резюме)\]"#, with: "", options: [.regularExpression, .caseInsensitive])
    result = result.replacingOccurrences(of: #"\[(?:À retenir|Key takeaways?|Puntos clave|Wichtigste Punkte|Da ricordare|Pontos[‑-]chave|要点|핵심 요약|Ключевые тезисы)\]"#, with: "", options: [.regularExpression, .caseInsensitive])
    // Strip markdown headers (## Résumé, etc.) line by line
    let lines = result.components(separatedBy: .newlines)
    let filtered = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
    result = filtered.joined(separator: "\n")
    // Decode HTML entities
    result = result.replacingOccurrences(of: "&amp;", with: "&")
    result = result.replacingOccurrences(of: "&lt;", with: "<")
    result = result.replacingOccurrences(of: "&gt;", with: ">")
    result = result.replacingOccurrences(of: "&quot;", with: "\"")
    result = result.replacingOccurrences(of: "&#39;", with: "'")
    result = result.replacingOccurrences(of: "&apos;", with: "'")
    result = result.replacingOccurrences(of: "&nbsp;", with: " ")
    // Collapse whitespace
    result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
    result = result.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Strips HTML, CDATA, and common RSS artifacts from raw article content before sending to AI
private func cleanSourceText(_ text: String) -> String {
    var result = text
    // Strip CDATA wrappers
    result = result.replacingOccurrences(of: #"<!\[CDATA\[|\]\]>"#, with: "", options: .regularExpression)
    // Strip HTML tags
    result = result.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    // Decode HTML entities
    result = result.replacingOccurrences(of: "&amp;", with: "&")
    result = result.replacingOccurrences(of: "&lt;", with: "<")
    result = result.replacingOccurrences(of: "&gt;", with: ">")
    result = result.replacingOccurrences(of: "&quot;", with: "\"")
    result = result.replacingOccurrences(of: "&#39;", with: "'")
    result = result.replacingOccurrences(of: "&apos;", with: "'")
    result = result.replacingOccurrences(of: "&nbsp;", with: " ")
    result = result.replacingOccurrences(of: #"&#(\d+);"#, with: "", options: .regularExpression)
    // Collapse whitespace
    result = result.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
    result = result.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

private struct FeedWallGridLayout {
    let columnCount: Int
    let minCardWidth: CGFloat
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat

    var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: minCardWidth), spacing: columnSpacing, alignment: .top), count: columnCount)
    }

    var id: Int {
        columnCount
    }
}

private struct GridSection: View {
    let articles: [Article]
    let isFeedWall: Bool
    let isLiveResizing: Bool
    let layout: FeedWallGridLayout
    let onOpenURL: (URL) -> Void

    var body: some View {
        LazyVGrid(columns: layout.columns, alignment: .leading, spacing: layout.rowSpacing) {
            ForEach(articles, id: \.id) { article in
                ArticleGridCard(article: article, isFeedWall: isFeedWall, isLiveResizing: isLiveResizing, onOpenURL: { url in
                    onOpenURL(url)
                }, onOversized: nil)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#elseif os(iOS)
import UIKit
typealias PlatformImage = UIImage
#endif

class SimpleImageLoader: ObservableObject {
    @Published var image: PlatformImage?
    @Published var isLoading = false
    
    private static let cache = NSCache<NSString, PlatformImage>()
    private var cancellables = Set<AnyCancellable>()
    private var triedYouTubeFallback = false
    
    func cancelAll() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
    
    func resetAndLoad(url: URL?, pageURL: URL?, referer: URL?) {
        cancelAll()
        image = nil
        isLoading = false
        load(url: url, pageURL: pageURL, referer: referer)
    }
    
    func load(url: URL?, pageURL: URL?, referer: URL?) {
        var candidates: [URL] = []
        if let p = pageURL, let vid = extractYouTubeVideoId(from: p) {
            let jpgNames = ["maxresdefault.jpg", "sddefault.jpg", "hqdefault.jpg", "mqdefault.jpg", "0.jpg"]
            let webpNames = ["maxresdefault.webp", "sddefault.webp", "hqdefault.webp", "mqdefault.webp"]
            let yt1 = jpgNames.compactMap { URL(string: "https://i.ytimg.com/vi/\(vid)/\($0)") }
            let yt2 = jpgNames.compactMap { URL(string: "https://img.youtube.com/vi/\(vid)/\($0)") }
            let yt3 = webpNames.compactMap { URL(string: "https://i.ytimg.com/vi_webp/\(vid)/\($0)") }
            candidates.append(contentsOf: yt1 + yt2 + yt3)
        }
        if let direct = url { candidates.append(direct) }
        if candidates.isEmpty {
            if let pageURL { discoverAndLoad(pageURL: pageURL, referer: referer) }
            return
        }
        loadSequential(urls: candidates, referer: referer) { [weak self] in
            if let pageURL { self?.discoverAndLoad(pageURL: pageURL, referer: referer) }
        }
    }
    
    func loadYouTubeThumbnail(videoId: String, referer: URL?, onAllFailed: (() -> Void)? = nil) {
        triedYouTubeFallback = true
        let candidates = ["maxresdefault.jpg", "sddefault.jpg", "hqdefault.jpg", "mqdefault.jpg"].compactMap { suf -> URL? in
            URL(string: "https://i.ytimg.com/vi/\(videoId)/\(suf)")
        }
        loadSequential(urls: candidates, referer: referer, onAllFailed: onAllFailed)
    }
    
    private func loadSequential(urls: [URL], referer: URL?, onAllFailed: (() -> Void)? = nil) {
        guard let first = urls.first else {
            self.isLoading = false
            onAllFailed?()
            return
        }
        isLoading = true
        let cacheKey = first.absoluteString as NSString
        if let cached = Self.cache.object(forKey: cacheKey) {
            self.image = cached
            self.isLoading = false
            return
        }
        var req = URLRequest(url: first)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        req.setValue("image/avif,image/webp,image/jpeg,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
        let host = first.host?.lowercased() ?? ""
        if host.contains("ytimg.com") || host.contains("img.youtube.com") {
            req.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        } else if let referer {
            req.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        URLSession.shared.dataTaskPublisher(for: req)
            .tryMap { output -> PlatformImage in
                let data = output.data
                #if os(macOS)
                if let img = NSImage(data: data) { return img }
                #elseif os(iOS)
                if let img = UIImage(data: data) { return img }
                #endif
                throw URLError(.cannotDecodeContentData)
            }
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                switch completion {
                case .failure:
                    self?.loadSequential(urls: Array(urls.dropFirst()), referer: referer, onAllFailed: onAllFailed)
                case .finished:
                    self?.isLoading = false
                }
            }, receiveValue: { [weak self] img in
                Self.cache.setObject(img, forKey: cacheKey)
                self?.image = img
            })
            .store(in: &cancellables)
    }
    
    private func discoverAndLoad(pageURL: URL, referer: URL?) {
        var request = URLRequest(url: pageURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        if let referer = referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .compactMap { String(data: $0, encoding: .utf8) }
            .tryMap { html in
                let doc = try SwiftSoup.parse(html)
                
                if let ogImage = try doc.select("meta[property=og:image]").first() {
                    let content = try ogImage.attr("content")
                    if !content.isEmpty, let url = URL(string: content) {
                        return url.scheme != nil ? url : URL(string: content, relativeTo: pageURL)
                    }
                }
                
                if let twitterImage = try doc.select("meta[name=twitter:image]").first() {
                    let content = try twitterImage.attr("content")
                    if !content.isEmpty, let url = URL(string: content) {
                        return url.scheme != nil ? url : URL(string: content, relativeTo: pageURL)
                    }
                }
                
                return nil
            }
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] discoveredURL in
                    self?.load(url: discoveredURL, pageURL: nil, referer: referer)
                }
            )
            .store(in: &cancellables)
    }
}

struct ArticleImage: View {
    let url: URL?
    let pageURL: URL?
    let referer: URL?
    let onSizeKnown: ((CGSize) -> Void)?
    
    @StateObject private var loader = SimpleImageLoader()
    @Environment(\.colorScheme) private var colorScheme
    
    init(url: URL?, pageURL: URL?, referer: URL?, onSizeKnown: ((CGSize) -> Void)? = nil) {
        self.url = url
        self.pageURL = pageURL
        self.referer = referer
        self.onSizeKnown = onSizeKnown
    }
    
    var body: some View {
        contentView
            .onAppear {
                if !isYouTube(pageURL) {
                    loader.load(url: url, pageURL: pageURL, referer: referer)
                }
            }
            .onChange(of: url) { _, _ in
                if !isYouTube(pageURL) {
                    loader.resetAndLoad(url: url, pageURL: pageURL, referer: referer)
                }
            }
            .onChange(of: pageURL) { _, _ in
                if !isYouTube(pageURL) {
                    loader.resetAndLoad(url: url, pageURL: pageURL, referer: referer)
                }
            }
            .onReceive(loader.$image) { newImage in
                guard let newImage else { return }
                #if os(macOS)
                let size = newImage.size
                #elseif os(iOS)
                let size = newImage.size
                #endif
                onSizeKnown?(size)
            }
    }

    private var contentView: AnyView {
        if isYouTube(pageURL) {
            return AnyView(
                YouTubeThumbnailView(videoPageURL: pageURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            )
        } else if let image = loader.image {
            #if os(macOS)
            return AnyView(Image(nsImage: image).resizable().scaledToFill().clipped())
            #elseif os(iOS)
            return AnyView(Image(uiImage: image).resizable().scaledToFill().clipped())
            #endif
        } else if loader.isLoading {
            return AnyView(
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.1))
            )
        } else {
            return AnyView(
                LinearGradient(
                    colors: [Color.gray.opacity(0.12), Color.gray.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ).skeletonPulse()
            )
        }
    }
}

#if os(macOS)
import AppKit
/// Vue neutre qui désactive le drag de fenêtre sur sa zone
private class NonMovableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}
private struct NonMovableWindowArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NonMovableNSView(frame: .zero) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

private struct HeroImage: View {
    let url: URL?
    let pageURL: URL?
    let referer: URL?

    var body: some View {
        GeometryReader { geo in
            Group {
                if isYouTube(pageURL) {
                    YouTubeThumbnailView(videoPageURL: pageURL)
                        .scaledToFill()
                } else if let direct = url {
                    AsyncImage(url: direct) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        case .failure:
                            ArticleImage(url: nil, pageURL: pageURL, referer: referer)
                                .scaledToFill()
                        case .empty:
                            LinearGradient(
                                colors: [Color.gray.opacity(0.12), Color.gray.opacity(0.22)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ).skeletonPulse()
                        @unknown default:
                            LinearGradient(
                                colors: [Color.gray.opacity(0.12), Color.gray.opacity(0.22)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    }
                } else {
                    ArticleImage(url: nil, pageURL: pageURL, referer: referer)
                        .scaledToFill()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

private struct YouTubeThumbnailView: View {
    let videoPageURL: URL?
    @State private var attempt: Int = 0
    @Environment(\.colorScheme) private var colorScheme
    private var videoId: String? { videoPageURL.flatMap { extractYouTubeVideoId(from: $0) } }
    private var urls: [URL] {
        guard let vid = videoId else { return [] }
        let jpg = ["maxresdefault.jpg", "sddefault.jpg", "hqdefault.jpg", "mqdefault.jpg", "0.jpg"].flatMap { suf in
            [URL(string: "https://i.ytimg.com/vi/\(vid)/\(suf)"), URL(string: "https://img.youtube.com/vi/\(vid)/\(suf)")]
        }
        let webp = ["maxresdefault.webp", "sddefault.webp", "hqdefault.webp", "mqdefault.webp"].compactMap { suf in
            URL(string: "https://i.ytimg.com/vi_webp/\(vid)/\(suf)")
        }
        return jpg.compactMap { $0 } + webp
    }
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if attempt < urls.count {
                    AsyncImage(url: urls[attempt]) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        case .failure:
                            Color.clear.onAppear { attempt += 1 }
                        case .empty:
                            Color.clear
                        @unknown default:
                            Color.clear
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

private func isYouTube(_ url: URL?) -> Bool {
    guard let u = url, let host = u.host?.lowercased() else { return false }
    return host.contains("youtube.com") || host.contains("youtu.be")
}

private func isAppleMusic(_ url: URL?) -> Bool {
    guard let u = url, let host = u.host?.lowercased() else { return false }
    return host == "music.apple.com" || host == "itunes.apple.com"
}

private func isTwitterURL(_ url: URL?) -> Bool {
    guard let u = url, let rawHost = u.host?.lowercased() else { return false }
    let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
    return host == "x.com"
        || host.hasSuffix(".x.com")
        || host == "twitter.com"
        || host.hasSuffix(".twitter.com")
}

private struct ReadLaterButton: View {
    let article: Article
    @Environment(FeedService.self) private var feedService
    var body: some View {
        Button(action: {
            Task { await feedService.toggleFavorite(for: article) }
        }) {
            let iconSize: CGFloat = 16
            Image(systemName: article.isSaved ? "clock.fill" : "clock")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(article.isSaved ? Color.orange : Color.primary)
                .frame(width: iconSize, height: iconSize)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.20), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .help(article.isSaved ? LocalizationManager.shared.localizedString(.removeFromFavorites) : LocalizationManager.shared.localizedString(.addToFavorites))
    }
}

struct MusicEqualizerBars: View {
    var color: Color = .gray
    @State private var heights: [CGFloat] = [0.4, 0.7, 0.5]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3, height: 6 + heights[index] * 14)
            }
        }
        .frame(height: 20)
        .onAppear { animate() }
    }

    private func animate() {
        withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
            heights[0] = CGFloat.random(in: 0.2...1.0)
        }
        withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true).delay(0.1)) {
            heights[1] = CGFloat.random(in: 0.2...1.0)
        }
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(0.2)) {
            heights[2] = CGFloat.random(in: 0.2...1.0)
        }
    }
}

private struct AppleMusicPlayButton: View {
    let article: Article
    private var musicService: MusicKitService { MusicKitService.shared }
    @Environment(FeedService.self) private var feedService

    private var articleURL: URL { article.url }
    private var artworkURL: URL? { article.imageURL }
    private var containerURL: URL? {
        feedService.feeds.first(where: { $0.id == article.feedId })?.feedURL
    }
    private var playlistTracks: [(url: URL, artworkURL: URL?)] {
        guard feedService.isAppleMusicFeed(feedId: article.feedId) else { return [] }
        return orderedAppleMusicTracks(for: article.feedId, from: feedService.articles)
    }

    private var isCurrentTrack: Bool {
        musicService.currentArticleURL == articleURL
    }

    private var isPlayingThis: Bool {
        isCurrentTrack && musicService.isPlaying
    }

    private var isLoadingThis: Bool {
        isCurrentTrack && musicService.isLoading
    }

    var body: some View {
        Button(action: {
            Task { @MainActor in
                if playlistTracks.count > 1 {
                    await MusicKitService.shared.playFromCollection(
                        itemURL: articleURL,
                        artworkURL: artworkURL,
                        containerURL: containerURL,
                        tracks: playlistTracks
                    )
                } else {
                    await MusicKitService.shared.play(from: articleURL, artworkURL: artworkURL)
                }
            }
        }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 54, height: 54)
                Circle()
                    .stroke(Color.white.opacity(0.30), lineWidth: 1)
                    .frame(width: 54, height: 54)

                if isLoadingThis {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: isPlayingThis ? 0 : 2)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private func orderedAppleMusicTracks(for feedId: UUID, from articles: [Article]) -> [(url: URL, artworkURL: URL?)] {
    var seenURLs = Set<String>()
    return articles
        .filter { $0.feedId == feedId }
        .filter { article in
            seenURLs.insert(article.url.absoluteString).inserted
        }
        .map { article in
            (url: article.url, artworkURL: article.imageURL)
        }
}

private func extractYouTubeVideoId(from url: URL) -> String? {
    guard let host = url.host?.lowercased() else { return nil }
    if host.contains("youtube.com"), let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
       let vid = items.first(where: { $0.name.lowercased() == "v" })?.value, !vid.isEmpty { return vid }
    if host.contains("youtu.be") {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.isEmpty { return path }
    }
    let comps = url.path.split(separator: "/").map(String.init)
    if let i = comps.firstIndex(of: "embed"), comps.count > i+1 { return comps[i+1] }
    if let i = comps.firstIndex(of: "live"), comps.count > i+1 { return comps[i+1] }
    if let i = comps.firstIndex(of: "shorts"), comps.count > i+1 { return comps[i+1] }
    return nil
}

#Preview {
    ArticlesView()
}

// MARK: - YouTube PIP Player
#if os(macOS)
import AppKit
import WebKit

@MainActor
class YouTubePIPPlayer: ObservableObject {
    static let shared = YouTubePIPPlayer()

    @Published var isPlaying = false
    private var window: NSWindow?

    private init() {}

    /// Ouvre une vidéo YouTube dans une fenêtre WebView dédiée
    /// - Parameter url: L'URL de la vidéo YouTube (youtube.com/watch?v=... ou youtu.be/...)
    func openYouTubeVideo(url: URL) {
        guard let videoId = extractYouTubeVideoId(from: url) else {
            print("[YouTubePIP] Cannot extract video ID from URL: \(url)")
            return
        }

        print("[YouTubePIP] Opening video ID: \(videoId)")
        createPlayerWindow(videoId: videoId)
    }

    private func createPlayerWindow(videoId: String) {
        let contentRect = NSRect(x: 0, y: 0, width: 960, height: 540)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        guard let window = window else { return }

        window.title = "YouTube"
        window.isReleasedWhenClosed = false
        window.center()

        let playerView = YouTubePIPPlayerView(videoId: videoId) { [weak self] in
            self?.closePlayer()
        }

        window.contentView = NSHostingView(rootView: playerView)
        window.makeKeyAndOrderFront(nil)
        isPlaying = true
    }

    func closePlayer() {
        window?.close()
        window = nil
        isPlaying = false
    }

    private func extractYouTubeVideoId(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }

        // youtube.com/watch?v=VIDEO_ID
        if host.contains("youtube.com"),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           let videoId = queryItems.first(where: { $0.name.lowercased() == "v" })?.value,
           !videoId.isEmpty {
            return videoId
        }

        // youtu.be/VIDEO_ID
        if host.contains("youtu.be") {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty {
                return path
            }
        }

        // youtube.com/embed/VIDEO_ID ou youtube.com/live/VIDEO_ID
        let pathComponents = url.path.split(separator: "/").map(String.init)
        if let embedIndex = pathComponents.firstIndex(of: "embed"),
           pathComponents.count > embedIndex + 1 {
            return pathComponents[embedIndex + 1]
        }

        if let liveIndex = pathComponents.firstIndex(of: "live"),
           pathComponents.count > liveIndex + 1 {
            return pathComponents[liveIndex + 1]
        }

        return nil
    }
}

private struct YouTubePIPPlayerView: View {
    let videoId: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(LocalizationManager.shared.localizedString(.youtube))
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))

            YouTubeWebPlayer(videoId: videoId)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct YouTubeWebPlayer: NSViewRepresentable {
    let videoId: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // Utiliser l'URL watch normale
        let watchURL = "https://www.youtube.com/watch?v=\(videoId)"
        if let url = URL(string: watchURL) {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            webView.load(request)
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Script pour améliorer l'expérience de lecture
            let script = """
            (function() {
                var video = document.querySelector('video');
                if (video) {
                    console.log('[Flux] Video element found');
                    // Cliquer automatiquement sur le lecteur pour démarrer la vidéo
                    setTimeout(function() {
                        var playButton = document.querySelector('.ytp-large-play-button');
                        if (playButton) {
                            playButton.click();
                        }
                    }, 1000);
                }
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}
#endif

extension String {
    var decodedHTMLEntities: String {
        var text = self
        text = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        if let regex = try? NSRegularExpression(pattern: "&#(?:x([0-9a-fA-F]+)|([0-9]+));", options: []) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            var mutable = text
            for match in matches.reversed() {
                let hexRange = match.range(at: 1)
                let decRange = match.range(at: 2)
                let codePoint: UInt32?
                if hexRange.location != NSNotFound {
                    let hex = nsText.substring(with: hexRange)
                    codePoint = UInt32(hex, radix: 16)
                } else if decRange.location != NSNotFound {
                    let dec = nsText.substring(with: decRange)
                    codePoint = UInt32(dec, radix: 10)
                } else {
                    codePoint = nil
                }
                if let cp = codePoint, let scalar = UnicodeScalar(cp) {
                    if let fullRange = Range(match.range, in: mutable) {
                        mutable.replaceSubrange(fullRange, with: String(Character(scalar)))
                    }
                }
            }
            text = mutable
        }
        return text
    }
}

// MARK: - iPad Article Summary Sheet

#if os(iOS)
struct ArticleSummarySheet: View {
    let article: Article
    let feedService: FeedService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var summaryText: String = ""
    @State private var takeaways: [String] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var sourceFeed: Feed? {
        feedService.feeds.first(where: { $0.id == article.feedId })
    }

    private var langConfig: (targetName: String, takeawaysHeading: String, summaryLabel: String) {
        let lang = LocalizationManager.shared.currentLanguage
        switch lang {
        case .french: return ("français", "À retenir", "Résumé")
        case .english: return ("English", "Key takeaways", "Summary")
        case .spanish: return ("español", "Puntos clave", "Resumen")
        case .german: return ("Deutsch", "Wichtigste Punkte", "Zusammenfassung")
        case .italian: return ("italiano", "Da ricordare", "Riassunto")
        case .portuguese: return ("português", "Pontos‑chave", "Resumo")
        case .japanese: return ("日本語", "要点", "概要")
        case .chinese: return ("中文", "要点", "摘要")
        case .korean: return ("한국어", "핵심 요약", "요약")
        case .russian: return ("русский", "Ключевые тезисы", "Резюме")
        @unknown default: return ("English", "Key takeaways", "Summary")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero image
                    headerImage
                    // Content
                    VStack(alignment: .leading, spacing: 24) {
                        articleMeta
                        if isLoading {
                            loadingSection
                        } else if let error = errorMessage {
                            errorSection(error)
                        } else {
                            summarySection
                            if !takeaways.isEmpty {
                                takeawaysSection
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
            .background(Color(.systemGroupedBackground))
            .ignoresSafeArea(.container, edges: .top)
            .toolbarVisibility(.visible, for: .navigationBar)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 16) {
                        Button {
                            Task { await feedService.toggleFavorite(for: article) }
                        } label: {
                            Image(systemName: article.isSaved ? "bookmark.fill" : "bookmark")
                        }
                        Button {
                            UIApplication.shared.open(article.url)
                        } label: {
                            Image(systemName: "safari")
                        }
                        ShareLink(item: article.url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .task { await generateSummary() }
    }

    // MARK: - Subviews

    private var headerImage: some View {
        Group {
            if let imageURL = article.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: 420)
                            .clipped()
                    case .failure:
                        headerPlaceholder
                    case .empty:
                        headerPlaceholder
                            .overlay { ProgressView() }
                    @unknown default:
                        headerPlaceholder
                    }
                }
            } else {
                headerPlaceholder
            }
        }
    }

    private var headerPlaceholder: some View {
        LinearGradient(
            colors: [Color.gray.opacity(0.15), Color.gray.opacity(0.25)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(maxWidth: .infinity)
        .frame(height: 420)
    }

    private var articleMeta: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Source + date
            HStack(spacing: 8) {
                if let feed = sourceFeed, let icon = faviconURL(for: feed) {
                    AsyncImage(url: icon) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.gray.opacity(0.2)
                    }
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                if let feed = sourceFeed {
                    Text(feed.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                if let date = article.publishedAt {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(date, style: .relative)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            // Title
            Text(article.title.decodedHTMLEntities)
                .font(.title)
                .fontWeight(.bold)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            // Author
            if let author = article.author, !author.isEmpty {
                Text(author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loadingSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Skeleton résumé
            VStack(alignment: .leading, spacing: 12) {
                // Label skeleton
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 20, height: 20)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 80, height: 18)
                }
                // Text lines
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.gray.opacity(0.12))
                        .frame(height: 16)
                        .frame(maxWidth: i == 4 ? .infinity : .infinity, alignment: .leading)
                        .padding(.trailing, i == 4 ? 80 : (i == 2 ? 40 : 0))
                }
            }

            // Skeleton à retenir
            VStack(alignment: .leading, spacing: 12) {
                // Label skeleton
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 20, height: 20)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 100, height: 18)
                }
                // Bullet point lines
                ForEach(0..<3, id: \.self) { i in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 7, height: 7)
                            .offset(y: 5)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.gray.opacity(0.12))
                                .frame(height: 16)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.gray.opacity(0.12))
                                .frame(height: 16)
                                .padding(.trailing, i == 0 ? 60 : (i == 1 ? 100 : 30))
                        }
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .modifier(ShimmerModifier())
    }

    private func errorSection(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await generateSummary() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(langConfig.summaryLabel, systemImage: "text.alignleft")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text(summaryText)
                .font(.title3)
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var takeawaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(langConfig.takeawaysHeading, systemImage: "lightbulb")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(takeaways.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                            .offset(y: 2)
                        Text(point)
                            .font(.title3)
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - AI Summary Generation

    private func generateSummary() async {
        isLoading = true
        errorMessage = nil

        let rawSource = article.contentText ?? article.summary ?? ""
        let sourceText = cleanSourceText(rawSource)
        let title = article.title.decodedHTMLEntities

        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                errorMessage = "No content available to summarize."
                isLoading = false
            }
            return
        }

        let config = langConfig
        let delimiter = "\n===TAKEAWAYS===\n"
        let system = """
        You are an editor that produces EXACTLY two sections every time. \
        You MUST always output both a summary AND key takeaways separated by the delimiter ===TAKEAWAYS===. \
        Never skip the takeaways section. \
        Translate to \(config.targetName) if needed. Output strictly in \(config.targetName) (except proper nouns). \
        Output plain text only (no HTML, no CDATA, no XML, no Markdown, no bold, no headers, no brackets like [Résumé]). No links, no disclaimers.
        """
        let user = """
        Title: \(title)

        Text:
        \(sourceText.prefix(12000))

        You MUST output EXACTLY this format — both sections are MANDATORY:

        [2-3 paragraphs summarizing the article in plain text]

        ===TAKEAWAYS===

        - [takeaway 1]
        - [takeaway 2]
        - [takeaway 3]
        - [takeaway 4]
        - [takeaway 5]
        - [takeaway 6]

        RULES:
        1. The summary (before ===TAKEAWAYS===) is 2-3 short paragraphs. Plain text, no bullets.
        2. After ===TAKEAWAYS=== write EXACTLY 5 to 8 bullet points starting with "- ". One per line.
        3. BOTH sections are REQUIRED. Never omit the takeaways.
        4. The delimiter ===TAKEAWAYS=== must appear exactly once, on its own line.
        5. Respond strictly in \(config.targetName).
        """

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                do {
                    let session = LanguageModelSession(
                        model: model,
                        instructions: { system }
                    )
                    let response = try await session.respond(to: user)
                    let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    let parts = content.components(separatedBy: delimiter)
                    var summary = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    var takeawaysRaw = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""

                    // Fallback: if no delimiter found, try to split on first "- " bullet line
                    if takeawaysRaw.isEmpty {
                        let lines = summary.components(separatedBy: .newlines)
                        if let firstBulletIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("• ") }) {
                            summary = lines[..<firstBulletIdx].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                            takeawaysRaw = lines[firstBulletIdx...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }

                    let points = takeawaysRaw
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }
                        .map { $0.hasPrefix("• ") ? String($0.dropFirst(2)) : $0 }
                        .filter { !$0.isEmpty }

                    await MainActor.run {
                        summaryText = cleanDisplaySummary(summary)
                        takeaways = points.map { cleanDisplaySummary($0) }
                        isLoading = false
                    }
                    return
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        isLoading = false
                    }
                    return
                }
            default:
                break
            }
        }
        #endif

        // Fallback: show existing summary if AI unavailable
        await MainActor.run {
            if let existing = article.summary {
                summaryText = cleanDisplaySummary(existing.decodedHTMLEntities)
            } else {
                errorMessage = "Apple Intelligence is not available on this device."
            }
            isLoading = false
        }
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .opacity(0.4 + 0.6 * (0.5 + 0.5 * Foundation.sin(phase)))
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    phase = .pi
                }
            }
    }
}
#endif
