// RSSFeedSuggestions.swift
// Catalogue éditorial de flux RSS prêts à ajouter

import Foundation

struct RSSFeedSuggestion: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: String
    let category: String
    let note: String
    let siteURL: String?

    var displayName: String {
        "\(name) • \(category)"
    }

    var preferredURLString: String {
        siteURL ?? url
    }

    var hostLabel: String {
        guard let host = URL(string: preferredURLString)?.host?.lowercased() else {
            return url
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    var faviconURL: URL? {
        guard let host = URL(string: preferredURLString)?.host?.lowercased() else { return nil }
        return URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")
    }
}

class RSSFeedSuggestionsManager {
    static let shared = RSSFeedSuggestionsManager()

    private let featuredNames: Set<String> = [
        "Le Monde",
        "The Verge",
        "9to5Mac",
        "OpenAI Blog",
        "Quanta Magazine",
        "MKBHD"
    ]

    private let suggestions: [RSSFeedSuggestion] = [
        // ===== TECH =====
        RSSFeedSuggestion(name: "TechCrunch", url: "https://techcrunch.com/feed/", category: "Tech", note: "Startups, produits et mouvements du secteur tech.", siteURL: "https://techcrunch.com"),
        RSSFeedSuggestion(name: "The Verge", url: "https://www.theverge.com/rss/index.xml", category: "Tech", note: "Un mix grand public entre tech, culture web et hardware.", siteURL: "https://www.theverge.com"),
        RSSFeedSuggestion(name: "Wired", url: "https://www.wired.com/feed/rss", category: "Tech", note: "Technologie, design et société dans un ton magazine.", siteURL: "https://www.wired.com"),
        RSSFeedSuggestion(name: "Hacker News", url: "https://news.ycombinator.com/rss", category: "Tech", note: "Les liens tech les plus relayés du moment.", siteURL: "https://news.ycombinator.com"),
        RSSFeedSuggestion(name: "Hacker News: Best", url: "https://hnrss.org/best", category: "Tech", note: "Une sélection plus resserrée des meilleurs posts HN.", siteURL: "https://news.ycombinator.com"),

        // ===== ENGINEERING =====
        RSSFeedSuggestion(name: "GitHub Blog", url: "https://github.blog/feed/", category: "Engineering", note: "Produit, open source et coulisses de la plateforme.", siteURL: "https://github.blog"),
        RSSFeedSuggestion(name: "Cloudflare Blog", url: "https://blog.cloudflare.com/rss/", category: "Engineering", note: "Infra, sécurité, web performance et réseau.", siteURL: "https://blog.cloudflare.com"),
        RSSFeedSuggestion(name: "Stripe Blog", url: "https://stripe.com/blog/feed.rss", category: "Engineering", note: "Produit, paiements et très bon contenu d’exécution.", siteURL: "https://stripe.com/blog"),

        // ===== DEVELOPERS =====
        RSSFeedSuggestion(name: "CSS Tricks", url: "https://css-tricks.com/feed/", category: "Dev", note: "Frontend clair, concret et facile à suivre.", siteURL: "https://css-tricks.com"),
        RSSFeedSuggestion(name: "Smashing Magazine", url: "https://www.smashingmagazine.com/feed/", category: "Dev", note: "Design web, UX et développement côté produit.", siteURL: "https://www.smashingmagazine.com"),
        RSSFeedSuggestion(name: "Dev.to", url: "https://dev.to/feed", category: "Dev", note: "Une source vivante pour découvrir des retours terrain.", siteURL: "https://dev.to"),

        // ===== AI =====
        RSSFeedSuggestion(name: "OpenAI Blog", url: "https://openai.com/blog/rss.xml", category: "AI", note: "Annonces, recherches et nouveautés IA officielles.", siteURL: "https://openai.com"),
        RSSFeedSuggestion(name: "Google AI Blog", url: "https://blog.google/technology/ai/rss/", category: "AI", note: "Actualité IA côté Google, souvent orientée produit.", siteURL: "https://blog.google/technology/ai"),

        // ===== SCIENCE =====
        RSSFeedSuggestion(name: "Science Daily", url: "https://www.sciencedaily.com/rss/all.xml", category: "Science", note: "Un bon flux large pour surveiller la recherche.", siteURL: "https://www.sciencedaily.com"),
        RSSFeedSuggestion(name: "Quanta Magazine", url: "https://www.quantamagazine.org/feed/", category: "Science", note: "Excellent pour des sujets scientifiques bien racontés.", siteURL: "https://www.quantamagazine.org"),
        RSSFeedSuggestion(name: "Nature", url: "https://www.nature.com/nature.rss", category: "Science", note: "Référence solide pour suivre les grandes publications.", siteURL: "https://www.nature.com"),

        // ===== APPLE =====
        RSSFeedSuggestion(name: "9to5Mac", url: "https://9to5mac.com/feed/", category: "Apple", note: "Une base très fiable pour l’actualité Apple au quotidien.", siteURL: "https://9to5mac.com"),
        RSSFeedSuggestion(name: "MacRumors", url: "https://feeds.macrumors.com/MacRumors-All", category: "Apple", note: "Rumeurs, sorties et couverture très réactive.", siteURL: "https://www.macrumors.com"),
        RSSFeedSuggestion(name: "Daring Fireball", url: "https://daringfireball.net/feeds/main", category: "Apple", note: "Analyse éditoriale plus personnelle et souvent très juste.", siteURL: "https://daringfireball.net"),
        RSSFeedSuggestion(name: "MacStories", url: "https://www.macstories.net/feed/", category: "Apple", note: "Approche plus posée, très utile pour iPad et productivité.", siteURL: "https://www.macstories.net"),

        // ===== SWIFT =====
        RSSFeedSuggestion(name: "Swift by Sundell", url: "https://www.swiftbysundell.com/rss", category: "Swift", note: "Une référence pédagogique autour de Swift et de l’architecture.", siteURL: "https://www.swiftbysundell.com"),
        RSSFeedSuggestion(name: "Hacking with Swift", url: "https://www.hackingwithswift.com/articles/rss", category: "Swift", note: "Très pratique pour apprendre ou se remettre à niveau.", siteURL: "https://www.hackingwithswift.com"),
        RSSFeedSuggestion(name: "SwiftLee", url: "https://www.avanderlee.com/feed/", category: "Swift", note: "Bon équilibre entre profondeur technique et clarté.", siteURL: "https://www.avanderlee.com"),

        // ===== NEWS =====
        RSSFeedSuggestion(name: "BBC News", url: "https://feeds.bbci.co.uk/news/rss.xml", category: "News", note: "Une bonne porte d’entrée pour l’actualité internationale.", siteURL: "https://www.bbc.com/news"),
        RSSFeedSuggestion(name: "The Guardian", url: "https://www.theguardian.com/world/rss", category: "News", note: "Une couverture large avec beaucoup de rythme.", siteURL: "https://www.theguardian.com"),
        RSSFeedSuggestion(name: "NY Times", url: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml", category: "News", note: "Un classique pour suivre les grands sujets du jour.", siteURL: "https://www.nytimes.com"),

        // ===== GAMING =====
        RSSFeedSuggestion(name: "Polygon", url: "https://www.polygon.com/rss/index.xml", category: "Gaming", note: "Jeux vidéo et culture internet dans un ton magazine.", siteURL: "https://www.polygon.com"),
        RSSFeedSuggestion(name: "Kotaku", url: "https://kotaku.com/rss", category: "Gaming", note: "Actu jeux vidéo rapide et très éditorialisée.", siteURL: "https://kotaku.com"),

        // ===== FRANCE =====
        RSSFeedSuggestion(name: "Le Monde", url: "https://www.lemonde.fr/rss/une.xml", category: "France", note: "Un bon point de départ pour un fil d’actualité généraliste.", siteURL: "https://www.lemonde.fr"),
        RSSFeedSuggestion(name: "Numerama", url: "https://www.numerama.com/feed/", category: "France", note: "Tech, numérique et culture web côté francophone.", siteURL: "https://www.numerama.com"),
        RSSFeedSuggestion(name: "Korben", url: "https://korben.info/feed", category: "France", note: "Culture geek, outils web et veille plus indépendante.", siteURL: "https://korben.info"),
        RSSFeedSuggestion(name: "Next", url: "https://next.ink/feed/", category: "France", note: "Tech et numérique avec une approche plus analytique.", siteURL: "https://next.ink"),

        // ===== YOUTUBE =====
        RSSFeedSuggestion(name: "Fireship", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCsBjURrPoezykLs9EqgamOA", category: "YouTube", note: "Chaîne parfaite pour un flux rapide sur le dev et la tech.", siteURL: "https://www.youtube.com/@Fireship"),
        RSSFeedSuggestion(name: "MKBHD", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCBJycsmduvYEL83R_U4JriQ", category: "YouTube", note: "Très bon ajout pour suivre le hardware et les lancements.", siteURL: "https://www.youtube.com/@mkbhd"),
        RSSFeedSuggestion(name: "Kurzgesagt", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCsXVk37bltHxD1rDPwtNM8Q", category: "YouTube", note: "Science et vulgarisation avec des vidéos très fortes visuellement.", siteURL: "https://www.youtube.com/@kurzgesagt")
    ]

    func search(_ query: String) -> [RSSFeedSuggestion] {
        filtered(query: query, category: nil)
            .prefix(10)
            .map { $0 }
    }

    func filtered(query: String, category: String?) -> [RSSFeedSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return suggestions.filter { suggestion in
            let matchesCategory = category == nil || suggestion.category == category
            guard matchesCategory else { return false }
            guard !trimmed.isEmpty else { return true }
            return suggestion.name.lowercased().contains(trimmed) ||
                suggestion.category.lowercased().contains(trimmed) ||
                suggestion.note.lowercased().contains(trimmed) ||
                suggestion.url.lowercased().contains(trimmed) ||
                suggestion.hostLabel.lowercased().contains(trimmed)
        }
    }

    func popular() -> [RSSFeedSuggestion] {
        let featured = suggestions.filter { featuredNames.contains($0.name) }
        return featured.isEmpty ? Array(suggestions.prefix(6)) : featured
    }

    func allCategories() -> [String] {
        var categories: [String] = []
        for suggestion in suggestions where !categories.contains(suggestion.category) {
            categories.append(suggestion.category)
        }
        return categories
    }

    func byCategory(_ category: String) -> [RSSFeedSuggestion] {
        suggestions.filter { $0.category == category }
    }
}
