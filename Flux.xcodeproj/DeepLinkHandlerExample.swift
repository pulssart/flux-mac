import SwiftUI

// Exemple minimal pour ouvrir un article via flux://article?id=<UUID>
// Intègre ce snippet là où tu gères ta navigation (par ex. dans FluxApp ou ContentView/AppSidebar).
// TODO: Remplacer le print par l’ouverture effective de l’article via FeedService/navigation.
struct DeepLinkHandlerExample: ViewModifier {
    func body(content: Content) -> some View {
        content.onOpenURL { url in
            guard url.scheme == "flux" else { return }
            if url.host == "article",
               let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let idStr = comps.queryItems?.first(where: { $0.name == "id" })?.value,
               let uuid = UUID(uuidString: idStr) {
                // TODO: ouvrir l’article UUID dans l’app
                print("Deep link article UUID:", uuid)
                // Exemple: NotificationCenter.default.post(name: .openArticleByUUID, object: uuid)
            }
        }
    }
}

extension View {
    func installDeepLinkHandler() -> some View { modifier(DeepLinkHandlerExample()) }
}

