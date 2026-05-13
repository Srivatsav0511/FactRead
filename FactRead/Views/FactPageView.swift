import SwiftUI
import UIKit
import AudioToolbox

struct FactPageView: View {
    let page: FactViewModel.PageSnapshot
    let pageNumber: Int
    let palette: ReaderTheme.Palette
    let topSafeAreaInset: CGFloat
    let language: AppLanguage
    let readerFontScale: Double
    let readerTypographyStyle: ReaderTypographyStyle
    let categoryTintIntensity: Double
    let isPreview: Bool
    let pageTextAnimationsEnabled: Bool
    let hapticsEnabled: Bool
    let typingSoundEnabled: Bool
    private let contentLeadingInset: CGFloat = 18
    private let contentTrailingInset: CGFloat = 58
    @State private var selectedHighlight: HighlightSnippet?
    @State private var shouldAnimateTyping = false
    @State private var shouldStartBodyTyping = false

    var body: some View {
        GeometryReader { proxy in
            let metrics = metrics(for: proxy.size)
            let highlightSnippets = makeHighlightSnippets(source: page.lockedBody)
            let bodyRenderSize = metrics.bodySize * readerScale
            let attributedBody = makeAttributedBody(
                source: page.lockedBody,
                highlights: highlightSnippets,
                bodyFontSize: bodyRenderSize,
                bodyLineSpacing: metrics.bodyLineSpacing
            )

            ZStack(alignment: .topLeading) {
                palette.pageBackground

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                    Text(Fact.localizedCategory(page.lockedCategory, language: .english).uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(2.2)
                        .foregroundStyle(CategoryStyle.accent(for: page.lockedCategory, intensity: categoryTintIntensity))
                        .padding(.top, metrics.topPadding)

                    TypewriterText(
                        text: page.lockedTitle,
                        animationKey: "title:\(page.sourceFactID.uuidString):en",
                        enabled: shouldAnimateTyping,
                        isPreview: isPreview,
                        hapticsEnabled: hapticsEnabled,
                        playTypingSound: typingSoundEnabled,
                        approxLineLength: 34,
                        targetDuration: .milliseconds(1600),
                        onCompletion: {
                            shouldStartBodyTyping = true
                        }
                    )
                    .font(titleFont(size: metrics.titleSize * readerScale))
                    .foregroundStyle(palette.inkPrimary)
                    .lineSpacing(metrics.titleLineSpacing)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, metrics.titleTopSpacing)
                        .layoutPriority(2)

                    TypewriterBodyText(
                        attributedText: attributedBody,
                        plainText: page.lockedBody,
                        animationKey: "body:\(page.sourceFactID.uuidString):en",
                        enabled: shouldAnimateTyping,
                        isPreview: isPreview,
                        hapticsEnabled: hapticsEnabled,
                        playTypingSound: typingSoundEnabled,
                        approxLineLength: 92,
                        startWhen: shouldStartBodyTyping,
                        onOpenURL: { url in
                            guard let index = highlightIndex(from: url) else { return }
                            guard highlightSnippets.indices.contains(index) else { return }
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.94)) {
                                selectedHighlight = highlightSnippets[index]
                            }
                        }
                    )
                    .font(bodyFont(size: metrics.bodySize * readerScale))
                    .foregroundStyle(palette.inkPrimary)
                    .lineSpacing(metrics.bodyLineSpacing)
                    .multilineTextAlignment(bodyTextAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, metrics.bodyTopSpacing)
                    .layoutPriority(1)

                    if let selectedHighlight {
                        HighlightContextCard(
                            snippet: selectedHighlight,
                            palette: palette,
                            onClose: {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    self.selectedHighlight = nil
                                }
                            }
                        )
                        .padding(.top, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Spacer(minLength: 18)
                }
                .padding(.leading, contentLeadingInset)
                .padding(.trailing, contentTrailingInset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(minHeight: proxy.size.height - ReaderTheme.bottomPadding - 10, alignment: .topLeading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .contentShape(Rectangle())

                Text(pageLabel)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(palette.inkSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 14)
                    .padding(.bottom, max(8, proxy.safeAreaInsets.bottom + 2))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            configureAnimationState()
        }
        .onChange(of: page.id) { _, _ in
            selectedHighlight = nil
            configureAnimationState()
        }
        .onChange(of: isPreview) { _, _ in
            configureAnimationState()
        }
        .onChange(of: pageTextAnimationsEnabled) { _, _ in
            configureAnimationState()
        }
    }

    private var pageLabel: String {
        "Page \(pageNumber)"
    }

    private var readerScale: CGFloat {
        CGFloat(min(max(readerFontScale, 0.86), 1.24))
    }

    private var pageVisitKey: String {
        "fact:\(page.sourceFactID.uuidString):en"
    }

    private func configureAnimationState() {
        let canAnimate = pageTextAnimationsEnabled && isPreview == false
        guard canAnimate else {
            shouldAnimateTyping = false
            shouldStartBodyTyping = true
            return
        }

        if PageTextAnimationMemory.hasPlayed(key: pageVisitKey) {
            // If we already kicked off animation for this page in the current activation cycle,
            // keep the running state instead of forcing an immediate jump to the final text.
            if shouldAnimateTyping, shouldStartBodyTyping == false {
                return
            }
            shouldAnimateTyping = false
            shouldStartBodyTyping = true
            return
        }

        PageTextAnimationMemory.markPlayed(key: pageVisitKey)
        shouldAnimateTyping = true
        shouldStartBodyTyping = false
    }

    private func metrics(for size: CGSize) -> TypographyMetrics {
        let compact = size.height < 760
        let bodyCount = page.lockedBody.count
        let titleCount = page.lockedTitle.count
        // ScrollView content already accounts for top safe area.
        // Keep a small optical offset to avoid double top spacing.
        let headerTopPadding: CGFloat = compact ? 6 : 8

        // Premium typography, but adapt slightly to always fit on one page.
        var titleSize: CGFloat = compact ? 28 : 32
        var bodySize: CGFloat = compact ? 17.2 : 18.4
        let titleLineSpacing: CGFloat = compact ? 1 : 2
        var bodyLineSpacing: CGFloat = compact ? 7.6 : 8.4
        var bodyTopSpacing: CGFloat = compact ? 14 : 18

        if titleCount > 56 { titleSize -= 2 }
        if titleCount > 78 { titleSize -= 2 }

        if bodyCount > 650 {
            bodySize -= 0.6
            bodyLineSpacing -= 0.4
            bodyTopSpacing -= 1
        }
        if bodyCount > 820 {
            bodySize -= 0.8
            bodyLineSpacing -= 0.6
            titleSize -= 1
        }

        return TypographyMetrics(
            topPadding: headerTopPadding,
            titleSize: max(24, titleSize),
            bodySize: max(16, bodySize),
            titleLineSpacing: max(0, titleLineSpacing),
            bodyLineSpacing: max(6.4, bodyLineSpacing),
            titleTopSpacing: compact ? 10 : 14,
            bodyTopSpacing: max(12, bodyTopSpacing)
        )
    }

    private func makeAttributedBody(
        source: String,
        highlights: [HighlightSnippet],
        bodyFontSize: CGFloat,
        bodyLineSpacing: CGFloat
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakStrategy = [.pushOut]
        paragraph.hyphenationFactor = 0.25
        paragraph.alignment = usesJustifiedBody ? .justified : .natural
        paragraph.lineSpacing = bodyLineSpacing
        let baseString = NSMutableAttributedString(
            string: source,
            attributes: [
                .paragraphStyle: paragraph,
                .font: bodyUIFont(size: bodyFontSize),
                .foregroundColor: UIColor(palette.inkPrimary)
            ]
        )

        guard highlights.isEmpty == false else {
            return baseString
        }

        let nsSource = source as NSString
        let highlightForeground = UIColor(palette.inkPrimary)
        let accent = UIColor(CategoryStyle.accent(for: page.lockedCategory, intensity: categoryTintIntensity))
        let highlightBackground = accent.withAlphaComponent(palette.isDark ? 0.38 : 0.23)
        let strokeColor = accent.withAlphaComponent(palette.isDark ? 0.56 : 0.40)

        for (index, snippet) in highlights.enumerated() {
            var searchRange = NSRange(location: 0, length: nsSource.length)
            let needle = snippet.phrase

            while true {
                let found = nsSource.range(
                    of: needle,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchRange
                )
                guard found.location != NSNotFound else { break }

                baseString.addAttributes(
                    [
                        .foregroundColor: highlightForeground,
                        .backgroundColor: highlightBackground,
                        .underlineColor: strokeColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .link: URL(string: "factbook-highlight://\(index)") as Any
                    ],
                    range: found
                )

                let nextLocation = found.location + found.length
                guard nextLocation < nsSource.length else { break }
                searchRange = NSRange(location: nextLocation, length: nsSource.length - nextLocation)
            }
        }

        return baseString
    }

    private var usesJustifiedBody: Bool {
        switch readerTypographyStyle {
        case .quiet, .focus:
            return true
        case .original, .paper, .bold, .calm:
            return false
        }
    }

    private var bodyTextAlignment: TextAlignment {
        usesJustifiedBody ? .leading : .leading
    }

    private func titleFont(size: CGFloat) -> Font {
        switch readerTypographyStyle {
        case .original:
            return .system(size: size, weight: .bold, design: .serif)
        case .quiet:
            return resolvedCustomFont(
                candidates: ["PublicoText-Roman", "PublicoText-Regular", "Publico"],
                size: size,
                fallback: .system(size: size, weight: .semibold, design: .serif)
            )
        case .paper:
            return resolvedCustomFont(
                candidates: ["Charter-Roman", "Charter"],
                size: size,
                fallback: .system(size: size, weight: .semibold, design: .serif)
            )
        case .bold:
            return .system(size: size, weight: .bold, design: .default)
        case .calm:
            return resolvedCustomFont(
                candidates: ["Canela-Regular", "Canela"],
                size: size,
                fallback: .system(size: size, weight: .semibold, design: .serif)
            )
        case .focus:
            return resolvedCustomFont(
                candidates: ["ProximaNova-Regular", "Proxima Nova"],
                size: size,
                fallback: .system(size: size, weight: .semibold, design: .default)
            )
        }
    }

    private func bodyFont(size: CGFloat) -> Font {
        switch readerTypographyStyle {
        case .original:
            return .system(size: size, weight: .regular, design: .default)
        case .quiet:
            return resolvedCustomFont(
                candidates: ["PublicoText-Roman", "PublicoText-Regular", "Publico"],
                size: size,
                fallback: .system(size: size, weight: .regular, design: .serif)
            )
        case .paper:
            return resolvedCustomFont(
                candidates: ["Charter-Roman", "Charter"],
                size: size,
                fallback: .system(size: size, weight: .regular, design: .serif)
            )
        case .bold:
            return .system(size: size, weight: .bold, design: .default)
        case .calm:
            return resolvedCustomFont(
                candidates: ["Canela-Regular", "Canela"],
                size: size,
                fallback: .system(size: size, weight: .regular, design: .serif)
            )
        case .focus:
            return resolvedCustomFont(
                candidates: ["ProximaNova-Regular", "Proxima Nova"],
                size: size,
                fallback: .system(size: size, weight: .regular, design: .default)
            )
        }
    }

    private func bodyUIFont(size: CGFloat) -> UIFont {
        switch readerTypographyStyle {
        case .original:
            return .systemFont(ofSize: size, weight: .regular)
        case .quiet:
            return resolvedUIFont(
                candidates: ["PublicoText-Roman", "PublicoText-Regular", "Publico"],
                size: size,
                fallback: .systemFont(ofSize: size, weight: .regular)
            )
        case .paper:
            return resolvedUIFont(
                candidates: ["Charter-Roman", "Charter"],
                size: size,
                fallback: .systemFont(ofSize: size, weight: .regular)
            )
        case .bold:
            return .systemFont(ofSize: size, weight: .bold)
        case .calm:
            return resolvedUIFont(
                candidates: ["Canela-Regular", "Canela"],
                size: size,
                fallback: .systemFont(ofSize: size, weight: .regular)
            )
        case .focus:
            return resolvedUIFont(
                candidates: ["ProximaNova-Regular", "Proxima Nova"],
                size: size,
                fallback: .systemFont(ofSize: size, weight: .regular)
            )
        }
    }

    private func resolvedCustomFont(candidates: [String], size: CGFloat, fallback: Font) -> Font {
        for name in candidates {
            if UIFont(name: name, size: size) != nil {
                return .custom(name, size: size, relativeTo: .body)
            }
        }
        return fallback
    }

    private func resolvedUIFont(candidates: [String], size: CGFloat, fallback: UIFont) -> UIFont {
        for name in candidates {
            if let font = UIFont(name: name, size: size) {
                return font
            }
        }
        return fallback
    }

    private func makeHighlightSnippets(source: String) -> [HighlightSnippet] {
        let phrases = page.lockedHighlights
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
        guard phrases.isEmpty == false else { return [] }

        var seen = Set<String>()
        var result: [HighlightSnippet] = []

        for phrase in phrases {
            let key = phrase.lowercased()
            guard seen.contains(key) == false else { continue }
            guard source.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { continue }

            seen.insert(key)
            let context = contextSentence(for: phrase, in: source)
            result.append(
                HighlightSnippet(
                    id: key,
                    phrase: phrase,
                    context: context
                )
            )
        }

        return result
    }

    private func contextSentence(for phrase: String, in source: String) -> String {
        let nsSource = source as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)

        var matchedRange: NSRange?
        nsSource.enumerateSubstrings(in: fullRange, options: [.bySentences, .substringNotRequired]) { _, sentenceRange, _, stop in
            let sentence = nsSource.substring(with: sentenceRange)
            if sentence.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                matchedRange = sentenceRange
                stop.pointee = true
            }
        }

        if let matchedRange {
            return nsSource.substring(with: matchedRange).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return source
    }

    private func highlightIndex(from url: URL) -> Int? {
        guard url.scheme == "factbook-highlight" else { return nil }
        if let host = url.host, let idx = Int(host) {
            return idx
        }
        let token = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return Int(token)
    }
}

private struct SelectableAttributedTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    var onOpenURL: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenURL: onOpenURL)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.delegate = context.coordinator
        view.dataDetectorTypes = []
        view.tintColor = .systemBlue
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.attributedText != attributedText {
            uiView.attributedText = attributedText
        }
        context.coordinator.onOpenURL = onOpenURL
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let screenWidth = uiView.window?.windowScene?.screen.bounds.width
            ?? (uiView.bounds.width > 0 ? uiView.bounds.width : 390)
        let targetWidth = proposal.width ?? screenWidth
        let fit = uiView.sizeThatFits(CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: targetWidth, height: fit.height)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpenURL: ((URL) -> Void)?

        init(onOpenURL: ((URL) -> Void)?) {
            self.onOpenURL = onOpenURL
        }

        @available(iOS 17.0, *)
        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            guard case let .link(url) = textItem.content else {
                return defaultAction
            }
            return UIAction { [weak self] _ in
                self?.onOpenURL?(url)
            }
        }
    }
}

private struct TypographyMetrics {
    let topPadding: CGFloat
    let titleSize: CGFloat
    let bodySize: CGFloat
    let titleLineSpacing: CGFloat
    let bodyLineSpacing: CGFloat
    let titleTopSpacing: CGFloat
    let bodyTopSpacing: CGFloat
}

private struct HighlightSnippet: Equatable, Identifiable {
    let id: String
    let phrase: String
    let context: String
}

private struct HighlightContextCard: View {
    let snippet: HighlightSnippet
    let palette: ReaderTheme.Palette
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(snippet.phrase)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .lineLimit(1)
                Spacer(minLength: 10)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)
            }

            Text(snippet.context)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.inkSecondary.opacity(0.92))
                .lineLimit(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlassCard(cornerRadius: 14, isDark: palette.isDark)
    }
}

private struct PageTextEntranceModifier: ViewModifier {
    let enabled: Bool
    let isPreview: Bool
    let animationKey: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasAnimatedIn = false

    func body(content: Content) -> some View {
        content
            .opacity(visualOpacity)
            .scaleEffect(visualScale, anchor: .center)
            .blur(radius: visualBlur)
            .onAppear {
                guard enabled, isPreview == false, reduceMotion == false else {
                    hasAnimatedIn = true
                    return
                }
                hasAnimatedIn = false
                withAnimation(.spring(response: 0.42, dampingFraction: 0.95)) {
                    hasAnimatedIn = true
                }
            }
    }

    private var visualOpacity: Double {
        guard enabled, isPreview == false, reduceMotion == false else { return 1 }
        return hasAnimatedIn ? 1 : 0
    }

    private var visualScale: CGFloat {
        guard enabled, isPreview == false, reduceMotion == false else { return 1 }
        return hasAnimatedIn ? 1 : 0.98
    }

    private var visualBlur: CGFloat {
        guard enabled, isPreview == false, reduceMotion == false else { return 0 }
        return hasAnimatedIn ? 0 : 8
    }
}

private struct TypewriterText: View {
    let fullText: String
    let animationKey: String?
    private let characters: [Character]
    let enabled: Bool
    let isPreview: Bool
    let hapticsEnabled: Bool
    let playTypingSound: Bool
    let approxLineLength: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleCount: Int = .max
    @State private var task: Task<Void, Never>?
    @State private var caretTask: Task<Void, Never>?
    @State private var reportedCompletion = false
    @State private var isAnimating = false
    @State private var isCaretVisible = false
    var targetDuration: Duration = .milliseconds(1200)
    var onCompletion: (() -> Void)?

    init(
        text: String,
        animationKey: String? = nil,
        enabled: Bool,
        isPreview: Bool,
        hapticsEnabled: Bool,
        playTypingSound: Bool,
        approxLineLength: Int,
        targetDuration: Duration = .milliseconds(1200),
        onCompletion: (() -> Void)? = nil
    ) {
        self.fullText = text
        self.animationKey = animationKey
        self.characters = Array(text)
        self.enabled = enabled
        self.isPreview = isPreview
        self.hapticsEnabled = hapticsEnabled
        self.playTypingSound = playTypingSound
        self.approxLineLength = approxLineLength
        self.targetDuration = targetDuration
        self.onCompletion = onCompletion
    }

    var body: some View {
        Text(displayText + caretSuffix)
            .animation(nil, value: visibleCount)
            .onAppear {
                runOrComplete()
            }
            .onChange(of: enabled) { _, _ in
                runOrComplete()
            }
            .onChange(of: isPreview) { _, _ in
                runOrComplete()
            }
            .onChange(of: animationKey) { _, _ in
                runOrComplete()
            }
            .onDisappear {
                task?.cancel()
                task = nil
                stopCaretBlink()
            }
    }

    private var displayText: String {
        if visibleCount == .max { return fullText }
        let clamped = min(max(visibleCount, 0), characters.count)
        return String(characters.prefix(clamped))
    }

    private var caretSuffix: String {
        guard enabled, isPreview == false, reduceMotion == false, isAnimating, isCaretVisible else { return "" }
        return "▍"
    }

    private func durationMs(_ duration: Duration) -> Int {
        let c = duration.components
        let seconds = Double(c.seconds) + (Double(c.attoseconds) / 1_000_000_000_000_000_000.0)
        return Int(seconds * 1000)
    }

    private func reportCompletionIfNeeded() {
        guard reportedCompletion == false else { return }
        reportedCompletion = true
        onCompletion?()
    }

    private func runOrComplete() {
        reportedCompletion = false
        task?.cancel()
        task = nil

        guard enabled, isPreview == false, reduceMotion == false else {
            visibleCount = .max
            isAnimating = false
            stopCaretBlink()
            reportCompletionIfNeeded()
            return
        }

        visibleCount = 0
        isAnimating = true
        startCaretBlink()
        task = Task {
            let len = characters.count
            guard len > 0 else {
                await MainActor.run {
                    visibleCount = .max
                    isAnimating = false
                    stopCaretBlink()
                    reportCompletionIfNeeded()
                }
                return
            }

            let checkpoints = lineCheckpoints()
            let stepCount = max(1, checkpoints.count)
            let targetMs = max(820, durationMs(targetDuration))
            let baseTickMs = max(26.0, Double(targetMs) / Double(stepCount))

            for (idx, checkpoint) in checkpoints.enumerated() {
                if Task.isCancelled { return }
                await MainActor.run {
                    visibleCount = checkpoint
                    TypingFeedbackEngine.tick(playSound: playTypingSound, hapticsEnabled: hapticsEnabled)
                }

                let progress = Double(idx + 1) / Double(stepCount)
                let taper = 0.84 + (pow(1 - progress, 1.25) * 0.44)
                let tickMs = Int(max(28, min(132, baseTickMs * taper)))
                try? await Task.sleep(for: .milliseconds(tickMs))
            }

            if Task.isCancelled == false {
                await MainActor.run {
                    visibleCount = .max
                    isAnimating = false
                    stopCaretBlink()
                    reportCompletionIfNeeded()
                }
            }
        }
    }

    private func lineCheckpoints() -> [Int] {
        let len = characters.count
        guard len > 0 else { return [0] }
        let target = max(8, approxLineLength / 3)
        var points: [Int] = []
        var index = 0

        while index < len {
            let hardStop = min(len, index + target)
            var stop = hardStop

            if hardStop < len {
                var j = hardStop
                while j > index {
                    if characters[j - 1].isWhitespace || characters[j - 1].isNewline {
                        stop = j
                        break
                    }
                    j -= 1
                }
            }

            if stop <= index {
                stop = min(len, index + target)
            }

            points.append(stop)
            index = stop
        }

        if points.last != len {
            points.append(len)
        }
        return points
    }

    private func startCaretBlink() {
        caretTask?.cancel()
        caretTask = Task {
            var visible = true
            await MainActor.run {
                isCaretVisible = visible
            }
            while Task.isCancelled == false {
                try? await Task.sleep(for: .milliseconds(240))
                visible.toggle()
                await MainActor.run {
                    isCaretVisible = visible
                }
            }
        }
    }

    private func stopCaretBlink() {
        caretTask?.cancel()
        caretTask = nil
        isCaretVisible = false
    }
}

private struct TypewriterBodyText: View {
    let attributedText: NSAttributedString
    let plainText: String
    let animationKey: String?
    let enabled: Bool
    let isPreview: Bool
    let hapticsEnabled: Bool
    let playTypingSound: Bool
    let approxLineLength: Int
    let startWhen: Bool
    var onOpenURL: ((URL) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didFinishTypewriter = false
    
    private var bodyDuration: Duration {
        let clamped = min(11_000, max(5_000, plainText.count * 14))
        return .milliseconds(clamped)
    }

    var body: some View {
        if startWhen == false {
            // Fallback: never keep body blank while waiting for title animation callbacks.
            SelectableAttributedTextView(
                attributedText: attributedText,
                onOpenURL: onOpenURL
            )
            .onAppear {
                didFinishTypewriter = false
            }
            .onChange(of: enabled) { _, newValue in
                if newValue {
                    didFinishTypewriter = false
                }
            }
        } else
        if enabled, isPreview == false, reduceMotion == false, didFinishTypewriter == false {
            TypewriterText(
                text: plainText,
                animationKey: animationKey,
                enabled: enabled,
                isPreview: isPreview,
                hapticsEnabled: hapticsEnabled,
                playTypingSound: playTypingSound,
                approxLineLength: approxLineLength,
                targetDuration: bodyDuration,
                onCompletion: {
                    withAnimation(.easeOut(duration: 0.16)) {
                        didFinishTypewriter = true
                    }
                }
            )
        } else {
            SelectableAttributedTextView(
                attributedText: attributedText,
                onOpenURL: onOpenURL
            )
                .onAppear {
                    didFinishTypewriter = true
                }
                .onChange(of: animationKey) { _, _ in
                    didFinishTypewriter = false
                }
                .onChange(of: enabled) { _, newValue in
                    if newValue {
                        didFinishTypewriter = false
                    }
                }
                .onChange(of: startWhen) { _, newValue in
                    if newValue == false {
                        didFinishTypewriter = false
                    }
                }
        }
    }
}

@MainActor
private enum TypingFeedbackEngine {
    private static var lastTickAt: CFTimeInterval = 0
    private static let minTickInterval: CFTimeInterval = 0.065

    static func tick(playSound: Bool, hapticsEnabled: Bool) {
        let now = CACurrentMediaTime()
        guard now - lastTickAt >= minTickInterval else { return }
        lastTickAt = now
        if playSound {
            let soundID: SystemSoundID = (HapticManager.shared.themeMode == .dark) ? 1105 : 1104
            AudioServicesPlaySystemSound(soundID)
        }
        if hapticsEnabled {
            HapticManager.shared.selection()
        }
    }
}

@MainActor
private enum PageTextAnimationMemory {
    private static var playedKeys: Set<String> = []

    static func hasPlayed(key: String) -> Bool {
        playedKeys.contains(key)
    }

    static func markPlayed(key: String) {
        playedKeys.insert(key)
    }
}
