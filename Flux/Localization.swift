// Localization.swift
// Gestion de la localisation de l'interface utilisateur
import Foundation
import SwiftUI

// MARK: - Langues supportées
enum SupportedLanguage: String, CaseIterable, Identifiable {
    case french = "fr"
    case english = "en"
    case spanish = "es"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case japanese = "ja"
    case chinese = "zh"
    case korean = "ko"
    case russian = "ru"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .french: return "Français"
        case .english: return "English"
        case .spanish: return "Español"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .japanese: return "日本語"
        case .chinese: return "中文"
        case .korean: return "한국어"
        case .russian: return "Русский"
        }
    }
    
    var flag: String {
        switch self {
        case .french: return "🇫🇷"
        case .english: return "🇺🇸"
        case .spanish: return "🇪🇸"
        case .german: return "🇩🇪"
        case .italian: return "🇮🇹"
        case .portuguese: return "🇵🇹"
        case .japanese: return "🇯🇵"
        case .chinese: return "🇨🇳"
        case .korean: return "🇰🇷"
        case .russian: return "🇷🇺"
        }
    }
    
    var locale: Locale {
        return Locale(identifier: rawValue)
    }
}

// MARK: - Gestionnaire de localisation
@Observable
class LocalizationManager {
    static let shared = LocalizationManager()
    
    private let userDefaults = UserDefaults.standard
    private let languageKey = "selected_language"
    
    var currentLanguage: SupportedLanguage {
        get {
            if let savedLanguage = userDefaults.string(forKey: languageKey),
               let language = SupportedLanguage(rawValue: savedLanguage) {
                return language
            }
            // Fallback sur la langue système
            let systemLanguage = Locale.current.language.languageCode?.identifier ?? "en"
            return SupportedLanguage(rawValue: systemLanguage) ?? .english
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: languageKey)
            // Notifier le changement de langue
            NotificationCenter.default.post(name: .languageChanged, object: newValue)
        }
    }
    
    var currentLocale: Locale {
        return currentLanguage.locale
    }
    
    // Phrases de chargement localisées
    func loadingPhrases() -> [String] {
        switch currentLanguage {
        case .french:
            return [
                "Je compresse l'actualité…",
                "Je briefe les derniers titres…",
                "Je distille les infos croustillantes…",
                "Je fais court, promis…",
                "J'ouvre les onglets de la connaissance…",
                "Je range les flux, je reviens…",
                "Je synthétise ça comme un chef…",
                "Je débobine le fil des événements…",
                "Je chasse les doublons…",
                "Je lis entre les balises…",
                "Je souffle sur le cache…",
                "Je dompte les flux capricieux…",
                "Je remixe les infos en 8 bits…",
                "Je mets des paillettes dans le résumé…",
                "Je traduis les acronymes mystérieux…",
                "Je dépile l'internet, calmement…",
                "Je découpe les niouz en fines rondelles…",
                "Je trie le bruit, je garde le signal…",
                "Je sors la loupe journalistique…",
                "Je vérifie deux fois, puis je résume…"
            ]
        case .english:
            return [
                "Compressing the news...",
                "Briefing the latest headlines...",
                "Distilling the juicy info...",
                "Keeping it short, I promise...",
                "Opening the knowledge tabs...",
                "Organizing feeds, be right back...",
                "Synthesizing like a pro...",
                "Unwinding the event thread...",
                "Hunting for duplicates...",
                "Reading between the tags...",
                "Blowing on the cache...",
                "Taming the capricious feeds...",
                "Remixing info in 8-bit...",
                "Adding sparkles to the summary...",
                "Translating mysterious acronyms...",
                "Stacking the internet, calmly...",
                "Slicing news into fine rounds...",
                "Filtering noise, keeping signal...",
                "Bringing out the journalistic magnifier...",
                "Double-checking, then summarizing..."
            ]
        case .spanish:
            return [
                "Comprimiendo las noticias...",
                "Resumiendo los últimos titulares...",
                "Destilando la información jugosa...",
                "Manteniéndolo corto, lo prometo...",
                "Abriendo las pestañas del conocimiento...",
                "Organizando feeds, vuelvo enseguida...",
                "Sintetizando como un profesional...",
                "Desenrollando el hilo de eventos...",
                "Cazando duplicados...",
                "Leyendo entre las etiquetas...",
                "Soplando en la caché...",
                "Domando los feeds caprichosos...",
                "Remezclando información en 8-bit...",
                "Añadiendo brillos al resumen...",
                "Traduciendo acrónimos misteriosos...",
                "Apilando internet, con calma...",
                "Cortando noticias en finas rodajas...",
                "Filtrando ruido, manteniendo señal...",
                "Sacando la lupa periodística...",
                "Verificando dos veces, luego resumiendo..."
            ]
        case .german:
            return [
                "Komprimiere die Nachrichten...",
                "Fasse die neuesten Schlagzeilen zusammen...",
                "Destilliere die saftigen Infos...",
                "Halte es kurz, versprochen...",
                "Öffne die Wissens-Tabs...",
                "Organisiere Feeds, bin gleich zurück...",
                "Synthetisiere wie ein Profi...",
                "Wickle den Ereignisfaden ab...",
                "Jage Duplikate...",
                "Lese zwischen den Tags...",
                "Blase in den Cache...",
                "Zähme die launischen Feeds...",
                "Remixe Infos in 8-Bit...",
                "Füge Glitzer zum Resümee hinzu...",
                "Übersetze mysteriöse Akronyme...",
                "Staple das Internet, ruhig...",
                "Schneide Nachrichten in feine Scheiben...",
                "Filtere Lärm, behalte Signal...",
                "Hole die journalistische Lupe raus...",
                "Prüfe zweimal, dann fasse zusammen..."
            ]
        case .italian:
            return [
                "Comprimo le notizie...",
                "Riassumo gli ultimi titoli...",
                "Distillo le informazioni succose...",
                "Lo tengo breve, promesso...",
                "Apro le schede della conoscenza...",
                "Organizzo i feed, torno subito...",
                "Sintetizzo come un professionista...",
                "Srotolo il filo degli eventi...",
                "Caccio i duplicati...",
                "Leggo tra i tag...",
                "Soffio sulla cache...",
                "Addomestico i feed capricciosi...",
                "Rimisco le info in 8-bit...",
                "Aggiungo brillantini al riassunto...",
                "Traduco acronimi misteriosi...",
                "Impilo internet, con calma...",
                "Affetto le notizie a fette sottili...",
                "Filtro il rumore, tengo il segnale...",
                "Tiro fuori la lente d'ingrandimento giornalistica...",
                "Controllo due volte, poi riassumo..."
            ]
        case .portuguese:
            return [
                "Compactando as notícias...",
                "Resumindo as manchetes...",
                "Destilando o suco das infos...",
                "Prometo ser breve...",
                "Abrindo as abas do conhecimento...",
                "Organizando os feeds, já volto...",
                "Sintetizando como um chef...",
                "Desenrolando o fio dos eventos...",
                "Caçando duplicatas...",
                "Lendo entre as tags...",
                "Soprando a poeira do cache...",
                "Domando feeds temperamentais...",
                "Remixando as infos em 8-bit...",
                "Jogando glitter no resumo...",
                "Traduzindo siglas misteriosas...",
                "Empilhando a internet, com calma...",
                "Fatiando as notícias bem fininho...",
                "Filtrando o ruído, guardando o sinal...",
                "Pegando a lupa jornalística...",
                "Checando duas vezes, depois resumo..."
            ]
        case .japanese:
            return [
                "ニュースをぎゅっと圧縮中…",
                "最新見出しを要約中…",
                "おいしい情報だけ抽出中…",
                "短くまとめます、約束…",
                "知識のタブを開いてます…",
                "フィードを整理中、すぐ戻ります…",
                "プロ級に合成中…",
                "出来事の糸をほどいてます…",
                "重複を狩りに行ってます…",
                "タグの行間を読んでます…",
                "キャッシュをふーっと…",
                "気まぐれフィードを手なずけ中…",
                "情報を8ビットでリミックス中…",
                "要約にキラキラ追加中…",
                "謎の略語を翻訳中…",
                "インターネットを静かに積み上げ中…",
                "ニュースを薄切りにしています…",
                "ノイズをふるい、信号だけ…",
                "記者の虫眼鏡を取り出し中…",
                "二度確認してから要約します…"
            ]
        case .chinese:
            return [
                "正在压缩新闻…",
                "正在汇总最新标题…",
                "正在提炼精华信息…",
                "保证简短…",
                "正在打开知识标签…",
                "正在整理订阅源，马上回来…",
                "正在专业级合成…",
                "正在梳理事件脉络…",
                "正在捕捉重复内容…",
                "正在读懂标签之间…",
                "正在给缓存吹口气…",
                "正在驯服任性的订阅源…",
                "正在用8位风格混音信息…",
                "正在给摘要加点闪光…",
                "正在翻译神秘缩写…",
                "正在安静地堆叠互联网…",
                "正在把新闻切成薄片…",
                "过滤噪音，保留信号…",
                "正在拿出记者放大镜…",
                "再核对一次，然后总结…"
            ]
        case .korean:
            return [
                "뉴스를 꾹 눌러 압축 중…",
                "최신 헤드라인 요약 중…",
                "맛있는 정보만 추출 중…",
                "짧게 정리할게요, 약속…",
                "지식 탭을 열고 있어요…",
                "피드 정리 중, 곧 돌아옵니다…",
                "프로처럼 합성 중…",
                "사건의 실을 풀어내는 중…",
                "중복을 사냥 중…",
                "태그 사이를 읽는 중…",
                "캐시를 후— 불고 있어요…",
                "까다로운 피드를 길들이는 중…",
                "정보를 8비트로 리믹스 중…",
                "요약에 반짝이를 더하는 중…",
                "미스터리한 약어를 번역 중…",
                "인터넷을 차분히 쌓는 중…",
                "뉴스를 얇게 썰고 있어요…",
                "노이즈는 거르고 신호만…",
                "기자 돋보기를 꺼내는 중…",
                "두 번 확인한 뒤 요약합니다…"
            ]
        case .russian:
            return [
                "Сжимаю новости…",
                "Собираю свежие заголовки…",
                "Выжимаю сок из информации…",
                "Коротко и по делу, обещаю…",
                "Открываю вкладки знаний…",
                "Навожу порядок в лентах, скоро вернусь…",
                "Синтезирую как профи…",
                "Распутываю нить событий…",
                "Охочусь на дубликаты…",
                "Читаю между тегами…",
                "Сдуваю пыль с кэша…",
                "Усмиряю капризные ленты…",
                "Ремиксую инфо в 8‑бит…",
                "Добавляю блёстки в резюме…",
                "Перевожу загадочные аббревиатуры…",
                "Спокойно складываю интернет…",
                "Нарезаю новости тонкими ломтиками…",
                "Фильтрую шум, оставляю сигнал…",
                "Достаю журналистскую лупу…",
                "Проверяю дважды, затем резюмирую…"
            ]
        default:
            // Fallback sur l'anglais pour les autres langues
            return [
                "Compressing the news...",
                "Briefing the latest headlines...",
                "Distilling the juicy info...",
                "Keeping it short, I promise...",
                "Opening the knowledge tabs...",
                "Organizing feeds, be right back...",
                "Synthesizing like a pro...",
                "Unwinding the event thread...",
                "Hunting for duplicates...",
                "Reading between the tags...",
                "Blowing on the cache...",
                "Taming the capricious feeds...",
                "Remixing info in 8-bit...",
                "Adding sparkles to the summary...",
                "Translating mysterious acronyms...",
                "Stacking the internet, calmly...",
                "Slicing news into fine rounds...",
                "Filtering noise, keeping signal...",
                "Bringing out the journalistic magnifier...",
                "Double-checking, then summarizing..."
            ]
        }
    }
    
    // Textes de l'interface localisés
    func localizedString(_ key: LocalizationKey) -> String {
        switch currentLanguage {
        case .french:
            return key.french
        case .english:
            return key.english
        case .spanish:
            return key.spanish
        case .german:
            return key.german
        case .italian:
            return key.italian
        case .portuguese:
            return key.portuguese
        case .japanese:
            return key.japanese
        case .chinese:
            return key.chinese
        case .korean:
            return key.korean
        case .russian:
            return key.russian
        }
    }

    func localizedString(_ key: LocalizationKey, _ args: CVarArg...) -> String {
        let format = localizedString(key)
        guard !args.isEmpty else { return format }
        return String(format: format, locale: currentLocale, arguments: args)
    }
}

// MARK: - Clés de localisation
enum LocalizationKey {
    case today
    case yesterday
    case all
    case newsWall
    case markAllAsSeen
    case markAllAsSeenHelp
    case myFavorites
    case folders
    case youtube
    case music
    case myFeeds
    case addFeed
    case addFolder
    case aiSettings
    case cancel
    case save
    case loading
    case reload
    case noArticles
    case noFavorites
    case lastUpdate
    case source
    case addToFavorites
    case removeFromFavorites
    case openInBrowser
    case readerMode
    case back
    case emptyReadLaterHint
    case shareByEmail
    case shareByMessage
    case writeXPost
    case copyURL
    case spacebarPlayPause
    case newsletterTitle
    case newsletterTitleWithDate
    case newsletterGenerated
    case newsletterImageAI
    case newsletterVideosToday
    case newsletterFeed
    case newsletterPreparing
    case newsletterEmptyHint
    case generate
    case generateMyNewsletter
    case scheduleSettings
    case listenNewsletter
    case appleIntelligenceWorking
    case aiCreatingSummary
    // Discovery
    case discoveryTitle
    case discoveryTrending
    case discoveryForYou
    case discoverySeeMore
    // Settings
    case settings
    case windowBlurToggle
    case hideTitleOnThumbnails
    case notificationsToggle
    case notificationsNewsToggle
    case notificationsSignalsToggle
    case hapticsToggle
    case openArticleFirstToggle
    case reduceOverlaysToggle
    case alwaysOpenInBrowserToggle
    case interfaceLanguage
    case language
    case reviewIntroduction
    case settingsSaved
    case saveError
    // Articles
    case allArticles
    case readLater
    // Newsletter Schedule
    case scheduleNewsletter
    case scheduleNewsletterDescription
    case scheduleNewsletterNotification
    case beta
    // Configuration Import/Export
    case configuration
    case configurationImportHint
    case exportConfig
    case importConfig
    case deleteConfig
    case importSummary
    case feedsImported
    case foldersImported
    case feedsSkipped
    case foldersSkipped
    case feeds
    case foldersLabel
    case deleteConfigWarning
    // Add Feed
    case searchingRSSFeed
    case subscriptions
    case addFeedURL
    case add
    // Actions
    case rename
    case delete
    case skip
    // Help texts
    case helpCloseArticle
    case helpOpenInBrowser
    case helpPostOnX
    case helpCloseWindow
    case helpReaderTheme
    case helpOpenVideo
    // Alerts
    case errorX
    case deleteFeed
    // Developer
    case openLogsWindow
    // Onboarding
    case onboardingWelcomeTitle
    case onboardingWelcomeSubtitle
    case onboardingWelcomeDescription
    case onboardingNewsWallTitle
    case onboardingNewsWallSubtitle
    case onboardingNewsWallDescription
    case onboardingAITitle
    case onboardingAISubtitle
    case onboardingAIDescription
    case onboardingPreferencesTitle
    case onboardingPreferencesSubtitle
    case onboardingEnableNotifications
    case onboardingReducePopups
    case onboardingSourcesTitle
    case onboardingSourcesSubtitle
    case onboardingOrganizationTitle
    case onboardingOrganizationSubtitle
    case onboardingOrganizationDescription
    case onboardingStartTitle
    case onboardingStartSubtitle
    case onboardingStartDescription
    case onboardingNext
    case onboardingStart
    case onboardingSafariTitle
    case onboardingSafariSubtitle
    case onboardingSafariDescription
    // Rate
    case rateApp
    case badgeReadLaterToggle
    case filterAdsToggle
    case signals
    // Signals section
    case signalsFeatured
    case signalsFeaturedSubtitle
    case signalsAll
    case signalsAllSubtitle
    case signalsUpdatedAt
    case signalsIntro
    case signalsYes
    case signalsNo
    case signalsNoResult
    case signalsTryOtherCategory
    case signalsLoading
    case signalsLoadError
    case signalsRetry
    case signalsEndDate
    case signalsResolution
    case signalsVolume
    case signalsLiquidity
    case signalsComments
    case signalsCompetitiveness
    case signalsProbability
    case signalsMarkets
    case signalsNoComments
    case signalsNewNotificationTitle
    case signalsNewNotificationBody

    var french: String {
        switch self {
        case .today: return "Aujourd'hui"
        case .yesterday: return "Hier"
        case .all: return "Tous"
        case .newsWall: return "Mur de flux"
        case .markAllAsSeen: return "Tout marquer comme vu"
        case .markAllAsSeenHelp: return "Mettre à zéro les compteurs de tous les flux"
        case .myFavorites: return "À lire plus tard"
        case .folders: return "Dossiers"
        case .youtube: return "Youtube"
        case .music: return "Music"
        case .myFeeds: return "Mes Flux"
        case .addFeed: return "Ajouter un flux"
        case .addFolder: return "Ajouter un dossier"
        case .aiSettings: return "Réglages IA"
        case .cancel: return "Annuler"
        case .save: return "Enregistrer"
        case .loading: return "Chargement des articles…"
        case .reload: return "Recharger"
        case .noArticles: return "Aucun article disponible"
        case .noFavorites: return "Aucun article à lire plus tard"
        case .lastUpdate: return "Dernière mise à jour"
        case .source: return "Source"
        case .addToFavorites: return "Ajouter à la liste de lecture"
        case .removeFromFavorites: return "Retirer de la liste de lecture"
        case .openInBrowser: return "Ouvrir dans le navigateur"
        case .readerMode: return "Mode lecteur"
        case .back: return "Retour"
        case .emptyReadLaterHint: return "Pour commencer, cliquez sur l’icône Lire plus tard"
        case .shareByEmail: return "Envoyer par mail"
        case .shareByMessage: return "Par message"
        case .writeXPost: return "Écrire un post X"
        case .copyURL: return "Copier l’URL"
        case .spacebarPlayPause: return "Utilise la barre d’espace pour play / pause la vidéo"
        case .newsletterTitle: return "Ma newsletter"
        case .newsletterTitleWithDate: return "Ma newsletter — %@"
        case .newsletterGenerated: return "Générée:"
        case .newsletterImageAI: return "Image IA"
        case .newsletterVideosToday: return "Vidéos aujourd'hui"
        case .newsletterFeed: return "Feed"
        case .newsletterPreparing: return "Je prépare votre newsletter avec l'intelligence artificielle locale…"
        case .newsletterEmptyHint: return "Créez une synthèse éditoriale de toute l’actualité du mur."
        case .generate: return "Générer"
        case .generateMyNewsletter: return "Générer ma newsletter"
        case .scheduleSettings: return "Paramètres de planification"
        case .listenNewsletter: return "Écouter la newsletter"
        case .appleIntelligenceWorking: return "L'intelligence artificielle locale travaille"
        case .aiCreatingSummary: return "L'intelligence artificielle locale crée votre résumé…"
        // Settings
        case .discoveryTitle: return "Découverte"
        case .discoveryTrending: return "Tendances"
        case .discoveryForYou: return "Pour vous"
        case .discoverySeeMore: return "Voir plus"
        case .settings: return "Réglages"
        case .windowBlurToggle: return "Fond de fenêtre en liquid glass"
        case .hideTitleOnThumbnails: return "Masquer titre et source sur les miniatures (visible au survol)"
        case .notificationsToggle: return "Activer les notifications"
        case .notificationsNewsToggle: return "Activer les notifications d'actualités"
        case .notificationsSignalsToggle: return "Activer les notifications de signaux"
        case .hapticsToggle: return "Activer les retours haptiques"
        case .openArticleFirstToggle: return "Ouvrir l'article avant le résumé IA"
        case .reduceOverlaysToggle: return "Réduire les popups dans le lecteur"
        case .alwaysOpenInBrowserToggle: return "Toujours ouvrir les articles dans votre navigateur"
        case .interfaceLanguage: return "Langue de l'interface"
        case .language: return "Langue"
        case .reviewIntroduction: return "Revoir l'introduction"
        case .settingsSaved: return "Paramètres sauvegardés ✅"
        case .saveError: return "Erreur lors de la sauvegarde"
        // Articles
        case .allArticles: return "Tous les articles"
        case .readLater: return "À lire plus tard"
        // Newsletter Schedule
        case .scheduleNewsletter: return "Planifier la newsletter"
        case .scheduleNewsletterDescription: return "Choisissez jusqu'à 3 horaires quotidiens pour générer automatiquement la newsletter."
        case .scheduleNewsletterNotification: return "Une notification vous préviendra quand la newsletter est prête."
        case .beta: return "BETA"
        // Configuration Import/Export
        case .configuration: return "Configuration"
        case .configurationImportHint: return "Utilisez le bouton 'Importer' pour sélectionner un fichier de configuration"
        case .exportConfig: return "Exporter"
        case .importConfig: return "Importer"
        case .deleteConfig: return "Supprimer"
        case .importSummary: return "Résumé de l'import"
        case .feedsImported: return "flux importés"
        case .foldersImported: return "dossiers importés"
        case .feedsSkipped: return "flux ignorés (déjà existants)"
        case .foldersSkipped: return "dossiers ignorés (déjà existants)"
        case .feeds: return "flux"
        case .foldersLabel: return "dossiers"
        case .deleteConfigWarning: return "Cette action va supprimer définitivement tous les flux, dossiers et paramètres. Cette action est irréversible.\n\nAssurez-vous d'avoir exporté votre configuration avant de continuer."
        // Add Feed
        case .searchingRSSFeed: return "Recherche du flux RSS…"
        case .subscriptions: return "Abonnements"
        case .addFeedURL: return "Ajouter un flux (URL)"
        case .add: return "Ajouter"
        // Actions
        case .rename: return "Renommer"
        case .delete: return "Supprimer"
        case .skip: return "Passer"
        // Help texts
        case .helpCloseArticle: return "Fermer l'article"
        case .helpOpenInBrowser: return "Ouvrir dans le navigateur"
        case .helpPostOnX: return "Publier sur X"
        case .helpCloseWindow: return "Fermer la fenêtre"
        case .helpReaderTheme: return "Thème lecteur"
        case .helpOpenVideo: return "Ouvrir la vidéo"
        // Alerts
        case .errorX: return "Erreur X"
        case .deleteFeed: return "Supprimer le flux"
        // Developer
        case .openLogsWindow: return "Ouvrir la fenêtre des logs"
        // Onboarding
        case .onboardingWelcomeTitle: return "Bienvenue dans Flux"
        case .onboardingWelcomeSubtitle: return "Votre lecteur RSS intelligent"
        case .onboardingWelcomeDescription: return "Suivez vos sites préférés et restez informé grâce à l'intelligence artificielle locale."
        case .onboardingNewsWallTitle: return "Mur d'actualités"
        case .onboardingNewsWallSubtitle: return "Toute l'info en un coup d'œil"
        case .onboardingNewsWallDescription: return "Visualisez tous vos articles dans une interface moderne et élégante."
        case .onboardingAITitle: return "Newsletter IA"
        case .onboardingAISubtitle: return "Propulsée par l'intelligence artificielle locale"
        case .onboardingAIDescription: return "Chaque jour, recevez une synthèse personnalisée de vos flux, générée 100% on-device."
        case .onboardingPreferencesTitle: return "Préférences"
        case .onboardingPreferencesSubtitle: return "Choisissez vos options, vous pourrez les modifier plus tard."
        case .onboardingEnableNotifications: return "Activer les notifications"
        case .onboardingReducePopups: return "Réduire les popups dans le lecteur"
        case .onboardingSourcesTitle: return "Choisissez vos premières sources"
        case .onboardingSourcesSubtitle: return "Vous pouvez les modifier plus tard dans la sidebar."
        case .onboardingOrganizationTitle: return "Organisation"
        case .onboardingOrganizationSubtitle: return "Classez vos sources"
        case .onboardingOrganizationDescription: return "Créez des dossiers et organisez vos flux par glisser-déposer."
        case .onboardingStartTitle: return "Commencer"
        case .onboardingStartSubtitle: return "Ajoutez votre premier flux"
        case .onboardingStartDescription: return "Cliquez sur + et collez l'URL d'un site. Flux trouvera le flux RSS automatiquement."
        case .onboardingNext: return "Suivant"
        case .onboardingStart: return "Commencer"
        case .onboardingSafariTitle: return "Extension Safari"
        case .onboardingSafariSubtitle: return "Ajoutez un flux en un clic"
        case .onboardingSafariDescription: return "Flux inclut une extension Safari. Activez-la dans les réglages de Safari pour ajouter un flux depuis n'importe quel site en un clic."
        case .rateApp: return "Noter l'application"
        case .badgeReadLaterToggle: return "Pastille « À lire plus tard » sur l'icône"
        case .filterAdsToggle: return "Masquer les articles publicitaires et promotionnels"
        case .signals: return "Signaux"
        case .signalsFeatured: return "À la une"
        case .signalsFeaturedSubtitle: return "Les événements les plus suivis en ce moment"
        case .signalsAll: return "Tous les signaux"
        case .signalsAllSubtitle: return "Parcourez les marchés prédictifs actifs par domaine"
        case .signalsUpdatedAt: return "Mis à jour "
        case .signalsIntro: return "Ce que les marchés prédictifs anticipent sur le monde. Chaque pourcentage reflète la probabilité estimée par des milliers de parieurs en argent réel."
        case .signalsYes: return "Oui"
        case .signalsNo: return "Non"
        case .signalsNoResult: return "Aucun signal pour « %@ »"
        case .signalsTryOtherCategory: return "Essayez une autre catégorie"
        case .signalsLoading: return "Chargement des signaux…"
        case .signalsLoadError: return "Impossible de charger les signaux"
        case .signalsRetry: return "Réessayer"
        case .signalsEndDate: return "Fin %@"
        case .signalsResolution: return "Résolution le %@"
        case .signalsVolume: return "Volume"
        case .signalsLiquidity: return "Liquidité"
        case .signalsComments: return "Commentaires"
        case .signalsCompetitiveness: return "Compétitivité"
        case .signalsProbability: return "Probabilité"
        case .signalsMarkets: return "Marchés"
        case .signalsNoComments: return "Aucun commentaire disponible"
        case .signalsNewNotificationTitle: return "Nouveau signal"
        case .signalsNewNotificationBody: return "%d nouveau(x) signal(aux) détecté(s)"
        }
    }

    var english: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .all: return "All"
        case .newsWall: return "News Wall"
        case .markAllAsSeen: return "Mark all as seen"
        case .markAllAsSeenHelp: return "Reset counters for all feeds"
        case .myFavorites: return "Read Later"
        case .folders: return "Folders"
        case .youtube: return "Youtube"
        case .music: return "Music"
        case .myFeeds: return "My Feeds"
        case .addFeed: return "Add Feed"
        case .addFolder: return "Add Folder"
        case .aiSettings: return "AI Settings"
        case .cancel: return "Cancel"
        case .save: return "Save"
        case .loading: return "Loading articles..."
        case .reload: return "Reload"
        case .noArticles: return "No articles available"
        case .noFavorites: return "No articles to read later"
        case .lastUpdate: return "Last update"
        case .source: return "Source"
        case .addToFavorites: return "Add to read later"
        case .removeFromFavorites: return "Remove from read later"
        case .openInBrowser: return "Open in browser"
        case .readerMode: return "Reader mode"
        case .back: return "Back"
        case .emptyReadLaterHint: return "To get started, click the Read Later icon"
        case .shareByEmail: return "Send by email"
        case .shareByMessage: return "By message"
        case .writeXPost: return "Write an X post"
        case .copyURL: return "Copy URL"
        case .spacebarPlayPause: return "Use the spacebar to play / pause the video"
        case .newsletterTitle: return "My newsletter"
        case .newsletterTitleWithDate: return "My newsletter — %@"
        case .newsletterGenerated: return "Generated:"
        case .newsletterImageAI: return "AI Image"
        case .newsletterVideosToday: return "Today's videos"
        case .newsletterFeed: return "Feed"
        case .newsletterPreparing: return "Preparing your newsletter with local artificial intelligence…"
        case .newsletterEmptyHint: return "Create an editorial summary of the entire news wall."
        case .generate: return "Generate"
        case .generateMyNewsletter: return "Generate my newsletter"
        case .scheduleSettings: return "Schedule settings"
        case .listenNewsletter: return "Listen to the newsletter"
        case .appleIntelligenceWorking: return "Local artificial intelligence at work"
        case .aiCreatingSummary: return "Local artificial intelligence is creating your summary…"
        // Settings
        case .discoveryTitle: return "Discovery"
        case .discoveryTrending: return "Trending"
        case .discoveryForYou: return "For You"
        case .discoverySeeMore: return "See more"
        case .settings: return "Settings"
        case .windowBlurToggle: return "Liquid glass window background"
        case .hideTitleOnThumbnails: return "Hide title and source on thumbnails (visible on hover)"
        case .notificationsToggle: return "Enable notifications"
        case .notificationsNewsToggle: return "Enable news notifications"
        case .notificationsSignalsToggle: return "Enable signal notifications"
        case .hapticsToggle: return "Enable haptic feedback"
        case .openArticleFirstToggle: return "Open the article before the AI summary"
        case .reduceOverlaysToggle: return "Reduce popups in reader"
        case .alwaysOpenInBrowserToggle: return "Always open articles in your browser"
        case .interfaceLanguage: return "Interface language"
        case .language: return "Language"
        case .reviewIntroduction: return "Review introduction"
        case .settingsSaved: return "Settings saved ✅"
        case .saveError: return "Error saving settings"
        // Articles
        case .allArticles: return "All articles"
        case .readLater: return "Read later"
        // Newsletter Schedule
        case .scheduleNewsletter: return "Schedule newsletter"
        case .scheduleNewsletterDescription: return "Choose up to 3 daily times to automatically generate the newsletter."
        case .scheduleNewsletterNotification: return "A notification will alert you when the newsletter is ready."
        case .beta: return "BETA"
        // Configuration Import/Export
        case .configuration: return "Configuration"
        case .configurationImportHint: return "Use the 'Import' button to select a configuration file"
        case .exportConfig: return "Export"
        case .importConfig: return "Import"
        case .deleteConfig: return "Delete"
        case .importSummary: return "Import summary"
        case .feedsImported: return "feeds imported"
        case .foldersImported: return "folders imported"
        case .feedsSkipped: return "feeds skipped (already exist)"
        case .foldersSkipped: return "folders skipped (already exist)"
        case .feeds: return "feeds"
        case .foldersLabel: return "folders"
        case .deleteConfigWarning: return "This action will permanently delete all feeds, folders and settings. This action is irreversible.\n\nMake sure you have exported your configuration before continuing."
        // Add Feed
        case .searchingRSSFeed: return "Searching for RSS feed…"
        case .subscriptions: return "Subscriptions"
        case .addFeedURL: return "Add a feed (URL)"
        case .add: return "Add"
        // Actions
        case .rename: return "Rename"
        case .delete: return "Delete"
        case .skip: return "Skip"
        // Help texts
        case .helpCloseArticle: return "Close article"
        case .helpOpenInBrowser: return "Open in browser"
        case .helpPostOnX: return "Post on X"
        case .helpCloseWindow: return "Close window"
        case .helpReaderTheme: return "Reader theme"
        case .helpOpenVideo: return "Open video"
        // Alerts
        case .errorX: return "X Error"
        case .deleteFeed: return "Delete feed"
        // Developer
        case .openLogsWindow: return "Open logs window"
        // Onboarding
        case .onboardingWelcomeTitle: return "Welcome to Flux"
        case .onboardingWelcomeSubtitle: return "Your smart RSS reader"
        case .onboardingWelcomeDescription: return "Follow your favorite sites and stay informed with local artificial intelligence."
        case .onboardingNewsWallTitle: return "News Wall"
        case .onboardingNewsWallSubtitle: return "All the news at a glance"
        case .onboardingNewsWallDescription: return "View all your articles in a modern and elegant interface."
        case .onboardingAITitle: return "AI Newsletter"
        case .onboardingAISubtitle: return "Powered by local artificial intelligence"
        case .onboardingAIDescription: return "Every day, receive a personalized summary of your feeds, generated 100% on-device."
        case .onboardingPreferencesTitle: return "Preferences"
        case .onboardingPreferencesSubtitle: return "Choose your options, you can change them later."
        case .onboardingEnableNotifications: return "Enable notifications"
        case .onboardingReducePopups: return "Reduce popups in reader"
        case .onboardingSourcesTitle: return "Choose your first sources"
        case .onboardingSourcesSubtitle: return "You can change them later in the sidebar."
        case .onboardingOrganizationTitle: return "Organization"
        case .onboardingOrganizationSubtitle: return "Organize your sources"
        case .onboardingOrganizationDescription: return "Create folders and organize your feeds with drag and drop."
        case .onboardingStartTitle: return "Get Started"
        case .onboardingStartSubtitle: return "Add your first feed"
        case .onboardingStartDescription: return "Click + and paste a website URL. Flux will find the RSS feed automatically."
        case .onboardingNext: return "Next"
        case .onboardingStart: return "Get Started"
        case .onboardingSafariTitle: return "Safari Extension"
        case .onboardingSafariSubtitle: return "Add a feed in one click"
        case .onboardingSafariDescription: return "Flux includes a Safari extension. Enable it in Safari settings to add a feed from any website in one click."
        case .rateApp: return "Rate the app"
        case .badgeReadLaterToggle: return "\"Read Later\" badge on app icon"
        case .filterAdsToggle: return "Hide advertising and promotional articles"
        case .signals: return "Signals"
        case .signalsFeatured: return "Featured"
        case .signalsFeaturedSubtitle: return "The most-watched events right now"
        case .signalsAll: return "All Signals"
        case .signalsAllSubtitle: return "Browse active prediction markets by category"
        case .signalsUpdatedAt: return "Updated "
        case .signalsIntro: return "What prediction markets anticipate about the world. Each percentage reflects the probability estimated by thousands of real-money bettors."
        case .signalsYes: return "Yes"
        case .signalsNo: return "No"
        case .signalsNoResult: return "No signal for \"%@\""
        case .signalsTryOtherCategory: return "Try another category"
        case .signalsLoading: return "Loading signals…"
        case .signalsLoadError: return "Unable to load signals"
        case .signalsRetry: return "Retry"
        case .signalsEndDate: return "Ends %@"
        case .signalsResolution: return "Resolves on %@"
        case .signalsVolume: return "Volume"
        case .signalsLiquidity: return "Liquidity"
        case .signalsComments: return "Comments"
        case .signalsCompetitiveness: return "Competitiveness"
        case .signalsProbability: return "Probability"
        case .signalsMarkets: return "Markets"
        case .signalsNoComments: return "No comments available"
        case .signalsNewNotificationTitle: return "New signal"
        case .signalsNewNotificationBody: return "%d new signal(s) detected"
        }
    }

    var spanish: String {
        switch self {
        case .today: return "Hoy"
        case .yesterday: return "Ayer"
        case .all: return "Todos"
        case .newsWall: return "Muro de Noticias"
        case .markAllAsSeen: return "Marcar todo como visto"
        case .markAllAsSeenHelp: return "Restablecer los contadores de todos los feeds"
        case .myFavorites: return "Leer Más Tarde"
        case .folders: return "Carpetas"
        case .youtube: return "Youtube"
        case .music: return "Music"
        case .myFeeds: return "Mis Feeds"
        case .addFeed: return "Añadir Feed"
        case .addFolder: return "Añadir Carpeta"
        case .aiSettings: return "Configuración IA"
        case .cancel: return "Cancelar"
        case .save: return "Guardar"
        case .loading: return "Cargando artículos..."
        case .reload: return "Recargar"
        case .noArticles: return "No hay artículos disponibles"
        case .noFavorites: return "No hay artículos para leer más tarde"
        case .lastUpdate: return "Última actualización"
        case .source: return "Fuente"
        case .addToFavorites: return "Añadir a leer más tarde"
        case .removeFromFavorites: return "Quitar de leer más tarde"
        case .openInBrowser: return "Abrir en navegador"
        case .readerMode: return "Modo lector"
        case .back: return "Atrás"
        case .emptyReadLaterHint: return "Para empezar, haz clic en el icono Leer más tarde"
        case .shareByEmail: return "Enviar por correo"
        case .shareByMessage: return "Por mensaje"
        case .writeXPost: return "Escribir un post de X"
        case .copyURL: return "Copiar URL"
        case .spacebarPlayPause: return "Usa la barra espaciadora para reproducir / pausar el vídeo"
        case .newsletterTitle: return "Mi newsletter"
        case .newsletterTitleWithDate: return "Mi newsletter — %@"
        case .newsletterGenerated: return "Generada:"
        case .newsletterImageAI: return "Imagen IA"
        case .newsletterVideosToday: return "Vídeos de hoy"
        case .newsletterFeed: return "Feed"
        case .newsletterPreparing: return "Preparando tu newsletter con inteligencia artificial local…"
        case .newsletterEmptyHint: return "Crea una síntesis editorial de todo el muro de noticias."
        case .generate: return "Generar"
        case .generateMyNewsletter: return "Generar mi newsletter"
        case .scheduleSettings: return "Ajustes de programación"
        case .listenNewsletter: return "Escuchar la newsletter"
        case .appleIntelligenceWorking: return "La inteligencia artificial local en acción"
        case .aiCreatingSummary: return "La inteligencia artificial local está creando tu resumen…"
        // Settings
        case .discoveryTitle: return "Descubrimiento"
        case .discoveryTrending: return "Tendencias"
        case .discoveryForYou: return "Para ti"
        case .discoverySeeMore: return "Ver más"
        case .settings: return "Ajustes"
        case .windowBlurToggle: return "Fondo de ventana en liquid glass"
        case .hideTitleOnThumbnails: return "Ocultar título y fuente en miniaturas (visible al pasar)"
        case .notificationsToggle: return "Activar notificaciones"
        case .notificationsNewsToggle: return "Activar notificaciones de noticias"
        case .notificationsSignalsToggle: return "Activar notificaciones de señales"
        case .hapticsToggle: return "Activar respuesta háptica"
        case .openArticleFirstToggle: return "Abrir el artículo antes del resumen con IA"
        case .reduceOverlaysToggle: return "Reducir pop-ups en el lector"
        case .alwaysOpenInBrowserToggle: return "Abrir siempre los artículos en su navegador"
        case .interfaceLanguage: return "Idioma de la interfaz"
        case .language: return "Idioma"
        case .reviewIntroduction: return "Volver a ver la introducción"
        case .settingsSaved: return "Ajustes guardados ✅"
        case .saveError: return "Error al guardar los ajustes"
        // Articles
        case .allArticles: return "Todos los artículos"
        case .readLater: return "Leer más tarde"
        // Newsletter Schedule
        case .scheduleNewsletter: return "Programar newsletter"
        case .scheduleNewsletterDescription: return "Elige hasta 3 horarios diarios para generar automáticamente la newsletter."
        case .scheduleNewsletterNotification: return "Una notificación te avisará cuando la newsletter esté lista."
        case .beta: return "BETA"
        // Configuration Import/Export
        case .configuration: return "Configuración"
        case .configurationImportHint: return "Usa el botón 'Importar' para seleccionar un archivo de configuración"
        case .exportConfig: return "Exportar"
        case .importConfig: return "Importar"
        case .deleteConfig: return "Eliminar"
        case .importSummary: return "Resumen de la importación"
        case .feedsImported: return "feeds importados"
        case .foldersImported: return "carpetas importadas"
        case .feedsSkipped: return "feeds omitidos (ya existen)"
        case .foldersSkipped: return "carpetas omitidas (ya existen)"
        case .feeds: return "feeds"
        case .foldersLabel: return "carpetas"
        case .deleteConfigWarning: return "Esta acción eliminará permanentemente todos los feeds, carpetas y configuraciones. Esta acción es irreversible.\n\nAsegúrate de haber exportado tu configuración antes de continuar."
        // Add Feed
        case .searchingRSSFeed: return "Buscando feed RSS…"
        case .subscriptions: return "Suscripciones"
        case .addFeedURL: return "Añadir un feed (URL)"
        case .add: return "Añadir"
        // Actions
        case .rename: return "Renombrar"
        case .delete: return "Eliminar"
        case .skip: return "Omitir"
        // Help texts
        case .helpCloseArticle: return "Cerrar artículo"
        case .helpOpenInBrowser: return "Abrir en navegador"
        case .helpPostOnX: return "Publicar en X"
        case .helpCloseWindow: return "Cerrar ventana"
        case .helpReaderTheme: return "Tema del lector"
        case .helpOpenVideo: return "Abrir vídeo"
        // Alerts
        case .errorX: return "Error de X"
        case .deleteFeed: return "Eliminar feed"
        // Developer
        case .openLogsWindow: return "Abrir ventana de logs"
        // Onboarding
        case .onboardingWelcomeTitle: return "Bienvenido a Flux"
        case .onboardingWelcomeSubtitle: return "Tu lector RSS inteligente"
        case .onboardingWelcomeDescription: return "Sigue tus sitios favoritos y mantente informado con inteligencia artificial local."
        case .onboardingNewsWallTitle: return "Muro de noticias"
        case .onboardingNewsWallSubtitle: return "Toda la información de un vistazo"
        case .onboardingNewsWallDescription: return "Visualiza todos tus artículos en una interfaz moderna y elegante."
        case .onboardingAITitle: return "Newsletter IA"
        case .onboardingAISubtitle: return "Impulsada por inteligencia artificial local"
        case .onboardingAIDescription: return "Cada día, recibe un resumen personalizado de tus feeds, generado 100% en el dispositivo."
        case .onboardingPreferencesTitle: return "Preferencias"
        case .onboardingPreferencesSubtitle: return "Elige tus opciones, podrás cambiarlas más tarde."
        case .onboardingEnableNotifications: return "Activar notificaciones"
        case .onboardingReducePopups: return "Reducir popups en el lector"
        case .onboardingSourcesTitle: return "Elige tus primeras fuentes"
        case .onboardingSourcesSubtitle: return "Puedes cambiarlas más tarde en la barra lateral."
        case .onboardingOrganizationTitle: return "Organización"
        case .onboardingOrganizationSubtitle: return "Clasifica tus fuentes"
        case .onboardingOrganizationDescription: return "Crea carpetas y organiza tus feeds arrastrando y soltando."
        case .onboardingStartTitle: return "Empezar"
        case .onboardingStartSubtitle: return "Añade tu primer feed"
        case .onboardingStartDescription: return "Haz clic en + y pega la URL de un sitio. Flux encontrará el feed RSS automáticamente."
        case .onboardingNext: return "Siguiente"
        case .onboardingStart: return "Empezar"
        case .onboardingSafariTitle: return "Extensión Safari"
        case .onboardingSafariSubtitle: return "Añade un feed con un clic"
        case .onboardingSafariDescription: return "Flux incluye una extensión de Safari. Actívala en los ajustes de Safari para añadir un feed desde cualquier sitio con un clic."
        case .rateApp: return "Valorar la aplicación"
        case .badgeReadLaterToggle: return "Insignia «Leer más tarde» en el icono"
        case .filterAdsToggle: return "Ocultar artículos publicitarios y promocionales"
        case .signals: return "Señales"
        case .signalsFeatured: return "Destacados"
        case .signalsFeaturedSubtitle: return "Los eventos más seguidos ahora mismo"
        case .signalsAll: return "Todas las señales"
        case .signalsAllSubtitle: return "Explora los mercados de predicción activos por categoría"
        case .signalsUpdatedAt: return "Actualizado "
        case .signalsIntro: return "Lo que los mercados de predicción anticipan sobre el mundo. Cada porcentaje refleja la probabilidad estimada por miles de apostadores con dinero real."
        case .signalsYes: return "Sí"
        case .signalsNo: return "No"
        case .signalsNoResult: return "Sin señales para \"%@\""
        case .signalsTryOtherCategory: return "Prueba otra categoría"
        case .signalsLoading: return "Cargando señales…"
        case .signalsLoadError: return "No se pueden cargar las señales"
        case .signalsRetry: return "Reintentar"
        case .signalsEndDate: return "Fin %@"
        case .signalsResolution: return "Resolución el %@"
        case .signalsVolume: return "Volumen"
        case .signalsLiquidity: return "Liquidez"
        case .signalsComments: return "Comentarios"
        case .signalsCompetitiveness: return "Competitividad"
        case .signalsProbability: return "Probabilidad"
        case .signalsMarkets: return "Mercados"
        case .signalsNoComments: return "No hay comentarios disponibles"
        case .signalsNewNotificationTitle: return "Nueva señal"
        case .signalsNewNotificationBody: return "%d nueva(s) señal(es) detectada(s)"
        }
    }

    var german: String {
        switch self {
        case .today: return "Heute"
        case .yesterday: return "Gestern"
        case .all: return "Alle"
        case .newsWall: return "Nachrichtenwand"
        case .markAllAsSeen: return "Alles als gesehen markieren"
        case .markAllAsSeenHelp: return "Zähler aller Feeds auf null setzen"
        case .myFavorites: return "Später lesen"
        case .folders: return "Ordner"
        case .youtube: return "Youtube"
        case .music: return "Music"
        case .myFeeds: return "Meine Feeds"
        case .addFeed: return "Feed hinzufügen"
        case .addFolder: return "Ordner hinzufügen"
        case .aiSettings: return "KI-Einstellungen"
        case .cancel: return "Abbrechen"
        case .save: return "Speichern"
        case .loading: return "Artikel werden geladen..."
        case .reload: return "Neu laden"
        case .noArticles: return "Keine Artikel verfügbar"
        case .noFavorites: return "Keine Artikel zum Später lesen"
        case .lastUpdate: return "Letzte Aktualisierung"
        case .source: return "Quelle"
        case .addToFavorites: return "Zum Später lesen hinzufügen"
        case .removeFromFavorites: return "Aus Später lesen entfernen"
        case .openInBrowser: return "Im Browser öffnen"
        case .readerMode: return "Lesemodus"
        case .back: return "Zurück"
        case .emptyReadLaterHint: return "Zum Start klicke auf das \u{201E}Später lesen\u{201C}-Symbol"
        case .shareByEmail: return "Per E-Mail senden"
        case .shareByMessage: return "Per Nachricht"
        case .writeXPost: return "Einen X-Post schreiben"
        case .copyURL: return "URL kopieren"
        case .spacebarPlayPause: return "Leertaste drücken zum Abspielen / Pausieren"
        case .newsletterTitle: return "Mein Newsletter"
        case .newsletterTitleWithDate: return "Mein Newsletter — %@"
        case .newsletterGenerated: return "Erstellt:"
        case .newsletterImageAI: return "KI-Bild"
        case .newsletterVideosToday: return "Videos heute"
        case .newsletterFeed: return "Feed"
        case .newsletterPreparing: return "Ich bereite Ihren Newsletter mit lokaler künstlicher Intelligenz vor…"
        case .newsletterEmptyHint: return "Erstellen Sie eine redaktionelle Zusammenfassung der gesamten Nachrichtenwand."
        case .generate: return "Generieren"
        case .generateMyNewsletter: return "Meinen Newsletter generieren"
        case .scheduleSettings: return "Planungseinstellungen"
        case .listenNewsletter: return "Newsletter anhören"
        case .appleIntelligenceWorking: return "Lokale künstliche Intelligenz arbeitet"
        case .aiCreatingSummary: return "Lokale künstliche Intelligenz erstellt Ihre Zusammenfassung…"
        // Settings
        case .discoveryTitle: return "Entdecken"
        case .discoveryTrending: return "Im Trend"
        case .discoveryForYou: return "Für dich"
        case .discoverySeeMore: return "Mehr anzeigen"
        case .settings: return "Einstellungen"
        case .windowBlurToggle: return "Transparenter Hintergrundunschärfe des Fensters"
        case .hideTitleOnThumbnails: return "Titel und Quelle auf Miniaturbildern ausblenden (beim Überfahren sichtbar)"
        case .notificationsToggle: return "Benachrichtigungen aktivieren"
        case .notificationsNewsToggle: return "Benachrichtigungen für Nachrichten aktivieren"
        case .notificationsSignalsToggle: return "Benachrichtigungen für Signale aktivieren"
        case .hapticsToggle: return "Haptisches Feedback aktivieren"
        case .openArticleFirstToggle: return "Artikel vor der KI-Zusammenfassung öffnen"
        case .reduceOverlaysToggle: return "Pop-ups im Lesemodus reduzieren"
        case .alwaysOpenInBrowserToggle: return "Artikel immer in Ihrem Browser öffnen"
        case .interfaceLanguage: return "Schnittstellensprache"
        case .language: return "Sprache"
        case .reviewIntroduction: return "Einführung erneut ansehen"
        case .settingsSaved: return "Einstellungen gespeichert ✅"
        case .saveError: return "Fehler beim Speichern der Einstellungen"
        // Articles
        case .allArticles: return "Alle Artikel"
        case .readLater: return "Später lesen"
        // Newsletter Schedule
        case .scheduleNewsletter: return "Newsletter planen"
        case .scheduleNewsletterDescription: return "Wähle bis zu 3 tägliche Uhrzeiten, um den Newsletter automatisch zu erstellen."
        case .scheduleNewsletterNotification: return "Eine Benachrichtigung informiert dich, wenn der Newsletter fertig ist."
        case .beta: return "BETA"
        // Configuration Import/Export
        case .configuration: return "Konfiguration"
        case .configurationImportHint: return "Verwende die Schaltfläche 'Importieren', um eine Konfigurationsdatei auszuwählen"
        case .exportConfig: return "Exportieren"
        case .importConfig: return "Importieren"
        case .deleteConfig: return "Löschen"
        case .importSummary: return "Importübersicht"
        case .feedsImported: return "Feeds importiert"
        case .foldersImported: return "Ordner importiert"
        case .feedsSkipped: return "Feeds übersprungen (bereits vorhanden)"
        case .foldersSkipped: return "Ordner übersprungen (bereits vorhanden)"
        case .feeds: return "Feeds"
        case .foldersLabel: return "Ordner"
        case .deleteConfigWarning: return "Diese Aktion löscht dauerhaft alle Feeds, Ordner und Einstellungen. Diese Aktion ist unwiderruflich.\n\nStelle sicher, dass du deine Konfiguration exportiert hast, bevor du fortfährst."
        // Add Feed
        case .searchingRSSFeed: return "RSS-Feed wird gesucht…"
        case .subscriptions: return "Abonnements"
        case .addFeedURL: return "Feed hinzufügen (URL)"
        case .add: return "Hinzufügen"
        // Actions
        case .rename: return "Umbenennen"
        case .delete: return "Löschen"
        case .skip: return "Überspringen"
        // Help texts
        case .helpCloseArticle: return "Artikel schließen"
        case .helpOpenInBrowser: return "Im Browser öffnen"
        case .helpPostOnX: return "Auf X posten"
        case .helpCloseWindow: return "Fenster schließen"
        case .helpReaderTheme: return "Leser-Thema"
        case .helpOpenVideo: return "Video öffnen"
        // Alerts
        case .errorX: return "X-Fehler"
        case .deleteFeed: return "Feed löschen"
        // Developer
        case .openLogsWindow: return "Log-Fenster öffnen"
        // Onboarding
        case .onboardingWelcomeTitle: return "Willkommen bei Flux"
        case .onboardingWelcomeSubtitle: return "Dein intelligenter RSS-Reader"
        case .onboardingWelcomeDescription: return "Folge deinen Lieblingsseiten und bleibe dank lokaler künstlicher Intelligenz informiert."
        case .onboardingNewsWallTitle: return "Nachrichtenwand"
        case .onboardingNewsWallSubtitle: return "Alle Infos auf einen Blick"
        case .onboardingNewsWallDescription: return "Sieh dir alle deine Artikel in einer modernen und eleganten Oberfläche an."
        case .onboardingAITitle: return "KI-Newsletter"
        case .onboardingAISubtitle: return "Angetrieben durch lokale künstliche Intelligenz"
        case .onboardingAIDescription: return "Erhalte jeden Tag eine personalisierte Zusammenfassung deiner Feeds, 100% auf dem Gerät generiert."
        case .onboardingPreferencesTitle: return "Einstellungen"
        case .onboardingPreferencesSubtitle: return "Wähle deine Optionen, du kannst sie später ändern."
        case .onboardingEnableNotifications: return "Benachrichtigungen aktivieren"
        case .onboardingReducePopups: return "Popups im Reader reduzieren"
        case .onboardingSourcesTitle: return "Wähle deine ersten Quellen"
        case .onboardingSourcesSubtitle: return "Du kannst sie später in der Seitenleiste ändern."
        case .onboardingOrganizationTitle: return "Organisation"
        case .onboardingOrganizationSubtitle: return "Ordne deine Quellen"
        case .onboardingOrganizationDescription: return "Erstelle Ordner und organisiere deine Feeds per Drag & Drop."
        case .onboardingStartTitle: return "Loslegen"
        case .onboardingStartSubtitle: return "Füge deinen ersten Feed hinzu"
        case .onboardingStartDescription: return "Klicke auf + und füge die URL einer Website ein. Flux findet den RSS-Feed automatisch."
        case .onboardingNext: return "Weiter"
        case .onboardingStart: return "Loslegen"
        case .onboardingSafariTitle: return "Safari-Erweiterung"
        case .onboardingSafariSubtitle: return "Feed mit einem Klick hinzufügen"
        case .onboardingSafariDescription: return "Flux enthält eine Safari-Erweiterung. Aktiviere sie in den Safari-Einstellungen, um Feeds von jeder Website mit einem Klick hinzuzufügen."
        case .rateApp: return "App bewerten"
        case .badgeReadLaterToggle: return "\"Später lesen\"-Badge auf dem App-Symbol"
        case .filterAdsToggle: return "Werbe- und Promotionsartikel ausblenden"
        case .signals: return "Signale"
        case .signalsFeatured: return "Highlights"
        case .signalsFeaturedSubtitle: return "Die meistbeobachteten Ereignisse gerade"
        case .signalsAll: return "Alle Signale"
        case .signalsAllSubtitle: return "Aktive Vorhersagemärkte nach Kategorie durchsuchen"
        case .signalsUpdatedAt: return "Aktualisiert "
        case .signalsIntro: return "Was Vorhersagemärkte über die Welt antizipieren. Jeder Prozentsatz spiegelt die von Tausenden von Echtgeld-Wettenden geschätzte Wahrscheinlichkeit wider."
        case .signalsYes: return "Ja"
        case .signalsNo: return "Nein"
        case .signalsNoResult: return "Kein Signal für \"%@\""
        case .signalsTryOtherCategory: return "Andere Kategorie versuchen"
        case .signalsLoading: return "Signale werden geladen…"
        case .signalsLoadError: return "Signale können nicht geladen werden"
        case .signalsRetry: return "Erneut versuchen"
        case .signalsEndDate: return "Ende %@"
        case .signalsResolution: return "Auflösung am %@"
        case .signalsVolume: return "Volumen"
        case .signalsLiquidity: return "Liquidität"
        case .signalsComments: return "Kommentare"
        case .signalsCompetitiveness: return "Wettbewerb"
        case .signalsProbability: return "Wahrscheinlichkeit"
        case .signalsMarkets: return "Märkte"
        case .signalsNoComments: return "Keine Kommentare verfügbar"
        case .signalsNewNotificationTitle: return "Neues Signal"
        case .signalsNewNotificationBody: return "%d neue(s) Signal(e) erkannt"
        }
    }

    var italian: String {
        switch self {
        case .today: return "Oggi"
        case .yesterday: return "Ieri"
        case .all: return "Tutti"
        case .newsWall: return "Muro delle Notizie"
        case .markAllAsSeen: return "Segna tutto come visto"
        case .markAllAsSeenHelp: return "Azzera i contatori di tutti i feed"
        case .myFavorites: return "Da Leggere Più Tardi"
        case .folders: return "Cartelle"
        case .youtube: return "Youtube"
        case .music: return "Music"
        case .myFeeds: return "I Miei Feed"
        case .addFeed: return "Aggiungi Feed"
        case .addFolder: return "Aggiungi Cartella"
        case .aiSettings: return "Impostazioni IA"
        case .cancel: return "Annulla"
        case .save: return "Salva"
        case .loading: return "Caricamento articoli..."
        case .reload: return "Ricarica"
        case .noArticles: return "Nessun articolo disponibile"
        case .noFavorites: return "Nessun articolo da leggere più tardi"
        case .lastUpdate: return "Ultimo aggiornamento"
        case .source: return "Fonte"
        case .addToFavorites: return "Aggiungi a da leggere più tardi"
        case .removeFromFavorites: return "Rimuovi da da leggere più tardi"
        case .openInBrowser: return "Apri nel browser"
        case .readerMode: return "Modalità lettura"
        case .back: return "Indietro"
        case .emptyReadLaterHint: return "Per iniziare, fai clic sull’icona Leggi dopo"
        case .shareByEmail: return "Invia per email"
        case .shareByMessage: return "Per messaggio"
        case .writeXPost: return "Scrivi un post su X"
        case .copyURL: return "Copia URL"
        case .spacebarPlayPause: return "Usa la barra spaziatrice per riprodurre / mettere in pausa"
        case .newsletterTitle: return "La mia newsletter"
        case .newsletterTitleWithDate: return "La mia newsletter — %@"
        case .newsletterGenerated: return "Generata:"
        case .newsletterImageAI: return "Immagine IA"
        case .newsletterVideosToday: return "Video di oggi"
        case .newsletterFeed: return "Feed"
        case .newsletterPreparing: return "Sto preparando la tua newsletter con intelligenza artificiale locale…"
        case .newsletterEmptyHint: return "Crea una sintesi editoriale di tutto il muro di notizie."
        case .generate: return "Genera"
        case .generateMyNewsletter: return "Genera la mia newsletter"
        case .scheduleSettings: return "Impostazioni di pianificazione"
        case .listenNewsletter: return "Ascolta la newsletter"
        case .appleIntelligenceWorking: return "L'intelligenza artificiale locale al lavoro"
        case .aiCreatingSummary: return "L'intelligenza artificiale locale sta creando il tuo riassunto…"
        // Settings
        case .discoveryTitle: return "Scopri"
        case .discoveryTrending: return "Di tendenza"
        case .discoveryForYou: return "Per te"
        case .discoverySeeMore: return "Vedi altro"
        case .settings: return "Impostazioni"
        case .windowBlurToggle: return "Sfocatura trasparente dello sfondo della finestra"
        case .hideTitleOnThumbnails: return "Nascondi titolo e fonte sulle miniature (visibile al passaggio)"
        case .notificationsToggle: return "Attiva notifiche"
        case .notificationsNewsToggle: return "Attiva le notifiche delle notizie"
        case .notificationsSignalsToggle: return "Attiva le notifiche dei segnali"
        case .hapticsToggle: return "Attiva feedback aptico"
        case .openArticleFirstToggle: return "Apri l'articolo prima del riassunto IA"
        case .reduceOverlaysToggle: return "Riduci i popup nel lettore"
        case .alwaysOpenInBrowserToggle: return "Apri sempre gli articoli nel tuo browser"
        case .interfaceLanguage: return "Lingua dell'interfaccia"
        case .language: return "Lingua"
        case .reviewIntroduction: return "Rivedi l'introduzione"
        case .settingsSaved: return "Impostazioni salvate ✅"
        case .saveError: return "Errore durante il salvataggio delle impostazioni"
        // Articles
        case .allArticles: return "Tutti gli articoli"
        case .readLater: return "Da leggere più tardi"
        // Newsletter Schedule
        case .scheduleNewsletter: return "Pianifica newsletter"
        case .scheduleNewsletterDescription: return "Scegli fino a 3 orari giornalieri per generare automaticamente la newsletter."
        case .scheduleNewsletterNotification: return "Una notifica ti avviserà quando la newsletter sarà pronta."
        case .beta: return "BETA"
        // Configuration Import/Export
        case .configuration: return "Configurazione"
        case .configurationImportHint: return "Usa il pulsante 'Importa' per selezionare un file di configurazione"
        case .exportConfig: return "Esporta"
        case .importConfig: return "Importa"
        case .deleteConfig: return "Elimina"
        case .importSummary: return "Riepilogo importazione"
        case .feedsImported: return "feed importati"
        case .foldersImported: return "cartelle importate"
        case .feedsSkipped: return "feed saltati (già esistenti)"
        case .foldersSkipped: return "cartelle saltate (già esistenti)"
        case .feeds: return "feed"
        case .foldersLabel: return "cartelle"
        case .deleteConfigWarning: return "Questa azione eliminerà definitivamente tutti i feed, le cartelle e le impostazioni. Questa azione è irreversibile.\n\nAssicurati di aver esportato la tua configurazione prima di continuare."
        // Add Feed
        case .searchingRSSFeed: return "Ricerca del feed RSS…"
        case .subscriptions: return "Abbonamenti"
        case .addFeedURL: return "Aggiungi un feed (URL)"
        case .add: return "Aggiungi"
        // Actions
        case .rename: return "Rinomina"
        case .delete: return "Elimina"
        case .skip: return "Salta"
        // Help texts
        case .helpCloseArticle: return "Chiudi articolo"
        case .helpOpenInBrowser: return "Apri nel browser"
        case .helpPostOnX: return "Pubblica su X"
        case .helpCloseWindow: return "Chiudi finestra"
        case .helpReaderTheme: return "Tema lettore"
        case .helpOpenVideo: return "Apri video"
        // Alerts
        case .errorX: return "Errore X"
        case .deleteFeed: return "Elimina feed"
        // Developer
        case .openLogsWindow: return "Apri finestra log"
        // Onboarding
        case .onboardingWelcomeTitle: return "Benvenuto in Flux"
        case .onboardingWelcomeSubtitle: return "Il tuo lettore RSS intelligente"
        case .onboardingWelcomeDescription: return "Segui i tuoi siti preferiti e resta informato con l'intelligenza artificiale locale."
        case .onboardingNewsWallTitle: return "Bacheca notizie"
        case .onboardingNewsWallSubtitle: return "Tutte le info a colpo d'occhio"
        case .onboardingNewsWallDescription: return "Visualizza tutti i tuoi articoli in un'interfaccia moderna ed elegante."
        case .onboardingAITitle: return "Newsletter IA"
        case .onboardingAISubtitle: return "Alimentata dall'intelligenza artificiale locale"
        case .onboardingAIDescription: return "Ogni giorno, ricevi un riepilogo personalizzato dei tuoi feed, generato al 100% sul dispositivo."
        case .onboardingPreferencesTitle: return "Preferenze"
        case .onboardingPreferencesSubtitle: return "Scegli le tue opzioni, potrai modificarle in seguito."
        case .onboardingEnableNotifications: return "Attiva le notifiche"
        case .onboardingReducePopups: return "Riduci i popup nel lettore"
        case .onboardingSourcesTitle: return "Scegli le tue prime fonti"
        case .onboardingSourcesSubtitle: return "Puoi modificarle in seguito nella barra laterale."
        case .onboardingOrganizationTitle: return "Organizzazione"
        case .onboardingOrganizationSubtitle: return "Classifica le tue fonti"
        case .onboardingOrganizationDescription: return "Crea cartelle e organizza i tuoi feed con il drag & drop."
        case .onboardingStartTitle: return "Inizia"
        case .onboardingStartSubtitle: return "Aggiungi il tuo primo feed"
        case .onboardingStartDescription: return "Clicca su + e incolla l'URL di un sito. Flux troverà il feed RSS automaticamente."
        case .onboardingNext: return "Avanti"
        case .onboardingStart: return "Inizia"
        case .onboardingSafariTitle: return "Estensione Safari"
        case .onboardingSafariSubtitle: return "Aggiungi un feed con un clic"
        case .onboardingSafariDescription: return "Flux include un'estensione Safari. Attivala nelle impostazioni di Safari per aggiungere un feed da qualsiasi sito con un clic."
        case .rateApp: return "Valuta l'app"
        case .badgeReadLaterToggle: return "Badge «Da leggere» sull'icona"
        case .filterAdsToggle: return "Nascondi articoli pubblicitari e promozionali"
        case .signals: return "Segnali"
        case .signalsFeatured: return "In evidenza"
        case .signalsFeaturedSubtitle: return "Gli eventi più seguiti al momento"
        case .signalsAll: return "Tutti i segnali"
        case .signalsAllSubtitle: return "Esplora i mercati predittivi attivi per categoria"
        case .signalsUpdatedAt: return "Aggiornato "
        case .signalsIntro: return "Ciò che i mercati predittivi anticipano sul mondo. Ogni percentuale riflette la probabilità stimata da migliaia di scommettitori con denaro reale."
        case .signalsYes: return "Sì"
        case .signalsNo: return "No"
        case .signalsNoResult: return "Nessun segnale per \"%@\""
        case .signalsTryOtherCategory: return "Prova un'altra categoria"
        case .signalsLoading: return "Caricamento segnali…"
        case .signalsLoadError: return "Impossibile caricare i segnali"
        case .signalsRetry: return "Riprova"
        case .signalsEndDate: return "Fine %@"
        case .signalsResolution: return "Risoluzione il %@"
        case .signalsVolume: return "Volume"
        case .signalsLiquidity: return "Liquidità"
        case .signalsComments: return "Commenti"
        case .signalsCompetitiveness: return "Competitività"
        case .signalsProbability: return "Probabilità"
        case .signalsMarkets: return "Mercati"
        case .signalsNoComments: return "Nessun commento disponibile"
        case .signalsNewNotificationTitle: return "Nuovo segnale"
        case .signalsNewNotificationBody: return "%d nuovo/i segnale/i rilevato/i"
        }
    }

    var portuguese: String {
        switch self {
        case .today: return "Hoje"
        case .yesterday: return "Ontem"
        case .all: return "Todos"
        case .markAllAsSeen: return "Marcar tudo como visto"
        case .markAllAsSeenHelp: return "Zerar os contadores de todos os feeds"
        case .newsletterTitle: return "Minha newsletter"
        case .newsletterTitleWithDate: return "Minha newsletter — %@"
        case .newsletterGenerated: return "Gerada:"
        case .newsletterImageAI: return "Imagem IA"
        case .newsletterVideosToday: return "Vídeos de hoje"
        case .newsletterFeed: return "Feed"
        case .newsletterPreparing: return "Preparando sua newsletter com inteligência artificial local…"
        case .newsletterEmptyHint: return "Crie uma síntese editorial de todas as notícias do mural."
        case .generate: return "Gerar"
        case .generateMyNewsletter: return "Gerar minha newsletter"
        case .scheduleSettings: return "Configurações de agendamento"
        case .listenNewsletter: return "Ouvir a newsletter"
        case .appleIntelligenceWorking: return "A inteligência artificial local em ação"
        case .aiCreatingSummary: return "A inteligência artificial local está criando seu resumo…"
        // Settings
        case .discoveryTitle: return "Descobrir"
        case .discoveryTrending: return "Em alta"
        case .discoveryForYou: return "Para você"
        case .discoverySeeMore: return "Ver mais"
        case .settings: return "Configurações"
        case .windowBlurToggle: return "Fundo da janela em liquid glass"
        case .hideTitleOnThumbnails: return "Ocultar título e fonte nas miniaturas (visível ao passar)"
        case .notificationsToggle: return "Ativar notificações"
        case .notificationsNewsToggle: return "Ativar notificações de notícias"
        case .notificationsSignalsToggle: return "Ativar notificações de sinais"
        case .hapticsToggle: return "Ativar feedback tátil"
        case .openArticleFirstToggle: return "Abrir o artigo antes do resumo de IA"
        case .reduceOverlaysToggle: return "Reduzir pop-ups no leitor"
        case .alwaysOpenInBrowserToggle: return "Abrir sempre os artigos no seu navegador"
        case .interfaceLanguage: return "Idioma da interface"
        case .language: return "Idioma"
        case .reviewIntroduction: return "Rever a introdução"
        case .settingsSaved: return "Configurações salvas ✅"
        case .saveError: return "Erro ao salvar as configurações"
        // Articles
        case .allArticles: return "Todos os artigos"
        case .readLater: return "Ler mais tarde"
        case .addToFavorites: return "Adicionar para ler mais tarde"
        case .removeFromFavorites: return "Remover de ler mais tarde"
        case .shareByEmail: return "Enviar por email"
        case .shareByMessage: return "Por mensagem"
        case .copyURL: return "Copiar URL"
        case .spacebarPlayPause: return "Usa a barra de espaço para reproduzir / pausar o vídeo"
        // Newsletter Schedule
        case .scheduleNewsletter: return "Agendar newsletter"
        case .scheduleNewsletterDescription: return "Escolha até 3 horários diários para gerar a newsletter automaticamente."
        case .scheduleNewsletterNotification: return "Uma notificação avisará quando a newsletter estiver pronta."
        case .beta: return "BETA"
        // Configuration Import/Export
        case .configuration: return "Configuração"
        case .configurationImportHint: return "Use o botão 'Importar' para selecionar um arquivo de configuração"
        case .exportConfig: return "Exportar"
        case .importConfig: return "Importar"
        case .deleteConfig: return "Excluir"
        case .importSummary: return "Resumo da importação"
        case .feedsImported: return "feeds importados"
        case .foldersImported: return "pastas importadas"
        case .feedsSkipped: return "feeds ignorados (já existem)"
        case .foldersSkipped: return "pastas ignoradas (já existem)"
        case .feeds: return "feeds"
        case .foldersLabel: return "pastas"
        case .deleteConfigWarning: return "Esta ação excluirá permanentemente todos os feeds, pastas e configurações. Esta ação é irreversível.\n\nCertifique-se de ter exportado sua configuração antes de continuar."
        // Add Feed
        case .searchingRSSFeed: return "Procurando feed RSS…"
        case .subscriptions: return "Assinaturas"
        case .addFeedURL: return "Adicionar um feed (URL)"
        case .add: return "Adicionar"
        // Actions
        case .rename: return "Renomear"
        case .delete: return "Excluir"
        case .skip: return "Pular"
        // Help texts
        case .helpCloseArticle: return "Fechar artigo"
        case .helpOpenInBrowser: return "Abrir no navegador"
        case .helpPostOnX: return "Publicar no X"
        case .helpCloseWindow: return "Fechar janela"
        case .helpReaderTheme: return "Tema do leitor"
        case .helpOpenVideo: return "Abrir vídeo"
        // Alerts
        case .errorX: return "Erro do X"
        case .deleteFeed: return "Excluir feed"
        // Onboarding
        case .onboardingWelcomeTitle: return "Bem-vindo ao Flux"
        case .onboardingWelcomeSubtitle: return "Seu leitor RSS inteligente"
        case .onboardingWelcomeDescription: return "Acompanhe seus sites favoritos e fique informado com inteligência artificial local."
        case .onboardingNewsWallTitle: return "Mural de notícias"
        case .onboardingNewsWallSubtitle: return "Todas as informações de relance"
        case .onboardingNewsWallDescription: return "Visualize todos os seus artigos em uma interface moderna e elegante."
        case .onboardingAITitle: return "Newsletter IA"
        case .onboardingAISubtitle: return "Impulsionada por inteligência artificial local"
        case .onboardingAIDescription: return "Todos os dias, receba um resumo personalizado dos seus feeds, gerado 100% no dispositivo."
        case .onboardingPreferencesTitle: return "Preferências"
        case .onboardingPreferencesSubtitle: return "Escolha suas opções, você pode alterá-las depois."
        case .onboardingEnableNotifications: return "Ativar notificações"
        case .onboardingReducePopups: return "Reduzir popups no leitor"
        case .onboardingSourcesTitle: return "Escolha suas primeiras fontes"
        case .onboardingSourcesSubtitle: return "Você pode alterá-las depois na barra lateral."
        case .onboardingOrganizationTitle: return "Organização"
        case .onboardingOrganizationSubtitle: return "Classifique suas fontes"
        case .onboardingOrganizationDescription: return "Crie pastas e organize seus feeds com arrastar e soltar."
        case .onboardingStartTitle: return "Começar"
        case .onboardingStartSubtitle: return "Adicione seu primeiro feed"
        case .onboardingStartDescription: return "Clique em + e cole a URL de um site. O Flux encontrará o feed RSS automaticamente."
        case .onboardingNext: return "Próximo"
        case .onboardingStart: return "Começar"
        case .onboardingSafariTitle: return "Extensão Safari"
        case .onboardingSafariSubtitle: return "Adicione um feed com um clique"
        case .onboardingSafariDescription: return "O Flux inclui uma extensão do Safari. Ative-a nas configurações do Safari para adicionar um feed de qualquer site com um clique."
        case .rateApp: return "Avaliar o aplicativo"
        case .badgeReadLaterToggle: return "Badge «Ler depois» no ícone"
        case .filterAdsToggle: return "Ocultar artigos publicitários e promocionais"
        case .signals: return "Sinais"
        case .signalsFeatured: return "Destaques"
        case .signalsFeaturedSubtitle: return "Os eventos mais acompanhados agora"
        case .signalsAll: return "Todos os sinais"
        case .signalsAllSubtitle: return "Explore os mercados de previsão ativos por categoria"
        case .signalsUpdatedAt: return "Atualizado "
        case .signalsIntro: return "O que os mercados de previsão antecipam sobre o mundo. Cada percentagem reflete a probabilidade estimada por milhares de apostadores com dinheiro real."
        case .signalsYes: return "Sim"
        case .signalsNo: return "Não"
        case .signalsNoResult: return "Nenhum sinal para \"%@\""
        case .signalsTryOtherCategory: return "Tente outra categoria"
        case .signalsLoading: return "A carregar sinais…"
        case .signalsLoadError: return "Não é possível carregar os sinais"
        case .signalsRetry: return "Tentar novamente"
        case .signalsEndDate: return "Fim %@"
        case .signalsResolution: return "Resolução em %@"
        case .signalsVolume: return "Volume"
        case .signalsLiquidity: return "Liquidez"
        case .signalsComments: return "Comentários"
        case .signalsCompetitiveness: return "Competitividade"
        case .signalsProbability: return "Probabilidade"
        case .signalsMarkets: return "Mercados"
        case .signalsNoComments: return "Nenhum comentário disponível"
        case .signalsNewNotificationTitle: return "Novo sinal"
        case .signalsNewNotificationBody: return "%d novo(s) sinal(is) detectado(s)"
        default: return english
        }
    }

    var japanese: String {
        switch self {
        case .today: return "今日"
        case .yesterday: return "昨日"
        case .all: return "すべて"
        case .markAllAsSeen: return "すべて既読にする"
        case .markAllAsSeenHelp: return "すべてのフィードのカウンターを0にする"
        case .newsletterTitle: return "マイニュースレター"
        case .newsletterTitleWithDate: return "マイニュースレター — %@"
        case .newsletterGenerated: return "生成日時:"
        case .newsletterImageAI: return "AI画像"
        case .newsletterVideosToday: return "今日の動画"
        case .newsletterFeed: return "Feed"
        case .newsletterPreparing: return "ローカル人工知能でニュースレターを準備中…"
        case .newsletterEmptyHint: return "ニュースウォール全体の要約を作成しましょう。"
        case .generate: return "生成"
        case .generateMyNewsletter: return "ニュースレターを生成"
        case .scheduleSettings: return "スケジュール設定"
        case .listenNewsletter: return "ニュースレターを再生"
        case .appleIntelligenceWorking: return "ローカル人工知能が処理中です"
        case .aiCreatingSummary: return "ローカル人工知能が要約を作成中…"
        // Settings
        case .discoveryTitle: return "ディスカバリー"
        case .discoveryTrending: return "トレンド"
        case .discoveryForYou: return "あなたへ"
        case .discoverySeeMore: return "もっと見る"
        case .settings: return "設定"
        case .windowBlurToggle: return "ウィンドウ背景の透明ブラー"
        case .hideTitleOnThumbnails: return "サムネイルのタイトルとソースを非表示（ホバー時に表示）"
        case .notificationsToggle: return "通知を有効にする"
        case .notificationsNewsToggle: return "ニュース通知を有効にする"
        case .notificationsSignalsToggle: return "シグナル通知を有効にする"
        case .hapticsToggle: return "触覚フィードバックを有効にする"
        case .openArticleFirstToggle: return "AI要約の前に記事を開く"
        case .reduceOverlaysToggle: return "リーダーでポップアップを減らす"
        case .alwaysOpenInBrowserToggle: return "常にお使いのブラウザで記事を開く"
        case .interfaceLanguage: return "インターフェース言語"
        case .language: return "言語"
        case .reviewIntroduction: return "紹介を再表示"
        case .settingsSaved: return "設定が保存されました ✅"
        case .saveError: return "設定の保存中にエラーが発生しました"
        // Articles
        case .allArticles: return "すべての記事"
        case .readLater: return "後で読む"
        case .addToFavorites: return "後で読むに追加"
        case .removeFromFavorites: return "後で読むから削除"
        case .shareByEmail: return "メールで送信"
        case .shareByMessage: return "メッセージで送信"
        case .copyURL: return "URLをコピー"
        case .spacebarPlayPause: return "スペースバーで再生 / 一時停止"
        // Newsletter Schedule
        case .scheduleNewsletter: return "ニュースレターをスケジュール"
        case .scheduleNewsletterDescription: return "ニュースレターを自動生成する最大3つの時刻を選択してください。"
        case .scheduleNewsletterNotification: return "ニュースレターの準備ができたら通知でお知らせします。"
        case .beta: return "ベータ"
        // Configuration Import/Export
        case .configuration: return "設定"
        case .configurationImportHint: return "「インポート」ボタンを使用して設定ファイルを選択してください"
        case .exportConfig: return "エクスポート"
        case .importConfig: return "インポート"
        case .deleteConfig: return "削除"
        case .importSummary: return "インポート概要"
        case .feedsImported: return "件のフィードをインポート"
        case .foldersImported: return "件のフォルダをインポート"
        case .feedsSkipped: return "件のフィードをスキップ（既存）"
        case .foldersSkipped: return "件のフォルダをスキップ（既存）"
        case .feeds: return "フィード"
        case .foldersLabel: return "フォルダ"
        case .deleteConfigWarning: return "この操作により、すべてのフィード、フォルダ、設定が完全に削除されます。この操作は取り消せません。\n\n続行する前に、設定をエクスポートしてください。"
        // Add Feed
        case .searchingRSSFeed: return "RSSフィードを検索中…"
        case .subscriptions: return "購読"
        case .addFeedURL: return "フィードを追加（URL）"
        case .add: return "追加"
        // Actions
        case .rename: return "名前を変更"
        case .delete: return "削除"
        case .skip: return "スキップ"
        // Help texts
        case .helpCloseArticle: return "記事を閉じる"
        case .helpOpenInBrowser: return "ブラウザで開く"
        case .helpPostOnX: return "Xに投稿"
        case .helpCloseWindow: return "ウィンドウを閉じる"
        case .helpReaderTheme: return "リーダーテーマ"
        case .helpOpenVideo: return "動画を開く"
        // Alerts
        case .errorX: return "Xエラー"
        case .deleteFeed: return "フィードを削除"
        // Onboarding
        case .onboardingWelcomeTitle: return "Fluxへようこそ"
        case .onboardingWelcomeSubtitle: return "スマートなRSSリーダー"
        case .onboardingWelcomeDescription: return "ローカルAIでお気に入りのサイトをフォローし、最新情報をチェックしましょう。"
        case .onboardingNewsWallTitle: return "ニュースウォール"
        case .onboardingNewsWallSubtitle: return "すべてのニュースを一目で"
        case .onboardingNewsWallDescription: return "モダンでエレガントなインターフェースですべての記事を閲覧できます。"
        case .onboardingAITitle: return "AIニュースレター"
        case .onboardingAISubtitle: return "ローカルAIが生成"
        case .onboardingAIDescription: return "毎日、フィードのパーソナライズされた要約を100%デバイス上で生成します。"
        case .onboardingPreferencesTitle: return "設定"
        case .onboardingPreferencesSubtitle: return "オプションを選択してください。後から変更できます。"
        case .onboardingEnableNotifications: return "通知を有効にする"
        case .onboardingReducePopups: return "リーダーのポップアップを減らす"
        case .onboardingSourcesTitle: return "最初のソースを選択"
        case .onboardingSourcesSubtitle: return "サイドバーで後から変更できます。"
        case .onboardingOrganizationTitle: return "整理"
        case .onboardingOrganizationSubtitle: return "ソースを分類"
        case .onboardingOrganizationDescription: return "フォルダを作成し、ドラッグ＆ドロップでフィードを整理しましょう。"
        case .onboardingStartTitle: return "はじめる"
        case .onboardingStartSubtitle: return "最初のフィードを追加"
        case .onboardingStartDescription: return "+をクリックしてサイトのURLを貼り付けてください。FluxがRSSフィードを自動的に見つけます。"
        case .onboardingNext: return "次へ"
        case .onboardingStart: return "はじめる"
        case .onboardingSafariTitle: return "Safari 拡張機能"
        case .onboardingSafariSubtitle: return "ワンクリックでフィードを追加"
        case .onboardingSafariDescription: return "FluxにはSafari拡張機能が含まれています。Safariの設定で有効にすると、どのサイトからでもワンクリックでフィードを追加できます。"
        case .rateApp: return "アプリを評価する"
        case .badgeReadLaterToggle: return "アイコンに「あとで読む」バッジを表示"
        case .filterAdsToggle: return "広告・プロモーション記事を非表示にする"
        case .signals: return "シグナル"
        case .signalsFeatured: return "注目"
        case .signalsFeaturedSubtitle: return "今最も注目されているイベント"
        case .signalsAll: return "すべてのシグナル"
        case .signalsAllSubtitle: return "カテゴリ別にアクティブな予測市場を閲覧"
        case .signalsUpdatedAt: return "更新 "
        case .signalsIntro: return "予測市場が世界について予測することです。各パーセンテージは、実際のお金で賭けている何千人ものベッターによって推定された確率を反映しています。"
        case .signalsYes: return "はい"
        case .signalsNo: return "いいえ"
        case .signalsNoResult: return "「%@」のシグナルなし"
        case .signalsTryOtherCategory: return "別のカテゴリを試す"
        case .signalsLoading: return "シグナルを読み込み中…"
        case .signalsLoadError: return "シグナルを読み込めません"
        case .signalsRetry: return "再試行"
        case .signalsEndDate: return "終了 %@"
        case .signalsResolution: return "解決日 %@"
        case .signalsVolume: return "取引量"
        case .signalsLiquidity: return "流動性"
        case .signalsComments: return "コメント"
        case .signalsCompetitiveness: return "競争率"
        case .signalsProbability: return "確率"
        case .signalsMarkets: return "マーケット"
        case .signalsNoComments: return "コメントはありません"
        case .signalsNewNotificationTitle: return "新しいシグナル"
        case .signalsNewNotificationBody: return "%d件の新しいシグナルを検出"
        default: return english
        }
    }

    var chinese: String {
        switch self {
        case .today: return "今天"
        case .yesterday: return "昨天"
        case .all: return "全部"
        case .markAllAsSeen: return "全部标记为已读"
        case .markAllAsSeenHelp: return "将所有订阅源计数器重置为 0"
        case .newsletterTitle: return "我的新闻简报"
        case .newsletterTitleWithDate: return "我的新闻简报 — %@"
        case .newsletterGenerated: return "生成时间："
        case .newsletterImageAI: return "AI 图片"
        case .newsletterVideosToday: return "今日视频"
        case .newsletterFeed: return "Feed"
        case .newsletterPreparing: return "正在使用本地人工智能准备您的新闻简报…"
        case .newsletterEmptyHint: return "为整个资讯墙创建一份编辑性摘要。"
        case .generate: return "生成"
        case .generateMyNewsletter: return "生成我的简报"
        case .scheduleSettings: return "计划设置"
        case .listenNewsletter: return "收听简报"
        case .appleIntelligenceWorking: return "本地人工智能正在处理"
        case .aiCreatingSummary: return "本地人工智能正在创建您的摘要…"
        // Settings
        case .discoveryTitle: return "发现"
        case .discoveryTrending: return "热门"
        case .discoveryForYou: return "为你推荐"
        case .discoverySeeMore: return "查看更多"
        case .settings: return "设置"
        case .windowBlurToggle: return "窗口背景透明模糊"
        case .hideTitleOnThumbnails: return "在缩略图上隐藏标题和来源（悬停时可见）"
        case .notificationsToggle: return "启用通知"
        case .notificationsNewsToggle: return "启用新闻通知"
        case .notificationsSignalsToggle: return "启用信号通知"
        case .hapticsToggle: return "启用触觉反馈"
        case .openArticleFirstToggle: return "在 AI 摘要前打开文章"
        case .reduceOverlaysToggle: return "在阅读模式减少弹窗"
        case .alwaysOpenInBrowserToggle: return "始终在您的浏览器中打开文章"
        case .interfaceLanguage: return "界面语言"
        case .language: return "语言"
        case .reviewIntroduction: return "重新查看介绍"
        case .settingsSaved: return "设置已保存 ✅"
        case .saveError: return "保存设置时出错"
        // Articles
        case .allArticles: return "所有文章"
        case .readLater: return "稍后阅读"
        case .addToFavorites: return "添加到稍后阅读"
        case .removeFromFavorites: return "从稍后阅读中移除"
        case .shareByEmail: return "通过电子邮件发送"
        case .shareByMessage: return "通过消息发送"
        case .copyURL: return "复制 URL"
        case .spacebarPlayPause: return "按空格键播放 / 暂停视频"
        // Newsletter Schedule
        case .scheduleNewsletter: return "计划新闻简报"
        case .scheduleNewsletterDescription: return "选择最多3个每日时间来自动生成新闻简报。"
        case .scheduleNewsletterNotification: return "新闻简报准备好后会通知您。"
        case .beta: return "测试版"
        // Configuration Import/Export
        case .configuration: return "配置"
        case .configurationImportHint: return "使用「导入」按钮选择配置文件"
        case .exportConfig: return "导出"
        case .importConfig: return "导入"
        case .deleteConfig: return "删除"
        case .importSummary: return "导入摘要"
        case .feedsImported: return "个订阅源已导入"
        case .foldersImported: return "个文件夹已导入"
        case .feedsSkipped: return "个订阅源已跳过（已存在）"
        case .foldersSkipped: return "个文件夹已跳过（已存在）"
        case .feeds: return "订阅源"
        case .foldersLabel: return "文件夹"
        case .deleteConfigWarning: return "此操作将永久删除所有订阅源、文件夹和设置。此操作不可撤销。\n\n请确保在继续之前已导出您的配置。"
        // Add Feed
        case .searchingRSSFeed: return "正在搜索RSS订阅源…"
        case .subscriptions: return "订阅"
        case .addFeedURL: return "添加订阅源（URL）"
        case .add: return "添加"
        // Actions
        case .rename: return "重命名"
        case .delete: return "删除"
        case .skip: return "跳过"
        // Help texts
        case .helpCloseArticle: return "关闭文章"
        case .helpOpenInBrowser: return "在浏览器中打开"
        case .helpPostOnX: return "发布到X"
        case .helpCloseWindow: return "关闭窗口"
        case .helpReaderTheme: return "阅读器主题"
        case .helpOpenVideo: return "打开视频"
        // Alerts
        case .errorX: return "X错误"
        case .deleteFeed: return "删除订阅源"
        // Onboarding
        case .onboardingWelcomeTitle: return "欢迎使用 Flux"
        case .onboardingWelcomeSubtitle: return "您的智能 RSS 阅读器"
        case .onboardingWelcomeDescription: return "通过本地人工智能关注您喜爱的网站，随时掌握最新资讯。"
        case .onboardingNewsWallTitle: return "资讯墙"
        case .onboardingNewsWallSubtitle: return "一览所有新闻"
        case .onboardingNewsWallDescription: return "在现代优雅的界面中查看所有文章。"
        case .onboardingAITitle: return "AI 简报"
        case .onboardingAISubtitle: return "由本地人工智能驱动"
        case .onboardingAIDescription: return "每天接收个性化的订阅摘要，100% 在设备上生成。"
        case .onboardingPreferencesTitle: return "偏好设置"
        case .onboardingPreferencesSubtitle: return "选择您的选项，稍后可以更改。"
        case .onboardingEnableNotifications: return "启用通知"
        case .onboardingReducePopups: return "减少阅读器中的弹窗"
        case .onboardingSourcesTitle: return "选择您的首批订阅源"
        case .onboardingSourcesSubtitle: return "您可以稍后在侧边栏中更改。"
        case .onboardingOrganizationTitle: return "整理"
        case .onboardingOrganizationSubtitle: return "分类您的订阅源"
        case .onboardingOrganizationDescription: return "创建文件夹，通过拖放整理您的订阅。"
        case .onboardingStartTitle: return "开始使用"
        case .onboardingStartSubtitle: return "添加您的第一个订阅"
        case .onboardingStartDescription: return "点击 + 并粘贴网站 URL。Flux 会自动找到 RSS 订阅源。"
        case .onboardingNext: return "下一步"
        case .onboardingStart: return "开始使用"
        case .onboardingSafariTitle: return "Safari 扩展"
        case .onboardingSafariSubtitle: return "一键添加订阅源"
        case .onboardingSafariDescription: return "Flux 包含 Safari 扩展。在 Safari 设置中启用后，即可在任意网站一键添加订阅源。"
        case .rateApp: return "评价应用"
        case .badgeReadLaterToggle: return "在图标上显示「稍后阅读」角标"
        case .filterAdsToggle: return "隐藏广告和促销文章"
        case .signals: return "信号"
        case .signalsFeatured: return "精选"
        case .signalsFeaturedSubtitle: return "当前最受关注的事件"
        case .signalsAll: return "所有信号"
        case .signalsAllSubtitle: return "按类别浏览活跃的预测市场"
        case .signalsUpdatedAt: return "更新于 "
        case .signalsIntro: return "预测市场对世界的预测。每个百分比反映了数千名真实资金投注者估计的概率。"
        case .signalsYes: return "是"
        case .signalsNo: return "否"
        case .signalsNoResult: return "没有\"%@\"的信号"
        case .signalsTryOtherCategory: return "尝试其他类别"
        case .signalsLoading: return "正在加载信号…"
        case .signalsLoadError: return "无法加载信号"
        case .signalsRetry: return "重试"
        case .signalsEndDate: return "结束 %@"
        case .signalsResolution: return "解析日期 %@"
        case .signalsVolume: return "成交量"
        case .signalsLiquidity: return "流动性"
        case .signalsComments: return "评论"
        case .signalsCompetitiveness: return "竞争度"
        case .signalsProbability: return "概率"
        case .signalsMarkets: return "市场"
        case .signalsNoComments: return "暂无评论"
        case .signalsNewNotificationTitle: return "新信号"
        case .signalsNewNotificationBody: return "检测到%d个新信号"
        default: return english
        }
    }

    var korean: String {
        switch self {
        case .today: return "오늘"
        case .yesterday: return "어제"
        case .all: return "전체"
        case .markAllAsSeen: return "모두 읽음으로 표시"
        case .markAllAsSeenHelp: return "모든 피드 카운터를 0으로 초기화"
        case .newsletterTitle: return "내 뉴스레터"
        case .newsletterTitleWithDate: return "내 뉴스레터 — %@"
        case .newsletterGenerated: return "생성 시간:"
        case .newsletterImageAI: return "AI 이미지"
        case .newsletterVideosToday: return "오늘의 영상"
        case .newsletterFeed: return "Feed"
        case .newsletterPreparing: return "로컬 인공지능으로 뉴스레터를 준비 중…"
        case .newsletterEmptyHint: return "뉴스 월 전체의 편집 요약을 만드세요."
        case .generate: return "생성"
        case .generateMyNewsletter: return "내 뉴스레터 생성"
        case .scheduleSettings: return "예약 설정"
        case .listenNewsletter: return "뉴스레터 듣기"
        case .appleIntelligenceWorking: return "로컬 인공지능 처리 중"
        case .aiCreatingSummary: return "로컬 인공지능이 요약을 생성 중…"
        // Settings
        case .discoveryTitle: return "디스커버리"
        case .discoveryTrending: return "트렌딩"
        case .discoveryForYou: return "당신을 위한"
        case .discoverySeeMore: return "더 보기"
        case .settings: return "설정"
        case .windowBlurToggle: return "창 배경 투명 블러"
        case .hideTitleOnThumbnails: return "썸네일에서 제목과 출처 숨기기 (호버 시 표시)"
        case .notificationsToggle: return "알림 활성화"
        case .notificationsNewsToggle: return "뉴스 알림 활성화"
        case .notificationsSignalsToggle: return "시그널 알림 활성화"
        case .hapticsToggle: return "햅틱 피드백 활성화"
        case .openArticleFirstToggle: return "AI 요약 전에 기사 열기"
        case .reduceOverlaysToggle: return "리더에서 팝업 줄이기"
        case .alwaysOpenInBrowserToggle: return "항상 내 브라우저에서 기사 열기"
        case .interfaceLanguage: return "인터페이스 언어"
        case .language: return "언어"
        case .reviewIntroduction: return "소개 다시 보기"
        case .settingsSaved: return "설정이 저장되었습니다 ✅"
        case .saveError: return "설정 저장 중 오류가 발생했습니다"
        // Articles
        case .allArticles: return "모든 기사"
        case .readLater: return "나중에 읽기"
        case .addToFavorites: return "나중에 읽기에 추가"
        case .removeFromFavorites: return "나중에 읽기에서 제거"
        case .shareByEmail: return "이메일로 보내기"
        case .shareByMessage: return "메시지로 보내기"
        case .copyURL: return "URL 복사"
        case .spacebarPlayPause: return "스페이스바로 재생 / 일시정지"
        // Newsletter Schedule
        case .scheduleNewsletter: return "뉴스레터 예약"
        case .scheduleNewsletterDescription: return "뉴스레터를 자동 생성할 최대 3개의 시간을 선택하세요."
        case .scheduleNewsletterNotification: return "뉴스레터가 준비되면 알림을 보내드립니다."
        case .beta: return "베타"
        // Configuration Import/Export
        case .configuration: return "구성"
        case .configurationImportHint: return "'가져오기' 버튼을 사용하여 구성 파일을 선택하세요"
        case .exportConfig: return "내보내기"
        case .importConfig: return "가져오기"
        case .deleteConfig: return "삭제"
        case .importSummary: return "가져오기 요약"
        case .feedsImported: return "개 피드 가져옴"
        case .foldersImported: return "개 폴더 가져옴"
        case .feedsSkipped: return "개 피드 건너뜀 (이미 존재)"
        case .foldersSkipped: return "개 폴더 건너뜀 (이미 존재)"
        case .feeds: return "피드"
        case .foldersLabel: return "폴더"
        case .deleteConfigWarning: return "이 작업은 모든 피드, 폴더 및 설정을 영구적으로 삭제합니다. 이 작업은 되돌릴 수 없습니다.\n\n계속하기 전에 구성을 내보냈는지 확인하세요."
        // Add Feed
        case .searchingRSSFeed: return "RSS 피드 검색 중…"
        case .subscriptions: return "구독"
        case .addFeedURL: return "피드 추가 (URL)"
        case .add: return "추가"
        // Actions
        case .rename: return "이름 변경"
        case .delete: return "삭제"
        case .skip: return "건너뛰기"
        // Help texts
        case .helpCloseArticle: return "기사 닫기"
        case .helpOpenInBrowser: return "브라우저에서 열기"
        case .helpPostOnX: return "X에 게시"
        case .helpCloseWindow: return "창 닫기"
        case .helpReaderTheme: return "리더 테마"
        case .helpOpenVideo: return "동영상 열기"
        // Alerts
        case .errorX: return "X 오류"
        case .deleteFeed: return "피드 삭제"
        // Onboarding
        case .onboardingWelcomeTitle: return "Flux에 오신 것을 환영합니다"
        case .onboardingWelcomeSubtitle: return "스마트 RSS 리더"
        case .onboardingWelcomeDescription: return "로컬 인공지능으로 좋아하는 사이트를 팔로우하고 최신 정보를 받아보세요."
        case .onboardingNewsWallTitle: return "뉴스 월"
        case .onboardingNewsWallSubtitle: return "한눈에 모든 뉴스를"
        case .onboardingNewsWallDescription: return "모던하고 세련된 인터페이스에서 모든 기사를 확인하세요."
        case .onboardingAITitle: return "AI 뉴스레터"
        case .onboardingAISubtitle: return "로컬 인공지능으로 구동"
        case .onboardingAIDescription: return "매일 피드의 맞춤 요약을 100% 기기에서 생성합니다."
        case .onboardingPreferencesTitle: return "환경설정"
        case .onboardingPreferencesSubtitle: return "옵션을 선택하세요. 나중에 변경할 수 있습니다."
        case .onboardingEnableNotifications: return "알림 활성화"
        case .onboardingReducePopups: return "리더의 팝업 줄이기"
        case .onboardingSourcesTitle: return "첫 번째 소스를 선택하세요"
        case .onboardingSourcesSubtitle: return "사이드바에서 나중에 변경할 수 있습니다."
        case .onboardingOrganizationTitle: return "정리"
        case .onboardingOrganizationSubtitle: return "소스를 분류하세요"
        case .onboardingOrganizationDescription: return "폴더를 만들고 드래그 앤 드롭으로 피드를 정리하세요."
        case .onboardingStartTitle: return "시작하기"
        case .onboardingStartSubtitle: return "첫 번째 피드 추가"
        case .onboardingStartDescription: return "+를 클릭하고 사이트 URL을 붙여넣으세요. Flux가 RSS 피드를 자동으로 찾습니다."
        case .onboardingNext: return "다음"
        case .onboardingStart: return "시작하기"
        case .onboardingSafariTitle: return "Safari 확장 프로그램"
        case .onboardingSafariSubtitle: return "원클릭으로 피드 추가"
        case .onboardingSafariDescription: return "Flux에는 Safari 확장 프로그램이 포함되어 있습니다. Safari 설정에서 활성화하면 어떤 사이트에서든 한 번의 클릭으로 피드를 추가할 수 있습니다."
        case .rateApp: return "앱 평가하기"
        case .badgeReadLaterToggle: return "앱 아이콘에 \"나중에 읽기\" 배지 표시"
        case .filterAdsToggle: return "광고 및 프로모션 기사 숨기기"
        case .signals: return "시그널"
        case .signalsFeatured: return "주목"
        case .signalsFeaturedSubtitle: return "지금 가장 많이 주목받는 이벤트"
        case .signalsAll: return "모든 시그널"
        case .signalsAllSubtitle: return "카테고리별 활성 예측 시장 탐색"
        case .signalsUpdatedAt: return "업데이트 "
        case .signalsIntro: return "예측 시장이 세계에 대해 예상하는 것. 각 퍼센트는 실제 돈을 베팅하는 수천 명의 베터들이 추정한 확률을 반영합니다."
        case .signalsYes: return "예"
        case .signalsNo: return "아니오"
        case .signalsNoResult: return "\"%@\"에 대한 시그널 없음"
        case .signalsTryOtherCategory: return "다른 카테고리 시도"
        case .signalsLoading: return "시그널 로딩 중…"
        case .signalsLoadError: return "시그널을 불러올 수 없습니다"
        case .signalsRetry: return "재시도"
        case .signalsEndDate: return "종료 %@"
        case .signalsResolution: return "해결일 %@"
        case .signalsVolume: return "거래량"
        case .signalsLiquidity: return "유동성"
        case .signalsComments: return "댓글"
        case .signalsCompetitiveness: return "경쟁도"
        case .signalsProbability: return "확률"
        case .signalsMarkets: return "마켓"
        case .signalsNoComments: return "댓글이 없습니다"
        case .signalsNewNotificationTitle: return "새로운 시그널"
        case .signalsNewNotificationBody: return "%d개의 새로운 시그널 감지"
        default: return english
        }
    }

    var russian: String {
        switch self {
        case .today: return "Сегодня"
        case .yesterday: return "Вчера"
        case .all: return "Все"
        case .markAllAsSeen: return "Отметить всё как прочитанное"
        case .markAllAsSeenHelp: return "Сбросить счётчики всех лент до 0"
        case .newsletterTitle: return "Моя рассылка"
        case .newsletterTitleWithDate: return "Моя рассылка — %@"
        case .newsletterGenerated: return "Сгенерировано:"
        case .newsletterImageAI: return "ИИ-изображение"
        case .newsletterVideosToday: return "Видео сегодня"
        case .newsletterFeed: return "Feed"
        case .newsletterPreparing: return "Готовлю вашу рассылку с локальным искусственным интеллектом…"
        case .newsletterEmptyHint: return "Создайте редакционное резюме всей ленты новостей."
        case .generate: return "Сгенерировать"
        case .generateMyNewsletter: return "Сгенерировать рассылку"
        case .scheduleSettings: return "Настройки расписания"
        case .listenNewsletter: return "Прослушать рассылку"
        case .appleIntelligenceWorking: return "Локальный искусственный интеллект работает"
        case .aiCreatingSummary: return "Локальный искусственный интеллект создаёт ваше резюме…"
        // Settings
        case .discoveryTitle: return "Открытия"
        case .discoveryTrending: return "В тренде"
        case .discoveryForYou: return "Для вас"
        case .discoverySeeMore: return "Показать ещё"
        case .settings: return "Настройки"
        case .windowBlurToggle: return "Прозрачное размытие фона окна"
        case .hideTitleOnThumbnails: return "Скрыть заголовок и источник на миниатюрах (видно при наведении)"
        case .notificationsToggle: return "Включить уведомления"
        case .notificationsNewsToggle: return "Включить уведомления о новостях"
        case .notificationsSignalsToggle: return "Включить уведомления о сигналах"
        case .hapticsToggle: return "Включить тактильную обратную связь"
        case .openArticleFirstToggle: return "Открывать статью до ИИ‑сводки"
        case .reduceOverlaysToggle: return "Уменьшать всплывающие окна в режиме чтения"
        case .alwaysOpenInBrowserToggle: return "Всегда открывать статьи в вашем браузере"
        case .interfaceLanguage: return "Язык интерфейса"
        case .language: return "Язык"
        case .reviewIntroduction: return "Посмотреть введение снова"
        case .settingsSaved: return "Настройки сохранены ✅"
        case .saveError: return "Ошибка при сохранении настроек"
        // Articles
        case .allArticles: return "Все статьи"
        case .readLater: return "Прочитать позже"
        case .addToFavorites: return "Добавить в «Прочитать позже»"
        case .removeFromFavorites: return "Убрать из «Прочитать позже»"
        case .shareByEmail: return "Отправить по почте"
        case .shareByMessage: return "Отправить сообщением"
        case .copyURL: return "Копировать URL"
        case .spacebarPlayPause: return "Нажмите пробел для воспроизведения / паузы"
        // Newsletter Schedule
        case .scheduleNewsletter: return "Запланировать рассылку"
        case .scheduleNewsletterDescription: return "Выберите до 3 ежедневных времён для автоматической генерации рассылки."
        case .scheduleNewsletterNotification: return "Уведомление сообщит вам, когда рассылка будет готова."
        case .beta: return "БЕТА"
        // Configuration Import/Export
        case .configuration: return "Конфигурация"
        case .configurationImportHint: return "Используйте кнопку «Импорт», чтобы выбрать файл конфигурации"
        case .exportConfig: return "Экспорт"
        case .importConfig: return "Импорт"
        case .deleteConfig: return "Удалить"
        case .importSummary: return "Сводка импорта"
        case .feedsImported: return "лент импортировано"
        case .foldersImported: return "папок импортировано"
        case .feedsSkipped: return "лент пропущено (уже существуют)"
        case .foldersSkipped: return "папок пропущено (уже существуют)"
        case .feeds: return "лент"
        case .foldersLabel: return "папок"
        case .deleteConfigWarning: return "Это действие навсегда удалит все ленты, папки и настройки. Это действие необратимо.\n\nУбедитесь, что вы экспортировали конфигурацию, прежде чем продолжить."
        // Add Feed
        case .searchingRSSFeed: return "Поиск RSS-ленты…"
        case .subscriptions: return "Подписки"
        case .addFeedURL: return "Добавить ленту (URL)"
        case .add: return "Добавить"
        // Actions
        case .rename: return "Переименовать"
        case .delete: return "Удалить"
        case .skip: return "Пропустить"
        // Help texts
        case .helpCloseArticle: return "Закрыть статью"
        case .helpOpenInBrowser: return "Открыть в браузере"
        case .helpPostOnX: return "Опубликовать в X"
        case .helpCloseWindow: return "Закрыть окно"
        case .helpReaderTheme: return "Тема чтения"
        case .helpOpenVideo: return "Открыть видео"
        // Alerts
        case .errorX: return "Ошибка X"
        case .deleteFeed: return "Удалить ленту"
        // Onboarding
        case .onboardingWelcomeTitle: return "Добро пожаловать в Flux"
        case .onboardingWelcomeSubtitle: return "Ваш умный RSS-ридер"
        case .onboardingWelcomeDescription: return "Следите за любимыми сайтами и оставайтесь в курсе благодаря локальному искусственному интеллекту."
        case .onboardingNewsWallTitle: return "Стена новостей"
        case .onboardingNewsWallSubtitle: return "Все новости одним взглядом"
        case .onboardingNewsWallDescription: return "Просматривайте все статьи в современном и элегантном интерфейсе."
        case .onboardingAITitle: return "ИИ-рассылка"
        case .onboardingAISubtitle: return "На базе локального искусственного интеллекта"
        case .onboardingAIDescription: return "Каждый день получайте персональную сводку ваших лент, сгенерированную на 100% на устройстве."
        case .onboardingPreferencesTitle: return "Настройки"
        case .onboardingPreferencesSubtitle: return "Выберите параметры, их можно изменить позже."
        case .onboardingEnableNotifications: return "Включить уведомления"
        case .onboardingReducePopups: return "Уменьшить всплывающие окна в ридере"
        case .onboardingSourcesTitle: return "Выберите первые источники"
        case .onboardingSourcesSubtitle: return "Вы можете изменить их позже в боковой панели."
        case .onboardingOrganizationTitle: return "Организация"
        case .onboardingOrganizationSubtitle: return "Классифицируйте источники"
        case .onboardingOrganizationDescription: return "Создавайте папки и упорядочивайте ленты перетаскиванием."
        case .onboardingStartTitle: return "Начать"
        case .onboardingStartSubtitle: return "Добавьте первую ленту"
        case .onboardingStartDescription: return "Нажмите + и вставьте URL сайта. Flux автоматически найдёт RSS-ленту."
        case .onboardingNext: return "Далее"
        case .onboardingStart: return "Начать"
        case .onboardingSafariTitle: return "Расширение Safari"
        case .onboardingSafariSubtitle: return "Добавляйте ленту в один клик"
        case .onboardingSafariDescription: return "Flux включает расширение для Safari. Активируйте его в настройках Safari, чтобы добавлять ленту с любого сайта одним кликом."
        case .rateApp: return "Оценить приложение"
        case .badgeReadLaterToggle: return "Значок «Прочитать позже» на иконке"
        case .filterAdsToggle: return "Скрыть рекламные и промо-статьи"
        case .signals: return "Сигналы"
        case .signalsFeatured: return "Избранное"
        case .signalsFeaturedSubtitle: return "Самые обсуждаемые события прямо сейчас"
        case .signalsAll: return "Все сигналы"
        case .signalsAllSubtitle: return "Просматривайте активные прогнозные рынки по категориям"
        case .signalsUpdatedAt: return "Обновлено "
        case .signalsIntro: return "То, что прогнозные рынки предвидят о мире. Каждый процент отражает вероятность, оцениваемую тысячами игроков на реальные деньги."
        case .signalsYes: return "Да"
        case .signalsNo: return "Нет"
        case .signalsNoResult: return "Нет сигналов для «%@»"
        case .signalsTryOtherCategory: return "Попробуйте другую категорию"
        case .signalsLoading: return "Загрузка сигналов…"
        case .signalsLoadError: return "Не удалось загрузить сигналы"
        case .signalsRetry: return "Повторить"
        case .signalsEndDate: return "Конец %@"
        case .signalsResolution: return "Решение %@"
        case .signalsVolume: return "Объём"
        case .signalsLiquidity: return "Ликвидность"
        case .signalsComments: return "Комментарии"
        case .signalsCompetitiveness: return "Конкурентность"
        case .signalsProbability: return "Вероятность"
        case .signalsMarkets: return "Рынки"
        case .signalsNoComments: return "Комментарии недоступны"
        case .signalsNewNotificationTitle: return "Новый сигнал"
        case .signalsNewNotificationBody: return "Обнаружено %d новых сигналов"
        default: return english
        }
    }
}

// MARK: - Extensions
extension Notification.Name {
    static let languageChanged = Notification.Name("LanguageChanged")
}

// MARK: - ViewModifier pour la localisation
struct LocalizedText: ViewModifier {
    let key: LocalizationKey
    
    func body(content: Content) -> some View {
        Text(LocalizationManager.shared.localizedString(key))
    }
}

extension View {
    func localizedText(_ key: LocalizationKey) -> some View {
        self.modifier(LocalizedText(key: key))
    }
}
