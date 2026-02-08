//
//  ContentView.swift
//  Flux
//
//  Created by Adrien Donot on 22/08/2025.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
// Wrapper around NSVisualEffectView to render a blur background
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
#endif

import SwiftUI

struct ContentView: View {
    @AppStorage("windowBlurEnabled") private var windowBlurEnabled: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    private let glassSmokeOpacity: CGFloat = 0.48
    var body: some View {
        ZStack {
            #if canImport(AppKit)
            if windowBlurEnabled {
                if #available(macOS 26.0, *) {
                    Rectangle()
                        .glassEffect(in: Rectangle())
                        .overlay(smokeColor.opacity(glassSmokeOpacity))
                        .ignoresSafeArea()
                } else {
                    VisualEffectBlur()
                        .ignoresSafeArea()
                }
            }
            #endif
            AppSidebar()
        }
        #if canImport(AppKit)
        .onAppear { configureWindowBlur(enabled: windowBlurEnabled) }
        .onChange(of: windowBlurEnabled) { _, newValue in
            configureWindowBlur(enabled: newValue)
        }
        #endif
    }
}

private extension ContentView {
    var smokeColor: Color {
        colorScheme == .dark ? .black : .white
    }
}

#if canImport(AppKit)
private func configureWindowBlur(enabled: Bool) {
    guard let window = NSApplication.shared.windows.first else { return }
    // Uniformiser l'apparence de la fenêtre pour éviter tout shift de layout
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.styleMask.insert(.fullSizeContentView)
    if #available(macOS 13.0, *) {
        window.titlebarSeparatorStyle = .none
    }
    if #available(macOS 11.0, *) {
        window.toolbarStyle = .unified
    }
    window.isMovableByWindowBackground = true
    window.contentView?.superview?.wantsLayer = true
    
    // Contraintes de taille (assouplies pour un feed plus responsive)
    window.minSize = NSSize(width: 420, height: 520)
    window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

    if enabled {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor
    } else {
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.contentView?.superview?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}
#endif

#Preview {
    ContentView()
}
