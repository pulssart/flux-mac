// DiscoveryView.swift
// Style Perplexity pour hero/featured, ancien design pour grille 3x

import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct DiscoveryView: View {
    @Environment(FeedService.self) private var feedService
    @AppStorage("reader.alwaysOpenInBrowser") private var alwaysOpenInBrowser: Bool = false
    @State private var webURL: URL? = nil
    @State private var webStartInReaderMode: Bool = true
    @State private var cachedLayout: DistributedLayout = DistributedLayout(hero: nil, groups: [])
    @State private var lastArticleCount: Int = -1
    private let lm = LocalizationManager.shared

    #if os(iOS)
    @Environment(iPadSheetState.self) private var sheetState: iPadSheetState?
    #endif

    private var isIPadDevice: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    private let maxContentWidth: CGFloat = 1100

    /// IDs des flux musique à exclure de la découverte
    private var musicFeedIds: Set<UUID> {
        Set(
            feedService.feeds
                .filter { feedService.isMusicFeedURL($0.feedURL) || feedService.isMusicFeedURL($0.siteURL ?? $0.feedURL) }
                .map(\.id)
        )
    }

    private func recomputeLayout() {
        let excludedIds = musicFeedIds
        let all = feedService.articles
            .filter { article in
                // Exclure les articles des flux musique
                if excludedIds.contains(article.feedId) { return false }
                let s = article.url.absoluteString.lowercased()
                if s.contains("youtube") && s.contains("/shorts/") { return false }
                return true
            }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }

        let withImg = all.filter { $0.imageURL != nil && !isYouTubeDiscovery($0.url) }
        let ytVideos = all.filter { isYouTubeDiscovery($0.url) && extractDiscoveryYouTubeVideoId(from: $0.url) != nil }

        let hero = withImg.first
        let remaining = Array(withImg.dropFirst(hero != nil ? 1 : 0))

        var groups: [DiscoveryGroup] = []
        var idx = 0
        var ytIdx = 0

        while idx < remaining.count {
            let gridEnd = min(idx + 3, remaining.count)
            let grid = Array(remaining[idx..<gridEnd])
            idx = gridEnd

            var featured: Article? = nil
            if idx < remaining.count {
                featured = remaining[idx]
                idx += 1
            }

            let yt: Article? = ytIdx < ytVideos.count ? ytVideos[ytIdx] : nil
            if yt != nil { ytIdx += 1 }

            groups.append(DiscoveryGroup(grid: grid, featured: featured, youtube: yt))
        }

        // Remaining YouTube videos that didn't fit into groups
        while ytIdx < ytVideos.count {
            groups.append(DiscoveryGroup(grid: [], featured: nil, youtube: ytVideos[ytIdx]))
            ytIdx += 1
        }

        cachedLayout = DistributedLayout(hero: hero, groups: groups)
        lastArticleCount = feedService.articles.count
    }

    var body: some View {
        ZStack {
            mainContent
                .opacity(webURL == nil ? 1 : 0)

            if let u = webURL {
                WebDrawer(url: u, startInReaderMode: webStartInReaderMode) {
                    withAnimation(.easeInOut(duration: 0.28)) { webURL = nil }
                }
            }
        }
        .onAppear { recomputeLayout() }
        .onChange(of: feedService.articles.count) { _, _ in recomputeLayout() }
        .onChange(of: feedService.discoveryRefreshTrigger) { _, _ in recomputeLayout() }
    }

    private var mainContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let layout = cachedLayout

                // HERO — Perplexity style
                if let hero = layout.hero {
                    PerplexityHeroCard(article: hero, feedService: feedService, onOpen: openArticle)
                        .padding(.bottom, 32)
                }

                // Groupes alternés
                ForEach(Array(layout.groups.enumerated()), id: \.element.id) { groupIndex, group in
                    if groupIndex == 0 {
                        sectionHeader(lm.localizedString(.discoveryTrending))
                            .padding(.bottom, 12)
                    } else if groupIndex == 1 {
                        sectionHeader(lm.localizedString(.discoveryForYou))
                            .padding(.bottom, 12)
                            .padding(.top, 8)
                    }

                    // Grille 3x — ancien design
                    if !group.grid.isEmpty {
                        DiscoveryTripleGrid(
                            articles: group.grid,
                            feedService: feedService,
                            onOpen: openArticle
                        )
                        .id(group.id)
                        .padding(.bottom, 28)
                    }

                    // Featured — Perplexity style
                    if let featured = group.featured {
                        PerplexityFeaturedBlock(
                            article: featured,
                            feedService: feedService,
                            imageOnLeft: groupIndex % 2 == 0,
                            onOpen: openArticle
                        )
                        .padding(.bottom, 32)
                    }

                    // YouTube video — pleine largeur
                    if let yt = group.youtube {
                        DiscoveryYouTubeCard(article: yt, feedService: feedService, onOpen: openArticle)
                            .padding(.bottom, 32)
                    }
                }

                Spacer(minLength: 60)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .frame(maxWidth: maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeWebViewOverlay)) { _ in
            withAnimation(.easeInOut(duration: 0.28)) { webURL = nil }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor)
                .frame(width: 3, height: 18)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
            Spacer(minLength: 0)
        }
    }

    private func openArticle(_ url: URL) {
        #if os(iOS)
        if isIPadDevice && isYouTubeDiscovery(url) {
            sheetState?.youtubeURL = url
            return
        }
        #endif

        if isYouTubeDiscovery(url) || alwaysOpenInBrowser {
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #elseif os(iOS)
            UIApplication.shared.open(url)
            #endif
            return
        }

        #if os(iOS)
        if isIPadDevice {
            let allArticles = cachedLayout.hero.map { [$0] + cachedLayout.groups.flatMap { g in
                (g.grid) + [g.featured].compactMap { $0 }
            } } ?? cachedLayout.groups.flatMap { g in
                (g.grid) + [g.featured].compactMap { $0 }
            }
            if let article = allArticles.first(where: { $0.url == url }) {
                sheetState?.article = article
                return
            }
        }
        #endif

        withAnimation(.easeInOut(duration: 0.28)) {
            webStartInReaderMode = true
            webURL = url
        }
    }
}

// MARK: - Data Model

private struct DiscoveryGroup: Identifiable {
    let id: String
    let grid: [Article]
    let featured: Article?
    let youtube: Article?

    init(grid: [Article], featured: Article?, youtube: Article?) {
        self.grid = grid
        self.featured = featured
        self.youtube = youtube
        // Stable identity based on actual article content
        let gridIds = grid.map { $0.id.uuidString }.joined(separator: ",")
        let featuredId = featured?.id.uuidString ?? ""
        let ytId = youtube?.id.uuidString ?? ""
        self.id = "\(gridIds)|\(featuredId)|\(ytId)"
    }
}

private struct DistributedLayout {
    let hero: Article?
    let groups: [DiscoveryGroup]
}

// MARK: - Hero Card (Perplexity style — image séparée, titre serif)

private struct PerplexityHeroCard: View {
    let article: Article
    let feedService: FeedService
    let onOpen: (URL) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var feed: Feed? {
        feedService.feeds.first(where: { $0.id == article.feedId })
    }

    var body: some View {
        Button(action: { onOpen(article.url) }) {
            VStack(alignment: .leading, spacing: 0) {
                // Image — standalone, pas de texte dessus
                ZStack {
                    ArticleImage(url: article.imageURL, pageURL: article.url, referer: article.url)
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                .frame(height: 400)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Texte sous l'image
                VStack(alignment: .leading, spacing: 10) {
                    Text(article.title.decodedHTMLEntities)
                        .font(.system(size: 28, design: .serif))
                        .fontWeight(.bold)
                        .lineLimit(3)
                        .foregroundStyle(Color.primary)
                        .lineSpacing(2)

                    if let summary = article.summary, !summary.isEmpty {
                        Text(summary.decodedHTMLEntities)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .lineSpacing(2)
                    }

                    HStack(spacing: 8) {
                        if let feed, let icon = discoveryFaviconURL(for: feed) {
                            AsyncImage(url: icon) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Color.clear
                            }
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        if let feed {
                            Text(feed.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let date = article.publishedAt {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(date, style: .relative)
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 4)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.003 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { isHovering = $0 }
        .contextMenu { articleContextMenu(article: article, feedService: feedService) }
    }

}

// MARK: - Triple Grid (ancien design — card avec bg/border/shadow)

private struct DiscoveryTripleGrid: View {
    let articles: [Article]
    let feedService: FeedService
    let onOpen: (URL) -> Void

    @State private var measuredWidth: CGFloat = 0

    private func layout(for width: CGFloat) -> (columns: [GridItem], id: Int) {
        let columnCount: Int
        if width > 600 { columnCount = 3 }
        else if width > 400 { columnCount = 2 }
        else { columnCount = 1 }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
        let bucketId = Int((width / 10).rounded()) * 100 + columnCount
        return (columns, bucketId)
    }

    private var articlesId: String {
        articles.map { $0.id.uuidString }.joined(separator: ",")
    }

    var body: some View {
        let computed = layout(for: measuredWidth > 0 ? measuredWidth : 800)
        LazyVGrid(columns: computed.columns, spacing: 16) {
            ForEach(articles, id: \.id) { article in
                DiscoveryGridCard(article: article, feedService: feedService, onOpen: onOpen)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measuredWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        let oldLayout = layout(for: measuredWidth)
                        let newLayout = layout(for: newWidth)
                        if oldLayout.id != newLayout.id {
                            measuredWidth = newWidth
                        }
                    }
            }
        )
        .id("\(computed.id)-\(articlesId)")
    }
}

// MARK: - Grid Card (ancien design)

private struct DiscoveryGridCard: View {
    let article: Article
    let feedService: FeedService
    let onOpen: (URL) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var feed: Feed? {
        feedService.feeds.first(where: { $0.id == article.feedId })
    }

    private let cardHeight: CGFloat = 240
    private let imageHeight: CGFloat = 140

    var body: some View {
        Button(action: { onOpen(article.url) }) {
            VStack(alignment: .leading, spacing: 0) {
                // Image
                ZStack {
                    ArticleImage(url: article.imageURL, pageURL: article.url, referer: article.url)
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                .frame(height: imageHeight)
                .frame(maxWidth: .infinity)
                .clipped()

                // Content
                VStack(alignment: .leading, spacing: 8) {
                    Text(article.title.decodedHTMLEntities)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .foregroundStyle(Color.primary)
                        .lineSpacing(1)

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        if let feed, let icon = discoveryFaviconURL(for: feed) {
                            AsyncImage(url: icon) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Color.clear
                            }
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                        if let feed {
                            Text(feed.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if let date = article.publishedAt {
                            Text(date, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: cardHeight)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .buttonStyle(.plain)
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(isHovering ? 0.15 : 0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.15 : 0.06), radius: 6, x: 0, y: 2)
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .contextMenu { articleContextMenu(article: article, feedService: feedService) }
    }

}

// MARK: - Featured Block (Perplexity style — image séparée, titre serif)

private struct PerplexityFeaturedBlock: View {
    let article: Article
    let feedService: FeedService
    let imageOnLeft: Bool
    let onOpen: (URL) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var feed: Feed? {
        feedService.feeds.first(where: { $0.id == article.feedId })
    }

    var body: some View {
        Button(action: { onOpen(article.url) }) {
            HStack(alignment: .top, spacing: 20) {
                if imageOnLeft {
                    imageSection
                    textSection
                } else {
                    textSection
                    imageSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.003 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { isHovering = $0 }
        .contextMenu { articleContextMenu(article: article, feedService: feedService) }
    }

    private var imageSection: some View {
        ZStack {
            ArticleImage(url: article.imageURL, pageURL: article.url, referer: article.url)
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .frame(width: 320, height: 220)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Source
            HStack(spacing: 6) {
                if let feed, let icon = discoveryFaviconURL(for: feed) {
                    AsyncImage(url: icon) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                if let feed {
                    Text(feed.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            // Titre serif
            Text(article.title.decodedHTMLEntities)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .lineLimit(3)
                .foregroundStyle(Color.primary)
                .lineSpacing(2)

            if let summary = article.summary, !summary.isEmpty {
                Text(summary.decodedHTMLEntities)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)

            if let date = article.publishedAt {
                Text(date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .layoutPriority(1)
    }

}

// MARK: - YouTube Card (pleine largeur, 16:9)

private struct DiscoveryYouTubeCard: View {
    let article: Article
    let feedService: FeedService
    let onOpen: (URL) -> Void
    @State private var isHovering = false
    @State private var thumbnailAttempt: Int = 0

    private var feed: Feed? {
        feedService.feeds.first(where: { $0.id == article.feedId })
    }

    private var videoId: String? {
        extractDiscoveryYouTubeVideoId(from: article.url)
    }

    private var thumbnailURLs: [URL] {
        guard let vid = videoId else { return [] }
        let jpg = ["maxresdefault.jpg", "sddefault.jpg", "hqdefault.jpg", "mqdefault.jpg"]
            .compactMap { URL(string: "https://i.ytimg.com/vi/\(vid)/\($0)") }
        return jpg
    }

    var body: some View {
        Button(action: { onOpen(article.url) }) {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail 16:9 avec play overlay
                ZStack {
                    if thumbnailAttempt < thumbnailURLs.count {
                        AsyncImage(url: thumbnailURLs[thumbnailAttempt]) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                            case .failure:
                                Color.clear.onAppear { thumbnailAttempt += 1 }
                            case .empty:
                                ytPlaceholder
                            @unknown default:
                                ytPlaceholder
                            }
                        }
                    } else {
                        ytPlaceholder
                    }

                    Circle()
                        .fill(.black.opacity(0.6))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white)
                                .offset(x: 2)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16/9, contentMode: .fit)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                infoBlock
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.003 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { isHovering = $0 }
        .contextMenu { articleContextMenu(article: article, feedService: feedService) }
    }

    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(article.title.decodedHTMLEntities)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(2)
                .foregroundStyle(Color.primary)
                .lineSpacing(1)

            HStack(spacing: 8) {
                if let feed, let icon = discoveryFaviconURL(for: feed) {
                    AsyncImage(url: icon) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                if let feed {
                    Text(feed.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let date = article.publishedAt {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(date, style: .relative)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 4)
    }

    private var ytPlaceholder: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.08))
            .overlay(
                Image(systemName: "play.rectangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            )
    }
}

// MARK: - Helpers

private func extractDiscoveryYouTubeVideoId(from url: URL) -> String? {
    guard let host = url.host?.lowercased() else { return nil }
    if host.contains("youtube.com"),
       let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
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

private func discoveryFaviconURL(for feed: Feed) -> URL? {
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

private func isYouTubeDiscovery(_ url: URL?) -> Bool {
    guard let u = url, let host = u.host?.lowercased() else { return false }
    return host.contains("youtube.com") || host.contains("youtu.be")
}

@ViewBuilder
private func articleContextMenu(article: Article, feedService: FeedService) -> some View {
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
        Label(
            article.isSaved ? lm.localizedString(.removeFromFavorites) : lm.localizedString(.addToFavorites),
            systemImage: "clock"
        )
    }
    Button(action: {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(article.url.absoluteString, forType: .string)
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
