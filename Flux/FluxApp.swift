//
//  FluxApp.swift
//  Flux
//
//  Created by Adrien Donot on 22/08/2025.
//

import SwiftUI
import SwiftData
@main
struct FluxApp: App {
    private let container: ModelContainer?
    private let context: ModelContext?
    private let feedService: FeedService?

    init() {
        do {
            let container = try ModelContainer(for: Feed.self, Article.self, Suggestion.self, Settings.self, Folder.self)
            self.container = container
            self.context = ModelContext(container)
            self.feedService = FeedService(context: self.context!)
            // Appliquer les defaults pour nouveaux utilisateurs si nécessaire
            DefaultsInitializer.applyIfNeeded(context: self.context!)
        } catch {
            self.container = nil
            self.context = nil
            self.feedService = nil
            print("ModelContainer failed to load: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if let feedService = feedService, let container = container {
                ContentView()
                    .environment(feedService)
                    .modelContainer(container)
            } else {
                Text("Failed to load data models.")
                    .padding()
            }
        }
    }
}
