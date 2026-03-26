// AISettingsInlineSheet.swift
// Inline settings sheet for language preferences.

import SwiftUI
import SwiftData

struct AISettingsInlineSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(FeedService.self) private var feedService
    @Binding var isPresented: Bool
    @Binding var showOnboarding: Bool
    @AppStorage("windowBlurEnabled") private var windowBlurEnabled: Bool = false
    @AppStorage("windowBlurTintOpacity") private var windowBlurTintOpacity: Double = 0.48
    @AppStorage("hideTitleOnThumbnails") private var hideTitleOnThumbnails: Bool = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("reader.alwaysOpenInBrowser") private var alwaysOpenInBrowser: Bool = false
    @AppStorage("badgeReadLaterEnabled") private var badgeReadLaterEnabled: Bool = true
    @AppStorage("filterAdsEnabled") private var filterAdsEnabled: Bool = false
    @State private var selectedLanguage: SupportedLanguage = .english
    @State private var error: String?
    #if os(macOS)
    @State private var showSafariExtensionSheet = false
    #endif

    private let lm = LocalizationManager.shared

    private var safariExtensionRowTitle: String {
        switch LocalizationManager.shared.currentLanguage {
        case .french:
            return "Extension Safari"
        default:
            return "Safari extension"
        }
    }

    private var blurTintTitle: String {
        switch LocalizationManager.shared.currentLanguage {
        case .french:
            return "Opacité de la teinte"
        default:
            return "Tint opacity"
        }
    }

    private var transparentLabel: String {
        switch LocalizationManager.shared.currentLanguage {
        case .french:
            return "Transparent"
        default:
            return "Transparent"
        }
    }

    private var opaqueLabel: String {
        switch LocalizationManager.shared.currentLanguage {
        case .french:
            return "Opaque"
        default:
            return "Opaque"
        }
    }

    private var blurTintPercentText: String {
        "\(Int(min(max(windowBlurTintOpacity, 0), 0.99) * 100))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(lm.localizedString(.settings)).font(.title3).bold()
            Toggle(lm.localizedString(.windowBlurToggle), isOn: $windowBlurEnabled)
                .toggleStyle(LeadingSwitchToggleStyle())
            if windowBlurEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(blurTintTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(blurTintPercentText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $windowBlurTintOpacity, in: 0...0.99)

                    HStack {
                        Text(transparentLabel)
                        Spacer()
                        Text(opaqueLabel)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.leading, 38)
                .padding(.top, -4)
                .padding(.bottom, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Toggle(lm.localizedString(.hideTitleOnThumbnails), isOn: $hideTitleOnThumbnails)
                .toggleStyle(LeadingSwitchToggleStyle())
            Toggle(lm.localizedString(.notificationsToggle), isOn: $notificationsEnabled)
                .toggleStyle(LeadingSwitchToggleStyle())
                .onChange(of: notificationsEnabled) { _, newValue in
                    if newValue {
                        feedService.requestNotificationPermissionIfNeeded()
                    }
                }
            #if os(macOS)
            Toggle(lm.localizedString(.hapticsToggle), isOn: $hapticsEnabled)
                .toggleStyle(LeadingSwitchToggleStyle())
            #endif
            Toggle(lm.localizedString(.alwaysOpenInBrowserToggle), isOn: $alwaysOpenInBrowser)
                .toggleStyle(LeadingSwitchToggleStyle())
            Toggle(lm.localizedString(.badgeReadLaterToggle), isOn: $badgeReadLaterEnabled)
                .toggleStyle(LeadingSwitchToggleStyle())
                .onChange(of: badgeReadLaterEnabled) { _, _ in
                    feedService.refreshAppBadge()
                }
            Toggle(lm.localizedString(.filterAdsToggle), isOn: $filterAdsEnabled)
                .toggleStyle(LeadingSwitchToggleStyle())
            Divider()
            
            // Sélection de la langue
            VStack(alignment: .leading, spacing: 8) {
                Text(lm.localizedString(.interfaceLanguage))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Picker(lm.localizedString(.language), selection: $selectedLanguage) {
                    ForEach(SupportedLanguage.allCases, id: \.self) { language in
                        Text("\(language.flag) \(language.displayName)")
                            .tag(language)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            
            Divider()
            
            // Section Import/Export
            ConfigurationImportExportView(language: selectedLanguage)
                .environment(feedService)
            
            Divider()
            
            // What's New
            Button(action: {
                isPresented = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .showWhatsNew, object: nil)
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "gift")
                        .foregroundStyle(.pink)
                    Text("What's New")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Relancer l'onboarding
            Button(action: {
                isPresented = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showOnboarding = true
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                    Text(lm.localizedString(.reviewIntroduction))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            // Ouvrir la fenêtre des logs
            #if os(macOS)
            Button(action: {
                LogsWindowController.shared.showWindow()
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "terminal")
                        .foregroundStyle(.green)
                    Text(lm.localizedString(.openLogsWindow))
                    Spacer()
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Button(action: {
                showSafariExtensionSheet = true
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "safari")
                        .foregroundStyle(.blue)
                    Text(safariExtensionRowTitle)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            #endif

            Button(action: {
                if let url = URL(string: "https://apps.apple.com/us/app/flux-rss/id6752223666?mt=12&action=write-review") {
                    #if os(macOS)
                    NSWorkspace.shared.open(url)
                    #endif
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text(lm.localizedString(.rateApp))
                    Spacer()
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            HStack {
                Spacer()
                Button(lm.localizedString(.cancel)) { isPresented = false }
                Button(lm.localizedString(.save), action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 520)
        #if os(macOS)
        .sheet(isPresented: $showSafariExtensionSheet) {
            SafariExtensionAnnouncementSheet(isPresented: $showSafariExtensionSheet)
        }
        #endif
        .onAppear {
            // Charger la langue actuelle depuis les paramètres
            if let settings = try? modelContext.fetch(FetchDescriptor<Settings>()).first {
                if let preferredLang = settings.preferredLangs.first {
                    selectedLanguage = SupportedLanguage(rawValue: preferredLang) ?? .english
                }
                filterAdsEnabled = settings.filterAdsEnabled ?? false
            } else {
                selectedLanguage = .english // Langue par défaut
            }
        }
        .onChange(of: selectedLanguage) { _, newLanguage in
            // Appliquer la langue instantanément
            LocalizationManager.shared.currentLanguage = newLanguage
        }
        .onChange(of: windowBlurEnabled) { _, newValue in
            if newValue == false {
                windowBlurTintOpacity = min(max(windowBlurTintOpacity, 0), 0.99)
            }
        }
    }

    private func save() {
        do {
            // Sauvegarder la langue sélectionnée
            let settings = (try modelContext.fetch(FetchDescriptor<Settings>()).first) ?? Settings()
            settings.preferredLangs = [selectedLanguage.rawValue]
            settings.filterAdsEnabled = filterAdsEnabled

            // Sauvegarder les paramètres
            if ((try? modelContext.fetch(FetchDescriptor<Settings>()))?.isEmpty ?? true) {
                modelContext.insert(settings)
            }
            try modelContext.save()
            
            // Mettre à jour la langue dans le gestionnaire de localisation
            LocalizationManager.shared.currentLanguage = selectedLanguage
            error = nil
            isPresented = false
            
        } catch {
            self.error = "\(lm.localizedString(.saveError)): \(error.localizedDescription)"
        }
    }
}

private struct LeadingSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: configuration.$isOn)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            configuration.label
            Spacer(minLength: 0)
        }
    }
}

// MARK: - AI Provider Configuration
// Made internal (removed 'private') so it’s visible to WebView 2.swift and others.
struct AIProviderConfig: Codable {
    let aiEnabled: Bool?
    let newsletterAudioEnabled: Bool?
}

#Preview {
    AISettingsInlineSheet(isPresented: .constant(true), showOnboarding: .constant(false))
        .environment(FeedService(context: try! ModelContext(ModelContainer(for: Feed.self))))
}
