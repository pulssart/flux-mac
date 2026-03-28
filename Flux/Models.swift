// Models.swift
// Flux
// Données principales (SwiftData)
import Foundation
import SwiftData
import CryptoKit

@Model
final class Feed: Identifiable {
    var id: UUID = UUID()
    var title: String = ""
    var siteURL: URL?
    var feedURL: URL = URL(string: "https://example.com/feed.xml")!
    var faviconURL: URL?
    var tags: [String] = []
    var addedAt: Date = Date()
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
    var id: UUID = UUID()
    var feedId: UUID = UUID()
    var title: String = ""
    var url: URL = URL(string: "https://example.com/article")!
    var author: String?
    var publishedAt: Date?
    var contentHTML: String?
    var contentText: String?
    var imageURL: URL?
    var summary: String?
    var readingTime: Int?
    var lang: String?
    var score: Double?
    var isRead: Bool = false
    var isSaved: Bool = false
    
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
    var id: UUID = UUID()
    var articleId: UUID?
    var feedId: UUID?
    var articleTitle: String = ""
    var articleURL: URL = URL(string: "https://example.com/article")!
    var articleImageURL: URL?
    var articleSource: String?
    var articlePublishedAt: Date?
    var selectedText: String = ""
    var createdAt: Date = Date()

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
    var id: UUID = UUID()
    var title: String = ""
    var url: URL = URL(string: "https://example.com")!
    var reason: String?
    var score: Double?
    var createdAt: Date = Date()
    
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
    static let sharedID = UUID(uuidString: "7D8C6C24-3F9A-4D61-8E8B-2DCC0B9A7E11")!

    var id: UUID = Settings.sharedID
    var theme: String = "system"
    var ttsVoice: String?
    var ttsRate: Double = 1.0
    var preferredLangs: [String] = ["fr", "en"]
    var aiProviderConfig: Data? // Stockage des settings AI sérialisés
    var imageScrapingEnabled: Bool = true
    var windowBlurEnabled: Bool?
    var windowBlurTintOpacity: Double?
    var hideTitleOnThumbnails: Bool?
    var filterAdsEnabled: Bool?
    var notificationsEnabled: Bool?
    var signalNotificationsEnabled: Bool?
    var hapticsEnabled: Bool?
    var alwaysOpenInBrowser: Bool?
    var badgeReadLaterEnabled: Bool?
    var signalFavoriteEventIds: [String] = []

    init(id: UUID = Settings.sharedID, theme: String = "system", ttsVoice: String? = nil, ttsRate: Double = 1.0, preferredLangs: [String] = ["fr", "en"], aiProviderConfig: Data? = nil, imageScrapingEnabled: Bool = true, windowBlurEnabled: Bool? = nil, windowBlurTintOpacity: Double? = nil, hideTitleOnThumbnails: Bool? = nil, filterAdsEnabled: Bool? = false, notificationsEnabled: Bool? = nil, signalNotificationsEnabled: Bool? = true, hapticsEnabled: Bool? = nil, alwaysOpenInBrowser: Bool? = nil, badgeReadLaterEnabled: Bool? = nil, signalFavoriteEventIds: [String] = []) {
        self.id = id
        self.theme = theme
        self.ttsVoice = ttsVoice
        self.ttsRate = ttsRate
        self.preferredLangs = preferredLangs
        self.aiProviderConfig = aiProviderConfig
        self.imageScrapingEnabled = imageScrapingEnabled
        self.windowBlurEnabled = windowBlurEnabled
        self.windowBlurTintOpacity = windowBlurTintOpacity
        self.hideTitleOnThumbnails = hideTitleOnThumbnails
        self.filterAdsEnabled = filterAdsEnabled
        self.notificationsEnabled = notificationsEnabled
        self.signalNotificationsEnabled = signalNotificationsEnabled
        self.hapticsEnabled = hapticsEnabled
        self.alwaysOpenInBrowser = alwaysOpenInBrowser
        self.badgeReadLaterEnabled = badgeReadLaterEnabled
        self.signalFavoriteEventIds = signalFavoriteEventIds
    }
}

@Model
final class Folder: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    // Ordre d'affichage des dossiers (drag & drop)
    var sortIndex: Int?
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String, sortIndex: Int? = nil, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}

@Model
final class SignalFavorite: Identifiable {
    var id: UUID = UUID()
    var eventId: String = ""
    var createdAt: Date = Date()

    static func stableID(for eventId: String) -> UUID {
        let digest = SHA256.hash(data: Data(eventId.utf8))
        let bytes = Array(digest.prefix(16))
        let uuidBytes: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuidBytes)
    }

    init(id: UUID? = nil, eventId: String, createdAt: Date = .now) {
        self.id = id ?? Self.stableID(for: eventId)
        self.eventId = eventId
        self.createdAt = createdAt
    }

    convenience init(eventId: String, createdAt: Date = .now) {
        self.init(id: Self.stableID(for: eventId), eventId: eventId, createdAt: createdAt)
    }

    init(id: UUID = UUID(), eventId: String, createdAt: Date = .now, legacy: Bool) {
        self.id = id
        self.eventId = eventId
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
    let windowBlurTintOpacity: Double?
    let hideTitleOnThumbnails: Bool?
    let filterAdsEnabled: Bool?
    let notificationsEnabled: Bool?
    let signalNotificationsEnabled: Bool?
    let hapticsEnabled: Bool?
    let alwaysOpenInBrowser: Bool?
    let badgeReadLaterEnabled: Bool?
    let signalFavoriteEventIds: [String]?
}

/// Résumé d'un import de configuration
struct ImportSummary {
    let importedFeeds: Int
    let importedFolders: Int
    let skippedFeeds: Int
    let skippedFolders: Int
}
