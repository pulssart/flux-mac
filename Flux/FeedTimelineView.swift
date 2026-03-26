import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct FeedTimelineView: View {
    @Environment(FeedService.self) private var feedService
    @State private var webURL: URL? = nil
    @State private var lastTopArticleId: UUID? = nil
    @AppStorage("reader.alwaysOpenInBrowser") private var alwaysOpenInBrowser: Bool = false
    private let lm = LocalizationManager.shared

    @Environment(iPadSheetState.self) private var sheetState: iPadSheetState?

    private var isIPadDevice: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }
    private let maxFeedWidth: CGFloat = 880

    private var musicFeedIds: Set<UUID> {
        Set(
            feedService.feeds
                .filter { feedService.isMusicFeedURL($0.feedURL) || feedService.isMusicFeedURL($0.siteURL ?? $0.feedURL) }
                .map(\.id)
        )
    }

    private var articles: [Article] {
        let musicIds = musicFeedIds
        var seenURLs = Set<String>()
        return feedService.articles
            .filter { !isYouTube($0.url) && !musicIds.contains($0.feedId) }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            .filter { seenURLs.insert($0.url.absoluteString).inserted }
    }

    var body: some View {
        if let url = webURL {
            WebDrawer(url: url, startInReaderMode: true, forceAISummary: true) {
                withAnimation(.easeInOut(duration: 0.28)) { webURL = nil }
            }
        } else {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .center, spacing: 18) {
                        Color.clear
                            .frame(height: 0)
                            .id("feed-top")
                        // header removed
                        if articles.isEmpty {
                            Text(lm.localizedString(.noArticles))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: maxFeedWidth, alignment: .leading)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(articles, id: \.id) { article in
                                    let meta = feedMeta(for: article)
                                    FeedTimelineCard(
                                        article: article,
                                        feedTitle: meta.title,
                                        faviconURL: meta.favicon,
                                        excerpt: articlePreview(for: article),
                                        thumbnailURL: articleThumbnail(for: article),
                                        onOpenURL: openInAppWebView
                                    )
                                    .frame(maxWidth: maxFeedWidth, alignment: .leading)
                                }
                            }
                            .frame(maxWidth: maxFeedWidth, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .onAppear {
                    lastTopArticleId = articles.first?.id
                }
                .onChange(of: articles.first?.id) { newId in
                    guard let newId, newId != lastTopArticleId else { return }
                    lastTopArticleId = newId
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scrollProxy.scrollTo("feed-top", anchor: .top)
                    }
                }
            }
        }
    }

    private func feedSidePadding(for available: CGFloat) -> CGFloat {
        if available < 520 { return 8 }
        if available < 760 { return 12 }
        return 16
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(lm.localizedString(.newsletterFeed))
                .font(.title2)
                .fontWeight(.semibold)
            Spacer(minLength: 8)
            if let last = feedService.lastRefreshAt {
                Text("\(lm.localizedString(.lastUpdate)): \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func openInAppWebView(_ url: URL) {
        if isYouTube(url) {
            if let article = articles.first(where: { $0.url == url }) {
                feedService.markArticleAsRead(article)
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                sheetState?.youtubeURL = url
            }
            return
        }

        if alwaysOpenInBrowser {
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #elseif os(iOS)
            UIApplication.shared.open(url)
            #endif
            return
        }

        if let article = articles.first(where: { $0.url == url }) {
            feedService.markArticleAsRead(article)
            withAnimation(.easeInOut(duration: 0.3)) {
                sheetState?.article = article
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.28)) {
            webURL = url
        }
    }

    private func feedMeta(for article: Article) -> (title: String, favicon: URL?) {
        if let feed = feedService.feeds.first(where: { $0.id == article.feedId }) {
            return (feed.title, feedFaviconURL(for: feed))
        }
        let host = article.url.host?.replacingOccurrences(of: "www.", with: "")
        return (host ?? lm.localizedString(.source), nil)
    }

    private func articleThumbnail(for article: Article) -> URL? {
        guard let imageURL = article.imageURL else { return nil }
        return isYouTube(imageURL) ? nil : imageURL
    }

    private func articlePreview(for article: Article) -> String? {
        if let summary = article.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cleanPreviewText(summary)
        }
        if let text = article.contentText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cleanPreviewText(text)
        }
        return nil
    }

    private func cleanPreviewText(_ text: String, limit: Int = 220) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else { return cleaned }
        let idx = cleaned.index(cleaned.startIndex, offsetBy: limit)
        let prefix = cleaned[..<idx].trimmingCharacters(in: .whitespacesAndNewlines)
        return String(prefix) + "..."
    }

    private func feedFaviconURL(for feed: Feed) -> URL? {
        if let u = feed.faviconURL { return u }
        if let site = feed.siteURL, let host = site.host, let scheme = site.scheme {
            return URL(string: "\(scheme)://\(host)/favicon.ico")
        }
        if let host = feed.feedURL.host, let scheme = feed.feedURL.scheme {
            return URL(string: "\(scheme)://\(host)/favicon.ico")
        }
        if let host = feed.siteURL?.host ?? feed.feedURL.host {
            return URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")
        }
        return nil
    }

    private func isYouTube(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host.contains("youtube.com") || host.contains("youtu.be")
    }
}

struct FeedTimelineCard: View {
    let article: Article
    let feedTitle: String
    let faviconURL: URL?
    let excerpt: String?
    let thumbnailURL: URL?
    let onOpenURL: (URL) -> Void

    @Environment(FeedService.self) private var feedService
    @State private var isHovering = false
    @State private var measuredWidth: CGFloat = 0

    init(
        article: Article,
        feedTitle: String,
        faviconURL: URL?,
        excerpt: String?,
        thumbnailURL: URL?,
        onOpenURL: @escaping (URL) -> Void
    ) {
        self.article = article
        self.feedTitle = feedTitle
        self.faviconURL = faviconURL
        self.excerpt = excerpt
        self.thumbnailURL = thumbnailURL
        self.onOpenURL = onOpenURL
    }

    private var handleText: String {
        let base = feedTitle
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
        return base.isEmpty ? "@flux" : "@\(base)"
    }

    private var isCompact: Bool {
        measuredWidth > 0 ? measuredWidth < 560 : false
    }

    private var titleFont: Font {
        .system(size: isCompact ? 16 : 18, weight: .regular)
    }

    private var metaFont: Font {
        .system(size: isCompact ? 14 : 16, weight: .semibold)
    }

    private var handleFont: Font {
        .system(size: isCompact ? 13 : 15)
    }

    private var excerptFont: Font {
        .system(size: isCompact ? 14 : 16)
    }

    private var actionFont: Font {
        .system(size: isCompact ? 14 : 15)
    }

    private var imageHeight: CGFloat {
        let width = measuredWidth > 0 ? measuredWidth : 600
        let scaled = width * (isCompact ? 0.28 : 0.32) * 2
        return min(max(267, scaled), 427)
    }

    var body: some View {
        Button(action: { onOpenURL(article.url) }) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let faviconURL {
                        AsyncImage(url: faviconURL) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Color.gray.opacity(0.2)
                        }
                    } else {
                        Image(systemName: "globe")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
                .frame(width: 42, height: 42)
                .background(Color.black.opacity(0.04))
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(feedTitle)
                            .font(metaFont)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .allowsTightening(true)
                        Text(handleText)
                            .font(handleFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .allowsTightening(true)
                        if let date = article.publishedAt {
                            Text("· \(date.formatted(.relative(presentation: .numeric)))")
                                .font(handleFont)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(article.title)
                        .font(titleFont)
                        .foregroundStyle(.primary)
                        .lineSpacing(2)
                        .lineLimit(isCompact ? 4 : 5)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)

                    if let excerpt, !excerpt.isEmpty {
                        Text(excerpt)
                            .font(excerptFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(isCompact ? 3 : 4)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(1.5)
                    }

                    if let thumbnailURL {
                        GeometryReader { imgProxy in
                            AsyncImage(url: thumbnailURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                        .frame(width: imgProxy.size.width, height: imageHeight)
                                        .clipped()
                                case .failure:
                                    Color.gray.opacity(0.2)
                                case .empty:
                                    Color.gray.opacity(0.12)
                                @unknown default:
                                    Color.gray.opacity(0.12)
                                }
                            }
                        }
                        .frame(height: imageHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    HStack(spacing: 22) {
                        if #available(macOS 13.0, iOS 16.0, *) {
                            ShareLink(item: article.url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.plain)
                            .font(actionFont)
                            .foregroundStyle(.secondary)
                        } else {
                            Button(action: { copyURL(article.url) }) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.plain)
                            .font(actionFont)
                            .foregroundStyle(.secondary)
                        }

                        Button(action: { postOnX(article) }) {
                            Image(systemName: "arrow.2.squarepath")
                        }
                        .buttonStyle(.plain)
                        .font(actionFont)
                        .foregroundStyle(.secondary)

                        Button(action: { toggleReadLater(article) }) {
                            Image(systemName: article.isSaved ? "heart.fill" : "heart")
                                .foregroundStyle(article.isSaved ? Color.red : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .font(actionFont)

                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.primary.opacity(0.04) : Color.clear)
        .clipShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measuredWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        measuredWidth = newWidth
                    }
            }
        )
        #if os(macOS)
        .onHover { hover in
            isHovering = hover
        }
        #endif
    }

    private func postOnX(_ article: Article) {
        let text = article.title + "\n" + article.url.absoluteString
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let u = URL(string: "https://x.com/intent/post?text=\(encoded)") {
            #if os(macOS)
            NSWorkspace.shared.open(u)
            #elseif os(iOS)
            Task { await UIApplication.shared.open(u) }
            #endif
        }
    }

    private func toggleReadLater(_ article: Article) {
        Task { await feedService.toggleFavorite(for: article) }
    }

    private func copyURL(_ url: URL) {
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = url.absoluteString
        #endif
    }
}
