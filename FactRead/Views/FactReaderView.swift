import SwiftUI

struct FactReaderView: View {
    let pages: [FactViewModel.PageSnapshot]
    @Binding var index: Int
    let palette: ReaderTheme.Palette
    let topSafeAreaInset: CGFloat
    let hapticsEnabled: Bool
    let typingSoundEnabled: Bool
    let appLanguage: AppLanguage
    let readerFontScale: Double
    let readerTypographyStyle: ReaderTypographyStyle
    let categoryTintIntensity: Double
    let pageTextAnimationsEnabled: Bool
    let showBookmarkHint: Bool
    let isDailyLimitReached: Bool
    let dailyLimitCount: Int
    let cooldownEndsAt: Date?
    let cooldownMessage: String
    let pageTurnStyle: PageTurnStyle
    let controlsVisible: Bool
    let canAccessFact: (Fact) -> Bool
    let onDoubleTapCurrent: (Fact) -> Void
    let onReaderTap: () -> Void
    let onDailyLimitHit: () -> Void
    var body: some View {
        ZStack {
            PaperBackdrop(palette: palette)

            Group {
                if pageTurnStyle == .curl {
                    BooksPageCurlView(
                        pages: pages,
                        index: $index,
                        palette: palette,
                        topSafeAreaInset: topSafeAreaInset,
                        hapticsEnabled: hapticsEnabled,
                        typingSoundEnabled: typingSoundEnabled,
                        appLanguage: appLanguage,
                        readerFontScale: readerFontScale,
                        readerTypographyStyle: readerTypographyStyle,
                        categoryTintIntensity: categoryTintIntensity,
                        pageTextAnimationsEnabled: pageTextAnimationsEnabled,
                        isDailyLimitReached: isDailyLimitReached,
                        dailyLimitCount: dailyLimitCount,
                        cooldownEndsAt: cooldownEndsAt,
                        cooldownMessage: cooldownMessage,
                        controlsVisible: controlsVisible,
                        canAccessFact: canAccessFact,
                        onDoubleTapCurrent: onDoubleTapCurrent,
                        onReaderTap: onReaderTap,
                        onDailyLimitHit: onDailyLimitHit
                    )
                } else {
                    BooksPageSlideView(
                        pages: pages,
                        index: $index,
                        palette: palette,
                        topSafeAreaInset: topSafeAreaInset,
                        hapticsEnabled: hapticsEnabled,
                        typingSoundEnabled: typingSoundEnabled,
                        appLanguage: appLanguage,
                        categoryTintIntensity: categoryTintIntensity,
                        pageTextAnimationsEnabled: pageTextAnimationsEnabled,
                        isDailyLimitReached: isDailyLimitReached,
                        dailyLimitCount: dailyLimitCount,
                        cooldownEndsAt: cooldownEndsAt,
                        cooldownMessage: cooldownMessage,
                        controlsVisible: controlsVisible,
                        canAccessFact: canAccessFact,
                        onDoubleTapCurrent: onDoubleTapCurrent,
                        onReaderTap: onReaderTap,
                        readerFontScale: readerFontScale,
                        readerTypographyStyle: readerTypographyStyle,
                        onDailyLimitHit: onDailyLimitHit
                    )
                }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if showBookmarkHint {
                BookmarkHintPill(palette: palette, language: appLanguage)
                    .padding(.top, topSafeAreaInset + 8)
                    .transition(.opacity)
            }
        }
    }

    private var dailyLimitText: String {
        "Daily limit reached. Come back tomorrow."
    }
}

private struct BookmarkHintPill: View {
    let palette: ReaderTheme.Palette
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.system(size: 13, weight: .semibold))
            Text(bookmarkHintText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(palette.inkPrimary.opacity(0.92))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlassCard(cornerRadius: 999, isDark: palette.isDark)
        .allowsHitTesting(false)
    }

    private var bookmarkHintText: String {
        "Double tap to bookmark"
    }
}

private struct DailyLimitPill: View {
    let palette: ReaderTheme.Palette
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .bold))
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(palette.inkPrimary.opacity(0.94))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlassCard(cornerRadius: 999, isDark: palette.isDark)
        .allowsHitTesting(false)
        .padding(.horizontal, 14)
    }
}
