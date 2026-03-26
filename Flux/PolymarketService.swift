// PolymarketService.swift
// Service pour récupérer les événements prédictifs Polymarket (API publique Gamma)

import Foundation
import Observation
import OSLog

// MARK: - Modèles de données Polymarket

/// Un événement Polymarket regroupe plusieurs marchés binaires autour d'un même sujet
struct PolymarketEvent: Identifiable, Hashable {
    let id: String
    let slug: String
    let title: String
    let description: String
    let imageURL: URL?
    let tags: [String]
    let volume: Double
    let liquidity: Double
    let commentCount: Int
    let startDate: Date?
    let endDate: Date?
    let markets: [PolymarketMarket]
    let competitive: Double // 0..1

    /// URL vers la page détail Polymarket
    var polymarketURL: URL {
        URL(string: "https://polymarket.com/event/\(slug)")!
    }

    /// Le marché principal (plus gros volume) ou le premier
    var leadMarket: PolymarketMarket? { markets.first }

    /// Top outcomes triés par probabilité décroissante (multi-outcome events)
    var topOutcomes: [(name: String, percentage: Int)] {
        markets
            .filter { !$0.question.isEmpty }
            .map { (name: $0.groupItemTitle.isEmpty ? $0.question : $0.groupItemTitle, percentage: $0.yesPercentage) }
            .sorted { $0.percentage > $1.percentage }
    }

    /// Est-ce un événement binaire simple (un seul marché Yes/No) ?
    var isBinary: Bool { markets.count <= 1 }

    /// Premier tag lisible comme catégorie
    var primaryTag: String? { tags.first }

    /// Volume formaté
    var formattedVolume: String {
        if volume >= 1_000_000 {
            return String(format: "$%.1fM", volume / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "$%.0fK", volume / 1_000)
        } else {
            return String(format: "$%.0f", volume)
        }
    }
}

/// Un commentaire Polymarket sur un événement
struct PolymarketComment: Identifiable {
    let id: String
    let content: String
    let author: String
    let createdAt: Date?
}

/// Un marché individuel (toujours binaire Yes/No)
struct PolymarketMarket: Identifiable, Hashable {
    let id: String
    let question: String
    let groupItemTitle: String
    let slug: String
    let outcomePrices: [Double] // [yesPrice, noPrice]
    let volume: Double
    let oneDayPriceChange: Double?
    let imageURL: URL?
    let endDate: Date?
    let description: String

    var yesPercentage: Int {
        guard let first = outcomePrices.first else { return 0 }
        return Int(round(first * 100))
    }

    var noPercentage: Int {
        100 - yesPercentage
    }

    /// Variation sur 24h en points de pourcentage
    var dailyChange: Int? {
        guard let change = oneDayPriceChange else { return nil }
        let points = Int(round(change * 100))
        return points == 0 ? nil : points
    }
}

/// Catégories de signaux affichées dans l'app
enum SignalCategory: String, CaseIterable, Identifiable {
    case all = "all"
    case politics = "politics"
    case sports = "sports"
    case crypto = "crypto"
    case popCulture = "pop-culture"
    case finance = "finance"
    case technology = "technology"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "Tendances"
        case .politics: return "Politique"
        case .sports: return "Sports"
        case .crypto: return "Crypto"
        case .popCulture: return "Culture"
        case .finance: return "Finance"
        case .technology: return "Tech"
        }
    }

    var icon: String {
        switch self {
        case .all: return "flame"
        case .politics: return "building.columns"
        case .sports: return "sportscourt"
        case .crypto: return "bitcoinsign.circle"
        case .popCulture: return "star"
        case .finance: return "chart.line.uptrend.xyaxis"
        case .technology: return "cpu"
        }
    }

    /// Mots-clés pour le filtrage côté client — matchés uniquement sur le titre et le slug
    var keywords: [String] {
        switch self {
        case .all: return []
        case .politics: return ["president", "presidential", "election", "democrat", "republican", "congress", "senate", "governor", "nominee", "trump", "biden", "political", "parliament", "minister", "regime", "invasion", "invade", "ceasefire", "military", "offensive", "nato", "sanction", "greenland", "iran", "ukraine", "russia", "venezuela", "taiwan", "israel", "lebanon", "hungary", "vietnam", "brazil", "netanyahu", "maduro", "starmer", "xi jinping", "fed chair", "measles"]
        case .sports: return ["nba", "nfl", "mlb", "nhl", "ncaa", "fifa", "ufc", "tennis", "soccer", "football", "basketball", "baseball", "hockey", "champion", "super bowl", "world cup", "grand slam", "olympics", "formula", "f1 driver", "playoff", "mvp", "boxing", "mma", "cricket", "golf", "pga", "masters", "augusta", "stanley cup", "premier league", "la liga", "serie a", "bundesliga", "ligue 1", "uefa", "australian open", "grand prix", "mls cup", "atlético", "atletico"]
        case .crypto: return ["bitcoin", "ethereum", "crypto", "solana", "blockchain", "defi", "memecoin", "dogecoin", "xrp", "stablecoin", "binance", "coinbase", "microstrategy", "backpack fdv", "megaeth", "satoshi", "metamask", "token", "edgex"]
        case .popCulture: return ["oscar", "grammy", "emmy", "movie", "film", "album", "music", "celebrity", "tiktok", "youtube", "streaming", "netflix", "disney", "kardashian", "taylor swift", "beyonce", "drake", "kanye", "box office", "billboard", "tv show", "influencer", "rapper", "singer", "actor", "actress", "entertainment", "hollywood", "anime", "video game", "gaming", "esport", "twitch", "spotify", "eurovision", "stranger things", "gta vi", "gta-vi", "grand theft auto", "mrbeast", "elon musk", "# tweet", "jesus christ", "pope", "nobel", "grossing", "pregnant", "views of next", "mindshare", "alien"]
        case .finance: return ["crude oil", "s&p", "nasdaq", "dow jones", "fed decision", "fed rate", "interest rate", "inflation rate", "inflation us", "annual inflation", "march inflation", "recession", "earnings", "commodity", "treasury", "tariff", "trade war", "wall street", "hedge fund", "forex", "housing", "real estate", "debt ceiling", "rate cut", "rate hike", "largest company", "acquired", "acquisition", "ipo"]
        case .technology: return ["artificial intelligence", "openai", "chatgpt", "claude 5", "google ai", "apple intelligence", "ai model", "ai bubble", "tesla", "spacex", "semiconductor", "robot", "quantum", "silicon valley", "self-driving", "autonomous", "neural", "llm", "machine learning", "deep learning", "nvidia", "anthropic"]
        }
    }

    /// Teste si un événement correspond à cette catégorie (match sur titre + slug uniquement)
    func matches(_ event: PolymarketEvent) -> Bool {
        guard !keywords.isEmpty else { return true }
        let searchText = " \(event.title) \(event.slug) ".lowercased()
        return keywords.contains { keyword in
            searchText.contains(keyword)
        }
    }
}

// MARK: - Service

@Observable
@MainActor
final class PolymarketService {
    private let logger = Logger(subsystem: "Flux", category: "PolymarketService")
    private static let baseURL = "https://gamma-api.polymarket.com"

    var events: [PolymarketEvent] = []
    var isLoading: Bool = false
    var lastError: String?
    var lastFetchedAt: Date?

    private var allEvents: [PolymarketEvent] = []
    private var fetchTask: Task<Void, Never>?

    /// Filtre les events par catégorie côté client
    func filterEvents(category: SignalCategory) {
        if category == .all {
            events = allEvents
        } else {
            events = allEvents.filter { category.matches($0) }
        }
    }

    /// Charge les événements actifs depuis l'API Gamma
    func fetchEvents() {
        fetchTask?.cancel()
        fetchTask = Task {
            isLoading = true
            lastError = nil
            defer { isLoading = false }

            do {
                var comps = URLComponents(string: "\(Self.baseURL)/events")!
                comps.queryItems = [
                    URLQueryItem(name: "limit", value: "500"),
                    URLQueryItem(name: "active", value: "true"),
                    URLQueryItem(name: "closed", value: "false"),
                    URLQueryItem(name: "order", value: "volume"),
                    URLQueryItem(name: "ascending", value: "false"),
                ]
                guard let url = comps.url else { lastError = "URL invalide"; return }

                let (data, response) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled else { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    lastError = "Erreur serveur"; return
                }

                let decoded = try JSONDecoder().decode([GammaEventResponse].self, from: data)
                let parsed = decoded.compactMap { Self.parseEvent($0) }
                guard !Task.isCancelled else { return }

                self.allEvents = parsed
                self.events = parsed
                self.lastFetchedAt = Date()
                logger.info("Fetched \(parsed.count) Polymarket events")
            } catch is CancellationError {
                // ignore
            } catch {
                guard !Task.isCancelled else { return }
                lastError = error.localizedDescription
                logger.error("Polymarket fetch error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Parsing

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func parseEvent(_ raw: GammaEventResponse) -> PolymarketEvent? {
        let markets = (raw.markets ?? []).compactMap { parseMarket($0) }
        guard !markets.isEmpty else { return nil }

        // Derive tags from ticker/slug (e.g. "democratic-presidential-nominee-2028" -> ["Democratic", "Presidential", "Nominee"])
        let slugWords = (raw.ticker ?? raw.slug ?? "")
            .split(separator: "-")
            .filter { $0.count > 2 && Int($0) == nil }
            .prefix(3)
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }

        return PolymarketEvent(
            id: raw.id ?? UUID().uuidString,
            slug: raw.slug ?? raw.ticker ?? "",
            title: raw.title ?? "",
            description: raw.description ?? "",
            imageURL: raw.image.flatMap { URL(string: $0) },
            tags: slugWords,
            volume: raw.volume ?? 0,
            liquidity: raw.liquidity ?? 0,
            commentCount: raw.commentCount ?? 0,
            startDate: raw.startDate.flatMap { isoFormatter.date(from: $0) },
            endDate: raw.endDate.flatMap { isoFormatter.date(from: $0) },
            markets: markets.sorted { $0.volume > $1.volume },
            competitive: raw.competitive ?? 0
        )
    }

    private static func parseMarket(_ raw: GammaMarketResponse) -> PolymarketMarket? {
        let prices = parseJSONArray(raw.outcomePrices ?? "[]").compactMap { Double($0) }
        guard !prices.isEmpty else { return nil }

        return PolymarketMarket(
            id: raw.id ?? UUID().uuidString,
            question: raw.question ?? "",
            groupItemTitle: raw.groupItemTitle ?? "",
            slug: raw.slug ?? "",
            outcomePrices: prices,
            volume: Double(raw.volume ?? "0") ?? 0,
            oneDayPriceChange: raw.oneDayPriceChange,
            imageURL: raw.image.flatMap { URL(string: $0) },
            endDate: raw.endDate.flatMap { isoFormatter.date(from: $0) },
            description: raw.description ?? ""
        )
    }

    /// Charge les 10 derniers commentaires d'un événement
    func fetchComments(for eventId: String) async -> [PolymarketComment] {
        var comps = URLComponents(string: "\(Self.baseURL)/comments")!
        comps.queryItems = [
            URLQueryItem(name: "parent_entity_id", value: eventId),
            URLQueryItem(name: "parent_entity_type", value: "Event"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "order", value: "createdAt"),
            URLQueryItem(name: "ascending", value: "false"),
        ]
        guard let url = comps.url else { return [] }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode([GammaCommentResponse].self, from: data)
            return decoded.compactMap { raw -> PolymarketComment? in
                guard let id = raw.id, let body = raw.body, !body.isEmpty else { return nil }
                let author = raw.profile?.displayName ?? "Anonyme"
                let date = (raw.createdAt ?? raw.updatedAt).flatMap { Self.isoFormatter.date(from: $0) }
                return PolymarketComment(id: id, content: body, author: author, createdAt: date)
            }
        } catch {
            logger.warning("Comments fetch error for \(eventId): \(error.localizedDescription)")
            return []
        }
    }

    private static func parseJSONArray(_ string: String) -> [String] {
        guard let data = string.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return []
        }
        return array.map { "\($0)" }
    }
}

// MARK: - API Response Models

private struct GammaEventResponse: Decodable {
    let id: String?
    let ticker: String?
    let slug: String?
    let title: String?
    let description: String?
    let image: String?
    let volume: Double?
    let liquidity: Double?
    let commentCount: Int?
    let startDate: String?
    let endDate: String?
    let competitive: Double?
    let markets: [GammaMarketResponse]?
}

private struct GammaMarketResponse: Decodable {
    let id: String?
    let question: String?
    let groupItemTitle: String?
    let slug: String?
    let outcomes: String?
    let outcomePrices: String?
    let volume: String?
    let oneDayPriceChange: Double?
    let image: String?
    let endDate: String?
    let description: String?
    let active: Bool?
}

private struct GammaCommentResponse: Decodable {
    let id: String?
    let body: String?
    let createdAt: String?
    let updatedAt: String?
    let profile: GammaCommentProfile?
}

private struct GammaCommentProfile: Decodable {
    let name: String?
    let pseudonym: String?
    let displayUsernamePublic: Bool?

    var displayName: String {
        if displayUsernamePublic == true, let name = name, !name.isEmpty { return name }
        return pseudonym ?? "Anonyme"
    }
}
