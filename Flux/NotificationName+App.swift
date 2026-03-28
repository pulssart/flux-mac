import Foundation
import Observation

extension Notification.Name {
    static let openWebViewOverlay = Notification.Name("OpenWebViewOverlay")
    static let closeWebViewOverlay = Notification.Name("CloseWebViewOverlay")
    static let toggleSidebar = Notification.Name("ToggleSidebar")
    static let collapseSidebar = Notification.Name("CollapseSidebar")
    static let expandSidebar = Notification.Name("ExpandSidebar")
    static let openSettings = Notification.Name("OpenSettings")
    static let showWhatsNew = Notification.Name("ShowWhatsNew")
}

struct ArticleOpenRequest: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let forceReaderFirst: Bool
}

@Observable
@MainActor
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    private(set) var pendingURLs: [URL] = []
    private(set) var eventId = UUID()
    private var lastReceivedURLString: String?
    private var lastReceivedAt = Date.distantPast

    private init() {}

    func receive(_ url: URL) {
        let urlString = url.absoluteString
        let now = Date()

        if lastReceivedURLString == urlString, now.timeIntervalSince(lastReceivedAt) < 1 {
            return
        }

        lastReceivedURLString = urlString
        lastReceivedAt = now
        pendingURLs.append(url)
        eventId = UUID()
    }

    func consume() -> URL? {
        guard pendingURLs.isEmpty == false else { return nil }
        return pendingURLs.removeFirst()
    }
}

enum FluxDeepLink {
    static func signalURL(eventId: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "flux"
        components.host = "signals"
        if let eventId, eventId.isEmpty == false {
            components.queryItems = [URLQueryItem(name: "eventId", value: eventId)]
        }
        return components.url
    }
}
