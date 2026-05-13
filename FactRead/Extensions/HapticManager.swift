import UIKit

final class HapticManager {
    static let shared = HapticManager()
    var isEnabled: Bool = true
    private(set) var themeMode: ReaderThemeMode = .light

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private var lastImpactAt: CFTimeInterval = 0
    private var lastSelectionAt: CFTimeInterval = 0
    private var lastNotificationAt: CFTimeInterval = 0
    private var impactIntensityMultiplier: CGFloat = 1.0

    // Smooth tactile pacing: prevents stacked pulses from feeling noisy.
    private let minImpactInterval: CFTimeInterval = 0.06
    private let minSelectionInterval: CFTimeInterval = 0.05
    private let minNotificationInterval: CFTimeInterval = 0.12

    private init() {
        prepareAll()
    }

    func configure(themeMode: ReaderThemeMode) {
        self.themeMode = themeMode
        switch themeMode {
        case .light:
            impactIntensityMultiplier = 1.0
        case .dark:
            // Dark palette feels better with a slightly softer tactile envelope.
            impactIntensityMultiplier = 0.86
        }
    }

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        let now = CACurrentMediaTime()
        guard now - lastImpactAt >= minImpactInterval else { return }
        lastImpactAt = now
        let (generator, intensity) = boostedImpactConfig(for: style)
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
    }

    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        let now = CACurrentMediaTime()
        guard now - lastNotificationAt >= minNotificationInterval else { return }
        lastNotificationAt = now
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(type)
    }

    func selection() {
        guard isEnabled else { return }
        let now = CACurrentMediaTime()
        guard now - lastSelectionAt >= minSelectionInterval else { return }
        lastSelectionAt = now
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
    }

    private func prepareAll() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        softImpact.prepare()
        rigidImpact.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }

    private func boostedImpactConfig(
        for style: UIImpactFeedbackGenerator.FeedbackStyle
    ) -> (UIImpactFeedbackGenerator, CGFloat) {
        let multiplier = impactIntensityMultiplier
        switch style {
        case .light:
            return (lightImpact, min(1.0, 0.55 * multiplier))
        case .medium:
            return (mediumImpact, min(1.0, 0.65 * multiplier))
        case .heavy:
            return (heavyImpact, min(1.0, 0.85 * multiplier))
        case .soft:
            return (softImpact, min(1.0, 0.60 * multiplier))
        case .rigid:
            return (rigidImpact, min(1.0, 0.75 * multiplier))
        @unknown default:
            return (mediumImpact, min(1.0, 0.62 * multiplier))
        }
    }
}
