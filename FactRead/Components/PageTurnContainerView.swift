import SwiftUI

struct PageFlipContainerView: View {
    let facts: [Fact]
    @Binding var index: Int
    let palette: ReaderTheme.Palette
    let topSafeAreaInset: CGFloat
    let hapticsEnabled: Bool
    let reduceMotionEnabled: Bool
    let appLanguage: AppLanguage
    let tuning: PageFlipTuning
    let onDoubleTapCurrent: (Fact) -> Void
    let categoryTintIntensity: Double
    let pageTextAnimationsEnabled: Bool
    let isDailyLimitReached: Bool
    let controlsVisible: Bool
    let canAccessFact: (Fact) -> Bool
    let readerFontScale: Double
    let onReaderTap: () -> Void
    let onDailyLimitHit: () -> Void

    @State private var gesture = PageFlipGestureController()
    @State private var physics: PageFlipPhysicsModel
    @State private var isSettling = false
    @State private var haptics = PageFlipHaptics()
    @State private var bookmarkToast: BookmarkToastState?
    @State private var lastSampleTime: Date?
    @State private var lastSampleTranslation: CGFloat = 0
    @State private var recentVelocity: CGFloat = 0

    init(
        facts: [Fact],
        index: Binding<Int>,
        palette: ReaderTheme.Palette,
        topSafeAreaInset: CGFloat,
        hapticsEnabled: Bool,
        reduceMotionEnabled: Bool,
        appLanguage: AppLanguage,
        tuning: PageFlipTuning,
        onDoubleTapCurrent: @escaping (Fact) -> Void,
        categoryTintIntensity: Double,
        pageTextAnimationsEnabled: Bool,
        isDailyLimitReached: Bool,
        controlsVisible: Bool,
        canAccessFact: @escaping (Fact) -> Bool,
        readerFontScale: Double,
        onReaderTap: @escaping () -> Void,
        onDailyLimitHit: @escaping () -> Void
    ) {
        self.facts = facts
        self._index = index
        self.palette = palette
        self.topSafeAreaInset = topSafeAreaInset
        self.hapticsEnabled = hapticsEnabled
        self.reduceMotionEnabled = reduceMotionEnabled
        self.appLanguage = appLanguage
        self.tuning = tuning
        self.onDoubleTapCurrent = onDoubleTapCurrent
        self.categoryTintIntensity = categoryTintIntensity
        self.pageTextAnimationsEnabled = pageTextAnimationsEnabled
        self.isDailyLimitReached = isDailyLimitReached
        self.controlsVisible = controlsVisible
        self.canAccessFact = canAccessFact
        self.readerFontScale = readerFontScale
        self.onReaderTap = onReaderTap
        self.onDailyLimitHit = onDailyLimitHit
        _physics = State(initialValue: PageFlipPhysicsModel(tuning: tuning))
    }

    private var currentFact: Fact? {
        guard facts.indices.contains(index) else { return nil }
        return facts[index]
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)

            ZStack {
                if let currentFact {
                    PageFlipRenderer(
                        palette: palette,
                        gesture: gesture,
                        tuning: tuning,
                        reduceMotionEnabled: reduceMotionEnabled,
                        currentPage: AnyView(pageView(for: currentFact, pageIndex: index, isPreview: false)),
                        underlyingPage: AnyView(underlyingView)
                    )
                }

                bookmarkToastOverlay
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                TapGesture(count: 2).onEnded {
                    guard let currentFact, isSettling == false else { return }
                    onDoubleTapCurrent(currentFact)
                    showBookmarkToast(isSaved: currentFact.isBookmarked)
                }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .onChanged { value in
                        handleDragChanged(value, size: proxy.size)
                    }
                    .onEnded { value in
                        handleDragEnded(value, width: width)
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 1).onEnded {
                    onReaderTap()
                }
            )
            .onAppear {
                haptics.prepare()
            }
        }
    }

    @ViewBuilder
    private var underlyingView: some View {
        if let targetFact {
            pageView(for: targetFact, pageIndex: targetIndex, isPreview: true)
        } else if let currentFact {
            pageView(for: currentFact, pageIndex: index, isPreview: false)
        } else {
            Color.clear
        }
    }

    private var targetIndex: Int {
        guard gesture.isActive else { return index }
        switch gesture.direction {
        case .next:
            return min(index + 1, facts.count - 1)
        case .previous:
            return max(index - 1, 0)
        }
    }

    private var targetFact: Fact? {
        guard facts.indices.contains(targetIndex), targetIndex != index else { return nil }
        return facts[targetIndex]
    }

    private func pageView(for fact: Fact, pageIndex: Int, isPreview: Bool) -> some View {
        let pageSnapshot = FactViewModel.PageSnapshot(
            id: fact.id,
            sourceFactID: fact.id,
            fact: fact,
            lockedCategory: fact.category,
            lockedTitle: fact.title,
            lockedBody: fact.body,
            lockedHighlights: fact.highlightedPhrases ?? []
        )
        return FactPageView(
            page: pageSnapshot,
            pageNumber: pageIndex + 1,
            palette: palette,
            topSafeAreaInset: topSafeAreaInset,
            language: appLanguage,
            readerFontScale: readerFontScale,
            readerTypographyStyle: .original,
            categoryTintIntensity: categoryTintIntensity,
            isPreview: isPreview,
            pageTextAnimationsEnabled: shouldAnimateText(for: fact, isPreview: isPreview),
            hapticsEnabled: hapticsEnabled,
            typingSoundEnabled: true
        )
    }

    private func handleDragChanged(_ value: DragGesture.Value, size: CGSize) {
        let width = max(size.width, 1)
        guard isSettling == false, facts.isEmpty == false else { return }

        let dx = value.translation.width
        let absX = abs(dx)
        let absY = abs(value.translation.height)

        if gesture.intentRejected { return }

        if gesture.intentResolved == false {
            if shouldIgnoreDragStart(value.startLocation, size: size) {
                gesture.intentRejected = true
                return
            }
            let edgeDistanceLeft = value.startLocation.x
            let edgeDistanceRight = max(0, width - value.startLocation.x)
            let nearestEdge = min(edgeDistanceLeft, edgeDistanceRight)
            let normalizedEdge = 1 - min(nearestEdge / max(width * 0.45, 1), 1)
            let edgeEngagement = 0.58 + (0.42 * normalizedEdge)

            let requiredIntentDistance: CGFloat = nearestEdge <= tuning.edgeActivationWidth ? 6 : 14
            if absX < requiredIntentDistance { return }
            if absY > absX + 8 {
                gesture.intentRejected = true
                return
            }

            if dx < 0, index < facts.count - 1 {
                gesture.begin(at: value.startLocation, direction: .next, edgeEngagement: edgeEngagement)
                haptics.prepare()
                haptics.resetThreshold()
            } else if dx > 0, index > 0 {
                gesture.begin(at: value.startLocation, direction: .previous, edgeEngagement: edgeEngagement)
                haptics.prepare()
                haptics.resetThreshold()
            } else {
                gesture.intentRejected = true
                return
            }

            lastSampleTime = value.time
            lastSampleTranslation = abs(dx)
            recentVelocity = 0
        }

        guard gesture.phase == .tracking else { return }

        if (dx * gesture.dragSign) < 0 {
            gesture.update(translation: 0, width: width, velocityNormalized: 0, physics: physics)
            return
        }

        updateVelocity(using: value)
        let velocityNorm = min(max(recentVelocity / max(width, 1), 0), 2)
        gesture.update(
            translation: abs(dx),
            width: width,
            velocityNormalized: velocityNorm,
            physics: physics
        )

        if gesture.progress >= tuning.hapticTriggerThreshold {
            if gesture.commitCrossed == false {
                gesture.commitCrossed = true
                haptics.fireThresholdIfNeeded(enabled: hapticsEnabled)
            }
        } else if gesture.progress <= (tuning.hapticTriggerThreshold - tuning.hapticThresholdHysteresis) {
            gesture.commitCrossed = false
            haptics.resetThreshold()
        }
    }

    private func shouldIgnoreDragStart(_ start: CGPoint, size: CGSize) -> Bool {
        let bottomPlayer = CGRect(
            x: 0,
            y: max(size.height - 170, 0),
            width: size.width,
            height: 170
        )
        if bottomPlayer.contains(start) {
            return true
        }

        guard controlsVisible else { return false }
        let topRightUnsafe = CGRect(
            x: max(size.width - 86, 0),
            y: 0,
            width: 86,
            height: max(topSafeAreaInset + 64, 84)
        )
        let trailingControls = CGRect(
            x: max(size.width - 120, 0),
            y: max(size.height - 250, 0),
            width: 120,
            height: 250
        )
        return topRightUnsafe.contains(start) || trailingControls.contains(start)
    }

    private func handleDragEnded(_ value: DragGesture.Value, width: CGFloat) {
        guard gesture.phase == .tracking, isSettling == false else {
            gesture.reset()
            return
        }

        isSettling = true

        let signedCurrent = gesture.dragSign * value.translation.width
        let signedPredicted = gesture.dragSign * value.predictedEndTranslation.width
        let dragProgress = min(max(abs(signedCurrent) / max(width, 1), 0), 1)
        let predictedProgress = min(max(abs(signedPredicted) / max(width, 1), 0), 1)
        let velocityNormalized = max(0, (signedPredicted - signedCurrent) / max(width, 1))

        let decision = physics.releaseDecision(
            dragProgress: dragProgress,
            predictedProgress: predictedProgress,
            velocityNormalized: velocityNormalized,
            edgeEngagement: gesture.edgeEngagement
        )

        let blockedByDailyLimit = gesture.direction == .next && nextDirectionBlockedByDailyLimit()
        let shouldCommit = decision.shouldCommit && canCommit(for: gesture.direction)

        if shouldCommit {
            withAnimation(tuning.completionSpring) {
                gesture.beginCommitSettle(width: width, physics: physics)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + decision.duration) {
                applyCommittedTurn(for: gesture.direction)
                gesture.reset()
                isSettling = false
                haptics.fireCompletion(enabled: hapticsEnabled)
            }
            return
        }

        if blockedByDailyLimit {
            onDailyLimitHit()
        }

        withAnimation(tuning.cancelSpring) {
            gesture.beginCancelSettle(width: width, physics: physics)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + decision.duration) {
            gesture.reset()
            isSettling = false
            haptics.fireCancel(enabled: hapticsEnabled)
        }
    }

    private func updateVelocity(using value: DragGesture.Value) {
        guard let lastTime = lastSampleTime else {
            lastSampleTime = value.time
            lastSampleTranslation = abs(value.translation.width)
            return
        }

        let dt = value.time.timeIntervalSince(lastTime)
        guard dt > 0 else { return }

        let distance = abs(value.translation.width) - lastSampleTranslation
        let instantaneous = distance / CGFloat(dt)
        recentVelocity = (recentVelocity * 0.62) + (max(0, instantaneous) * 0.38)
        lastSampleTime = value.time
        lastSampleTranslation = abs(value.translation.width)
    }

    private func canCommit(for direction: PageFlipDirection) -> Bool {
        switch direction {
        case .next:
            guard index < facts.count - 1 else { return false }
            let nextIndex = index + 1
            guard facts.indices.contains(nextIndex) else { return false }
            return canAccessFact(facts[nextIndex])
        case .previous: return index > 0
        }
    }

    private func nextDirectionBlockedByDailyLimit() -> Bool {
        guard index < facts.count - 1 else { return false }
        let nextIndex = index + 1
        guard facts.indices.contains(nextIndex) else { return false }
        return canAccessFact(facts[nextIndex]) == false
    }

    private func applyCommittedTurn(for direction: PageFlipDirection) {
        switch direction {
        case .next:
            index = min(index + 1, facts.count - 1)
        case .previous:
            index = max(index - 1, 0)
        }
    }

    private func shouldAnimateText(for _: Fact, isPreview: Bool) -> Bool {
        guard isPreview == false else { return false }
        guard pageTextAnimationsEnabled else { return false }
        return true
    }

    @ViewBuilder
    private var bookmarkToastOverlay: some View {
        if let toast = bookmarkToast {
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    Image(systemName: toast.isSaved ? "bookmark.fill" : "bookmark.slash")
                        .font(.system(size: 15, weight: .semibold))
                    Text(bookmarkToastText(isSaved: toast.isSaved))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .liquidGlassCard(cornerRadius: 999, isDark: palette.isDark)
                .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
                .padding(.bottom, 22)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    private func showBookmarkToast(isSaved: Bool) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
            bookmarkToast = BookmarkToastState(isSaved: isSaved)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeOut(duration: 0.22)) {
                bookmarkToast = nil
            }
        }
    }

    private func bookmarkToastText(isSaved: Bool) -> String {
        isSaved ? "Saved" : "Removed"
    }
}

private struct BookmarkToastState: Equatable {
    let isSaved: Bool
}

typealias PageTurnContainerView = PageFlipContainerView
