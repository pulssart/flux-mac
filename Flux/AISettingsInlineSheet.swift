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
    @AppStorage("hideTitleOnThumbnails") private var hideTitleOnThumbnails: Bool = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("reader.openArticleInReaderFirst") private var openArticleInReaderFirst: Bool = true
    @AppStorage("reader.reduceOverlaysEnabled") private var reduceOverlaysEnabled: Bool = false
    @State private var selectedLanguage: SupportedLanguage = .english
    @State private var error: String?
    @State private var saveSuccess: String?

    private let lm = LocalizationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(lm.localizedString(.settings)).font(.title3).bold()
            Toggle(lm.localizedString(.windowBlurToggle), isOn: $windowBlurEnabled)
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            Toggle(lm.localizedString(.hideTitleOnThumbnails), isOn: $hideTitleOnThumbnails)
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            Toggle(lm.localizedString(.notificationsToggle), isOn: $notificationsEnabled)
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                .onChange(of: notificationsEnabled) { _, newValue in
                    if newValue {
                        feedService.requestNotificationPermissionIfNeeded()
                    }
                }
            #if os(macOS)
            Toggle(lm.localizedString(.hapticsToggle), isOn: $hapticsEnabled)
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            #endif
            Toggle(lm.localizedString(.openArticleFirstToggle), isOn: $openArticleInReaderFirst)
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            Toggle(lm.localizedString(.reduceOverlaysToggle), isOn: $reduceOverlaysEnabled)
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            Divider()
            
            // Sélection de la langue
            VStack(alignment: .leading, spacing: 8) {
                Text(lm.localizedString(.interfaceLanguage))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Picker(lm.localizedString(.language), selection: $selectedLanguage) {
                    ForEach(SupportedLanguage.allCases, id: \.self) { language in
                        HStack {
                            Text(language.flag)
                            Text(language.displayName)
                        }
                        .tag(language)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            
            Divider()
            
            // Section Import/Export
            ConfigurationImportExportView()
                .environment(feedService)
            
            Divider()
            
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
            #endif

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            if let saveSuccess = saveSuccess {
                Text(saveSuccess)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            HStack {
                Spacer()
                Button(lm.localizedString(.cancel)) { isPresented = false }
                Button(lm.localizedString(.save), action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .onAppear {
            // Charger la langue actuelle depuis les paramètres
            if let settings = try? modelContext.fetch(FetchDescriptor<Settings>()).first,
               let preferredLang = settings.preferredLangs.first {
                selectedLanguage = SupportedLanguage(rawValue: preferredLang) ?? .english
            } else {
                selectedLanguage = .english // Langue par défaut
            }
        }
        .onChange(of: selectedLanguage) { _, newLanguage in
            // Appliquer la langue instantanément
            LocalizationManager.shared.currentLanguage = newLanguage
        }
    }

    private func save() {
        do {
            // Sauvegarder la langue sélectionnée
            let settings = (try modelContext.fetch(FetchDescriptor<Settings>()).first) ?? Settings()
            settings.preferredLangs = [selectedLanguage.rawValue]
            
            // Sauvegarder les paramètres
            if ((try? modelContext.fetch(FetchDescriptor<Settings>()))?.isEmpty ?? true) {
                modelContext.insert(settings)
            }
            try modelContext.save()
            
            // Mettre à jour la langue dans le gestionnaire de localisation
            LocalizationManager.shared.currentLanguage = selectedLanguage
            
            // Afficher le message de succès
            saveSuccess = lm.localizedString(.settingsSaved)
            error = nil
            
            // Fermer la modale après un délai
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                isPresented = false
            }
            
        } catch {
            self.error = "\(lm.localizedString(.saveError)): \(error.localizedDescription)"
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
