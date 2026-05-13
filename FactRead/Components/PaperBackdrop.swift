import SwiftUI

struct PaperBackdrop: View {
    let palette: ReaderTheme.Palette

    var body: some View {
        ZStack {
            palette.pageBackground

            if palette.isDark {
                darkBacksideTexture
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    private var darkBacksideTexture: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.12),
                    .clear,
                    Color.black.opacity(0.20)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                Spacer()
                RadialGradient(
                    colors: [
                        palette.warmOverlay.opacity(0.22),
                        palette.markerTint.opacity(0.10),
                        .clear
                    ],
                    center: .center,
                    startRadius: 18,
                    endRadius: 210
                )
                .frame(height: 230)
                .blur(radius: 7)
                .offset(y: 30)
            }
        }
    }
}
