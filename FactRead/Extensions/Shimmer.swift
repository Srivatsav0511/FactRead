import SwiftUI

struct Shimmer: ViewModifier {
    let isActive: Bool
    @State private var phase: CGFloat = -0.8

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    LinearGradient(
                        colors: [
                            .white.opacity(0.0),
                            .white.opacity(0.16),
                            .white.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .rotationEffect(.degrees(18))
                    .offset(x: phase * 240)
                    .blendMode(.plusLighter)
                    .mask(content)
                    .onAppear {
                        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                            phase = 1.2
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func shimmer(active: Bool) -> some View {
        modifier(Shimmer(isActive: active))
    }
}

