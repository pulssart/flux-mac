//
//  ContentView.swift
//  Flux
//
//  Created by Adrien Donot on 22/08/2025.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
// Wrapper around NSVisualEffectView to render a blur background
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
#endif

struct ContentView: View {
    @AppStorage("windowBlurEnabled") private var windowBlurEnabled: Bool = false
    @AppStorage("windowBlurTintOpacity") private var windowBlurTintOpacity: Double = 0.48
    @Environment(\.colorScheme) private var colorScheme
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(FeedService.self) private var feedService
    @State private var isInFullScreen: Bool = false

    private var glassSmokeOpacity: CGFloat {
        CGFloat(min(max(windowBlurTintOpacity, 0), 0.99))
    }

    private var hasVisibleGlassTint: Bool {
        glassSmokeOpacity > 0.001
    }

    @State private var macSheetState = iPadSheetState()

    var body: some View {
        #if os(iOS)
        IOSAppRootView()
            .onOpenURL { url in
                deepLinkRouter.receive(url)
            }
        #else
        ZStack {
            #if canImport(AppKit)
            if !windowBlurEnabled {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
            }
            if windowBlurEnabled {
                if #available(macOS 26.0, *) {
                    Rectangle()
                        .glassEffect(
                            hasVisibleGlassTint
                                ? .regular.tint(smokeColor.opacity(glassSmokeOpacity))
                                : .clear,
                            in: Rectangle()
                        )
                        .ignoresSafeArea()
                } else {
                    Group {
                        if hasVisibleGlassTint {
                            ZStack {
                                VisualEffectBlur()
                                smokeColor.opacity(glassSmokeOpacity)
                            }
                        } else {
                            Color.clear
                        }
                    }
                    .ignoresSafeArea()
                }
            }
            #endif
            AppSidebar()
                .environment(macSheetState)
            NotesWidgetSyncView().environment(feedService)
            // Frosted overlay when article or YouTube sheet is open
            if macSheetState.article != nil || macSheetState.youtubeURL != nil {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(macSheetState.youtubeURL != nil ? 0.35 : 0.15))
                    .ignoresSafeArea()
                    .onTapGesture {
                        macSheetState.article = nil
                        macSheetState.youtubeURL = nil
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: macSheetState.article != nil || macSheetState.youtubeURL != nil)
            }
            // Article summary sheet overlay
            if let article = macSheetState.article {
                GeometryReader { proxy in
                    MacArticleSummarySheet(
                        article: article,
                        feedService: feedService,
                        containerWidth: proxy.size.width,
                        containerHeight: proxy.size.height
                    ) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            macSheetState.article = nil
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .zIndex(100)
            }
            // YouTube cinema sheet overlay
            if let youtubeURL = macSheetState.youtubeURL {
                GeometryReader { proxy in
                    MacYouTubeCinemaSheet(
                        url: youtubeURL,
                        containerWidth: proxy.size.width,
                        containerHeight: proxy.size.height
                    ) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            macSheetState.youtubeURL = nil
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: macSheetState.article != nil || macSheetState.youtubeURL != nil)
        .onOpenURL { url in
            deepLinkRouter.receive(url)
        }
        #if canImport(AppKit)
        .onAppear {
            isInFullScreen = (NSApplication.shared.keyWindow?.styleMask.contains(.fullScreen) == true)
            configureWindowBlur(enabled: windowBlurEnabled, colorScheme: colorScheme)
        }
        .onChange(of: windowBlurEnabled) { _, newValue in
            configureWindowBlur(enabled: newValue, colorScheme: colorScheme)
        }
        .onChange(of: colorScheme) { _, newValue in
            configureWindowBlur(enabled: windowBlurEnabled, colorScheme: newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            isInFullScreen = true
            if let window = notification.object as? NSWindow {
                preventFullscreenIfNeeded(for: window)
                enforceWindowAppearance(enabled: windowBlurEnabled, colorScheme: colorScheme, for: window)
            } else {
                enforceWindowAppearance(enabled: windowBlurEnabled, colorScheme: colorScheme)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            isInFullScreen = false
            if let window = notification.object as? NSWindow {
                enforceWindowAppearance(enabled: windowBlurEnabled, colorScheme: colorScheme, for: window)
            } else {
                enforceWindowAppearance(enabled: windowBlurEnabled, colorScheme: colorScheme)
            }
        }
        #endif
        #endif
    }
}

@Observable
@MainActor
final class iPadSheetState {
    var article: Article?
    var youtubeURL: URL?
}

#if os(iOS)
import WebKit

/// Identifiable wrapper for a YouTube URL (needed for .sheet(item:))
private struct YouTubeSheetItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct IOSAppRootView: View {
    @Environment(FeedService.self) private var feedService
    @State private var sheetState = iPadSheetState()

    private var youtubeSheetItem: Binding<YouTubeSheetItem?> {
        Binding(
            get: { sheetState.youtubeURL.map { YouTubeSheetItem(url: $0) } },
            set: { if $0 == nil { sheetState.youtubeURL = nil } }
        )
    }

    private var hasAnySheet: Bool {
        sheetState.article != nil || sheetState.youtubeURL != nil
    }

    var body: some View {
        ZStack {
            AppSidebar()
                .environment(sheetState)
            NotesWidgetSyncView()
                .environment(feedService)
                .allowsHitTesting(false)
            // Frosted overlay above everything (including toolbar)
            if hasAnySheet {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.15))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: hasAnySheet)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: Bindable(sheetState).article) { article in
            ArticleSummarySheet(article: article, feedService: feedService)
                .presentationSizing(.page)
                .presentationCornerRadius(20)
                .presentationBackground(.clear)
                .presentationBackgroundInteraction(.disabled)
        }
        .sheet(item: youtubeSheetItem) { item in
            YouTubeCinemaSheet(url: item.url)
                .presentationSizing(.page)
                .presentationCornerRadius(20)
                .presentationBackground(.black)
                .presentationBackgroundInteraction(.disabled)
        }
    }
}

// MARK: - YouTube Cinema Modal

private struct YouTubeCinemaSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            YouTubeWebView(url: url)
                .ignoresSafeArea()

            // Close button top-left
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(.leading, 20)
                    .padding(.top, 16)
                    Spacer()
                }
                Spacer()
            }
        }
        .presentationDragIndicator(.hidden)
    }
}

private struct YouTubeWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

private extension ContentView {
    var smokeColor: Color {
        colorScheme == .dark ? .black : .white
    }
}

#if canImport(AppKit)
import WebKit

struct MacYouTubeCinemaSheet: View {
    let url: URL
    let containerWidth: CGFloat
    let containerHeight: CGFloat
    let onClose: () -> Void
    @State private var webViewRef: WKWebView?

    private var sheetWidth: CGFloat {
        let maxWidth: CGFloat = 1120
        let horizontalPadding: CGFloat = 40
        return min(maxWidth, containerWidth - horizontalPadding)
    }

    private var sheetHeight: CGFloat {
        // 16:9 ratio
        return sheetWidth * 9.0 / 16.0
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                MacYouTubeWebView(url: url, webViewRef: $webViewRef)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    webViewRef?.evaluateJavaScript("document.querySelector('video')?.pause()")
                    webViewRef?.loadHTMLString("", baseURL: nil)
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.black.opacity(0.5), in: Circle())
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(14)
            }
            .frame(width: sheetWidth, height: sheetHeight)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 10)

            Text(LocalizationManager.shared.localizedString(.spacebarPlayPause))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

struct MacYouTubeWebView: NSViewRepresentable {
    let url: URL
    @Binding var webViewRef: WKWebView?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true

        // Inject CSS to hide chrome and fill video on page load
        let cinemaCSS = """
        ytd-masthead, #masthead, #masthead-container,
        #secondary, #related, #comments, #meta,
        #info, #below, ytd-watch-metadata,
        .ytp-chrome-top, tp-yt-app-header,
        #guide-button, ytd-mini-guide-renderer,
        #page-manager > *:not(ytd-watch-flexy),
        ytd-watch-flexy #columns #secondary {
            display: none !important;
        }
        html, body, ytd-app, ytd-page-manager,
        ytd-watch-flexy {
            background: #000 !important;
            overflow: hidden !important;
        }
        ytd-watch-flexy {
            --ytd-watch-flexy-panel-max-height: 100vh !important;
        }
        ytd-watch-flexy #columns {
            max-width: 100% !important;
            padding: 0 !important;
        }
        ytd-watch-flexy #primary {
            max-width: 100% !important;
            padding: 0 !important;
            margin: 0 !important;
        }
        #player-container-outer, #player-container-inner,
        #ytd-player, .html5-video-container,
        .html5-video-player {
            width: 100vw !important;
            height: 100vh !important;
            max-width: 100vw !important;
            max-height: 100vh !important;
            position: fixed !important;
            top: 0 !important;
            left: 0 !important;
            z-index: 9999 !important;
        }
        video {
            width: 100% !important;
            height: 100% !important;
            object-fit: contain !important;
            position: absolute !important;
            top: 50% !important;
            left: 50% !important;
            transform: translate(-50%, -50%) !important;
        }
        .html5-video-player {
            cursor: pointer !important;
        }
        .ytp-chrome-bottom {
            z-index: 10000 !important;
            bottom: 20px !important;
        }
        .ytp-gradient-bottom {
            height: 120px !important;
        }
        .ytp-right-controls,
        .ytp-settings-button,
        .ytp-size-button,
        .ytp-miniplayer-button,
        .ytp-fullscreen-button,
        .ytp-subtitles-button,
        .ytp-watch-later-button,
        .ytp-copylink-button,
        .ytp-share-button-visible,
        .ytp-overflow-button {
            display: none !important;
        }
        .ytp-large-play-button {
            z-index: 10001 !important;
        }
        """
        let cssScript = WKUserScript(
            source: """
            const style = document.createElement('style');
            style.textContent = `\(cinemaCSS)`;
            document.documentElement.appendChild(style);
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(cssScript)

        // Also re-apply after page finishes loading (SPA navigation)
        let reapplyScript = WKUserScript(
            source: """
            const observer = new MutationObserver(() => {
                if (!document.getElementById('flux-cinema-css')) {
                    const s = document.createElement('style');
                    s.id = 'flux-cinema-css';
                    s.textContent = `\(cinemaCSS)`;
                    document.head.appendChild(s);
                }
                // Click theater mode button if available
                const theaterBtn = document.querySelector('.ytp-size-button');
                if (theaterBtn) theaterBtn.click();
            });
            observer.observe(document.body || document.documentElement, { childList: true, subtree: true });

            // Attempt theater mode after short delay
            setTimeout(() => {
                const btn = document.querySelector('.ytp-size-button');
                if (btn) btn.click();
            }, 2000);
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(reapplyScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        DispatchQueue.main.async { webViewRef = webView }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.evaluateJavaScript("document.querySelector('video')?.pause()")
        nsView.stopLoading()
        nsView.loadHTMLString("", baseURL: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Extra JS injection after full page load
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                webView.evaluateJavaScript("""
                    document.querySelectorAll('ytd-masthead, #masthead, #secondary, #comments, #related, #below, #meta, #info, ytd-watch-metadata').forEach(e => e.remove());
                    const btn = document.querySelector('.ytp-size-button');
                    if (btn) btn.click();
                """)
            }
        }
    }
}

private func configureWindowBlur(enabled: Bool, colorScheme: ColorScheme) {
    let windows = NSApplication.shared.windows.filter { $0.contentView != nil }
    if windows.isEmpty {
        if let fallback = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first {
            applyWindowAppearance(fallback, enabled: enabled, colorScheme: colorScheme)
        }
        return
    }
    for window in windows {
        applyWindowAppearance(window, enabled: enabled, colorScheme: colorScheme)
    }
}

private func configureWindowBlur(enabled: Bool, colorScheme: ColorScheme, for window: NSWindow) {
    applyWindowAppearance(window, enabled: enabled, colorScheme: colorScheme)
}

private func enforceWindowAppearance(enabled: Bool, colorScheme: ColorScheme) {
    let delays: [TimeInterval] = [0.0, 0.12, 0.35, 0.8]
    for delay in delays {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            configureWindowBlur(enabled: enabled, colorScheme: colorScheme)
        }
    }
}

private func enforceWindowAppearance(enabled: Bool, colorScheme: ColorScheme, for window: NSWindow) {
    let delays: [TimeInterval] = [0.0, 0.12, 0.35, 0.8]
    for delay in delays {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            configureWindowBlur(enabled: enabled, colorScheme: colorScheme, for: window)
        }
    }
}

private func applyWindowAppearance(_ window: NSWindow, enabled: Bool, colorScheme: ColorScheme) {
    let shouldUseTransparentWindow = enabled

    // Désactive le plein écran et force le bouton vert en mode "zoom/maximize".
    disableFullscreenCapabilities(for: window)

    // Force la titlebar à suivre le thème clair/sombre de l'app.
    if #available(macOS 10.14, *) {
        window.appearance = (colorScheme == .dark)
            ? NSAppearance(named: .darkAqua)
            : NSAppearance(named: .aqua)
    } else {
        window.appearance = nil
    }

    // Uniformiser l'apparence de la fenêtre pour éviter tout shift de layout
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.styleMask.insert(.fullSizeContentView)
    if #available(macOS 13.0, *) {
        window.titlebarSeparatorStyle = .none
    }
    if #available(macOS 11.0, *) {
        window.toolbarStyle = .automatic
    }
    window.toolbar?.showsBaselineSeparator = false
    // Important: en mode lecteur, sinon la zone top capte les clics et les boutons overlay deviennent non cliquables.
    window.isMovableByWindowBackground = false
    window.contentView?.superview?.wantsLayer = true
    
    // Contraintes de taille (assouplies pour un feed plus responsive)
    window.minSize = NSSize(width: 420, height: 520)
    window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

    if shouldUseTransparentWindow {
        // Mode blur: fond transparent pour laisser passer l'effet matière.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor
        forceTransparentTitlebar(window)
    } else {
        // Mode normal: fond standard de fenêtre.
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.contentView?.superview?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}

private func forceTransparentTitlebar(_ window: NSWindow) {
    if let titlebarView = window.standardWindowButton(.closeButton)?.superview {
        clearTitlebarBackground(in: titlebarView)
        if let container = titlebarView.superview {
            clearTitlebarBackground(in: container)
        }
    }
}

private func clearTitlebarBackground(in view: NSView) {
    let className = String(describing: type(of: view)).lowercased()
    if className.contains("titlebar") || className.contains("toolbar") {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }
    for subview in view.subviews {
        clearTitlebarBackground(in: subview)
    }
}

private func disableFullscreenCapabilities(for window: NSWindow) {
    window.collectionBehavior.remove([.fullScreenPrimary, .fullScreenAuxiliary, .fullScreenAllowsTiling])

    if let zoomButton = window.standardWindowButton(.zoomButton) {
        zoomButton.target = window
        zoomButton.action = #selector(NSWindow.performZoom(_:))
        zoomButton.isEnabled = true
    }
}

private func preventFullscreenIfNeeded(for window: NSWindow) {
    disableFullscreenCapabilities(for: window)
    if window.styleMask.contains(.fullScreen) {
        DispatchQueue.main.async {
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
    }
}

#endif

#Preview {
    ContentView()
}
