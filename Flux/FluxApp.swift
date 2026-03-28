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
#if canImport(UserNotifications)
import UserNotifications
#endif
#endif
#if os(iOS)
import BackgroundTasks
#endif

#if os(macOS)
final class FluxAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var windowDelegateHandler: ZoomGuardWindowDelegate?

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                DeepLinkRouter.shared.receive(url)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().delegate = self
        #endif
        // Install zoom guard on main window to prevent infinite recursion on macOS Tahoe
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let window = NSApplication.shared.mainWindow else { return }
            let handler = ZoomGuardWindowDelegate(original: window.delegate)
            self?.windowDelegateHandler = handler
            window.delegate = handler
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard
            let deepLinkValue = response.notification.request.content.userInfo["fluxDeepLink"] as? String,
            let deepLinkURL = URL(string: deepLinkValue)
        else {
            return
        }

        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            DeepLinkRouter.shared.receive(deepLinkURL)
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
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer?
    private let context: ModelContext?
    private let feedService: FeedService?
    private let polymarketService: PolymarketService
    private let deepLinkRouter: DeepLinkRouter
    private let isICloudSyncConfigured: Bool

    init() {
        self.deepLinkRouter = DeepLinkRouter.shared
        self.polymarketService = PolymarketService()
        do {
            let schema = Schema([
                Feed.self,
                Article.self,
                ReaderNote.self,
                Suggestion.self,
                Settings.self,
                Folder.self,
                SignalFavorite.self
            ])
            let cloudConfiguration = ModelConfiguration(
                "Flux",
                schema: schema,
                cloudKitDatabase: .automatic
            )
            let container = try ModelContainer(for: schema, configurations: [cloudConfiguration])
            let context = ModelContext(container)

            self.container = container
            self.context = context
            self.isICloudSyncConfigured = true
            let feedService = FeedService(context: context, isICloudSyncConfigured: true)
            feedService.iCloudSyncDiagnosticMessage = "Le stockage iCloud a été initialisé."
            self.feedService = feedService
            DefaultsInitializer.applyIfNeeded(context: context)
        } catch {
            do {
                let schema = Schema([
                    Feed.self,
                    Article.self,
                    ReaderNote.self,
                    Suggestion.self,
                    Settings.self,
                    Folder.self,
                    SignalFavorite.self
                ])
                let fallbackConfiguration = ModelConfiguration(
                    "Flux",
                    schema: schema,
                    cloudKitDatabase: .none
                )
                let container = try ModelContainer(for: schema, configurations: [fallbackConfiguration])
                let context = ModelContext(container)

                self.container = container
                self.context = context
                self.isICloudSyncConfigured = false
                let feedService = FeedService(context: context, isICloudSyncConfigured: false)
                let nsError = error as NSError
                let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String
                let suggestion = nsError.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String
                let details = [
                    error.localizedDescription,
                    reason,
                    suggestion,
                    "\(nsError.domain) (\(nsError.code))"
                ]
                .compactMap { $0 }
                .joined(separator: " | ")
                feedService.iCloudSyncDiagnosticMessage = "Le stockage iCloud n’a pas pu démarrer: \(details)"
                self.feedService = feedService
                DefaultsInitializer.applyIfNeeded(context: context)
                print("Cloud-backed ModelContainer failed to load, falling back to local storage: \(error)")
            } catch {
                self.container = nil
                self.context = nil
                self.feedService = nil
                self.isICloudSyncConfigured = false
                print("ModelContainer failed to load: \(error)")
            }
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
                    .environment(polymarketService)
                    .environment(deepLinkRouter)
                    .modelContainer(container)
                    .frame(minWidth: 420, minHeight: 500)
                    .onAppear {
                        polymarketService.startMonitoring()
                        let defaults = UserDefaults.standard
                        let newsNotificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
                        let signalNotificationsEnabled: Bool = {
                            if defaults.object(forKey: "signalNotificationsEnabled") == nil {
                                return true
                            }
                            return defaults.bool(forKey: "signalNotificationsEnabled")
                        }()

                        if newsNotificationsEnabled || signalNotificationsEnabled {
                            feedService.requestNotificationPermissionIfNeeded()
                        }
                    }
                #else
                ContentView()
                    .environment(feedService)
                    .environment(polymarketService)
                    .environment(deepLinkRouter)
                    .modelContainer(container)
                    .onAppear {
                        polymarketService.startMonitoring()
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                polymarketService.refreshIfNeeded()
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
