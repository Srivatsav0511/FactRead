import SwiftUI

struct LoadingSkeletonView: View {
    let palette: ReaderTheme.Palette
    let topSafeAreaInset: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.pageGradientTop, palette.pageBackground, palette.pageGradientBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.inkSecondary.opacity(0.24))
                    .frame(width: 112, height: 12)
                    .padding(.top, topSafeAreaInset + 26)

                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.inkPrimary.opacity(0.22))
                        .frame(height: 32)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.inkPrimary.opacity(0.18))
                        .frame(width: 236, height: 32)
                }
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 11) {
                    ForEach(0..<9, id: \.self) { idx in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.inkSecondary.opacity(idx < 3 ? 0.22 : 0.16))
                            .frame(width: lineWidth(at: idx), height: 14)
                    }
                }
                .padding(.top, 16)
                .shimmer(active: true)
            }
            .padding(.horizontal, ReaderTheme.horizontalMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }

    private func lineWidth(at index: Int) -> CGFloat {
        switch index {
        case 0: return 330
        case 1: return 307
        case 2: return 321
        case 3: return 295
        case 4: return 313
        case 5: return 268
        case 6: return 324
        case 7: return 276
        default: return 294
        }
    }
}
