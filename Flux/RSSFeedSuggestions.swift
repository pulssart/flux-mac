// RSSFeedSuggestions.swift
// Liste minimale de flux RSS ultra-fiables

import Foundation

struct RSSFeedSuggestion: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: String
    let category: String?
    
    var displayName: String {
        if let category = category {
            return "\(name) • \(category)"
        }
        return name
    }
}

class RSSFeedSuggestionsManager {
    static let shared = RSSFeedSuggestionsManager()
    
    private let suggestions: [RSSFeedSuggestion] = [
        // ===== TECH =====
        RSSFeedSuggestion(name: "TechCrunch", url: "https://techcrunch.com/feed/", category: "Tech"),
        RSSFeedSuggestion(name: "The Verge", url: "https://www.theverge.com/rss/index.xml", category: "Tech"),
        RSSFeedSuggestion(name: "Ars Technica", url: "https://feeds.arstechnica.com/arstechnica/index", category: "Tech"),
        RSSFeedSuggestion(name: "Wired", url: "https://www.wired.com/feed/rss", category: "Tech"),
        RSSFeedSuggestion(name: "Hacker News", url: "https://news.ycombinator.com/rss", category: "Tech"),
        RSSFeedSuggestion(name: "Hacker News: Best", url: "https://hnrss.org/best", category: "Tech"),
        
        // ===== ENGINEERING =====
        RSSFeedSuggestion(name: "GitHub Blog", url: "https://github.blog/feed/", category: "Engineering"),
        RSSFeedSuggestion(name: "Cloudflare Blog", url: "https://blog.cloudflare.com/rss/", category: "Engineering"),
        RSSFeedSuggestion(name: "Stripe Blog", url: "https://stripe.com/blog/feed.rss", category: "Engineering"),
        
        // ===== DEVELOPERS =====
        RSSFeedSuggestion(name: "CSS Tricks", url: "https://css-tricks.com/feed/", category: "Dev"),
        RSSFeedSuggestion(name: "Smashing Magazine", url: "https://www.smashingmagazine.com/feed/", category: "Dev"),
        RSSFeedSuggestion(name: "Dev.to", url: "https://dev.to/feed", category: "Dev"),
        
        // ===== AI =====
        RSSFeedSuggestion(name: "OpenAI Blog", url: "https://openai.com/blog/rss.xml", category: "AI"),
        RSSFeedSuggestion(name: "Google AI Blog", url: "https://blog.google/technology/ai/rss/", category: "AI"),
        
        // ===== SCIENCE =====
        RSSFeedSuggestion(name: "Science Daily", url: "https://www.sciencedaily.com/rss/all.xml", category: "Science"),
        RSSFeedSuggestion(name: "Quanta Magazine", url: "https://www.quantamagazine.org/feed/", category: "Science"),
        RSSFeedSuggestion(name: "Nature", url: "https://www.nature.com/nature.rss", category: "Science"),
        
        // ===== APPLE =====
        RSSFeedSuggestion(name: "9to5Mac", url: "https://9to5mac.com/feed/", category: "Apple"),
        RSSFeedSuggestion(name: "MacRumors", url: "https://feeds.macrumors.com/MacRumors-All", category: "Apple"),
        RSSFeedSuggestion(name: "Daring Fireball", url: "https://daringfireball.net/feeds/main", category: "Apple"),
        RSSFeedSuggestion(name: "MacStories", url: "https://www.macstories.net/feed/", category: "Apple"),
        
        // ===== SWIFT =====
        RSSFeedSuggestion(name: "Swift by Sundell", url: "https://www.swiftbysundell.com/rss", category: "Swift"),
        RSSFeedSuggestion(name: "Hacking with Swift", url: "https://www.hackingwithswift.com/articles/rss", category: "Swift"),
        RSSFeedSuggestion(name: "SwiftLee", url: "https://www.avanderlee.com/feed/", category: "Swift"),
        
        // ===== NEWS =====
        RSSFeedSuggestion(name: "BBC News", url: "https://feeds.bbci.co.uk/news/rss.xml", category: "News"),
        RSSFeedSuggestion(name: "The Guardian", url: "https://www.theguardian.com/world/rss", category: "News"),
        RSSFeedSuggestion(name: "NY Times", url: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml", category: "News"),
        
        // ===== GAMING =====
        RSSFeedSuggestion(name: "Polygon", url: "https://www.polygon.com/rss/index.xml", category: "Gaming"),
        RSSFeedSuggestion(name: "Kotaku", url: "https://kotaku.com/rss", category: "Gaming"),
        
        // ===== FRANCE =====
        RSSFeedSuggestion(name: "Le Monde", url: "https://www.lemonde.fr/rss/une.xml", category: "France"),
        RSSFeedSuggestion(name: "Numerama", url: "https://www.numerama.com/feed/", category: "France"),
        RSSFeedSuggestion(name: "Korben", url: "https://korben.info/feed", category: "France"),
        RSSFeedSuggestion(name: "Next", url: "https://next.ink/feed/", category: "France"),
        
        // ===== YOUTUBE =====
        RSSFeedSuggestion(name: "Fireship", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCsBjURrPoezykLs9EqgamOA", category: "YouTube"),
        RSSFeedSuggestion(name: "MKBHD", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCBJycsmduvYEL83R_U4JriQ", category: "YouTube"),
        RSSFeedSuggestion(name: "Kurzgesagt", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCsXVk37bltHxD1rDPwtNM8Q", category: "YouTube"),
    ]
    
    func search(_ query: String) -> [RSSFeedSuggestion] {
        guard !query.isEmpty else { return [] }
        let lowercased = query.lowercased()
        return suggestions.filter { suggestion in
            suggestion.name.lowercased().contains(lowercased) ||
            suggestion.category?.lowercased().contains(lowercased) == true ||
            suggestion.url.lowercased().contains(lowercased)
        }
        .prefix(10)
        .map { $0 }
    }
    
    func popular() -> [RSSFeedSuggestion] {
        Array(suggestions.prefix(6))
    }
    
    func allCategories() -> [String] {
        Array(Set(suggestions.compactMap { $0.category })).sorted()
    }
    
    func byCategory(_ category: String) -> [RSSFeedSuggestion] {
        suggestions.filter { $0.category == category }
    }
}
