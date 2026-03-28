// PolymarketService.swift
// Service pour récupérer les événements prédictifs Polymarket (API publique Gamma)

import Foundation
import Observation
import OSLog
#if canImport(UserNotifications)
import UserNotifications
#endif

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

    /// Plus forte variation absolue sur 24h parmi les marchés de l'événement
    var strongestDailyChange: Int? {
        markets
            .compactMap(\.dailyChange)
            .max { abs($0) < abs($1) }
    }

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
    case breakingNews = "breaking-news"
    case politics = "politics"
    case sports = "sports"
    case crypto = "crypto"
    case popCulture = "pop-culture"
    case finance = "finance"
    case technology = "technology"

    var id: String { rawValue }

    var displayName: String {
        let language = LocalizationManager.shared.currentLanguage
        switch self {
        case .all:
            switch language {
            case .french: return "Tendances"
            case .spanish: return "Tendencias"
            case .german: return "Trends"
            case .italian: return "Tendenze"
            case .portuguese: return "Tendências"
            case .japanese: return "トレンド"
            case .chinese: return "趋势"
            case .korean: return "트렌드"
            case .russian: return "Тренды"
            case .english: return "Trending"
            }
        case .breakingNews:
            switch language {
            case .french: return "Breaking"
            case .spanish: return "Última hora"
            case .german: return "Eilmeldung"
            case .italian: return "Ultim'ora"
            case .portuguese: return "Urgente"
            case .japanese: return "速報"
            case .chinese: return "快讯"
            case .korean: return "속보"
            case .russian: return "Срочно"
            case .english: return "Breaking"
            }
        case .politics:
            switch language {
            case .french: return "Politique"
            case .spanish: return "Política"
            case .german: return "Politik"
            case .italian: return "Politica"
            case .portuguese: return "Política"
            case .japanese: return "政治"
            case .chinese: return "政治"
            case .korean: return "정치"
            case .russian: return "Политика"
            case .english: return "Politics"
            }
        case .sports:
            switch language {
            case .french: return "Sports"
            case .spanish: return "Deportes"
            case .german: return "Sport"
            case .italian: return "Sport"
            case .portuguese: return "Esportes"
            case .japanese: return "スポーツ"
            case .chinese: return "体育"
            case .korean: return "스포츠"
            case .russian: return "Спорт"
            case .english: return "Sports"
            }
        case .crypto:
            switch language {
            case .french: return "Crypto"
            case .spanish: return "Cripto"
            case .german: return "Krypto"
            case .italian: return "Cripto"
            case .portuguese: return "Cripto"
            case .japanese: return "暗号資産"
            case .chinese: return "加密"
            case .korean: return "크립토"
            case .russian: return "Крипто"
            case .english: return "Crypto"
            }
        case .popCulture:
            switch language {
            case .french: return "Culture"
            case .spanish: return "Cultura"
            case .german: return "Kultur"
            case .italian: return "Cultura"
            case .portuguese: return "Cultura"
            case .japanese: return "カルチャー"
            case .chinese: return "文化"
            case .korean: return "컬처"
            case .russian: return "Культура"
            case .english: return "Culture"
            }
        case .finance:
            switch language {
            case .french: return "Finance"
            case .spanish: return "Finanzas"
            case .german: return "Finanzen"
            case .italian: return "Finanza"
            case .portuguese: return "Finanças"
            case .japanese: return "金融"
            case .chinese: return "金融"
            case .korean: return "금융"
            case .russian: return "Финансы"
            case .english: return "Finance"
            }
        case .technology:
            switch language {
            case .french: return "Tech"
            case .spanish: return "Tecnología"
            case .german: return "Tech"
            case .italian: return "Tech"
            case .portuguese: return "Tecnologia"
            case .japanese: return "テック"
            case .chinese: return "科技"
            case .korean: return "테크"
            case .russian: return "Тех"
            case .english: return "Tech"
            }
        }
    }

    var icon: String {
        switch self {
        case .all: return "flame"
        case .breakingNews: return "bolt.badge.clock"
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
        case .breakingNews: return []
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
        let normalizedTokens = Self.normalizedTokens(from: "\(event.title) \(event.slug)")
        return keywords.contains { keyword in
            Self.matchesKeyword(keyword, in: normalizedTokens)
        }
    }

    private static func normalizedTokens(from text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func matchesKeyword(_ keyword: String, in tokens: [String]) -> Bool {
        let keywordTokens = normalizedTokens(from: keyword)
        guard !keywordTokens.isEmpty, keywordTokens.count <= tokens.count else { return false }

        if keywordTokens.count == 1 {
            return tokens.contains(keywordTokens[0])
        }

        for start in 0...(tokens.count - keywordTokens.count) {
            let slice = Array(tokens[start..<(start + keywordTokens.count)])
            if slice == keywordTokens {
                return true
            }
        }
        return false
    }
}

// MARK: - Service

@Observable
@MainActor
final class PolymarketService {
    private let logger = Logger(subsystem: "Flux", category: "PolymarketService")
    private static let baseURL = "https://gamma-api.polymarket.com"
    private static let refreshInterval: TimeInterval = 5 * 60

    var events: [PolymarketEvent] = []
    var isLoading: Bool = false
    var lastError: String?
    var lastFetchedAt: Date?
    var favoriteEventIds: Set<String> = []

    private var allEvents: [PolymarketEvent] = []
    private var fetchTask: Task<Void, Never>?
    private var monitoringTimer: Timer?
    private var knownEventIds: Set<String> = []
    private var hasPerformedInitialFetch: Bool = false

    private static let favoritesKey = "polymarket.favoriteEventIds"

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) {
            favoriteEventIds = Set(saved)
        }
    }

    func startMonitoring() {
        if monitoringTimer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.fetchEvents()
                }
            }
            timer.tolerance = 30
            monitoringTimer = timer
            logger.info("Started Polymarket monitoring")
        }

        refreshIfNeeded()
    }

    func refreshIfNeeded(maxAge: TimeInterval = 90) {
        guard !isLoading else { return }
        if let lastFetchedAt, Date().timeIntervalSince(lastFetchedAt) < maxAge, !events.isEmpty {
            return
        }
        fetchEvents()
    }

    func replaceFavoriteEventIds(with ids: [String]) {
        favoriteEventIds = Set(ids)
        UserDefaults.standard.set(Array(favoriteEventIds).sorted(), forKey: Self.favoritesKey)
    }

    /// Les événements favoris actuellement actifs (triés par volume)
    var favoriteEvents: [PolymarketEvent] {
        allEvents
            .filter { favoriteEventIds.contains($0.id) }
            .sorted { $0.volume > $1.volume }
    }

    func isFavorite(_ event: PolymarketEvent) -> Bool {
        favoriteEventIds.contains(event.id)
    }

    func toggleFavorite(_ event: PolymarketEvent) {
        if favoriteEventIds.contains(event.id) {
            favoriteEventIds.remove(event.id)
        } else {
            favoriteEventIds.insert(event.id)
        }
        UserDefaults.standard.set(Array(favoriteEventIds).sorted(), forKey: Self.favoritesKey)
    }

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

                // Detect new signals (skip first fetch to avoid spamming)
                let newIds = Set(parsed.map(\.id))
                if hasPerformedInitialFetch {
                    let freshIds = newIds.subtracting(knownEventIds)
                    if !freshIds.isEmpty {
                        let freshEvents = parsed.filter { freshIds.contains($0.id) }
                        notifyNewSignals(freshEvents)
                    }
                }
                knownEventIds = newIds
                hasPerformedInitialFetch = true

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

    // MARK: - Notifications

    private var signalNotificationsEnabled: Bool {
        if UserDefaults.standard.object(forKey: "signalNotificationsEnabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "signalNotificationsEnabled")
    }

    private func notifyNewSignals(_ newEvents: [PolymarketEvent]) {
        guard signalNotificationsEnabled, !newEvents.isEmpty else { return }
        #if canImport(UserNotifications)
        let lm = LocalizationManager.shared
        let content = UNMutableNotificationContent()
        if newEvents.count == 1, let first = newEvents.first {
            content.title = lm.localizedString(.signalsNewNotificationTitle)
            content.body = first.title
            content.userInfo["fluxDeepLink"] = FluxDeepLink.signalURL(eventId: first.id)?.absoluteString
        } else {
            content.title = lm.localizedString(.signalsNewNotificationTitle)
            let bodyTemplate = lm.localizedString(.signalsNewNotificationBody)
            content.body = String(format: bodyTemplate, newEvents.count)
            content.userInfo["fluxDeepLink"] = FluxDeepLink.signalURL(eventId: nil)?.absoluteString
        }
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(
            identifier: "flux.signals.new.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        logger.info("Sent notification for \(newEvents.count) new signal(s)")
        #endif
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
