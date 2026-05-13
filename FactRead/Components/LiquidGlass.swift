import SwiftUI

extension View {
    @ViewBuilder
    func liquidGlassButtonStyle<S: InsettableShape>(fallbackShape: S, isDark: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.plain)
        }
    }

    func liquidGlassButtonStyle(isDark: Bool = false) -> some View {
        liquidGlassButtonStyle(fallbackShape: Capsule(style: .continuous), isDark: isDark)
    }

    @ViewBuilder
    func liquidGlassCard(cornerRadius: CGFloat = 16, isDark: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
        }
    }
}
