#if os(macOS)
import SafariServices
import SwiftUI

enum SafariExtensionStatus: Equatable {
    case checking
    case enabled
    case disabled
    case unavailable(String)
}

enum SafariExtensionSupport {
    static let bundleIdentifier = "com.adriendonot.fluxapp.safari"
    static let announcementToken = "2026-03-safari-extension"

    static func refreshStatus(completion: @escaping (SafariExtensionStatus) -> Void) {
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: bundleIdentifier) { state, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.unavailable(error.localizedDescription))
                    return
                }

                guard let state else {
                    completion(.unavailable("Unknown state"))
                    return
                }

                completion(state.isEnabled ? .enabled : .disabled)
            }
        }
    }

    static func openPreferences(completion: @escaping (String?) -> Void) {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: bundleIdentifier) { error in
            DispatchQueue.main.async {
                completion(error?.localizedDescription)
            }
        }
    }
}

private struct SafariExtensionCopy {
    let sectionTitle: String
    let sectionDescription: String
    let statusChecking: String
    let statusEnabled: String
    let statusDisabled: String
    let statusUnavailable: String
    let openSettings: String
    let refreshStatus: String
    let step1: String
    let step2: String
    let step3: String
    let sheetTitle: String
    let sheetBody: String
    let later: String
    let close: String

    static func current() -> SafariExtensionCopy {
        switch LocalizationManager.shared.currentLanguage {
        case .french:
            return SafariExtensionCopy(
                sectionTitle: "Extension Safari",
                sectionDescription: "Ajoutez vos flux depuis Safari en un clic. Flux vérifie si le site propose un vrai flux RSS, Atom ou JSON, puis l’ajoute directement dans l’app.",
                statusChecking: "Vérification en cours…",
                statusEnabled: "Activée dans Safari",
                statusDisabled: "Disponible mais non activée",
                statusUnavailable: "Impossible de lire l’état pour le moment",
                openSettings: "Ouvrir les réglages Safari",
                refreshStatus: "Actualiser",
                step1: "Ouvrez les réglages des extensions dans Safari.",
                step2: "Activez “Flux for Safari”.",
                step3: "Épinglez l’extension dans la barre Safari si vous voulez l’avoir sous la main.",
                sheetTitle: "Flux fonctionne aussi dans Safari",
                sheetBody: "L’extension Safari est maintenant incluse dans Flux. Il suffit de l’activer une fois dans Safari pour ajouter des flux depuis le navigateur.",
                later: "Plus tard",
                close: "Fermer"
            )
        default:
            return SafariExtensionCopy(
                sectionTitle: "Safari Extension",
                sectionDescription: "Add feeds from Safari in one click. Flux checks whether the site has a real RSS, Atom, or JSON feed, then adds it directly to the app.",
                statusChecking: "Checking status…",
                statusEnabled: "Enabled in Safari",
                statusDisabled: "Available but not enabled",
                statusUnavailable: "Status is unavailable right now",
                openSettings: "Open Safari Settings",
                refreshStatus: "Refresh",
                step1: "Open Safari extension settings.",
                step2: "Turn on “Flux for Safari”.",
                step3: "Pin the extension in Safari if you want faster access.",
                sheetTitle: "Flux now works in Safari",
                sheetBody: "The Safari extension is now included in Flux. You only need to enable it once in Safari to add feeds from the browser.",
                later: "Later",
                close: "Close"
            )
        }
    }
}

private extension SafariExtensionStatus {
    var tint: Color {
        switch self {
        case .checking:
            return .orange
        case .enabled:
            return .green
        case .disabled:
            return .blue
        case .unavailable:
            return .red
        }
    }

    func label(using copy: SafariExtensionCopy) -> String {
        switch self {
        case .checking:
            return copy.statusChecking
        case .enabled:
            return copy.statusEnabled
        case .disabled:
            return copy.statusDisabled
        case .unavailable:
            return copy.statusUnavailable
        }
    }
}

struct SafariExtensionSettingsCard: View {
    @State private var status: SafariExtensionStatus = .checking
    @State private var actionError: String?

    private let copy = SafariExtensionCopy.current()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "safari")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 6) {
                    Text(copy.sectionTitle)
                        .font(.headline)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(status.tint)
                            .frame(width: 8, height: 8)

                        Text(status.label(using: copy))
                            .font(.subheadline.weight(.semibold))
                    }

                    Text(copy.sectionDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                stepRow("1", text: copy.step1)
                stepRow("2", text: copy.step2)
                stepRow("3", text: copy.step3)
            }

            HStack(spacing: 10) {
                Button(copy.openSettings) {
                    SafariExtensionSupport.openPreferences { error in
                        actionError = error
                    }
                }
                .buttonStyle(.borderedProminent)

                Button(copy.refreshStatus) {
                    loadStatus()
                }
                .buttonStyle(.bordered)
            }

            if case .unavailable(let reason) = status, reason.isEmpty == false {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionError {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.quaternary.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
        .onAppear(perform: loadStatus)
    }

    private func stepRow(_ number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.blue))

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func loadStatus() {
        actionError = nil
        status = .checking
        SafariExtensionSupport.refreshStatus { newStatus in
            status = newStatus
        }
    }
}

struct SafariExtensionAnnouncementSheet: View {
    @Binding var isPresented: Bool

    private let copy = SafariExtensionCopy.current()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(copy.sheetTitle)
                .font(.title3.bold())

            Text(copy.sheetBody)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SafariExtensionSettingsCard()

            HStack {
                Spacer()
                Button(copy.later) { isPresented = false }
                Button(copy.close) { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
    }
}
#endif
