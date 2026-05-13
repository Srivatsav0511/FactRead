import SwiftUI
import UIKit

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppSettings.self) private var settings

    @State private var selectedCategories: Set<String> = []
    @State private var selectedPageTurnStyle: PageTurnStyle = .slide
    @State private var selectedThemeID: String = "paper"

    @State private var currentSlideIndex = 0
    @State private var slideDirection: CGFloat = 1
    @State private var logoPulsing = false
    @State private var ambientMotion = false

    private let themePresets: [OnboardingThemePreset] = [
        .init(id: "original", title: "Original", subtitle: "Balanced", tint: 0.90, turn: .curl, typographyStyle: .original, lightBackgroundHex: "F9F9F7", lightForegroundHex: "171717", darkBackgroundHex: "0B0B0E", darkForegroundHex: "F2F2F2"),
        .init(id: "quiet", title: "Quiet", subtitle: "Dim", tint: 0.70, turn: .curl, typographyStyle: .quiet, lightBackgroundHex: "585960", lightForegroundHex: "B4B7C0", darkBackgroundHex: "050507", darkForegroundHex: "9497A2"),
        .init(id: "paper", title: "Paper", subtitle: "Soft", tint: 0.55, turn: .slide, typographyStyle: .paper, lightBackgroundHex: "F1F1EE", lightForegroundHex: "22232A", darkBackgroundHex: "1B1C23", darkForegroundHex: "D3D5DD"),
        .init(id: "bold", title: "Bold", subtitle: "High Contrast", tint: 1.00, turn: .slide, typographyStyle: .bold, lightBackgroundHex: "FFFFFF", lightForegroundHex: "101216", darkBackgroundHex: "121318", darkForegroundHex: "FDFEFF"),
        .init(id: "calm", title: "Calm", subtitle: "Easy Read", tint: 0.62, turn: .curl, typographyStyle: .calm, lightBackgroundHex: "E6D8BE", lightForegroundHex: "4C402F", darkBackgroundHex: "534A3C", darkForegroundHex: "E9DFC9"),
        .init(id: "focus", title: "Focus", subtitle: "Tight", tint: 0.50, turn: .curl, typographyStyle: .focus, lightBackgroundHex: "F3F2E7", lightForegroundHex: "201F14", darkBackgroundHex: "17160A", darkForegroundHex: "F0EBD1")
    ]

    private var slides: [OnboardingSlideSpec] {
        [
            .init(
                title: "What are you into?",
                subtitle: "Pick at least 2 so your feed feels like you."
            ),
            .init(
                title: "How should pages feel?",
                subtitle: "Pick the motion you like."
            ),
            .init(
                title: "Pick your vibe",
                subtitle: "Choose the look that feels right."
            )
        ]
    }

    private var canAdvance: Bool {
        switch currentSlideIndex {
        case 0: return selectedCategories.count >= 2
        case 1...2: return true
        default: return false
        }
    }

    private var isLastSlide: Bool {
        currentSlideIndex == slides.count - 1
    }

    private var selectedTone: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private var ctaBackground: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private var ctaForeground: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var baseBackground: Color {
        Color(uiColor: colorScheme == .dark ? .black : .systemGroupedBackground)
    }

    private var cardBackground: Color {
        Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemBackground)
    }

    private var rowBackground: Color {
        Color(uiColor: colorScheme == .dark ? .tertiarySystemBackground : .secondarySystemBackground)
    }

    private var rowBorder: Color {
        colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.08)
    }

    var body: some View {
        ZStack {
            baseBackground
                .ignoresSafeArea()

            Circle()
                .fill(selectedTone.opacity(colorScheme == .dark ? 0.08 : 0.06))
                .frame(width: 280, height: 280)
                .blur(radius: 24)
                .offset(x: ambientMotion ? 120 : -70, y: -250)

            Circle()
                .fill(selectedTone.opacity(colorScheme == .dark ? 0.05 : 0.04))
                .frame(width: 320, height: 320)
                .blur(radius: 30)
                .offset(x: ambientMotion ? -90 : 90, y: 330)

            VStack(spacing: 0) {
                topIntro
                    .padding(.horizontal, 24)
                    .padding(.top, 14)

                ZStack {
                    slideContent(for: currentSlideIndex, slide: slides[currentSlideIndex])
                        .id(currentSlideIndex)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: slideDirection > 0 ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: slideDirection > 0 ? .leading : .trailing).combined(with: .opacity)
                            )
                        )
                        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: currentSlideIndex)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 14)
                }
                .clipped()

                footer
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
        }
        .interactiveDismissDisabled(true)
        .onAppear {
            selectedCategories = settings.selectedCategories
            selectedPageTurnStyle = settings.pageTurnStyle
            selectedThemeID = detectThemeID(from: settings)

            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                logoPulsing = true
            }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                ambientMotion = true
            }
        }
    }

    private var topIntro: some View {
        VStack(spacing: 11) {
            AppIconArtwork()
                .frame(width: 72, height: 72)
                .scaleEffect(logoPulsing ? 1.01 : 0.96)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.13), radius: 18, y: 8)

            Text("Welcome to FactRead")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Let’s tune your feed in under a minute.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Text("\(currentSlideIndex + 1) of \(slides.count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            progressRow

            if currentSlideIndex > 0 {
                Button {
                    goBack()
                } label: {
                    Text("Back")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                if isLastSlide {
                    applyAndFinishOnboarding()
                } else {
                    goNext()
                }
            } label: {
                Text(isLastSlide ? "Start Reading" : "Continue")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(ctaForeground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(canAdvance ? ctaBackground : ctaBackground.opacity(0.35))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.12), radius: 12, y: 6)
            }
            .disabled(canAdvance == false)
        }
    }

    private var progressRow: some View {
        HStack(spacing: 7) {
            ForEach(0..<slides.count, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index <= currentSlideIndex ? selectedTone : selectedTone.opacity(0.18))
                    .frame(width: index == currentSlideIndex ? 28 : 18, height: 4)
                    .animation(.easeInOut(duration: 0.22), value: currentSlideIndex)
            }
        }
    }

    private func goNext() {
        guard currentSlideIndex < slides.count - 1 else { return }
        slideDirection = 1
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            currentSlideIndex += 1
        }
        HapticManager.shared.selection()
    }

    private func goBack() {
        guard currentSlideIndex > 0 else { return }
        slideDirection = -1
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            currentSlideIndex -= 1
        }
        HapticManager.shared.selection()
    }

    @ViewBuilder
    private func slideContent(for index: Int, slide: OnboardingSlideSpec) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(slide.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(slide.subtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Group {
                switch index {
                case 0:
                    categorySelectionGrid
                case 1:
                    singleChoiceList(options: PageTurnStyle.allCases, selection: $selectedPageTurnStyle, label: { $0 == .slide ? "Slide" : "Curl" })
                case 2:
                    themeCards
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(cardBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(rowBorder, lineWidth: 1)
            }

            Spacer(minLength: 0)
        }
    }

    private var categorySelectionGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(selectedCategories.count) picked • at least 2 needed")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(Fact.allCategories, id: \.self) { category in
                        categoryChip(for: category)
                    }
                }
            }
        }
    }

    private var themeCards: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(themePresets) { preset in
                let isSelected = preset.id == selectedThemeID
                Button {
                    selectedThemeID = preset.id
                    HapticManager.shared.selection()
                } label: {
                    VStack(spacing: 6) {
                        Text("Aa")
                            .font(sampleFont(for: preset.typographyStyle, size: 30))
                            .lineLimit(1)
                        Text(preset.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Text(preset.subtitle)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(foregroundColor(for: preset).opacity(0.82))
                    }
                    .foregroundStyle(foregroundColor(for: preset))
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(backgroundColor(for: preset))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? foregroundColor(for: preset).opacity(0.75) : rowBorder, lineWidth: isSelected ? 2 : 1)
                    }
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 8, y: 5)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func singleChoiceList<Value: Hashable>(
        options: [Value],
        selection: Binding<Value>,
        label: @escaping (Value) -> String
    ) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    premiumRow(isSelected: option == selection.wrappedValue) {
                        selection.wrappedValue = option
                        HapticManager.shared.selection()
                    } content: {
                        HStack(spacing: 10) {
                            Text(label(option))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            Image(systemName: option == selection.wrappedValue ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(option == selection.wrappedValue ? selectedTone : .secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func categoryChip(for category: String) -> some View {
        let isSelected = selectedCategories.contains(category)

        premiumRow(isSelected: isSelected) {
            toggle(category: category)
        } content: {
            HStack(spacing: 8) {
                Text(Fact.localizedCategory(category, language: .english))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? selectedTone : .secondary)
            }
        }
    }

    @ViewBuilder
    private func premiumRow<Content: View>(
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? rowBackground.opacity(colorScheme == .dark ? 0.90 : 1.0) : rowBackground.opacity(0.72))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? selectedTone.opacity(0.32) : rowBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func toggle(category: String) {
        if selectedCategories.contains(category) {
            if selectedCategories.count > 2 {
                selectedCategories.remove(category)
                HapticManager.shared.selection()
            }
        } else {
            selectedCategories.insert(category)
            HapticManager.shared.selection()
        }
    }

    private func applyAndFinishOnboarding() {
        settings.applySelectedCategories(selectedCategories)
        settings.appLanguage = .english
        settings.pageTurnStyle = selectedPageTurnStyle
        if let selectedTheme = themePresets.first(where: { $0.id == selectedThemeID }) {
            settings.categoryTintIntensity = selectedTheme.tint
            settings.readerTypographyStyle = selectedTheme.typographyStyle
        }
        settings.hasCompletedOnboarding = true
        HapticManager.shared.notification(.success)
        dismiss()
    }

    private func detectThemeID(from settings: AppSettings) -> String {
        if let exact = themePresets.first(where: {
            abs($0.tint - settings.categoryTintIntensity) < 0.07
            && $0.typographyStyle == settings.readerTypographyStyle
        }) {
            return exact.id
        }
        return "paper"
    }

    private func backgroundColor(for preset: OnboardingThemePreset) -> Color {
        Color(hex: colorScheme == .dark ? preset.darkBackgroundHex : preset.lightBackgroundHex)
    }

    private func foregroundColor(for preset: OnboardingThemePreset) -> Color {
        Color(hex: colorScheme == .dark ? preset.darkForegroundHex : preset.lightForegroundHex)
    }

    private func sampleFont(for style: ReaderTypographyStyle, size: CGFloat) -> Font {
        switch style {
        case .original:
            return .system(size: size, weight: .semibold, design: .default)
        case .quiet:
            return .system(size: size, weight: .medium, design: .serif)
        case .paper:
            return .system(size: size, weight: .semibold, design: .rounded)
        case .bold:
            return .system(size: size, weight: .bold, design: .rounded)
        case .calm:
            return .system(size: size, weight: .semibold, design: .serif)
        case .focus:
            return .system(size: size, weight: .semibold, design: .monospaced)
        }
    }
}

private struct OnboardingSlideSpec {
    let title: String
    let subtitle: String
}

private struct OnboardingThemePreset: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let tint: Double
    let turn: PageTurnStyle
    let typographyStyle: ReaderTypographyStyle
    let lightBackgroundHex: String
    let lightForegroundHex: String
    let darkBackgroundHex: String
    let darkForegroundHex: String
}

private struct AppIconArtwork: View {
    var body: some View {
        Group {
            if let image = appIconImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                    Image(systemName: "book.pages")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var appIconImage: UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let iconName = files.last
        else {
            return nil
        }

        return UIImage(named: iconName)
    }
}
