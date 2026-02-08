// FeedsView.swift
// Affichage et ajout de flux RSS
import SwiftUI
import SwiftData

struct FeedsView: View {
    @Environment(FeedService.self) private var feedService
    private let lm = LocalizationManager.shared
    @State private var urlString: String = ""
    @State private var error: String?
    @State private var isAdding = false
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(lm.localizedString(.subscriptions)).font(.title2)
            HStack {
                TextField(lm.localizedString(.addFeedURL), text: $urlString, prompt: Text("https://…"))
                    .textFieldStyle(.roundedBorder)
                    .disabled(isAdding)
                Button {
                    Task {
                        await MainActor.run {
                            self.error = nil
                            isAdding = true
                        }
                        do {
                            try await feedService.addFeed(from: urlString)
                            await MainActor.run {
                                urlString = ""
                            }
                        } catch let e as LocalizedError {
                            await MainActor.run {
                                self.error = e.errorDescription ?? e.localizedDescription
                            }
                        } catch {
                            await MainActor.run {
                                self.error = error.localizedDescription
                            }
                        }
                        await MainActor.run {
                            isAdding = false
                        }
                    }
                } label: {
                    if isAdding { ProgressView() } else { Text(lm.localizedString(.add)) }
                }
                .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
            }
            if let error {
                Text(error).foregroundColor(.red).font(.caption)
            }
            List(feedService.feeds, id: \.id) { feed in
                HStack {
                    VStack(alignment: .leading) {
                        Text(feed.title).bold()
                        Text(feed.feedURL.absoluteString).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(feed.addedAt, style: .date).font(.caption2)
                }
            }
            .listStyle(.plain)
        }
        .padding()
    }
}

#Preview {
    // Prévoir un MockFeedService pour le preview.
    FeedsView().environment(FeedService(context: try! ModelContext(ModelContainer(for: Feed.self))))
}
