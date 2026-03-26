import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

struct AddFeedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FeedService.self) private var feedService
    @Binding var newFeedURL: String
    @Binding var addError: String?
    let onAdd: (URL) async -> Void

    private let lm = LocalizationManager.shared
    @State private var discoveryQuery = ""
    @State private var selectedCategory: String?
    @State private var currentLanguage = LocalizationManager.shared.currentLanguage
    @FocusState private var isTextFieldFocused: Bool

    private let suggestionsManager = RSSFeedSuggestionsManager.shared

    private var filteredSuggestions: [RSSFeedSuggestion] {
        suggestionsManager.filtered(query: discoveryQuery, category: selectedCategory)
    }

    private var featuredSuggestions: [RSSFeedSuggestion] {
        suggestionsManager.popular()
    }

    private var categories: [String] {
        suggestionsManager.allCategories()
    }

    private var typedURLAlreadyAdded: Bool {
        guard let normalized = normalizedFeedKey(from: newFeedURL) else { return false }
        return existingFeedKeys.contains(normalized)
    }

    private var existingFeedKeys: Set<String> {
        var keys = Set<String>()
        for feed in feedService.feeds {
            keys.insert(normalizedFeedKey(for: feed.feedURL))
            if let siteURL = feed.siteURL {
                keys.insert(normalizedFeedKey(for: siteURL))
            }
        }
        return keys
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerView

            HStack(alignment: .top, spacing: 18) {
                manualColumn
                    .frame(width: 290)
                    .frame(maxHeight: .infinity, alignment: .top)

                discoveryColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #if os(macOS)
        .ignoresSafeArea(.container, edges: .top)
        .background(SheetWindowChromeConfigurator())
        #endif
        #if os(macOS)
        .frame(minWidth: 780, minHeight: 760, alignment: .topLeading)
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { notification in
            if let language = notification.object as? SupportedLanguage {
                currentLanguage = language
            } else {
                currentLanguage = lm.currentLanguage
            }
        }
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr(
                    "Ajoutez une source",
                    "Add a source",
                    "Añade una fuente",
                    "Quelle hinzufügen",
                    "Aggiungi una fonte",
                    "Adicionar uma fonte",
                    "ソースを追加",
                    "添加来源",
                    "소스 추가",
                    "Добавить источник"
                ))
                    .font(.system(size: 30, weight: .bold, design: .serif))

                Text(tr(
                    "Collez l’adresse d’un site ou ajoutez un flux fiable en un clic.",
                    "Paste a website address or add a trusted feed in one click.",
                    "Pega la dirección de un sitio o añade una fuente fiable en un clic.",
                    "Füge die Adresse einer Website ein oder ergänze eine zuverlässige Quelle mit einem Klick.",
                    "Incolla l’indirizzo di un sito o aggiungi una fonte affidabile con un clic.",
                    "Cole o endereço de um site ou adicione uma fonte confiável com um clique.",
                    "サイトのアドレスを貼り付けるか、信頼できるソースをワンクリックで追加します。",
                    "粘贴网站地址，或一键添加可靠的信息源。",
                    "사이트 주소를 붙여넣거나 신뢰할 수 있는 소스를 한 번에 추가하세요.",
                    "Вставьте адрес сайта или добавьте надежный источник одним нажатием."
                ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                isTextFieldFocused = false
                addError = nil
                dismiss()
            } label: {
                Label(tr(
                    "Fermer",
                    "Close",
                    "Cerrar",
                    "Schließen",
                    "Chiudi",
                    "Fechar",
                    "閉じる",
                    "关闭",
                    "닫기",
                    "Закрыть"
                ), systemImage: "xmark")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
        }
    }

    private var manualColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Label(tr(
                    "Ajouter avec une URL",
                    "Add with a URL",
                    "Añadir con una URL",
                    "Mit URL hinzufügen",
                    "Aggiungi con un URL",
                    "Adicionar com URL",
                    "URLで追加",
                    "通过 URL 添加",
                    "URL로 추가",
                    "Добавить по URL"
                ), systemImage: "link.badge.plus")
                    .font(.headline)

                Text(tr(
                    "Collez un site web, un blog ou un flux RSS. Flux tente ensuite de trouver le bon flux automatiquement.",
                    "Paste a website, blog, or RSS feed. Flux then tries to find the right feed automatically.",
                    "Pega un sitio web, un blog o una fuente RSS. Flux intentará encontrar automáticamente la fuente correcta.",
                    "Füge eine Website, einen Blog oder einen RSS-Feed ein. Flux versucht dann automatisch, den richtigen Feed zu finden.",
                    "Incolla un sito web, un blog o un feed RSS. Flux proverà quindi a trovare automaticamente il feed corretto.",
                    "Cole um site, um blog ou um feed RSS. O Flux tentará encontrar automaticamente o feed correto.",
                    "Webサイト、ブログ、またはRSSフィードを貼り付けてください。Flux が適切なフィードを自動的に見つけます。",
                    "粘贴网站、博客或 RSS 源。Flux 会自动尝试找到正确的订阅源。",
                    "웹사이트, 블로그 또는 RSS 피드를 붙여넣으세요. Flux가 알맞은 피드를 자동으로 찾습니다.",
                    "Вставьте сайт, блог или RSS-ленту. Flux попробует автоматически найти подходящую ленту."
                ))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TextField("https://…", text: $newFeedURL, prompt: Text("https://…"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                        .focused($isTextFieldFocused)

                Button {
                    Task { await addURLString(newFeedURL) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text(tr(
                            "Ajouter cette URL",
                            "Add this URL",
                            "Añadir esta URL",
                            "Diese URL hinzufügen",
                            "Aggiungi questo URL",
                            "Adicionar esta URL",
                            "このURLを追加",
                            "添加此 URL",
                            "이 URL 추가",
                            "Добавить этот URL"
                        ))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(newFeedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || typedURLAlreadyAdded)

                Text(tr(
                    "Astuce: vous pouvez coller l’URL d’un site entier, pas seulement le lien RSS.",
                    "Tip: you can paste a full website URL, not only the RSS link.",
                    "Consejo: puedes pegar la URL completa de un sitio, no solo el enlace RSS.",
                    "Tipp: Du kannst die komplette Website-URL einfügen, nicht nur den RSS-Link.",
                    "Suggerimento: puoi incollare l’URL completa di un sito, non solo il link RSS.",
                    "Dica: você pode colar a URL completa de um site, não apenas o link RSS.",
                    "ヒント: RSS リンクだけでなく、サイト全体の URL も貼り付けられます。",
                    "提示：你可以粘贴整个网站的 URL，不仅仅是 RSS 链接。",
                    "팁: RSS 링크뿐 아니라 사이트 전체 URL도 붙여넣을 수 있습니다.",
                    "Совет: можно вставить URL всего сайта, а не только RSS-ссылку."
                ))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if typedURLAlreadyAdded {
                    Label(tr(
                        "Ce flux est déjà dans vos sources.",
                        "This feed is already in your sources.",
                        "Esta fuente ya está en tus fuentes.",
                        "Dieser Feed ist bereits in deinen Quellen.",
                        "Questo feed è già tra le tue fonti.",
                        "Este feed já está nas suas fontes.",
                        "このフィードはすでに追加されています。",
                        "这个订阅源已经在你的来源列表中了。",
                        "이 피드는 이미 추가되어 있습니다.",
                        "Этот источник уже добавлен."
                    ), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if let err = addError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(tr(
                        "Sélection rapide",
                        "Quick picks",
                        "Selección rápida",
                        "Schnellauswahl",
                        "Selezione rapida",
                        "Seleção rápida",
                        "クイック追加",
                        "快速选择",
                        "빠른 선택",
                        "Быстрый выбор"
                    ))
                        .font(.headline)
                    Spacer()
                    Text(tr(
                        "1 clic",
                        "1 click",
                        "1 clic",
                        "1 Klick",
                        "1 clic",
                        "1 clique",
                        "1クリック",
                        "1 次点击",
                        "1회 클릭",
                        "1 клик"
                    ))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(featuredSuggestions) { suggestion in
                            let alreadyAdded = isSuggestionAlreadyAdded(suggestion)
                            CompactSuggestionRow(
                                suggestion: suggestion,
                                categoryTitle: categoryTitle(for: suggestion.category),
                                actionTitle: lm.localizedString(.add),
                                addedTitle: tr(
                                    "Déjà ajouté",
                                    "Already added",
                                    "Ya añadida",
                                    "Bereits hinzugefügt",
                                    "Già aggiunta",
                                    "Já adicionada",
                                    "追加済み",
                                    "已添加",
                                    "이미 추가됨",
                                    "Уже добавлено"
                                ),
                                isAdded: alreadyAdded
                            ) {
                                Task { await addSuggestion(suggestion) }
                            }
                            .disabled(alreadyAdded)
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var discoveryColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr(
                        "Suggestions prêtes à l’emploi",
                        "Ready-to-add suggestions",
                        "Sugerencias listas para usar",
                        "Sofort verfügbare Vorschläge",
                        "Suggerimenti pronti all’uso",
                        "Sugestões prontas para usar",
                        "すぐ使えるおすすめ",
                        "即用推荐",
                        "바로 추가할 추천",
                        "Готовые предложения"
                    ))
                        .font(.headline)
                    Text(tr(
                        "Filtrez par thème puis ajoutez une source immédiatement.",
                        "Filter by topic and add a source instantly.",
                        "Filtra por tema y añade una fuente al instante.",
                        "Nach Thema filtern und sofort eine Quelle hinzufügen.",
                        "Filtra per tema e aggiungi subito una fonte.",
                        "Filtre por tema e adicione uma fonte imediatamente.",
                        "テーマで絞り込み、すぐにソースを追加できます。",
                        "按主题筛选，并立即添加来源。",
                        "주제로 필터링하고 바로 소스를 추가하세요.",
                        "Фильтруйте по теме и сразу добавляйте источник."
                    ))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(sourcesCountLabel(filteredSuggestions.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField(tr(
                "Rechercher une source ou une catégorie",
                "Search a source or category",
                "Buscar una fuente o una categoría",
                "Quelle oder Kategorie suchen",
                "Cerca una fonte o una categoria",
                "Buscar uma fonte ou uma categoria",
                "ソースまたはカテゴリーを検索",
                "搜索来源或分类",
                "소스 또는 카테고리 검색",
                "Найти источник или категорию"
            ), text: $discoveryQuery)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    CategoryPill(
                        title: tr(
                            "Tout",
                            "All",
                            "Todas",
                            "Alle",
                            "Tutto",
                            "Todas",
                            "すべて",
                            "全部",
                            "전체",
                            "Все"
                        ),
                        isSelected: selectedCategory == nil
                    ) {
                        selectedCategory = nil
                    }

                    ForEach(categories, id: \.self) { category in
                        CategoryPill(
                            title: categoryTitle(for: category),
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            ScrollView {
                if filteredSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tr(
                            "Aucune suggestion trouvée",
                            "No suggestion found",
                            "No se encontró ninguna sugerencia",
                            "Keine Vorschläge gefunden",
                            "Nessun suggerimento trovato",
                            "Nenhuma sugestão encontrada",
                            "候補が見つかりません",
                            "未找到推荐",
                            "추천을 찾을 수 없습니다",
                            "Ничего не найдено"
                        ))
                            .font(.headline)
                        Text(tr(
                            "Essayez un autre mot-clé ou revenez à toutes les catégories.",
                            "Try another keyword or go back to all categories.",
                            "Prueba con otra palabra clave o vuelve a todas las categorías.",
                            "Versuche ein anderes Stichwort oder gehe zurück zu allen Kategorien.",
                            "Prova un’altra parola chiave oppure torna a tutte le categorie.",
                            "Tente outra palavra-chave ou volte para todas as categorias.",
                            "別のキーワードを試すか、すべてのカテゴリーに戻ってください。",
                            "请尝试其他关键词，或返回全部分类。",
                            "다른 키워드를 시도하거나 모든 카테고리로 돌아가세요.",
                            "Попробуйте другое ключевое слово или вернитесь ко всем категориям."
                        ))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach(filteredSuggestions) { suggestion in
                            let alreadyAdded = isSuggestionAlreadyAdded(suggestion)
                            SuggestionCard(
                                suggestion: suggestion,
                                categoryTitle: categoryTitle(for: suggestion.category),
                                actionTitle: lm.localizedString(.add),
                                addedTitle: tr(
                                    "Déjà ajouté",
                                    "Already added",
                                    "Ya añadida",
                                    "Bereits hinzugefügt",
                                    "Già aggiunta",
                                    "Já adicionada",
                                    "追加済み",
                                    "已添加",
                                    "이미 추가됨",
                                    "Уже добавлено"
                                ),
                                isAdded: alreadyAdded
                            ) {
                                Task { await addSuggestion(suggestion) }
                            }
                            .disabled(alreadyAdded)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @MainActor
    private func addSuggestion(_ suggestion: RSSFeedSuggestion) async {
        guard !isSuggestionAlreadyAdded(suggestion) else { return }
        newFeedURL = suggestion.url
        isTextFieldFocused = false
        await addURLString(suggestion.url)
    }

    @MainActor
    private func addURLString(_ rawURLString: String) async {
        var urlString = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        if urlString.hasPrefix("http://") {
            urlString = "https://" + urlString.dropFirst("http://".count)
        }
        if !urlString.isEmpty && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }

        guard let url = URL(string: urlString), url.scheme == "https" else {
            addError = tr(
                "Seuls les flux HTTPS sont acceptés",
                "Only HTTPS feeds are accepted",
                "Solo se aceptan fuentes HTTPS",
                "Es werden nur HTTPS-Feeds akzeptiert",
                "Sono accettati solo feed HTTPS",
                "Apenas feeds HTTPS são aceitos",
                "HTTPS フィードのみ利用できます",
                "仅接受 HTTPS 订阅源",
                "HTTPS 피드만 허용됩니다",
                "Поддерживаются только HTTPS-ленты"
            )
            return
        }

        addError = nil
        Task {
            await onAdd(url)
        }
    }

    private func isSuggestionAlreadyAdded(_ suggestion: RSSFeedSuggestion) -> Bool {
        if existingFeedKeys.contains(normalizedFeedKey(for: suggestion.url)) {
            return true
        }
        if let siteURL = suggestion.siteURL, existingFeedKeys.contains(normalizedFeedKey(for: siteURL)) {
            return true
        }
        return false
    }

    private func normalizedFeedKey(from rawURLString: String) -> String? {
        let trimmed = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var candidate = trimmed
        if !candidate.contains("://") {
            candidate = "https://" + candidate
        }
        return normalizedFeedKey(for: candidate)
    }

    private func normalizedFeedKey(for rawURLString: String) -> String {
        normalizedFeedKey(for: URL(string: rawURLString))
    }

    private func normalizedFeedKey(for url: URL?) -> String {
        guard let url else { return "" }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = (components?.host ?? "").lowercased()
        var path = components?.path ?? ""
        while path.hasSuffix("/") && path.count > 1 {
            path.removeLast()
        }
        return host + path
    }

    private func categoryTitle(for rawCategory: String) -> String {
        switch rawCategory {
        case "Engineering":
            return tr("Engineering", "Engineering", "Ingeniería", "Engineering", "Ingegneria", "Engenharia", "エンジニアリング", "工程", "엔지니어링", "Инженерия")
        case "Dev":
            return tr("Développement", "Development", "Desarrollo", "Entwicklung", "Sviluppo", "Desenvolvimento", "開発", "开发", "개발", "Разработка")
        case "AI":
            return tr("IA", "AI", "IA", "KI", "IA", "IA", "AI", "AI", "AI", "ИИ")
        case "Science":
            return tr("Science", "Science", "Ciencia", "Wissenschaft", "Scienza", "Ciência", "科学", "科学", "과학", "Наука")
        case "Apple":
            return "Apple"
        case "Swift":
            return "Swift"
        case "News":
            return tr("Actualités", "News", "Noticias", "Nachrichten", "Notizie", "Notícias", "ニュース", "新闻", "뉴스", "Новости")
        case "Gaming":
            return tr("Jeux vidéo", "Gaming", "Videojuegos", "Spiele", "Videogiochi", "Jogos", "ゲーム", "游戏", "게임", "Игры")
        case "France":
            return tr("France", "France", "Francia", "Frankreich", "Francia", "França", "フランス", "法国", "프랑스", "Франция")
        case "YouTube":
            return "YouTube"
        default:
            return rawCategory
        }
    }

    private func sourcesCountLabel(_ count: Int) -> String {
        switch currentLanguage {
        case .french:
            return "\(count) sources"
        case .english:
            return "\(count) sources"
        case .spanish:
            return "\(count) fuentes"
        case .german:
            return "\(count) Quellen"
        case .italian:
            return "\(count) fonti"
        case .portuguese:
            return "\(count) fontes"
        case .japanese:
            return "\(count) 件"
        case .chinese:
            return "\(count) 个来源"
        case .korean:
            return "\(count)개 소스"
        case .russian:
            return "\(count) источников"
        }
    }

    private func tr(
        _ french: String,
        _ english: String,
        _ spanish: String,
        _ german: String,
        _ italian: String,
        _ portuguese: String,
        _ japanese: String,
        _ chinese: String,
        _ korean: String,
        _ russian: String
    ) -> String {
        switch currentLanguage {
        case .french:
            return french
        case .english:
            return english
        case .spanish:
            return spanish
        case .german:
            return german
        case .italian:
            return italian
        case .portuguese:
            return portuguese
        case .japanese:
            return japanese
        case .chinese:
            return chinese
        case .korean:
            return korean
        case .russian:
            return russian
        }
    }
}

#if os(macOS)
private struct SheetWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            if #available(macOS 13.0, *) {
                window.titlebarSeparatorStyle = .none
            }
        }
    }
}
#endif

private struct CategoryPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(isSelected ? 0 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct CompactSuggestionRow: View {
    let suggestion: RSSFeedSuggestion
    let categoryTitle: String
    let actionTitle: String
    let addedTitle: String
    let isAdded: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SuggestionFaviconView(suggestion: suggestion, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(categoryTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Label(isAdded ? addedTitle : actionTitle, systemImage: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isAdded ? .green : .secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.06) : Color.primary.opacity(0.035))
            )
        }
        .buttonStyle(.plain)
        .opacity(isAdded ? 0.7 : 1)
        .onHover { isHovering = $0 }
    }
}

private struct SuggestionCard: View {
    let suggestion: RSSFeedSuggestion
    let categoryTitle: String
    let actionTitle: String
    let addedTitle: String
    let isAdded: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    SuggestionFaviconView(suggestion: suggestion, size: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(suggestion.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        Text(suggestion.hostLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                Text(categoryTitle.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06), in: Capsule())

                Text(suggestion.note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                HStack {
                    Text("RSS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Label(isAdded ? addedTitle : actionTitle, systemImage: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isAdded ? .green : .primary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(isHovering ? 0.12 : 0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(isHovering ? 0.08 : 0.03), radius: isHovering ? 14 : 8, y: isHovering ? 10 : 4)
            .scaleEffect(isHovering ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .opacity(isAdded ? 0.72 : 1)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.18), value: isHovering)
    }
}

private struct SuggestionFaviconView: View {
    let suggestion: RSSFeedSuggestion
    let size: CGFloat

    var body: some View {
        Group {
            if let faviconURL = suggestion.faviconURL {
                AsyncImage(url: faviconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var fallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                .fill(Color.primary.opacity(0.07))
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
