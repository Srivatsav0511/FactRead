import UIKit

@MainActor
final class PageFlipHaptics {
    private let thresholdGenerator = UIImpactFeedbackGenerator(style: .light)
    private let completionGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let cancelGenerator = UIImpactFeedbackGenerator(style: .soft)

    private var thresholdFired = false

    func prepare() {
        thresholdGenerator.prepare()
        completionGenerator.prepare()
        cancelGenerator.prepare()
    }

    func resetThreshold() {
        thresholdFired = false
    }

    func fireThresholdIfNeeded(enabled: Bool) {
        guard enabled, HapticManager.shared.isEnabled, thresholdFired == false else { return }
        thresholdFired = true
        thresholdGenerator.impactOccurred(intensity: 0.40)
    }

    func fireCompletion(enabled: Bool) {
        guard enabled, HapticManager.shared.isEnabled else { return }
        completionGenerator.impactOccurred(intensity: 0.28)
    }

    func fireCancel(enabled: Bool) {
        guard enabled, HapticManager.shared.isEnabled else { return }
        cancelGenerator.impactOccurred(intensity: 0.24)
    }
}

typealias PageTurnHaptics = PageFlipHaptics
