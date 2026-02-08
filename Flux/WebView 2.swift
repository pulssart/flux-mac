// WebView.swift
// Contains the WebDrawer SwiftUI view for macOS that presents a WKWebView in a sliding overlay with a close button.

import SwiftUI
#if os(macOS)
import WebKit
import AppKit
import Combine
import AVFoundation
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

struct WebDrawer: View {
    let url: URL
    let forceAISummary: Bool
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
    @State private var readerTheme: ReaderTheme = .sepia
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
    // Métadonnées extraites pour la sidebar du lecteur
    @State private var readerEntities: [String] = []
    @State private var readerTags: [String] = []
    @State private var readerSourceName: String = ""

    init(url: URL, startInReaderMode: Bool = false, forceAISummary: Bool = false, onClose: @escaping () -> Void) {
        self.url = url
        self.forceAISummary = forceAISummary
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
                        if forceAISummary {
                            Task { await applyReaderAI() }
                        } else if openArticleInReaderFirst {
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
                    NotificationCenter.default.post(name: Notification.Name("CollapseSidebar"), object: nil)
                    guard !isApplyingReaderAI else { return }
                    showReaderMask = true
                    readerFallbackTriggered = false
                    Task { await applyReaderAI() }
                }
            })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(showReaderMask ? 0 : 1)

            // Indicateur de chargement centré pendant la génération IA
            if showReaderMask && readerMode {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(readerMaskTint)
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
        .onReceive(readerTicker) { _ in
            if showReaderMask && !readerPhrases.isEmpty {
                readerPhraseIndex = (readerPhraseIndex + 1) % readerPhrases.count
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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

                Button(action: {
                    NotificationCenter.default.post(name: Notification.Name("ExpandSidebar"), object: nil)
                    onClose()
                }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .help(lm.localizedString(.helpCloseWindow))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarColorScheme(readerMode ? (isLightReaderTheme ? .light : .dark) : nil, for: .windowToolbar)
        .alert(lm.localizedString(.errorX), isPresented: Binding<Bool>(
            get: { postXError != nil },
            set: { if !$0 { postXError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(postXError ?? "")
        }
        .onAppear {
            // Définir le thème du lecteur en fonction du mode clair/sombre de l'app
            readerTheme = colorScheme == .dark ? .dark : .sepia
        }
    }

    // Couleur de fond du mode lecteur selon le thème
    private var readerBackgroundColor: Color {
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
            let css = readerCSS()
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
            let css = readerCSS()
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

    private func readerCSS() -> String {
        // Layout avec sidebar fixe à droite
        let layout = """
        /* Container centré quelle que soit la présence de la sidebar */
        .reader-outer{width:100%;}
        .reader-container{display:flex;align-items:flex-start;justify-content:center;gap:32px;max-width:1200px;margin:0 auto;padding:72px 24px 40px;box-sizing:border-box}
        /* Colonne de lecture limitée et centrée naturellement si pas de sidebar */
        .reader{flex:1;max-width:760px;width:100%;font:18px -apple-system,system-ui,sans-serif;line-height:1.7;text-align:left}
        /* Bloc A retenir aligné à gauche dans la colonne de lecture */
        .reader-takeaways{width:100%;margin-left:0;margin-right:0;padding-top:12px}
        .reader-takeaways h3{margin-top:0}
        .reader-takeaways ul{margin:8px 0 0;padding-left:18px}
        /* Sidebar fixe à droite - style liquid glass */
        .reader-sidebar{width:260px;flex-shrink:0;position:sticky;top:72px;height:fit-content;padding:16px;border-radius:16px;font:14px -apple-system,system-ui,sans-serif;box-sizing:border-box;overflow:hidden;-webkit-backdrop-filter:blur(20px) saturate(180%);backdrop-filter:blur(20px) saturate(180%);border:1px solid rgba(255,255,255,0.18);box-shadow:0 8px 32px rgba(0,0,0,0.08)}
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
        .reader-sidebar .x-btn,.reader-sidebar .ai-btn{display:flex;align-items:center;gap:6px;margin-top:16px;padding:8px 10px;border-radius:8px;font-size:11px;font-weight:500;text-decoration:none !important;cursor:pointer;border:none;box-sizing:border-box;justify-content:center;width:100%;max-width:100%}
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
          .reader-container{flex-direction:column;align-items:center;padding:60px 16px 40px}
          .reader{max-width:760px}
          .reader-sidebar{width:100%;position:static;order:2}
          .reader-slider-btn{width:36px;height:36px}
          .reader-slider-btn.prev{left:8px}
          .reader-slider-btn.next{right:8px}
        }
        """
        let (bgColor, textColor, sidebarBg, tagBg, xBtnBg) = themeColors()
        let fontFamily = readerFont == .serif
            ? "Georgia,'Times New Roman',serif"
            : "-apple-system,system-ui,Helvetica,Arial,sans-serif"
        let themeBase = "body{background:\(bgColor);margin:0;color:\(textColor);font:18px \(fontFamily)}"
        let fontStyle = ".reader{font-family:\(fontFamily)}"
        let sidebarStyle = ".reader-sidebar{background:\(sidebarBg)} .reader-sidebar .tag{background:\(tagBg)} .reader-sidebar .x-btn,.reader-sidebar .ai-btn{background:\(xBtnBg);color:\(textColor)}"
        // Slider theme colors
        let (sliderBtnBg, sliderBtnColor, sliderBtnShadow, sliderDotBg, sliderCounterBg, sliderCounterColor) = sliderColors()
        let sliderStyle = ".reader-slider-btn{background:\(sliderBtnBg);color:\(sliderBtnColor);box-shadow:\(sliderBtnShadow)} .reader-slider-btn svg{fill:\(sliderBtnColor)} .reader-slider-dot{background:\(sliderDotBg)} .reader-slider-counter{background:\(sliderCounterBg);color:\(sliderCounterColor);box-shadow:\(sliderBtnShadow)}"
        return themeBase + layout + fontStyle + sidebarStyle + sliderStyle
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
    
    // MARK: - Reader Mode
    private func toggleReader() {
        readerMode.toggle()
        if readerMode {
            // Recouvre immédiatement via overlay SwiftUI (pas JS)
            showReaderMask = true
            if forceAISummary {
                Task { await applyReaderAI() }
            } else if openArticleInReaderFirst {
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
        Task { @MainActor in
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
            // 2) Appliquer un rendu strict: titre + texte + photos avec slider
            let readerJS = """
            (function(){
              try {
                var rd = new Readability(document.cloneNode(true));
                var article = rd.parse();
                if(!article){ return false; }
                
                // Extraire toutes les images
                var images = [];
                var seenUrls = {};
                var lead = article.lead_image_url || article.image || '';
                if(lead && lead.trim()){ seenUrls[lead] = true; images.push(lead); }
                
                // Images du contenu Readability
                if(article.content){
                  var tmp = document.createElement('div');
                  tmp.innerHTML = article.content;
                  tmp.querySelectorAll('img').forEach(function(img){
                    var src = img.src || img.getAttribute('data-src') || '';
                    if(src && src.trim() && !seenUrls[src]){
                      var w = parseInt(img.getAttribute('width') || '0', 10);
                      var h = parseInt(img.getAttribute('height') || '0', 10);
                      if((w > 0 && w < 100) || (h > 0 && h < 100)) return;
                      var srcLower = src.toLowerCase();
                      if(srcLower.indexOf('pixel') >= 0 || srcLower.indexOf('tracking') >= 0 || srcLower.indexOf('logo') >= 0 || srcLower.indexOf('icon') >= 0) return;
                      seenUrls[src] = true;
                      images.push(src);
                    }
                  });
                }
                images = images.slice(0, 10);
                
                var text = (article.textContent||'').replace(/\\r/g,'');
                var parts = text.split(/\\n\\s*\\n+/).map(function(s){ return s.trim(); }).filter(Boolean);
                var bodyHTML = parts.map(function(p){ return '<p>'+p.replace(/</g,'&lt;').replace(/>/g,'&gt;')+'</p>'; }).join('');
                
                // Générer le HTML des images (slider si plusieurs, sinon image simple)
                var imgHTML = '';
                if(images.length === 1){
                  imgHTML = '<img src="'+images[0]+'" alt="" loading="lazy" style="border-radius:16px;box-shadow:0 4px 20px rgba(0,0,0,0.25);"/>';
                } else if(images.length > 1){
                  var slidesHTML = images.map(function(url, i){ return '<div class="reader-slider-slide'+(i===0?' active':'')+'"><img src="'+url+'" alt="" loading="lazy"/></div>'; }).join('');
                  var dotsHTML = images.map(function(_, i){ return '<span class="reader-slider-dot'+(i===0?' active':'')+'" data-index="'+i+'"></span>'; }).join('');
                  var prevArrow = '<svg viewBox="0 0 24 24"><polyline points="15 18 9 12 15 6"></polyline></svg>';
                  var nextArrow = '<svg viewBox="0 0 24 24"><polyline points="9 18 15 12 9 6"></polyline></svg>';
                  imgHTML = '<div class="reader-slider-wrapper"><div class="reader-slider"><div class="reader-slider-track">'+slidesHTML+'</div></div><button class="reader-slider-btn prev">'+prevArrow+'</button><button class="reader-slider-btn next">'+nextArrow+'</button><span class="reader-slider-counter">1 / '+images.length+'</span></div><div class="reader-slider-dots">'+dotsHTML+'</div>';
                }
                
                var sourceName = (window.location && window.location.hostname) ? window.location.hostname.replace(/^www\\./,'') : '';
                var sidebar = '<aside class="reader-sidebar">'+
                              '<div class="section"><h4>Source</h4><div class="source">'+sourceName+'</div></div>'+
                              '<button onclick="window.location.href=\\'flux-action://share-x\\'" class="x-btn"><svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>'+
                              '<span>Partager sur X</span></button>'+
                              '<button onclick="window.location.href=\\'flux-action://summary-ai\\'" class="ai-btn"><span>Résumé (Intelligence artificielle locale)</span></button>'+
                              '</aside>';
                var html = '<!doctype html><meta charset="utf-8"><style>\(style)</style>'+
                           '<div class="reader-outer"><div class="reader-container">'+
                           '<article class="reader"><h1>'+(article.title||'')+'</h1>'+imgHTML+bodyHTML+'</article>'+sidebar+
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
                
                // Initialiser le slider si présent
                if(images.length > 1){
                  setTimeout(function(){
                    var wrapper = document.querySelector('.reader-slider-wrapper');
                    if(!wrapper) return;
                    var slider = wrapper.querySelector('.reader-slider');
                    var track = wrapper.querySelector('.reader-slider-track');
                    var slides = wrapper.querySelectorAll('.reader-slider-slide');
                    var imgs = wrapper.querySelectorAll('.reader-slider-slide img');
                    var dots = document.querySelectorAll('.reader-slider-dot');
                    var counter = wrapper.querySelector('.reader-slider-counter');
                    var current = 0, total = slides.length;
                    var autoTimer = null;
                    function updateHeight(){ var img=imgs[current]; if(img&&img.complete&&img.naturalHeight>0){ slider.style.height=img.offsetHeight+'px'; } }
                    function goTo(i){ if(i<0)i=total-1; if(i>=total)i=0; current=i; track.style.transform='translateX(-'+(current*100)+'%)'; slides.forEach(function(s,j){s.classList.toggle('active',j===current);}); dots.forEach(function(d,j){d.classList.toggle('active',j===current);}); if(counter)counter.textContent=(current+1)+' / '+total; updateHeight(); }
                    function cancelAuto(){ if(autoTimer){clearTimeout(autoTimer);autoTimer=null;} }
                    imgs.forEach(function(img,i){ if(img.complete){ if(i===0)updateHeight(); } else { img.onload=function(){ if(i===current)updateHeight(); }; } });
                    window.onresize=updateHeight;
                    // Auto-avance vers la 2e image après 3 secondes
                    autoTimer = setTimeout(function(){ if(current===0)goTo(1); }, 3000);
                    wrapper.querySelector('.reader-slider-btn.prev').onclick = function(e){e.preventDefault();cancelAuto();goTo(current-1);};
                    wrapper.querySelector('.reader-slider-btn.next').onclick = function(e){e.preventDefault();cancelAuto();goTo(current+1);};
                    dots.forEach(function(d){d.onclick=function(){cancelAuto();goTo(parseInt(this.getAttribute('data-index'),10));};});
                    document.onkeydown=function(e){if(e.key==='ArrowLeft'){cancelAuto();goTo(current-1);}if(e.key==='ArrowRight'){cancelAuto();goTo(current+1);}};
                  }, 100);
                }
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
                        await MainActor.run { applyReader(); showReaderMask = false }
                        return
                    }
                    let style = readerCSS()
                    let safeTitle = fallbackTitle.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
                    let imgHTML = buildImageSliderHTML(images: normalizeLeadURL(stored.imageURL).map { [$0] } ?? [])
                    let sidebarHTML = buildSidebarHTML(source: getSourceFeedName(), entities: metadata.entities, tags: metadata.tags, articleURL: url.absoluteString, pageTitle: fallbackTitle, showSummaryButton: false)
                    let scrambleScript = scrambleEffectScript()
                    let html = "<!doctype html><meta charset=\"utf-8\"><style>\(style)</style><div class=\"reader-outer\"><div class=\"reader-container\"><article class=\"reader\"><h1>\(safeTitle)</h1>\(imgHTML)\(summaryHTML)</article>\(sidebarHTML)</div></div>\(scrambleScript)"
                    await MainActor.run {
                        webView.loadHTMLString(html, baseURL: url)
                        readerAICompleted = true
                        readerTimeoutTask?.cancel()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showReaderMask = false
                        }
                    }
                } catch {
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
                await MainActor.run { applyReader(); showReaderMask = false }
                return
            }
            if readerFallbackTriggered {
                print("[ReaderAI] fallback already shown -> skip AI inject")
                readerTimeoutTask?.cancel()
                return
            }
            // 3) Construire et injecter le HTML lecteur avec sidebar
            let style = readerCSS()
            let safeTitle = article.title.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            // Utiliser le slider si plusieurs images, sinon image simple
            let imgHTML = buildImageSliderHTML(images: allImages)
            let contentHTML = summaryHTML
            let sidebarHTML = buildSidebarHTML(source: getSourceFeedName(), entities: metadata.entities, tags: metadata.tags, articleURL: url.absoluteString, pageTitle: article.title, showSummaryButton: false)
            // Script pour l'effet scramble sur le texte du résumé
            let scrambleScript = scrambleEffectScript()
            // Sidebar après le contenu pour qu'elle soit à droite avec flexbox
            let html = "<!doctype html><meta charset=\"utf-8\"><style>\(style)</style><div class=\"reader-outer\"><div class=\"reader-container\"><article class=\"reader\"><h1>\(safeTitle)</h1>\(imgHTML)\(contentHTML)</article>\(sidebarHTML)</div></div>\(scrambleScript)"
            await MainActor.run {
                // Utiliser loadHTMLString directement (plus fiable que document.write)
                appLog("[ReaderAI] loading reader HTML via loadHTMLString")
                webView.loadHTMLString(html, baseURL: url)
                readerAICompleted = true
                readerTimeoutTask?.cancel()
                // Délai court pour laisser le temps au HTML de se charger avant d'enlever le masque
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showReaderMask = false
                }
            }
        } catch {
            appLogError("[ReaderAI] exception: \(error.localizedDescription)")
            readerTimeoutTask?.cancel()
            readerAICompleted = true // Marquer comme complété même en cas d'erreur pour éviter les retentatives
            // En cas d'échec IA/extraction, fallback classique
            await MainActor.run { applyReader(); showReaderMask = false }
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
        let cleaned = text
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: " ")
        let parts = cleaned
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let body = parts.isEmpty
            ? "<p>Contenu indisponible pour cet article.</p>"
            : parts.map { "<p>\($0.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;"))</p>" }.joined()
        let leadURL = normalizeLeadURL(lead)
        let imgHTML = (leadURL?.isEmpty == false) ? "<img src=\"\(leadURL!)\" alt=\"\" loading=\"lazy\" style=\"margin-top:16px;\"/>" : ""
        let sidebarHTML = buildSidebarHTML(
            source: getSourceFeedName(),
            entities: [],
            tags: [],
            articleURL: url.absoluteString,
            pageTitle: title,
            showSummaryButton: true
        )
        let html = "<!doctype html><meta charset=\"utf-8\"><style>\(style)</style><div class=\"reader-outer\"><div class=\"reader-container\"><article class=\"reader\"><h1>\(safeTitle)</h1>\(imgHTML)\(body)</article>\(sidebarHTML)</div></div>"
        return html
    }

    private func storedArticleFallback() -> (title: String?, text: String?, imageURL: String?) {
        let target = normalizeURLForMatch(url)
        guard let match = feedService.articles.first(where: { normalizeURLForMatch($0.url) == target }) else {
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
        let target = normalizeURLForMatch(url)
        if let match = feedService.articles.first(where: { normalizeURLForMatch($0.url) == target }) {
            return match.imageURL?.absoluteString
        }
        return nil
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
        case .french: targetName = "français"; takeawaysHeading = "A retenir"
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
        let system = "You are an editor. Clean the article (remove navigation, cookies, promos), translate to \(targetName) if needed, and produce strictly in \(targetName). Output HTML only (no Markdown). Do not output any headings (no <h1>, <h2>, <h3>, <h4> and no Markdown ##). Never output the label 'Résumé' or 'Summary' in the content. No links, no disclaimers."
        let user = """
        Title: \(title)

        Text:
        \(text.prefix(12000))

        STRICT OUTPUT FORMAT (two separate sections):

        SECTION 1 - SUMMARY:
        Write ONLY 2-3 <p> paragraphs that summarize the main ideas. NO bullet points, NO lists in this section.

        ===TAKEAWAYS===

        SECTION 2 - KEY POINTS:
        Write ONLY a <ul> list with 6-10 <li> bullet points. These are the actionable takeaways.

        CRITICAL: The summary section must contain ONLY <p> paragraphs. ALL bullet points go AFTER the ===TAKEAWAYS=== delimiter.
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
                    // Convert any markdown-style bold to HTML for display safety.
                    summaryHTML = summaryHTML.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
                    takeawaysHTML = takeawaysHTML.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
                    summaryHTML = fixMojibake(summaryHTML)
                    takeawaysHTML = fixMojibake(takeawaysHTML)
                    summaryHTML = summaryHTML.replacingOccurrences(of: "===TAKEAWAYS===", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    takeawaysHTML = takeawaysHTML.replacingOccurrences(of: "===TAKEAWAYS===", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    // Nettoyer les marqueurs de section que le modèle peut inclure
                    summaryHTML = cleanSectionMarkers(summaryHTML)
                    takeawaysHTML = cleanSectionMarkers(takeawaysHTML)
                    takeawaysHTML = normalizeTakeawaysHTML(takeawaysHTML)
                    summaryHTML = normalizeHeadingHTML(summaryHTML)
                    takeawaysHTML = normalizeHeadingHTML(takeawaysHTML)
                    takeawaysHTML = ensureTakeawaysHTML(takeawaysHTML: takeawaysHTML, summaryHTML: summaryHTML, sourceText: text)
                    let hSummary = "<h3>Résumé</h3>"
                    let takeawaysBlock = "<section class=\"reader-takeaways\"><h3>\(takeawaysHeading)</h3>\n<div class=\"scramble-target\" data-scramble-delay=\"400\">\(takeawaysHTML)</div></section>"
                    return "\(hSummary)\n<div class=\"scramble-target\" data-scramble-delay=\"0\">\(summaryHTML)</div>\n\(takeawaysBlock)"
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
            
            function revealWordByWord(element, delay) {
                const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT, null, false);
                const textNodes = [];
                let node;
                while (node = walker.nextNode()) {
                    if (node.textContent.trim()) {
                        textNodes.push({ node: node, original: node.textContent, parent: node.parentNode });
                    }
                }
                
                if (textNodes.length === 0) return;
                
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
                        if (revealedCount >= allWords.length) return;
                        
                        // Révéler plusieurs mots par batch
                        for (let i = 0; i < wordsPerBatch && revealedCount < allWords.length; i++) {
                            allWords[revealedCount].classList.add('revealed');
                            revealedCount++;
                        }
                        
                        if (revealedCount < allWords.length) {
                            setTimeout(revealBatch, delayBetweenBatches);
                        }
                    }
                    
                    revealBatch();
                }, delay);
            }
            
            // Appliquer l'effet aux éléments avec la classe scramble-target
            document.addEventListener('DOMContentLoaded', function() {
                document.querySelectorAll('.scramble-target').forEach(el => {
                    const delay = parseInt(el.dataset.scrambleDelay || '0', 10);
                    revealWordByWord(el, delay);
                });
            });
            
            // Fallback si DOMContentLoaded déjà passé
            if (document.readyState !== 'loading') {
                document.querySelectorAll('.scramble-target').forEach(el => {
                    const delay = parseInt(el.dataset.scrambleDelay || '0', 10);
                    revealWordByWord(el, delay);
                });
            }
        })();
        </script>
        """
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
            \(xButtonHTML)
            \(summaryButtonHTML)
        </aside>
        """
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

    private func normalizeTakeawaysHTML(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("<li>") {
            return trimmed
        }
        let cleaned = trimmed
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "===TAKEAWAYS===", with: "")
        let parts = cleaned
            .components(separatedBy: "*")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count > 1 {
            let items = parts.map { "<li>\($0)</li>" }.joined()
            return "<ul>\(items)</ul>"
        }
        let lines = cleaned
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                let lower = $0.lowercased()
                return !$0.isEmpty &&
                    lower != "a retenir" &&
                    lower != "à retenir" &&
                    lower != "résumé" &&
                    lower != "resume" &&
                    lower != "html"
            }
            .map { line -> String in
                if line.hasPrefix("•") { return String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) }
                if line.hasPrefix("-") { return String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) }
                return line
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
            "SECTION\\s*[12]\\s*[-–—:]?",
            "<p>\\s*SECTION\\s*1\\s*[-–—:]?\\s*SUMMARY\\s*:?\\s*</p>",
            "<p>\\s*SECTION\\s*2\\s*[-–—:]?\\s*KEY\\s*POINTS\\s*:?\\s*</p>",
            "^\\s*SUMMARY\\s*:?\\s*",
            "^\\s*KEY\\s*POINTS\\s*:?\\s*",
            "^\\s*RÉSUMÉ\\s*:?\\s*",
            "^\\s*RESUME\\s*:?\\s*",
            "^\\s*A\\s*RETENIR\\s*:?\\s*",
            "^\\s*À\\s*RETENIR\\s*:?\\s*",
            "^\\s*HTML\\s*$",
            "<p>\\s*HTML\\s*</p>",
            "={3,}",
            "<strong>\\s*SECTION\\s*1\\s*[-–—:]?\\s*SUMMARY\\s*:?\\s*</strong>",
            "<strong>\\s*SECTION\\s*2\\s*[-–—:]?\\s*KEY\\s*POINTS\\s*:?\\s*</strong>",
            "<b>\\s*SECTION\\s*1\\s*[-–—:]?\\s*SUMMARY\\s*:?\\s*</b>",
            "<b>\\s*SECTION\\s*2\\s*[-–—:]?\\s*KEY\\s*POINTS\\s*:?\\s*</b>"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
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
            Task { try? await webView.evaluateJavaScript(adBlockerScript) }
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
import SafariServices

struct WebDrawer: View {
    let url: URL
    let startInReaderMode: Bool
    let forceAISummary: Bool
    let onClose: () -> Void
    @State private var showSafari = true

    init(url: URL, startInReaderMode: Bool = false, forceAISummary: Bool = false, onClose: @escaping () -> Void) {
        self.url = url
        self.startInReaderMode = startInReaderMode
        self.forceAISummary = forceAISummary
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    onClose()
                }

            SafariView(url: url, onDismiss: onClose)
                .edgesIgnoringSafeArea(.all)
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onDismiss()
        }
    }
}
#endif
