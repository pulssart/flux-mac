// ConfigurationImportExportView.swift
// Vue pour l'import/export de configuration
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct ConfigurationImportExportView: View {
    @Environment(FeedService.self) private var feedService
    private let lm = LocalizationManager.shared
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isPreparingExport = false
    @State private var exportError: String?
    @State private var importError: String?
    @State private var successMessage: String?
    @State private var showingFilePicker = false
    @State private var importSummary: ImportSummary?
    @State private var exportDocument: ConfigurationDocument?
    @State private var showingDeleteAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // En-tête
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.blue)
                Text(lm.localizedString(.configuration))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            
            Divider()
            
            // Note d'information
            HStack {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(lm.localizedString(.configurationImportHint))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(4)
            
            // Boutons d'action
            HStack(spacing: 8) {
                // Bouton Export
                Button(action: exportConfiguration) {
                    HStack(spacing: 4) {
                        if isExporting || isPreparingExport {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text(lm.localizedString(.exportConfig))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.08))
                    .foregroundStyle(.blue)
                    .cornerRadius(6)
                }
                .disabled(isExporting || isImporting || isPreparingExport)
                .buttonStyle(.plain)
                
                // Bouton Import
                Button(action: { 
                    #if os(macOS)
                    openImportDialog()
                    #else
                    showingFilePicker = true
                    #endif
                }) {
                    HStack(spacing: 4) {
                        if isImporting {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text(lm.localizedString(.importConfig))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.08))
                    .foregroundStyle(.green)
                    .cornerRadius(6)
                }
                .disabled(isExporting || isImporting || isPreparingExport)
                .buttonStyle(.plain)
                
                // Bouton de suppression
                Button(action: { showingDeleteAlert = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                        Text(lm.localizedString(.deleteConfig))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.08))
                    .foregroundStyle(.red)
                    .cornerRadius(6)
                }
                .disabled(isExporting || isImporting || isPreparingExport)
                .buttonStyle(.plain)
                
                Spacer()
            }
            
            // Messages d'état
            if let error = exportError ?? importError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.red)
                    Spacer()
                    Button(action: { 
                        exportError = nil
                        importError = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            if let success = successMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(success)
                        .foregroundStyle(.green)
                    Spacer()
                    Button(action: { 
                        successMessage = nil
                        importSummary = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Résumé de l'import
            if let summary = importSummary {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text(lm.localizedString(.importSummary))
                            .font(.subheadline)
                            .bold()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if summary.importedFeeds > 0 {
                            Text("✓ \(summary.importedFeeds) \(lm.localizedString(.feedsImported))")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        if summary.importedFolders > 0 {
                            Text("✓ \(summary.importedFolders) \(lm.localizedString(.foldersImported))")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        if summary.skippedFeeds > 0 {
                            Text("⚠ \(summary.skippedFeeds) \(lm.localizedString(.feedsSkipped))")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if summary.skippedFolders > 0 {
                            Text("⚠ \(summary.skippedFolders) \(lm.localizedString(.foldersSkipped))")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Statistiques
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("\(feedService.feeds.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(lm.localizedString(.feeds))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 4) {
                    Text("\(feedService.folders.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(lm.localizedString(.foldersLabel))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                let youtubeCount = feedService.feeds.filter { feed in
                    let host = (feed.siteURL?.host ?? feed.feedURL.host ?? "").lowercased()
                    return host.contains("youtube.com") || host.contains("youtu.be")
                }.count
                
                if youtubeCount > 0 {
                    HStack(spacing: 4) {
                        Text("\(youtubeCount)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(lm.localizedString(.youtube))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(6)
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: UTType.json,
            defaultFilename: "flux-configuration-\(Date().formatted(.dateTime.year().month().day()))"
        ) { result in
            handleExportResult(result)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .alert(lm.localizedString(.deleteConfig), isPresented: $showingDeleteAlert) {
            Button(lm.localizedString(.cancel), role: .cancel) { }
            Button(lm.localizedString(.deleteConfig), role: .destructive) {
                deleteAllContent()
            }
        } message: {
            Text(lm.localizedString(.deleteConfigWarning))
        }
    }
    
    private func exportConfiguration() {
        exportError = nil
        successMessage = nil
        isPreparingExport = true
        
        Task {
            do {
                print("🔄 Starting export configuration...")
                
                // Faire l'export sur un thread de fond pour éviter les blocages
                let data = try await Task.detached {
                    try await feedService.exportConfiguration()
                }.value
                
                print("✅ Export completed, data size: \(data.count) bytes")
                
                await MainActor.run {
                    exportDocument = ConfigurationDocument(data: data)
                    isPreparingExport = false
                    isExporting = true
                    print("📁 File exporter dialog should now appear")
                }
            } catch {
                print("❌ Export failed: \(error)")
                await MainActor.run {
                    exportError = "Erreur lors de l'export : \(error.localizedDescription)"
                    isPreparingExport = false
                }
            }
        }
    }
    
    private func deleteAllContent() {
        exportError = nil
        importError = nil
        successMessage = nil
        importSummary = nil
        
        Task {
            do {
                print("🗑️ Starting deletion of all content...")
                
                try await feedService.deleteAllContent()
                
                await MainActor.run {
                    successMessage = "Tout le contenu a été supprimé avec succès"
                    print("✅ All content deleted successfully")
                    
                    // Effacer le message après 3 secondes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        successMessage = nil
                    }
                }
            } catch {
                print("❌ Failed to delete content: \(error)")
                await MainActor.run {
                    exportError = "Erreur lors de la suppression : \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func handleExportResult(_ result: Result<URL, Error>) {
        isExporting = false
        
        switch result {
        case .success(let url):
            successMessage = "Configuration exportée avec succès vers \(url.lastPathComponent)"
            // Effacer le message après 3 secondes
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                successMessage = nil
            }
        case .failure(let error):
            exportError = "Erreur lors de la sauvegarde : \(error.localizedDescription)"
        }
    }
    
    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            Task {
                await importConfiguration(from: url)
            }
        case .failure(let error):
            importError = "Erreur lors de la sélection du fichier : \(error.localizedDescription)"
        }
    }
    
    private func importConfiguration(from url: URL) async {
        importError = nil
        successMessage = nil
        importSummary = nil
        isImporting = true
        
        // Accéder à la ressource avec sécurité
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            print("📥 Starting import from: \(url.lastPathComponent)")
            print("🔐 Security scoped access: \(hasAccess)")
            
            let data = try Data(contentsOf: url)
            print("📄 File loaded: \(data.count) bytes")
            
            let summary = try await feedService.importConfiguration(from: data)
            
            await MainActor.run {
                successMessage = "Configuration importée avec succès"
                importSummary = summary
                isImporting = false
                print("✅ Import completed successfully")
                
                // Effacer les messages après 5 secondes
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    successMessage = nil
                    importSummary = nil
                }
            }
        } catch {
            print("❌ Import failed: \(error)")
            
            let errorMessage: String
            if let localizedError = error as? LocalizedError {
                errorMessage = localizedError.errorDescription ?? "Erreur d'import"
            } else if error.localizedDescription.contains("permission") || error.localizedDescription.contains("Permission") {
                errorMessage = "Permission refusée pour lire le fichier. Le fichier doit être sélectionné via le dialogue d'import."
            } else {
                errorMessage = "Erreur lors de l'import : \(error.localizedDescription)"
            }
            
            await MainActor.run {
                importError = errorMessage
                importSummary = nil
                isImporting = false
            }
        }
    }
    
    #if os(macOS)
    private func openImportDialog() {
        let panel = NSOpenPanel()
        panel.title = "Importer la configuration Flux"
        panel.message = "Sélectionnez un fichier de configuration JSON"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    await importConfiguration(from: url)
                }
            }
        }
    }
    #endif
}

// Document pour l'export
struct ConfigurationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var data: Data
    
    init(data: Data) {
        print("📄 Creating ConfigurationDocument with \(data.count) bytes")
        self.data = data
    }
    
    init(configuration: FileDocumentReadConfiguration) throws {
        print("📖 Reading ConfigurationDocument from file")
        guard let data = configuration.file.regularFileContents else {
            print("❌ No file contents found")
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        print("💾 Writing ConfigurationDocument to file (\(data.count) bytes)")
        return FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    ConfigurationImportExportView()
        .environment(FeedService(context: try! ModelContext(ModelContainer(for: Feed.self))))
}
