import Foundation
import SwiftData

// Configuration par défaut pour les nouveaux utilisateurs (export par défaut)
// Contenu JSON basé sur l'exemple fourni par l'utilisateur
private let defaultFluxConfigurationJSON = """
{
  "version" : "1.0",
  "folders" : [
    {
      "sortIndex" : 1,
      "createdAt" : "2025-09-05T16:14:16Z",
      "name" : "Apple",
      "id" : "6DF4DBEA-0E4D-4EF4-98C2-E664C98AAEA1"
    },
    {
      "sortIndex" : 0,
      "createdAt" : "2025-09-01T22:13:17Z",
      "name" : "Science",
      "id" : "C0B03D61-262C-4499-9CFE-48C543342FF9"
    }
  ],
  "exportedAt" : "2025-09-15T18:03:46Z",
  "settings" : {
    "theme" : "system",
    "ttsVoice" : null,
    "ttsRate" : 1,
    "preferredLangs" : ["fr"],
    "aiProviderConfig" : "eyJhaUVuYWJsZWQiOmZhbHNlLCJvcGVuYWlBcGlLZXkiOiLigKLigKLigKLigKLigKLigKLigKLigKIiLCJ0dHNWb2ljZSI6ImFsbG95In0=",
    "imageScrapingEnabled" : true,
    "windowBlurEnabled" : false
  },
  "feeds" : [
    {
      "id" : "2DC008B7-6863-489A-95CC-A195450150E3",
      "siteURL" : "https://www.polygon.com",
      "feedURL" : "https://www.polygon.com/rss/index.xml",
      "faviconURL" : "https://static0.polygonimages.com/assets/images/favicon-240x240.009c4ca7.png",
      "sortIndex" : 4,
      "addedAt" : "2025-09-02T14:00:50Z",
      "title" : "Polygon.com",
      "tags" : [ ],
      "isYouTube" : false,
      "folderId" : null
    },
    {
      "id" : "D18ECB68-ED3E-4A2B-B197-A92AEDD7FF0F",
      "siteURL" : "https://www.youtube.com/channel/UC3WC-t0RGn9m4PqAnecO5MA",
      "feedURL" : "https://www.youtube.com/feeds/videos.xml?channel_id=UC3WC-t0RGn9m4PqAnecO5MA",
      "faviconURL" : null,
      "sortIndex" : 21,
      "addedAt" : "2025-09-05T16:18:19Z",
      "title" : "Design Lovers",
      "tags" : [ ],
      "isYouTube" : true,
      "folderId" : null
    },
    {
      "id" : "E045F0E7-EE5E-4180-9026-4DBED19E8F19",
      "siteURL" : "https://openai.com/news",
      "feedURL" : "https://openai.com/blog/rss.xml",
      "faviconURL" : "https://openai.com/apple-icon.png?d110ffad1a87c75b",
      "sortIndex" : 9,
      "addedAt" : "2025-09-02T15:55:27Z",
      "title" : "OpenAI News",
      "tags" : [ ],
      "isYouTube" : false,
      "folderId" : null
    },
    {
      "id" : "6EC84F7D-D38D-4C59-AB76-7FC75E8C2926",
      "siteURL" : "https://www.sciencesetavenir.fr",
      "feedURL" : "https://www.sciencesetavenir.fr/rss.xml",
      "faviconURL" : "https://www.sciencesetavenir.fr/icons/apple-touch-icon.png",
      "sortIndex" : 3,
      "addedAt" : "2025-09-02T13:37:45Z",
      "title" : "Sciences et Avenir",
      "tags" : [ ],
      "isYouTube" : false,
      "folderId" : null
    }
  ]
}
"""

private struct FluxExportFolder: Codable {
    let id: UUID
    let name: String
    let sortIndex: Int?
    let createdAt: Date
}

// Décodage simplifié via FluxConfiguration existant dans Models.swift
struct DefaultsInitializer {
    static func applyIfNeeded(context: ModelContext) {
        // On ne crée les defaults que s’il n’y a pas encore de données (aucun feed/folder/settings)
        guard (try? context.fetch(FetchDescriptor<Feed>()).first) == nil,
              (try? context.fetch(FetchDescriptor<Folder>()).first) == nil,
              (try? context.fetch(FetchDescriptor<Settings>()).first) == nil else {
            return
        }

        guard let jsonData = defaultFluxConfigurationJSON.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let config = try decoder.decode(FluxConfiguration.self, from: jsonData)
            // Insérer folders
            for f in config.folders {
                let folder = Folder(id: f.id, name: f.name, sortIndex: f.sortIndex, createdAt: f.createdAt)
                context.insert(folder)
            }
            // Insérer feeds
            for feedData in config.feeds {
                let siteURL = feedData.siteURL != nil ? URL(string: feedData.siteURL!) : nil
                let faviconURL = feedData.faviconURL != nil ? URL(string: feedData.faviconURL!) : nil
                if let feedURL = URL(string: feedData.feedURL) {
                    let feed = Feed(id: feedData.id,
                                    title: feedData.title,
                                    siteURL: siteURL,
                                    feedURL: feedURL,
                                    faviconURL: faviconURL,
                                    tags: feedData.tags,
                                    addedAt: feedData.addedAt,
                                    sortIndex: feedData.sortIndex,
                                    folderId: feedData.folderId)
                    context.insert(feed)
                }
            }
            // Settings
            if let settingsData = config.settings {
                let s = Settings(theme: settingsData.theme,
                                 ttsVoice: settingsData.ttsVoice,
                                 ttsRate: settingsData.ttsRate,
                                 preferredLangs: settingsData.preferredLangs,
                                 aiProviderConfig: settingsData.aiProviderConfig,
                                 imageScrapingEnabled: settingsData.imageScrapingEnabled,
                                 windowBlurEnabled: settingsData.windowBlurEnabled,
                                 windowBlurTintOpacity: settingsData.windowBlurTintOpacity,
                                 hideTitleOnThumbnails: settingsData.hideTitleOnThumbnails,
                                 filterAdsEnabled: settingsData.filterAdsEnabled,
                                 notificationsEnabled: settingsData.notificationsEnabled,
                                 signalNotificationsEnabled: settingsData.signalNotificationsEnabled ?? true,
                                 hapticsEnabled: settingsData.hapticsEnabled,
                                 alwaysOpenInBrowser: settingsData.alwaysOpenInBrowser,
                                 badgeReadLaterEnabled: settingsData.badgeReadLaterEnabled,
                                 signalFavoriteEventIds: settingsData.signalFavoriteEventIds ?? [])
                context.insert(s)
            }
            try context.save()
        } catch {
            print("DefaultsInitializer: could not apply defaults: \(error)")
        }
    }
}
