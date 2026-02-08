// HapticFeedback.swift
// Centralized haptic feedback for macOS Force Touch trackpad

#if os(macOS)
import AppKit

enum HapticFeedback {
    /// Feedback générique léger (tap discret)
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    
    /// Feedback d'alignement (snap, accrochage)
    static func alignment() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
    
    /// Feedback de changement de niveau (slider, progression)
    static func levelChange() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
    
    /// Feedback de succès (action complétée)
    static func success() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    
    /// Feedback d'erreur (double tap rapide)
    static func error() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }
}

// MARK: - Heartbeat Haptic Manager

/// Gère les vibrations rythmiques "heartbeat" pendant les opérations longues
final class HeartbeatHaptic {
    static let shared = HeartbeatHaptic()
    
    private var timer: Timer?
    private var isRunning = false
    
    private init() {}
    
    /// Démarre le battement de cœur haptique
    /// Pattern: deux taps rapides (lub-dub) toutes les 0.8 secondes
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        // Premier battement immédiat
        performHeartbeat()
        
        // Répéter toutes les 0.9 secondes
        timer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in
            self?.performHeartbeat()
        }
    }
    
    /// Arrête le battement de cœur
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
    
    /// Un battement : lub-dub (deux taps rapprochés)
    private func performHeartbeat() {
        // "Lub" - premier tap (plus fort)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        
        // "Dub" - second tap après 120ms (plus léger)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}
#endif
