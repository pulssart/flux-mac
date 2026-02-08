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
    case myFavorites
    case folders
    case youtube
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
    // Settings
    case settings
    case windowBlurToggle
    case hideTitleOnThumbnails
    case notificationsToggle
    case hapticsToggle
    case openArticleFirstToggle
    case reduceOverlaysToggle
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
    
    var french: String {
        switch self {
        case .today: return "Aujourd'hui"
        case .yesterday: return "Hier"
        case .all: return "Tous"
        case .newsWall: return "Mur de flux"
        case .myFavorites: return "À lire plus tard"
        case .folders: return "Dossiers"
        case .youtube: return "Youtube"
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
        case .settings: return "Réglages"
        case .windowBlurToggle: return "Fond de fenêtre en liquid glass"
        case .hideTitleOnThumbnails: return "Masquer titre et source sur les miniatures (visible au survol)"
        case .notificationsToggle: return "Activer les notifications"
        case .hapticsToggle: return "Activer les retours haptiques"
        case .openArticleFirstToggle: return "Ouvrir l'article avant le résumé IA"
        case .reduceOverlaysToggle: return "Réduire les popups dans le lecteur"
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
        }
    }
    
    var english: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .all: return "All"
        case .newsWall: return "News Wall"
        case .myFavorites: return "Read Later"
        case .folders: return "Folders"
        case .youtube: return "Youtube"
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
        case .settings: return "Settings"
        case .windowBlurToggle: return "Liquid glass window background"
        case .hideTitleOnThumbnails: return "Hide title and source on thumbnails (visible on hover)"
        case .notificationsToggle: return "Enable notifications"
        case .hapticsToggle: return "Enable haptic feedback"
        case .openArticleFirstToggle: return "Open the article before the AI summary"
        case .reduceOverlaysToggle: return "Reduce popups in reader"
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
        }
    }
    
    var spanish: String {
        switch self {
        case .today: return "Hoy"
        case .yesterday: return "Ayer"
        case .all: return "Todos"
        case .newsWall: return "Muro de Noticias"
        case .myFavorites: return "Leer Más Tarde"
        case .folders: return "Carpetas"
        case .youtube: return "Youtube"
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
        case .settings: return "Ajustes"
        case .windowBlurToggle: return "Fondo de ventana en liquid glass"
        case .hideTitleOnThumbnails: return "Ocultar título y fuente en miniaturas (visible al pasar)"
        case .notificationsToggle: return "Activar notificaciones"
        case .hapticsToggle: return "Activar respuesta háptica"
        case .openArticleFirstToggle: return "Abrir el artículo antes del resumen con IA"
        case .reduceOverlaysToggle: return "Reducir pop-ups en el lector"
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
        }
    }
    
    var german: String {
        switch self {
        case .today: return "Heute"
        case .yesterday: return "Gestern"
        case .all: return "Alle"
        case .newsWall: return "Nachrichtenwand"
        case .myFavorites: return "Später lesen"
        case .folders: return "Ordner"
        case .youtube: return "Youtube"
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
        case .settings: return "Einstellungen"
        case .windowBlurToggle: return "Transparenter Hintergrundunschärfe des Fensters"
        case .hideTitleOnThumbnails: return "Titel und Quelle auf Miniaturbildern ausblenden (beim Überfahren sichtbar)"
        case .notificationsToggle: return "Benachrichtigungen aktivieren"
        case .hapticsToggle: return "Haptisches Feedback aktivieren"
        case .openArticleFirstToggle: return "Artikel vor der KI-Zusammenfassung öffnen"
        case .reduceOverlaysToggle: return "Pop-ups im Lesemodus reduzieren"
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
        }
    }
    
    var italian: String {
        switch self {
        case .today: return "Oggi"
        case .yesterday: return "Ieri"
        case .all: return "Tutti"
        case .newsWall: return "Muro delle Notizie"
        case .myFavorites: return "Da Leggere Più Tardi"
        case .folders: return "Cartelle"
        case .youtube: return "Youtube"
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
        case .settings: return "Impostazioni"
        case .windowBlurToggle: return "Sfocatura trasparente dello sfondo della finestra"
        case .hideTitleOnThumbnails: return "Nascondi titolo e fonte sulle miniature (visibile al passaggio)"
        case .notificationsToggle: return "Attiva notifiche"
        case .hapticsToggle: return "Attiva feedback aptico"
        case .openArticleFirstToggle: return "Apri l'articolo prima del riassunto IA"
        case .reduceOverlaysToggle: return "Riduci i popup nel lettore"
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
        }
    }

    var portuguese: String {
        switch self {
        case .today: return "Hoje"
        case .yesterday: return "Ontem"
        case .all: return "Todos"
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
        case .settings: return "Configurações"
        case .windowBlurToggle: return "Fundo da janela em liquid glass"
        case .hideTitleOnThumbnails: return "Ocultar título e fonte nas miniaturas (visível ao passar)"
        case .notificationsToggle: return "Ativar notificações"
        case .hapticsToggle: return "Ativar feedback tátil"
        case .openArticleFirstToggle: return "Abrir o artigo antes do resumo de IA"
        case .reduceOverlaysToggle: return "Reduzir pop-ups no leitor"
        case .interfaceLanguage: return "Idioma da interface"
        case .language: return "Idioma"
        case .reviewIntroduction: return "Rever a introdução"
        case .settingsSaved: return "Configurações salvas ✅"
        case .saveError: return "Erro ao salvar as configurações"
        // Articles
        case .allArticles: return "Todos os artigos"
        case .readLater: return "Ler mais tarde"
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
        default: return english
        }
    }

    var japanese: String {
        switch self {
        case .today: return "今日"
        case .yesterday: return "昨日"
        case .all: return "すべて"
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
        case .settings: return "設定"
        case .windowBlurToggle: return "ウィンドウ背景の透明ブラー"
        case .hideTitleOnThumbnails: return "サムネイルのタイトルとソースを非表示（ホバー時に表示）"
        case .notificationsToggle: return "通知を有効にする"
        case .hapticsToggle: return "触覚フィードバックを有効にする"
        case .openArticleFirstToggle: return "AI要約の前に記事を開く"
        case .reduceOverlaysToggle: return "リーダーでポップアップを減らす"
        case .interfaceLanguage: return "インターフェース言語"
        case .language: return "言語"
        case .reviewIntroduction: return "紹介を再表示"
        case .settingsSaved: return "設定が保存されました ✅"
        case .saveError: return "設定の保存中にエラーが発生しました"
        // Articles
        case .allArticles: return "すべての記事"
        case .readLater: return "後で読む"
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
        default: return english
        }
    }

    var chinese: String {
        switch self {
        case .today: return "今天"
        case .yesterday: return "昨天"
        case .all: return "全部"
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
        case .settings: return "设置"
        case .windowBlurToggle: return "窗口背景透明模糊"
        case .hideTitleOnThumbnails: return "在缩略图上隐藏标题和来源（悬停时可见）"
        case .notificationsToggle: return "启用通知"
        case .hapticsToggle: return "启用触觉反馈"
        case .openArticleFirstToggle: return "在 AI 摘要前打开文章"
        case .reduceOverlaysToggle: return "在阅读模式减少弹窗"
        case .interfaceLanguage: return "界面语言"
        case .language: return "语言"
        case .reviewIntroduction: return "重新查看介绍"
        case .settingsSaved: return "设置已保存 ✅"
        case .saveError: return "保存设置时出错"
        // Articles
        case .allArticles: return "所有文章"
        case .readLater: return "稍后阅读"
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
        default: return english
        }
    }

    var korean: String {
        switch self {
        case .today: return "오늘"
        case .yesterday: return "어제"
        case .all: return "전체"
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
        case .settings: return "설정"
        case .windowBlurToggle: return "창 배경 투명 블러"
        case .hideTitleOnThumbnails: return "썸네일에서 제목과 출처 숨기기 (호버 시 표시)"
        case .notificationsToggle: return "알림 활성화"
        case .hapticsToggle: return "햅틱 피드백 활성화"
        case .openArticleFirstToggle: return "AI 요약 전에 기사 열기"
        case .reduceOverlaysToggle: return "리더에서 팝업 줄이기"
        case .interfaceLanguage: return "인터페이스 언어"
        case .language: return "언어"
        case .reviewIntroduction: return "소개 다시 보기"
        case .settingsSaved: return "설정이 저장되었습니다 ✅"
        case .saveError: return "설정 저장 중 오류가 발생했습니다"
        // Articles
        case .allArticles: return "모든 기사"
        case .readLater: return "나중에 읽기"
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
        default: return english
        }
    }

    var russian: String {
        switch self {
        case .today: return "Сегодня"
        case .yesterday: return "Вчера"
        case .all: return "Все"
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
        case .settings: return "Настройки"
        case .windowBlurToggle: return "Прозрачное размытие фона окна"
        case .hideTitleOnThumbnails: return "Скрыть заголовок и источник на миниатюрах (видно при наведении)"
        case .notificationsToggle: return "Включить уведомления"
        case .hapticsToggle: return "Включить тактильную обратную связь"
        case .openArticleFirstToggle: return "Открывать статью до ИИ‑сводки"
        case .reduceOverlaysToggle: return "Уменьшать всплывающие окна в режиме чтения"
        case .interfaceLanguage: return "Язык интерфейса"
        case .language: return "Язык"
        case .reviewIntroduction: return "Посмотреть введение снова"
        case .settingsSaved: return "Настройки сохранены ✅"
        case .saveError: return "Ошибка при сохранении настроек"
        // Articles
        case .allArticles: return "Все статьи"
        case .readLater: return "Прочитать позже"
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
