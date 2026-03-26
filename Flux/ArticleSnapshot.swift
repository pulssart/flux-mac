import Foundation

// Modèle minimal lu/écrit pour les widgets
struct ArticleSnapshot: Codable, Identifiable {
    let id: UUID
    let title: String
    let url: URL
    let imageURL: URL?
    let feedTitle: String
    let publishedAt: Date?
    let isSaved: Bool
}

