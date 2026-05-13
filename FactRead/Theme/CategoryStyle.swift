import SwiftUI

enum CategoryStyle {
    static func accent(for category: String, intensity: Double) -> Color {
        let clamped = min(max(intensity, 0), 1)
        // Keep a baseline so colors don't disappear in glass-heavy UI.
        let opacity = 0.32 + (0.68 * clamped)
        return Fact.tint(for: category).opacity(opacity)
    }
}

