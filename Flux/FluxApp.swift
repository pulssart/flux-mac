//
//  FluxApp.swift
//  Flux
//
//  Created by Adrien Donot on 22/08/2025.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import BackgroundTasks
#endif

#if os(macOS)
final class FluxAppDelegate: NSObject, NSApplicationDelegate {
    private var windowDelegateHandler: ZoomGuardWindowDelegate?

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                DeepLinkRouter.shared.receive(url)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Install zoom guard on main window to prevent infinite recursion on macOS Tahoe
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let window = NSApplication.shared.mainWindow else { return }
            let handler = ZoomGuardWindowDelegate(original: window.delegate)
            self?.windowDelegateHandler = handler
            window.delegate = handler
        }
    }
}

/// Prevents infinite recursion in _NSThemeZoomWidgetCell on macOS Tahoe beta
/// by intercepting the zoom action and performing it manually.
final class ZoomGuardWindowDelegate: NSObject, NSWindowDelegate {
    weak var original: (any NSWindowDelegate)?
    private var isZooming = false

    init(original: (any NSWindowDelegate)?) {
        self.original = original
        super.init()
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        guard !isZooming else { return false }
        return original?.windowShouldZoom?(window, toFrame: newFrame) ?? true
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        return original?.windowWillUseStandardFrame?(window, defaultFrame: newFrame) ?? newFrame
    }

    func window(_ window: NSWindow, willUseFullScreenContentSize proposedSize: NSSize) -> NSSize {
        return original?.window?(window, willUseFullScreenContentSize: proposedSize) ?? proposedSize
    }

    // Forward all other delegate calls to original
    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        if let original = original as? NSObject {
            return original.responds(to: aSelector)
        }
        return false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original = original as? NSObject, original.responds(to: aSelector) {
            return original
        }
        return super.forwardingTarget(for: aSelector)
    }
}
#endif

@main
struct FluxApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(FluxAppDelegate.self) private var appDelegate
    #endif
    private let container: ModelContainer?
    private let context: ModelContext?
    private let feedService: FeedService?
    private let deepLinkRouter: DeepLinkRouter

    init() {
        self.deepLinkRouter = DeepLinkRouter.shared
        do {
            let container = try ModelContainer(for: Feed.self, Article.self, ReaderNote.self, Suggestion.self, Settings.self, Folder.self)
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

    #if os(iOS)
    private static let backgroundRefreshTaskId = "com.adriendonot.fluxapp.refresh"
    #endif

    var body: some Scene {
        WindowGroup {
            if let feedService = feedService, let container = container {
                #if os(macOS)
                ContentView()
                    .environment(feedService)
                    .environment(deepLinkRouter)
                    .modelContainer(container)
                    .frame(minWidth: 420, minHeight: 500)
                #else
                ContentView()
                    .environment(feedService)
                    .environment(deepLinkRouter)
                    .modelContainer(container)
                    .onAppear {
                        registerBackgroundRefresh()
                        scheduleBackgroundRefresh()
                    }
                #endif
            } else {
                Text("Failed to load data models.")
                    .padding()
            }
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 750)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("\(LocalizationManager.shared.localizedString(.settings))…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
        #endif
    }

    #if os(iOS)
    private func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundRefreshTaskId, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleBackgroundRefresh(refreshTask)
        }
    }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundRefreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BackgroundRefresh] Failed to schedule: \(error)")
        }
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()

        guard let feedService = feedService else {
            task.setTaskCompleted(success: false)
            return
        }

        let refreshWork = Task {
            do {
                try await feedService.refreshArticles(for: nil)
                task.setTaskCompleted(success: true)
            } catch {
                print("[BackgroundRefresh] Refresh failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            refreshWork.cancel()
        }
    }
    #endif
}
