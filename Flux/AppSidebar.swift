// AppSidebar.swift
// Vue principale avec navigation sidebar
import SwiftUI
import Foundation
#if canImport(AppKit)
import AppKit
private let bodyPlus2Font: Font = {
    let size = NSFont.preferredFont(forTextStyle: .body).pointSize + 2
    return .system(size: size)
}()
private let sidebarItemFont: Font = {
    let size = NSFont.preferredFont(forTextStyle: .body).pointSize - 1.5
    return .system(size: size)
}()
#elseif canImport(UIKit)
import UIKit
private let bodyPlus2Font: Font = {
    let size = UIFont.preferredFont(forTextStyle: .body).pointSize + 2
    return .system(size: size)
}()
private let sidebarItemFont: Font = {
    let size = UIFont.preferredFont(forTextStyle: .body).pointSize - 1.5
    return .system(size: size)
}()
#else
private let bodyPlus2Font: Font = .body
private let sidebarItemFont: Font = .body
#endif
// import UniformTypeIdentifiers (retiré car drag personnalisé supprimé)
import SwiftData

#if os(macOS)
import AppKit
#endif

private let sidebarItemTextOpacity: Double = 0.80

struct AppSidebar: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(FeedService.self) private var feedService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("windowBlurEnabled") private var windowBlurEnabled: Bool = false
    private let lm = LocalizationManager.shared
    @State private var selectedFeedId: UUID? = AppSidebar.allFeedsId
    @State private var selectedFolderId: UUID? = nil
    @State private var showAddSheet = false
    @State private var showSettings = false
    @State private var newFeedURL = ""
    @State private var addError: String?
    @State private var showDeleteAlert = false
    @State private var feedToDelete: Feed?
    @State private var readerWebURL: URL?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isWebOverlayOpen: Bool = false
    // Effondrement des sections
    @AppStorage("sidebar.collapse.youtube") private var collapseYouTube: Bool = false
    @AppStorage("sidebar.collapse.other") private var collapseOther: Bool = false
    // Dossiers: édition et expansion
    @State private var renamingFolderId: UUID? = nil
    @State private var tempFolderName: String = ""
    @FocusState private var folderNameFocused: Bool
    @State private var expandedFolders: Set<UUID> = []
    @State private var dragTargetFeedId: UUID? = nil
    // Onboarding
    @State private var showOnboarding: Bool = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    
    // Identifiants sentinelles pour les entrées spéciales
    private static let allFeedsId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    private static let favoritesId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let newsletterId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let feedTimelineId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    
    // Propriété calculée pour déterminer si la sidebar doit être visible
    private var shouldShowSidebar: Bool {
        // En mode portrait, toujours montrer la sidebar
        if verticalSizeClass == .regular {
            return true
        }
        // En mode paysage, respecter le choix de l'utilisateur
        return columnVisibility == .all
    }
    
    // Propriété calculée pour la largeur de la sidebar selon l'orientation
    private var sidebarWidth: CGFloat {
        if verticalSizeClass == .regular {
            // Mode portrait : sidebar plus large
            return 320
        } else {
            // Mode paysage : sidebar standard
            return 280
        }
    }
    
    // Propriété calculée pour le titre dynamique de la fenêtre
    private var dynamicTitle: String {
        if let selectedFeedId = selectedFeedId {
            if selectedFeedId == Self.newsletterId {
                return lm.localizedString(.newsletterTitle)
            }
            if selectedFeedId == Self.feedTimelineId {
                return lm.localizedString(.newsletterFeed)
            }
            if selectedFeedId != Self.allFeedsId && selectedFeedId != Self.favoritesId,
               let feed = feedService.feeds.first(where: { $0.id == selectedFeedId }) {
                return feed.title
            }
        }
        return "Flux"
    }
    
    var body: some View {
        ZStack {
            mainNavigationView
        }
        .sheet(isPresented: $showAddSheet) {
            addFeedSheetContent
        }
        .sheet(isPresented: settingsSheetBinding) {
            settingsSheetContent
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
                .environment(feedService)
        }
        .alert(lm.localizedString(.deleteFeed), isPresented: $showDeleteAlert) {
            deleteAlertButtons
        } message: {
            deleteAlertMessage
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenWebViewOverlay"))) { _ in
            handleOpenWebViewOverlay()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CloseWebViewOverlay"))) { _ in
            handleCloseWebViewOverlay()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ToggleSidebar"))) { _ in
            handleToggleSidebar()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CollapseSidebar"))) { _ in
            handleCollapseSidebar()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ExpandSidebar"))) { _ in
            handleExpandSidebar()
        }
    }
    
    // MARK: - Body Subviews
    
    private var mainNavigationView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
        } detail: {
            detailView()
        }
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .modifier(WindowTitleModifier(title: dynamicTitle))
        #endif
        .background(Color.clear)
        #if os(macOS)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarBackground(Color.clear, for: .windowToolbar)
        #endif
        .onAppear {
            if verticalSizeClass == .regular {
                columnVisibility = .all
            }
        }
        .onChange(of: verticalSizeClass) { _, newValue in
            withAnimation(.linear(duration: 0.2)) {
                columnVisibility = .all
            }
        }
    }
    
    private var addFeedSheetContent: some View {
        AddFeedSheet(newFeedURL: $newFeedURL, addError: $addError) { url in
            do {
                try await feedService.addFeed(from: url.absoluteString)
                await MainActor.run { showAddSheet = false }
            } catch let e as LocalizedError {
                await MainActor.run { addError = e.errorDescription ?? e.localizedDescription }
            } catch {
                await MainActor.run { addError = "Erreur inconnue" }
            }
        }
        .frame(width: 420)
    }
    
    private var settingsSheetBinding: Binding<Bool> {
        Binding(
            get: { showSettings || feedService.showSettingsSheet },
            set: { newValue in
                showSettings = newValue
                if newValue == false { feedService.showSettingsSheet = false }
            }
        )
    }
    
    private var settingsSheetContent: some View {
        AISettingsInlineSheet(isPresented: $showSettings, showOnboarding: $showOnboarding)
            .environment(feedService)
            .frame(width: 440)
    }
    
    @ViewBuilder
    private var deleteAlertButtons: some View {
        Button(LocalizationManager.shared.localizedString(.cancel), role: .cancel) { }
        Button("Supprimer", role: .destructive) {
            if let feed = feedToDelete {
                Task {
                    await deleteFeedConfirmed(feed)
                }
            }
        }
    }
    
    @ViewBuilder
    private var deleteAlertMessage: some View {
        if let feed = feedToDelete {
            Text("Êtes-vous sûr de vouloir supprimer le flux \"\(feed.title)\" ? Cette action est irréversible.")
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleOpenWebViewOverlay() {
        withAnimation(.linear(duration: 0.2)) {
            isWebOverlayOpen = true
        }
    }

    private func handleCloseWebViewOverlay() {
        withAnimation(.linear(duration: 0.2)) {
            isWebOverlayOpen = false
        }
    }

    private func handleToggleSidebar() {
        withAnimation(.linear(duration: 0.2)) {
            columnVisibility = columnVisibility == .all ? .detailOnly : .all
        }
    }

    private func handleCollapseSidebar() {
        withAnimation(.linear(duration: 0.2)) {
            #if os(macOS)
            columnVisibility = .detailOnly
            #else
            if verticalSizeClass != .regular {
                columnVisibility = .detailOnly
            }
            #endif
        }
    }

    private func handleExpandSidebar() {
        withAnimation(.linear(duration: 0.2)) {
            #if os(macOS)
            columnVisibility = .all
            #else
            if verticalSizeClass != .regular {
                columnVisibility = .all
            }
            #endif
        }
    }
    
    // MARK: - Propriétés calculées
    
    private var youtubeFeeds: [Feed] {
        let feeds = feedService.feeds.filter { f in
            let h = (f.siteURL?.host ?? f.feedURL.host ?? "").lowercased()
            let isYouTube = h.contains("youtube.com") || h.contains("youtu.be")
            print("Feed: \(f.title), Host: \(h), IsYouTube: \(isYouTube)")
            return isYouTube
        }
        print("YouTube feeds count: \(feeds.count)")
        return feeds
    }
    
    private var otherFeeds: [Feed] {
        feedService.feeds.filter { f in
            let h = (f.siteURL?.host ?? f.feedURL.host ?? "").lowercased()
            return !(h.contains("youtube.com") || h.contains("youtu.be")) && f.folderId == nil
        }
    }
    
    // MARK: - Méthodes
    
    private func feeds(in folder: Folder) -> [Feed] {
        feedService.feeds.filter { f in
            let h = (f.siteURL?.host ?? f.feedURL.host ?? "").lowercased()
            return !(h.contains("youtube.com") || h.contains("youtu.be")) && f.folderId == folder.id
        }
    }
    
    private func unreadCount(in folder: Folder) -> Int {
        // Le trigger force le recalcul quand les articles sont marqués comme lus
        _ = feedService.badgeUpdateTrigger
        let ids = Set(feeds(in: folder).map { $0.id })
        return feedService.articles.reduce(0) { partial, article in
            partial + ((ids.contains(article.feedId) && article.isRead == false) ? 1 : 0)
        }
    }
    
    private func toggleFolder(_ folderId: UUID) {
        withAnimation(.linear(duration: 0.15)) {
            if expandedFolders.contains(folderId) {
                expandedFolders.remove(folderId)
            } else {
                expandedFolders.insert(folderId)
            }
        }
    }
    
    private func startFolderRenaming(_ folder: Folder) {
        renamingFolderId = folder.id
        tempFolderName = folder.name
    }
    
    private func commitFolderRename(folderId: UUID) {
        if feedService.folders.contains(where: { $0.id == folderId }) {
            feedService.renameFolder(folderId, to: tempFolderName)
        }
        renamingFolderId = nil
        tempFolderName = ""
        folderNameFocused = false
    }
    
    private func deleteFeed(_ feed: Feed) {
        feedToDelete = feed
        showDeleteAlert = true
    }
    
    private func deleteFeedConfirmed(_ feed: Feed) async {
        // Pass the Feed directly (FeedService.deleteFeed expects Feed)
        do {
            try await feedService.deleteFeed(feed)
        } catch {
            // Handle deletion error if needed
        }
        showDeleteAlert = false
        feedToDelete = nil
    }

    
    // MARK: - Sous-vues et méthodes
    
    // Contenu de la sidebar
    @ViewBuilder
    private var sidebarContent: some View {
        List {
            todaySection
            foldersSection
            youtubeSection
            otherFeedsSection
        }
        .font(sidebarItemFont)
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .listRowBackground(Color.clear)
        .navigationTitle("")
        .onChange(of: selectedFeedId) { _, newValue in
            if let fid = newValue, fid != Self.allFeedsId && fid != Self.favoritesId {
                Task { await feedService.markFeedVisited(feedId: fid) }
            }
            NotificationCenter.default.post(name: .closeWebViewOverlay, object: nil)
            if newValue != nil { selectedFolderId = nil }
        }
        .toolbar {
            sidebarToolbar
        }
    }
    
    // Section "Aujourd'hui"
    @ViewBuilder
    private var todaySection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                Text(LocalizationManager.shared.localizedString(.newsWall))
                    .opacity(sidebarItemTextOpacity)
                Spacer()
                if feedService.isRefreshing && feedService.refreshingFeedId == nil {
                    ProgressView().controlSize(.small)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedFeedId = Self.allFeedsId
                selectedFolderId = nil
            }
            .listRowBackground(selectedFeedId == Self.allFeedsId ? Color.accentColor.opacity(0.15) : Color.clear)
            
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.orange)
                Text(LocalizationManager.shared.localizedString(.myFavorites))
                    .opacity(sidebarItemTextOpacity)
                Spacer()
                if feedService.favoriteArticlesCount > 0 {
                    Text("\(feedService.favoriteArticlesCount)")
                        .font(.caption2).bold()
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                        .foregroundStyle(.orange)
                        .opacity(sidebarItemTextOpacity)
                } else {
                    Text("0")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .opacity(sidebarItemTextOpacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedFeedId = Self.favoritesId
                selectedFolderId = nil
            }
            .listRowBackground(selectedFeedId == Self.favoritesId ? Color.accentColor.opacity(0.15) : Color.clear)

            HStack(spacing: 8) {
                Image(systemName: "newspaper")
                    .foregroundStyle(.blue)
                Text(lm.localizedString(.newsletterTitle))
                    .opacity(sidebarItemTextOpacity)
                Text(lm.localizedString(.beta))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(.secondary.opacity(0.15))
                    )
                    .opacity(sidebarItemTextOpacity)
                Spacer()
                if feedService.isGeneratingNewsletter {
                    ProgressView().controlSize(.small)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedFeedId = Self.newsletterId
                selectedFolderId = nil
            }
            .listRowBackground(selectedFeedId == Self.newsletterId ? Color.accentColor.opacity(0.15) : Color.clear)
            
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(.teal)
                Text(lm.localizedString(.newsletterFeed))
                    .opacity(sidebarItemTextOpacity)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedFeedId = Self.feedTimelineId
                selectedFolderId = nil
            }
            .listRowBackground(selectedFeedId == Self.feedTimelineId ? Color.accentColor.opacity(0.15) : Color.clear)
        } header: {
            Text(lm.localizedString(.today))
                .opacity(sidebarItemTextOpacity)
        }
    }
    
    // Section des dossiers
    @ViewBuilder
    private var foldersSection: some View {
        if !feedService.folders.isEmpty {
            Section {
                ForEach(feedService.folders, id: \.id) { folder in
                    folderRow(folder)
                }
                .onMove { indices, newOffset in
                    feedService.reorderFolders(fromOffsets: indices, toOffset: newOffset)
                }
            } header: {
                Text(LocalizationManager.shared.localizedString(.folders))
                    .opacity(sidebarItemTextOpacity)
            }
        }
    }
    
    // Section YouTube
    @ViewBuilder
    private var youtubeSection: some View {
        let feeds = youtubeFeeds
        // Debug: on peut voir dans la console si cette section est appelée
        let _ = print("YouTube section - feeds count: \(feeds.count), isEmpty: \(feeds.isEmpty)")
        if !feeds.isEmpty {
            Section {
                ForEach(collapseYouTube ? [] : feeds, id: \.id) { feed in
                    FeedRow(feed: feed, selectedFeedId: $selectedFeedId) {
                        deleteFeed($0)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sidebarDraggable(id: feed.id.uuidString)
                    .sidebarDropTarget(
                        feed: feed,
                        feeds: feeds,
                        isTargeted: dragTargetFeedId == feed.id,
                        onTargeted: { isTargeted in
                            if isTargeted {
                                dragTargetFeedId = feed.id
                            } else if dragTargetFeedId == feed.id {
                                dragTargetFeedId = nil
                            }
                        }
                    ) { indices, newOffset in
                        feedService.reorderYouTubeFeeds(fromOffsets: indices, toOffset: newOffset)
                    }
                    .listRowBackground(selectedFeedId == feed.id ? Color.accentColor.opacity(0.15) : Color.clear)
                }
                .onMove(perform: { indices, newOffset in
                    feedService.reorderYouTubeFeeds(fromOffsets: indices, toOffset: newOffset)
                })
            } header: {
                Button(action: { withAnimation(.linear(duration: 0.15)) { collapseYouTube.toggle() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: collapseYouTube ? "chevron.right" : "chevron.down")
                        Text(LocalizationManager.shared.localizedString(.youtube))
                            .opacity(sidebarItemTextOpacity)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // Section autres flux
    @ViewBuilder
    private var otherFeedsSection: some View {
        Section {
            ForEach(collapseOther ? [] : otherFeeds, id: \.id) { feed in
                FeedRow(feed: feed, selectedFeedId: $selectedFeedId) {
                    deleteFeed($0)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sidebarDraggable(id: feed.id.uuidString)
                .sidebarDropTarget(
                    feed: feed,
                    feeds: otherFeeds,
                    isTargeted: dragTargetFeedId == feed.id,
                    onTargeted: { isTargeted in
                        if isTargeted {
                            dragTargetFeedId = feed.id
                        } else if dragTargetFeedId == feed.id {
                            dragTargetFeedId = nil
                        }
                    }
                ) { indices, newOffset in
                    feedService.reorderNonYouTubeFeeds(fromOffsets: indices, toOffset: newOffset)
                }
                .listRowBackground(selectedFeedId == feed.id ? Color.accentColor.opacity(0.15) : Color.clear)
            }
            .onMove(perform: { indices, newOffset in
                feedService.reorderNonYouTubeFeeds(fromOffsets: indices, toOffset: newOffset)
            })
        } header: {
            Button(action: { withAnimation(.linear(duration: 0.15)) { collapseOther.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: collapseOther ? "chevron.right" : "chevron.down")
                    Text(LocalizationManager.shared.localizedString(.myFeeds))
                        .opacity(sidebarItemTextOpacity)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .dropDestination(for: String.self) { items, _ in
            print("[Sidebar] Drop on Mes Flux — items: \(items)")
            // Déposer ici pour sortir un flux d'un dossier (retour à la racine "Mes Flux")
            guard let first = items.first, let fid = UUID(uuidString: first) else { return false }
            feedService.moveFeed(fid, toFolder: nil)
            return true
        }
    }
    
    // Footer AI tokens supprimé
    
    // Toolbar de la sidebar
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button(action: {
                newFeedURL = ""
                addError = nil
                showAddSheet = true
            }, label: {
                Image(systemName: "plus")
            })
            .help(LocalizationManager.shared.localizedString(.addFeed))
            
            Button(action: { feedService.addFolder(name: "Nouveau dossier") }) {
                Image(systemName: "folder.badge.plus")
            }
            .help(LocalizationManager.shared.localizedString(.addFolder))
            
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
            }
            .help(LocalizationManager.shared.localizedString(.aiSettings))
        }
    }
    
    // Toolbar de la vue détail
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) { }
    }
    
    // MARK: - Vue détail
    
    // Vue d'une ligne de dossier
    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
        Group {
            // Ligne d'en-tête du dossier
            HStack(spacing: 8) {
                Button(action: { toggleFolder(folder.id) }) {
                    Image(systemName: expandedFolders.contains(folder.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Image(systemName: "folder")
                if renamingFolderId == folder.id {
                    TextField("Nom du dossier", text: Binding(
                        get: { tempFolderName },
                        set: { tempFolderName = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .focused($folderNameFocused)
                    .onSubmit { commitFolderRename(folderId: folder.id) }
                    .onAppear { if tempFolderName.isEmpty { tempFolderName = folder.name }; folderNameFocused = true }
                } else {
                    Text(folder.name)
                        .font(bodyPlus2Font)
                        .opacity(sidebarItemTextOpacity)
                }
                Spacer(minLength: 8)
                let countUnread = unreadCount(in: folder)
                if countUnread > 0 {
                    Text("\(countUnread)")
                        .font(.caption2).bold()
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Color.black.opacity(0.10)))
                        .opacity(sidebarItemTextOpacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedFolderId = folder.id
                selectedFeedId = nil
                Task { await feedService.markFolderVisited(folderId: folder.id) }
            }
            .contextMenu {
                Button { startFolderRenaming(folder) } label: { Label(lm.localizedString(.rename), systemImage: "pencil") }
                Button(role: .destructive) { feedService.deleteFolder(folder.id) } label: { Label(lm.localizedString(.delete), systemImage: "trash") }
            }
            .dropDestination(for: String.self) { items, _ in
                print("[Sidebar] Drop on folder: \(folder.name) (\(folder.id)) — items: \(items)")
                guard let first = items.first, let fid = UUID(uuidString: first) else { return false }
                feedService.moveFeed(fid, toFolder: folder.id)
                withAnimation(.linear(duration: 0.15)) { expandedFolders.insert(folder.id) }
                return true
            }
            .listRowBackground(selectedFolderId == folder.id ? Color.accentColor.opacity(0.15) : Color.clear)

            // Lignes des flux dans le dossier
            if expandedFolders.contains(folder.id) || renamingFolderId == folder.id {
                ForEach(feeds(in: folder), id: \.id) { feed in
                    FeedRow(feed: feed, selectedFeedId: $selectedFeedId) { f in
                        deleteFeed(f)
                    }
                    .padding(.leading, 22)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sidebarDraggable(id: feed.id.uuidString)
                    .sidebarDropTarget(
                        feed: feed,
                        feeds: feeds(in: folder),
                        isTargeted: dragTargetFeedId == feed.id,
                        onTargeted: { isTargeted in
                            if isTargeted {
                                dragTargetFeedId = feed.id
                            } else if dragTargetFeedId == feed.id {
                                dragTargetFeedId = nil
                            }
                        }
                    ) { indices, newOffset in
                        feedService.reorderFeeds(inFolder: folder.id, fromOffsets: indices, toOffset: newOffset)
                    }
                    .listRowBackground(selectedFeedId == feed.id ? Color.accentColor.opacity(0.15) : Color.clear)
                }
                .onMove(perform: { indices, newOffset in
                    feedService.reorderFeeds(inFolder: folder.id, fromOffsets: indices, toOffset: newOffset)
                })
            }
        }
    }
    
    @ViewBuilder
    private func detailView() -> some View {
        VStack(spacing: 0) {
            webViewControls
            if let selectedFolderId {
                ArticlesView(feedId: nil, folderId: selectedFolderId)
            } else if let selectedFeedId {
                if selectedFeedId == Self.favoritesId {
                    ArticlesView(feedId: nil, showOnlyFavorites: true)
                } else if selectedFeedId == Self.feedTimelineId {
                    FeedTimelineView()
                } else if selectedFeedId == Self.newsletterId {
                    NewsletterView()
                } else if selectedFeedId != Self.allFeedsId {
                    ArticlesView(feedId: selectedFeedId)
                } else {
                    ArticlesView()
                }
            } else {
                // Fallback: afficher le mur et corriger la sélection
                ArticlesView()
                    .onAppear {
                        if selectedFeedId == nil && selectedFolderId == nil {
                            selectedFeedId = Self.allFeedsId
                        }
                    }
            }
        }
        .toolbar {
            detailToolbar
        }
        .overlay(alignment: .bottom) {
            AudioGlassPill()
                .environment(feedService)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
    }
    
    @ViewBuilder
    private var webViewControls: some View {
        if readerWebURL != nil {
            HStack(spacing: 16) {
                Button(action: { readerWebURL = nil }) {
                    Image(systemName: "xmark.circle")
                        .imageScale(.large)
                }
                .help(lm.localizedString(.helpCloseArticle))
                Spacer()
            }
        }
    }

}

private struct AudioMiniPlayerFooter: View {
    @Environment(FeedService.self) private var feedService
    var body: some View {
        VStack(spacing: 0) {
            if feedService.isAudioOverlayVisible {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        // Favicon agrandi à gauche
                        if let icon = feedService.audioOverlayIcon {
                            AsyncImage(url: icon) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Color.gray.opacity(0.2)
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        } else {
                            Image(systemName: "globe")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                        }
                        // Titre et durée
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feedService.audioOverlayTitle ?? "")
                                .lineLimit(1)
                                .font(.callout)
                                .foregroundStyle(.primary)
                            Text(timeString(feedService.audioCurrentTime) + " / " + timeString(feedService.audioDuration))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        // Contrôles à droite
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(.ultraThickMaterial)
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                                if feedService.isAudioLoading {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: feedService.isAudioPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 12, weight: .bold))
                                }
                            }
                            .onTapGesture {
                                if feedService.isAudioLoading { return }
                                if feedService.isAudioPlaying { feedService.pauseAudio() } else { feedService.resumeAudio() }
                            }
                            ZStack {
                                Circle().fill(.ultraThickMaterial)
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                                Image(systemName: "stop.fill").font(.system(size: 12, weight: .bold))
                            }
                            .onTapGesture { if !feedService.isAudioLoading { feedService.stopAudio() } }
                        }
                    }
                    GeometryReader { geo in
                        let p = max(0, min(1, (feedService.audioDuration > 0 ? feedService.audioCurrentTime / feedService.audioDuration : 0)))
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.12))
                            Capsule().fill(LinearGradient(colors: [.accentColor.opacity(0.9), .accentColor.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * p)
                        }
                    }
                    .frame(height: 5)
                    .padding(.horizontal, 6)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .overlay(
                    Rectangle().fill(Color.black.opacity(0.08)).frame(height: 0.5), alignment: .top
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: feedService.isAudioOverlayVisible)
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

private struct SidebarDraggableModifier: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.clear)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(object: id as NSString) }
    }
}

private struct SidebarDropTargetModifier: ViewModifier {
    let feed: Feed
    let feeds: [Feed]
    let isTargeted: Bool
    let onTargeted: (Bool) -> Void
    let reorder: (IndexSet, Int) -> Void

    func body(content: Content) -> some View {
        content
            .dropDestination(for: String.self, action: { items, _ in
                guard let first = items.first,
                      let draggedId = UUID(uuidString: first),
                      let fromIndex = feeds.firstIndex(where: { $0.id == draggedId }),
                      let toIndex = feeds.firstIndex(where: { $0.id == feed.id }) else {
                    return false
                }
                if fromIndex == toIndex { return false }
                var destination = toIndex
                if fromIndex < toIndex { destination += 1 }
                reorder(IndexSet(integer: fromIndex), destination)
                return true
            }, isTargeted: onTargeted)
            .overlay(alignment: .top) {
                if isTargeted {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .padding(.leading, 6)
                }
            }
    }
}

private extension View {
    func sidebarDraggable(id: String) -> some View {
        modifier(SidebarDraggableModifier(id: id))
    }

    func sidebarDropTarget(
        feed: Feed,
        feeds: [Feed],
        isTargeted: Bool,
        onTargeted: @escaping (Bool) -> Void,
        reorder: @escaping (IndexSet, Int) -> Void
    ) -> some View {
        modifier(SidebarDropTargetModifier(feed: feed, feeds: feeds, isTargeted: isTargeted, onTargeted: onTargeted, reorder: reorder))
    }
}

// DropDelegate supprimé: on applique exactement le même pattern que pour les dossiers

#if os(macOS)
struct WindowTitleModifier: ViewModifier {
    let title: String
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                if let window = NSApplication.shared.windows.first {
                    window.title = title
                    window.isMovableByWindowBackground = false
                }
            }
            .onChange(of: title) { _, newTitle in
                if let window = NSApplication.shared.windows.first {
                    window.title = newTitle
                    window.isMovableByWindowBackground = false
                }
            }
    }
}
#endif
