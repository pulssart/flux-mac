// GlowEffect.swift
// Apple Intelligence-style glow effect for window borders
// Inspired by: https://github.com/jacobamobin/AppleIntelligenceGlowEffect

#if os(macOS)
import SwiftUI

/// Generates animated gradient stops for the glow effect
struct GlowEffect {
    /// Generates random gradient stops with colors similar to Apple Intelligence effect
    static func generateGradientStops() -> [Gradient.Stop] {
        let colors: [Color] = [
            .blue, .purple, .pink, .orange, .yellow, .green, .cyan, .indigo
        ]

        let count = Int.random(in: 8...12)
        var stops: [Gradient.Stop] = []

        for i in 0..<count {
            let color = colors.randomElement() ?? .blue
            let location = Double(i) / Double(count - 1)
            stops.append(Gradient.Stop(color: color.opacity(0.8), location: location))
        }

        return stops
    }
}

/// Window border glow effect view (no blur layer)
struct GlowEffectNoBlur: View {
    let gradientStops: [Gradient.Stop]
    let lineWidth: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                LinearGradient(
                    stops: gradientStops,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: lineWidth
            )
    }
}

/// Window border glow effect view (with blur)
struct GlowEffectWithBlur: View {
    let gradientStops: [Gradient.Stop]
    let lineWidth: CGFloat
    let blurRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                LinearGradient(
                    stops: gradientStops,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: lineWidth
            )
            .blur(radius: blurRadius)
    }
}

/// Combined window glow effect with animation
struct WindowGlowEffect: View {
    @State private var gradientStops: [Gradient.Stop] = GlowEffect.generateGradientStops()
    @State private var animationTimer: Timer?

    let isActive: Bool

    var body: some View {
        GeometryReader { geometry in
            if isActive {
                ZStack {
                    // Sharp layer
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(
                            LinearGradient(
                                stops: gradientStops,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 6
                        )
                        .opacity(0.95)

                    // Medium blur layer for depth
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(
                            LinearGradient(
                                stops: gradientStops,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 10
                        )
                        .blur(radius: 8)
                        .opacity(0.75)

                    // Outer glow
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(
                            LinearGradient(
                                stops: gradientStops,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 14
                        )
                        .blur(radius: 16)
                        .opacity(0.6)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: isActive) { _, active in
            if active {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
        .onAppear {
            if isActive {
                startAnimation()
            }
        }
        .onDisappear {
            stopAnimation()
        }
    }

    private func startAnimation() {
        // Initial animation
        updateGradient()

        // Repeat animation every 250ms
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            updateGradient()
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func updateGradient() {
        withAnimation(.easeInOut(duration: 0.5)) {
            gradientStops = GlowEffect.generateGradientStops()
        }
    }
}

#endif
