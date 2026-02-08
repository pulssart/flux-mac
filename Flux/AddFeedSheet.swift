import SwiftUI

struct AddFeedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var newFeedURL: String
    @Binding var addError: String?
    let onAdd: (URL) async -> Void

    @State private var isAdding = false
    @State private var showSuggestions = false
    @State private var suggestions: [RSSFeedSuggestion] = []
    @FocusState private var isTextFieldFocused: Bool

    private let suggestionsManager = RSSFeedSuggestionsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LocalizationManager.shared.localizedString(.addFeed))
                .font(.title3).bold()
            
            VStack(alignment: .leading, spacing: 0) {
                TextField("https://…", text: $newFeedURL, prompt: Text("https://…"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .disabled(isAdding)
                    .focused($isTextFieldFocused)
                    .onChange(of: newFeedURL) { _, newValue in
                        updateSuggestions(for: newValue)
                    }
                    .onChange(of: isTextFieldFocused) { _, focused in
                        if focused {
                            if newFeedURL.isEmpty {
                                suggestions = suggestionsManager.popular()
                            }
                            showSuggestions = true
                        } else {
                            // Délai pour permettre le clic sur une suggestion
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showSuggestions = false
                            }
                        }
                    }
                
                // Menu de suggestions
                if showSuggestions && !suggestions.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(suggestions) { suggestion in
                                Button(action: {
                                    newFeedURL = suggestion.url
                                    showSuggestions = false
                                    isTextFieldFocused = false
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "rss")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                            .frame(width: 16)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.name)
                                                .font(.callout)
                                                .foregroundStyle(.primary)
                                            
                                            if let category = suggestion.category {
                                                Text(category)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "arrow.up.left")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                
                                if suggestion.id != suggestions.last?.id {
                                    Divider()
                                        .padding(.leading, 38)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                    .padding(.top, 4)
                }
            }
            
            if let err = addError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            
            if isAdding {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(LocalizationManager.shared.localizedString(.searchingRSSFeed))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
            }
            
            HStack {
                Spacer()
                Button(LocalizationManager.shared.localizedString(.cancel)) {
                    showSuggestions = false
                    isTextFieldFocused = false
                    addError = nil
                    dismiss()
                }
                .disabled(isAdding)
                
                Button(LocalizationManager.shared.localizedString(.save)) {
                    showSuggestions = false
                    isTextFieldFocused = false
                    
                    var urlString = newFeedURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Normaliser en HTTPS (ATS / Mac App Store)
                    if urlString.hasPrefix("http://") {
                        urlString = "https://" + urlString.dropFirst("http://".count)
                    }
                    if !urlString.isEmpty && !urlString.hasPrefix("https://") {
                        urlString = "https://" + urlString
                    }

                    guard let url = URL(string: urlString), url.scheme == "https" else {
                        addError = "Seuls les flux HTTPS sont acceptés"
                        return
                    }
                    isAdding = true
                    addError = nil
                    Task {
                        await onAdd(url)
                        isAdding = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newFeedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
        .onAppear {
            suggestions = suggestionsManager.popular()
        }
    }
    
    private func updateSuggestions(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            suggestions = suggestionsManager.popular()
        } else {
            suggestions = suggestionsManager.search(trimmed)
        }
        showSuggestions = isTextFieldFocused && !suggestions.isEmpty
    }
}
