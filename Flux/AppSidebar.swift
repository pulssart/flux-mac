// AppSidebar.swift
// Vue principale avec navigation sidebar
import SwiftUI
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
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
import UniformTypeIdentifiers
import SwiftData

#if os(macOS)
import AppKit
#endif

private let sidebarItemTextOpacity: Double = 0.80

private func makeSidebarDragItemProvider(id: String) -> NSItemProvider {
    let provider = NSItemProvider()
    let payload = id.data(using: .utf8) ?? Data()
    let identifiers = [
        UTType.text.identifier,
        UTType.plainText.identifier,
        UTType.utf8PlainText.identifier
    ]

    for identifier in identifiers {
        provider.registerDataRepresentation(forTypeIdentifier: identifier, visibility: .all) { completion in
            completion(payload, nil)
            return nil
        }
    }

    provider.suggestedName = id
    return provider
}

struct AppSidebar: View {
    private struct AddFeedDeepLinkRequest {
        let preferredURL: URL
        let fallbackSiteURL: URL?
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(FeedService.self) private var feedService
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("windowBlurEnabled") private var windowBlurEnabled: Bool = false
    #if os(macOS)
    @AppStorage("safariExtensionAnnouncementToken") private var safariExtensionAnnouncementToken: String = ""
    #endif
    private let lm = LocalizationManager.shared
    @State private var selectedFeedId: UUID? = AppSidebar.allFeedsId
    @State private var selectedFolderId: UUID? = nil
    @State private var deepLinkArticleRequest: ArticleOpenRequest? = nil
    @State private var showAddSheet = false
    @State private var showSettings = false
    @State private var newFeedURL = ""
    @State private var addError: String?
    @State private var showDeleteAlert = false
    @State private var feedToDelete: Feed?
    @State private var readerWebURL: URL?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isWebOverlayOpen: Bool = false
    @State private var showIPhoneSidebar: Bool = false
    @State private var sidebarMeasuredWidth: CGFloat = 280
    @State private var mainNavigationWidth: CGFloat = 0
    // Effondrement des sections
    @AppStorage("sidebar.collapse.youtube") private var collapseYouTube: Bool = false
    @AppStorage("sidebar.collapse.music") private var collapseMusic: Bool = false
    @AppStorage("sidebar.collapse.other") private var collapseOther: Bool = false
    // Dossiers: édition et expansion
    @State private var renamingFolderId: UUID? = nil
    @State private var tempFolderName: String = ""
    @FocusState private var folderNameFocused: Bool
    @State private var expandedFolders: Set<UUID> = []
    @State private var dragTargetFeedId: UUID? = nil
    @State private var dragTargetFolderId: UUID? = nil
    // Onboarding
    @State private var showOnboarding: Bool = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @State private var showWhatsNew: Bool = false
    #if os(macOS)
    @State private var showSafariExtensionAnnouncement = false
    #endif
    
    // Identifiants sentinelles pour les entrées spéciales
    private static let allFeedsId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    private static let favoritesId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let newsletterId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let feedTimelineId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private static let discoveryId = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    private static let notesId = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
    private static let signauxId = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
    
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

    // En rail étroit, on évite l'overflow ">>" des items toolbar
    private var isSidebarCollapsedRail: Bool {
        sidebarMeasuredWidth < 120
    }

    private var isIPhoneDevice: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private var prefersOverlaySidebarOnIPad: Bool {
        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        if verticalSizeClass == .regular {
            return true
        }
        return mainNavigationWidth > 0 && mainNavigationWidth < 980
        #else
        false
        #endif
    }

    @ViewBuilder
    private func ipadSectionTitleText(_ title: String) -> some View {
        #if os(iOS)
        Text(title)
            .font(bodyPlus2Font)
            .opacity(sidebarItemTextOpacity)
        #else
        Text(title)
            .opacity(sidebarItemTextOpacity)
        #endif
    }
    
    // Propriété calculée pour le titre dynamique de la fenêtre
    private var dynamicTitle: String {
        if let selectedFeedId = selectedFeedId {
            if selectedFeedId == Self.feedTimelineId {
                return lm.localizedString(.newsletterFeed)
            }
            if selectedFeedId == Self.notesId {
                return notesSectionTitle
            }
            if selectedFeedId == Self.signauxId {
                return lm.localizedString(.signals)
            }
            if selectedFeedId != Self.allFeedsId && selectedFeedId != Self.favoritesId,
               let feed = feedService.feeds.first(where: { $0.id == selectedFeedId }) {
                return feed.title
            }
        }
        return "Flux"
    }

    private var notesSectionTitle: String {
        switch lm.currentLanguage {
        case .french: return "Notes"
        case .english: return "Notes"
        case .spanish: return "Notas"
        case .german: return "Notizen"
        case .italian: return "Note"
        case .portuguese: return "Notas"
        case .japanese: return "ノート"
        case .chinese: return "笔记"
        case .korean: return "노트"
        case .russian: return "Заметки"
        @unknown default: return "Notes"
        }
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
        #if os(macOS)
        .sheet(isPresented: $showSafariExtensionAnnouncement) {
            SafariExtensionAnnouncementSheet(isPresented: $showSafariExtensionAnnouncement)
        }
        #endif
        .sheet(isPresented: $showOnboarding, onDismiss: {
            showAddSheet = true
        }) {
            OnboardingView(isPresented: $showOnboarding)
                .environment(feedService)
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(isPresented: $showWhatsNew)
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
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            handleOpenSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWhatsNew)) { _ in
            showWhatsNew = true
        }
        .onAppear {
            // Initialiser le cache des compteurs non lus par dossier
            var counts: [UUID: Int] = [:]
            for folder in feedService.folders {
                let ids = Set(feeds(in: folder).map { $0.id })
                counts[folder.id] = feedService.articles.reduce(0) { partial, article in
                    partial + ((ids.contains(article.feedId) && article.isRead == false) ? 1 : 0)
                }
            }
            cachedFolderUnreadCounts = counts
            consumePendingDeepLinkIfNeeded()
            #if os(macOS)
            maybePresentSafariExtensionAnnouncementIfNeeded()
            #endif
            // Show What's New once per version (only after onboarding)
            if !showOnboarding && shouldShowWhatsNew() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showWhatsNew = true
                }
            }
        }
        .onChange(of: feedService.isRefreshing) { _, refreshing in
            if !refreshing {
                // Mettre à jour le cache des compteurs non lus par dossier
                var counts: [UUID: Int] = [:]
                for folder in feedService.folders {
                    let ids = Set(feeds(in: folder).map { $0.id })
                    counts[folder.id] = feedService.articles.reduce(0) { partial, article in
                        partial + ((ids.contains(article.feedId) && article.isRead == false) ? 1 : 0)
                    }
                }
                cachedFolderUnreadCounts = counts
            }
        }
        .onChange(of: deepLinkRouter.eventId) { _, _ in
            consumePendingDeepLinkIfNeeded()
        }
        .onChange(of: showOnboarding) { _, newValue in
            #if os(macOS)
            if newValue == false {
                maybePresentSafariExtensionAnnouncementIfNeeded()
            }
            #endif
            // New users finishing onboarding: mark What's New as seen (they just set up)
            if newValue == false {
                markWhatsNewAsSeen()
            }
        }
    }
    
    // MARK: - Body Subviews
    
    private var mainNavigationView: some View {
        GeometryReader { proxy in
            Group {
                #if os(macOS)
                navigationSplitViewContent
                #else
                if isIPhoneDevice {
                    iPhoneNavigationContent
                } else if prefersOverlaySidebarOnIPad {
                    navigationSplitViewContent
                        .navigationSplitViewStyle(.prominentDetail)
                } else {
                    navigationSplitViewContent
                        .navigationSplitViewStyle(.balanced)
                }
                #endif
            }
            .onAppear { updateNavigationLayout(for: proxy.size.width) }
            .onChange(of: proxy.size.width) { _, newValue in updateNavigationLayout(for: newValue) }
            .onChange(of: verticalSizeClass) { _, _ in applyPreferredColumnVisibility() }
        }
    }

    #if os(iOS)
    private var iPhoneNavigationContent: some View {
        NavigationStack {
            detailView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showIPhoneSidebar = true
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.body.weight(.medium))
                        }
                    }
                }
        }
        .sheet(isPresented: $showIPhoneSidebar) {
            NavigationStack {
                sidebarContent
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            HStack(spacing: 16) {
                                Button {
                                    newFeedURL = ""
                                    addError = nil
                                    showIPhoneSidebar = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        showAddSheet = true
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                }
                                Button {
                                    feedService.addFolder(name: "Nouveau dossier")
                                } label: {
                                    Image(systemName: "folder.badge.plus")
                                }
                                Button {
                                    showIPhoneSidebar = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        showSettings = true
                                    }
                                } label: {
                                    Image(systemName: "gearshape")
                                }
                            }
                        }
                        ToolbarItem(placement: .topBarLeading) {
                            Button("OK") {
                                showIPhoneSidebar = false
                            }
                            .bold()
                        }
                    }
                    .navigationTitle("Flux")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
    #endif

    private var navigationSplitViewContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 275, ideal: max(sidebarWidth, 275), max: 420)
        } detail: {
            detailView()
        }
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .modifier(WindowTitleModifier(title: dynamicTitle))
        .background(Color.clear)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbarColorScheme(colorScheme, for: .windowToolbar)
        .toolbar(removing: .sidebarToggle)
        #else
        .background(Color.clear)
        #endif
    }
    
    private var addFeedSheetContent: some View {
        AddFeedSheet(newFeedURL: $newFeedURL, addError: $addError) { url in
            do {
                let addedFeed = try await feedService.addFeed(from: url.absoluteString)
                await MainActor.run {
                    showAddSheet = false
                    focusFeed(addedFeed.id)
                    newFeedURL = ""
                    addError = nil
                }
            } catch let e as LocalizedError {
                await MainActor.run { addError = e.errorDescription ?? e.localizedDescription }
            } catch {
                await MainActor.run { addError = "Erreur inconnue" }
            }
        }
        .frame(width: 860, height: 840, alignment: .topLeading)
        #if os(macOS)
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
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
            .frame(width: 560)
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
        columnVisibility = columnVisibility == .all ? .detailOnly : .all
    }

    private func handleCollapseSidebar() {
        #if os(macOS)
        columnVisibility = .detailOnly
        #else
        columnVisibility = .detailOnly
        #endif
    }

    private func handleExpandSidebar() {
        #if os(macOS)
        columnVisibility = .all
        #else
        columnVisibility = .all
        #endif
    }

    private func updateNavigationLayout(for width: CGFloat) {
        guard width > 0 else { return }
        let previousPrefersOverlay = prefersOverlaySidebarOnIPad
        mainNavigationWidth = width
        #if os(iOS)
        if isIPhoneDevice {
            if columnVisibility != .detailOnly {
                applyPreferredColumnVisibility()
            }
        } else {
            let currentPrefersOverlay = prefersOverlaySidebarOnIPad
            if currentPrefersOverlay != previousPrefersOverlay {
                applyPreferredColumnVisibility()
            } else if columnVisibility != .all && columnVisibility != .detailOnly {
                applyPreferredColumnVisibility()
            }
        }
        #endif
    }

    private func applyPreferredColumnVisibility() {
        #if os(macOS)
        columnVisibility = .all
        #else
        columnVisibility = (isIPhoneDevice || prefersOverlaySidebarOnIPad) ? .detailOnly : .all
        #endif
    }

    private func handleOpenSettings() {
        showSettings = true
    }

    #if os(macOS)
    private func maybePresentSafariExtensionAnnouncementIfNeeded() {
        guard showOnboarding == false else { return }
        guard safariExtensionAnnouncementToken != SafariExtensionSupport.announcementToken else { return }
        safariExtensionAnnouncementToken = SafariExtensionSupport.announcementToken

        SafariExtensionSupport.refreshStatus { state in
            guard showSettings == false, showAddSheet == false else { return }
            if case .enabled = state { return }
            showSafariExtensionAnnouncement = true
        }
    }
    #endif

    private func consumePendingDeepLinkIfNeeded() {
        while let incomingURL = deepLinkRouter.consume() {
            handleIncomingURL(incomingURL)
        }
    }

    private func handleIncomingURL(_ incomingURL: URL) {
        if handleNotesWidgetDeepLinkIfNeeded(incomingURL) {
            return
        }

        if let browserURL = parseBrowserDeepLink(from: incomingURL) {
            openInDefaultBrowser(browserURL)
            return
        }

        if let request = parseAddFeedDeepLink(from: incomingURL) {
            handleAddFeedDeepLink(request)
            return
        }

        if let request = parseArticleDeepLink(from: incomingURL) {
            selectedFolderId = nil
            selectedFeedId = Self.allFeedsId
            deepLinkArticleRequest = request
            return
        }

        guard let scheme = incomingURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        openInDefaultBrowser(incomingURL)
    }

    private func handleNotesWidgetDeepLinkIfNeeded(_ incomingURL: URL) -> Bool {
        guard incomingURL.scheme?.lowercased() == "flux" else { return false }
        guard incomingURL.host?.lowercased() == "notes" else { return false }
        guard let components = URLComponents(url: incomingURL, resolvingAgainstBaseURL: false) else { return false }

        if components.queryItems?.first(where: { $0.name == "copy" }) != nil {
            copySelectedWidgetNoteToClipboard()
            return true
        }

        let deltaString = components.queryItems?.first(where: { $0.name == "delta" })?.value
        let delta = Int(deltaString ?? "") ?? 0
        guard delta != 0 else { return true }

        let total = max(1, feedService.readerNotes.count)
        let defaults = UserDefaults(suiteName: "group.com.adriendonot.fluxapp")
        let key = "notesWidget.selectedIndex"
        let current = defaults?.integer(forKey: key) ?? 0
        let next = (current + delta) % total
        let wrapped = next < 0 ? (next + total) : next
        defaults?.set(wrapped, forKey: key)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "NotesWidgetV2")
        WidgetCenter.shared.reloadTimelines(ofKind: "NotesWidgetV3")
        #endif
        return true
    }

    private func copySelectedWidgetNoteToClipboard() {
        let defaults = UserDefaults(suiteName: "group.com.adriendonot.fluxapp")
        let key = "notesWidget.selectedIndex"
        let idx = defaults?.integer(forKey: key) ?? 0

        let sortedNotes = feedService.readerNotes.sorted { $0.createdAt > $1.createdAt }
        guard sortedNotes.isEmpty == false else { return }
        let normalized = ((idx % sortedNotes.count) + sortedNotes.count) % sortedNotes.count
        let text = sortedNotes[normalized].selectedText

        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }

    private func openInDefaultBrowser(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.hide(nil)
        }
        #elseif canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }

    private func parseArticleDeepLink(from incomingURL: URL) -> ArticleOpenRequest? {
        guard incomingURL.scheme?.lowercased() == "flux" else { return nil }
        guard incomingURL.host?.lowercased() == "article" else { return nil }
        guard let components = URLComponents(url: incomingURL, resolvingAgainstBaseURL: false) else { return nil }

        let articleURLString = components.queryItems?.first(where: { $0.name == "url" })?.value
        guard
            let articleURLString,
            let articleURL = URL(string: articleURLString),
            let scheme = articleURL.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return nil
        }

        let readerValue = components.queryItems?.first(where: { $0.name == "reader" })?.value?.lowercased()
        let forceReaderFirst = !(readerValue == "0" || readerValue == "false")

        return ArticleOpenRequest(url: articleURL, forceReaderFirst: forceReaderFirst)
    }

    private func parseBrowserDeepLink(from incomingURL: URL) -> URL? {
        guard incomingURL.scheme?.lowercased() == "flux" else { return nil }
        guard incomingURL.host?.lowercased() == "open" else { return nil }
        guard let components = URLComponents(url: incomingURL, resolvingAgainstBaseURL: false) else { return nil }

        let urlValue = components.queryItems?.first(where: { $0.name == "url" })?.value
        guard
            let urlValue,
            let url = URL(string: urlValue),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return nil
        }

        return url
    }

    private func parseAddFeedDeepLink(from incomingURL: URL) -> AddFeedDeepLinkRequest? {
        guard incomingURL.scheme?.lowercased() == "flux" else { return nil }
        guard incomingURL.host?.lowercased() == "add-feed" else { return nil }
        guard let components = URLComponents(url: incomingURL, resolvingAgainstBaseURL: false) else { return nil }

        func parsedWebURL(named name: String) -> URL? {
            guard
                let value = components.queryItems?.first(where: { $0.name == name })?.value,
                let url = URL(string: value),
                let scheme = url.scheme?.lowercased(),
                scheme == "http" || scheme == "https"
            else {
                return nil
            }
            return url
        }

        let feedURL = parsedWebURL(named: "feed")
        let siteURL = parsedWebURL(named: "url") ?? parsedWebURL(named: "site")
        guard let preferredURL = feedURL ?? siteURL else { return nil }
        return AddFeedDeepLinkRequest(preferredURL: preferredURL, fallbackSiteURL: siteURL)
    }

    private func handleAddFeedDeepLink(_ request: AddFeedDeepLinkRequest) {
        addError = nil
        newFeedURL = request.preferredURL.absoluteString

        if let existingFeed = existingFeedMatching(urls: [request.preferredURL, request.fallbackSiteURL].compactMap { $0 }) {
            focusFeed(existingFeed.id)
            return
        }

        Task {
            do {
                let addedFeed = try await feedService.addFeed(from: request.preferredURL.absoluteString)
                await MainActor.run {
                    addError = nil
                    showAddSheet = false
                    focusFeed(addedFeed.id)
                }
            } catch FeedService.FeedError.duplicate {
                await MainActor.run {
                    if let existingFeed = existingFeedMatching(urls: [request.preferredURL, request.fallbackSiteURL].compactMap { $0 }) {
                        addError = nil
                        showAddSheet = false
                        focusFeed(existingFeed.id)
                    } else {
                        addError = FeedService.FeedError.duplicate.errorDescription
                        showAddSheet = true
                    }
                }
            } catch let error as LocalizedError {
                await MainActor.run {
                    addError = error.errorDescription ?? error.localizedDescription
                    newFeedURL = (request.fallbackSiteURL ?? request.preferredURL).absoluteString
                    showAddSheet = true
                }
            } catch {
                await MainActor.run {
                    addError = error.localizedDescription
                    newFeedURL = (request.fallbackSiteURL ?? request.preferredURL).absoluteString
                    showAddSheet = true
                }
            }
        }
    }

    private func focusFeed(_ feedId: UUID) {
        selectedFolderId = nil
        selectedFeedId = feedId
        #if os(iOS)
        columnVisibility = prefersOverlaySidebarOnIPad ? .detailOnly : .all
        #else
        columnVisibility = .all
        #endif
    }

    private func existingFeedMatching(urls: [URL]) -> Feed? {
        let normalizedTargets = Set(urls.map(normalizedFeedKey))
        guard normalizedTargets.isEmpty == false else { return nil }

        return feedService.feeds.first { feed in
            normalizedTargets.contains(normalizedFeedKey(feed.feedURL))
            || normalizedTargets.contains(normalizedFeedKey(feed.siteURL))
        }
    }

    private func normalizedFeedKey(_ url: URL?) -> String {
        guard let url else { return "" }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let normalizedScheme = components?.scheme?.lowercased()
        let normalizedHost = components?.host?.lowercased()
        components?.scheme = normalizedScheme
        components?.host = normalizedHost
        let normalizedURL = components?.url ?? url
        var value = normalizedURL.absoluteString
        while value.hasSuffix("/") && value.count > "https://a".count {
            value.removeLast()
        }
        return value
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
    
    private var musicFeeds: [Feed] {
        feedService.feeds.filter { f in
            feedService.isMusicFeedURL(f.feedURL) || feedService.isMusicFeedURL(f.siteURL ?? f.feedURL)
        }
    }

    private var otherFeeds: [Feed] {
        feedService.feeds.filter { f in
            let h = (f.siteURL?.host ?? f.feedURL.host ?? "").lowercased()
            let isYouTube = h.contains("youtube.com") || h.contains("youtu.be")
            let isMusic = feedService.isMusicFeedURL(f.feedURL) || feedService.isMusicFeedURL(f.siteURL ?? f.feedURL)
            return !isYouTube && !isMusic && f.folderId == nil
        }
    }
    
    // MARK: - Méthodes
    
    private func feeds(in folder: Folder) -> [Feed] {
        feedService.feeds.filter { f in
            let h = (f.siteURL?.host ?? f.feedURL.host ?? "").lowercased()
            return !(h.contains("youtube.com") || h.contains("youtu.be")) && f.folderId == folder.id
        }
    }
    
    @State private var cachedFolderUnreadCounts: [UUID: Int] = [:]

    private func unreadCount(in folder: Folder) -> Int {
        // Le trigger force le recalcul quand les articles sont marqués comme lus
        _ = feedService.badgeUpdateTrigger
        // Pendant le refresh global, garder le compteur gelé pour éviter les pics
        guard !feedService.isRefreshing else { return cachedFolderUnreadCounts[folder.id] ?? 0 }
        let ids = Set(feeds(in: folder).map { $0.id })
        let count = feedService.articles.reduce(0) { partial, article in
            partial + ((ids.contains(article.feedId) && article.isRead == false) ? 1 : 0)
        }
        return count
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
            musicSection
            youtubeSection
            otherFeedsSection
        }
        .font(sidebarItemFont)
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .listRowBackground(Color.clear)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { sidebarMeasuredWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newValue in
                        sidebarMeasuredWidth = newValue
                    }
            }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MusicMiniPlayer()
                .animation(.easeInOut(duration: 0.25), value: MusicKitService.shared.isActive || MusicKitService.shared.isLoading)
        }
        .navigationTitle("")
        .onChange(of: selectedFeedId) { _, newValue in
            NotificationCenter.default.post(name: .closeWebViewOverlay, object: nil)
            if newValue != nil { selectedFolderId = nil }
            #if os(iOS)
            if newValue != nil && isIPhoneDevice {
                showIPhoneSidebar = false
            } else if newValue != nil && prefersOverlaySidebarOnIPad {
                columnVisibility = .detailOnly
            }
            #endif
        }
        .onChange(of: selectedFolderId) { _, newValue in
            #if os(iOS)
            if newValue != nil && isIPhoneDevice {
                showIPhoneSidebar = false
            } else if newValue != nil && prefersOverlaySidebarOnIPad {
                columnVisibility = .detailOnly
            }
            #endif
        }
        .toolbar {
            sidebarToolbar
        }
        #if os(macOS)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
    }
    
    // Section "Aujourd'hui"
    @ViewBuilder
    private var todaySection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                ipadSectionTitleText(LocalizationManager.shared.localizedString(.newsWall))
                Spacer()
                if feedService.isRefreshing && feedService.refreshingFeedId == nil {
                    ProgressView().controlSize(.small)
                }
            }
            .contentShape(Rectangle())
            .sidebarSelectableRow(isSelected: selectedFeedId == Self.allFeedsId)
            .onTapGesture {
                selectedFeedId = Self.allFeedsId
                selectedFolderId = nil
            }
            
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.orange)
                ipadSectionTitleText(LocalizationManager.shared.localizedString(.myFavorites))
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
            .sidebarSelectableRow(isSelected: selectedFeedId == Self.favoritesId)
            .onTapGesture {
                selectedFeedId = Self.favoritesId
                selectedFolderId = nil
            }

            
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(.teal)
                ipadSectionTitleText(lm.localizedString(.newsletterFeed))
                Spacer()
            }
            .contentShape(Rectangle())
            .sidebarSelectableRow(isSelected: selectedFeedId == Self.feedTimelineId)
            .onTapGesture {
                selectedFeedId = Self.feedTimelineId
                selectedFolderId = nil
            }

            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                ipadSectionTitleText(lm.localizedString(.discoveryTitle))
                Spacer()
            }
            .contentShape(Rectangle())
            .sidebarSelectableRow(isSelected: selectedFeedId == Self.discoveryId)
            .onTapGesture {
                selectedFeedId = Self.discoveryId
                selectedFolderId = nil
            }


            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.mint)
                ipadSectionTitleText(lm.localizedString(.signals))
                Spacer()
            }
            .contentShape(Rectangle())
            .sidebarSelectableRow(isSelected: selectedFeedId == Self.signauxId)
            .onTapGesture {
                selectedFeedId = Self.signauxId
                selectedFolderId = nil
            }

            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom != .pad {
                HStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .foregroundStyle(.indigo)
                    ipadSectionTitleText(notesSectionTitle)
                    Spacer()
                    if feedService.readerNotesCount > 0 {
                        Text("\(feedService.readerNotesCount)")
                            .font(.caption2).bold()
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .background(Capsule().fill(Color.indigo.opacity(0.15)))
                            .foregroundStyle(.indigo)
                            .opacity(sidebarItemTextOpacity)
                    } else {
                        Text("0")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .opacity(sidebarItemTextOpacity)
                    }
                }
                .contentShape(Rectangle())
                .sidebarSelectableRow(isSelected: selectedFeedId == Self.notesId)
                .onTapGesture {
                    selectedFeedId = Self.notesId
                    selectedFolderId = nil
                }
            }
            #else
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundStyle(.indigo)
                ipadSectionTitleText(notesSectionTitle)
                Spacer()
                if feedService.readerNotesCount > 0 {
                    Text("\(feedService.readerNotesCount)")
                        .font(.caption2).bold()
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Color.indigo.opacity(0.15)))
                        .foregroundStyle(.indigo)
                        .opacity(sidebarItemTextOpacity)
                } else {
                    Text("0")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .opacity(sidebarItemTextOpacity)
                }
            }
            .contentShape(Rectangle())
            .sidebarSelectableRow(isSelected: selectedFeedId == Self.notesId)
            .onTapGesture {
                selectedFeedId = Self.notesId
                selectedFolderId = nil
            }
            #endif

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
    
    // Section Music (Apple Music / iTunes)
    @ViewBuilder
    private var musicSection: some View {
        let feeds = musicFeeds
        if !feeds.isEmpty {
            Section {
                ForEach(collapseMusic ? [] : feeds, id: \.id) { feed in
                    FeedRow(feed: feed, selectedFeedId: $selectedFeedId) {
                        deleteFeed($0)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sidebarSelectableRow(isSelected: selectedFeedId == feed.id)
                }
            } header: {
                Button(action: { withAnimation(.linear(duration: 0.15)) { collapseMusic.toggle() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: collapseMusic ? "chevron.right" : "chevron.down")
                        Text(LocalizationManager.shared.localizedString(.music))
                            .opacity(sidebarItemTextOpacity)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

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
                    .sidebarSelectableRow(isSelected: selectedFeedId == feed.id)
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
                .sidebarSelectableRow(isSelected: selectedFeedId == feed.id)
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
            if !isSidebarCollapsedRail {
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
            }
            
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
            }
            .help(LocalizationManager.shared.localizedString(.aiSettings))
        }
    }
    
    // MARK: - Vue détail
    
    // Vue d'une ligne de dossier
    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
        Group {
            // Ligne d'en-tête du dossier
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.clear)

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
                        Circle()
                            .fill(.blue)
                            .frame(width: 7, height: 7)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .sidebarSelectableRow(isSelected: selectedFolderId == folder.id)
            .onTapGesture {
                selectedFolderId = folder.id
                selectedFeedId = nil
                Task { await feedService.markFolderVisited(folderId: folder.id) }
            }
            .contextMenu {
                Button { startFolderRenaming(folder) } label: { Label(lm.localizedString(.rename), systemImage: "pencil") }
                Button(role: .destructive) { feedService.deleteFolder(folder.id) } label: { Label(lm.localizedString(.delete), systemImage: "trash") }
            }
            .sidebarFolderDropTarget(
                folderId: folder.id,
                isTargeted: dragTargetFolderId == folder.id,
                onTargeted: { isTargeted in
                    if isTargeted {
                        withAnimation(.linear(duration: 0.12)) {
                            dragTargetFolderId = folder.id
                            expandedFolders.insert(folder.id)
                        }
                    } else if dragTargetFolderId == folder.id {
                        withAnimation(.linear(duration: 0.12)) {
                            dragTargetFolderId = nil
                        }
                    }
                },
                onDropFeed: { fid in
                    print("[Sidebar] Drop on folder: \(folder.name) (\(folder.id)) — feed: \(fid)")
                    feedService.moveFeed(fid, toFolder: folder.id)
                    withAnimation(.linear(duration: 0.15)) {
                        expandedFolders.insert(folder.id)
                        dragTargetFolderId = nil
                    }
                }
            )
            .overlay {
                if dragTargetFolderId == folder.id {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(.horizontal, 6)
                }
            }

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
                    .sidebarSelectableRow(isSelected: selectedFeedId == feed.id)
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
                articleDetailView(feedId: nil, folderId: selectedFolderId)
            } else if let selectedFeedId {
                if selectedFeedId == Self.favoritesId {
                    articleDetailView(feedId: nil, showOnlyFavorites: true)
                } else if selectedFeedId == Self.feedTimelineId {
                    FeedTimelineView()
                } else if selectedFeedId == Self.discoveryId {
                    DiscoveryView()
                } else if selectedFeedId == Self.signauxId {
                    SignauxView()
                } else if selectedFeedId == Self.notesId {
                    NotesView()
                } else if selectedFeedId != Self.allFeedsId {
                    articleDetailView(feedId: selectedFeedId)
                } else {
                    articleDetailView()
                }
            } else {
                // Fallback: afficher le mur et corriger la sélection
                articleDetailView()
                    .onAppear {
                        if selectedFeedId == nil && selectedFolderId == nil {
                            selectedFeedId = Self.allFeedsId
                        }
                }
            }
        }
        #if os(macOS)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbarColorScheme(colorScheme, for: .windowToolbar)
        #endif
        .overlay(alignment: .bottom) {
            AudioGlassPill()
                .environment(feedService)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func articleDetailView(
        feedId: UUID? = nil,
        folderId: UUID? = nil,
        showOnlyFavorites: Bool = false
    ) -> some View {
        let content = ArticlesView(
            feedId: feedId,
            folderId: folderId,
            showOnlyFavorites: showOnlyFavorites,
            deepLinkRequest: $deepLinkArticleRequest
        )

        #if os(iOS)
        content.id(articleDetailIdentity(feedId: feedId, folderId: folderId, showOnlyFavorites: showOnlyFavorites))
        #else
        content
        #endif
    }

    private func articleDetailIdentity(
        feedId: UUID?,
        folderId: UUID?,
        showOnlyFavorites: Bool
    ) -> String {
        let feedPart = feedId?.uuidString ?? "all-feeds"
        let folderPart = folderId?.uuidString ?? "no-folder"
        let favoritesPart = showOnlyFavorites ? "favorites" : "regular"
        return "ipad-articles-\(feedPart)-\(folderPart)-\(favoritesPart)"
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

private extension View {
    @ViewBuilder
    func sidebarSelectableRow(isSelected: Bool, horizontalPadding: CGFloat = 14) -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            self
                .frame(minHeight: 42, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .background {
                    if isSelected {
                        Color.accentColor.opacity(0.15)
                            .padding(.horizontal, -horizontalPadding)
                    }
                }
        } else {
            self
                .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        }
        #else
        self
            .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        #endif
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

// MARK: - Music Mini Player (sidebar footer)

private struct MusicMiniPlayer: View {
    private var music: MusicKitService { MusicKitService.shared }
    @State private var isExpanded = false

    var body: some View {
        if music.isActive || music.isLoading {
            Group {
                if isExpanded {
                    expandedPlayer
                } else {
                    compactPlayer
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.25), value: isExpanded)
            .onChange(of: music.isActive) { _, isActive in
                if !isActive {
                    isExpanded = false
                }
            }
        }
    }

    private var compactPlayer: some View {
        HStack(alignment: .center, spacing: 10) {
            artworkButton

            trackInfo(lineLimit: 1)
                .frame(maxWidth: .infinity, alignment: .leading)

            playbackControls()
        }
    }

    private var expandedPlayer: some View {
        artworkView
            .overlay(alignment: .bottomLeading) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.00),
                            Color.black.opacity(0.18),
                            Color.black.opacity(0.72)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 10) {
                        trackInfo(lineLimit: 2, isOverlay: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(alignment: .bottom) {
                            playbackControls(isOverlay: true)
                            Spacer()
                            if music.isPlaying {
                                MusicEqualizerBars(color: .white)
                            }
                        }
                    }
                    .padding(14)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded = false
                    }
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
                        .padding(10)
                }
                .buttonStyle(.plain)
            }
    }

    private var artworkButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.toggle()
            }
        } label: {
            artworkView
        }
        .buttonStyle(.plain)
    }

    private var artworkView: some View {
        let cornerRadius: CGFloat = isExpanded ? 10 : 8
        let shadowColor = Color.black.opacity(isExpanded ? 0.18 : 0.10)
        let shadowRadius: CGFloat = isExpanded ? 14 : 5
        let shadowYOffset: CGFloat = isExpanded ? 6 : 2

        return Group {
        if let artworkURL = music.currentArtworkURL {
            AsyncImage(url: artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    artworkPlaceholder
                }
            }
        } else {
            artworkPlaceholder
        }
        }
        .frame(maxWidth: isExpanded ? .infinity : nil)
        .aspectRatio(1, contentMode: .fit)
        .frame(width: isExpanded ? nil : 40, height: isExpanded ? nil : 40)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .id(music.currentArtworkURL?.absoluteString ?? "artwork-placeholder")
    }

    private func trackInfo(lineLimit: Int, isOverlay: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: isExpanded ? 4 : 2) {
            Text(music.currentTrackTitle ?? "Apple Music")
                .font(.callout.weight(.medium))
                .foregroundStyle(isOverlay ? Color.white : Color.primary)
                .lineLimit(lineLimit)

            if let artist = music.currentTrackArtist, !artist.isEmpty {
                Text(artist)
                    .font(.caption)
                    .foregroundStyle(isOverlay ? Color.white.opacity(0.78) : Color.secondary)
                    .lineLimit(lineLimit)
            }
        }
        .shadow(color: isOverlay ? Color.black.opacity(0.30) : .clear, radius: 10, x: 0, y: 2)
    }

    private func playbackControls(isOverlay: Bool = false) -> some View {
        HStack(spacing: 4) {
            Button {
                Task { await MusicKitService.shared.skipToNext() }
            } label: {
                ZStack {
                    Circle()
                        .fill(controlFillStyle(isOverlay: isOverlay, overlayOpacity: 0.32))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 0.5))
                    Image(systemName: "backward.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(controlIconColor(isOverlay: isOverlay))
                }
            }
            .buttonStyle(.plain)
            .disabled(!music.hasQueue || music.isLoading)
            .opacity((!music.hasQueue || music.isLoading) ? 0.45 : 1)

            Button {
                Task { @MainActor in
                    MusicKitService.shared.togglePlayPause()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(controlFillStyle(isOverlay: isOverlay, overlayOpacity: 0.40))
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 0.5))
                    if music.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(controlIconColor(isOverlay: isOverlay))
                    } else {
                        Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(controlIconColor(isOverlay: isOverlay))
                            .offset(x: music.isPlaying ? 0 : 1)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                Task { await MusicKitService.shared.skipToPrevious() }
            } label: {
                ZStack {
                    Circle()
                        .fill(controlFillStyle(isOverlay: isOverlay, overlayOpacity: 0.32))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 0.5))
                    Image(systemName: "forward.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(controlIconColor(isOverlay: isOverlay))
                }
            }
            .buttonStyle(.plain)
            .disabled(!music.hasQueue || music.isLoading)
            .opacity((!music.hasQueue || music.isLoading) ? 0.45 : 1)

            if !isExpanded {
                Button {
                    Task { @MainActor in
                        MusicKitService.shared.stop()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(controlFillStyle(isOverlay: isOverlay, overlayOpacity: 0.32))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 0.5))
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(controlIconColor(isOverlay: isOverlay))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func controlFillStyle(isOverlay: Bool, overlayOpacity: Double) -> AnyShapeStyle {
        if isOverlay {
            return AnyShapeStyle(Color.black.opacity(overlayOpacity))
        }
        return AnyShapeStyle(.ultraThickMaterial)
    }

    private func controlIconColor(isOverlay: Bool) -> Color {
        isOverlay ? .white : .primary
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: isExpanded ? 10 : 8, style: .continuous)
                .fill(Color.pink.opacity(0.15))
            Image(systemName: "music.note")
                .font(.system(size: isExpanded ? 42 : 16, weight: .medium))
                .foregroundStyle(.pink)
        }
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
        .modifier(PlatformSidebarDragModifier(id: id))
    }
}

private struct PlatformSidebarDragModifier: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        content.onDrag {
            return makeSidebarDragItemProvider(id: id)
        }
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

private struct SidebarFolderDropTargetModifier: ViewModifier {
    let folderId: UUID
    let isTargeted: Bool
    let onTargeted: (Bool) -> Void
    let onDropFeed: (UUID) -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        content.background(
            SidebarFolderDropInteractionView(
                folderId: folderId,
                isTargeted: isTargeted,
                onTargeted: onTargeted,
                onDropFeed: onDropFeed
            )
        )
        #else
        content.dropDestination(for: String.self, action: { items, _ in
            guard let first = items.first, let feedId = UUID(uuidString: first) else { return false }
            onDropFeed(feedId)
            return true
        }, isTargeted: onTargeted)
        #endif
    }
}

#if os(iOS)
private struct SidebarFolderDropInteractionView: UIViewRepresentable {
    static let acceptedTypes: [UTType] = [
        .text,
        .plainText,
        .utf8PlainText
    ]

    let folderId: UUID
    let isTargeted: Bool
    let onTargeted: (Bool) -> Void
    let onDropFeed: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> FolderDropUIView {
        let view = FolderDropUIView()
        let interaction = UIDropInteraction(delegate: context.coordinator)
        view.addInteraction(interaction)
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ uiView: FolderDropUIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIDropInteractionDelegate {
        var parent: SidebarFolderDropInteractionView

        init(parent: SidebarFolderDropInteractionView) {
            self.parent = parent
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            let accepted = SidebarFolderDropInteractionView.acceptedTypes.map(\.identifier)
            return session.hasItemsConforming(toTypeIdentifiers: accepted)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
            parent.onTargeted(true)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
            parent.onTargeted(false)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
            parent.onTargeted(false)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            return UIDropProposal(operation: .move)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            let providers = session.items.map(\.itemProvider)
            guard let provider = providers.first else {
                parent.onTargeted(false)
                return
            }

            loadFeedID(from: provider) { feedId in
                DispatchQueue.main.async {
                    guard let feedId else {
                        self.parent.onTargeted(false)
                        return
                    }

                    self.parent.onDropFeed(feedId)
                    self.parent.onTargeted(false)
                }
            }
        }

        private func loadFeedID(from provider: NSItemProvider, completion: @escaping (UUID?) -> Void) {
            let typeIdentifiers = SidebarFolderDropInteractionView.acceptedTypes.map(\.identifier)
            loadFeedID(from: provider, remainingTypeIdentifiers: typeIdentifiers, completion: completion)
        }

        private func loadFeedID(
            from provider: NSItemProvider,
            remainingTypeIdentifiers: [String],
            completion: @escaping (UUID?) -> Void
        ) {
            guard let typeIdentifier = remainingTypeIdentifiers.first else {
                completion(nil)
                return
            }

            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let feedId = self.decodeFeedID(from: data) {
                    completion(feedId)
                    return
                }

                provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, itemError in
                    if let feedId = self.decodeFeedID(from: item) {
                        completion(feedId)
                        return
                    }

                    self.loadFeedID(
                        from: provider,
                        remainingTypeIdentifiers: Array(remainingTypeIdentifiers.dropFirst()),
                        completion: completion
                    )
                }
            }
        }

        private func decodeFeedID(from data: Data?) -> UUID? {
            guard let data else { return nil }
            let rawValue = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\0", with: "")
            return UUID(uuidString: rawValue)
        }

        private func decodeFeedID(from item: NSSecureCoding?) -> UUID? {
            switch item {
            case let string as NSString:
                let rawValue = String(string)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\0", with: "")
                return UUID(uuidString: rawValue)
            case let data as NSData:
                return decodeFeedID(from: data as Data)
            case let url as NSURL:
                let rawValue = url.absoluteString ?? ""
                return UUID(uuidString: rawValue)
            default:
                return nil
            }
        }
    }
}

private final class FolderDropUIView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif

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

    func sidebarFolderDropTarget(
        folderId: UUID,
        isTargeted: Bool,
        onTargeted: @escaping (Bool) -> Void,
        onDropFeed: @escaping (UUID) -> Void
    ) -> some View {
        modifier(SidebarFolderDropTargetModifier(folderId: folderId, isTargeted: isTargeted, onTargeted: onTargeted, onDropFeed: onDropFeed))
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
