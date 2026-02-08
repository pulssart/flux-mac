// NewsletterView.swift
import SwiftUI
import SwiftData

struct NewsletterView: View {
    @Environment(FeedService.self) private var feedService
    @Environment(\.openURL) private var openURL
    @State private var showScheduleSheet: Bool = false
    @State private var webURL: URL? = nil
    private let heroHeight: CGFloat = 520
    private let lm = LocalizationManager.shared

    private var header: some View {
        Group {
            if let content = feedService.newsletterContent, !content.isEmpty {
                HStack(spacing: 10) {
                    Text(LocalizationManager.shared.localizedString(.newsletterTitle))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let date = feedService.newsletterGeneratedAt {
                        Text("\(LocalizationManager.shared.localizedString(.newsletterGenerated)) \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                EmptyView()
            }
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Héro en tête du contenu pour défiler avec le texte
                if let hero = feedService.newsletterHeroURL {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: heroHeight)
                        .background(alignment: .top) {
                            heroImageView(url: hero)
                                .frame(maxWidth: .infinity)
                                .frame(height: heroHeight)
                                .clipped()
                                .overlay(alignment: .top) {
                                    LinearGradient(
                                        colors: [Color.black.opacity(0.45), Color.black.opacity(0.20), Color.clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                }
                                .overlay(alignment: .topLeading) {
                                    if feedService.newsletterHeroIsAI {
                                        Text(LocalizationManager.shared.localizedString(.newsletterImageAI))
                                            .font(.caption2).bold()
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(Color.black.opacity(0.55)))
                                            .foregroundStyle(Color.white)
                                            .padding(12)
                                    }
                                }
                                .ignoresSafeArea(edges: .horizontal)
                        }
                }
                // Corps centré (largeur de lecture)
                VStack(alignment: .leading, spacing: 18) {
                    header
                    editorialContent
                }
                .frame(maxWidth: 840)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(edges: .top)
        // pas de background héro: il défile avec le contenu
        .overlay(alignment: .center) {
            if feedService.isGeneratingNewsletter {
                NewsletterLoadingOverlay()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .center) {
            // État vide centré parfaitement (icône + texte + bouton)
            let isEmpty = (feedService.newsletterContent == nil) || (feedService.newsletterContent?.isEmpty == true)
            if isEmpty && !feedService.isGeneratingNewsletter {
                VStack(spacing: 14) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text(LocalizationManager.shared.localizedString(.newsletterEmptyHint))
                        .foregroundStyle(.secondary)
                    generateButton
                    if let err = feedService.aiErrorMessage {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 24)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                generateButtonInline
                Button(action: { showScheduleSheet = true }) {
                    Image(systemName: "gearshape")
                }
                .help(LocalizationManager.shared.localizedString(.scheduleSettings))
                if feedService.newsletterAudioURL != nil {
                    Button(action: { feedService.toggleSpeakNewsletter() }) {
                        if feedService.isSpeakingNewsletter {
                            Image(systemName: "stop.fill").foregroundStyle(.red)
                        } else {
                            Image(systemName: "headphones").foregroundStyle(.blue)
                        }
                    }
                    .help(LocalizationManager.shared.localizedString(.listenNewsletter))
                }
            }
        }
        .sheet(isPresented: $showScheduleSheet) {
            NewsletterScheduleSheet(isPresented: $showScheduleSheet)
                .environment(feedService)
        }
    }

    var body: some View {
        Group {
            if let url = webURL {
                WebDrawer(url: url, startInReaderMode: false) {
                    withAnimation(.easeInOut(duration: 0.28)) { webURL = nil }
                }
            } else {
                mainContent
            }
        }
    }
    
    private func openInAppWebView(_ url: URL) {
        withAnimation(.easeInOut(duration: 0.28)) {
            webURL = url
        }
    }

    @ViewBuilder
    private var content: some View { EmptyView() }

    @ViewBuilder
    private var editorialContent: some View {
        if let text = feedService.newsletterContent, !text.isEmpty {
            let blocks = parseMarkdownBlocks(text)
            let h2Count = blocks.filter { if case .h2 = $0 { return true }; return false }.count
            let paraCount = blocks.filter { if case .paragraph = $0 { return true }; return false }.count
            let _ = print("[Newsletter] Blocs: total=\(blocks.count), H2=\(h2Count), paragraphes=\(paraCount)")
            let imagesForParagraph = selectParagraphImageMap(blocks: blocks)
            let sourcesForParagraph = selectParagraphSourcesMap(blocks: blocks)
            let firstParagraphAfterH2 = findFirstParagraphsAfterH2(blocks: blocks)
            
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(blocks.enumerated()), id: \.0) { idx, block in
                    switch block {
                    case .h1(let t):
                        // Titre principal avec style éditorial
                        VStack(alignment: .leading, spacing: 12) {
                            Text(attributed(fromMarkdown: t))
                                .font(.system(size: 34, weight: .bold, design: .serif))
                                .foregroundStyle(.primary)
                                .lineSpacing(4)
                            
                            // Ligne d'accent sous le titre
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor)
                                    .frame(width: 40, height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor.opacity(0.4))
                                    .frame(width: 20, height: 4)
                            }
                        }
                        .padding(.bottom, 16)
                        
                    case .h2(let t):
                        // Séparateur élégant avant chaque section H2 (sauf la première)
                        if idx > 0 && !isFirstH2(blocks: blocks, currentIndex: idx) {
                            HStack(spacing: 12) {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 1)
                                Circle()
                                    .fill(Color.primary.opacity(0.15))
                                    .frame(width: 6, height: 6)
                                Rectangle()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 1)
                            }
                            .padding(.vertical, 24)
                        }
                        
                        // Titre de section avec accent
                        HStack(alignment: .center, spacing: 10) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.accentColor)
                                .frame(width: 3, height: 22)
                            Text(attributed(fromMarkdown: t))
                                .font(.system(size: 20, weight: .semibold, design: .default))
                        }
                        .padding(.top, idx > 0 ? 0 : 8)
                        
                    case .h3(let t):
                        Text(attributed(fromMarkdown: t))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.9))
                            .padding(.top, 8)
                            .padding(.leading, 13)
                        
                    case .paragraph(let t):
                        // Premier paragraphe de section : style légèrement différent
                        if firstParagraphAfterH2.contains(idx) {
                            Text(attributed(fromMarkdown: t))
                                .font(.system(size: 15.5, weight: .regular))
                                .foregroundStyle(.primary.opacity(0.95))
                                .lineSpacing(7)
                                .padding(.leading, 13)
                        } else {
                            Text(attributed(fromMarkdown: t))
                                .font(.system(size: 15))
                                .foregroundStyle(.primary.opacity(0.88))
                                .lineSpacing(6)
                                .padding(.leading, 13)
                        }
                        
                        // Sources avec icônes
                        if let names = sourcesForParagraph[idx] {
                            sourcesRow(names)
                                .padding(.top, 6)
                                .padding(.leading, 13)
                        }
                        
                        // Image avec style éditorial
                        if let u = imagesForParagraph[idx] {
                            editorialImage(url: u)
                                .padding(.top, 8)
                        }
                        
                    case .listItem(let t):
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                            Text(attributed(fromMarkdown: t))
                                .font(.system(size: 14.5))
                                .foregroundStyle(.primary.opacity(0.9))
                        }
                        .padding(.leading, 16)
                        
                    case .sources:
                        EmptyView()
                    }
                }
                
                // Vidéos du jour
                let todayUrls = todayVideoURLs()
                if !todayUrls.isEmpty {
                    // Séparateur avant vidéos
                    HStack(spacing: 12) {
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(Color.primary.opacity(0.2))
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                    }
                    .padding(.vertical, 20)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.red)
                                .frame(width: 3, height: 18)
                            Text(LocalizationManager.shared.localizedString(.newsletterVideosToday))
                                .font(.system(size: 18, weight: .semibold))
                        }
                        
                        ForEach(todayUrls.prefix(3), id: \.self) { url in
                            YouTubeIframeView(videoURL: url, onTap: openInAppWebView)
                                .frame(maxWidth: .infinity)
                                .aspectRatio(16.0/9.0, contentMode: .fit)
                                .cornerRadius(10)
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        }
                    }
                }
                // Footer signature élégant
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 30, height: 1)
                        Circle().fill(Color.primary.opacity(0.1)).frame(width: 4, height: 4)
                        Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 30, height: 1)
                    }
                    Text(localizedFooterText())
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)

                // Feed des articles (style social)
                feedSection
            }
        } else if feedService.isGeneratingNewsletter {
            HStack(spacing: 10) {
                ProgressView().controlSize(.regular)
                Text(LocalizationManager.shared.localizedString(.newsletterPreparing))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 320, alignment: .center)
        } else {
            EmptyView() // l'état vide est géré par l'overlay centré
        }
    }

    private var feedSectionArticles: [Article] {
        feedService.articles
            .filter { !isYouTube($0.url) }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    private var feedSection: some View {
        let articles = Array(feedSectionArticles.prefix(12))
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(Color.primary.opacity(0.2))
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            }
            .padding(.vertical, 16)

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 18)
                Text(lm.localizedString(.newsletterFeed))
                    .font(.system(size: 18, weight: .semibold))
                Spacer(minLength: 0)
            }

            if articles.isEmpty {
                Text(lm.localizedString(.noArticles))
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    private var generateButtonInline: some View {
        Button(action: generate) {
            if feedService.isGeneratingNewsletter {
                ProgressView().controlSize(.small)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text(LocalizationManager.shared.localizedString(.generate))
                }
            }
        }
        .disabled(feedService.isGeneratingNewsletter)
        .help(LocalizationManager.shared.localizedString(.generateMyNewsletter))
    }

    private var generateButton: some View {
        Button(action: generate) {
            HStack(spacing: 8) {
                if feedService.isGeneratingNewsletter {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(LocalizationManager.shared.localizedString(.generateMyNewsletter))
                    .font(.headline)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .disabled(feedService.isGeneratingNewsletter)
    }

    private func generate() {
        Task { await feedService.generateNewsletter() }
    }

    private func attributed(fromMarkdown md: String) -> AttributedString {
        // Essayer de parser le markdown
        if let a = try? AttributedString(markdown: md) { return a }
        // Fallback: nettoyer les ** manuellement si le parsing échoue
        let cleaned = md.replacingOccurrences(of: "**", with: "")
        return AttributedString(cleaned)
    }

    // MARK: - Parsing & Images
    private enum Block { case h1(String), h2(String), h3(String), paragraph(String), listItem(String), sources([String]) }
    
    private func parseMarkdownBlocks(_ md: String) -> [Block] {
        // Log les premières lignes pour débug
        let preview = md.prefix(500).replacingOccurrences(of: "\n", with: "\\n")
        print("[Newsletter Parser] Content preview: \(preview)")
        
        var blocks: [Block] = []
        let lines = md.components(separatedBy: "\n")
        var i = 0
        var buffer: [String] = []
        var foundH1 = false
        
        func flushBuffer() {
            let text = buffer.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            buffer.removeAll()
        }
        
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            let cleanLine = line.replacingOccurrences(of: "**", with: "")
            
            // 1) Markdown H3: ### ou ###Titre
            if line.hasPrefix("###") {
                flushBuffer()
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "")
                if !title.isEmpty { blocks.append(.h3(title)) }
            }
            // 2) Markdown H2: ## ou ##Titre
            else if line.hasPrefix("##") {
                flushBuffer()
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "")
                if !title.isEmpty { blocks.append(.h2(title)) }
            }
            // 3) Markdown H1: # ou #Titre
            else if line.hasPrefix("#") && !line.hasPrefix("# #") {
                flushBuffer()
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "")
                if !title.isEmpty { 
                    blocks.append(.h1(title))
                    foundH1 = true
                }
            }
            // 4) Ligne entièrement en gras **Titre** = H2
            else if isBoldTitle(line) {
                flushBuffer()
                let title = cleanLine.trimmingCharacters(in: .whitespaces)
                if !foundH1 {
                    blocks.append(.h1(title))
                    foundH1 = true
                } else {
                    blocks.append(.h2(title))
                }
            }
            // 5) Ligne numérotée: 1. Titre = H2
            else if isNumberedTitle(line) {
                flushBuffer()
                let title = removeNumberPrefix(line)
                blocks.append(.h2(title))
            }
            // 6) SOURCES:
            else if line.uppercased().hasPrefix("SOURCES:") || line.uppercased().hasPrefix("SOURCE:") {
                flushBuffer()
                let rawNames = line.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
                let parts = rawNames.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                blocks.append(.sources(parts))
            }
            // 7) Liste
            else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flushBuffer()
                let content = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                blocks.append(.listItem(content))
            }
            // 8) Ligne vide = fin de paragraphe
            else if line.isEmpty {
                flushBuffer()
            }
            // 9) Heuristique: ligne courte isolée entre lignes vides = probablement un titre H2
            else if isLikelyTitle(line: line, prevLine: i > 0 ? lines[i-1] : "", nextLine: i < lines.count - 1 ? lines[i+1] : "") {
                flushBuffer()
                if !foundH1 {
                    blocks.append(.h1(cleanLine))
                    foundH1 = true
                } else {
                    blocks.append(.h2(cleanLine))
                }
            }
            // 10) Sinon c'est du texte de paragraphe
            else {
                buffer.append(line)
            }
            
            i += 1
        }
        flushBuffer()
        
        // Log le résultat du parsing
        let h1Count = blocks.filter { if case .h1 = $0 { return true }; return false }.count
        let h2Count = blocks.filter { if case .h2 = $0 { return true }; return false }.count
        let paraCount = blocks.filter { if case .paragraph = $0 { return true }; return false }.count
        print("[Newsletter Parser] Résultat: H1=\(h1Count), H2=\(h2Count), paragraphes=\(paraCount)")
        
        return blocks
    }
    
    /// Heuristique: une ligne courte entre deux lignes vides est probablement un titre
    private func isLikelyTitle(line: String, prevLine: String, nextLine: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let cleanLine = trimmed.replacingOccurrences(of: "**", with: "")
        
        // Doit être court (titre typique)
        guard cleanLine.count >= 5 && cleanLine.count <= 80 else { return false }
        
        // La ligne précédente doit être vide
        guard prevLine.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        
        // Commence par une majuscule
        guard let first = cleanLine.first, first.isUppercase else { return false }
        
        // Ne contient pas de point au milieu (sinon c'est une phrase)
        let withoutEnd = cleanLine.dropLast()
        if withoutEnd.contains(".") || withoutEnd.contains("!") || withoutEnd.contains("?") { return false }
        
        return true
    }
    
    /// Détecte si une ligne est un titre en gras seul (ex: "**Titre de section**")
    private func isBoldTitle(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Doit commencer et finir par ** et avoir du contenu entre
        guard trimmed.hasPrefix("**") && trimmed.hasSuffix("**") else { return false }
        let inner = trimmed.dropFirst(2).dropLast(2)
        // Pas d'autres ** à l'intérieur (sinon c'est juste du texte avec du gras)
        guard !inner.contains("**") else { return false }
        // Longueur raisonnable pour un titre (pas trop long)
        return inner.count > 3 && inner.count < 100
    }
    
    /// Détecte si une ligne est un titre numéroté (ex: "1. Titre", "2. Section")
    private func isNumberedTitle(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Pattern: chiffre(s) + point + espace + texte court
        let pattern = #"^\d{1,2}\.\s+.{5,80}$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return regex.firstMatch(in: trimmed, range: range) != nil
    }
    
    /// Supprime le préfixe numéroté d'un titre
    private func removeNumberPrefix(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let dotIndex = trimmed.firstIndex(of: ".") {
            let afterDot = trimmed[trimmed.index(after: dotIndex)...]
            return afterDot.trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }
    
    /// Vérifie si c'est le premier H2 du document
    private func isFirstH2(blocks: [Block], currentIndex: Int) -> Bool {
        for i in 0..<currentIndex {
            if case .h2 = blocks[i] { return false }
        }
        return true
    }
    
    /// Trouve les indices des premiers paragraphes après chaque H2
    private func findFirstParagraphsAfterH2(blocks: [Block]) -> Set<Int> {
        var result: Set<Int> = []
        var afterH2 = false
        for (idx, block) in blocks.enumerated() {
            switch block {
            case .h2:
                afterH2 = true
            case .paragraph:
                if afterH2 {
                    result.insert(idx)
                    afterH2 = false
                }
            default:
                break
            }
        }
        return result
    }

    private func imageAt(index: Int) -> URL? {
        guard index >= 0, index < feedService.newsletterImageURLs.count else { return nil }
        return feedService.newsletterImageURLs[index]
    }

    private func sectionImageURL(for names: [String]) -> URL? {
        // Tenter de trouver une image d'article du jour provenant d'un des flux listés
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? Date()
        let feedIds: Set<UUID> = Set(names.compactMap { name in bestMatchingFeed(for: name)?.id })
        if feedIds.isEmpty { return nil }
        // Parcourir les articles du jour, plus récents d'abord
        let candidates = feedService.articles.filter { art in
            guard feedIds.contains(art.feedId) else { return false }
            let d = art.publishedAt ?? .distantPast
            guard d >= start && d < end else { return false }
            guard let u = art.imageURL, !isYouTube(u) else { return false }
            return true
        }.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        // Choisir la première image différente du héro
        return candidates.first(where: { $0.imageURL != nil && $0.imageURL != feedService.newsletterHeroURL })?.imageURL
    }

    private func isYouTube(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host.contains("youtube.com") || host.contains("youtu.be")
    }

    // Vidéos d'aujourd'hui (3 max) pour embed dans la newsletter
    private func todayVideoURLs() -> [URL] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? Date()
        var urls: [URL] = []
        var seen = Set<URL>()
        for art in feedService.articles {
            guard let d = art.publishedAt, d >= start && d < end else { continue }
            let u = art.url
            if isYouTube(u) && !seen.contains(u) {
                urls.append(u)
                seen.insert(u)
                if urls.count >= 3 { break }
            }
        }
        return urls
    }

    private func selectParagraphImageMap(blocks: [Block]) -> [Int: URL] {
        var result: [Int: URL] = [:]
        let keywordImageMap = feedService.newsletterArticleTitleImageMap
        // Exclure l'image hero de façon robuste (comparaison par absoluteString pour éviter les problèmes d'URL)
        let heroString = feedService.newsletterHeroURL?.absoluteString ?? ""
        let allImages = feedService.newsletterImageURLs.filter { $0.absoluteString != heroString }
        
        print("[Newsletter] Images disponibles: \(allImages.count), Keywords map: \(keywordImageMap.count), Hero exclu: \(heroString)")
        guard !allImages.isEmpty else { return result }
        
        // Collecter les sections: titre H2 + texte des paragraphes + index du dernier paragraphe
        var sections: [(title: String, text: String, lastParagraphIdx: Int)] = []
        var currentTitle = ""
        var currentText = ""
        var currentLastParagraph: Int? = nil
        
        for (idx, block) in blocks.enumerated() {
            switch block {
            case .h1(let t):
                // Sauvegarder section précédente si existe
                if let lastPara = currentLastParagraph, !currentTitle.isEmpty {
                    sections.append((currentTitle, currentText, lastPara))
                }
                currentTitle = t
                currentText = ""
                currentLastParagraph = nil
            case .h2(let t):
                // Sauvegarder section précédente si existe
                if let lastPara = currentLastParagraph {
                    sections.append((currentTitle, currentText, lastPara))
                }
                currentTitle = t
                currentText = ""
                currentLastParagraph = nil
            case .paragraph(let t):
                currentText += " " + t
                currentLastParagraph = idx
            default:
                break
            }
        }
        // Ajouter la dernière section
        if let lastPara = currentLastParagraph {
            sections.append((currentTitle, currentText, lastPara))
        }
        
        print("[Newsletter] Sections à matcher: \(sections.count)")
        
        // Pour chaque section, chercher une image via les mots-clés
        var usedImages = Set<URL>()
        for section in sections {
            let sectionWords = (section.title + " " + section.text).lowercased()
            var bestMatch: (keyword: String, image: URL)? = nil
            
            for (keyword, imageURL) in keywordImageMap where !usedImages.contains(imageURL) {
                if sectionWords.contains(keyword) {
                    bestMatch = (keyword, imageURL)
                    break
                }
            }
            
            if let match = bestMatch {
                result[section.lastParagraphIdx] = match.image
                usedImages.insert(match.image)
                print("[Newsletter] Match '\(match.keyword)' -> paragraphe \(section.lastParagraphIdx)")
            }
        }
        
        // Fallback: distribuer les images restantes aux sections sans image (max 3)
        let sectionsWithoutImage = sections.filter { result[$0.lastParagraphIdx] == nil }
        let remainingImages = allImages.filter { !usedImages.contains($0) }
        let maxFallback = min(3, remainingImages.count, sectionsWithoutImage.count)
        for i in 0..<maxFallback {
            result[sectionsWithoutImage[i].lastParagraphIdx] = remainingImages[i]
        }
        
        print("[Newsletter] Images assignées: \(result.count)")
        return result
    }
    

    private func selectParagraphSourcesMap(blocks: [Block]) -> [Int: [String]] {
        var result: [Int: [String]] = [:]
        var lastContentIndex: Int? = nil
        for (idx, block) in blocks.enumerated() {
            switch block {
            case .paragraph:
                lastContentIndex = idx
            case .listItem:
                lastContentIndex = idx
            case .h2:
                lastContentIndex = idx
            case .sources(let names):
                guard let ai = lastContentIndex else { continue }
                result[ai] = names
            default:
                break
            }
        }
        return result
    }

    @ViewBuilder
    private func editorialImage(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFill()
            case .failure:
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary.opacity(0.3))
                    }
            case .empty:
                Rectangle()
                    .fill(Color.gray.opacity(0.08))
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
            @unknown default:
                Rectangle().fill(Color.gray.opacity(0.1))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func heroImageView(url: URL) -> some View {
        #if os(macOS)
        if url.isFileURL, let nsimg = NSImage(contentsOf: url) {
            Image(nsImage: nsimg).resizable().scaledToFill()
        } else {
            AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: {
                LinearGradient(colors: [Color.gray.opacity(0.12), Color.gray.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        #elseif os(iOS)
        if url.isFileURL, let uiimg = UIImage(contentsOfFile: url.path) {
            Image(uiImage: uiimg).resizable().scaledToFill()
        } else {
            AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: {
                LinearGradient(colors: [Color.gray.opacity(0.12), Color.gray.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        #else
        AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: {
            LinearGradient(colors: [Color.gray.opacity(0.12), Color.gray.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        #endif
    }

    private func localizedFooterText() -> String {
        switch LocalizationManager.shared.currentLanguage {
        case .french: return "Généré par IA mais avec amour par Flux."
        case .english: return "Generated by AI, with love by Flux."
        case .spanish: return "Generado por IA, con amor por Flux."
        case .german: return "Von KI erstellt – mit Liebe von Flux."
        case .italian: return "Generato dall'IA, con amore da Flux."
        case .portuguese: return "Gerado por IA, com carinho pela Flux."
        case .japanese: return "AI によって生成、Flux の愛を込めて。"
        case .chinese: return "由 AI 生成，凝聚 Flux 的心意。"
        case .korean: return "AI가 생성했지만, Flux의 사랑을 담아."
        case .russian: return "Создано ИИ, с любовью от Flux."
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
        return String(prefix) + "…"
    }

    // MARK: - Favicons helpers
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

    private func feedFaviconURL(for title: String) -> URL? {
        guard let feed = bestMatchingFeed(for: title) else { return nil }
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

    private func bestMatchingFeed(for name: String) -> Feed? {
        let target = normalizeTitle(name)
        if let exact = feedService.feeds.first(where: { normalizeTitle($0.title) == target }) { return exact }
        // Contient
        if let contains = feedService.feeds.first(where: { normalizeTitle($0.title).contains(target) || target.contains(normalizeTitle($0.title)) }) { return contains }
        // Levenshtein simplifié: choisir le plus proche par distance de préfixe
        return feedService.feeds.min { a, b in
            let da = distance(normalizeTitle(a.title), target)
            let db = distance(normalizeTitle(b.title), target)
            return da < db
        }
    }

    private func normalizeTitle(_ s: String) -> String {
        return s.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private func distance(_ a: String, _ b: String) -> Int {
        // distance de Levenshtein très simple (optimisée pour petites chaînes)
        let aChars = Array(a)
        let bChars = Array(b)
        var dp = Array(repeating: Array(repeating: 0, count: bChars.count + 1), count: aChars.count + 1)
        for i in 0...aChars.count { dp[i][0] = i }
        for j in 0...bChars.count { dp[0][j] = j }
        if !aChars.isEmpty && !bChars.isEmpty {
            for i in 1...aChars.count {
                for j in 1...bChars.count {
                    let cost = (aChars[i-1] == bChars[j-1]) ? 0 : 1
                    dp[i][j] = min(dp[i-1][j] + 1, dp[i][j-1] + 1, dp[i-1][j-1] + cost)
                }
            }
        }
        return dp[aChars.count][bChars.count]
    }

    @ViewBuilder
    private func sourcesRow(_ names: [String]) -> some View {
        if names.isEmpty { EmptyView() } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(names, id: \.self) { name in
                        let icon = feedFaviconURL(for: name)
                        Group {
                            if let icon {
                                AsyncImage(url: icon) { img in img.resizable().scaledToFit() } placeholder: { Color.gray.opacity(0.15) }
                            } else {
                                Image(systemName: "globe")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .help(name)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// Préférence pour remonter le défilement
private struct NewsletterScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct FeedTimelineView: View {
    @Environment(FeedService.self) private var feedService
    @State private var webURL: URL? = nil
    @State private var lastTopArticleId: UUID? = nil
    private let lm = LocalizationManager.shared

    private var articles: [Article] {
        feedService.articles
            .filter { !isYouTube($0.url) }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    var body: some View {
        if let url = webURL {
            WebDrawer(url: url, startInReaderMode: true, forceAISummary: true) {
                withAnimation(.easeInOut(duration: 0.28)) { webURL = nil }
            }
        } else {
            GeometryReader { proxy in
                let available = proxy.size.width
                let sidePadding = feedSidePadding(for: available)
                let contentWidth = min(900, max(0, available - sidePadding * 2))
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Color.clear
                                .frame(height: 0)
                                .id("feed-top")
                            header
                            if articles.isEmpty {
                                Text(lm.localizedString(.noArticles))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
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
                                    }
                                }
                            }
                        }
                        .frame(width: contentWidth, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, sidePadding)
                        .padding(.top, 20)
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
        withAnimation(.easeInOut(duration: 0.28)) {
            webURL = url
        }
    }
    
    private func feedSidePadding(for available: CGFloat) -> CGFloat {
        if available < 520 { return 8 }
        if available < 760 { return 12 }
        return 16
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
        return String(prefix) + "…"
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
        let scaled = width * (isCompact ? 0.42 : 0.48)
        return min(max(200, scaled), 320)
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
                        AsyncImage(url: thumbnailURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            case .failure:
                                Color.gray.opacity(0.2)
                            case .empty:
                                Color.gray.opacity(0.12)
                            @unknown default:
                                Color.gray.opacity(0.12)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: imageHeight)
                        .clipped()
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

#Preview {
    NewsletterView().environment(FeedService(context: try! ModelContext(ModelContainer(for: Feed.self))))
}

// (Suppression du bloc de vidéos embed externe du bottom de fichier pour éviter les doublons)

/// Vue pour afficher une miniature YouTube cliquable (évite les erreurs d'embedding 150/152/153)
struct YouTubeIframeView: View {
    let videoURL: URL
    var onTap: ((URL) -> Void)? = nil
    @State private var isHovering = false

    var body: some View {
        if let videoId = extractVideoId(videoURL) {
            ZStack {
                // Miniature YouTube
                AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(videoId)/maxresdefault.jpg")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fit)
                    case .failure:
                        // Fallback sur miniature standard si maxres échoue
                        AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg")) { p2 in
                            if let img = p2.image {
                                img.resizable().aspectRatio(16/9, contentMode: .fit)
                            } else {
                                Rectangle().fill(Color.black).aspectRatio(16/9, contentMode: .fit)
                            }
                        }
                    case .empty:
                        Rectangle()
                            .fill(Color.black.opacity(0.3))
                            .aspectRatio(16/9, contentMode: .fit)
                            .overlay(ProgressView())
                    @unknown default:
                        Rectangle().fill(Color.black).aspectRatio(16/9, contentMode: .fit)
                    }
                }
                .cornerRadius(12)

                // Bouton play YouTube
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(isHovering ? 1 : 0.85))
                    .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 2)
                    .scaleEffect(isHovering ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isHovering)
            }
            #if os(macOS)
            .onHover { hovering in
                isHovering = hovering
            }
            #endif
            .onTapGesture {
                if let action = onTap {
                    action(videoURL)
                } else {
                    #if os(macOS)
                    NSWorkspace.shared.open(videoURL)
                    #elseif os(iOS)
                    UIApplication.shared.open(videoURL)
                    #endif
                }
            }
            #if os(macOS)
            .help(LocalizationManager.shared.localizedString(.helpOpenVideo))
            #endif
        }
    }

    private func extractVideoId(_ url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        if host.contains("youtube.com"), let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            return comps.queryItems?.first(where: { $0.name == "v" })?.value
        }
        if host.contains("youtu.be") {
            return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        let parts = url.path.split(separator: "/").map(String.init)
        if let i = parts.firstIndex(of: "embed"), parts.count > i+1 { return parts[i+1] }
        if let i = parts.firstIndex(of: "live"), parts.count > i+1 { return parts[i+1] }
        if let i = parts.firstIndex(of: "shorts"), parts.count > i+1 { return parts[i+1] }
        return nil
    }
}


// MARK: - Loading Overlay
private struct NewsletterLoadingOverlay: View {
    @Environment(FeedService.self) private var feedService
    @State private var fade: Bool = false
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)
                .opacity(fade ? 0.45 : 0.25)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gray.opacity(0.25))
                    .frame(maxWidth: 840)
                    .frame(height: 220)
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.28)).frame(width: 220, height: 18)
                    RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.22)).frame(width: 540, height: 12)
                    RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.20)).frame(width: 520, height: 12)
                    RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.18)).frame(width: 480, height: 12)
                }
                .frame(maxWidth: 840, alignment: .leading)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                fade.toggle()
            }
        }
    }
}
