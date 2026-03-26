import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension Color {
    static func fluxAppBackground(for colorScheme: ColorScheme) -> Color {
        #if os(iOS)
        if colorScheme == .dark {
            return Color(red: 0.075, green: 0.078, blue: 0.086)
        } else {
            return Color(uiColor: .systemGroupedBackground)
        }
        #elseif os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return .background
        #endif
    }
}
