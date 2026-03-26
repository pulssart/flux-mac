// Models.swift
// Flux
// Données principales (SwiftData)
import Foundation
import SwiftData

@Model
final class Feed: Identifiable {
    @Attribute(.unique)
    var id: UUID
    var title: String
    var siteURL: URL?
    var feedURL: URL
    var faviconURL: URL?
    var tags: [String]
    var addedAt: Date
    // Index d'ordre pour la sidebar (drag & drop). Optionnel pour permettre la migration soft.
    var sortIndex: Int?
    // Association optionnelle à un dossier (organisation dans la sidebar)
    var folderId: UUID?
    
    init(id: UUID = UUID(), title: String, siteURL: URL? = nil, feedURL: URL, faviconURL: URL? = nil, tags: [String] = [], addedAt: Date = .now, sortIndex: Int? = nil, folderId: UUID? = nil) {
        self.id = id
        self.title = title
        self.siteURL = siteURL
        self.feedURL = feedURL
        self.faviconURL = faviconURL
        self.tags = tags
        self.addedAt = addedAt
        self.sortIndex = sortIndex
        self.folderId = folderId
    }
}

@Model
final class Article: Identifiable {
    @Attribute(.unique)
    var id: UUID
    var feedId: UUID
    var title: String
    var url: URL
    var author: String?
    var publishedAt: Date?
    var contentHTML: String?
    var contentText: String?
    var imageURL: URL?
    var summary: String?
    var readingTime: Int?
    var lang: String?
    var score: Double?
    var isRead: Bool
    var isSaved: Bool
    
    init(id: UUID = UUID(), feedId: UUID, title: String, url: URL, author: String? = nil, publishedAt: Date? = nil, contentHTML: String? = nil, contentText: String? = nil, imageURL: URL? = nil, summary: String? = nil, readingTime: Int? = nil, lang: String? = nil, score: Double? = nil, isRead: Bool = false, isSaved: Bool = false) {
        self.id = id
        self.feedId = feedId
        self.title = title
        self.url = url
        self.author = author
        self.publishedAt = publishedAt
        self.contentHTML = contentHTML
        self.contentText = contentText
        self.imageURL = imageURL
        self.summary = summary
        self.readingTime = readingTime
        self.lang = lang
        self.score = score
        self.isRead = isRead
        self.isSaved = isSaved
    }
}

@Model
final class ReaderNote: Identifiable {
    @Attribute(.unique)
    var id: UUID
    var articleId: UUID?
    var feedId: UUID?
    var articleTitle: String
    var articleURL: URL
    var articleImageURL: URL?
    var articleSource: String?
    var articlePublishedAt: Date?
    var selectedText: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        articleId: UUID? = nil,
        feedId: UUID? = nil,
        articleTitle: String,
        articleURL: URL,
        articleImageURL: URL? = nil,
        articleSource: String? = nil,
        articlePublishedAt: Date? = nil,
        selectedText: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.articleId = articleId
        self.feedId = feedId
        self.articleTitle = articleTitle
        self.articleURL = articleURL
        self.articleImageURL = articleImageURL
        self.articleSource = articleSource
        self.articlePublishedAt = articlePublishedAt
        self.selectedText = selectedText
        self.createdAt = createdAt
    }
}

@Model
final class Suggestion: Identifiable {
    @Attribute(.unique)
    var id: UUID
    var title: String
    var url: URL
    var reason: String?
    var score: Double?
    var createdAt: Date
    
    init(id: UUID = UUID(), title: String, url: URL, reason: String? = nil, score: Double? = nil, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.url = url
        self.reason = reason
        self.score = score
        self.createdAt = createdAt
    }
}

@Model
final class Settings: Identifiable {
    @Attribute(.unique)
    var id: UUID
    var theme: String
    var ttsVoice: String?
    var ttsRate: Double
    var preferredLangs: [String]
    var aiProviderConfig: Data? // Stockage des settings AI sérialisés
    var imageScrapingEnabled: Bool
    var windowBlurEnabled: Bool?
    var hideTitleOnThumbnails: Bool?
    var filterAdsEnabled: Bool?

    init(id: UUID = UUID(), theme: String = "system", ttsVoice: String? = nil, ttsRate: Double = 1.0, preferredLangs: [String] = ["fr", "en"], aiProviderConfig: Data? = nil, imageScrapingEnabled: Bool = true, windowBlurEnabled: Bool? = nil, hideTitleOnThumbnails: Bool? = nil, filterAdsEnabled: Bool? = false) {
        self.id = id
        self.theme = theme
        self.ttsVoice = ttsVoice
        self.ttsRate = ttsRate
        self.preferredLangs = preferredLangs
        self.aiProviderConfig = aiProviderConfig
        self.imageScrapingEnabled = imageScrapingEnabled
        self.windowBlurEnabled = windowBlurEnabled
        self.hideTitleOnThumbnails = hideTitleOnThumbnails
        self.filterAdsEnabled = filterAdsEnabled
    }
}

@Model
final class Folder: Identifiable {
    @Attribute(.unique)
    var id: UUID
    var name: String
    // Ordre d'affichage des dossiers (drag & drop)
    var sortIndex: Int?
    var createdAt: Date

    init(id: UUID = UUID(), name: String, sortIndex: Int? = nil, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}

// MARK: - Modèles pour l'export/import de configuration

/// Configuration exportable de l'application Flux
struct FluxConfiguration: Codable {
    let version: String
    let exportedAt: Date
    let feeds: [FeedExportData]
    let folders: [FolderExportData]
    let settings: SettingsExportData?
}

/// Données exportables d'un flux
struct FeedExportData: Codable {
    let id: UUID
    let title: String
    let siteURL: String?
    let feedURL: String
    let faviconURL: String?
    let tags: [String]
    let addedAt: Date
    let sortIndex: Int?
    let folderId: UUID?
    let isYouTube: Bool
}

/// Données exportables d'un dossier
struct FolderExportData: Codable {
    let id: UUID
    let name: String
    let sortIndex: Int?
    let createdAt: Date
}

/// Données exportables des paramètres
struct SettingsExportData: Codable {
    let theme: String
    let ttsVoice: String?
    let ttsRate: Double
    let preferredLangs: [String]
    let aiProviderConfig: Data?
    let imageScrapingEnabled: Bool
    let windowBlurEnabled: Bool?
    let hideTitleOnThumbnails: Bool?
    let filterAdsEnabled: Bool?
}

/// Résumé d'un import de configuration
struct ImportSummary {
    let importedFeeds: Int
    let importedFolders: Int
    let skippedFeeds: Int
    let skippedFolders: Int
}
