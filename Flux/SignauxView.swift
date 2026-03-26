// SignauxView.swift
// Section éditoriale "Signaux" — marchés prédictifs Polymarket

import SwiftUI

struct SignauxView: View {
    @State private var polymarket = PolymarketService()
    @State private var selectedCategory: SignalCategory = .all
    @State private var hoveredEventId: String?
    @State private var selectedEvent: PolymarketEvent?
    @State private var shuffledTopIds: [String] = []
    @State private var currentLanguage = LocalizationManager.shared.currentLanguage
    @Environment(\.colorScheme) private var colorScheme
    private let lm = LocalizationManager.shared

    // Cached computed results — mis à jour seulement quand les inputs changent
    @State private var cachedFiltered: [PolymarketEvent] = []
    @State private var cachedFeatured: [PolymarketEvent] = []
    @State private var cachedRemaining: [PolymarketEvent] = []

    private let maxContentWidth: CGFloat = 1100

    /// Fond de page sur iPad en dark mode : gris foncé au lieu de noir pur
    private var pageBackgroundColor: Color {
        #if os(iOS)
        colorScheme == .dark ? Color(white: 0.11) : Color(.systemGroupedBackground)
        #else
        Color.clear
        #endif
    }

    /// Fond des cards : légèrement relevé par rapport au background sur iPad dark
    private var cardBackgroundColor: Color {
        #if os(iOS)
        colorScheme == .dark ? Color(white: 0.16) : Color(.systemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    /// Events filtrés par la catégorie sélectionnée
    private var heroEvent: PolymarketEvent? { cachedFeatured.first }
    private var spotlightEvents: [PolymarketEvent] { Array(cachedFeatured.dropFirst().prefix(2)) }

    private func recomputeCache() {
        let filtered: [PolymarketEvent]
        if selectedCategory == .all {
            filtered = polymarket.events
        } else {
            filtered = polymarket.events.filter { selectedCategory.matches($0) }
        }

        let filteredIds = Set(filtered.map { $0.id })
        var featuredResult = shuffledTopIds
            .filter { filteredIds.contains($0) }
            .compactMap { id in filtered.first { $0.id == id } }
            .prefix(3)
        if featuredResult.count < 3 {
            let picked = Set(featuredResult.map { $0.id })
            let extra = filtered.filter { !picked.contains($0.id) }.prefix(3 - featuredResult.count)
            featuredResult = (featuredResult + Array(extra)).prefix(3)
        }
        let featured = Array(featuredResult)
        let featuredIds = Set(featured.map { $0.id })

        cachedFiltered = filtered
        cachedFeatured = featured
        cachedRemaining = filtered.filter { !featuredIds.contains($0.id) }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                categoryPicker
                    .padding(.top, 12)

                if polymarket.isLoading && polymarket.events.isEmpty {
                    loadingView
                        .padding(.top, 60)
                } else if let error = polymarket.lastError, polymarket.events.isEmpty {
                    errorView(error)
                        .padding(.top, 60)
                } else if cachedFiltered.isEmpty {
                    emptyFilterView
                        .padding(.top, 60)
                } else {
                    // Hero
                    if let hero = heroEvent {
                        heroCard(hero)
                            .padding(.top, 24)
                    }

                    // À la une
                    if !spotlightEvents.isEmpty {
                        sectionHeader(lm.localizedString(.signalsFeatured), subtitle: lm.localizedString(.signalsFeaturedSubtitle))
                            .padding(.top, 32)
                        spotlightRow
                            .padding(.top, 12)
                    }

                    // Tous les signaux
                    if !cachedRemaining.isEmpty {
                        sectionHeader(lm.localizedString(.signalsAll), subtitle: lm.localizedString(.signalsAllSubtitle))
                            .padding(.top, 36)
                        allSignalsGrid
                            .padding(.top, 12)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 48)
            .frame(maxWidth: maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(pageBackgroundColor)
        .sheet(item: $selectedEvent) { event in
            SignalDetailSheet(event: event)
                .environment(polymarket)
                #if os(macOS)
                .frame(minWidth: 680, idealWidth: 760, minHeight: 560, idealHeight: 680)
                .toolbarVisibility(.hidden, for: .windowToolbar)
                #endif
        }
        .task {
            polymarket.fetchEvents()
        }
        .onChange(of: polymarket.events) { _, events in
            if shuffledTopIds.isEmpty, !events.isEmpty {
                shuffledTopIds = Array(events.prefix(50)).shuffled().map { $0.id }
            }
            recomputeCache()
        }
        .onChange(of: shuffledTopIds) { _, _ in
            recomputeCache()
        }
        .onChange(of: selectedCategory) { _, _ in
            recomputeCache()
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { notification in
            currentLanguage = notification.object as? SupportedLanguage ?? lm.currentLanguage
        }
    }

    // MARK: - Open event

    private func openEvent(_ event: PolymarketEvent) {
        selectedEvent = event
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(lm.localizedString(.signals))
                    .font(.system(size: 32, weight: .bold))
                if polymarket.isLoading && !polymarket.events.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                if let date = polymarket.lastFetchedAt {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text(lm.localizedString(.signalsUpdatedAt))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        + Text(date, style: .relative)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text(lm.localizedString(.signalsIntro))
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SignalCategory.allCases) { category in
                    categoryChip(category)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func categoryChip(_ category: SignalCategory) -> some View {
        let isSelected = selectedCategory == category
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = category
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: category.icon)
                    .font(.system(size: 11))
                Text(category.displayName)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06))
            )
            .foregroundStyle(isSelected ? Color.accentColor : .primary.opacity(0.6))
            .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Hero Card (layout horizontal : image gauche, contenu droite)

    private func heroCard(_ event: PolymarketEvent) -> some View {
        let isHovered = hoveredEventId == event.id

        return HStack(spacing: 0) {
            // Image à gauche (moitié exacte)
            GeometryReader { geo in
                Group {
                    if let imageURL = event.imageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                            default:
                                heroImagePlaceholder
                                    .frame(width: geo.size.width, height: geo.size.height)
                            }
                        }
                    } else {
                        heroImagePlaceholder
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16))

            // Contenu à droite (moitié)
            VStack(alignment: .leading, spacing: 14) {
                eventTagsRow(event)

                Text(event.title)
                    .font(.title.weight(.bold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !event.description.isEmpty {
                    Text(event.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if event.isBinary {
                    binaryOutcomeBar(event)
                } else {
                    multiOutcomeList(event, maxShown: 5)
                }

                eventFooter(event)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minHeight: 360)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackgroundColor)
                .shadow(color: .black.opacity(isHovered ? 0.12 : 0.06), radius: isHovered ? 16 : 8, y: isHovered ? 6 : 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(isHovered ? 0.12 : 0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { openEvent(event) }
        .scaleEffect(isHovered ? 1.005 : 1.0)
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            hoveredEventId = hovering ? event.id : nil
        }
    }

    private var heroImagePlaceholder: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.08))
            .overlay {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary.opacity(0.3))
            }
    }

    // MARK: - Spotlight Row (2 colonnes)

    private var spotlightRow: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(spotlightEvents) { event in
                spotlightCard(event)
            }
        }
    }

    private func spotlightCard(_ event: PolymarketEvent) -> some View {
        let isHovered = hoveredEventId == event.id

        return VStack(alignment: .leading, spacing: 0) {
            if let imageURL = event.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 200)
                            .clipped()
                    default:
                        Rectangle()
                            .fill(Color.secondary.opacity(0.06))
                            .frame(height: 200)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
            }

            VStack(alignment: .leading, spacing: 10) {
                eventTagsRow(event)

                Text(event.title)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !event.description.isEmpty {
                    Text(event.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .lineSpacing(2)
                }

                if event.isBinary {
                    binaryOutcomeBar(event)
                } else {
                    multiOutcomeList(event, maxShown: 3)
                }

                Spacer(minLength: 0)

                eventFooter(event)
            }
            .padding(18)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBackgroundColor)
                .shadow(color: .black.opacity(isHovered ? 0.10 : 0.05), radius: isHovered ? 10 : 5, y: isHovered ? 4 : 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(isHovered ? 0.12 : 0.06), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { openEvent(event) }
        .scaleEffect(isHovered ? 1.005 : 1.0)
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            hoveredEventId = hovering ? event.id : nil
        }
    }

    // MARK: - All Signals Grid (3 colonnes)

    private var allSignalsGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14),
        ]

        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(cachedRemaining) { event in
                CompactSignalCard(event: event, onTap: { openEvent(event) })
            }
        }
    }

    // MARK: - Outcome Components

    /// Barre binaire Oui/Non pour un événement à marché unique
    private func binaryOutcomeBar(_ event: PolymarketEvent) -> some View {
        let pct = event.leadMarket?.yesPercentage ?? 50
        let change = event.leadMarket?.dailyChange

        return VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Text(lm.localizedString(.signalsYes))
                        .font(.body.weight(.semibold))
                    Text("\(pct)%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(percentageColor(pct))
                    if let change {
                        dailyChangeBadge(change)
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("\(100 - pct)%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(percentageColor(100 - pct))
                    Text(lm.localizedString(.signalsNo))
                        .font(.body.weight(.semibold))
                }
            }

            // Barre de probabilité
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(percentageColor(pct).opacity(0.7))
                        .frame(width: max(proxy.size.width * CGFloat(pct) / 100 - 1, 0))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                }
            }
            .frame(height: 8)
        }
    }

    /// Liste multi-outcomes (ex: "Qui sera le prochain président ?")
    private func multiOutcomeList(_ event: PolymarketEvent, maxShown: Int) -> some View {
        let outcomes = event.topOutcomes
        let shown = Array(outcomes.prefix(maxShown))
        let remaining = outcomes.count - maxShown

        return VStack(spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, outcome in
                HStack(spacing: 8) {
                    Text("\(index + 1).")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, alignment: .trailing)
                    Text(outcome.name)
                        .font(.body)
                        .lineLimit(1)
                    Spacer()
                    Text("\(outcome.percentage)%")
                        .font(.body.weight(.bold).monospacedDigit())
                        .foregroundStyle(percentageColor(outcome.percentage))
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(index == 0 ? percentageColor(outcome.percentage).opacity(0.06) : Color.clear)
                )
            }
            if remaining > 0 {
                Text("+\(remaining) autres options")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 28)
            }
        }
    }

    // MARK: - Shared Components

    private func eventTagsRow(_ event: PolymarketEvent) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(event.tags.prefix(3)), id: \.self) { tag in
                Text(tag.capitalized)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.08)))
            }
        }
    }

    private func eventFooter(_ event: PolymarketEvent) -> some View {
        HStack(spacing: 16) {
            Label(event.formattedVolume, systemImage: "chart.bar")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if event.commentCount > 0 {
                Label("\(event.commentCount)", systemImage: "bubble.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let endDate = event.endDate {
                Label {
                    Text(endDate, style: .date)
                        .font(.footnote)
                } icon: {
                    Image(systemName: "calendar")
                        .font(.footnote)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func dailyChangeBadge(_ change: Int) -> some View {
        let isPositive = change > 0
        return Text("\(isPositive ? "+" : "")\(change)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(isPositive ? .green : .red)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isPositive ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
            )
    }

    private func percentageColor(_ pct: Int) -> Color {
        if pct >= 70 { return .green }
        if pct >= 40 { return .orange }
        return .red
    }

    // MARK: - Loading & Error

    private var emptyFilterView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(lm.localizedString(.signalsNoResult, selectedCategory.displayName))
                .font(.headline)
            Text(lm.localizedString(.signalsTryOtherCategory))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(lm.localizedString(.signalsLoading))
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)
            Text(lm.localizedString(.signalsLoadError))
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(lm.localizedString(.signalsRetry)) {
                polymarket.fetchEvents()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Compact Signal Card

private struct CompactSignalCard: View {
    let event: PolymarketEvent
    let onTap: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    private let lm = LocalizationManager.shared

    private var cardBackground: Color {
        #if os(iOS)
        colorScheme == .dark ? Color(white: 0.16) : Color(.systemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let imageURL = event.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        default:
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                                .frame(width: 44, height: 44)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let tag = event.primaryTag {
                        Text(tag.capitalized)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                    Text(event.formattedVolume)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }

            Text(event.title)
                .font(.body.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if event.isBinary {
                compactBinaryBar
            } else {
                compactOutcomeList
            }

            Spacer(minLength: 0)

            if let endDate = event.endDate {
                Text(lm.localizedString(.signalsEndDate, endDate.formatted(date: .abbreviated, time: .omitted)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackground)
                .shadow(color: .black.opacity(isHovered ? 0.09 : 0.04), radius: isHovered ? 8 : 4, y: isHovered ? 3 : 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(isHovered ? 0.12 : 0.06), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { onTap() }
        .scaleEffect(isHovered ? 1.008 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var compactBinaryBar: some View {
        let pct = event.leadMarket?.yesPercentage ?? 50
        return HStack(spacing: 0) {
            Text("\(lm.localizedString(.signalsYes)) \(pct)%")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(pctColor(pct))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 7).padding(.horizontal, 10)
                .background(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6)
                    .fill(pctColor(pct).opacity(0.08)))
            Text("\(lm.localizedString(.signalsNo)) \(100 - pct)%")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.vertical, 7).padding(.horizontal, 10)
                .background(UnevenRoundedRectangle(bottomTrailingRadius: 6, topTrailingRadius: 6)
                    .fill(Color.secondary.opacity(0.06)))
        }
    }

    private var compactOutcomeList: some View {
        let outcomes = Array(event.topOutcomes.prefix(3))
        return VStack(spacing: 4) {
            ForEach(Array(outcomes.enumerated()), id: \.offset) { _, outcome in
                HStack {
                    Text(outcome.name).font(.subheadline).lineLimit(1)
                    Spacer()
                    Text("\(outcome.percentage)%")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(pctColor(outcome.percentage))
                }
                .padding(.vertical, 2)
            }
            if event.topOutcomes.count > 3 {
                Text("+\(event.topOutcomes.count - 3) autres")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func pctColor(_ pct: Int) -> Color {
        if pct >= 70 { return .green }
        if pct >= 40 { return .orange }
        return .red
    }
}

// MARK: - Signal Detail Sheet

private struct SignalDetailSheet: View {
    let event: PolymarketEvent
    @Environment(\.dismiss) private var dismiss
    @Environment(PolymarketService.self) private var service
    private let lm = LocalizationManager.shared

    @State private var currentLanguage = LocalizationManager.shared.currentLanguage
    @State private var isCommentsExpanded = false
    @State private var comments: [PolymarketComment] = []
    @State private var isLoadingComments = false

    private static let endDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let commentDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)

                Spacer()

                if let tag = event.primaryTag {
                    Text(tag.capitalized)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.1)))
                }

                Button(action: {
                    #if os(macOS)
                    NSWorkspace.shared.open(event.polymarketURL)
                    #elseif os(iOS)
                    UIApplication.shared.open(event.polymarketURL)
                    #endif
                }) {
                    Label("Polymarket", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {

                    // Image + Titre
                    HStack(alignment: .top, spacing: 16) {
                        if let imgURL = event.imageURL {
                            AsyncImage(url: imgURL) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                default:
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.secondary.opacity(0.1))
                                        .frame(width: 72, height: 72)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(event.title)
                                .font(.title2.weight(.bold))
                                .fixedSize(horizontal: false, vertical: true)
                            if let end = event.endDate {
                                Label(lm.localizedString(.signalsResolution, Self.endDateFormatter.string(from: end)), systemImage: "calendar")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Description
                    if !event.description.isEmpty {
                        Text(event.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Stats
                    HStack(spacing: 0) {
                        statCell(label: lm.localizedString(.signalsVolume), value: event.formattedVolume, icon: "chart.bar.fill")
                        Divider().frame(height: 44)
                        statCell(label: lm.localizedString(.signalsLiquidity), value: formattedLiquidity, icon: "drop.fill")
                        Divider().frame(height: 44)
                        statCell(label: lm.localizedString(.signalsComments), value: "\(event.commentCount)", icon: "bubble.left.fill")
                        if event.competitive > 0 {
                            Divider().frame(height: 44)
                            statCell(label: lm.localizedString(.signalsCompetitiveness), value: "\(Int(event.competitive * 100))%", icon: "bolt.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))

                    // Marchés
                    VStack(alignment: .leading, spacing: 12) {
                        Text(event.isBinary ? lm.localizedString(.signalsProbability) : lm.localizedString(.signalsMarkets))
                            .font(.title3.weight(.semibold))

                        ForEach(event.markets.sorted { $0.yesPercentage > $1.yesPercentage }) { market in
                            marketRow(market)
                        }
                    }

                    // Commentaires
                    if event.commentCount > 0 {
                        VStack(alignment: .leading, spacing: 0) {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isCommentsExpanded.toggle()
                                }
                                if isCommentsExpanded && comments.isEmpty {
                                    Task { await loadComments() }
                                }
                            }) {
                                HStack {
                                    Label("\(lm.localizedString(.signalsComments)) (\(event.commentCount))", systemImage: "bubble.left.fill")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Group {
                                        if isLoadingComments {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Image(systemName: isCommentsExpanded ? "chevron.up" : "chevron.down")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            if isCommentsExpanded {
                                VStack(alignment: .leading, spacing: 10) {
                                    if comments.isEmpty && !isLoadingComments {
                                        Text(lm.localizedString(.signalsNoComments))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 12)
                                    } else {
                                        ForEach(comments) { comment in
                                            commentRow(comment)
                                        }
                                    }
                                }
                                .padding(.top, 12)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .task(id: event.id) {
            // Preload si on revient sur la même sheet
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { notification in
            currentLanguage = notification.object as? SupportedLanguage ?? lm.currentLanguage
        }
    }

    private func loadComments() async {
        isLoadingComments = true
        defer { isLoadingComments = false }
        comments = await service.fetchComments(for: event.id)
    }

    private func commentRow(_ comment: PolymarketComment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(comment.author)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let date = comment.createdAt {
                    Text(Self.commentDateFormatter.localizedString(for: date, relativeTo: Date()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(comment.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
    }

    // MARK: - Sous-vues

    private func statCell(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func marketRow(_ market: PolymarketMarket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(event.isBinary ? lm.localizedString(.signalsYes) : (market.groupItemTitle.isEmpty ? market.question : market.groupItemTitle))
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Text("\(market.yesPercentage)%")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(probabilityColor(market.yesPercentage))
                    if let change = market.dailyChange {
                        Text(change > 0 ? "+\(change)pt" : "\(change)pt")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(change > 0 ? .green : .red)
                    }
                }
            }

            // Barre de probabilité
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(probabilityColor(market.yesPercentage))
                        .frame(width: geo.size.width * CGFloat(market.yesPercentage) / 100, height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }

    private func probabilityColor(_ pct: Int) -> Color {
        switch pct {
        case 70...: return .green
        case 40..<70: return .orange
        default: return .red
        }
    }

    private var formattedLiquidity: String {
        let l = event.liquidity
        if l >= 1_000_000 { return String(format: "$%.1fM", l / 1_000_000) }
        if l >= 1_000 { return String(format: "$%.0fK", l / 1_000) }
        return String(format: "$%.0f", l)
    }
}
