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
    
    private var unreadCount: Int {
        feedService.articles.reduce(0) { partial, a in
            partial + ((a.feedId == feed.id && a.isRead == false) ? 1 : 0)
        }
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
            } else if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.caption2).bold()
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(Capsule().fill(Color.black.opacity(0.10)))
                    .opacity(sidebarItemTextOpacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRenaming {
                selectedFeedId = feed.id
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
