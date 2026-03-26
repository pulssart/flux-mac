import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
private let bodyPlus1Font: Font = {
    let size = NSFont.preferredFont(forTextStyle: .body).pointSize + 0.5
    return .system(size: size)
}()
#elseif canImport(UIKit)
import UIKit
private let bodyPlus1Font: Font = {
    let size = UIFont.preferredFont(forTextStyle: .body).pointSize + 0.5
    return .system(size: size)
}()
#else
private let bodyPlus1Font: Font = .body
#endif

private let sidebarItemTextOpacity: Double = 0.80

struct FeedRow: View {
    let feed: Feed
    @Binding var selectedFeedId: UUID?
    let onDelete: (Feed) -> Void
    
    @Environment(FeedService.self) private var feedService
    @Environment(\.modelContext) private var modelContext
    @State private var isRenaming = false
    @State private var newTitle = ""
    @FocusState private var titleFieldFocused: Bool
    private let lm = LocalizationManager.shared

    private var isMusicFeed: Bool {
        feedService.isMusicFeedURL(feed.feedURL) || feedService.isMusicFeedURL(feed.siteURL ?? feed.feedURL)
    }

    private var isPlayingFromThisFeed: Bool {
        guard MusicKitService.shared.isPlaying,
              let currentURL = MusicKitService.shared.currentArticleURL else { return false }
        return feedService.articles.contains { $0.feedId == feed.id && $0.url == currentURL }
    }

    @State private var cachedUnreadCount: Int = 0

    private var unreadCount: Int {
        _ = feedService.badgeUpdateTrigger
        guard !isMusicFeed else { return 0 }
        // Pendant le refresh global, garder le compteur gelé pour éviter les pics
        guard !feedService.isRefreshing else { return cachedUnreadCount }
        let count = feedService.articles.reduce(0) { partial, a in
            partial + ((a.feedId == feed.id && a.isRead == false) ? 1 : 0)
        }
        return count
    }
    
    var body: some View {
        HStack(spacing: 8) {
            if let icon = faviconURL(for: feed) {
                AsyncImage(url: icon) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit()
                    default: Color.gray.opacity(0.2)
                    }
                }
                .frame(width: 13, height: 13)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                Image(systemName: "globe")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 13, height: 13)
            }
            
            if isRenaming {
                TextField("Nom du flux", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($titleFieldFocused)
                    .onSubmit {
                        commitRename()
                    }
                    .onAppear {
                        if newTitle.isEmpty {
                            newTitle = feed.title
                        }
                        titleFieldFocused = true
                    }
            } else {
                Text(feed.title)
                    .font(bodyPlus1Font)
                    .lineLimit(1)
                    .opacity(sidebarItemTextOpacity)
            }
            
            Spacer()
            
            // Spinner de rafraîchissement pour ce feed
            if feedService.isRefreshing, feedService.refreshingFeedId == feed.id {
                ProgressView()
                    .controlSize(.small)
            } else if isMusicFeed && isPlayingFromThisFeed {
                MusicEqualizerBars()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 14)
            } else if unreadCount > 0 {
                Circle()
                    .fill(.blue)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRenaming {
                selectedFeedId = feed.id
            }
        }
        .onChange(of: feedService.isRefreshing) { _, refreshing in
            if !refreshing {
                // Mettre à jour le cache quand le refresh se termine
                if !isMusicFeed {
                    cachedUnreadCount = feedService.articles.reduce(0) { partial, a in
                        partial + ((a.feedId == feed.id && a.isRead == false) ? 1 : 0)
                    }
                }
            }
        }
        .onAppear {
            if !isMusicFeed {
                cachedUnreadCount = feedService.articles.reduce(0) { partial, a in
                    partial + ((a.feedId == feed.id && a.isRead == false) ? 1 : 0)
                }
            }
        }
        .contextMenu {
            Button {
                startRenaming()
            } label: {
                Label(lm.localizedString(.rename), systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                onDelete(feed)
            } label: {
                Label(lm.localizedString(.delete), systemImage: "trash")
            }
        }
    }
    
    // MARK: - Fonctions de renommage
    
    private func startRenaming() {
        newTitle = feed.title
        isRenaming = true
    }
    
    private func commitRename() {
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty && trimmedTitle != feed.title {
            feed.title = trimmedTitle
            // Sauvegarder les changements
            do {
                try modelContext.save()
            } catch {
                print("Erreur lors de la sauvegarde: \(error)")
            }
        }
        isRenaming = false
        newTitle = ""
    }
}

// Utilitaire favicon déjà présent dans ArticlesView; on le réutilise ici
private func faviconURL(for feed: Feed) -> URL? {
    if let explicit = feed.faviconURL { return explicit }
    if let site = feed.siteURL, let host = site.host, let scheme = site.scheme {
        return URL(string: "\(scheme)://\(host)/favicon.ico")
    }
    if let host = feed.feedURL.host, let scheme = feed.feedURL.scheme {
        return URL(string: "\(scheme)://\(host)/favicon.ico")
    }
    return nil
}
