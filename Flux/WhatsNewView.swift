// WhatsNewView.swift
// What's New modal — shown once per version, re-accessible from Settings.

import SwiftUI

/// Current app version for the What's New screen.
/// Bump this value and update `whatsNewFeatures(for:)` when releasing a new version.
private let whatsNewVersion = "1.0.5"

/// Each feature displayed in the What's New modal.
private struct WhatsNewFeature: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
}

private func whatsNewTitle(for language: SupportedLanguage) -> String {
    switch language {
    case .french: return "Nouveautés"
    case .english: return "What's New"
    case .spanish: return "Novedades"
    case .german: return "Neu in dieser Version"
    case .italian: return "Novità"
    case .portuguese: return "Novidades"
    case .japanese: return "新機能"
    case .chinese: return "新内容"
    case .korean: return "새로운 기능"
    case .russian: return "Что нового"
    }
}

private func continueLabel(for language: SupportedLanguage) -> String {
    switch language {
    case .french: return "Continuer"
    case .english: return "Continue"
    case .spanish: return "Continuar"
    case .german: return "Fortfahren"
    case .italian: return "Continua"
    case .portuguese: return "Continuar"
    case .japanese: return "続ける"
    case .chinese: return "继续"
    case .korean: return "계속"
    case .russian: return "Продолжить"
    }
}

private func whatsNewFeatures(for language: SupportedLanguage) -> [WhatsNewFeature] {
    switch language {
    case .french:
        return [
            WhatsNewFeature(
                icon: "waveform.path.ecg",
                iconColor: .pink,
                title: "Nouvelle section Signaux",
                description: "Retrouvez les signaux majeurs de Polymarket dans un espace dédié. Les marchés prédictifs prennent désormais une vraie place dans l’actualité mondiale."
            ),
            WhatsNewFeature(
                icon: "sparkles.rectangle.stack",
                iconColor: .purple,
                title: "Nouveau lecteur de résumés IA",
                description: "Une nouvelle modale rend la lecture des résumés générés par IA plus claire, plus agréable et plus rapide à parcourir."
            ),
            WhatsNewFeature(
                icon: "play.rectangle",
                iconColor: .red,
                title: "Nouvelle modale pour YouTube",
                description: "Les vidéos YouTube profitent maintenant d’une présentation dédiée, pensée pour une consultation plus confortable."
            ),
            WhatsNewFeature(
                icon: "ipad.landscape",
                iconColor: .blue,
                title: "Flux arrive sur iPad",
                description: "L’app est maintenant disponible sur iPad, avec une expérience adaptée au grand écran pour lire vos flux plus confortablement."
            ),
            WhatsNewFeature(
                icon: "checkmark.circle.badge.xmark",
                iconColor: .green,
                title: "Badges lu / non lu",
                description: "Les cartes affichent désormais un repère visuel pour distinguer plus rapidement les articles lus de ceux qu’il vous reste à découvrir."
            ),
            WhatsNewFeature(
                icon: "hare.fill",
                iconColor: .orange,
                title: "Performances fortement améliorées",
                description: "L’application a été optimisée en profondeur pour offrir une navigation plus fluide, des vues plus réactives et un chargement globalement plus rapide."
            ),
            WhatsNewFeature(
                icon: "line.3.horizontal.decrease.circle",
                iconColor: .mint,
                title: "Filtre publicité / promotion",
                description: "Une nouvelle option permet de masquer les articles à caractère publicitaire ou promotionnel pour garder un flux plus propre."
            ),
            WhatsNewFeature(
                icon: "music.note",
                iconColor: .indigo,
                title: "Meilleure lecture Apple Music",
                description: "La prise en charge des contenus Apple Music a été améliorée pour une lecture plus fiable et plus agréable."
            ),
            WhatsNewFeature(
                icon: "icloud",
                iconColor: .cyan,
                title: "Synchronisation iCloud",
                description: "Vos flux, dossiers et réglages compatibles peuvent maintenant se synchroniser entre Mac, iPad et iPhone."
            ),
        ]
    case .english:
        return [
            WhatsNewFeature(
                icon: "waveform.path.ecg",
                iconColor: .pink,
                title: "New Signals section",
                description: "Follow Polymarket’s main signals in a dedicated space. Prediction markets now play a real role in global news."
            ),
            WhatsNewFeature(
                icon: "sparkles.rectangle.stack",
                iconColor: .purple,
                title: "New AI summary reader",
                description: "A redesigned modal makes AI summaries clearer, easier to read, and faster to browse."
            ),
            WhatsNewFeature(
                icon: "play.rectangle",
                iconColor: .red,
                title: "New YouTube modal",
                description: "YouTube videos now open in a dedicated view designed for a cleaner and more comfortable experience."
            ),
            WhatsNewFeature(
                icon: "ipad.landscape",
                iconColor: .blue,
                title: "Flux is now on iPad",
                description: "Flux is now available on iPad with an experience tailored to the larger screen."
            ),
            WhatsNewFeature(
                icon: "checkmark.circle.badge.xmark",
                iconColor: .green,
                title: "Read / unread badges",
                description: "Cards now show a visual badge so you can instantly tell which articles you have already read."
            ),
            WhatsNewFeature(
                icon: "hare.fill",
                iconColor: .orange,
                title: "Major performance improvements",
                description: "The app has been heavily optimized for smoother navigation, faster loading, and a more responsive overall experience."
            ),
            WhatsNewFeature(
                icon: "line.3.horizontal.decrease.circle",
                iconColor: .mint,
                title: "Ad / promotion filter",
                description: "A new option lets you hide promotional and advertising articles to keep your feed cleaner."
            ),
            WhatsNewFeature(
                icon: "music.note",
                iconColor: .indigo,
                title: "Better Apple Music playback",
                description: "Apple Music content is now handled more reliably for a smoother listening experience."
            ),
            WhatsNewFeature(
                icon: "icloud",
                iconColor: .cyan,
                title: "iCloud sync",
                description: "Your feeds, folders, and compatible settings can now sync between Mac, iPad, and iPhone."
            ),
        ]
    case .spanish:
        return [
            WhatsNewFeature(icon: "waveform.path.ecg", iconColor: .pink, title: "Nueva sección Señales", description: "Encuentra las principales señales de Polymarket en un espacio dedicado. Los mercados predictivos ahora forman parte real de la actualidad mundial."),
            WhatsNewFeature(icon: "sparkles.rectangle.stack", iconColor: .purple, title: "Nuevo lector de resúmenes con IA", description: "Una nueva ventana hace que los resúmenes generados por IA sean más claros, cómodos y rápidos de consultar."),
            WhatsNewFeature(icon: "play.rectangle", iconColor: .red, title: "Nueva ventana para YouTube", description: "Los vídeos de YouTube ahora se muestran en una vista dedicada, más cómoda y mejor organizada."),
            WhatsNewFeature(icon: "ipad.landscape", iconColor: .blue, title: "Flux llega al iPad", description: "Flux ya está disponible en iPad con una experiencia adaptada a la pantalla grande."),
            WhatsNewFeature(icon: "checkmark.circle.badge.xmark", iconColor: .green, title: "Insignias leído / no leído", description: "Las tarjetas muestran ahora un indicador visual para distinguir al instante los artículos leídos de los pendientes."),
            WhatsNewFeature(icon: "hare.fill", iconColor: .orange, title: "Gran mejora de rendimiento", description: "La app ha sido optimizada en profundidad para ofrecer una navegación más fluida y tiempos de carga más rápidos."),
            WhatsNewFeature(icon: "line.3.horizontal.decrease.circle", iconColor: .mint, title: "Filtro de publicidad / promoción", description: "Una nueva opción permite ocultar artículos publicitarios o promocionales para mantener un feed más limpio."),
            WhatsNewFeature(icon: "music.note", iconColor: .indigo, title: "Mejor lectura de Apple Music", description: "La gestión del contenido de Apple Music se ha mejorado para una experiencia más fiable y agradable."),
            WhatsNewFeature(icon: "icloud", iconColor: .cyan, title: "Sincronización con iCloud", description: "Tus feeds, carpetas y ajustes compatibles ahora pueden sincronizarse entre Mac, iPad y iPhone."),
        ]
    case .german:
        return [
            WhatsNewFeature(icon: "waveform.path.ecg", iconColor: .pink, title: "Neuer Bereich Signale", description: "Die wichtigsten Polymarket-Signale sind jetzt in einem eigenen Bereich gebündelt. Prognosemärkte gehören inzwischen klar zum Weltgeschehen."),
            WhatsNewFeature(icon: "sparkles.rectangle.stack", iconColor: .purple, title: "Neuer KI-Zusammenfassungsleser", description: "Ein neues Fenster macht KI-Zusammenfassungen klarer, angenehmer und schneller lesbar."),
            WhatsNewFeature(icon: "play.rectangle", iconColor: .red, title: "Neues YouTube-Fenster", description: "YouTube-Videos werden jetzt in einer eigenen Ansicht geöffnet, die übersichtlicher und komfortabler ist."),
            WhatsNewFeature(icon: "ipad.landscape", iconColor: .blue, title: "Flux auf dem iPad", description: "Flux ist jetzt auch auf dem iPad verfügbar, mit einer für den größeren Bildschirm angepassten Erfahrung."),
            WhatsNewFeature(icon: "checkmark.circle.badge.xmark", iconColor: .green, title: "Gelesen / ungelesen-Badges", description: "Karten zeigen nun einen sichtbaren Status, damit gelesene und noch offene Artikel schneller erkennbar sind."),
            WhatsNewFeature(icon: "hare.fill", iconColor: .orange, title: "Deutlich bessere Leistung", description: "Die App wurde umfassend optimiert und reagiert jetzt flüssiger, schneller und insgesamt direkter."),
            WhatsNewFeature(icon: "line.3.horizontal.decrease.circle", iconColor: .mint, title: "Werbe- / Promotionsfilter", description: "Mit einer neuen Option lassen sich werbliche oder promotete Artikel ausblenden."),
            WhatsNewFeature(icon: "music.note", iconColor: .indigo, title: "Bessere Apple Music-Wiedergabe", description: "Apple Music-Inhalte werden jetzt zuverlässiger verarbeitet und angenehmer wiedergegeben."),
            WhatsNewFeature(icon: "icloud", iconColor: .cyan, title: "iCloud-Synchronisierung", description: "Feeds, Ordner und kompatible Einstellungen können jetzt zwischen Mac, iPad und iPhone synchronisiert werden."),
        ]
    case .italian:
        return [
            WhatsNewFeature(icon: "waveform.path.ecg", iconColor: .pink, title: "Nuova sezione Segnali", description: "Trova i principali segnali di Polymarket in uno spazio dedicato. I mercati predittivi fanno ormai parte dell’attualità globale."),
            WhatsNewFeature(icon: "sparkles.rectangle.stack", iconColor: .purple, title: "Nuovo lettore dei riassunti IA", description: "Una nuova finestra rende i riassunti generati dall’IA più chiari, leggibili e rapidi da consultare."),
            WhatsNewFeature(icon: "play.rectangle", iconColor: .red, title: "Nuova finestra per YouTube", description: "I video YouTube ora si aprono in una vista dedicata, più comoda e meglio organizzata."),
            WhatsNewFeature(icon: "ipad.landscape", iconColor: .blue, title: "Flux arriva su iPad", description: "Flux è ora disponibile su iPad con un’esperienza pensata per il grande schermo."),
            WhatsNewFeature(icon: "checkmark.circle.badge.xmark", iconColor: .green, title: "Badge letto / non letto", description: "Le card mostrano ora un indicatore visivo per distinguere più rapidamente gli articoli letti da quelli ancora da scoprire."),
            WhatsNewFeature(icon: "hare.fill", iconColor: .orange, title: "Prestazioni molto migliorate", description: "L’app è stata ottimizzata a fondo per offrire una navigazione più fluida e tempi di caricamento più rapidi."),
            WhatsNewFeature(icon: "line.3.horizontal.decrease.circle", iconColor: .mint, title: "Filtro pubblicità / promozioni", description: "Una nuova opzione permette di nascondere gli articoli pubblicitari o promozionali per mantenere il feed più pulito."),
            WhatsNewFeature(icon: "music.note", iconColor: .indigo, title: "Migliore lettura Apple Music", description: "La gestione dei contenuti Apple Music è stata migliorata per un’esperienza più affidabile e piacevole."),
            WhatsNewFeature(icon: "icloud", iconColor: .cyan, title: "Sincronizzazione iCloud", description: "Feed, cartelle e impostazioni compatibili ora possono sincronizzarsi tra Mac, iPad e iPhone."),
        ]
    case .portuguese:
        return [
            WhatsNewFeature(icon: "waveform.path.ecg", iconColor: .pink, title: "Nova seção Sinais", description: "Encontre os principais sinais do Polymarket em um espaço dedicado. Os mercados preditivos agora fazem parte real das notícias globais."),
            WhatsNewFeature(icon: "sparkles.rectangle.stack", iconColor: .purple, title: "Novo leitor de resumos com IA", description: "Uma nova janela torna os resumos gerados por IA mais claros, confortáveis e rápidos de consultar."),
            WhatsNewFeature(icon: "play.rectangle", iconColor: .red, title: "Nova janela para YouTube", description: "Os vídeos do YouTube agora abrem em uma visualização dedicada, mais organizada e agradável."),
            WhatsNewFeature(icon: "ipad.landscape", iconColor: .blue, title: "Flux agora no iPad", description: "Flux agora está disponível no iPad com uma experiência pensada para a tela maior."),
            WhatsNewFeature(icon: "checkmark.circle.badge.xmark", iconColor: .green, title: "Badges de lido / não lido", description: "Os cards agora mostram um indicador visual para diferenciar rapidamente os artigos já lidos dos que ainda faltam."),
            WhatsNewFeature(icon: "hare.fill", iconColor: .orange, title: "Grande melhoria de desempenho", description: "O app foi profundamente otimizado para ficar mais fluido, rápido e responsivo no uso diário."),
            WhatsNewFeature(icon: "line.3.horizontal.decrease.circle", iconColor: .mint, title: "Filtro de publicidade / promoção", description: "Uma nova opção permite esconder artigos promocionais ou publicitários para manter o feed mais limpo."),
            WhatsNewFeature(icon: "music.note", iconColor: .indigo, title: "Melhor reprodução do Apple Music", description: "O conteúdo do Apple Music agora é tratado com mais confiabilidade para uma experiência melhor."),
            WhatsNewFeature(icon: "icloud", iconColor: .cyan, title: "Sincronização com iCloud", description: "Seus feeds, pastas e ajustes compatíveis agora podem sincronizar entre Mac, iPad e iPhone."),
        ]
    case .japanese:
        return [
            WhatsNewFeature(icon: "waveform.path.ecg", iconColor: .pink, title: "新しい「シグナル」セクション", description: "Polymarketの主要シグナルを専用画面で確認できるようになりました。予測市場は世界のニュースの一部になりつつあります。"),
            WhatsNewFeature(icon: "sparkles.rectangle.stack", iconColor: .purple, title: "新しいAI要約リーダー", description: "AIが生成した要約を、より見やすく、読みやすく、すばやく確認できる新しいモーダルを追加しました。"),
            WhatsNewFeature(icon: "play.rectangle", iconColor: .red, title: "新しいYouTubeモーダル", description: "YouTube動画は、より快適に閲覧できる専用表示で開くようになりました。"),
            WhatsNewFeature(icon: "ipad.landscape", iconColor: .blue, title: "iPad版Flux登場", description: "FluxがiPadでも利用可能になり、大きな画面に合わせた快適な体験を提供します。"),
            WhatsNewFeature(icon: "checkmark.circle.badge.xmark", iconColor: .green, title: "既読 / 未読バッジ", description: "カードに視覚的なバッジが追加され、読んだ記事と未読の記事をすぐに見分けられます。"),
            WhatsNewFeature(icon: "hare.fill", iconColor: .orange, title: "大幅なパフォーマンス改善", description: "アプリ全体を最適化し、操作の滑らかさ、表示速度、反応の良さが大きく向上しました。"),
            WhatsNewFeature(icon: "line.3.horizontal.decrease.circle", iconColor: .mint, title: "広告 / プロモーション非表示", description: "広告やプロモーション記事を隠せる新しいオプションを追加し、より見やすいフィードを保てます。"),
            WhatsNewFeature(icon: "music.note", iconColor: .indigo, title: "Apple Music表示の改善", description: "Apple Musicコンテンツの読み込みと表示がより安定し、快適になりました。"),
            WhatsNewFeature(icon: "icloud", iconColor: .cyan, title: "iCloud同期", description: "フィード、フォルダ、対応設定をMac、iPad、iPhoneの間で同期できるようになりました。"),
        ]
    case .chinese:
        return [
            WhatsNewFeature(icon: "waveform.path.ecg", iconColor: .pink, title: "全新“信号”板块", description: "现在你可以在专属区域查看 Polymarket 的主要信号。预测市场已经逐渐成为全球新闻的一部分。"),
            WhatsNewFeature(icon: "sparkles.rectangle.stack", iconColor: .purple, title: "全新 AI 摘要阅读弹窗", description: "新的弹窗让 AI 摘要更清晰、更易读，也更方便快速浏览。"),
            WhatsNewFeature(icon: "play.rectangle", iconColor: .red, title: "全新 YouTube 弹窗", description: "YouTube 视频现在会在专属界面中打开，阅读和观看体验更舒适。"),
            WhatsNewFeature(icon: "ipad.landscape", iconColor: .blue, title: "Flux 登陆 iPad", description: "Flux 现已支持 iPad，并针对大屏幕做了专门优化。"),
            WhatsNewFeature(icon: "checkmark.circle.badge.xmark", iconColor: .green, title: "已读 / 未读徽章", description: "卡片现在会显示可视状态标记，帮助你更快区分已经读过和还没读的文章。"),
            WhatsNewFeature(icon: "hare.fill", iconColor: .orange, title: "性能大幅提升", description: "应用整体经过深度优化，带来更流畅的导航、更快的加载和更灵敏的响应。"),
            WhatsNewFeature(icon: "line.3.horizontal.decrease.circle", iconColor: .mint, title: "广告 / 推广过滤", description: "新增选项可隐藏广告或推广类文章，让你的信息流更干净。"),
            WhatsNewFeature(icon: "music.note", iconColor: .indigo, title: "Apple Music 体验改进", description: "Apple Music 内容的处理方式已优化，播放和阅读体验更稳定。"),
            WhatsNewFeature(icon: "icloud", iconColor: .cyan, title: "iCloud 同步", description: "你的订阅源、文件夹和兼容设置现在可以在 Mac、iPad 和 iPhone 之间同步。"),
        ]
    case .korean:
        return [
            WhatsNewFeature(icon: "waveform.path.ecg", iconColor: .pink, title: "새로운 시그널 섹션", description: "Polymarket의 주요 시그널을 전용 공간에서 확인할 수 있습니다. 예측 시장은 이제 세계 뉴스의 한 축이 되고 있습니다."),
            WhatsNewFeature(icon: "sparkles.rectangle.stack", iconColor: .purple, title: "새로운 AI 요약 리더", description: "새 모달로 AI 요약을 더 깔끔하고 편하게, 더 빠르게 읽을 수 있습니다."),
            WhatsNewFeature(icon: "play.rectangle", iconColor: .red, title: "새로운 YouTube 모달", description: "이제 YouTube 영상은 더 보기 좋고 편안한 전용 화면에서 열립니다."),
            WhatsNewFeature(icon: "ipad.landscape", iconColor: .blue, title: "iPad용 Flux 출시", description: "Flux를 이제 iPad에서도 사용할 수 있으며, 큰 화면에 맞춘 경험을 제공합니다."),
            WhatsNewFeature(icon: "checkmark.circle.badge.xmark", iconColor: .green, title: "읽음 / 안 읽음 배지", description: "카드에 시각 배지가 추가되어 읽은 기사와 아직 읽지 않은 기사를 더 빨리 구분할 수 있습니다."),
            WhatsNewFeature(icon: "hare.fill", iconColor: .orange, title: "대폭 향상된 성능", description: "앱 전반을 깊이 최적화해 더 부드러운 탐색, 더 빠른 로딩, 더 민감한 반응을 제공합니다."),
            WhatsNewFeature(icon: "line.3.horizontal.decrease.circle", iconColor: .mint, title: "광고 / 프로모션 필터", description: "광고성 또는 홍보성 기사를 숨길 수 있는 새 옵션으로 더 깔끔한 피드를 유지할 수 있습니다."),
            WhatsNewFeature(icon: "music.note", iconColor: .indigo, title: "Apple Music 처리 개선", description: "Apple Music 콘텐츠 지원이 개선되어 더 안정적이고 쾌적하게 이용할 수 있습니다."),
            WhatsNewFeature(icon: "icloud", iconColor: .cyan, title: "iCloud 동기화", description: "피드, 폴더, 호환 설정을 Mac, iPad, iPhone 사이에서 동기화할 수 있습니다."),
        ]
    case .russian:
        return [
            WhatsNewFeature(icon: "waveform.path.ecg", iconColor: .pink, title: "Новый раздел «Сигналы»", description: "Основные сигналы Polymarket теперь собраны в отдельном разделе. Рынки предсказаний становятся частью мировой новостной повестки."),
            WhatsNewFeature(icon: "sparkles.rectangle.stack", iconColor: .purple, title: "Новый просмотрщик ИИ-сводок", description: "Новая модальная панель делает ИИ-сводки более понятными, удобными и быстрыми для чтения."),
            WhatsNewFeature(icon: "play.rectangle", iconColor: .red, title: "Новая модальная панель для YouTube", description: "Видео YouTube теперь открываются в отдельном представлении, которое выглядит чище и удобнее."),
            WhatsNewFeature(icon: "ipad.landscape", iconColor: .blue, title: "Flux теперь на iPad", description: "Flux теперь доступен на iPad с интерфейсом, адаптированным под большой экран."),
            WhatsNewFeature(icon: "checkmark.circle.badge.xmark", iconColor: .green, title: "Значки прочитано / не прочитано", description: "Карточки теперь показывают заметный статус, чтобы быстрее отличать прочитанные материалы от новых."),
            WhatsNewFeature(icon: "hare.fill", iconColor: .orange, title: "Серьёзное улучшение производительности", description: "Приложение было глубоко оптимизировано: навигация стала плавнее, загрузка быстрее, а интерфейс отзывчивее."),
            WhatsNewFeature(icon: "line.3.horizontal.decrease.circle", iconColor: .mint, title: "Фильтр рекламы / промо", description: "Новая настройка позволяет скрывать рекламные и промо-материалы, чтобы лента оставалась чище."),
            WhatsNewFeature(icon: "music.note", iconColor: .indigo, title: "Улучшена работа с Apple Music", description: "Поддержка материалов Apple Music стала стабильнее и приятнее в использовании."),
            WhatsNewFeature(icon: "icloud", iconColor: .cyan, title: "Синхронизация через iCloud", description: "Ваши ленты, папки и совместимые настройки теперь могут синхронизироваться между Mac, iPad и iPhone."),
        ]
    }
}

// MARK: - Public helpers

/// Returns `true` the first time this version's What's New has not been seen yet.
/// After the first call that returns `true`, subsequent calls return `false` (the key is written when the sheet is dismissed).
func shouldShowWhatsNew() -> Bool {
    let seen = UserDefaults.standard.string(forKey: "whatsNew.lastSeenVersion") ?? ""
    return seen != whatsNewVersion
}

/// Marks the current version's What's New as seen.
func markWhatsNewAsSeen() {
    UserDefaults.standard.set(whatsNewVersion, forKey: "whatsNew.lastSeenVersion")
}

// MARK: - View

struct WhatsNewView: View {
    @Binding var isPresented: Bool
    @State private var appeared = false

    private let language = LocalizationManager.shared.currentLanguage

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(whatsNewTitle(for: language))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Version \(whatsNewVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            ScrollView {
                VStack(spacing: 20) {
                    ForEach(Array(whatsNewFeatures(for: language).enumerated()), id: \.element.id) { index, feature in
                        featureRow(feature)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 16)
                            .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.07), value: appeared)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
            }

            Button {
                markWhatsNewAsSeen()
                isPresented = false
            } label: {
                Text(continueLabel(for: language))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .frame(width: 420, height: 680)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                appeared = true
            }
        }
    }

    private func featureRow(_ feature: WhatsNewFeature) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(feature.iconColor.gradient)
                    .frame(width: 44, height: 44)
                Image(systemName: feature.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(feature.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
