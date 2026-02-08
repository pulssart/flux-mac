// ArticlesView.swift
import SwiftUI
import SwiftData
import SwiftSoup
import OSLog
import Combine

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
    @State private var webURL: URL? = nil
    @State private var webStartInReaderMode: Bool = true
    @State private var loadingPhrase: String? = nil
    @State private var phraseIndex: Int = 0
    @State private var loadingTicker = Timer.publish(every: 1.6, on: .main, in: .common).autoconnect()
    // Filtre temporel global (mur et vues par flux): Aujourd'hui, Hier, Tous
    enum TimeFilter: String, CaseIterable, Identifiable { case today, yesterday, all; var id: String { rawValue } }
    @State private var timeFilter: TimeFilter = .all
    
    // Détermine rapidement portrait/paysage (utile ailleurs mais pas suffisant pour iPad Split View)
    private var isPortrait: Bool {
        verticalSizeClass == .regular
    }
    
    // Padding latéral pour mode pleine largeur sous la sidebar
    // Si vous souhaitez garder un léger air, mettez 12; pour coller au bord, laissez 0.
    private var fullWidthSidePadding: CGFloat { 24 }
    
    init(feedId: UUID? = nil, folderId: UUID? = nil, showOnlyFavorites: Bool = false) {
        self.feedId = feedId
        self.folderId = folderId
        self.showOnlyFavorites = showOnlyFavorites
    }
    
    private var articlesSorted: [Article] {
        let base: [Article]
        if showOnlyFavorites {
            base = feedService.favoriteArticles
        } else if let folderId = folderId {
            let folderFeedIds: Set<UUID> = Set(feedService.feeds.filter { $0.folderId == folderId }.map { $0.id })
            base = feedService.articles.filter { folderFeedIds.contains($0.feedId) }
        } else if let feedId = feedId {
            base = feedService.articles.filter { $0.feedId == feedId }
        } else {
            base = feedService.articles
        }
        // Appliquer filtre temporel
        let filteredBase: [Article] = {
            let start = startDate(for: timeFilter)
            let end = endDate(for: timeFilter)
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
            return true
        }
        return articles.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
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
                    .id(feedId)
                    .toolbar { toolbarContent }
                    .overlay { emptyFavoritesOverlay }
            }
        }
    }

    private var baseScrollView: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    mainContentView()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: geometry.size.height)
                .padding(.horizontal, fullWidthSidePadding)
                .padding(.top, 16)
            }
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
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if webURL == nil {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarItems
            }
        }
    }

    @ViewBuilder
    private var toolbarItems: some View {
        let lm = LocalizationManager.shared
        let isWall = (feedId == nil && !showOnlyFavorites)
        let labels = computeToolbarLabels(isWall: isWall, lm: lm)

        TimeScopePicker(
            selection: $timeFilter,
            todayLabel: labels.0,
            yesterdayLabel: labels.1,
            allLabel: labels.2
        )

        if let fid = feedId, !showOnlyFavorites {
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
    private func mainContentView() -> some View {
        if !articlesSorted.isEmpty {
            Group {
                heroSectionView()
                gridSectionView()
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
            ArticleHeroCard(article: first) { url in
                if isYouTubeURL(url) {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        webStartInReaderMode = false
                        webURL = url
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        webStartInReaderMode = true
                        webURL = url
                    }
                }
            }
            .zIndex(0)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func gridSectionView() -> some View {
        let others = Array(articlesSorted.dropFirst(1))
        Group {
            if others.isEmpty {
                EmptyView()
            } else {
                GridSection(articles: others, isFeedWall: feedId == nil && !showOnlyFavorites) { url in
                    if isYouTubeURL(url) {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            webStartInReaderMode = false
                            webURL = url
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            webStartInReaderMode = true
                            webURL = url
                        }
                    }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func isYouTubeURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("youtube.com") || host.contains("youtu.be")
    }
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
}

private struct CardSizeModifier: ViewModifier {
    let hasDescription: Bool
    let isYouTube: Bool
    private let classicHeight: CGFloat = 320
    private let compactHeight: CGFloat = 220
    private let youtubeCompactHeight: CGFloat = 250
    func body(content: Content) -> some View {
        Group {
            if hasDescription {
                content.frame(height: classicHeight)
            } else {
                if isYouTube {
                    content.frame(height: youtubeCompactHeight)
                } else {
                    content.frame(height: compactHeight)
                }
            }
        }
    }
}

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
    let onOpenURL: (URL) -> Void
    @Environment(FeedService.self) private var feedService
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("windowBlurEnabled") private var windowBlurEnabled: Bool = false
    @AppStorage("hideTitleOnThumbnails") private var hideTitleOnThumbnails: Bool = false
    @State private var isHovering = false

    private var cardBaseColor: Color { colorScheme == .dark ? .black : .white }
    private var cardBackgroundStyle: AnyShapeStyle { windowBlurEnabled ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(cardBaseColor) }
    private var shouldShowOverlay: Bool { !hideTitleOnThumbnails || isHovering }
    
    var body: some View {
        Button(action: {
            onOpenURL(article.url)
        }) {
            ZStack(alignment: .bottomLeading) {
                HeroImage(url: isYouTube(article.url) ? nil : article.imageURL, pageURL: article.url, referer: article.url)
                    .frame(height: 500)
                    .clipped()

                if shouldShowOverlay {
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
                            Text(summary.decodedHTMLEntities)
                                .font(.title3)
                                .foregroundStyle(Color.white.opacity(0.7))
                                .lineSpacing(2)
                                .lineLimit(2)
                        }
                    }
                    .padding(24)
                }
            }
            .frame(height: 500)
            .animation(.easeInOut(duration: 0.2), value: shouldShowOverlay)
        }
        .buttonStyle(.plain)
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
                    .padding(16)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(isHovering ? 0.50 : 0.15), lineWidth: 1)
        )
        .compositingGroup()
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.14 : 0.09), radius: 8, x: 0, y: 3)
        .onHover { hover in
            isHovering = hover
        }
        .contextMenu {
            let lm = LocalizationManager.shared
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
    let onOpenURL: (URL) -> Void
    let onOversized: ((UUID) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(FeedService.self) private var feedService
    @AppStorage("windowBlurEnabled") private var windowBlurEnabled: Bool = false
    @AppStorage("hideTitleOnThumbnails") private var hideTitleOnThumbnails: Bool = false
    @State private var isHovering = false
    private let maxAspectRatio: CGFloat = 2.0
    private var cardBaseColor: Color { colorScheme == .dark ? .black : .white }
    private var cardBackgroundStyle: AnyShapeStyle { windowBlurEnabled ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(cardBaseColor) }
    private let gridImageHeight: CGFloat = 180
    private let gridAspectRatio: CGFloat = 1.0
    private let compactAspectRatio: CGFloat = 4.0/3.0
    
    private var descriptionText: String? {
        if let summary = article.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return summary
        }
        if let content = article.contentText?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
            return content
        }
        return nil
    }
    private var hasDescription: Bool { descriptionText != nil }
    private var isYouTubeArticle: Bool { isYouTube(article.url) }
    private var shouldShowOverlay: Bool { !hideTitleOnThumbnails || isHovering }
    
    var body: some View {
        Button(action: {
            onOpenURL(article.url)
        }) {
            Group {
                if hasDescription {
                    ZStack(alignment: .bottomLeading) {
                        // Image en pleine hauteur - contrainte à la géométrie de la carte
                        GeometryReader { geometry in
                            ProgressiveBlurImage(
                                url: isYouTube(article.url) ? nil : article.imageURL,
                                pageURL: article.url,
                                referer: article.url,
                                showOverlay: shouldShowOverlay,
                                onSizeKnown: { size in
                                    let w = max(size.width, 1)
                                    let h = max(size.height, 1)
                                    let ratio = w / h
                                    if ratio > self.maxAspectRatio || (h / w) < 0.45 { self.onOversized?(article.id) }
                                }
                            )
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                        }

                        if shouldShowOverlay {
                            // Texte par-dessus l'image
                            VStack(alignment: .leading, spacing: 8) {
                                Spacer()

                                Text(article.title.decodedHTMLEntities)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                                if let feed = feedService.feeds.first(where: { $0.id == article.feedId }) {
                                    Text(feed.title)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.75))
                                        .lineLimit(1)
                                }
                            }
                            .padding(12)
                        }
                    }
                    .frame(height: 320)
                    .animation(.easeInOut(duration: 0.2), value: shouldShowOverlay)
                } else {
                    if isYouTube(article.url) {
                        if isFeedWall {
                            ZStack(alignment: .bottomLeading) {
                                ArticleImage(url: nil, pageURL: article.url, referer: article.url)
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                                if isHovering {
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(0.0),
                                            Color.black.opacity(0.4),
                                            Color.black.opacity(0.7)
                                        ],
                                        startPoint: .center,
                                        endPoint: .bottom
                                    )
                                    .allowsHitTesting(false)
                                    Text(article.title)
                                        .font(.title2)
                                        .fontWeight(.regular)
                                        .lineLimit(3)
                                        .foregroundStyle(Color.white)
                                        .padding(12)
                                }
                            }
                            .frame(height: 220)
                        } else {
                            ZStack(alignment: .bottomLeading) {
                                ArticleImage(url: nil, pageURL: article.url, referer: article.url)
                                    .scaledToFill()
                                    .frame(height: 220)
                                    .clipped()
                                if isHovering {
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(0.0),
                                            Color.black.opacity(0.4),
                                            Color.black.opacity(0.7)
                                        ],
                                        startPoint: .center,
                                        endPoint: .bottom
                                    )
                                    .allowsHitTesting(false)
                                    Text(article.title)
                                        .font(.title2)
                                        .fontWeight(.regular)
                                        .lineLimit(3)
                                        .foregroundStyle(Color.white)
                                        .padding(12)
                                }
                            }
                        }
                    } else {
                        ZStack(alignment: .bottomLeading) {
                            ArticleImage(url: isYouTube(article.url) ? nil : article.imageURL, pageURL: article.url, referer: article.url, onSizeKnown: { size in
                                let w = max(size.width, 1)
                                let h = max(size.height, 1)
                                let ratio = w / h
                                if ratio > self.maxAspectRatio || (h / w) < 0.45 { self.onOversized?(article.id) }
                            })
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                            if shouldShowOverlay {
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.0),
                                        Color.black.opacity(0.4),
                                        Color.black.opacity(0.7)
                                    ],
                                    startPoint: .center,
                                    endPoint: .bottom
                                )
                                .allowsHitTesting(false)
                                Text(article.title.decodedHTMLEntities)
                                    .font(.title2)
                                    .fontWeight(.regular)
                                    .lineLimit(3)
                                    .foregroundStyle(Color.white)
                                    .padding(12)
                            }
                        }
                        .modifier(CardSizeModifier(hasDescription: hasDescription, isYouTube: isYouTubeArticle))
                        .padding(.vertical, 2)
                        .buttonStyle(.plain)
                        .background(cardBackgroundStyle)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.black.opacity(isHovering ? 0.50 : 0.15), lineWidth: 1)
                        )
                        .compositingGroup()
                        .animation(.easeInOut(duration: 0.2), value: shouldShowOverlay)
                        .onHover { hover in isHovering = hover }
                        .onDrag { NSItemProvider(object: article.url as NSURL) }
                    }
                }
            }
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
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(isHovering ? 0.50 : 0.15), lineWidth: 1)
        )
        .compositingGroup()
        .padding(.vertical, 6)
        .onHover { hover in
            isHovering = hover
        }
        .contextMenu {
            let lm = LocalizationManager.shared
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

private struct GridSection: View {
    let articles: [Article]
    let isFeedWall: Bool
    let onOpenURL: (URL) -> Void
    
    @State private var measuredWidth: CGFloat = 0
    @State private var oversizedIds: Set<UUID> = []
    private let minItemWidth: CGFloat = 320
    
    private func layout(for width: CGFloat) -> (rowSpacing: CGFloat, columnSpacing: CGFloat, columns: [GridItem], id: Int) {
        let columnSpacing: CGFloat = width < 700 ? 32 : 40
        let rowSpacing: CGFloat = width < 700 ? 12 : 16
        let rawCount = Int((width + columnSpacing) / (minItemWidth + columnSpacing))
        // Permettre jusqu'à 6 colonnes pour les très grandes fenêtres
        let columnCount = max(1, min(6, rawCount))
        let columns = Array(repeating: GridItem(.flexible(), spacing: columnSpacing, alignment: .top), count: columnCount)
        // Utiliser une combinaison de la largeur et du nombre de colonnes pour l'ID
        let widthBucket = Int((width / 10).rounded()) * 100 + columnCount
        return (rowSpacing, columnSpacing, columns, widthBucket)
    }
    
    var body: some View {
        let computed = layout(for: measuredWidth > 0 ? measuredWidth : 800) // Valeur par défaut pour macOS
        let visible = articles.filter { !oversizedIds.contains($0.id) }
        LazyVGrid(columns: computed.columns, alignment: .leading, spacing: computed.rowSpacing) {
            ForEach(visible, id: \.id) { article in
                ArticleGridCard(article: article, isFeedWall: isFeedWall, onOpenURL: { url in
                    onOpenURL(url)
                }, onOversized: { id in
                    oversizedIds.insert(id)
                })
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measuredWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        // Calculer les buckets avec la nouvelle logique
                        let oldLayout = layout(for: measuredWidth)
                        let newLayout = layout(for: newWidth)
                        if oldLayout.id != newLayout.id {
                            measuredWidth = newWidth
                        }
                    }
            }
        )
        .id(computed.id)
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
            return AnyView(YouTubeThumbnailView(videoPageURL: pageURL).clipped())
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

private struct ProgressiveBlurImage: View {
    let url: URL?
    let pageURL: URL?
    let referer: URL?
    let showOverlay: Bool
    let onSizeKnown: ((CGSize) -> Void)?

    @StateObject private var loader = SimpleImageLoader()

    private struct BlurLayer: Identifiable {
        let id: Int
        let radius: CGFloat
        let startOpacity: Double
        let endOpacity: Double
        let heightFraction: CGFloat
    }

    private let blurLayers: [BlurLayer] = [
        BlurLayer(id: 0, radius: 6, startOpacity: 0.08, endOpacity: 0.22, heightFraction: 0.46),
        BlurLayer(id: 1, radius: 10, startOpacity: 0.12, endOpacity: 0.32, heightFraction: 0.40),
        BlurLayer(id: 2, radius: 14, startOpacity: 0.16, endOpacity: 0.42, heightFraction: 0.34),
        BlurLayer(id: 3, radius: 18, startOpacity: 0.20, endOpacity: 0.52, heightFraction: 0.28)
    ]

    var body: some View {
        ZStack {
            baseContent
            if showOverlay, let image = loader.image {
                progressiveOverlay(for: image)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            loader.load(url: url, pageURL: pageURL, referer: referer)
        }
        .onChange(of: url) { _, _ in
            loader.resetAndLoad(url: url, pageURL: pageURL, referer: referer)
        }
        .onChange(of: pageURL) { _, _ in
            loader.resetAndLoad(url: url, pageURL: pageURL, referer: referer)
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

    @ViewBuilder
    private var baseContent: some View {
        if let image = loader.image {
            platformImageView(image)
                .resizable()
                .scaledToFill()
        } else if loader.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.1))
        } else {
            LinearGradient(
                colors: [Color.gray.opacity(0.12), Color.gray.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .skeletonPulse()
        }
    }

    private func progressiveOverlay(for image: PlatformImage) -> some View {
        GeometryReader { geo in
            ZStack {
                ForEach(blurLayers) { layer in
                    platformImageView(image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: layer.radius)
                        .mask(
                            VStack(spacing: 0) {
                                Spacer()
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        .black.opacity(layer.startOpacity),
                                        .black.opacity(layer.endOpacity)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: geo.size.height * layer.heightFraction)
                            }
                        )
                }

                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.18),
                            .black.opacity(0.32)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.4)
                }
            }
        }
    }

    private func platformImageView(_ image: PlatformImage) -> Image {
        #if os(macOS)
        return Image(nsImage: image)
        #elseif os(iOS)
        return Image(uiImage: image)
        #endif
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

private extension String {
    var decodedHTMLEntities: String {
        if let data = self.data(using: .utf8),
           let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
           ) {
            let s = attributed.string
            return s.isEmpty ? self : s
        }
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
