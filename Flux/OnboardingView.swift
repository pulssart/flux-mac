// OnboardingView.swift
// Clean onboarding with native Liquid Glass

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage: Int = 0
    @Environment(FeedService.self) private var feedService
    private let lm = LocalizationManager.shared
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true

    private enum OnboardingStep {
        case info(OnboardingPage)
        case preferences
        case sources
    }

    private var steps: [OnboardingStep] {
        [
            .info(OnboardingPage(
                icon: "sparkles",
                iconColor: .purple,
                title: lm.localizedString(.onboardingWelcomeTitle),
                subtitle: lm.localizedString(.onboardingWelcomeSubtitle),
                description: lm.localizedString(.onboardingWelcomeDescription)
            )),
            .info(OnboardingPage(
                icon: "newspaper.fill",
                iconColor: .blue,
                title: lm.localizedString(.onboardingNewsWallTitle),
                subtitle: lm.localizedString(.onboardingNewsWallSubtitle),
                description: lm.localizedString(.onboardingNewsWallDescription)
            )),
            .info(OnboardingPage(
                icon: "wand.and.stars",
                iconColor: .orange,
                title: lm.localizedString(.onboardingAITitle),
                subtitle: lm.localizedString(.onboardingAISubtitle),
                description: lm.localizedString(.onboardingAIDescription)
            )),
            .preferences,
            .sources,
            .info(OnboardingPage(
                icon: "folder.fill",
                iconColor: .green,
                title: lm.localizedString(.onboardingOrganizationTitle),
                subtitle: lm.localizedString(.onboardingOrganizationSubtitle),
                description: lm.localizedString(.onboardingOrganizationDescription)
            )),
            .info(OnboardingPage(
                icon: "safari.fill",
                iconColor: .blue,
                title: lm.localizedString(.onboardingSafariTitle),
                subtitle: lm.localizedString(.onboardingSafariSubtitle),
                description: lm.localizedString(.onboardingSafariDescription)
            )),
            .info(OnboardingPage(
                icon: "plus.circle.fill",
                iconColor: .cyan,
                title: lm.localizedString(.onboardingStartTitle),
                subtitle: lm.localizedString(.onboardingStartSubtitle),
                description: lm.localizedString(.onboardingStartDescription)
            ))
        ]
    }

    private struct ProposedSource: Identifiable {
        let id: String
        let name: String
        let url: String
    }

    private let proposedSources: [ProposedSource] = [
        ProposedSource(id: "the-verge", name: "The Verge", url: "https://www.theverge.com/rss/index.xml"),
        ProposedSource(id: "techcrunch", name: "TechCrunch", url: "https://techcrunch.com/feed/"),
        ProposedSource(id: "sciencedaily", name: "ScienceDaily", url: "https://www.sciencedaily.com/rss/all.xml"),
        ProposedSource(id: "polygon", name: "Polygon", url: "https://www.polygon.com/rss/index.xml")
    ]

    @State private var selectedSourceIds: Set<String> = [
        "the-verge",
        "techcrunch",
        "sciencedaily",
        "polygon"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Content
            stepContent(step: steps[currentPage])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Bottom bar
            bottomBar
        }
        .frame(width: 520, height: 420)
        .background(.regularMaterial)
    }
    
    // MARK: - Page Content
    
    @ViewBuilder
    private func stepContent(step: OnboardingStep) -> some View {
        switch step {
        case .info(let page):
            pageContent(page: page)
        case .preferences:
            preferencesContent
        case .sources:
            sourcesContent
        }
    }

    private func pageContent(page: OnboardingPage) -> some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Icon
            Image(systemName: page.icon)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(page.iconColor.gradient)
                .frame(height: 70)
            
            // Text
            VStack(spacing: 8) {
                Text(page.title)
                    .font(.title.bold())
                
                Text(page.subtitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .padding(.top, 4)
            }
            
            Spacer()
            
            // Page indicators
            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 40)
    }

    private var sourcesContent: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checklist")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color.accentColor.gradient)
                .frame(height: 70)

            VStack(spacing: 8) {
                Text(lm.localizedString(.onboardingSourcesTitle))
                    .font(.title.bold())
                Text(lm.localizedString(.onboardingSourcesSubtitle))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(proposedSources) { source in
                    Toggle(isOn: Binding(
                        get: { selectedSourceIds.contains(source.id) },
                        set: { isSelected in
                            if isSelected { selectedSourceIds.insert(source.id) }
                            else { selectedSourceIds.remove(source.id) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                                .font(.body.weight(.medium))
                            Text(source.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    #if os(macOS)
                    .toggleStyle(.checkbox)
                    #endif
                }
            }
            .frame(maxWidth: 380, alignment: .leading)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private var preferencesContent: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color.accentColor.gradient)
                .frame(height: 70)

            VStack(spacing: 8) {
                Text(lm.localizedString(.onboardingPreferencesTitle))
                    .font(.title.bold())
                Text(lm.localizedString(.onboardingPreferencesSubtitle))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Toggle(lm.localizedString(.onboardingEnableNotifications), isOn: $notificationsEnabled)
                Toggle(lm.localizedString(.hapticsToggle), isOn: $hapticsEnabled)

                Divider()

                HStack {
                    Text(lm.localizedString(.interfaceLanguage))
                    Spacer()
                    Picker(lm.localizedString(.language), selection: Binding(
                        get: { lm.currentLanguage },
                        set: { lm.currentLanguage = $0 }
                    )) {
                        ForEach(SupportedLanguage.allCases, id: \.self) { language in
                            Text("\(language.flag) \(language.displayName)")
                                .tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180, alignment: .trailing)
                }
            }
            .frame(maxWidth: 380, alignment: .leading)
            .padding(.top, 8)
            .onChange(of: notificationsEnabled) { _, newValue in
                if newValue {
                    feedService.requestNotificationPermissionIfNeeded()
                }
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        HStack {
            // Skip
            if currentPage < steps.count - 1 {
                Button(lm.localizedString(.skip)) {
                    completeOnboarding()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                Spacer()
                    .frame(width: 60)
            }
            
            Spacer()
            
            // Next / Done
            Button(action: {
                if currentPage < steps.count - 1 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentPage += 1
                    }
                    #if os(macOS)
                    HapticFeedback.levelChange()
                    #endif
                } else {
                    #if os(macOS)
                    HapticFeedback.success()
                    #endif
                    completeOnboarding()
                }
            }) {
                Text(currentPage < steps.count - 1 ? lm.localizedString(.onboardingNext) : lm.localizedString(.onboardingStart))
                    .frame(width: 90)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial)
    }
    
    private func completeOnboarding() {
        addSelectedSources()
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        isPresented = false
    }

    private func addSelectedSources() {
        let selected = proposedSources.filter { selectedSourceIds.contains($0.id) }
        guard !selected.isEmpty else { return }
        Task {
            for source in selected {
                try? await feedService.addFeed(from: source.url)
            }
        }
    }
}

// MARK: - Model

private struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String
}

// MARK: - Preview

#Preview {
    OnboardingView(isPresented: .constant(true))
}
