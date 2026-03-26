// WebView.swift
// Contains the WebDrawer SwiftUI view for macOS that presents a WKWebView in a sliding overlay with a close button.

import SwiftUI
#if os(macOS)
import WebKit
import AppKit
import Combine
import AVFoundation
import SwiftData
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

struct WebDrawer: View {
    let url: URL
    let forceAISummary: Bool
    let forceReaderFirst: Bool
    let hideReaderSidebar: Bool
    let useMonochromeDefaultTheme: Bool
    let showCloseButton: Bool
    let onClose: () -> Void
    private let lm = LocalizationManager.shared
    @State private var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        // Utiliser un store éphémère pour éviter la création/lecture de clés WebCrypto dans le Trousseau
        config.websiteDataStore = .nonPersistent()
        // Bloquer WebCrypto (subtle) pour empêcher WebKit de créer la "WebCrypto Master Key"
        let ucc = WKUserContentController()
        let blockWebCrypto = """
        try {
          if (window.crypto && window.crypto.subtle) {
            const disabled = new Proxy({}, { get() { throw new Error('WebCrypto disabled by app'); } });
            Object.defineProperty(window.crypto, 'subtle', { get: () => disabled, configurable: true });
          }
        } catch (e) { }
        """
        let script = WKUserScript(source: blockWebCrypto, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        ucc.addUserScript(script)
        // Désactiver l'enregistrement de Service Workers (peut aussi déclencher stockage persistant)
        let blockSW = """
        try {
          if (navigator && navigator.serviceWorker) {
            navigator.serviceWorker.register = function(){ return Promise.reject(new Error('ServiceWorker disabled by app')); };
          }
        } catch (e) { }
        """
        ucc.addUserScript(WKUserScript(source: blockSW, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController = ucc
        // JS autorisé (comportement par défaut), ici laissé explicite si futur durcissement
        if #available(macOS 13.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        return WKWebView(frame: .zero, configuration: config)
    }()
    @State private var readerMode = false
    @State private var isReaderAnimating = false
    @State private var showReaderMask = false
    @State private var readerPhraseIndex = 0
    @State private var readerTicker = Timer.publish(every: 1.4, on: .main, in: .common).autoconnect()
    @State private var pageTitle: String = ""
    private var readerPhrases: [String] { lm.loadingPhrases() }
    private enum ReaderTheme { case sepia, paper, sage, grey, dark }
    private enum ReaderFont { case serif, sans }
    @State private var readerTheme: ReaderTheme = .paper
    @State private var readerFont: ReaderFont = .serif
    
    @Environment(FeedService.self) private var feedService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("reader.openArticleInReaderFirst") private var openArticleInReaderFirst: Bool = true
    @AppStorage("reader.reduceOverlaysEnabled") private var reduceOverlaysEnabled: Bool = false
    
    // MARK: - Summarization & Speech State
    @State private var isSummarizing = false
    @State private var summaryError: String?
    @State private var isSpeaking = false
    @State private var summaryText: String?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var showSummaryPanel: Bool = false
    // Partage X
    @State private var isPostingToX: Bool = false
    @State private var postXError: String?
    @State private var loadingPulse = false
    @State private var readerTimeoutTask: Task<Void, Never>?
    @State private var readerFallbackTriggered = false
    @State private var readerAITask: Task<Void, Never>?
    @State private var isApplyingReaderAI = false
    @State private var readerAICompleted = false
    @State private var readerAIAutoRetryCount = 0
    @State private var isShowingAISummary = false
    @State private var forceClassicReaderOnNextLoad = false
    @State private var isClassicReaderOptionsExpanded = false
    @State private var isWindowFullScreen = false
    // Métadonnées extraites pour la sidebar du lecteur
    @State private var readerEntities: [String] = []
    @State private var readerTags: [String] = []
    @State private var readerSourceName: String = ""

    private var shouldUseFloatingReaderControls: Bool {
        readerMode && !showReaderMask && (!showCloseButton || hideReaderSidebar)
    }

    private var shouldUseFullscreenCustomPill: Bool {
        isWindowFullScreen && shouldUseFloatingReaderControls
    }

    private var floatingReaderControlForeground: Color {
        isLightReaderTheme ? Color(red: 0.24, green: 0.29, blue: 0.36) : .white
    }

    init(
        url: URL,
        startInReaderMode: Bool = false,
        forceAISummary: Bool = false,
        forceReaderFirst: Bool = false,
        hideReaderSidebar: Bool = false,
        useMonochromeDefaultTheme: Bool = false,
        showCloseButton: Bool = true,
        onClose: @escaping () -> Void
    ) {
        self.url = url
        self.forceAISummary = forceAISummary
        self.forceReaderFirst = forceReaderFirst
        self.hideReaderSidebar = hideReaderSidebar
        self.useMonochromeDefaultTheme = useMonochromeDefaultTheme
        self.showCloseButton = showCloseButton
        self.onClose = onClose
        _readerMode = State(initialValue: startInReaderMode)
        _showReaderMask = State(initialValue: startInReaderMode)
    }
    
    var body: some View {
        ZStack {
            // Fond qui couvre TOUT l'écran y compris la titlebar en mode lecteur
            if readerMode {
                GeometryReader { _ in
                    readerBackgroundColor
                }
                .ignoresSafeArea(.container, edges: .all)
            }
            
            WebViewWrapper(webView: webView, url: url, onPageLoad: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if readerMode && !readerAICompleted {
                        showReaderMask = true
                        if forceClassicReaderOnNextLoad {
                            forceClassicReaderOnNextLoad = false
                            applyReader()
                        } else if forceAISummary {
                            Task { await applyReaderAI() }
                        } else if forceReaderFirst || openArticleInReaderFirst {
                            applyReader()
                        } else {
                            Task { await applyReaderAI() }
                        }
                    }
                    NotificationCenter.default.post(name: Notification.Name("OpenWebViewOverlay"), object: nil)
                }
                Task {
                    if reduceOverlaysEnabled {
                        await cleanupOverlaysIfEnabled()
                    }
                    await enforceYouTubeThemeFromAppAppearance()
                    let evaluated = try? await evaluateJavaScript("document.title || ''") as? String
                    await MainActor.run {
                        self.pageTitle = (evaluated ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }, onAction: { action in
                switch action {
                case .shareX:
                    postXError = nil
                    isPostingToX = true
                    Task { await generateAndOpenXComposer() }
                case .summarizeAI:
                    triggerReaderAISummary()
                case .openOriginalArticle:
                    NSWorkspace.shared.open(url)
                case .addNote(let selectedText):
                    saveSelectedReaderNote(selectedText)
                }
            })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(showReaderMask ? 0 : 1)

            // Indicateur de chargement centré pendant la génération IA
            if showReaderMask && readerMode {
                VStack(spacing: 16) {
                    CrystallineRefractionLoader(tint: readerMaskTint)
                        .frame(width: 84, height: 84)
                    Text(isApplyingReaderAI ? LocalizationManager.shared.localizedString(.aiCreatingSummary) : "Chargement du mode lecteur…")
                        .font(.callout)
                        .foregroundStyle(readerMaskTextColor)
                    if !readerPhrases.isEmpty {
                        let phrase = readerPhrases[readerPhraseIndex % readerPhrases.count]
                        Text(phrase)
                            .font(.callout)
                            .foregroundStyle(readerMaskTextColor.opacity(isLightReaderTheme ? 0.6 : 0.7))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if shouldUseFloatingReaderControls {
                classicReaderSummaryFloatingButton
                    .fixedSize()
            }
        }
        .overlay(alignment: .topTrailing) {
            if shouldUseFullscreenCustomPill {
                compactReaderToolbarPill
                    .fixedSize()
                    .padding(.top, 12)
                    .padding(.trailing, 16)
            }
        }
        .onReceive(readerTicker) { _ in
            if showReaderMask && !readerPhrases.isEmpty {
                readerPhraseIndex = (readerPhraseIndex + 1) % readerPhrases.count
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if shouldUseFloatingReaderControls {
                    compactReaderToolbarPill
                        .fixedSize()
                } else {
                    // Theme selector (only in reader mode)
                    if readerMode && !showReaderMask {
                        HStack(spacing: 10) {
                            themeDot(color: Color(red: 0.97, green: 0.95, blue: 0.89), selected: readerTheme == .sepia) {
                                setTheme(.sepia)
                            }
                            themeDot(color: Color(red: 0.96, green: 0.97, blue: 0.99), selected: readerTheme == .paper) {
                                setTheme(.paper)
                            }
                            themeDot(color: Color(red: 0.93, green: 0.96, blue: 0.93), selected: readerTheme == .sage) {
                                setTheme(.sage)
                            }
                            themeDot(color: Color(white: 0.25), selected: readerTheme == .grey) {
                                setTheme(.grey)
                            }
                            themeDot(color: Color(white: 0.07), selected: readerTheme == .dark) {
                                setTheme(.dark)
                            }
                        }
                        .padding(.leading, 24)
                        .padding(.trailing, 4)
                        HStack(spacing: 10) {
                            fontChip(label: "Serif", font: "Times New Roman", selected: readerFont == .serif) {
                                setFont(.serif)
                            }
                            fontChip(label: "Sans Serif", font: "Helvetica Neue", selected: readerFont == .sans) {
                                setFont(.sans)
                            }
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, 20)
                    }

                    Button(action: { NSWorkspace.shared.open(url) }) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .help(lm.localizedString(.helpOpenInBrowser))

                    Button(action: {
                        postXError = nil
                        isPostingToX = true
                        Task { await generateAndOpenXComposer() }
                    }) {
                        ZStack {
                            Image(systemName: "square.and.pencil").opacity(isPostingToX ? 0 : 1)
                            if isPostingToX { ProgressView().controlSize(.small) }
                        }
                    }
                    .help(lm.localizedString(.helpPostOnX))
                    .disabled(isPostingToX)

                    if showCloseButton {
                        Button(action: {
                            Task {
                                await prepareWebViewForClosure()
                                NotificationCenter.default.post(name: .expandSidebar, object: nil)
                                onClose()
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .help(lm.localizedString(.helpCloseWindow))
                    }
                }
            }
        }
        .toolbar(removing: .sidebarToggle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbarVisibility(shouldUseFullscreenCustomPill ? .hidden : .automatic, for: .windowToolbar)
        .toolbarColorScheme(readerMode ? (isLightReaderTheme ? .light : .dark) : nil, for: .windowToolbar)
        .alert(lm.localizedString(.errorX), isPresented: Binding<Bool>(
            get: { postXError != nil },
            set: { if !$0 { postXError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(postXError ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeWebViewOverlay)) { _ in
            Task { await prepareWebViewForClosure() }
        }
        .onDisappear {
            Task { await prepareWebViewForClosure() }
        }
        .onChange(of: colorScheme) { _, _ in
            Task { await enforceYouTubeThemeFromAppAppearance() }
        }
        .onChange(of: shouldUseFloatingReaderControls) { _, newValue in
            if !newValue {
                isClassicReaderOptionsExpanded = false
            }
        }
        .onAppear {
            // Définir le thème du lecteur en fonction du mode clair/sombre de l'app
            readerTheme = colorScheme == .dark ? .dark : .paper
            isWindowFullScreen = (NSApplication.shared.keyWindow?.styleMask.contains(.fullScreen) == true)
            if !showCloseButton {
                NotificationCenter.default.post(name: Notification.Name("ExpandSidebar"), object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isWindowFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isWindowFullScreen = false
        }
    }

    @MainActor
    private func triggerReaderAISummary() {
        if showCloseButton {
            NotificationCenter.default.post(name: Notification.Name("CollapseSidebar"), object: nil)
        }
        guard !isApplyingReaderAI else { return }
        forceClassicReaderOnNextLoad = false
        readerAIAutoRetryCount = 0
        readerAICompleted = false
        isShowingAISummary = false
        showReaderMask = true
        readerFallbackTriggered = false
        Task { await applyReaderAI() }
    }

    @MainActor
    private func triggerClassicReaderFromCurrentArticle() {
        if showCloseButton {
            NotificationCenter.default.post(name: Notification.Name("CollapseSidebar"), object: nil)
        }
        guard !isApplyingReaderAI else { return }
        readerTimeoutTask?.cancel()
        forceClassicReaderOnNextLoad = true
        readerAIAutoRetryCount = 0
        isShowingAISummary = false
        readerAICompleted = false
        readerFallbackTriggered = false
        showReaderMask = true
        webView.load(URLRequest(url: url))
    }

    private func scheduleReaderAIAutoRetryIfNeeded(reason: String) -> Bool {
        guard readerAIAutoRetryCount < 1 else { return false }
        readerAIAutoRetryCount += 1
        appLogWarning("[ReaderAI] first attempt failed (\(reason)) -> auto retry \(readerAIAutoRetryCount)/1")
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await applyReaderAI()
        }
        return true
    }

    @ViewBuilder
    private var compactReaderToolbarPill: some View {
        HStack(spacing: 0) {
            Button(action: {
                isClassicReaderOptionsExpanded.toggle()
            }) {
                Image(systemName: "eyeglasses")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(floatingReaderControlForeground)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Afficher les options du lecteur")
            .popover(isPresented: $isClassicReaderOptionsExpanded, arrowEdge: .top) {
                classicReaderControlsPopover
            }

            compactReaderToolbarPillSeparator

            Button(action: { NSWorkspace.shared.open(url) }) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(floatingReaderControlForeground)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(lm.localizedString(.helpOpenInBrowser))

            compactReaderToolbarPillSeparator

            Button(action: {
                guard !isPostingToX else { return }
                postXError = nil
                isPostingToX = true
                Task { await generateAndOpenXComposer() }
            }) {
                ZStack {
                    Image(systemName: "square.and.pencil")
                        .opacity(isPostingToX ? 0 : 1)
                    if isPostingToX {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(floatingReaderControlForeground)
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(lm.localizedString(.helpPostOnX))
            .disabled(isPostingToX)
            .opacity(isPostingToX ? 0.6 : 1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(floatingReaderControlForeground.opacity(0.16), lineWidth: 1)
        )
        .contentShape(Capsule())
        .fixedSize()
    }

    @ViewBuilder
    private var compactReaderToolbarPillSeparator: some View {
        Rectangle()
            .fill(floatingReaderControlForeground.opacity(0.16))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var classicReaderExpandedControls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                themeDot(color: Color(red: 0.97, green: 0.95, blue: 0.89), selected: readerTheme == .sepia) {
                    setTheme(.sepia)
                }
                themeDot(color: Color(red: 0.96, green: 0.97, blue: 0.99), selected: readerTheme == .paper) {
                    setTheme(.paper)
                }
                themeDot(color: Color(red: 0.93, green: 0.96, blue: 0.93), selected: readerTheme == .sage) {
                    setTheme(.sage)
                }
                themeDot(color: Color(white: 0.25), selected: readerTheme == .grey) {
                    setTheme(.grey)
                }
                themeDot(color: Color(white: 0.07), selected: readerTheme == .dark) {
                    setTheme(.dark)
                }
            }

            HStack(spacing: 10) {
                fontChip(label: "Serif", font: "Times New Roman", selected: readerFont == .serif) {
                    setFont(.serif)
                }
                fontChip(label: "Sans Serif", font: "Helvetica Neue", selected: readerFont == .sans) {
                    setFont(.sans)
                }
            }

            Button(action: { NSWorkspace.shared.open(url) }) {
                Image(systemName: "arrow.up.right.square")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(lm.localizedString(.helpOpenInBrowser))

            Button(action: {
                guard !isPostingToX else { return }
                postXError = nil
                isPostingToX = true
                Task { await generateAndOpenXComposer() }
            }) {
                ZStack {
                    Image(systemName: "square.and.pencil").opacity(isPostingToX ? 0 : 1)
                    if isPostingToX { ProgressView().controlSize(.small) }
                }
                .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(lm.localizedString(.helpPostOnX))
            .disabled(isPostingToX)
            .opacity(isPostingToX ? 0.55 : 1)
        }
    }

    @ViewBuilder
    private var classicReaderControlsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Options lecteur")
                .font(.subheadline.weight(.semibold))
            classicReaderExpandedControls
        }
        .padding(14)
        .frame(minWidth: 360, alignment: .leading)
    }

    @ViewBuilder
    private var classicReaderSummaryFloatingButton: some View {
        Button(action: {
            guard !isApplyingReaderAI else { return }
            if isShowingAISummary {
                triggerClassicReaderFromCurrentArticle()
            } else {
                triggerReaderAISummary()
            }
        }) {
            ZStack {
                if isApplyingReaderAI {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if isShowingAISummary {
                    Image(systemName: "doc.text")
                        .font(.system(size: 16, weight: .semibold))
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .contentShape(Circle())
            .glassEffect(.regular.tint(.blue), in: Circle())
        }
        .buttonStyle(.plain)
        .help(isShowingAISummary ? "Revenir au lecteur" : "Générer un résumé IA dans le lecteur")
        .opacity(isApplyingReaderAI ? 0.8 : 1)
        .padding(.trailing, 18)
        .padding(.bottom, 18)
        .zIndex(10)
    }

    // Couleur de fond du mode lecteur selon le thème
    private var readerBackgroundColor: Color {
        if useMonochromeDefaultTheme {
            switch readerTheme {
            case .paper:
                return .white
            case .dark:
                return .black
            default:
                break
            }
        }
        switch readerTheme {
        case .sepia:
            return Color(red: 0.969, green: 0.945, blue: 0.890) // #F7F1E3
        case .paper:
            return Color(red: 0.961, green: 0.969, blue: 0.984) // #F5F7FB
        case .sage:
            return Color(red: 0.933, green: 0.961, blue: 0.937) // #EEF5EF
        case .grey:
            return Color(white: 0.122) // #1f1f1f
        case .dark:
            return Color(white: 0.067) // #111
        }
    }

    private var isLightReaderTheme: Bool {
        switch readerTheme {
        case .sepia, .paper, .sage:
            return true
        case .grey, .dark:
            return false
        }
    }

    private var readerMaskTint: Color {
        switch readerTheme {
        case .sepia:
            return .brown
        case .paper:
            return Color(red: 0.24, green: 0.29, blue: 0.36)
        case .sage:
            return Color(red: 0.20, green: 0.32, blue: 0.23)
        case .grey, .dark:
            return .white
        }
    }

    private var readerMaskTextColor: Color {
        isLightReaderTheme ? Color(red: 0.22, green: 0.21, blue: 0.20) : .white.opacity(0.8)
    }

    @ViewBuilder
    private func themeDot(color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color)
                if selected {
                    Circle().stroke(Color.accentColor, lineWidth: 2)
                } else {
                    Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                }
            }
            .frame(width: 18, height: 18)
            .help(lm.localizedString(.helpReaderTheme))
        }
        .buttonStyle(.plain)
    }

    private func setTheme(_ theme: ReaderTheme) {
        readerTheme = theme
        // Réappliquer le style si on est déjà en mode lecteur
        if readerMode {
            let css = readerCSS(hideSidebar: hideReaderSidebar && !isShowingAISummary)
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ")
            // Remplacer le contenu du premier tag <style> existant ou en créer un nouveau
            let js = """
            (function(){
                var styles = document.querySelectorAll('style');
                if(styles.length > 0) {
                    styles[0].innerHTML = "\(css)";
                } else {
                    var st = document.createElement('style');
                    st.innerHTML = "\(css)";
                    document.head.appendChild(st);
                }
            })();
            """
            Task { try? await webView.evaluateJavaScript(js) }
        }
    }

    private func setFont(_ font: ReaderFont) {
        readerFont = font
        if readerMode {
            let css = readerCSS(hideSidebar: hideReaderSidebar && !isShowingAISummary)
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ")
            let js = """
            (function(){
                var styles = document.querySelectorAll('style');
                if(styles.length > 0) {
                    styles[0].innerHTML = "\(css)";
                } else {
                    var st = document.createElement('style');
                    st.innerHTML = "\(css)";
                    document.head.appendChild(st);
                }
            })();
            """
            Task { try? await webView.evaluateJavaScript(js) }
        }
    }

    private func readerCSS(hideSidebar: Bool? = nil) -> String {
        // Layout avec sidebar fixe à droite
        let layout = """
        /* Container centré avec réserve d'espace pour la sidebar fixe */
        .reader-outer{width:100%;}
        .reader-container{position:relative;max-width:1200px;margin:0 auto;padding:72px 316px 40px 24px;box-sizing:border-box}
        /* Colonne de lecture limitée et centrée naturellement dans l'espace restant */
        .reader{max-width:760px;width:100%;font:18px -apple-system,system-ui,sans-serif;line-height:1.7;text-align:left;margin:-14px auto 0}
        /* Cartes Résumé + À retenir */
        .reader-section{position:relative;width:100%;margin:22px 0;padding:18px 20px;border-radius:18px;border:1px solid;box-sizing:border-box}
        .reader-section-title{margin:0 0 12px;font-size:12px;letter-spacing:0.1em;text-transform:uppercase;font-weight:700}
        .reader-section .scramble-target > *:first-child{margin-top:0}
        .reader-section .scramble-target > *:last-child{margin-bottom:0}
        .reader-summary{padding-left:20px}
        .reader-summary strong,.reader-summary b{font-weight:400}
        .reader-takeaways{padding-left:20px}
        .reader-takeaways ul{margin:6px 0 0;padding-left:20px}
        .reader-takeaways li{margin:0 0 8px}
        .reader-takeaways li:last-child{margin-bottom:0}
        /* Sidebar fixe à droite - style liquid glass */
        .reader-sidebar{width:260px;position:fixed;top:72px;right:max(24px, calc((100vw - 1200px) / 2 + 24px));max-height:calc(100vh - 96px);padding:16px;border-radius:16px;font:14px -apple-system,system-ui,sans-serif;box-sizing:border-box;overflow:auto;-webkit-backdrop-filter:blur(20px) saturate(180%);backdrop-filter:blur(20px) saturate(180%);border:1px solid rgba(255,255,255,0.18);box-shadow:0 8px 32px rgba(0,0,0,0.08)}
        /* Typo et médias */
        .reader h1{font-size:32px;line-height:1.2;margin:0 0 16px}
        .reader img{max-width:100%;height:auto;border-radius:16px;display:block;margin:16px auto;box-shadow:0 4px 20px rgba(0,0,0,0.12)}
        .reader a{color:inherit !important;text-decoration:underline}
        .reader a:visited{color:inherit !important}
        /* Sidebar contenus */
        .reader-sidebar h4{font-size:10px;text-transform:uppercase;letter-spacing:0.5px;margin:0 0 8px;opacity:0.5;font-weight:600}
        .reader-sidebar .source{font-size:14px;font-weight:600;margin-bottom:16px;word-break:break-word}
        .reader-sidebar .entity{display:flex;align-items:flex-start;gap:6px;margin-bottom:6px;font-size:12px}
        .reader-sidebar .entity-icon{font-size:13px;opacity:0.7;flex-shrink:0}
        .reader-sidebar .entity-name{line-height:1.3}
        .reader-sidebar .entity-type{font-size:10px;opacity:0.5}
        .reader-sidebar .tags{display:flex;flex-wrap:wrap;gap:5px;margin-top:12px}
        .reader-sidebar .tag{display:inline-block;padding:3px 8px;border-radius:999px;font-size:11px}
        .reader-sidebar .ai-disclaimer-section{margin-top:4px;padding-top:10px;border-top:1px solid rgba(255,255,255,0.18)}
        .reader-sidebar .ai-disclaimer{margin:0;font-size:11px;line-height:1.45;opacity:0.78}
        .reader-sidebar .x-btn,.reader-sidebar .ai-btn,.reader-sidebar .origin-btn{display:flex;align-items:center;gap:6px;margin-top:16px;padding:8px 10px;border-radius:8px;font-size:11px;font-weight:500;text-decoration:none !important;cursor:pointer;border:none;box-sizing:border-box;justify-content:center;width:100%;max-width:100%}
        .reader-sidebar .origin-btn{margin-top:10px}
        .reader-sidebar .ai-btn{margin-top:8px}
        .reader-sidebar .x-btn svg{flex-shrink:0;width:14px;height:14px}
        .reader-sidebar .section{margin-bottom:16px}
        /* Image Slider */
        .reader-slider-wrapper{position:relative;width:100%;margin:28px 0 24px;border-radius:16px;overflow:hidden;box-shadow:0 4px 20px rgba(0,0,0,0.12)}
        .reader-slider{position:relative;width:100%;transition:height 0.35s cubic-bezier(0.4,0,0.2,1)}
        .reader-slider-track{display:flex;transition:transform 0.35s cubic-bezier(0.4,0,0.2,1);align-items:flex-start}
        .reader-slider-slide{flex:0 0 100%;width:100%;opacity:0.4;transition:opacity 0.35s ease}
        .reader-slider-slide.active{opacity:1}
        .reader-slider-slide img{width:100%;height:auto;display:block;margin:0;border-radius:0;box-shadow:none}
        .reader-slider-btn{position:absolute;top:50%;transform:translateY(-50%);width:40px;height:40px;border:none;border-radius:50%;cursor:pointer;display:flex;align-items:center;justify-content:center;opacity:0.85;transition:opacity 0.2s,transform 0.2s;z-index:2}
        .reader-slider-btn:hover{opacity:1;transform:translateY(-50%) scale(1.08)}
        .reader-slider-btn:active{transform:translateY(-50%) scale(0.95)}
        .reader-slider-btn.prev{left:12px}
        .reader-slider-btn.next{right:12px}
        .reader-slider-btn svg{width:20px;height:20px}
        .reader-slider-dots{display:flex;justify-content:center;gap:6px;margin-top:12px}
        .reader-slider-dot{width:8px;height:8px;border-radius:50%;cursor:pointer;transition:transform 0.2s,opacity 0.2s;opacity:0.4}
        .reader-slider-dot.active{opacity:1;transform:scale(1.2)}
        .reader-slider-dot:hover{opacity:0.8}
        .reader-slider-counter{position:absolute;bottom:12px;right:12px;padding:4px 10px;border-radius:12px;font-size:12px;font-weight:500;z-index:2}
        /* Responsive: pile en colonne et garde le centrage */
        @media(max-width:900px){
          .reader-container{padding:60px 16px 40px}
          .reader{max-width:760px}
          .reader-sidebar{width:100%;position:static;top:auto;right:auto;max-height:none;overflow:visible;margin-top:24px}
          .reader-slider-btn{width:36px;height:36px}
          .reader-slider-btn.prev{left:8px}
          .reader-slider-btn.next{right:8px}
        }
        """
        let shouldHideSidebar = hideSidebar ?? hideReaderSidebar
        let noSidebarOverride: String = shouldHideSidebar ? """
        .reader-container{display:block;max-width:820px;margin:0 auto;padding:36px 24px 40px;box-sizing:border-box}
        .reader{max-width:760px;width:100%;margin:-14px auto 0;display:block}
        .reader-sidebar{display:none !important}
        @media(max-width:900px){
          .reader-container{padding:34px 16px 40px}
          .reader{max-width:760px}
        }
        """ : ""
        let (bgColor, textColor, sidebarBg, tagBg, xBtnBg) = themeColors()
        let fontFamily = readerFont == .serif
            ? "Georgia,'Times New Roman',serif"
            : "-apple-system,system-ui,Helvetica,Arial,sans-serif"
        let themeBase = "body{background:\(bgColor);margin:0;color:\(textColor);font:18px \(fontFamily)}"
        let fontStyle = ".reader{font-family:\(fontFamily)}"
        let sidebarStyle = ".reader-sidebar{background:\(sidebarBg)} .reader-sidebar .tag{background:\(tagBg)} .reader-sidebar .x-btn,.reader-sidebar .ai-btn,.reader-sidebar .origin-btn{background:\(xBtnBg);color:\(textColor)}"
        let (summaryBg, takeawaysBg, sectionBorder, _, _, sectionTitleColor, _) = sectionCardColors()
        let summaryHighlightBg = summaryHighlightBackground()
        let sectionStyle = """
        .reader-section{border-color:\(sectionBorder)}
        .reader-section-title{color:\(sectionTitleColor)}
        .reader-summary{background:\(summaryBg)}
        .reader-summary strong,.reader-summary b{background:transparent;color:inherit}
        .reader-summary .reader-highlight{font-weight:400;color:inherit;padding:0 1px;border-radius:2px;box-decoration-break:clone;-webkit-box-decoration-break:clone;background:linear-gradient(to bottom, transparent 0%, transparent 42%, \(summaryHighlightBg) 42%, \(summaryHighlightBg) 88%, transparent 88%, transparent 100%)}
        .reader-note-highlight{color:inherit;padding:0 2px;border-radius:4px;box-decoration-break:clone;-webkit-box-decoration-break:clone;background:linear-gradient(to bottom, transparent 0%, transparent 28%, \(summaryHighlightBg) 28%, \(summaryHighlightBg) 100%)}
        .reader-note-action{position:fixed;z-index:9999;display:flex;align-items:center;gap:8px;padding:10px 14px;border-radius:999px;font:600 12px -apple-system,system-ui,sans-serif;border:1px solid \(sectionBorder);background:\(sidebarBg);color:\(textColor);box-shadow:0 14px 40px rgba(0,0,0,0.16);cursor:pointer;opacity:0;pointer-events:none;transform:translateY(6px);transition:opacity 0.16s ease,transform 0.16s ease}
        .reader-note-action.is-visible{opacity:1;pointer-events:auto;transform:translateY(0)}
        .reader-note-action:focus{outline:none}
        .reader-takeaways{background:\(takeawaysBg)}
        """
        // Slider theme colors
        let (sliderBtnBg, sliderBtnColor, sliderBtnShadow, sliderDotBg, sliderCounterBg, sliderCounterColor) = sliderColors()
        let sliderStyle = ".reader-slider-btn{background:\(sliderBtnBg);color:\(sliderBtnColor);box-shadow:\(sliderBtnShadow)} .reader-slider-btn svg{fill:\(sliderBtnColor)} .reader-slider-dot{background:\(sliderDotBg)} .reader-slider-counter{background:\(sliderCounterBg);color:\(sliderCounterColor);box-shadow:\(sliderBtnShadow)}"
        return themeBase + layout + noSidebarOverride + fontStyle + sidebarStyle + sectionStyle + sliderStyle
    }

    @ViewBuilder
    private func fontChip(label: String, font: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("T")
                .font(.custom(font, size: 18).weight(.semibold))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .accessibilityLabel(Text(label))
        }
        .buttonStyle(.plain)
        .help(label)
    }
    
    /// Génère le HTML du slider d'images pour le mode lecteur
    private func buildImageSliderHTML(images: [String]) -> String {
        guard !images.isEmpty else { return "" }
        
        // Si une seule image, afficher simplement sans slider
        if images.count == 1 {
            return "<img src=\"\(images[0])\" alt=\"\" loading=\"lazy\" style=\"margin-top:28px;border-radius:16px;box-shadow:0 4px 20px rgba(0,0,0,0.12);\"/>"
        }
        
        // Générer les slides
        let slidesHTML = images.enumerated().map { index, url in
            "<div class=\"reader-slider-slide\(index == 0 ? " active" : "")\"><img src=\"\(url)\" alt=\"\" loading=\"lazy\"/></div>"
        }.joined()
        
        // Générer les points indicateurs
        let dotsHTML = images.enumerated().map { index, _ in
            "<span class=\"reader-slider-dot\(index == 0 ? " active" : "")\" data-index=\"\(index)\"></span>"
        }.joined()
        
        // Flèches SVG
        let prevArrow = "<svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><polyline points=\"15 18 9 12 15 6\"></polyline></svg>"
        let nextArrow = "<svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><polyline points=\"9 18 15 12 9 6\"></polyline></svg>"
        
        // JavaScript pour la navigation
        let sliderJS = """
        <script>
        (function(){
          var wrapper = document.querySelector('.reader-slider-wrapper');
          if(!wrapper) return;
          var slider = wrapper.querySelector('.reader-slider');
          var track = wrapper.querySelector('.reader-slider-track');
          var slides = wrapper.querySelectorAll('.reader-slider-slide');
          var imgs = wrapper.querySelectorAll('.reader-slider-slide img');
          var dots = document.querySelectorAll('.reader-slider-dots .reader-slider-dot');
          var counter = wrapper.querySelector('.reader-slider-counter');
          var prevBtn = wrapper.querySelector('.reader-slider-btn.prev');
          var nextBtn = wrapper.querySelector('.reader-slider-btn.next');
          var current = 0;
          var total = slides.length;
          
          // Mettre à jour la hauteur du slider selon l'image active
          function updateHeight() {
            var img = imgs[current];
            if(img && img.complete && img.naturalHeight > 0) {
              slider.style.height = img.offsetHeight + 'px';
            }
          }
          
          function goTo(index) {
            if(index < 0) index = total - 1;
            if(index >= total) index = 0;
            current = index;
            track.style.transform = 'translateX(-' + (current * 100) + '%)';
            slides.forEach(function(s, i) {
              s.classList.toggle('active', i === current);
            });
            dots.forEach(function(d, i) {
              d.classList.toggle('active', i === current);
            });
            if(counter) counter.textContent = (current + 1) + ' / ' + total;
            updateHeight();
          }
          
          // Initialiser: premier slide actif
          slides[0].classList.add('active');
          
          // Auto-avance vers la 2e image après 3 secondes (une seule fois)
          var autoAdvanceTimer = null;
          if(total > 1) {
            autoAdvanceTimer = setTimeout(function() {
              if(current === 0) goTo(1);
            }, 3000);
          }
          
          // Annuler l'auto-avance si interaction manuelle
          function cancelAutoAdvance() {
            if(autoAdvanceTimer) {
              clearTimeout(autoAdvanceTimer);
              autoAdvanceTimer = null;
            }
          }
          
          // Écouter le chargement des images pour ajuster la hauteur
          imgs.forEach(function(img, i) {
            if(img.complete) {
              if(i === 0) updateHeight();
            } else {
              img.addEventListener('load', function() {
                if(i === current) updateHeight();
              });
            }
          });
          
          // Ajuster la hauteur au redimensionnement
          window.addEventListener('resize', updateHeight);
          
          if(prevBtn) prevBtn.addEventListener('click', function(e) { e.preventDefault(); cancelAutoAdvance(); goTo(current - 1); });
          if(nextBtn) nextBtn.addEventListener('click', function(e) { e.preventDefault(); cancelAutoAdvance(); goTo(current + 1); });
          dots.forEach(function(dot) {
            dot.addEventListener('click', function() {
              cancelAutoAdvance();
              goTo(parseInt(this.getAttribute('data-index'), 10));
            });
          });
          
          // Support clavier
          document.addEventListener('keydown', function(e) {
            if(e.key === 'ArrowLeft') { cancelAutoAdvance(); goTo(current - 1); }
            if(e.key === 'ArrowRight') { cancelAutoAdvance(); goTo(current + 1); }
          });
          
          // Support swipe tactile
          var startX = 0;
          slider.addEventListener('touchstart', function(e) { startX = e.touches[0].clientX; cancelAutoAdvance(); }, {passive: true});
          slider.addEventListener('touchend', function(e) {
            var diff = startX - e.changedTouches[0].clientX;
            if(Math.abs(diff) > 50) {
              if(diff > 0) goTo(current + 1);
              else goTo(current - 1);
            }
          }, {passive: true});
        })();
        </script>
        """
        
        return """
        <div class="reader-slider-wrapper">
          <div class="reader-slider">
            <div class="reader-slider-track">\(slidesHTML)</div>
          </div>
          <button class="reader-slider-btn prev" aria-label="Image précédente">\(prevArrow)</button>
          <button class="reader-slider-btn next" aria-label="Image suivante">\(nextArrow)</button>
          <span class="reader-slider-counter">1 / \(images.count)</span>
        </div>
        <div class="reader-slider-dots">\(dotsHTML)</div>
        \(sliderJS)
        """
    }

    private func themeColors() -> (bg: String, text: String, sidebarBg: String, tagBg: String, xBtnBg: String) {
        if useMonochromeDefaultTheme {
            switch readerTheme {
            case .paper:
                return ("#FFFFFF", "#111111", "rgba(255,255,255,0.75)", "rgba(0,0,0,0.06)", "rgba(0,0,0,0.06)")
            case .dark:
                return ("#000000", "#EFEFEF", "rgba(18,18,18,0.75)", "rgba(255,255,255,0.08)", "rgba(255,255,255,0.08)")
            default:
                break
            }
        }
        switch readerTheme {
        case .sepia:
            // Liquid glass style pour le thème sépia
            return ("#F7F1E3", "#3a2f2a", "rgba(247,241,227,0.65)", "rgba(0,0,0,0.06)", "rgba(0,0,0,0.06)")
        case .paper:
            // Papier froid et net
            return ("#F5F7FB", "#2B3440", "rgba(245,247,251,0.7)", "rgba(43,52,64,0.08)", "rgba(43,52,64,0.06)")
        case .sage:
            // Vert doux, confortable à la lecture
            return ("#EEF5EF", "#2E3B32", "rgba(238,245,239,0.7)", "rgba(46,59,50,0.08)", "rgba(46,59,50,0.06)")
        case .grey:
            // Liquid glass style pour le thème gris
            return ("#1f1f1f", "#e0e0e0", "rgba(45,45,45,0.65)", "rgba(255,255,255,0.08)", "rgba(255,255,255,0.08)")
        case .dark:
            // Liquid glass style pour le thème sombre
            return ("#111", "#e6e6e6", "rgba(30,30,30,0.65)", "rgba(255,255,255,0.06)", "rgba(255,255,255,0.06)")
        }
    }

    private func sliderColors() -> (btnBg: String, btnColor: String, btnShadow: String, dotBg: String, counterBg: String, counterColor: String) {
        switch readerTheme {
        case .sepia:
            return ("rgba(60,50,40,0.85)", "#fff", "0 2px 8px rgba(0,0,0,0.3)", "#5a4a3a", "rgba(60,50,40,0.8)", "#fff")
        case .paper:
            return ("rgba(43,52,64,0.18)", "#2B3440", "0 2px 8px rgba(0,0,0,0.15)", "rgba(43,52,64,0.35)", "rgba(43,52,64,0.12)", "#2B3440")
        case .sage:
            return ("rgba(46,59,50,0.2)", "#2E3B32", "0 2px 8px rgba(0,0,0,0.16)", "rgba(46,59,50,0.35)", "rgba(46,59,50,0.12)", "#2E3B32")
        case .grey, .dark:
            return ("rgba(255,255,255,0.2)", "#fff", "0 2px 8px rgba(0,0,0,0.4)", "#e0e0e0", "rgba(255,255,255,0.2)", "#e0e0e0")
        }
    }

    private func sectionCardColors() -> (summaryBg: String, takeawaysBg: String, border: String, summaryAccent: String, takeawaysAccent: String, title: String, strongBg: String) {
        switch readerTheme {
        case .sepia:
            return ("rgba(255,248,232,0.88)", "rgba(248,238,223,0.84)", "rgba(107,84,63,0.22)", "#AD7A45", "#8F6439", "#5A4634", "rgba(173,122,69,0.16)")
        case .paper:
            return ("rgba(255,255,255,0.88)", "rgba(243,248,255,0.88)", "rgba(43,52,64,0.14)", "#3E6DA8", "#2D7A8C", "#2B3440", "rgba(62,109,168,0.14)")
        case .sage:
            return ("rgba(245,251,245,0.88)", "rgba(236,246,238,0.88)", "rgba(46,59,50,0.16)", "#3C7A60", "#5F7C43", "#2E3B32", "rgba(60,122,96,0.16)")
        case .grey:
            return ("rgba(56,56,56,0.82)", "rgba(52,52,52,0.82)", "rgba(255,255,255,0.14)", "#B9D6FF", "#B7E0C9", "#EFEFEF", "rgba(185,214,255,0.2)")
        case .dark:
            return ("rgba(35,35,35,0.84)", "rgba(29,29,29,0.86)", "rgba(255,255,255,0.12)", "#8CB6FF", "#87D8B2", "#F2F2F2", "rgba(140,182,255,0.22)")
        }
    }

    private func summaryHighlightBackground() -> String {
        if useMonochromeDefaultTheme {
            switch readerTheme {
            case .paper:
                return "rgba(255, 224, 92, 0.78)"
            case .dark:
                return "rgba(255, 206, 74, 0.42)"
            default:
                break
            }
        }

        switch readerTheme {
        case .sepia:
            return "rgba(221, 183, 108, 0.62)"
        case .paper:
            return "rgba(255, 224, 77, 0.74)"
        case .sage:
            return "rgba(223, 213, 104, 0.58)"
        case .grey:
            return "rgba(255, 205, 88, 0.38)"
        case .dark:
            return "rgba(255, 196, 56, 0.42)"
        }
    }
    
    // MARK: - Reader Mode
    private func toggleReader() {
        readerMode.toggle()
        if readerMode {
            // Recouvre immédiatement via overlay SwiftUI (pas JS)
            showReaderMask = true
            if forceAISummary {
                Task { await applyReaderAI() }
            } else if forceReaderFirst || openArticleInReaderFirst {
                applyReader()
            } else {
                Task { await applyReaderAI() }
            }
        } else {
            exitReader()
            NotificationCenter.default.post(name: Notification.Name("ExpandSidebar"), object: nil)
        }
    }
    
    // Mode lecteur classique (fallback)
    private func applyReader() {
        let style = readerCSS()
        let openOriginalLabel = localizedOpenOriginalArticleButtonText()
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let sidebarJS: String = hideReaderSidebar ? "var sidebar = '';" : """
                var sourceName = (window.location && window.location.hostname) ? window.location.hostname.replace(/^www\\./,'') : '';
                var sidebar = '<aside class="reader-sidebar">'+
                              '<div class="section"><h4>Source</h4><div class="source">'+sourceName+'</div></div>'+
                              '<button onclick="window.location.href=\\'flux-action://open-original\\'" class="origin-btn"><span>\(openOriginalLabel)</span></button>'+
                              '<button onclick="window.location.href=\\'flux-action://share-x\\'" class="x-btn"><svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>'+
                              '<span>Partager sur X</span></button>'+
                              '<button onclick="window.location.href=\\'flux-action://summary-ai\\'" class="ai-btn"><span>Résumé (Intelligence artificielle locale)</span></button>'+
                              '</aside>';
                """
        Task { @MainActor in
            isShowingAISummary = false
            print("[Reader] applyReader fallback start url=\(url.absoluteString)")
            await cleanupOverlaysIfEnabled()
            // 1) Injecter Readability local si besoin
            let hasReadability = (try? await evaluateJavaScript("!!window.Readability") as? Bool) ?? false
            print("[Reader] Readability present=\(hasReadability)")
            if !hasReadability {
                if let jsURL = Bundle.main.url(forResource: "Readability", withExtension: "js"),
                   let src = try? String(contentsOf: jsURL, encoding: .utf8) {
                    print("[Reader] Inject Readability from bundle")
                    _ = try? await webView.evaluateJavaScript(src)
                } else {
                    print("[Reader] Readability bundle missing")
                }
                // petite attente pour que le script soit prêt
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            // 2) Appliquer un rendu strict: titre + images utiles + texte (sans bruit parasite)
            let readerJS = """
            (function(){
              try {
                var rd = new Readability(document.cloneNode(true));
                var article = rd.parse();
                if(!article){ return false; }

                function escapeHTML(value){
                  return (value || '')
                    .replace(/&/g, '&amp;')
                    .replace(/</g, '&lt;')
                    .replace(/>/g, '&gt;');
                }

                function normalizeText(value){
                  return (value || '')
                    .replace(/\\r/g, '\\n')
                    .replace(/\\u00A0/g, ' ')
                    .replace(/[ \\t]+/g, ' ')
                    .replace(/\\n{3,}/g, '\\n\\n')
                    .trim();
                }

                function isLikelyNoise(text){
                  var lower = (text || '').toLowerCase().trim();
                  if(!lower) return true;
                  if(/^(advertisement|sponsored|publicite|publicité|newsletter|cookies?|consent|share|partager|follow us|suivez-nous|read more|lire la suite|voir plus|comments?)[:\\s]*$/.test(lower)) return true;
                  if(lower.length <= 220 && /(cookie|consent|newsletter|subscribe|inscrivez-vous|publicite|publicité|sponsor|sponsored|related|recommended|read more|lire aussi|lire la suite|voir aussi|suivez-nous|follow us|share this|partager|comment)/.test(lower)) return true;
                  return false;
                }

                function hasNoiseClassOrId(node){
                  var label = ((node.className || '') + ' ' + (node.id || '') + ' ' + (node.getAttribute('role') || '') + ' ' + (node.getAttribute('aria-label') || '')).toLowerCase();
                  return /(cookie|consent|newsletter|subscribe|paywall|related|recommend|share|social|comment|promo|sponsor|advert|banner|outbrain|taboola|breadcrumb|menu|header|footer|sidebar|toolbar|nav|reaction)/.test(label);
                }

                function removeNoiseNodes(root){
                  var selectors = [
                    'script','style','noscript','iframe','form','button','input','select','textarea',
                    'nav','aside','footer','header',
                    '[role="dialog"]','[role="alertdialog"]','[role="navigation"]','[role="contentinfo"]','[role="banner"]','[role="complementary"]',
                    '.share','.sharing','.social','.newsletter','.cookie','.consent','.paywall','.related','.recommended','.comments','.comment','.ad','.ads','.advert','.promo','.sponsored'
                  ];
                  selectors.forEach(function(sel){
                    root.querySelectorAll(sel).forEach(function(el){ el.remove(); });
                  });
                  root.querySelectorAll('*').forEach(function(el){
                    if(hasNoiseClassOrId(el)){ el.remove(); return; }
                    var t = normalizeText(el.textContent || '');
                    if(t && t.length <= 220 && isLikelyNoise(t)){ el.remove(); }
                  });
                }

                var tmp = document.createElement('div');
                tmp.innerHTML = article.content || '';
                removeNoiseNodes(tmp);

                var images = [];
                var seenImageUrls = {};
                function isValidContentImage(img){
                  if(!img) return false;
                  var src = img.src || img.getAttribute('src') || img.getAttribute('data-src') || img.getAttribute('data-lazy-src') || img.getAttribute('data-original') || '';
                  if(!src || !src.trim()) return false;
                  var lower = src.toLowerCase();
                  if(lower.indexOf('data:image') === 0) return false;
                  if(/(pixel|tracking|analytics|beacon|sprite|avatar|logo|icon|placeholder|thumb)/.test(lower)) return false;
                  var w = parseInt(img.getAttribute('width') || '0', 10);
                  var h = parseInt(img.getAttribute('height') || '0', 10);
                  var nw = img.naturalWidth || 0;
                  var nh = img.naturalHeight || 0;
                  var finalW = nw > 0 ? nw : w;
                  var finalH = nh > 0 ? nh : h;
                  if((finalW > 0 && finalW < 160) || (finalH > 0 && finalH < 120)) return false;
                  var cls = ((img.className || '') + ' ' + (img.id || '') + ' ' + (img.alt || '')).toLowerCase();
                  if(/(logo|icon|avatar|emoji|sprite|tracking|advert|ads?)/.test(cls)) return false;
                  return true;
                }

                function addImageFromNode(img){
                  if(!isValidContentImage(img)) return;
                  var src = img.src || img.getAttribute('src') || img.getAttribute('data-src') || img.getAttribute('data-lazy-src') || img.getAttribute('data-original') || '';
                  if(!src) return;
                  var key = src.trim();
                  if(seenImageUrls[key]) return;
                  seenImageUrls[key] = true;
                  images.push(key);
                }

                var lead = article.lead_image_url || article.image || '';
                if(lead && lead.trim() && !seenImageUrls[lead.trim()]){
                  seenImageUrls[lead.trim()] = true;
                  images.push(lead.trim());
                }

                tmp.querySelectorAll('figure img, picture img, img').forEach(function(img){
                  if(img.closest('nav,aside,footer,header,[role="navigation"],[role="contentinfo"]')) return;
                  addImageFromNode(img);
                });

                if(images.length === 0){
                  var fallbackRootForImages = document.querySelector('article') || document.querySelector('main') || document.body;
                  if(fallbackRootForImages){
                    fallbackRootForImages.querySelectorAll('figure img, picture img, img').forEach(function(img){
                      addImageFromNode(img);
                    });
                  }
                }
                images = images.slice(0, 6);

                var parts = [];
                var seen = {};
                function pushPart(raw){
                  var t = normalizeText(raw);
                  if(!t) return;
                  if(t.length < 40){
                    var words = t.split(/\\s+/).length;
                    if(words < 7) return;
                  }
                  if(t.length > 2000) return;
                  if(isLikelyNoise(t)) return;
                  var key = t.toLowerCase();
                  if(seen[key]) return;
                  seen[key] = true;
                  parts.push(t);
                }

                tmp.querySelectorAll('h2,h3,p,li,blockquote').forEach(function(node){
                  if(node.closest('nav,aside,footer,header,[role="navigation"],[role="contentinfo"],[aria-hidden="true"]')) return;
                  if(node.closest('figure')) return;
                  pushPart(node.textContent || '');
                });

                if(parts.length < 4){
                  normalizeText(article.textContent || '').split(/\\n+/).forEach(function(line){ pushPart(line); });
                }
                if(parts.length < 3){
                  var fallbackRoot = document.querySelector('article') || document.querySelector('main') || document.body;
                  if(fallbackRoot){
                    normalizeText(fallbackRoot.innerText || '').split(/\\n+/).forEach(function(line){ pushPart(line); });
                  }
                }
                if(parts.length === 0){ return false; }

                var bodyHTML = parts.map(function(p){ return '<p>' + escapeHTML(p) + '</p>'; }).join('');
                var imagesHTML = images.map(function(src){ return '<img src="' + src.replace(/"/g, '&quot;') + '" alt="" loading="lazy" />'; }).join('');
                var safeTitle = escapeHTML(article.title || document.title || '');

                \(sidebarJS)
                var html = '<!doctype html><meta charset="utf-8"><style>\(style)</style>'+
                           '<div class="reader-outer"><div class="reader-container">'+
                           '<article class="reader"><h1>'+safeTitle+'</h1>'+imagesHTML+bodyHTML+'</article>'+sidebar+
                           '</div></div>';
                document.open(); document.write(html); document.close();
                try {
                  document.documentElement.style.overflow = 'auto';
                  document.documentElement.style.position = 'static';
                  document.body.style.overflow = 'auto';
                  document.body.style.position = 'static';
                  document.documentElement.classList.remove('modal-open','no-scroll','noscroll','overflow-hidden','is-locked','scroll-lock','scroll-locked','disable-scroll');
                  document.body.classList.remove('modal-open','no-scroll','noscroll','overflow-hidden','is-locked','scroll-lock','scroll-locked','disable-scroll');
                } catch(e){}
                return true;
              } catch (e) { return false; }
            })();
            """
            let ok = (try? await evaluateJavaScript(readerJS) as? Bool) ?? false
            print("[Reader] Readability parse success=\(ok)")
            if !ok {
                let fallbackTitle = (try? await evaluateJavaScript("document.title || ''") as? String) ?? ""
                let fallbackText = (try? await evaluateJavaScript("document.body.innerText || ''") as? String) ?? ""
                let ogImage = (try? await evaluateJavaScript("document.querySelector('meta[property=\"og:image\"],meta[name=\"og:image\"],meta[property=\"twitter:image\"],meta[name=\"twitter:image\"]')?.getAttribute('content') || ''") as? String) ?? ""
                let stored = storedArticleFallback()
                let finalTitle = !fallbackTitle.isEmpty ? fallbackTitle : (stored.title ?? "")
                let finalText = !fallbackText.isEmpty ? fallbackText : (stored.text ?? "")
                let finalImage = !ogImage.isEmpty ? ogImage : (stored.imageURL ?? "")
                print("[Reader] Fallback title len=\(finalTitle.count) text len=\(finalText.count) ogImage=\(!finalImage.isEmpty)")
                let html = buildSimpleReaderHTML(title: finalTitle, text: finalText, lead: finalImage, style: style)
                let okInject = await injectHTML(html)
                print("[Reader] inject html ok=\(okInject)")
                if !okInject {
                    print("[Reader] inject html failed -> loadHTMLString")
                    webView.loadHTMLString(html, baseURL: url)
                }
            }
            showReaderMask = false
        }
    }

    /// Réduit les overlays gênants AVANT l'extraction du contenu (opt-in utilisateur)
    private func cleanupOverlaysIfEnabled() async {
        guard reduceOverlaysEnabled else { return }
        let script = """
        (function(){
          try {
            // Débloquer le scroll si une overlay le bloque
            document.body.style.overflow = 'auto';
            document.body.style.position = 'static';
            document.documentElement.style.overflow = 'auto';
            document.documentElement.style.position = 'static';
            document.documentElement.classList.remove('modal-open', 'no-scroll', 'noscroll', 'overflow-hidden', 'is-locked', 'scroll-lock', 'scroll-locked', 'disable-scroll');
            document.body.classList.remove('modal-open', 'no-scroll', 'noscroll', 'overflow-hidden', 'is-locked', 'scroll-lock', 'scroll-locked', 'disable-scroll');

            // Supprimer les overlays génériques (sans ciblage paywall/consent)
            var selectors = [
              '[role="dialog"]', '[role="alertdialog"]',
              '.modal-backdrop', '.overlay-backdrop', '.overlay', '.modal'
            ];
            selectors.forEach(function(sel){
              document.querySelectorAll(sel).forEach(function(el){
                try {
                  var st = window.getComputedStyle(el);
                  if(st && (st.position==='fixed' || st.position==='sticky' || parseInt(st.zIndex||'0',10)>50)){
                    el.remove();
                  }
                } catch(e){ el.remove(); }
              });
            });

            // Supprimer tout élément fixed/sticky avec z-index élevé
            document.querySelectorAll('body *').forEach(function(el){
              try {
                var st = window.getComputedStyle(el);
                if(!st) return;
                var z = parseInt(st.zIndex || '0', 10);
                if((st.position==='fixed' || st.position==='sticky') && z >= 100){
                  el.remove();
                }
              } catch(e){}
            });
          } catch(e){}
        })();
        """
        _ = try? await evaluateJavaScript(script)
    }

    // Mode lecteur intelligent: nettoie/traduit/résume via intelligence artificielle locale puis injecte
    private func applyReaderAI() async {
        // Empêcher les appels multiples simultanés ou si déjà complété
        guard !isApplyingReaderAI else {
            print("[ReaderAI] already running, skip duplicate call")
            return
        }
        guard !readerAICompleted else {
            print("[ReaderAI] already completed, skip duplicate call")
            return
        }
        isApplyingReaderAI = true
        
        let hapticsEnabled = UserDefaults.standard.object(forKey: "hapticsEnabled") == nil || UserDefaults.standard.bool(forKey: "hapticsEnabled")
        #if os(macOS)
        if hapticsEnabled { HeartbeatHaptic.shared.start() }
        #endif
        
        defer {
            isApplyingReaderAI = false
            #if os(macOS)
            if hapticsEnabled {
                HeartbeatHaptic.shared.stop()
                HapticFeedback.success()
            }
            #endif
        }
        
        // 0) Si on est déjà dans le mode lecteur (HTML injecté), utiliser le texte stocké pour l'IA
        let isReaderDoc = (try? await evaluateJavaScript("!!document.querySelector('.reader-container')") as? Bool) ?? false
        if isReaderDoc {
            let stored = storedArticleFallback()
            let fallbackTitle = stored.title ?? pageTitle
            let fallbackText = stored.text ?? ""
            if !fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run { injectReaderLoadingPlaceholder(title: fallbackTitle, lead: normalizeLeadURL(stored.imageURL)) }
                async let summaryTask = summarizeForReaderHTML(title: fallbackTitle, text: fallbackText)
                async let metadataTask = extractEntitiesAndTags(title: fallbackTitle, text: fallbackText)
                do {
                    let summaryHTML = try await summaryTask
                    let metadata = await metadataTask
                    await MainActor.run {
                        readerEntities = metadata.entities
                        readerTags = metadata.tags
                        readerSourceName = getSourceFeedName()
                    }
                    if summaryHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if scheduleReaderAIAutoRetryIfNeeded(reason: "empty summary from stored article") {
                            return
                        }
                        await MainActor.run { applyReader(); showReaderMask = false }
                        return
                    }
                    let style = readerCSS(hideSidebar: false)
                    let safeTitle = fallbackTitle.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
                    let imgHTML = buildImageSliderHTML(images: normalizeLeadURL(stored.imageURL).map { [$0] } ?? [])
                    let sidebarHTML = buildSidebarHTML(source: getSourceFeedName(), entities: metadata.entities, tags: metadata.tags, articleURL: url.absoluteString, pageTitle: fallbackTitle, showSummaryButton: false)
                    let scrambleScript = scrambleEffectScript()
                    let notesScript = readerNoteSupportScript()
                    let html = "<!doctype html><meta charset=\"utf-8\"><style>\(style)</style><div class=\"reader-outer\"><div class=\"reader-container\"><article class=\"reader\"><h1>\(safeTitle)</h1>\(imgHTML)\(summaryHTML)</article>\(sidebarHTML)</div></div>\(scrambleScript)\(notesScript)"
                    await MainActor.run {
                        webView.loadHTMLString(html, baseURL: url)
                        readerAICompleted = true
                        isShowingAISummary = true
                        readerTimeoutTask?.cancel()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showReaderMask = false
                        }
                    }
                } catch {
                    if scheduleReaderAIAutoRetryIfNeeded(reason: "stored article pipeline error: \(error.localizedDescription)") {
                        return
                    }
                    await MainActor.run { applyReader(); showReaderMask = false }
                }
                return
            }
        }

        // 1) Réduire les overlays gênants AVANT extraction (opt-in)
        await cleanupOverlaysIfEnabled()
        // Attendre un peu pour laisser la page se stabiliser
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        await cleanupOverlaysIfEnabled() // Réessayer au cas où
        
        // 1) Extraire titre/texte/lead via Readability
        do {
            appLog("[ReaderAI] start url=\(url.absoluteString)")
            readerFallbackTriggered = false
            readerTimeoutTask?.cancel()
            readerTimeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 45_000_000_000) // 45 secondes pour laisser le temps à l'intelligence artificielle locale
                guard !Task.isCancelled else { return }
                if showReaderMask {
                    appLogWarning("[ReaderAI] timeout -> fallback applyReader")
                    readerFallbackTriggered = true
                    readerAICompleted = true
                    applyReader()
                    showReaderMask = false
                }
            }
            try await ensureReadabilityInjected()
            appLogDebug("[ReaderAI] Readability injected")
            let article = try await extractArticle()
            appLog("[ReaderAI] extractArticle title len=\(article.title.count) text len=\(article.text.count) lead=\(article.lead ?? "") images=\(article.images.count)")
            let storedImageURL = articleImageURL()
            let preferredLead = storedImageURL ?? article.lead
            
            // Préparer les images pour le slider
            var allImages: [String] = []
            // Ajouter l'image stockée en premier si disponible
            if let stored = storedImageURL, let normalized = normalizeLeadURL(stored) {
                allImages.append(normalized)
            }
            // Ajouter les images extraites de l'article
            for imgURL in article.images {
                if let normalized = normalizeLeadURL(imgURL), !allImages.contains(normalized) {
                    allImages.append(normalized)
                }
            }
            // Limiter à 10 images
            allImages = Array(allImages.prefix(10))
            
            // Mettre à jour le placeholder avec titre/image si dispo (sans attendre encore)
            await MainActor.run { injectReaderLoadingPlaceholder(title: article.title, lead: normalizeLeadURL(preferredLead)) }
            // 2) Appeler l'IA locale (Apple Foundation Models) et extraire les métadonnées en parallèle
            async let summaryTask = summarizeForReaderHTML(title: article.title, text: article.text)
            async let metadataTask = extractEntitiesAndTags(title: article.title, text: article.text)

            let summaryHTML = try await summaryTask
            let metadata = await metadataTask

            // Stocker les métadonnées pour la sidebar
            await MainActor.run {
                readerEntities = metadata.entities
                readerTags = metadata.tags
                readerSourceName = getSourceFeedName()
            }

            appLog("[ReaderAI] summaryHTML len=\(summaryHTML.count) entities=\(metadata.entities.count) tags=\(metadata.tags.count)")
            guard !summaryHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                appLogWarning("[ReaderAI] empty summary -> fallback applyReader")
                readerTimeoutTask?.cancel()
                if scheduleReaderAIAutoRetryIfNeeded(reason: "empty summary") {
                    return
                }
                await MainActor.run { applyReader(); showReaderMask = false }
                return
            }
            if readerFallbackTriggered {
                print("[ReaderAI] fallback already shown -> skip AI inject")
                readerTimeoutTask?.cancel()
                return
            }
            // 3) Construire et injecter le HTML lecteur avec sidebar
            let style = readerCSS(hideSidebar: false)
            let safeTitle = article.title.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            // Utiliser le slider si plusieurs images, sinon image simple
            let imgHTML = buildImageSliderHTML(images: allImages)
            let contentHTML = summaryHTML
            let sidebarHTML = buildSidebarHTML(source: getSourceFeedName(), entities: metadata.entities, tags: metadata.tags, articleURL: url.absoluteString, pageTitle: article.title, showSummaryButton: false)
            // Script pour l'effet scramble sur le texte du résumé
            let scrambleScript = scrambleEffectScript()
            let notesScript = readerNoteSupportScript()
            // Sidebar après le contenu pour qu'elle soit à droite avec flexbox
            let html = "<!doctype html><meta charset=\"utf-8\"><style>\(style)</style><div class=\"reader-outer\"><div class=\"reader-container\"><article class=\"reader\"><h1>\(safeTitle)</h1>\(imgHTML)\(contentHTML)</article>\(sidebarHTML)</div></div>\(scrambleScript)\(notesScript)"
            await MainActor.run {
                // Utiliser loadHTMLString directement (plus fiable que document.write)
                appLog("[ReaderAI] loading reader HTML via loadHTMLString")
                webView.loadHTMLString(html, baseURL: url)
                readerAICompleted = true
                isShowingAISummary = true
                readerTimeoutTask?.cancel()
                // Délai court pour laisser le temps au HTML de se charger avant d'enlever le masque
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showReaderMask = false
                }
            }
        } catch {
            appLogError("[ReaderAI] exception: \(error.localizedDescription)")
            readerTimeoutTask?.cancel()
            if scheduleReaderAIAutoRetryIfNeeded(reason: error.localizedDescription) {
                return
            }
            readerAICompleted = true // Marquer comme complété même en cas d'erreur pour éviter les retentatives
            // En cas d'échec IA/extraction, fallback classique
            await MainActor.run { isShowingAISummary = false; applyReader(); showReaderMask = false }
        }
    }

    private func injectReaderLoadingPlaceholder(title: String, lead: String?) {
        let style = readerCSS() + " .center{display:flex;align-items:center;justify-content:center;margin:24px 0;color:#bdbdbd} .chip{display:inline-block;padding:6px 10px;border-radius:999px;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.15);font-size:12px;color:#d0d0d0} .phrase{font-size:19px;color:#cfcfcf;margin-top:8px}"
        let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        let imgHTML = (lead?.isEmpty == false) ? "<img class=\"lead\" src=\"\(lead!)\" alt=\"\">" : ""
        let js = """
        (function(){
          var html='<!doctype html><meta charset="utf-8"><style>\(style)</style>'+
                   '<div class="reader-outer"><div class="reader-container">'+
                   '<article class="reader">'+
                   '<h1>\(safeTitle)</h1>'+
                   '\(imgHTML)'+
                   '<div class="center"><span class="chip">Mode lecteur IA</span></div>'+
                   '<div class="center" id="phr"><span class="phrase">Je brosse l\'article…</span></div>'+
                   '</article></div></div>';
          document.open(); document.write(html); document.close();
          try {
            document.documentElement.style.overflow = 'auto';
            document.documentElement.style.position = 'static';
            document.body.style.overflow = 'auto';
            document.body.style.position = 'static';
            document.documentElement.classList.remove('modal-open','no-scroll','noscroll','overflow-hidden','is-locked','scroll-lock','scroll-locked','disable-scroll');
            document.body.classList.remove('modal-open','no-scroll','noscroll','overflow-hidden','is-locked','scroll-lock','scroll-locked','disable-scroll');
          } catch(e){}
          var phrases=[
            "Je taille les longueurs…",
            "Je chasse les pubs et je garde l\'essentiel…",
            "Je traduis en français soigné…",
            "Je clarifie l\'intrigue…",
            "Je condense sans trahir…",
            "Je polie les tournures…",
            "Je coupe les cookies (pas les bons)…",
            "Je range les idées dans l\'ordre…"
          ];
          var i=0; setInterval(function(){
            var el=document.getElementById('phr'); if(!el) return;
            i=(i+1)%phrases.length;
            el.innerHTML='<span class="phrase">'+phrases[i]+'</span>';
          },1400);
        })();
        """
        Task { try? await webView.evaluateJavaScript(js) }
    }

    private func injectBlackOverlay() {
        let js = """
        (function(){
          var id='reader_black_overlay';
          var el=document.getElementById(id);
          if(!el){
            el=document.createElement('div');
            el.id=id; el.style.position='fixed'; el.style.left='0'; el.style.top='0';
            el.style.width='100vw'; el.style.height='100vh'; el.style.background='#000';
            el.style.zIndex='2147483647'; el.style.pointerEvents='none';
            el.style.display='flex'; el.style.alignItems='center'; el.style.justifyContent='center';
            var box=document.createElement('div');
            box.style.textAlign='center';
            var chip=document.createElement('div'); chip.textContent='Mode lecteur IA';
            chip.style.display='inline-block'; chip.style.padding='6px 10px'; chip.style.borderRadius='999px';
            chip.style.border='1px solid rgba(255,255,255,.15)'; chip.style.background='rgba(255,255,255,.08)';
            chip.style.color='#d0d0d0'; chip.style.fontFamily='-apple-system,system-ui,sans-serif'; chip.style.fontSize='12px';
            var phr=document.createElement('div'); phr.id='reader_black_phrase';
            phr.style.marginTop='10px'; phr.style.color='#cfcfcf'; phr.style.fontFamily='-apple-system,system-ui,sans-serif'; phr.style.fontSize='16px';
            phr.textContent='Je brosse l\'article…';
            box.appendChild(chip); box.appendChild(phr); el.appendChild(box);
            document.documentElement.appendChild(el);
            var phrases=[
              'Je taille les longueurs…',
              'Je chasse les pubs et je garde l\'essentiel…',
              'Je traduis en français soigné…',
              'Je clarifie l\'intrigue…',
              'Je condense sans trahir…',
              'Je polie les tournures…',
              'Je coupe les cookies (pas les bons)…',
              'Je range les idées dans l\'ordre…'
            ];
            var i=0; setInterval(function(){ var p=document.getElementById('reader_black_phrase'); if(!p) return; i=(i+1)%phrases.length; p.textContent=phrases[i]; },1400);
          }
        })();
        """
        Task { try? await webView.evaluateJavaScript(js) }
    }

    private func ensureReadabilityInjected() async throws {
        let has = (try? await evaluateJavaScript("!!window.Readability") as? Bool) ?? false
        if !has {
            if let jsURL = Bundle.main.url(forResource: "Readability", withExtension: "js"), let src = try? String(contentsOf: jsURL, encoding: .utf8) {
                _ = await MainActor.run {
                    Task { _ = try? await webView.evaluateJavaScript(src) }
                }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func extractArticle() async throws -> (title: String, text: String, lead: String?, images: [String]) {
        let script = """
        (function(){
          try {
            var a = (new Readability(document.cloneNode(true))).parse();
            var title = (a && a.title) ? a.title : (document.title || '');
            var text = (a && a.textContent) ? a.textContent : '';
            var lead = (a && (a.lead_image_url || a.image)) ? (a.lead_image_url || a.image) : '';
            
            // Extraire toutes les images de l'article
            var images = [];
            var seenUrls = {};
            // D'abord, ajouter la lead image si présente
            if(lead && lead.trim()){
              seenUrls[lead] = true;
              images.push(lead);
            }
            // Ensuite, extraire les images du contenu Readability
            if(a && a.content){
              var tmp = document.createElement('div');
              tmp.innerHTML = a.content;
              tmp.querySelectorAll('img').forEach(function(img){
                var src = img.src || img.getAttribute('data-src') || img.getAttribute('data-lazy-src') || '';
                if(src && src.trim() && !seenUrls[src]){
                  // Filtrer les petites images (icônes, avatars, etc.)
                  var w = parseInt(img.getAttribute('width') || '0', 10);
                  var h = parseInt(img.getAttribute('height') || '0', 10);
                  // Ignorer si dimensions connues et trop petites
                  if((w > 0 && w < 100) || (h > 0 && h < 100)) return;
                  // Ignorer les images de tracking/pub
                  var srcLower = src.toLowerCase();
                  if(srcLower.indexOf('pixel') >= 0 || srcLower.indexOf('tracking') >= 0 || srcLower.indexOf('analytics') >= 0 || srcLower.indexOf('beacon') >= 0 || srcLower.indexOf('1x1') >= 0) return;
                  seenUrls[src] = true;
                  images.push(src);
                }
              });
            }
            // Fallback: si pas d'images trouvées, chercher dans le DOM original
            if(images.length === 0){
              var node = document.querySelector('article') || document.querySelector('main') || document.body;
              if(node){
                node.querySelectorAll('img').forEach(function(img){
                  var src = img.src || img.getAttribute('data-src') || '';
                  if(src && src.trim() && !seenUrls[src]){
                    var w = img.naturalWidth || parseInt(img.getAttribute('width') || '0', 10);
                    var h = img.naturalHeight || parseInt(img.getAttribute('height') || '0', 10);
                    if((w > 0 && w < 150) || (h > 0 && h < 150)) return;
                    var srcLower = src.toLowerCase();
                    if(srcLower.indexOf('pixel') >= 0 || srcLower.indexOf('tracking') >= 0 || srcLower.indexOf('logo') >= 0 || srcLower.indexOf('icon') >= 0 || srcLower.indexOf('avatar') >= 0) return;
                    seenUrls[src] = true;
                    images.push(src);
                  }
                });
              }
            }
            // Fallback si toujours pas de lead
            if(!lead && images.length > 0){
              lead = images[0];
            }
            // Fallbacks when Readability fails or returns too little text
            if(!text || text.trim().length < 200){
              cleanupOverlays();
              var og = document.querySelector('meta[property="og:image"], meta[name="og:image"], meta[property="twitter:image"], meta[name="twitter:image"]');
              if(og && !lead){ 
                lead = og.getAttribute('content') || ''; 
                if(lead && !seenUrls[lead]){
                  images.unshift(lead);
                  seenUrls[lead] = true;
                }
              }
              var node = document.querySelector('article') || document.querySelector('main') || document.body;
              if(node){
                text = (node.innerText || '').replace(/\\s+\\n/g,'\\n').replace(/\\n\\s+/g,'\\n').trim();
              }
            }
            // Limiter à 10 images max
            images = images.slice(0, 10);
            return JSON.stringify({title:(title||''), text:(text||''), lead:(lead||''), images:images});
          } catch(e){ return JSON.stringify({title:'',text:'',lead:'',images:[]}); }
        })();
        """
        let result = try await evaluateJavaScript(script) as? String ?? "{}"
        struct A: Decodable { let title: String; let text: String; let lead: String?; let images: [String]? }
        let data = result.data(using: .utf8) ?? Data()
        let a = (try? JSONDecoder().decode(A.self, from: data)) ?? A(title: "", text: "", lead: nil, images: nil)
        return (a.title, a.text, a.lead, a.images ?? [])
    }

    private func normalizeLeadURL(_ lead: String?) -> String? {
        guard let lead, !lead.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let urlObj = URL(string: lead, relativeTo: url) {
            return urlObj.absoluteURL.absoluteString
        }
        return nil
    }

    private func buildSimpleReaderHTML(title: String, text: String, lead: String?, style: String) -> String {
        let safeTitle = title.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        let parts = cleanReaderParagraphs(from: text)
        let body = parts.isEmpty
            ? "<p>Contenu indisponible pour cet article.</p>"
            : parts.map { "<p>\($0.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;"))</p>" }.joined()
        let leadURL = normalizeLeadURL(lead)
        let leadHTML = leadURL.map { "<img src=\"\($0)\" alt=\"\" loading=\"lazy\" style=\"margin-top:16px;\"/>" } ?? ""
        let sidebarHTML = hideReaderSidebar
            ? ""
            : buildSidebarHTML(
                source: getSourceFeedName(),
                entities: [],
                tags: [],
                articleURL: url.absoluteString,
                pageTitle: title,
                showSummaryButton: true
            )
        let html = "<!doctype html><meta charset=\"utf-8\"><style>\(style)</style><div class=\"reader-outer\"><div class=\"reader-container\"><article class=\"reader\"><h1>\(safeTitle)</h1>\(leadHTML)\(body)</article>\(sidebarHTML)</div></div>"
        return html
    }

    private func cleanReaderParagraphs(from raw: String) -> [String] {
        let normalized = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "[ ]{2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        var results: [String] = []
        var seen = Set<String>()

        func push(_ rawLine: String) {
            let line = rawLine
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            guard !line.isEmpty else { return }
            if line.count < 40 {
                let words = line.split(whereSeparator: { $0.isWhitespace }).count
                if words < 7 { return }
            }
            if line.count > 2000 { return }
            guard !isReaderNoiseLine(line) else { return }
            let key = line.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            results.append(line)
        }

        normalized
            .components(separatedBy: "\n\n")
            .forEach { block in push(block) }

        if results.count < 3 {
            normalized
                .components(separatedBy: .newlines)
                .forEach { line in push(line) }
        }

        return results
    }

    private func isReaderNoiseLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.isEmpty { return true }

        let exact: Set<String> = [
            "advertisement", "sponsored", "publicite", "publicité", "newsletter",
            "cookies", "cookie", "consent", "share", "partager", "follow us",
            "suivez-nous", "read more", "lire la suite", "voir plus", "comments", "commentaires"
        ]
        if exact.contains(lower) { return true }

        if line.count <= 220 {
            let noisyFragments = [
                "cookie", "consent", "newsletter", "subscribe", "inscrivez-vous",
                "publicite", "publicité", "sponsor", "sponsored", "related", "recommended",
                "read more", "lire aussi", "lire la suite", "voir aussi", "follow us", "suivez-nous",
                "share this", "partager", "comment"
            ]
            if noisyFragments.contains(where: { lower.contains($0) }) {
                return true
            }
        }
        return false
    }

    private func storedArticleMatch() -> Article? {
        let target = normalizeURLForMatch(url)
        return feedService.articles.first(where: { normalizeURLForMatch($0.url) == target })
    }

    private func storedArticleFallback() -> (title: String?, text: String?, imageURL: String?) {
        guard let match = storedArticleMatch() else {
            return (nil, nil, nil)
        }
        let text = match.contentText?.isEmpty == false ? match.contentText : match.summary
        return (match.title, text, match.imageURL?.absoluteString)
    }

    private func injectHTML(_ html: String) async -> Bool {
        let base64 = Data(html.utf8).base64EncodedString()
        let js = "(function(){try{var b64='\(base64)';var bytes=Uint8Array.from(atob(b64), function(c){return c.charCodeAt(0);});var html=new TextDecoder('utf-8').decode(bytes);document.open();document.write(html);document.close();try{document.documentElement.style.overflow='auto';document.documentElement.style.position='static';document.body.style.overflow='auto';document.body.style.position='static';document.documentElement.classList.remove('modal-open','no-scroll','noscroll','overflow-hidden','is-locked','scroll-lock','scroll-locked','disable-scroll');document.body.classList.remove('modal-open','no-scroll','noscroll','overflow-hidden','is-locked','scroll-lock','scroll-locked','disable-scroll');}catch(e){}return true;}catch(e){return false;}})();"
        return (try? await evaluateJavaScript(js) as? Bool) ?? false
    }

    private func articleImageURL() -> String? {
        storedArticleMatch()?.imageURL?.absoluteString
    }

    private func saveSelectedReaderNote(_ rawText: String) {
        let cleanedText = rawText
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else { return }

        let article = storedArticleMatch()
        let pageTitleCandidate = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = article?.title
            ?? (pageTitleCandidate.isEmpty ? nil : pageTitleCandidate)
            ?? url.host
            ?? url.absoluteString
        let imageURL = article?.imageURL ?? articleImageURL().flatMap(URL.init(string:))

        _ = feedService.addReaderNote(
            selectedText: cleanedText,
            articleTitle: resolvedTitle,
            articleURL: url,
            articleImageURL: imageURL,
            articleSource: getSourceFeedName(),
            articlePublishedAt: article?.publishedAt,
            articleId: article?.id,
            feedId: article?.feedId
        )
    }

    private func normalizeURLForMatch(_ input: URL) -> String {
        var comps = URLComponents(url: input, resolvingAgainstBaseURL: false)
        comps?.fragment = nil
        comps?.query = nil
        return comps?.url?.absoluteString ?? input.absoluteString
    }

    private func summarizeForReaderHTML(title: String, text: String) async throws -> String {
        // Déterminer la langue cible depuis les réglages
        let lang = LocalizationManager.shared.currentLanguage
        // Nom lisible pour l’instruction de langue
        let targetName: String
        let takeawaysHeading: String
        switch lang {
        case .french: targetName = "français"; takeawaysHeading = "À retenir"
        case .english: targetName = "English"; takeawaysHeading = "Key takeaways"
        case .spanish: targetName = "español"; takeawaysHeading = "Puntos clave"
        case .german: targetName = "Deutsch"; takeawaysHeading = "Wichtigste Punkte"
        case .italian: targetName = "italiano"; takeawaysHeading = "Da ricordare"
        case .portuguese: targetName = "português"; takeawaysHeading = "Pontos‑chave"
        case .japanese: targetName = "日本語"; takeawaysHeading = "要点"
        case .chinese: targetName = "中文"; takeawaysHeading = "要点"
        case .korean: targetName = "한국어"; takeawaysHeading = "핵심 요약"
        case .russian: targetName = "русский"; takeawaysHeading = "Ключевые тезисы"
        @unknown default: targetName = "English"; takeawaysHeading = "Key takeaways"
        }
        let delimiter = "\n===TAKEAWAYS===\n"
        let system = "You are an editor. Clean the article (remove navigation, cookies, promos), translate to \(targetName) if needed, and produce strictly in \(targetName). ABSOLUTE LANGUAGE RULE: output must be in \(targetName) only (except unavoidable proper nouns). Output HTML only (no Markdown). Do not output any headings (no <h1>, <h2>, <h3>, <h4> and no Markdown ##). Never output the label 'Résumé' or 'Summary' in the content. No links, no disclaimers."
        let user = """
        Title: \(title)

        Text:
        \(text.prefix(12000))

        STRICT OUTPUT FORMAT (two separate sections):

        SECTION 1 - SUMMARY:
        Write ONLY 2-3 <p> paragraphs that summarize the main ideas. NO bullet points, NO lists in this section.
        In this SUMMARY section only, use <strong>...</strong> around the most essential facts (2 to 6 highlights max).

        ===TAKEAWAYS===

        SECTION 2 - KEY POINTS:
        Write ONLY a <ul> list with 6-10 <li> bullet points. These are the actionable takeaways.

        CRITICAL: The summary section must contain ONLY <p> paragraphs. ALL bullet points go AFTER the ===TAKEAWAYS=== delimiter.
        CRITICAL LANGUAGE: If target language is not English, do NOT keep English sentences. Translate everything except proper nouns and brand names.
        Respond strictly in \(targetName).
        """
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                let session = LanguageModelSession(
                    model: model,
                    instructions: { system }
                )
                let response = try await session.respond(to: user)
                let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty {
                    let cleaned = stripCodeFences(content)
                    let parts = cleaned.components(separatedBy: delimiter)
                    var summaryHTML = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    var takeawaysHTML = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                    
                    // FALLBACK: Si le résumé contient des <li>, extraire la liste et la déplacer vers takeaways
                    if summaryHTML.contains("<li>") && takeawaysHTML.isEmpty {
                        // Extraire la liste <ul>...</ul> du résumé
                        if let ulStart = summaryHTML.range(of: "<ul>"),
                           let ulEnd = summaryHTML.range(of: "</ul>", options: .backwards),
                           ulStart.lowerBound < ulEnd.upperBound {
                            takeawaysHTML = String(summaryHTML[ulStart.lowerBound..<ulEnd.upperBound])
                            summaryHTML = summaryHTML.replacingOccurrences(of: takeawaysHTML, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            appLog("[ReaderAI] Moved list from summary to takeaways")
                        }
                    }
                    // Si takeaways est toujours vide et le résumé contient des <li> individuels
                    if summaryHTML.contains("<li>") && takeawaysHTML.isEmpty {
                        // Extraire tous les <li>...</li> et les encapsuler dans <ul>
                        let liPattern = "<li>.*?</li>"
                        if let regex = try? NSRegularExpression(pattern: liPattern, options: [.dotMatchesLineSeparators]) {
                            let range = NSRange(summaryHTML.startIndex..., in: summaryHTML)
                            let matches = regex.matches(in: summaryHTML, options: [], range: range)
                            if !matches.isEmpty {
                                // D'abord extraire tous les items, puis supprimer du résumé
                                var liItems: [String] = []
                                for match in matches {
                                    if let matchRange = Range(match.range, in: summaryHTML) {
                                        liItems.append(String(summaryHTML[matchRange]))
                                    }
                                }
                                // Supprimer tous les <li> du résumé en une seule opération
                                summaryHTML = regex.stringByReplacingMatches(in: summaryHTML, options: [], range: range, withTemplate: "")
                                takeawaysHTML = "<ul>\(liItems.joined())</ul>"
                                summaryHTML = summaryHTML.trimmingCharacters(in: .whitespacesAndNewlines)
                                appLog("[ReaderAI] Extracted individual <li> items to takeaways")
                            }
                        }
                    }
                    // Nettoyage markdown global (gras/italique/astérisques parasites).
                    summaryHTML = normalizeMarkdownArtifacts(summaryHTML, forceRemoveAsterisks: true)
                    takeawaysHTML = normalizeMarkdownArtifacts(takeawaysHTML, forceRemoveAsterisks: true)
                    summaryHTML = fixMojibake(summaryHTML)
                    takeawaysHTML = fixMojibake(takeawaysHTML)
                    summaryHTML = summaryHTML.replacingOccurrences(of: "===TAKEAWAYS===", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    takeawaysHTML = takeawaysHTML.replacingOccurrences(of: "===TAKEAWAYS===", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    // Nettoyer les marqueurs de section que le modèle peut inclure
                    summaryHTML = cleanSectionMarkers(summaryHTML)
                    takeawaysHTML = cleanSectionMarkers(takeawaysHTML)
                    summaryHTML = normalizeSummaryHTML(summaryHTML)
                    takeawaysHTML = normalizeTakeawaysHTML(takeawaysHTML)
                    summaryHTML = normalizeHeadingHTML(summaryHTML)
                    takeawaysHTML = normalizeHeadingHTML(takeawaysHTML)
                    takeawaysHTML = ensureTakeawaysHTML(takeawaysHTML: takeawaysHTML, summaryHTML: summaryHTML, sourceText: text)

                    // Si la sortie n'est pas dans la langue cible, forcer une retraduction.
                    let rewritten = await enforceTargetLanguageForSummary(
                        summaryHTML: summaryHTML,
                        takeawaysHTML: takeawaysHTML,
                        targetLanguage: lang,
                        targetName: targetName
                    )
                    summaryHTML = rewritten.summaryHTML
                    takeawaysHTML = rewritten.takeawaysHTML

                    let summaryBlock = """
                    <section class="reader-section reader-summary">
                    <h3 class="reader-section-title">Résumé</h3>
                    <div class="scramble-target" data-scramble-delay="0">\(summaryHTML)</div>
                    </section>
                    """
                    let takeawaysBlock = """
                    <section class="reader-section reader-takeaways">
                    <h3 class="reader-section-title">\(takeawaysHeading)</h3>
                    <div class="scramble-target" data-scramble-delay="400">\(takeawaysHTML)</div>
                    </section>
                    """
                    return "\(summaryBlock)\n\(takeawaysBlock)"
                }
                throw NSError(domain: "ReaderAI", code: -2, userInfo: nil)
            case .unavailable(let reason):
                throw NSError(domain: "ReaderAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "\(reason)"])
            @unknown default:
                throw NSError(domain: "ReaderAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Modèle local indisponible."])
            }
        }
        #endif
        throw NSError(domain: "ReaderAI", code: -3, userInfo: [NSLocalizedDescriptionKey: "Modèle local indisponible."])
    }

    /// Extrait les entités principales et les tags de l'article via intelligence artificielle locale
    private func extractEntitiesAndTags(title: String, text: String) async -> (entities: [String], tags: [String]) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                print("[ReaderAI] extractEntitiesAndTags: model not available")
                return ([], [])
            }
            let system = """
            Tu es un extracteur de métadonnées. À partir d'un article, extrais:
            1. ENTITIES: Les sujets principaux mentionnés (personnes, organisations, lieux, produits, concepts). Format: "Nom (type)" où type est: personne, organisation, lieu, produit, événement, concept. Maximum 5 entités, les plus importantes.
            2. TAGS: 4-6 mots-clés courts qui résument les thèmes de l'article.

            IMPORTANT: Réponds UNIQUEMENT avec du JSON valide, sans markdown, sans backticks, sans explication.
            Format exact:
            {"entities":["Entité1 (type)","Entité2 (type)"],"tags":["tag1","tag2","tag3"]}
            """
            let user = "Titre: \(title)\n\nTexte:\n\(text.prefix(4000))"
            do {
                let session = LanguageModelSession(model: model, instructions: { system })
                let response = try await session.respond(to: user)
                var content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[ReaderAI] extractEntitiesAndTags raw response: \(content.prefix(500))")

                // Nettoyer les blocs de code markdown si présents
                content = content
                    .replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Essayer de trouver le JSON dans la réponse
                if let startIndex = content.firstIndex(of: "{"),
                   let endIndex = content.lastIndex(of: "}") {
                    content = String(content[startIndex...endIndex])
                }

                // Parse JSON response
                if let data = content.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let entities = (json["entities"] as? [String]) ?? []
                    let tags = (json["tags"] as? [String]) ?? []
                    print("[ReaderAI] extractEntitiesAndTags parsed: entities=\(entities) tags=\(tags)")
                    return (entities, tags)
                } else {
                    print("[ReaderAI] extractEntitiesAndTags: failed to parse JSON from: \(content)")
                }
            } catch {
                print("[ReaderAI] extractEntitiesAndTags error: \(error)")
            }
        }
        #endif
        return ([], [])
    }

    /// Récupère le nom du feed source pour l'article courant
    private func getSourceFeedName() -> String {
        let target = normalizeURLForMatch(url)
        if let article = feedService.articles.first(where: { normalizeURLForMatch($0.url) == target }),
           let feed = feedService.feeds.first(where: { $0.id == article.feedId }) {
            return feed.title
        }
        // Fallback: utiliser le host de l'URL
        return url.host ?? "Source inconnue"
    }

    private func exitReader() {
        readerAICompleted = false
        isShowingAISummary = false
        forceClassicReaderOnNextLoad = false
        webView.load(URLRequest(url: url))
    }

    /// Génère le script JavaScript pour l'effet d'apparition mot par mot
    private func scrambleEffectScript() -> String {
        return """
        <style>
        .word-reveal { 
            opacity: 0; 
            display: inline;
            transition: opacity 0.25s ease-out;
        }
        .word-reveal.revealed { 
            opacity: 1; 
        }
        </style>
        <script>
        (function() {
            const wordsPerBatch = 2;
            const delayBetweenBatches = 80;
            let scrambleStarted = false;
            
            function revealWordByWord(element, delay) {
                return new Promise((resolve) => {
                const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT, null, false);
                const textNodes = [];
                let node;
                while (node = walker.nextNode()) {
                    if (node.textContent.trim()) {
                        textNodes.push({ node: node, original: node.textContent, parent: node.parentNode });
                    }
                }
                
                if (textNodes.length === 0) { resolve(); return; }
                
                // Remplacer chaque mot par un span
                const allWords = [];
                textNodes.forEach(item => {
                    const fragment = document.createDocumentFragment();
                    // Séparer en mots tout en gardant les espaces
                    const parts = item.original.split(/(\\s+)/);
                    parts.forEach(part => {
                        if (part.match(/^\\s+$/)) {
                            // Espace ou whitespace - ajouter tel quel
                            fragment.appendChild(document.createTextNode(part));
                        } else if (part.trim()) {
                            // Mot - envelopper dans un span
                            const span = document.createElement('span');
                            span.className = 'word-reveal';
                            span.textContent = part;
                            fragment.appendChild(span);
                            allWords.push(span);
                        }
                    });
                    item.parent.replaceChild(fragment, item.node);
                });
                
                // Révéler les mots progressivement
                setTimeout(() => {
                    let revealedCount = 0;
                    
                    function revealBatch() {
                        if (revealedCount >= allWords.length) { resolve(); return; }
                        
                        // Révéler plusieurs mots par batch
                        for (let i = 0; i < wordsPerBatch && revealedCount < allWords.length; i++) {
                            allWords[revealedCount].classList.add('revealed');
                            revealedCount++;
                        }
                        
                        if (revealedCount < allWords.length) {
                            setTimeout(revealBatch, delayBetweenBatches);
                        } else {
                            resolve();
                        }
                    }
                    
                    revealBatch();
                }, delay);
                });
            }

            function runScrambleSequence() {
                if (scrambleStarted) { return; }
                scrambleStarted = true;
                const targets = Array.from(document.querySelectorAll('.scramble-target'));
                const finalizeHighlights = () => {
                    document.querySelectorAll('.reader-summary strong, .reader-summary b').forEach(el => {
                        const text = el.textContent || '';
                        const highlight = document.createElement('span');
                        highlight.className = 'reader-highlight';
                        highlight.textContent = text;
                        el.replaceWith(highlight);
                    });
                };
                document.body.classList.remove('scramble-complete');
                if (targets.length === 0) {
                    finalizeHighlights();
                    document.body.classList.add('scramble-complete');
                    return;
                }
                Promise.all(targets.map(el => {
                    const delay = parseInt(el.dataset.scrambleDelay || '0', 10);
                    return revealWordByWord(el, delay);
                })).then(() => {
                    finalizeHighlights();
                    document.body.classList.add('scramble-complete');
                });
            }
            
            // Appliquer l'effet aux éléments avec la classe scramble-target
            document.addEventListener('DOMContentLoaded', function() {
                runScrambleSequence();
            });
            
            // Fallback si DOMContentLoaded déjà passé
            if (document.readyState !== 'loading') {
                runScrambleSequence();
            }
        })();
        </script>
        """
    }

    private func readerNoteSupportScript() -> String {
        let buttonLabel = javaScriptSingleQuotedText(localizedAddNoteButtonText())
        return """
        <script>
        (function() {
            var button = null;
            var lastRange = null;

            function ensureButton() {
                if (button) { return button; }
                button = document.createElement('button');
                button.type = 'button';
                button.className = 'reader-note-action';
                button.textContent = '\(buttonLabel)';
                button.addEventListener('mousedown', function(e) {
                    e.preventDefault();
                });
                button.addEventListener('click', function(e) {
                    e.preventDefault();
                    addCurrentSelectionToNotes();
                });
                document.body.appendChild(button);
                return button;
            }

            function hideButton() {
                if (!button) { return; }
                button.classList.remove('is-visible');
            }

            function normalizeSelectionText(value) {
                return (value || '').replace(/\\s+/g, ' ').trim();
            }

            function allowedContainerFromNode(node) {
                if (!node) { return null; }
                if (node.nodeType === Node.TEXT_NODE) {
                    node = node.parentElement;
                }
                if (!node || !node.closest) { return null; }
                return node.closest('.reader-summary, .reader-takeaways');
            }

            function selectionBlockFromNode(node) {
                if (!node) { return null; }
                if (node.nodeType === Node.TEXT_NODE) {
                    node = node.parentElement;
                }
                if (!node || !node.closest) { return null; }
                return node.closest('p, li, blockquote');
            }

            function selectionInfo() {
                var selection = window.getSelection();
                if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
                    return null;
                }

                var range = selection.getRangeAt(0);
                var text = normalizeSelectionText(selection.toString());
                if (!text) { return null; }

                var startContainer = allowedContainerFromNode(range.startContainer);
                var endContainer = allowedContainerFromNode(range.endContainer);
                if (!startContainer || !endContainer || startContainer !== endContainer) {
                    return null;
                }
                var startBlock = selectionBlockFromNode(range.startContainer);
                var endBlock = selectionBlockFromNode(range.endContainer);
                if (!startBlock || !endBlock || startBlock !== endBlock) {
                    return null;
                }

                var rect = range.getBoundingClientRect();
                if (!rect || (!rect.width && !rect.height)) {
                    return null;
                }

                return {
                    text: text,
                    range: range.cloneRange(),
                    rect: rect
                };
            }

            function placeButton(rect) {
                var el = ensureButton();
                var articleRect = document.querySelector('.reader') ? document.querySelector('.reader').getBoundingClientRect() : null;
                var sidebarRect = document.querySelector('.reader-sidebar') ? document.querySelector('.reader-sidebar').getBoundingClientRect() : null;
                var left = articleRect ? articleRect.right + 14 : (window.innerWidth - 180);
                if (sidebarRect) {
                    left = Math.min(left, sidebarRect.left - 170);
                }
                left = Math.max(16, Math.min(left, window.innerWidth - 170));
                var top = Math.max(90, Math.min(rect.top - 4, window.innerHeight - 56));

                el.style.left = left + 'px';
                el.style.top = top + 'px';
                el.classList.add('is-visible');
            }

            function wrapRange(range) {
                if (!range || range.collapsed) { return false; }
                try {
                    var mark = document.createElement('mark');
                    mark.className = 'reader-note-highlight';
                    mark.appendChild(range.extractContents());
                    range.insertNode(mark);
                    return true;
                } catch (error) {
                    return false;
                }
            }

            function addCurrentSelectionToNotes() {
                var info = selectionInfo();
                var range = (info && info.range) || lastRange;
                var text = info ? info.text : normalizeSelectionText(window.getSelection ? String(window.getSelection()) : '');
                if ((!text || !text.length) && range) {
                    text = normalizeSelectionText(range.toString());
                }
                if (!range || !text) {
                    hideButton();
                    return;
                }

                wrapRange(range.cloneRange());
                hideButton();
                if (window.getSelection) {
                    var selection = window.getSelection();
                    if (selection) {
                        selection.removeAllRanges();
                    }
                }
                try {
                    window.location.href = 'flux-action://add-note?text=' + encodeURIComponent(text);
                } catch (error) {}
            }

            function refreshButton() {
                var info = selectionInfo();
                if (!info) {
                    lastRange = null;
                    hideButton();
                    return;
                }
                lastRange = info.range.cloneRange();
                placeButton(info.rect);
            }

            document.addEventListener('selectionchange', function() {
                window.requestAnimationFrame(refreshButton);
            });
            window.addEventListener('scroll', function() {
                hideButton();
            }, { passive: true });
            window.addEventListener('resize', function() {
                hideButton();
            });
            document.addEventListener('keydown', function(e) {
                if (e.key === 'Escape') {
                    hideButton();
                }
            });
        })();
        </script>
        """
    }

    private func javaScriptSingleQuotedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Construit le HTML de la sidebar du lecteur
    private func buildSidebarHTML(source: String, entities: [String], tags: [String], articleURL: String, pageTitle: String, showSummaryButton: Bool) -> String {
        let safeSource = source.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")

        // Section source
        let sourceSection = """
        <div class="section">
            <h4>Source</h4>
            <div class="source">\(safeSource)</div>
        </div>
        """

        // Section entités avec icônes selon le type
        var entitiesHTML = ""
        if !entities.isEmpty {
            let entitiesItems = entities.map { entity -> String in
                // Parser "Name (type)" pour extraire le type
                let (name, type) = parseEntity(entity)
                let icon = iconForEntityType(type)
                let safeName = name.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
                let safeType = type.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
                return """
                <div class="entity">
                    <span class="entity-icon">\(icon)</span>
                    <div>
                        <div class="entity-name">\(safeName)</div>
                        <div class="entity-type">\(safeType)</div>
                    </div>
                </div>
                """
            }.joined()
            entitiesHTML = """
            <div class="section">
                <h4>Dans cet article</h4>
                \(entitiesItems)
            </div>
            """
        }

        // Section tags
        var tagsHTML = ""
        if !tags.isEmpty {
            let tagsItems = tags.map { tag -> String in
                let safeTag = tag.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
                return "<span class=\"tag\">\(safeTag)</span>"
            }.joined()
            tagsHTML = """
            <div class="section">
                <h4>Tags</h4>
                <div class="tags">\(tagsItems)</div>
            </div>
            """
        }

        let disclaimerText = escapeHTML(localizedReaderAIDisclaimerText())
        let disclaimerHTML = """
        <div class="section ai-disclaimer-section">
            <p class="ai-disclaimer">\(disclaimerText)</p>
        </div>
        """
        let openOriginalLabel = escapeHTML(localizedOpenOriginalArticleButtonText())
        let openOriginalButtonHTML = """
        <button onclick="window.location.href='flux-action://open-original'" class="origin-btn">
            <span>\(openOriginalLabel)</span>
        </button>
        """

        // Bouton partager sur X - utilise un schéma personnalisé pour déclencher la génération IA
        let xButtonHTML = """
        <button onclick="window.location.href='flux-action://share-x'" class="x-btn">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>
            <span>Partager sur X</span>
        </button>
        """
        let summaryButtonHTML = showSummaryButton ? """
        <button onclick="window.location.href='flux-action://summary-ai'" class="ai-btn">
            <span>Résumé (Intelligence artificielle locale)</span>
        </button>
        """ : ""

        return """
        <aside class="reader-sidebar">
            \(sourceSection)
            \(entitiesHTML)
            \(tagsHTML)
            \(disclaimerHTML)
            \(openOriginalButtonHTML)
            \(xButtonHTML)
            \(summaryButtonHTML)
        </aside>
        """
    }

    private func localizedReaderAIDisclaimerText() -> String {
        switch lm.currentLanguage {
        case .french:
            return "L’IA locale d’Apple peut faire des erreurs dans les résumés et les traductions. Vérifiez les informations en cas de doute."
        case .english:
            return "Apple’s on-device AI can make mistakes in summaries and translations. Verify information if in doubt."
        case .spanish:
            return "La IA local de Apple puede cometer errores en los resúmenes y las traducciones. Verifica la información en caso de duda."
        case .german:
            return "Die lokale KI von Apple kann bei Zusammenfassungen und Übersetzungen Fehler machen. Prüfen Sie die Informationen im Zweifel."
        case .italian:
            return "L’IA locale di Apple può commettere errori nei riassunti e nelle traduzioni. Verifica le informazioni in caso di dubbio."
        case .portuguese:
            return "A IA local da Apple pode cometer erros em resumos e traduções. Verifique as informações em caso de dúvida."
        case .japanese:
            return "AppleのローカルAIは、要約や翻訳で誤りを含む場合があります。疑わしい場合は情報を確認してください。"
        case .chinese:
            return "Apple 本地 AI 在摘要和翻译中可能会出错。如有疑问，请核实相关信息。"
        case .korean:
            return "Apple의 로컬 AI는 요약과 번역에서 오류를 낼 수 있습니다. 의심될 때는 정보를 확인하세요."
        case .russian:
            return "Локальный ИИ Apple может допускать ошибки в резюме и переводах. Если есть сомнения, проверяйте информацию."
        @unknown default:
            return "Apple’s on-device AI can make mistakes in summaries and translations. Verify information if in doubt."
        }
    }

    private func localizedOpenOriginalArticleButtonText() -> String {
        switch lm.currentLanguage {
        case .french:
            return "Ouvrir l'article original"
        case .english:
            return "Open original article"
        case .spanish:
            return "Abrir artículo original"
        case .german:
            return "Originalartikel öffnen"
        case .italian:
            return "Apri articolo originale"
        case .portuguese:
            return "Abrir artigo original"
        case .japanese:
            return "元の記事を開く"
        case .chinese:
            return "打开原始文章"
        case .korean:
            return "원문 기사 열기"
        case .russian:
            return "Открыть оригинальную статью"
        @unknown default:
            return "Open original article"
        }
    }

    private func localizedAddNoteButtonText() -> String {
        switch lm.currentLanguage {
        case .french:
            return "Ajouter en note"
        case .english:
            return "Add note"
        case .spanish:
            return "Añadir nota"
        case .german:
            return "Als Notiz speichern"
        case .italian:
            return "Aggiungi nota"
        case .portuguese:
            return "Adicionar nota"
        case .japanese:
            return "ノートに追加"
        case .chinese:
            return "添加到笔记"
        case .korean:
            return "노트에 추가"
        case .russian:
            return "Добавить в заметки"
        @unknown default:
            return "Add note"
        }
    }

    /// Parse une entité au format "Name (type)" et retourne (name, type)
    private func parseEntity(_ entity: String) -> (name: String, type: String) {
        let pattern = #"^(.+?)\s*\(([^)]+)\)$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: entity, range: NSRange(entity.startIndex..., in: entity)) {
            let nameRange = Range(match.range(at: 1), in: entity)
            let typeRange = Range(match.range(at: 2), in: entity)
            if let nameRange, let typeRange {
                return (String(entity[nameRange]).trimmingCharacters(in: .whitespaces),
                        String(entity[typeRange]).trimmingCharacters(in: .whitespaces))
            }
        }
        return (entity, "")
    }

    /// Retourne une icône emoji selon le type d'entité
    private func iconForEntityType(_ type: String) -> String {
        let lowerType = type.lowercased()
        if lowerType.contains("person") || lowerType.contains("personne") || lowerType.contains("humain") {
            return "👤"
        } else if lowerType.contains("organization") || lowerType.contains("organisation") || lowerType.contains("entreprise") || lowerType.contains("company") || lowerType.contains("groupe") {
            return "🏢"
        } else if lowerType.contains("place") || lowerType.contains("lieu") || lowerType.contains("location") || lowerType.contains("ville") || lowerType.contains("pays") {
            return "📍"
        } else if lowerType.contains("product") || lowerType.contains("produit") {
            return "📦"
        } else if lowerType.contains("event") || lowerType.contains("événement") || lowerType.contains("evenement") {
            return "📅"
        } else if lowerType.contains("concept") || lowerType.contains("idée") || lowerType.contains("idea") {
            return "💡"
        } else if lowerType.contains("animal") {
            return "🐾"
        }
        return "•"
    }

    private func targetLanguageISOCode(_ language: SupportedLanguage) -> String {
        switch language {
        case .chinese:
            return "zh"
        default:
            return language.rawValue
        }
    }

    private func normalizedLanguageCode(_ code: String) -> String {
        let lower = code.lowercased()
        if lower.hasPrefix("zh") { return "zh" }
        if lower.hasPrefix("pt") { return "pt" }
        if lower.hasPrefix("es") { return "es" }
        if lower.hasPrefix("de") { return "de" }
        if lower.hasPrefix("it") { return "it" }
        if lower.hasPrefix("ja") { return "ja" }
        if lower.hasPrefix("ko") { return "ko" }
        if lower.hasPrefix("ru") { return "ru" }
        if lower.hasPrefix("fr") { return "fr" }
        if lower.hasPrefix("en") { return "en" }
        return lower.components(separatedBy: "-").first ?? lower
    }

    private func languageCodeMatchesTarget(_ code: String, targetLanguage: SupportedLanguage) -> Bool {
        normalizedLanguageCode(code) == targetLanguageISOCode(targetLanguage)
    }

    private func detectedLanguageCode(for text: String) -> String? {
        let sample = stripHTMLTags(String(text.prefix(4500))).trimmingCharacters(in: .whitespacesAndNewlines)
        guard sample.count >= 80 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let detected = recognizer.dominantLanguage else { return nil }
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[detected] ?? 0
        guard confidence >= 0.55 else { return nil }
        return normalizedLanguageCode(detected.rawValue)
    }

    private func shouldForceLanguageRewrite(text: String, targetLanguage: SupportedLanguage) -> Bool {
        guard let detectedCode = detectedLanguageCode(for: text) else { return false }
        return !languageCodeMatchesTarget(detectedCode, targetLanguage: targetLanguage)
    }

    private func enforceTargetLanguageForSummary(
        summaryHTML: String,
        takeawaysHTML: String,
        targetLanguage: SupportedLanguage,
        targetName: String
    ) async -> (summaryHTML: String, takeawaysHTML: String) {
        let combined = summaryHTML + "\n" + takeawaysHTML
        guard shouldForceLanguageRewrite(text: combined, targetLanguage: targetLanguage) else {
            return (summaryHTML, takeawaysHTML)
        }

        appLogWarning("[ReaderAI] language mismatch detected -> forcing rewrite to \(targetLanguage.rawValue)")

        guard let rewritten = try? await rewriteSummaryBlocksInTargetLanguage(
            summaryHTML: summaryHTML,
            takeawaysHTML: takeawaysHTML,
            targetName: targetName
        ) else {
            return (summaryHTML, takeawaysHTML)
        }

        let delimiter = "\n===TAKEAWAYS===\n"
        let cleaned = stripCodeFences(rewritten)
        let parts = cleaned.components(separatedBy: delimiter)
        let rewrittenSummary = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? summaryHTML
        let rewrittenTakeaways = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            : takeawaysHTML

        var normalizedSummary = normalizeMarkdownArtifacts(rewrittenSummary, forceRemoveAsterisks: true)
        var normalizedTakeaways = normalizeMarkdownArtifacts(rewrittenTakeaways, forceRemoveAsterisks: true)

        normalizedSummary = fixMojibake(normalizedSummary)
        normalizedTakeaways = fixMojibake(normalizedTakeaways)
        normalizedSummary = cleanSectionMarkers(normalizedSummary)
        normalizedTakeaways = cleanSectionMarkers(normalizedTakeaways)
        normalizedSummary = normalizeSummaryHTML(normalizedSummary)
        normalizedTakeaways = normalizeTakeawaysHTML(normalizedTakeaways)
        normalizedSummary = normalizeHeadingHTML(normalizedSummary)
        normalizedTakeaways = normalizeHeadingHTML(normalizedTakeaways)
        normalizedTakeaways = ensureTakeawaysHTML(
            takeawaysHTML: normalizedTakeaways,
            summaryHTML: normalizedSummary,
            sourceText: stripHTMLTags(summaryHTML)
        )

        return (normalizedSummary, normalizedTakeaways)
    }

    private func rewriteSummaryBlocksInTargetLanguage(
        summaryHTML: String,
        takeawaysHTML: String,
        targetName: String
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                throw NSError(domain: "ReaderAI", code: -11, userInfo: [NSLocalizedDescriptionKey: "Model unavailable for language rewrite"])
            }

            let delimiter = "\n===TAKEAWAYS===\n"
            let system = """
            You are a translator-editor.
            Translate both HTML blocks strictly to \(targetName).
            Keep HTML tags intact as much as possible.
            Do not add headings, labels, notes, links, or markdown.
            Output format must be:
            <translated section 1 HTML>
            ===TAKEAWAYS===
            <translated section 2 HTML>
            """

            let user = """
            SECTION 1 HTML:
            \(summaryHTML)

            ===TAKEAWAYS===

            SECTION 2 HTML:
            \(takeawaysHTML)
            """

            let session = LanguageModelSession(model: model, instructions: { system })
            let response = try await session.respond(to: user)
            let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                throw NSError(domain: "ReaderAI", code: -12, userInfo: [NSLocalizedDescriptionKey: "Empty rewrite response"])
            }

            let cleaned = stripCodeFences(content)
            if cleaned.contains(delimiter) { return cleaned }
            return cleaned + delimiter + takeawaysHTML
        }
        #endif
        throw NSError(domain: "ReaderAI", code: -13, userInfo: [NSLocalizedDescriptionKey: "Model unavailable for language rewrite"])
    }

    private func normalizeMarkdownArtifacts(_ raw: String, forceRemoveAsterisks: Bool = false) -> String {
        var result = raw
            .replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
            .replacingOccurrences(of: "__(.+?)__", with: "<strong>$1</strong>", options: .regularExpression)
            .replacingOccurrences(of: "(?<!\\*)\\*([^*\\n]+)\\*(?!\\*)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "(?<!_)_([^_\\n]+)_(?!_)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "(?m)^\\s*\\*+\\s*$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(^|\\s)\\*(?=\\s|$)", with: "$1", options: .regularExpression)

        if forceRemoveAsterisks {
            result = result.replacingOccurrences(of: "*", with: "")
        }
        return result
    }

    private func normalizeSummaryHTML(_ raw: String) -> String {
        var cleaned = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "</?(ul|ol)[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<li[^>]*>\\s*", with: "<p>", options: .regularExpression)
            .replacingOccurrences(of: "\\s*</li>", with: "</p>", options: .regularExpression)
            .replacingOccurrences(of: "<div[^>]*>", with: "<p>", options: .regularExpression)
            .replacingOccurrences(of: "</div>", with: "</p>", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<br\\s*/?>", with: "</p><p>", options: .regularExpression)
            .replacingOccurrences(of: "<p>\\s*(?:[-•*]+|\\d+[\\.)])\\s*", with: "<p>", options: .regularExpression)
            .replacingOccurrences(of: "(?m)^\\s*(?:[-•*]+|\\d+[\\.)])\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<p>\\s*</p>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let hasParagraphTag = cleaned.range(of: "<p\\b", options: .regularExpression) != nil
        if !hasParagraphTag, !cleaned.isEmpty {
            let hasHTMLTag = cleaned.range(of: "<[^>]+>", options: .regularExpression) != nil
            if hasHTMLTag {
                cleaned = "<p>\(cleaned)</p>"
            } else {
                let lines = cleaned
                    .components(separatedBy: .newlines)
                    .map { line in
                        line
                            .replacingOccurrences(of: "^(?:[-•*]+|\\d+[\\.)])\\s*", with: "", options: .regularExpression)
                            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    .filter {
                        let lower = $0.lowercased()
                        return !$0.isEmpty &&
                            lower != "résumé" &&
                            lower != "resume" &&
                            lower != "summary" &&
                            lower != "html" &&
                            lower != "html:" &&
                            lower != "section 1 html:" &&
                            lower != "section 2 html:"
                    }

                if !lines.isEmpty {
                    cleaned = lines.map { "<p>\(escapeHTML($0))</p>" }.joined()
                } else {
                    cleaned = "<p>\(escapeHTML(cleaned))</p>"
                }
            }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeTakeawaysHTML(_ raw: String) -> String {
        let trimmed = normalizeMarkdownArtifacts(raw, forceRemoveAsterisks: true).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("<li>") {
            return trimmed
                .replacingOccurrences(of: "<li[^>]*>\\s*(?:[-•*]+|\\d+[\\.)])\\s*", with: "<li>", options: .regularExpression)
        }
        let cleaned = trimmed
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "===TAKEAWAYS===", with: "")
        let lines = cleaned
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: "^(?:[-•*]+|\\d+[\\.)])\\s*", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter {
                let lower = $0.lowercased()
                return !$0.isEmpty &&
                    lower != "a retenir" &&
                    lower != "à retenir" &&
                    lower != "résumé" &&
                    lower != "resume" &&
                    lower != "html" &&
                    lower != "html:" &&
                    lower != "section 1 html:" &&
                    lower != "section 2 html:"
            }
        if lines.count > 1 {
            let items = lines.map { "<li>\($0)</li>" }.joined()
            return "<ul>\(items)</ul>"
        }
        if !trimmed.isEmpty {
            return "<ul><li>\(trimmed)</li></ul>"
        }
        return "<ul><li>—</li></ul>"
    }

    private func normalizeHeadingHTML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "<h1", with: "<h4")
            .replacingOccurrences(of: "</h1>", with: "</h4>")
            .replacingOccurrences(of: "<h2", with: "<h4")
            .replacingOccurrences(of: "</h2>", with: "</h4>")
            .replacingOccurrences(of: "<h3", with: "<h4")
            .replacingOccurrences(of: "</h3>", with: "</h4>")
    }

    private func stripHTMLTags(_ input: String) -> String {
        let noTags = input.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return noTags.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func escapeHTML(_ input: String) -> String {
        input
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func splitIntoSentences(_ input: String) -> [String] {
        let text = input.replacingOccurrences(of: "\n", with: " ")
        let separators = ".!?。！？"
        var sentences: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if separators.contains(ch) {
                let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { sentences.append(s) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }

    private func buildTakeawaysFallback(summaryHTML: String, sourceText: String, maxItems: Int = 8) -> String {
        let summaryPlain = stripHTMLTags(summaryHTML)
        var candidates = splitIntoSentences(summaryPlain)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count >= 20 }

        if candidates.count < 4 {
            let sourcePlain = sourceText
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            let extra = splitIntoSentences(String(sourcePlain.prefix(1500)))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count >= 20 }
            candidates.append(contentsOf: extra)
        }

        var unique: [String] = []
        var seen = Set<String>()
        for c in candidates {
            if seen.contains(c) { continue }
            seen.insert(c)
            unique.append(c)
            if unique.count >= maxItems { break }
        }

        if unique.isEmpty {
            return "<ul><li>—</li></ul>"
        }
        let items = unique.map { "<li>\(escapeHTML($0))</li>" }.joined()
        return "<ul>\(items)</ul>"
    }

    private func ensureTakeawaysHTML(takeawaysHTML: String, summaryHTML: String, sourceText: String) -> String {
        let plain = stripHTMLTags(takeawaysHTML).trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLi = takeawaysHTML.range(of: "<li", options: .caseInsensitive) != nil
        if plain.isEmpty || plain == "—" || !hasLi {
            return buildTakeawaysFromText(summaryHTML: summaryHTML, sourceText: sourceText, maxItems: 8)
        }
        return takeawaysHTML
    }

    private func buildTakeawaysFromText(summaryHTML: String, sourceText: String, maxItems: Int = 8) -> String {
        func pickSentences(from text: String, limit: Int) -> [String] {
            splitIntoSentences(text)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count >= 20 }
                .prefix(limit)
                .map { String($0) }
        }

        let summaryPlain = stripHTMLTags(summaryHTML)
        var candidates = pickSentences(from: summaryPlain, limit: maxItems)

        if candidates.count < 3 {
            let sourcePlain = sourceText
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            let extra = pickSentences(from: String(sourcePlain.prefix(2000)), limit: maxItems)
            candidates.append(contentsOf: extra)
        }

        var unique: [String] = []
        var seen = Set<String>()
        for c in candidates {
            if seen.contains(c) { continue }
            seen.insert(c)
            unique.append(c)
            if unique.count >= maxItems { break }
        }

        if unique.isEmpty {
            return "<ul><li>—</li></ul>"
        }
        let items = unique.map { "<li>\(escapeHTML($0))</li>" }.joined()
        return "<ul>\(items)</ul>"
    }

    private func stripCodeFences(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "```html", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Nettoie les marqueurs de section que le modèle AI peut inclure dans sa réponse
    private func cleanSectionMarkers(_ html: String) -> String {
        var result = html
        // Liste des patterns à supprimer (insensible à la casse)
        let patterns = [
            "SECTION\\s*1\\s*[-–—:]?\\s*SUMMARY\\s*:?",
            "SECTION\\s*2\\s*[-–—:]?\\s*KEY\\s*POINTS\\s*:?",
            "SECTION\\s*1\\s*[-–—:]?\\s*HTML\\s*:?",
            "SECTION\\s*2\\s*[-–—:]?\\s*HTML\\s*:?",
            "SECTION\\s*[12]\\s*[-–—:]?",
            "<p>\\s*SECTION\\s*1\\s*[-–—:]?\\s*SUMMARY\\s*:?\\s*</p>",
            "<p>\\s*SECTION\\s*2\\s*[-–—:]?\\s*KEY\\s*POINTS\\s*:?\\s*</p>",
            "<p>\\s*SECTION\\s*1\\s*[-–—:]?\\s*HTML\\s*:?\\s*</p>",
            "<p>\\s*SECTION\\s*2\\s*[-–—:]?\\s*HTML\\s*:?\\s*</p>",
            "^\\s*SUMMARY\\s*:?\\s*",
            "^\\s*KEY\\s*POINTS\\s*:?\\s*",
            "^\\s*RÉSUMÉ\\s*:?\\s*",
            "^\\s*RESUME\\s*:?\\s*",
            "^\\s*A\\s*RETENIR\\s*:?\\s*",
            "^\\s*À\\s*RETENIR\\s*:?\\s*",
            "^\\s*HTML\\s*:?\\s*$",
            "<p>\\s*HTML\\s*:?\\s*</p>",
            "<li>\\s*HTML\\s*:?\\s*</li>",
            "={3,}",
            "<strong>\\s*SECTION\\s*1\\s*[-–—:]?\\s*SUMMARY\\s*:?\\s*</strong>",
            "<strong>\\s*SECTION\\s*2\\s*[-–—:]?\\s*KEY\\s*POINTS\\s*:?\\s*</strong>",
            "<b>\\s*SECTION\\s*1\\s*[-–—:]?\\s*SUMMARY\\s*:?\\s*</b>",
            "<b>\\s*SECTION\\s*2\\s*[-–—:]?\\s*KEY\\s*POINTS\\s*:?\\s*</b>",
            "(?m)^\\s*#{1,6}\\s*HTML\\s*:?\\s*$",
            "(?m)^\\s*#{1,6}\\s*(SUMMARY|R[ÉE]SUM[ÉE]|KEY\\s*POINTS|A\\s*RETENIR|À\\s*RETENIR)\\s*:?\\s*$",
            "<p>\\s*#{1,6}\\s*HTML\\s*:?\\s*</p>",
            "<p>\\s*#{1,6}\\s*(SUMMARY|R[ÉE]SUM[ÉE]|KEY\\s*POINTS|A\\s*RETENIR|À\\s*RETENIR)\\s*:?\\s*</p>"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }
        // Supprimer les labels "HTML:" restants en début de ligne.
        if let htmlPrefixLineRegex = try? NSRegularExpression(
            pattern: "(?mi)^\\s*(?:section\\s*[12]\\s*[-–—:]?\\s*)?html\\s*:\\s*",
            options: []
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = htmlPrefixLineRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        // Supprimer "HTML:" juste après l'ouverture de <p> ou <li>.
        if let htmlPrefixPRegex = try? NSRegularExpression(
            pattern: "(?i)(<p\\b[^>]*>\\s*)(?:section\\s*[12]\\s*[-–—:]?\\s*)?html\\s*:\\s*",
            options: []
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = htmlPrefixPRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }
        if let htmlPrefixLiRegex = try? NSRegularExpression(
            pattern: "(?i)(<li\\b[^>]*>\\s*)(?:section\\s*[12]\\s*[-–—:]?\\s*)?html\\s*:\\s*",
            options: []
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = htmlPrefixLiRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }
        // Nettoyage agressif des titres markdown restants: "## ..." -> "..."
        if let markdownHeadingRegex = try? NSRegularExpression(pattern: "(?m)^\\s*#{1,6}\\s*", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = markdownHeadingRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        // Même nettoyage quand le markdown heading est encapsulé dans un <p>.
        if let pHeadingRegex = try? NSRegularExpression(pattern: "<p>\\s*#{1,6}\\s*(.*?)</p>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(result.startIndex..., in: result)
            result = pHeadingRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "<p>$1</p>")
        }
        // Supprimer les paragraphes devenus vides après nettoyage.
        if let emptyPRegex = try? NSRegularExpression(pattern: "<p>\\s*</p>", options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..., in: result)
            result = emptyPRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fixMojibake(_ raw: String) -> String {
        // Heuristic: UTF-8 misread as Latin-1 / Windows-1252
        if raw.contains("Ã") || raw.contains("Â") || raw.contains("�") || raw.contains("â") {
            if let data = raw.data(using: .windowsCP1252),
               let fixed = String(data: data, encoding: .utf8) {
                return fixed
            }
            if let data = raw.data(using: .isoLatin1),
               let fixed = String(data: data, encoding: .utf8) {
                return fixed
            }
        }
        return raw
    }
    
    /// Minimal proof-of-concept for direct article summarization and speech synthesis.
    private func summarizeAndSpeakArticle() async {
        do {
            // Extract main text of the article via JS
            let text = try await evaluateJavaScript("document.body.innerText") as? String ?? ""
            guard !text.isEmpty else {
                throw NSError(domain: "WebDrawerError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Impossible d'extraire le texte de l'article."])
            }
            
            let summary = try await summarizeWithAppleIntelligence(text: text)
            DispatchQueue.main.async {
                self.summaryText = summary
                self.showSummaryPanel = true
            }
        } catch {
            DispatchQueue.main.async {
                summaryError = error.localizedDescription
            }
        }
        DispatchQueue.main.async {
            isSummarizing = false
        }
    }
    
    private func evaluateJavaScript(_ script: String) async throws -> Any? {
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }
    
    private func summarizeWithAppleIntelligence(text: String) async throws -> String {
        let lang = LocalizationManager.shared.currentLanguage
        let targetName: String
        switch lang {
        case .french: targetName = "français"
        case .english: targetName = "English"
        case .spanish: targetName = "español"
        case .german: targetName = "Deutsch"
        case .italian: targetName = "italiano"
        case .portuguese: targetName = "português"
        case .japanese: targetName = "日本語"
        case .chinese: targetName = "中文"
        case .korean: targetName = "한국어"
        case .russian: targetName = "русский"
        }
        let systemPrompt = "You summarize web articles concisely and clearly in \(targetName). Always respond strictly in \(targetName)."
        let userPrompt = "Summarize this article. Respond strictly in \(targetName):\n\n\(text.prefix(3000))"
        
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                let session = LanguageModelSession(
                    model: model,
                    instructions: { systemPrompt }
                )
                let response = try await session.respond(to: userPrompt)
                let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty {
                    return content
                }
                throw NSError(domain: "WebDrawerError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Réponse vide de l'intelligence artificielle locale."])
            case .unavailable(let reason):
                throw NSError(domain: "WebDrawerError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Intelligence artificielle locale non disponible : \(reason)"])
            @unknown default:
                throw NSError(domain: "WebDrawerError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Intelligence artificielle locale non disponible."])
            }
        }
        #endif
        throw NSError(domain: "WebDrawerError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Intelligence artificielle locale non disponible sur cette version de macOS."])
    }
    

    private func stopSpeaking() {
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
    }

    @MainActor
    private func enforceYouTubeThemeFromAppAppearance() async {
        let shouldUseDarkTheme = (colorScheme == .dark)
        let darkFlag = shouldUseDarkTheme ? "true" : "false"
        let js = """
        (function () {
          try {
            var host = (location.hostname || '').toLowerCase();
            var isYouTubeHost = host.includes('youtube.com') || host.includes('youtube-nocookie.com');
            if (!isYouTubeHost) return false;

            var dark = \(darkFlag);

            // Préférence persistée côté YouTube (session WebView en cours)
            try {
              var currentPref = '';
              var m = document.cookie.match(/(?:^|;\\s*)PREF=([^;]*)/);
              if (m && m[1]) currentPref = decodeURIComponent(m[1]);
              var parts = currentPref ? currentPref.split('&').filter(Boolean) : [];
              var map = {};
              parts.forEach(function (p) {
                var i = p.indexOf('=');
                if (i > 0) map[p.slice(0, i)] = p.slice(i + 1);
              });
              var f6 = parseInt(map.f6 || '0', 10);
              if (isNaN(f6)) f6 = 0;
              if (dark) {
                f6 = f6 | 400;
              } else {
                f6 = f6 & ~400;
              }
              map.f6 = String(f6);
              var rebuilt = Object.keys(map).map(function (k) { return k + '=' + map[k]; }).join('&');
              document.cookie = 'PREF=' + encodeURIComponent(rebuilt) + '; path=/; domain=.youtube.com; max-age=31536000; SameSite=Lax';
            } catch (e) {}

            // Application immédiate du thème dans l'UI en cours
            if (dark) {
              document.documentElement.setAttribute('dark', '');
              document.documentElement.setAttribute('dark-theme', 'true');
              document.documentElement.classList.add('dark');
              document.documentElement.style.colorScheme = 'dark';
            } else {
              document.documentElement.removeAttribute('dark');
              document.documentElement.removeAttribute('dark-theme');
              document.documentElement.classList.remove('dark');
              document.documentElement.style.colorScheme = 'light';
            }

            return true;
          } catch (e) {
            return false;
          }
        })();
        """
        _ = try? await evaluateJavaScript(js)
    }

    @MainActor
    private func prepareWebViewForClosure() async {
        let pauseMediaJS = """
        (function () {
          try {
            var medias = document.querySelectorAll('video, audio');
            medias.forEach(function (el) { try { el.pause(); } catch (e) {} });
            var iframes = document.querySelectorAll('iframe');
            iframes.forEach(function (frame) {
              try {
                var src = (frame.src || '').toLowerCase();
                if (src.includes('youtube.com') || src.includes('youtu.be') || src.includes('youtube-nocookie.com')) {
                  var win = frame.contentWindow;
                  if (win) {
                    win.postMessage(JSON.stringify({ event: 'command', func: 'pauseVideo', args: [] }), '*');
                  }
                }
              } catch (e) {}
            });
          } catch (e) {}
          return true;
        })();
        """
        _ = try? await evaluateJavaScript(pauseMediaJS)
        webView.stopLoading()
        webView.loadHTMLString("<html><head></head><body></body></html>", baseURL: nil)
    }

    // MARK: - X Posting
    private func generateAndOpenXComposer() async {
        defer { DispatchQueue.main.async { self.isPostingToX = false } }
        do {
            // Extraire titre et URL courante
            let currentURL = self.url.absoluteString
            let titleJS = "document.title || ''"
            let pageTitle = (try await evaluateJavaScript(titleJS) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Extraire un bref résumé du contenu pour aider le prompt
            let text = (try? await evaluateJavaScript("document.body.innerText") as? String) ?? ""

            let tweet = try await generateTweetWithFoundationModels(pageTitle: pageTitle, pageText: text, articleURL: currentURL)
            openXComposer(text: tweet)
        } catch {
            DispatchQueue.main.async { self.postXError = error.localizedDescription }
        }
    }

    private func generateTweetWithFoundationModels(pageTitle: String, pageText: String, articleURL: String) async throws -> String {
        // Langue cible depuis les réglages
        let lang = LocalizationManager.shared.currentLanguage
        let targetName: String
        switch lang {
        case .french: targetName = "French"
        case .english: targetName = "English"
        case .spanish: targetName = "Spanish"
        case .german: targetName = "German"
        case .italian: targetName = "Italian"
        case .portuguese: targetName = "Portuguese"
        case .japanese: targetName = "Japanese"
        case .chinese: targetName = "Chinese"
        case .korean: targetName = "Korean"
        case .russian: targetName = "Russian"
        @unknown default: targetName = "English"
        }

        let system = "You write short X posts in \(targetName), clear and punchy. No emojis. No hashtags. Respond strictly in \(targetName). Return only the post text, without quotes."
        let user = "Title: \(pageTitle)\n\nExcerpt:\n\(pageText.prefix(1800))\n\nGenerate a short X post in \(targetName) that summarizes the article and makes people want to read it. Do not include the link; I will append it."
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                let session = LanguageModelSession(
                    model: model,
                    instructions: { system }
                )
                let response = try await session.respond(to: user)
                let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return buildTweetText(summary: trimmed.isEmpty ? nil : trimmed, title: pageTitle, url: articleURL)
            case .unavailable:
                return buildTweetText(summary: nil, title: pageTitle, url: articleURL)
            @unknown default:
                return buildTweetText(summary: nil, title: pageTitle, url: articleURL)
            }
        }
        #endif
        return buildTweetText(summary: nil, title: pageTitle, url: articleURL)
    }

    private func buildTweetText(summary: String?, title: String, url: String) -> String {
        // Construire un post concis, sinon fallback sur titre
        var base = summary?.isEmpty == false ? summary!.trimmingCharacters(in: .whitespacesAndNewlines) : title
        // Limiter à ~240 caractères pour garder de la marge pour l'URL, X auto-raccourcit les liens (~23 caractères)
        let limit = 1000
        if base.count > limit {
            base = String(base.prefix(limit - 1)) + "…"
        }
        let composed = base + " " + url
        // X autorise ~280; on coupe si besoin par sécurité
        if composed.count > 1000 {
            let extra = composed.count - 1000
            if base.count > extra {
                let newBase = String(base.dropLast(extra + 1)) + "…"
                return newBase + " " + url
            }
        }
        return composed
    }

    private func openXComposer(text: String) {
        // Utilise l'intent Web (x.com/intent/post) qui ouvre le composer côté navigateur/app
        // Encodage du texte
        let allowed = CharacterSet.urlQueryAllowed
        let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        if let intentURL = URL(string: "https://x.com/intent/post?text=\(encoded)") {
            #if os(macOS)
            NSWorkspace.shared.open(intentURL)
            #endif
        }
    }
}

private struct WebViewWrapper: NSViewRepresentable {
    enum WebViewAction {
        case shareX
        case summarizeAI
        case openOriginalArticle
        case addNote(String)
    }

    let webView: WKWebView
    let url: URL
    let onPageLoad: (() -> Void)?
    let onAction: ((WebViewAction) -> Void)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPageLoad: onPageLoad, onAction: onAction)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        if let targetURL = httpsOnlyURL(from: url) {
            webView.load(URLRequest(url: targetURL))
        } else {
            NSWorkspace.shared.open(url)
        }
        return webView
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url != url {
            if let targetURL = httpsOnlyURL(from: url) {
                nsView.load(URLRequest(url: targetURL))
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func httpsOnlyURL(from url: URL) -> URL? {
        if url.scheme == "https" { return url }
        if url.scheme == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            return components.url
        }
        return nil
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let onPageLoad: (() -> Void)?
        let onAction: ((WebViewAction) -> Void)?

        init(onPageLoad: (() -> Void)?, onAction: ((WebViewAction) -> Void)?) {
            self.onPageLoad = onPageLoad
            self.onAction = onAction
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let navType = navigationAction.navigationType
            let isUserInitiated = navType == .linkActivated || navType == .formSubmitted || navType == .formResubmitted
            if let url = navigationAction.request.url, url.scheme == "flux-action" {
                switch url.host {
                case "share-x":
                    onAction?(.shareX)
                case "summary-ai":
                    onAction?(.summarizeAI)
                case "open-original":
                    onAction?(.openOriginalArticle)
                case "add-note":
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    let text = components?.queryItems?.first(where: { $0.name == "text" })?.value ?? ""
                    onAction?(.addNote(text))
                default:
                    break
                }
                decisionHandler(.cancel)
                return
            }
            // Intercepter les liens vers x.com/intent pour les ouvrir dans le navigateur externe
            if let url = navigationAction.request.url,
               url.host?.contains("x.com") == true || url.host?.contains("twitter.com") == true {
                if isUserInitiated {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }
            // Bloquer les popups et navigations non sollicitées vers une nouvelle fenêtre
            if navigationAction.targetFrame == nil {
                if let url = navigationAction.request.url, isUserInitiated {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }
            if let url = navigationAction.request.url, url.scheme == "http" {
                if isUserInitiated {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let adBlockerScript = """
            (function() {
                // Masque seulement les iframes très probablement publicitaires et les bannières classiques
                var style = document.createElement('style');
                style.innerHTML = `
                    iframe[src*="doubleclick" i],
                    iframe[src*="googlesyndication" i],
                    iframe[src*="adservice" i],
                    .ad-banner, .adsbygoogle, .google-ad, #ads, #ad-banner {
                        display: none !important; visibility: hidden !important;
                    }
                `;
                document.head.appendChild(style);
            })();
            """
            let youtubeCinemaScript = """
            (function () {
              try {
                var host = (location.hostname || '').toLowerCase();
                var isYoutubeHost = host.includes('youtube.com') || host.includes('youtube-nocookie.com');
                if (!isYoutubeHost) return false;
            
                function isWatchPage() {
                  var path = location.pathname || '';
                  return path === '/watch' || path.indexOf('/watch') === 0;
                }
            
                function isAlreadyCinemaMode() {
                  var flexy = document.querySelector('ytd-watch-flexy');
                  return !!(flexy && (flexy.hasAttribute('theater') || flexy.getAttribute('theater') !== null));
                }
            
                function enableCinemaModeIfNeeded() {
                  if (!isWatchPage() || isAlreadyCinemaMode()) return false;
                  var btn = document.querySelector('.ytp-size-button');
                  if (!btn) return false;
                  btn.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                  return true;
                }
            
                function applyWithRetry() {
                  if (!isWatchPage()) return;
                  var tries = 0;
                  var maxTries = 30;
                  var timer = setInterval(function () {
                    tries += 1;
                    if (isAlreadyCinemaMode() || enableCinemaModeIfNeeded() || tries >= maxTries) {
                      clearInterval(timer);
                    }
                  }, 300);
                }
            
                applyWithRetry();
            
                if (!window.__fluxYouTubeCinemaHooked) {
                  window.__fluxYouTubeCinemaHooked = true;
                  document.addEventListener('yt-navigate-finish', function () {
                    setTimeout(applyWithRetry, 120);
                  }, true);
                }
            
                return true;
              } catch (e) {
                return false;
              }
            })();
            """
            Task {
                _ = try? await webView.evaluateJavaScript(adBlockerScript)
                _ = try? await webView.evaluateJavaScript(youtubeCinemaScript)
            }
            onPageLoad?()
        }
    }
}

private struct LeadingRoundedRectangle: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = cornerRadius
        var path = Path()
        // Start top-right corner (square)
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Line to top-left corner's start of curve
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        // Quad curve for top-left corner
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + radius), control: CGPoint(x: rect.minX, y: rect.minY))
        // Line down left edge to bottom-left corner's start of curve
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        // Quad curve for bottom-left corner
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
        // Line to bottom-right corner (square)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // Close path back to start point
        path.closeSubpath()
        return path
    }
}

private struct CrystallineRefractionLoader: View {
    let tint: Color
    @State private var startDate = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startDate)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let gridSize = 15.0
                let spacing = min(size.width, size.height) / (gridSize - 1.0)
                let globalSpeed = 0.5
                let waveRadius = (elapsed * 28.0 * globalSpeed).truncatingRemainder(dividingBy: min(size.width, size.height) * 1.2)
                let waveWidth = min(size.width, size.height) * 0.42

                for row in 0..<Int(gridSize) {
                    for col in 0..<Int(gridSize) {
                        let baseX = Double(col) * spacing
                        let baseY = Double(row) * spacing
                        let dxCenter = baseX - center.x
                        let dyCenter = baseY - center.y
                        let dist = hypot(dxCenter, dyCenter)
                        let distToWave = abs(dist - waveRadius)

                        var displacement = 0.0
                        if distToWave < waveWidth / 2.0 {
                            let wavePhase = (distToWave / (waveWidth / 2.0)) * .pi
                            let signal = max(0.0, sin(wavePhase))
                            displacement = easeInOutCubic(signal) * (min(size.width, size.height) * 0.055)
                        }

                        let angle = atan2(dyCenter, dxCenter)
                        let finalX = baseX + cos(angle) * displacement
                        let finalY = baseY + sin(angle) * displacement
                        let progress = min(1.0, abs(displacement) / (min(size.width, size.height) * 0.055))
                        let opacity = 0.2 + progress * 0.8
                        let dotSize = 1.2 + progress * 2.0

                        let rect = CGRect(
                            x: finalX - dotSize / 2.0,
                            y: finalY - dotSize / 2.0,
                            width: dotSize,
                            height: dotSize
                        )
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(tint.opacity(opacity))
                        )
                    }
                }
            }
        }
        .onAppear {
            startDate = Date()
        }
    }

    private func easeInOutCubic(_ x: Double) -> Double {
        if x < 0.5 {
            return 4.0 * x * x * x
        }
        return 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0
    }
}

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)

        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }
        return path
    }
}
#endif

#if os(iOS)
import SwiftUI
import Combine
import WebKit
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

struct WebDrawer: View {
    @Environment(FeedService.self) private var feedService
    @Environment(\.colorScheme) private var colorScheme
    let url: URL
    let startInReaderMode: Bool
    let forceAISummary: Bool
    let forceReaderFirst: Bool
    let hideReaderSidebar: Bool
    let useMonochromeDefaultTheme: Bool
    let showCloseButton: Bool
    let onClose: () -> Void
    private let lm = LocalizationManager.shared
    @StateObject private var state = IOSArticleWebState()
    @State private var readerMode: Bool
    @State private var showReaderMask: Bool
    @State private var isApplyingReaderAI = false
    @State private var readerPhraseIndex = 0
    @State private var readerTicker = Timer.publish(every: 1.4, on: .main, in: .common).autoconnect()
    @State private var hasStartedReaderPipeline = false
    @State private var readerEntities: [String] = []
    @State private var readerTags: [String] = []
    @State private var readerSourceName: String = ""
    @AppStorage("reader.openArticleInReaderFirst") private var openArticleInReaderFirst: Bool = true

    init(
        url: URL,
        startInReaderMode: Bool = false,
        forceAISummary: Bool = false,
        forceReaderFirst: Bool = false,
        hideReaderSidebar: Bool = false,
        useMonochromeDefaultTheme: Bool = false,
        showCloseButton: Bool = true,
        onClose: @escaping () -> Void
    ) {
        self.url = url
        self.startInReaderMode = startInReaderMode
        self.forceAISummary = forceAISummary
        self.forceReaderFirst = forceReaderFirst
        self.hideReaderSidebar = hideReaderSidebar
        self.useMonochromeDefaultTheme = useMonochromeDefaultTheme
        self.showCloseButton = showCloseButton
        self.onClose = onClose
        let shouldStartReaderOnIPad = UIDevice.current.userInterfaceIdiom == .pad && startInReaderMode
        _readerMode = State(initialValue: shouldStartReaderOnIPad)
        _showReaderMask = State(initialValue: shouldStartReaderOnIPad)
    }

    var body: some View {
        ZStack {
            IOSArticleWebView(
                url: url,
                state: state,
                onPageLoad: handlePageLoad,
                onReaderAction: handleReaderAction
            )
                .ignoresSafeArea()
                .opacity(readerMode && showReaderMask ? 0.08 : 1)

            if readerMode && showReaderMask {
                readerLoadingOverlay
            }
        }
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .top) {
            topBar
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .onReceive(readerTicker) { _ in
            guard readerMode, showReaderMask, !readerPhrases.isEmpty else { return }
            readerPhraseIndex = (readerPhraseIndex + 1) % readerPhrases.count
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            if showCloseButton {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
            }

            Text(state.title.isEmpty ? "Article" : state.title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: toggleReaderMode) {
                Image(systemName: state.isShowingReaderDocument ? "doc.richtext" : "doc.text.viewfinder")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
            }

            Button(action: {
                let target = state.currentURL ?? url
                UIApplication.shared.open(target)
            }) {
                Image(systemName: "safari")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if state.isLoading {
                ProgressView(value: state.progress)
                    .progressViewStyle(.linear)
            }
            HStack(spacing: 20) {
                Button(action: { state.webView?.goBack() }) {
                    Image(systemName: "chevron.backward")
                }
                .disabled(!state.canGoBack)

                Button(action: { state.webView?.goForward() }) {
                    Image(systemName: "chevron.forward")
                }
                .disabled(!state.canGoForward)

                Button(action: {
                    if state.isLoading {
                        state.webView?.stopLoading()
                    } else {
                        state.webView?.reload()
                    }
                }) {
                    Image(systemName: state.isLoading ? "xmark" : "arrow.clockwise")
                }

                ShareLink(item: state.currentURL ?? url) {
                    Image(systemName: "square.and.arrow.up")
                }

                Button(action: {
                    UIPasteboard.general.url = state.currentURL ?? url
                }) {
                    Image(systemName: "link")
                }
            }
                .font(.system(size: 17, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
    }

    private var readerLoadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .tint(.primary)

            Text(isApplyingReaderAI ? LocalizationManager.shared.localizedString(.aiCreatingSummary) : "Chargement du mode lecteur…")
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)

            if !readerPhrases.isEmpty {
                Text(readerPhrases[readerPhraseIndex % readerPhrases.count])
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).opacity(0.96))
    }

    private var readerPhrases: [String] {
        lm.loadingPhrases()
    }

    private var shouldUseAIReader: Bool {
        if forceAISummary { return true }
        if forceReaderFirst { return false }
        return !openArticleInReaderFirst
    }

    private func handlePageLoad(_ loadedURL: URL?) {
        guard readerMode, !hasStartedReaderPipeline else { return }
        guard !state.isShowingReaderDocument else { return }
        let current = loadedURL ?? state.currentURL ?? url
        guard current.scheme?.lowercased() != "about" else { return }
        hasStartedReaderPipeline = true
        showReaderMask = true

        Task {
            await presentReaderDocument()
        }
    }

    private func presentReaderDocument(forceAISummaryOverride: Bool? = nil) async {
        do {
            try await ensureReadabilityInjected()
            let article = try await extractArticle()
            let resolvedTitle = resolvedReaderTitle(from: article.title)
            let resolvedImages = resolvedReaderImages(lead: article.lead, images: article.images)
            let sourceName = getSourceFeedName()
            let shouldUseAISummary = forceAISummaryOverride ?? shouldUseAIReader

            await MainActor.run {
                if !resolvedTitle.isEmpty {
                    state.title = resolvedTitle
                }
                readerSourceName = sourceName
            }

            let bodyHTML: String
            let metadata: (entities: [String], tags: [String])
            if shouldUseAISummary {
                await MainActor.run { isApplyingReaderAI = true }
                async let metadataTask = extractEntitiesAndTags(title: resolvedTitle, text: article.text)
                do {
                    bodyHTML = try await summarizeForReaderHTML(title: resolvedTitle, text: article.text)
                    metadata = await metadataTask
                } catch {
                    bodyHTML = buildClassicReaderBodyHTML(from: article.text)
                    metadata = await metadataTask
                }
            } else {
                bodyHTML = buildClassicReaderBodyHTML(from: article.text)
                metadata = ([], [])
            }

            await MainActor.run {
                readerEntities = metadata.entities
                readerTags = metadata.tags
            }

            let html = buildReaderDocumentHTML(
                title: resolvedTitle,
                images: resolvedImages,
                bodyHTML: bodyHTML,
                sourceName: sourceName,
                entities: metadata.entities,
                tags: metadata.tags,
                showSummaryButton: !shouldUseAISummary
            )

            await MainActor.run {
                state.loadReaderHTML(html, baseURL: url)
            }
            await MainActor.run {
                isApplyingReaderAI = false
                showReaderMask = false
            }
        } catch {
            await MainActor.run {
                isApplyingReaderAI = false
                showReaderMask = false
            }
        }
    }

    private func toggleReaderMode() {
        if state.isShowingReaderDocument {
            exitReaderMode()
            return
        }

        readerMode = true
        showReaderMask = true
        hasStartedReaderPipeline = true
        Task {
            await presentReaderDocument()
        }
    }

    private func exitReaderMode() {
        readerMode = false
        showReaderMask = false
        isApplyingReaderAI = false
        hasStartedReaderPipeline = false
        readerEntities = []
        readerTags = []
        readerSourceName = ""
        state.isShowingReaderDocument = false
        state.webView?.load(URLRequest(url: url))
    }

    private func handleReaderAction(_ action: IOSReaderAction) {
        switch action {
        case .openOriginalArticle:
            UIApplication.shared.open(url)
        case .summarizeAI:
            readerMode = true
            showReaderMask = true
            hasStartedReaderPipeline = true
            Task {
                await presentReaderDocument(forceAISummaryOverride: true)
            }
        }
    }

    private func ensureReadabilityInjected() async throws {
        let hasReadability = (try? await state.evaluateJavaScript("!!window.Readability") as? Bool) ?? false
        guard !hasReadability else { return }
        guard
            let jsURL = Bundle.main.url(forResource: "Readability", withExtension: "js"),
            let source = try? String(contentsOf: jsURL, encoding: .utf8)
        else {
            throw NSError(domain: "IOSReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Readability introuvable."])
        }
        _ = try await state.evaluateJavaScript(source)
        try? await Task.sleep(nanoseconds: 200_000_000)
    }

    private func extractArticle() async throws -> IOSReaderExtractedArticle {
        let script = """
        (function(){
          try {
            var article = (new Readability(document.cloneNode(true))).parse();
            var title = (article && article.title) ? article.title : (document.title || '');
            var text = (article && article.textContent) ? article.textContent : '';
            var lead = (article && (article.lead_image_url || article.image)) ? (article.lead_image_url || article.image) : '';
            var images = [];
            var seen = {};

            function pushImage(src){
              if(!src || !src.trim()) return;
              if(seen[src]) return;
              seen[src] = true;
              images.push(src);
            }

            if(lead && lead.trim()){
              pushImage(lead.trim());
            }

            if(article && article.content){
              var container = document.createElement('div');
              container.innerHTML = article.content;
              container.querySelectorAll('img').forEach(function(img){
                var src = img.src || img.getAttribute('data-src') || img.getAttribute('data-lazy-src') || '';
                if(!src || !src.trim()) return;
                var width = img.naturalWidth || parseInt(img.getAttribute('width') || '0', 10);
                var height = img.naturalHeight || parseInt(img.getAttribute('height') || '0', 10);
                if((width > 0 && width < 140) || (height > 0 && height < 140)) return;
                var lower = src.toLowerCase();
                if(lower.indexOf('logo') >= 0 || lower.indexOf('icon') >= 0 || lower.indexOf('avatar') >= 0 || lower.indexOf('tracking') >= 0 || lower.indexOf('pixel') >= 0) return;
                pushImage(src.trim());
              });
            }

            if((!text || text.trim().length < 200) && document.body){
              text = (document.body.innerText || '').trim();
            }

            if((!lead || !lead.trim()) && images.length > 0){
              lead = images[0];
            }

            images = images.slice(0, 6);
            return JSON.stringify({ title: title || '', text: text || '', lead: lead || '', images: images });
          } catch (error) {
            return JSON.stringify({ title: document.title || '', text: (document.body && document.body.innerText) || '', lead: '', images: [] });
          }
        })();
        """

        let raw = try await state.evaluateJavaScript(script) as? String ?? "{}"
        let data = raw.data(using: .utf8) ?? Data()
        return (try? JSONDecoder().decode(IOSReaderExtractedArticle.self, from: data))
            ?? IOSReaderExtractedArticle(title: state.title, text: "", lead: "", images: [])
    }

    private func summarizeForReaderHTML(title: String, text: String) async throws -> String {
        let language = readerLanguageDescriptor()
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else {
            throw NSError(domain: "IOSReader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Contenu vide."])
        }
        let delimiter = "\n===TAKEAWAYS===\n"

        let systemPrompt = """
        You are an editor.
        Clean the article, remove navigation and noise, and produce output strictly in \(language.targetName).
        Return HTML only, with no Markdown and no code fences.
        """
        let userPrompt = """
        Title: \(title)

        Article:
        \(cleanedText.prefix(10000))

        Return exactly two sections separated by this delimiter:
        ===TAKEAWAYS===

        Section 1 before the delimiter:
        only 2 or 3 <p> summary paragraphs.

        Section 2 after the delimiter:
        only one <ul> with 4 to 7 <li> key points.

        The response must be strictly in \(language.targetName).
        """

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                let session = LanguageModelSession(
                    model: model,
                    instructions: { systemPrompt }
                )
                let response = try await session.respond(to: userPrompt)
                let content = stripCodeFences(response.content.trimmingCharacters(in: .whitespacesAndNewlines))
                guard !content.isEmpty else {
                    throw NSError(domain: "IOSReader", code: 3, userInfo: [NSLocalizedDescriptionKey: "Réponse vide de l'intelligence artificielle locale."])
                }
                let parts = content.components(separatedBy: delimiter)
                let summaryHTML = normalizeSimpleSummaryHTML(parts.first ?? "")
                let takeawaysHTML = normalizeSimpleTakeawaysHTML(
                    parts.count > 1 ? parts[1] : "",
                    sourceText: cleanedText
                )
                return """
                <section class="reader-section reader-summary">
                  <h2>\(escapeHTML(language.summaryHeading))</h2>
                  \(summaryHTML)
                </section>
                <section class="reader-section reader-takeaways">
                  <h2>\(escapeHTML(language.takeawaysHeading))</h2>
                  \(takeawaysHTML)
                </section>
                """
            case .unavailable(let reason):
                throw NSError(domain: "IOSReader", code: 4, userInfo: [NSLocalizedDescriptionKey: "\(reason)"])
            @unknown default:
                throw NSError(domain: "IOSReader", code: 5, userInfo: [NSLocalizedDescriptionKey: "Intelligence artificielle locale indisponible."])
            }
        }
        #endif

        throw NSError(domain: "IOSReader", code: 6, userInfo: [NSLocalizedDescriptionKey: "Intelligence artificielle locale indisponible."])
    }

    private func buildClassicReaderBodyHTML(from text: String) -> String {
        let language = readerLanguageDescriptor()
        let paragraphs = text
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 40 }

        let paragraphHTML = paragraphs
            .map { "<p>\(escapeHTML($0))</p>" }
            .joined()

        return """
        <section class="reader-section reader-summary">
          <h2>\(escapeHTML(language.articleHeading))</h2>
          \(paragraphHTML)
        </section>
        """
    }

    private func buildReaderDocumentHTML(
        title: String,
        images: [String],
        bodyHTML: String,
        sourceName: String,
        entities: [String],
        tags: [String],
        showSummaryButton: Bool
    ) -> String {
        let leadHTML = buildImageSliderHTML(images: images)
        let sidebarHTML = buildSidebarHTML(
            source: sourceName,
            entities: entities,
            tags: tags,
            showSummaryButton: showSummaryButton
        )
        let css = readerCSS()

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <style>\(css)</style>
        </head>
        <body>
          <div class="reader-outer">
            <div class="reader-container">
              <article class="reader">
                <h1>\(escapeHTML(title))</h1>
                \(leadHTML)
                \(bodyHTML)
              </article>
              \(sidebarHTML)
            </div>
          </div>
        </body>
        </html>
        """
    }

    private func resolvedReaderTitle(from extractedTitle: String) -> String {
        let candidate = extractedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.isEmpty { return candidate }
        let fallback = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty { return fallback }
        return "Article"
    }

    private func resolvedReaderImages(lead: String, images: [String]) -> [String] {
        var all: [String] = []
        if let normalizedLead = normalizeURLString(lead) {
            all.append(normalizedLead)
        }
        for image in images {
            guard let normalized = normalizeURLString(image), !all.contains(normalized) else { continue }
            all.append(normalized)
        }
        return all
    }

    private func normalizeURLString(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let absolute = URL(string: value, relativeTo: url)?.absoluteURL.absoluteString {
            return absolute
        }
        return nil
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func stripCodeFences(_ value: String) -> String {
        value
            .replacingOccurrences(of: "```html", with: "")
            .replacingOccurrences(of: "```HTML", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeSimpleSummaryHTML(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.contains("<p") {
            return cleaned
        }

        let paragraphs = cleaned
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if paragraphs.isEmpty {
            return "<p>\(escapeHTML(cleaned))</p>"
        }

        return paragraphs.map { "<p>\(escapeHTML($0))</p>" }.joined()
    }

    private func normalizeSimpleTakeawaysHTML(_ raw: String, sourceText: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.contains("<li") {
            return cleaned
        }

        let lines = cleaned
            .components(separatedBy: CharacterSet.newlines)
            .map {
                $0
                    .replacingOccurrences(of: "^(?:[-•*]+|\\d+[\\.)])\\s*", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        if !lines.isEmpty {
            return "<ul>\(lines.map { "<li>\(escapeHTML($0))</li>" }.joined())</ul>"
        }

        return buildTakeawaysFallback(from: sourceText)
    }

    private func buildTakeawaysFallback(from text: String) -> String {
        let candidates = splitIntoSentences(text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 24 }
            .prefix(6)

        if candidates.isEmpty {
            return "<ul><li>—</li></ul>"
        }

        return "<ul>\(candidates.map { "<li>\(escapeHTML($0))</li>" }.joined())</ul>"
    }

    private func splitIntoSentences(_ input: String) -> [String] {
        let text = input.replacingOccurrences(of: "\n", with: " ")
        let separators = ".!?。！？"
        var sentences: [String] = []
        var current = ""

        for character in text {
            current.append(character)
            if separators.contains(character) {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    sentences.append(sentence)
                }
                current = ""
            }
        }

        let remainder = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty {
            sentences.append(remainder)
        }

        return sentences
    }

    private func readerCSS() -> String {
        let isDark = colorScheme == .dark
        let background = isDark ? "#151515" : "#F5F7FB"
        let text = isDark ? "#F2F2F2" : "#20242B"
        let secondary = isDark ? "rgba(255,255,255,0.68)" : "rgba(32,36,43,0.58)"
        let sectionBorder = isDark ? "rgba(255,255,255,0.10)" : "rgba(43,52,64,0.14)"
        let summaryBackground = isDark ? "rgba(35,35,35,0.84)" : "rgba(255,255,255,0.88)"
        let takeawaysBackground = isDark ? "rgba(29,29,29,0.86)" : "rgba(243,248,255,0.88)"
        let sidebarBackground = isDark ? "rgba(36,36,36,0.86)" : "rgba(255,255,255,0.78)"
        let pillBackground = isDark ? "rgba(140,182,255,0.18)" : "rgba(62,109,168,0.12)"
        let buttonBackground = isDark ? "rgba(255,255,255,0.10)" : "rgba(32,36,43,0.08)"
        let shadow = isDark ? "0 12px 38px rgba(0,0,0,0.28)" : "0 12px 38px rgba(31,42,55,0.10)"

        return """
        :root { color-scheme: \(isDark ? "dark" : "light"); }
        html, body {
          margin: 0;
          padding: 0;
          background: \(background);
          color: \(text);
          font: 18px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
          -webkit-font-smoothing: antialiased;
        }
        .reader-outer { width: 100%; }
        .reader-container {
          position: relative;
          max-width: 1200px;
          margin: 0 auto;
          padding: 72px 316px 54px 24px;
          box-sizing: border-box;
        }
        .reader {
          max-width: 760px;
          width: 100%;
          margin: -14px auto 0;
          line-height: 1.7;
        }
        .reader h1 {
          margin: 0 0 16px;
          font-size: 32px;
          line-height: 1.16;
          letter-spacing: -0.03em;
        }
        .reader p,
        .reader li {
          font-size: 18px;
          line-height: 1.74;
          color: \(text);
        }
        .reader p { margin: 0 0 1em; }
        .reader-section {
          width: 100%;
          margin: 22px 0;
          padding: 18px 20px;
          border-radius: 18px;
          border: 1px solid \(sectionBorder);
          box-sizing: border-box;
          box-shadow: \(shadow);
        }
        .reader-summary { background: \(summaryBackground); }
        .reader-takeaways { background: \(takeawaysBackground); }
        .reader-section h2 {
          margin: 0 0 14px;
          font-size: 12px;
          letter-spacing: 0.10em;
          text-transform: uppercase;
          font-weight: 700;
          color: \(secondary);
        }
        .reader-takeaways ul { margin: 0; padding-left: 20px; }
        .reader-takeaways li + li { margin-top: 8px; }
        .reader-slider-wrapper {
          position: relative;
          width: 100%;
          margin: 28px 0 24px;
          border-radius: 18px;
          overflow: hidden;
          box-shadow: \(shadow);
          background: \(summaryBackground);
        }
        .reader-slider { position: relative; width: 100%; transition: height 0.35s cubic-bezier(0.4,0,0.2,1); }
        .reader-slider-track { display: flex; transition: transform 0.35s cubic-bezier(0.4,0,0.2,1); align-items: flex-start; }
        .reader-slider-slide { flex: 0 0 100%; width: 100%; opacity: 0.4; transition: opacity 0.35s ease; }
        .reader-slider-slide.active { opacity: 1; }
        .reader-slider-slide img { width: 100%; height: auto; display: block; margin: 0; border-radius: 0; }
        .reader-slider-btn {
          position: absolute;
          top: 50%;
          transform: translateY(-50%);
          width: 40px;
          height: 40px;
          border: none;
          border-radius: 999px;
          background: \(buttonBackground);
          color: \(text);
          backdrop-filter: blur(18px);
          cursor: pointer;
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 2;
        }
        .reader-slider-btn.prev { left: 12px; }
        .reader-slider-btn.next { right: 12px; }
        .reader-slider-btn svg { width: 20px; height: 20px; stroke: currentColor; }
        .reader-slider-dots { display: flex; justify-content: center; gap: 6px; margin-top: 12px; }
        .reader-slider-dot {
          width: 8px;
          height: 8px;
          border-radius: 999px;
          background: \(secondary);
          opacity: 0.4;
          cursor: pointer;
        }
        .reader-slider-dot.active { opacity: 1; transform: scale(1.15); }
        .reader-sidebar {
          width: 260px;
          position: fixed;
          top: 72px;
          right: max(24px, calc((100vw - 1200px) / 2 + 24px));
          max-height: calc(100vh - 96px);
          overflow: auto;
          padding: 16px;
          border-radius: 18px;
          box-sizing: border-box;
          background: \(sidebarBackground);
          border: 1px solid \(sectionBorder);
          box-shadow: \(shadow);
          backdrop-filter: blur(24px) saturate(180%);
        }
        .reader-sidebar .section { margin-bottom: 16px; }
        .reader-sidebar h4 {
          margin: 0 0 8px;
          font-size: 10px;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: \(secondary);
        }
        .reader-sidebar .source {
          font-size: 14px;
          font-weight: 600;
        }
        .reader-sidebar .entity {
          display: flex;
          gap: 8px;
          margin-bottom: 8px;
          font-size: 12px;
        }
        .reader-sidebar .entity-type {
          font-size: 10px;
          color: \(secondary);
        }
        .reader-sidebar .tags { display: flex; flex-wrap: wrap; gap: 6px; }
        .reader-sidebar .tag {
          display: inline-flex;
          align-items: center;
          padding: 4px 9px;
          border-radius: 999px;
          background: \(pillBackground);
          font-size: 11px;
        }
        .reader-sidebar .ai-disclaimer {
          margin: 0;
          font-size: 11px;
          line-height: 1.45;
          color: \(secondary);
        }
        .reader-sidebar button {
          width: 100%;
          margin-top: 10px;
          padding: 10px 12px;
          border-radius: 12px;
          border: 1px solid \(sectionBorder);
          background: \(buttonBackground);
          color: \(text);
          font: 600 12px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
        }
        @media (max-width: 900px) {
          .reader-container {
            padding: 56px 16px 48px;
          }
          .reader-sidebar {
            position: static;
            width: 100%;
            max-height: none;
            margin-top: 24px;
          }
        }
        """
    }

    private func buildImageSliderHTML(images: [String]) -> String {
        guard !images.isEmpty else { return "" }

        if images.count == 1, let image = images.first {
            return "<img src=\"\(escapeHTML(image))\" alt=\"\" loading=\"lazy\" style=\"width:100%;display:block;border-radius:18px;box-shadow:0 12px 38px rgba(0,0,0,0.16);margin:28px 0 24px;\">"
        }

        let slidesHTML = images.enumerated().map { index, image in
            "<div class=\"reader-slider-slide\(index == 0 ? " active" : "")\"><img src=\"\(escapeHTML(image))\" alt=\"\" loading=\"lazy\"></div>"
        }.joined()

        let dotsHTML = images.enumerated().map { index, _ in
            "<span class=\"reader-slider-dot\(index == 0 ? " active" : "")\" data-index=\"\(index)\"></span>"
        }.joined()

        return """
        <div class="reader-slider-wrapper">
          <div class="reader-slider">
            <div class="reader-slider-track">
              \(slidesHTML)
            </div>
            <button class="reader-slider-btn prev" type="button" aria-label="Image précédente">
              <svg viewBox="0 0 24 24" fill="none"><polyline points="15 18 9 12 15 6"></polyline></svg>
            </button>
            <button class="reader-slider-btn next" type="button" aria-label="Image suivante">
              <svg viewBox="0 0 24 24" fill="none"><polyline points="9 18 15 12 9 6"></polyline></svg>
            </button>
          </div>
          <div class="reader-slider-dots">\(dotsHTML)</div>
        </div>
        <script>
        (function(){
          var wrapper = document.querySelector('.reader-slider-wrapper');
          if (!wrapper) return;
          var slider = wrapper.querySelector('.reader-slider');
          var track = wrapper.querySelector('.reader-slider-track');
          var slides = Array.from(wrapper.querySelectorAll('.reader-slider-slide'));
          var dots = Array.from(wrapper.querySelectorAll('.reader-slider-dot'));
          var prev = wrapper.querySelector('.reader-slider-btn.prev');
          var next = wrapper.querySelector('.reader-slider-btn.next');
          var current = 0;

          function updateHeight() {
            var activeImage = slides[current] && slides[current].querySelector('img');
            if (!activeImage) return;
            if (activeImage.complete && activeImage.naturalHeight > 0) {
              slider.style.height = activeImage.offsetHeight + 'px';
            } else {
              activeImage.addEventListener('load', updateHeight, { once: true });
            }
          }

          function update() {
            track.style.transform = 'translateX(-' + (current * 100) + '%)';
            slides.forEach(function(slide, index){ slide.classList.toggle('active', index === current); });
            dots.forEach(function(dot, index){ dot.classList.toggle('active', index === current); });
            updateHeight();
          }

          prev.addEventListener('click', function(){ current = (current - 1 + slides.length) % slides.length; update(); });
          next.addEventListener('click', function(){ current = (current + 1) % slides.length; update(); });
          dots.forEach(function(dot, index){
            dot.addEventListener('click', function(){ current = index; update(); });
          });

          window.addEventListener('resize', updateHeight);
          update();
        })();
        </script>
        """
    }

    private func buildSidebarHTML(source: String, entities: [String], tags: [String], showSummaryButton: Bool) -> String {
        let entitiesHTML = entities.map { entity in
            let parsed = parseEntity(entity)
            return """
            <div class="entity">
              <span>\(iconForEntityType(parsed.type))</span>
              <div>
                <div>\(escapeHTML(parsed.name))</div>
                <div class="entity-type">\(escapeHTML(parsed.type))</div>
              </div>
            </div>
            """
        }.joined()

        let tagsHTML = tags.map { "<span class=\"tag\">\(escapeHTML($0))</span>" }.joined()
        let summaryButtonHTML = showSummaryButton ? """
        <button type="button" onclick="window.location.href='flux-action://summary-ai'">Résumé (Intelligence artificielle locale)</button>
        """ : ""

        return """
        <aside class="reader-sidebar">
          <div class="section">
            <h4>Source</h4>
            <div class="source">\(escapeHTML(source))</div>
          </div>
          \(entities.isEmpty ? "" : "<div class=\"section\"><h4>Dans cet article</h4>\(entitiesHTML)</div>")
          \(tags.isEmpty ? "" : "<div class=\"section\"><h4>Tags</h4><div class=\"tags\">\(tagsHTML)</div></div>")
          <div class="section">
            <p class="ai-disclaimer">\(escapeHTML(localizedReaderAIDisclaimerText()))</p>
          </div>
          <button type="button" onclick="window.location.href='flux-action://open-original'">\(escapeHTML(localizedOpenOriginalArticleButtonText()))</button>
          \(summaryButtonHTML)
        </aside>
        """
    }

    private func localizedReaderAIDisclaimerText() -> String {
        switch lm.currentLanguage {
        case .french:
            return "L’IA locale d’Apple peut faire des erreurs dans les résumés et les traductions. Vérifie les informations en cas de doute."
        case .english:
            return "Apple’s on-device AI can make mistakes in summaries and translations. Verify information if in doubt."
        case .spanish:
            return "La IA local de Apple puede cometer errores en los resúmenes y las traducciones. Verifica la información en caso de duda."
        case .german:
            return "Die lokale KI von Apple kann bei Zusammenfassungen und Übersetzungen Fehler machen. Prüfen Sie die Informationen im Zweifel."
        case .italian:
            return "L’IA locale di Apple può commettere errori nei riassunti e nelle traduzioni. Verifica le informazioni in caso di dubbio."
        case .portuguese:
            return "A IA local da Apple pode cometer erros em resumos e traduções. Verifique as informações em caso de dúvida."
        case .japanese:
            return "AppleのローカルAIは、要約や翻訳で誤りを含む場合があります。疑わしい場合は情報を確認してください。"
        case .chinese:
            return "Apple 本地 AI 在摘要和翻译中可能会出错。如有疑问，请核实相关信息。"
        case .korean:
            return "Apple의 로컬 AI는 요약과 번역에서 오류를 낼 수 있습니다. 의심될 때는 정보를 확인하세요."
        case .russian:
            return "Локальный ИИ Apple может допускать ошибки в резюме и переводах. Если есть сомнения, проверяйте информацию."
        @unknown default:
            return "Apple’s on-device AI can make mistakes in summaries and translations. Verify information if in doubt."
        }
    }

    private func localizedOpenOriginalArticleButtonText() -> String {
        switch lm.currentLanguage {
        case .french:
            return "Ouvrir l'article original"
        case .english:
            return "Open original article"
        case .spanish:
            return "Abrir artículo original"
        case .german:
            return "Originalartikel öffnen"
        case .italian:
            return "Apri articolo originale"
        case .portuguese:
            return "Abrir artigo original"
        case .japanese:
            return "元の記事を開く"
        case .chinese:
            return "打开原始文章"
        case .korean:
            return "원문 기사 열기"
        case .russian:
            return "Открыть оригинальную статью"
        @unknown default:
            return "Open original article"
        }
    }

    private func parseEntity(_ entity: String) -> (name: String, type: String) {
        if let openParen = entity.lastIndex(of: "("),
           let closeParen = entity.lastIndex(of: ")"),
           openParen < closeParen {
            let name = String(entity[..<openParen]).trimmingCharacters(in: .whitespacesAndNewlines)
            let type = String(entity[entity.index(after: openParen)..<closeParen]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (name.isEmpty ? entity : name, type.isEmpty ? "concept" : type)
        }
        return (entity, "concept")
    }

    private func iconForEntityType(_ type: String) -> String {
        switch type.lowercased() {
        case "personne", "person", "people":
            return "👤"
        case "organisation", "organization", "company":
            return "🏢"
        case "lieu", "place", "location":
            return "📍"
        case "produit", "product":
            return "📦"
        case "événement", "event":
            return "📅"
        default:
            return "✦"
        }
    }

    private func extractEntitiesAndTags(title: String, text: String) async -> (entities: [String], tags: [String]) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                return ([], [])
            }

            let system = """
            Tu extrais des métadonnées d'article.
            Réponds uniquement avec du JSON valide au format:
            {"entities":["Nom (type)"],"tags":["tag1","tag2"]}
            Maximum 5 entités et 6 tags.
            """
            let user = "Titre: \(title)\n\nTexte:\n\(text.prefix(4000))"

            do {
                let session = LanguageModelSession(model: model, instructions: { system })
                let response = try await session.respond(to: user)
                var content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                content = content
                    .replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let start = content.firstIndex(of: "{"),
                   let end = content.lastIndex(of: "}") {
                    content = String(content[start...end])
                }

                if let data = content.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return ((json["entities"] as? [String]) ?? [], (json["tags"] as? [String]) ?? [])
                }
            } catch {
                return ([], [])
            }
        }
        #endif
        return ([], [])
    }

    private func normalizeURLForMatch(_ input: URL) -> String {
        var components = URLComponents(url: input, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        components?.query = nil
        return components?.url?.absoluteString ?? input.absoluteString
    }

    private func getSourceFeedName() -> String {
        let target = normalizeURLForMatch(url)
        if let article = feedService.articles.first(where: { normalizeURLForMatch($0.url) == target }),
           let feed = feedService.feeds.first(where: { $0.id == article.feedId }) {
            return feed.title
        }
        return url.host ?? "Source"
    }

    private func readerLanguageDescriptor() -> (targetName: String, summaryHeading: String, articleHeading: String, takeawaysHeading: String) {
        switch LocalizationManager.shared.currentLanguage {
        case .french:
            return ("français", "Résumé", "Article", "À retenir")
        case .english:
            return ("English", "Summary", "Article", "Key takeaways")
        case .spanish:
            return ("español", "Resumen", "Artículo", "Puntos clave")
        case .german:
            return ("Deutsch", "Zusammenfassung", "Artikel", "Wichtigste Punkte")
        case .italian:
            return ("italiano", "Riassunto", "Articolo", "Da ricordare")
        case .portuguese:
            return ("português", "Resumo", "Artigo", "Pontos-chave")
        case .japanese:
            return ("日本語", "要約", "記事", "要点")
        case .chinese:
            return ("中文", "摘要", "文章", "要点")
        case .korean:
            return ("한국어", "요약", "기사", "핵심 요약")
        case .russian:
            return ("русский", "Сводка", "Статья", "Ключевые тезисы")
        @unknown default:
            return ("English", "Summary", "Article", "Key takeaways")
        }
    }
}

@MainActor
final class IOSArticleWebState: ObservableObject {
    weak var webView: WKWebView?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var title: String = ""
    @Published var currentURL: URL?
    var isShowingReaderDocument = false

    func sync(with webView: WKWebView) {
        self.webView = webView
        setIfChanged(webView.canGoBack, keyPath: \.canGoBack)
        setIfChanged(webView.canGoForward, keyPath: \.canGoForward)
        setIfChanged(webView.isLoading, keyPath: \.isLoading)
        setIfChanged(webView.estimatedProgress, keyPath: \.progress)
        setIfChanged(webView.title ?? "", keyPath: \.title)
        setIfChanged(webView.url, keyPath: \.currentURL)
    }

    private func setIfChanged<T: Equatable>(_ value: T, keyPath: ReferenceWritableKeyPath<IOSArticleWebState, T>) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }

    func evaluateJavaScript(_ script: String) async throws -> Any? {
        guard let webView else {
            throw NSError(domain: "IOSReader", code: 7, userInfo: [NSLocalizedDescriptionKey: "WebView indisponible."])
        }
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    func loadReaderHTML(_ html: String, baseURL: URL?) {
        guard let webView else { return }
        isShowingReaderDocument = true
        webView.loadHTMLString(html, baseURL: baseURL)
    }
}

private struct IOSArticleWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: IOSArticleWebState
    let onPageLoad: (URL?) -> Void
    let onReaderAction: (IOSReaderAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, onPageLoad: onPageLoad, onReaderAction: onReaderAction)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        state.isShowingReaderDocument = false
        webView.load(URLRequest(url: url))
        state.sync(with: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if state.webView !== uiView {
            state.webView = uiView
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @MainActor private let state: IOSArticleWebState
        private let onPageLoad: (URL?) -> Void
        private let onReaderAction: (IOSReaderAction) -> Void

        @MainActor
        init(
            state: IOSArticleWebState,
            onPageLoad: @escaping (URL?) -> Void,
            onReaderAction: @escaping (IOSReaderAction) -> Void
        ) {
            self.state = state
            self.onPageLoad = onPageLoad
            self.onReaderAction = onReaderAction
        }

        @MainActor
        private func sync(_ webView: WKWebView) {
            state.sync(with: webView)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                self.sync(webView)
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            Task { @MainActor in
                self.sync(webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               url.scheme == "flux-action" {
                Task { @MainActor in
                    switch url.host {
                    case "open-original":
                        onReaderAction(.openOriginalArticle)
                    case "summary-ai":
                        onReaderAction(.summarizeAI)
                    default:
                        break
                    }
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                self.sync(webView)
                self.onPageLoad(webView.url)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.sync(webView)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.sync(webView)
            }
        }
    }
}

private enum IOSReaderAction {
    case openOriginalArticle
    case summarizeAI
}

private struct IOSReaderExtractedArticle: Decodable {
    let title: String
    let text: String
    let lead: String
    let images: [String]
}
#endif
