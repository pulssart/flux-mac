// WhatsNewView.swift
// What's New modal — shown once per version, re-accessible from Settings.

import SwiftUI

/// Current app version for the What's New screen.
/// Bump this value and update `whatsNewFeatures` when releasing a new version.
private let whatsNewVersion = "1.0.4"

/// Each feature displayed in the What's New modal.
private struct WhatsNewFeature: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
}

/// Features for the current release.
private let whatsNewFeatures: [WhatsNewFeature] = [
    WhatsNewFeature(
        icon: "hand.wave",
        iconColor: .blue,
        title: "Redesigned Onboarding",
        description: "A fresh onboarding experience with language selection, notification preferences, haptic feedback, and Safari extension guidance."
    ),
    WhatsNewFeature(
        icon: "globe",
        iconColor: .purple,
        title: "Language Selection",
        description: "Choose your preferred language right from the onboarding or settings. The entire app adapts instantly."
    ),
    WhatsNewFeature(
        icon: "app.badge",
        iconColor: .red,
        title: "Read Later Badge",
        description: "The app icon badge now shows your Read Later count instead of unread articles. Toggle it on or off in settings."
    ),
    WhatsNewFeature(
        icon: "safari",
        iconColor: .cyan,
        title: "Safari Extension",
        description: "Add any RSS feed in one click with the Flux Safari extension — highlighted during onboarding."
    ),
    WhatsNewFeature(
        icon: "star",
        iconColor: .yellow,
        title: "Rate the App",
        description: "Love Flux? A new shortcut in Settings lets you leave a review on the Mac App Store."
    ),
    WhatsNewFeature(
        icon: "bolt.fill",
        iconColor: .green,
        title: "Smarter Feed Detection",
        description: "Already-added feeds are now properly detected in the Add Feed sheet, avoiding duplicates."
    ),
]

// MARK: - Public helpers

/// Returns `true` the first time this version's What's New has not been seen yet.
/// After the first call that returns `true`, subsequent calls return `false` (the key is written when the sheet is dismissed).
func shouldShowWhatsNew() -> Bool {
    let seen = UserDefaults.standard.string(forKey: "whatsNew.lastSeenVersion") ?? ""
    return seen != whatsNewVersion
}

/// Marks the current version's What's New as seen.
func markWhatsNewAsSeen() {
    UserDefaults.standard.set(whatsNewVersion, forKey: "whatsNew.lastSeenVersion")
}

// MARK: - View

struct WhatsNewView: View {
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Text("What's New")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Version \(whatsNewVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            // Feature list
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(Array(whatsNewFeatures.enumerated()), id: \.element.id) { index, feature in
                        featureRow(feature)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 16)
                            .animation(
                                .easeOut(duration: 0.4).delay(Double(index) * 0.07),
                                value: appeared
                            )
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
            }

            // Continue button
            Button {
                markWhatsNewAsSeen()
                isPresented = false
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .frame(width: 420, height: 680)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                appeared = true
            }
        }
    }

    private func featureRow(_ feature: WhatsNewFeature) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(feature.iconColor.gradient)
                    .frame(width: 44, height: 44)
                Image(systemName: feature.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(feature.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
