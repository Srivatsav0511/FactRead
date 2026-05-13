import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(FactViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings

    @State private var isSettingsPresented = false
    @State private var isQuickCustomizePresented = false
    @State private var isReaderAppearancePresented = false
    @State private var isOnboardingPresented = false
    @State private var reloadTask: Task<Void, Never>?
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var reminderSyncTask: Task<Void, Never>?
    @State private var bookmarkToast: BookmarkToastState?
    @State private var bookmarkToastTask: Task<Void, Never>?
    @State private var showReaderChrome = false
    @State private var chromeAutoHideTask: Task<Void, Never>?
    @State private var narrator = FactNarrationManager.shared
    @State private var hasInitializedSession = false
    @State private var isNarrationPlayerExpanded = false
    @State private var isNarrationPlayerDismissed = false
    @State private var showNarrationPlayerChrome = false
    @State private var categorySyncTask: Task<Void, Never>?
    @State private var hasPendingCategorySync = false
    @State private var loadingWatchdogTask: Task<Void, Never>?
    @State private var suppressTextAnimations = false
    @State private var suppressTextAnimationsTask: Task<Void, Never>?
    @State private var isSplashVisible = true
    @State private var splashDismissTask: Task<Void, Never>?

    private var resolvedThemeMode: ReaderThemeMode {
        if settings.followsSystemTheme {
            return colorScheme == .dark ? .dark : .light
        }
        return settings.themeMode
    }

    private var palette: ReaderTheme.Palette {
        ReaderTheme.palette(for: resolvedThemeMode, typographyStyle: settings.readerTypographyStyle)
    }

    private var selectedVoiceIdentifier: String? {
        settings.narrationVoiceIdentifier(for: settings.appLanguage.bcp47Code)
    }
    
    private var isLoadingState: Bool {
        viewModel.isInitialLoading
    }

    private var isDailyLimitReachedForReader: Bool {
        guard viewModel.currentFact != nil else { return false }
        let nextIndex = viewModel.currentIndex + 1
        return settings.canAccessPage(nextIndex) == false
    }

    var body: some View {
        GeometryReader { proxy in
            let safeTopInset = min(max(0, proxy.safeAreaInsets.top), 64)
            let pageIndexByFactID = Dictionary(
                uniqueKeysWithValues: viewModel.visiblePages.enumerated().map { index, page in
                    (page.sourceFactID, index)
                }
            )
            ZStack {
                if viewModel.visiblePages.isEmpty {
                    PaperBackdrop(palette: palette)

                    if isLoadingState {
                        LoadingSkeletonView(
                            palette: palette,
                            topSafeAreaInset: safeTopInset
                        )
                        .allowsHitTesting(false)
                    } else {
                        emptyState(topSafeAreaInset: safeTopInset + 8)
                    }
                } else {
                    FactReaderView(
                        pages: viewModel.visiblePages,
                        index: Binding(
                            get: { viewModel.currentIndex },
                            set: { viewModel.currentIndex = $0 }
                        ),
                        palette: palette,
                        topSafeAreaInset: safeTopInset,
                        hapticsEnabled: settings.hapticsEnabled && (isOnboardingPresented == false),
                        typingSoundEnabled: settings.typingSoundEnabled && (isOnboardingPresented == false),
                        appLanguage: settings.appLanguage,
                        readerFontScale: settings.readerFontScale,
                        readerTypographyStyle: settings.readerTypographyStyle,
                        categoryTintIntensity: settings.categoryTintIntensity,
                        pageTextAnimationsEnabled: settings.pageTextAnimationsEnabled
                            && (isOnboardingPresented == false)
                            && (suppressTextAnimations == false)
                            && (isSplashVisible == false),
                        showBookmarkHint: (settings.hasSeenBookmarkHint == false) && (isOnboardingPresented == false),
                        isDailyLimitReached: isDailyLimitReachedForReader,
                        dailyLimitCount: AppSettings.dailyFactLimit,
                        cooldownEndsAt: settings.effectiveDailyLimitResetDate,
                        cooldownMessage: settings.dailyLimitModeMessage,
                        pageTurnStyle: settings.pageTurnStyle,
                        controlsVisible: showReaderChrome,
                        canAccessFact: { fact in
                            let pageIndex = pageIndexByFactID[fact.id]
                            // If this fact is no longer in the current page list (e.g. during an in-flight reload),
                            // avoid false locking and let the current transition settle.
                            guard let pageIndex else { return true }
                            return settings.canAccessPage(pageIndex)
                        },
                        onDoubleTapCurrent: { fact in
                            let saved = toggleBookmark(for: fact)
                            showBookmarkToast(isSaved: saved)
                        },
                        onReaderTap: {
                            if narrator.hasActiveSession {
                                isNarrationPlayerDismissed = false
                            }
                            revealReaderChrome()
                        },
                        onDailyLimitHit: {
                            HapticManager.shared.notification(.warning)
                        }
                    )
                    .id(settings.pageTurnStyle.rawValue)
                }
            }
            .overlay(alignment: .bottom) {
                if let toast = bookmarkToast {
                    BookmarkToastPill(
                        isSaved: toast.isSaved,
                        language: settings.appLanguage,
                        isDark: palette.isDark
                    )
                    .padding(.bottom, ReaderTheme.bottomPadding + 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if shouldShowNarrationPlayer {
                    NarrationPlayerCard(
                        title: narrator.currentTitle,
                        category: narrator.currentCategory,
                        isSpeaking: narrator.isSpeaking,
                        isPaused: narrator.isPaused,
                        progress: narrator.playbackProgress,
                        elapsed: narrator.playbackElapsed,
                        duration: narrator.playbackDuration,
                        isDark: palette.isDark,
                        language: settings.appLanguage,
                        canGoPrevious: viewModel.currentIndex > 0,
                        canGoNext: viewModel.currentIndex < (viewModel.visiblePages.count - 1),
                        isExpanded: $isNarrationPlayerExpanded,
                        onPrevious: {
                            if narrator.hasActiveSession {
                                _ = narrator.requestManualPageTurn(.previous)
                            } else if viewModel.currentIndex > 0 {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    viewModel.currentIndex -= 1
                                }
                            }
                        },
                        onNext: {
                            if narrator.hasActiveSession {
                                _ = narrator.requestManualPageTurn(.next)
                            } else {
                                let nextIndex = viewModel.currentIndex + 1
                                if nextIndex < viewModel.visiblePages.count {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        viewModel.currentIndex = nextIndex
                                    }
                                }
                            }
                        },
                        onPlayPause: {
                            revealReaderChrome()
                            toggleNarration()
                        },
                        onStop: {
                            revealReaderChrome()
                            narrator.stop()
                            forceHideNarrationPlayer()
                        },
                        onSeek: { value in
                            narrator.seek(to: value)
                        },
                        onExpand: {
                            revealReaderChrome()
                        },
                        onMinimize: {
                            if showReaderChrome {
                                scheduleChromeAutoHide()
                            }
                        },
                        onClose: {
                            narrator.stop()
                            forceHideNarrationPlayer()
                        }
                    )
                    .padding(.bottom, (bookmarkToast != nil ? 82 : 14))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea()
            .background(palette.pageBackground.ignoresSafeArea())
            .overlay(alignment: .topTrailing) {
                if (showReaderChrome || viewModel.visiblePages.isEmpty), isQuickCustomizePresented == false {
                    topTrailingControls
                        .padding(.top, max(2, safeTopInset - 50))
                        .padding(.trailing, 12)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showReaderChrome, isNarrationPlayerExpanded == false, isQuickCustomizePresented == false {
                    VStack(spacing: 10) {
                        if viewModel.currentFact != nil {
                            Button(action: {
                                revealReaderChrome()
                                isNarrationPlayerDismissed = false
                                toggleNarration()
                            }) {
                                Image(systemName: narrator.isSpeaking && !narrator.isPaused ? "pause.fill" : "play.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.primary)
                                    .frame(width: 36, height: 36)
                            }
                            .controlSize(.small)
                            .liquidGlassButtonStyle(fallbackShape: Circle(), isDark: palette.isDark)
                            .accessibilityLabel(
                                narrator.isSpeaking && !narrator.isPaused
                                    ? localized("Pause narration")
                                    : localized("Listen to fact")
                            )
                        }

                        Button(action: {
                            revealReaderChrome()
                            isReaderAppearancePresented = true
                        }) {
                            Text("Aa")
                                .font(.system(size: 18, weight: .semibold, design: .serif))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                        }
                        .controlSize(.small)
                        .liquidGlassButtonStyle(fallbackShape: Circle(), isDark: palette.isDark)
                    }
                    .padding(.trailing, 14)
                    .padding(.bottom, narrator.hasActiveSession ? 124 : (ReaderTheme.bottomPadding + 30))
                }
            }
            .overlay {
                if isSplashVisible {
                    AppSplashOverlay(
                        palette: palette,
                        topSafeAreaInset: safeTopInset
                    )
                    .transition(.opacity)
                    .zIndex(1000)
                }
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView(
                    onOpenFact: { fact in
                        Task { await viewModel.ensureFactVisible(fact, context: modelContext, settings: settings) }
                    },
                    onDone: {
                        isSettingsPresented = false
                    }
                )
                .preferredColorScheme(resolvedThemeMode == .dark ? .dark : .light)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isReaderAppearancePresented) {
                ReaderAppearanceSheet()
                    .preferredColorScheme(resolvedThemeMode == .dark ? .dark : .light)
                    .presentationDetents([.height(520)])
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.scrolls)
                    .presentationCornerRadius(30)
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $isQuickCustomizePresented) {
                QuickCustomizeSheet()
                    .preferredColorScheme(resolvedThemeMode == .dark ? .dark : .light)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.scrolls)
                    .presentationCornerRadius(28)
                    .presentationBackground(.ultraThinMaterial)
            }
            .fullScreenCover(isPresented: $isOnboardingPresented) {
                OnboardingView()
                    .interactiveDismissDisabled(true)
            }
            .onAppear {
                AppBrightnessManager.shared.applyForAppIfNeeded()
                guard hasInitializedSession == false else { return }
                hasInitializedSession = true
                applyFeedbackProfile()

                showReaderChrome = false
                isOnboardingPresented = (settings.hasCompletedOnboarding == false)
                if isOnboardingPresented {
                    hideSplashNow()
                } else {
                    showSplash()
                    startReload(
                        preserveCurrentFact: false,
                        restoreFromLastRead: settings.resumeFromLastRead
                    )
                }
                AdMobManager.shared.configureIfNeeded(presenter: AdMobManager.shared.topPresenter())
                syncRemindersIfNeeded()
                enforceDailyWindowIndexIfNeeded()
                settings.markPageViewed(viewModel.currentFact == nil ? nil : viewModel.currentIndex)
                startLoadingWatchdog()

                narrator.onAutoAdvanceToNext = { [weak viewModel] in
                    guard let viewModel else { return nil }
                    let nextIndex = viewModel.currentIndex + 1
                    guard nextIndex < viewModel.visiblePages.count else { return nil }
                    viewModel.currentIndex = nextIndex
                    return (viewModel.visiblePages[nextIndex].fact, nextIndex + 1)
                }

                narrator.onAutoAdvanceToPrevious = { [weak viewModel] in
                    guard let viewModel else { return nil }
                    let previousIndex = viewModel.currentIndex - 1
                    guard previousIndex >= 0 else { return nil }
                    viewModel.currentIndex = previousIndex
                    return (viewModel.visiblePages[previousIndex].fact, previousIndex + 1)
                }
            }
            .onChange(of: settings.selectedCategories) { _, _ in
                scheduleCategorySync()
            }
            .onChange(of: settings.alertsEnabled) { _, enabled in
                reminderSyncTask?.cancel()
                reminderSyncTask = Task {
                    _ = await FactReminderNotifications.shared.sync(
                        enabled: enabled,
                        language: settings.appLanguage
                    )
                }
            }
            .onChange(of: settings.pageTurnStyle) { _, _ in
                HapticManager.shared.impact(.rigid)
                suppressTextAnimationsTemporarily()
            }
            .onChange(of: settings.themeMode) { _, _ in
                applyFeedbackProfile()
                suppressTextAnimationsTemporarily()
            }
            .onChange(of: settings.followsSystemTheme) { _, _ in
                applyFeedbackProfile()
                suppressTextAnimationsTemporarily()
            }
            .onChange(of: settings.readerTypographyStyle) { _, _ in
                suppressTextAnimationsTemporarily()
            }
            .onChange(of: settings.categoryTintIntensity) { _, _ in
                suppressTextAnimationsTemporarily()
            }
            .onChange(of: viewModel.currentIndex) { oldIndex, newIndex in
                settings.lastReadFactID = viewModel.currentFact?.id
                guard oldIndex != newIndex else { return }
                guard settings.canAccessPage(newIndex) else {
                    enforceDailyWindowIndexIfNeeded()
                    return
                }
                settings.markPageViewed(viewModel.currentFact == nil ? nil : viewModel.currentIndex)
                if let category = viewModel.currentFact?.category {
                    settings.trackCategoryRead(category)
                }
                let narrationWasActive = narrator.hasActiveSession || narrator.isSpeaking || narrator.isPaused
                if narrationWasActive {
                    syncNarrationWithCurrentFact(forceStart: true)
                }

                loadMoreTask?.cancel()
                loadMoreTask = Task {
                    await viewModel.loadMoreIfNeeded(context: modelContext, settings: settings)
                }

                guard isSettingsPresented == false else { return }
                guard newIndex > oldIndex else { return }
                AdMobManager.shared.trackPageAdvanceAndPresentIfNeeded(from: AdMobManager.shared.topPresenter())
            }
            .onReceive(NotificationCenter.default.publisher(for: .factLibraryDidChange)) { _ in
                startReload(preserveCurrentFact: true, restoreFromLastRead: settings.resumeFromLastRead)
            }
            .onChange(of: settings.hasCompletedOnboarding) { _, hasCompleted in
                if hasCompleted {
                    isOnboardingPresented = false
                    if viewModel.visiblePages.isEmpty, viewModel.isInitialLoading == false {
                        startReload(
                            preserveCurrentFact: false,
                            restoreFromLastRead: settings.resumeFromLastRead
                        )
                    }
                }
            }
            .onDisappear {
                handleViewDisappear()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    AppBrightnessManager.shared.applyForAppIfNeeded()
                    Task {
                        await FactReminderNotifications.shared.clearDeliveredAndBadge()
                    }
                    syncRemindersIfNeeded()
                } else {
                    AppBrightnessManager.shared.restoreSystemBrightnessIfNeeded()
                }
            }
            .onChange(of: isSettingsPresented) { _, presented in
                if presented {
                    revealReaderChrome()
                } else {
                    scheduleChromeAutoHide()
                    if hasPendingCategorySync {
                        scheduleCategorySync()
                    }
                }
            }
            .onChange(of: isReaderAppearancePresented) { _, presented in
                if presented {
                    revealReaderChrome()
                } else {
                    scheduleChromeAutoHide()
                }
            }
            .onChange(of: narrator.hasActiveSession) { _, hasSession in
                if hasSession {
                    withAnimation(.easeOut(duration: 0.14)) {
                        isNarrationPlayerDismissed = false
                        showNarrationPlayerChrome = true
                    }
                } else {
                    forceHideNarrationPlayer()
                }
            }
            .onChange(of: narrator.isPaused) { _, isPaused in
                if isPaused, narrator.hasActiveSession {
                    withAnimation(.easeOut(duration: 0.14)) {
                        isNarrationPlayerDismissed = false
                        showNarrationPlayerChrome = true
                    }
                }
            }
        }
    }

    private func emptyState(topSafeAreaInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(emptyTitle)
                .font(.system(size: 36, weight: .bold, design: .serif))
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(palette.inkPrimary)
                .padding(.top, topSafeAreaInset + 62)

            Text(emptySubtitle)
                .font(.system(size: 17, weight: .regular, design: .default))
                .lineSpacing(8)
                .multilineTextAlignment(.leading)
                .foregroundStyle(palette.inkSecondary)
                .padding(.top, 18)

            Spacer(minLength: 18)
        }
        .padding(.horizontal, ReaderTheme.horizontalMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var topTrailingControls: some View {
        let controlSize: CGFloat = 42
        let iconSize: CGFloat = 18

        return HStack(spacing: 0) {
            Button(action: {
                revealReaderChrome()
                isSettingsPresented = true
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: iconSize, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .frame(width: controlSize, height: controlSize)
            }
            .buttonStyle(ReaderTopGlassButtonStyle())
            .contentShape(Rectangle())
            .accessibilityLabel(localized("Open Settings"))

            Capsule(style: .continuous)
                .fill(.primary.opacity(0.12))
                .frame(width: 1, height: 20)
                .padding(.horizontal, 1)

            Button(action: {
                revealReaderChrome()
                isQuickCustomizePresented = true
            }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: iconSize, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .frame(width: controlSize, height: controlSize)
            }
            .buttonStyle(ReaderTopGlassButtonStyle())
            .contentShape(Rectangle())
            .accessibilityLabel("Open category customization")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 0)
        .liquidGlassCapsuleMaterial()
    }

    private var emptyTitle: String {
        if settings.selectedCategories.count < 2 {
            return localized("Choose at least two categories")
        }
        return localized(isLoadingState ? "Loading facts..." : "No facts available.")
    }

    private var emptySubtitle: String {
        if settings.selectedCategories.count < 2 {
            return localized("Select at least two categories in onboarding.")
        }
        if
            isLoadingState == false,
            let remoteError = settings.lastRemoteSyncError?.trimmingCharacters(in: .whitespacesAndNewlines),
            remoteError.isEmpty == false
        {
            return remoteError
        }
        return localized(isLoadingState ? "Please wait..." : "Customize categories in Settings.")
    }

    @discardableResult
    private func toggleBookmark(for fact: Fact) -> Bool {
        fact.isBookmarked.toggle()
        if fact.isBookmarked {
            settings.trackCategoryRead(fact.category, weight: 3.0)
        }
        if settings.hasSeenBookmarkHint == false {
            settings.hasSeenBookmarkHint = true
        }
        try? modelContext.save()
        HapticManager.shared.impact(.rigid)
        return fact.isBookmarked
    }

    private func applyFeedbackProfile() {
        HapticManager.shared.configure(themeMode: resolvedThemeMode)
    }

    private func toggleNarration() {
        isNarrationPlayerDismissed = false
        showNarrationPlayerChrome = true
        guard let currentFact = viewModel.currentFact else { return }
        let currentPageNumber = viewModel.currentIndex + 1

        // If session is closed, always start fresh for smooth/reliable restart.
        if narrator.hasActiveSession == false {
            narrator.stop()
            narrator.play(
                fact: currentFact,
                pageNumber: currentPageNumber,
                languageCode: settings.appLanguage.bcp47Code,
                voiceIdentifier: selectedVoiceIdentifier
            )
            return
        }

        narrator.togglePlayPause(
            currentFact: currentFact,
            currentPageNumber: currentPageNumber,
            languageCode: settings.appLanguage.bcp47Code,
            voiceIdentifier: selectedVoiceIdentifier
        )
    }

    private func revealReaderChrome() {
        guard viewModel.visiblePages.isEmpty == false else { return }
        if narrator.hasActiveSession {
            isNarrationPlayerDismissed = false
            showNarrationPlayerChrome = true
        }
        if showReaderChrome == false {
            withAnimation(.easeOut(duration: 0.14)) {
                showReaderChrome = true
            }
        }
        scheduleChromeAutoHide()
    }

    private func scheduleChromeAutoHide() {
        chromeAutoHideTask?.cancel()
        guard showReaderChrome else { return }
        guard isSettingsPresented == false, isReaderAppearancePresented == false else { return }
        guard isNarrationPlayerExpanded == false else { return }
        chromeAutoHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.2))
            guard Task.isCancelled == false else { return }
            guard isSettingsPresented == false, isReaderAppearancePresented == false else { return }
            guard isNarrationPlayerExpanded == false else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                showReaderChrome = false
            }
        }
    }

    private var shouldShowNarrationPlayer: Bool {
        let narrationIsActive = narrator.hasActiveSession || narrator.isSpeaking || narrator.isPaused
        guard narrationIsActive else { return false }
        guard isNarrationPlayerDismissed == false else { return false }
        return true
    }

    private func syncNarrationWithCurrentFact(forceStart: Bool = false) {
        guard narrator.hasActiveSession || forceStart else { return }
        guard let fact = viewModel.currentFact else {
            narrator.stop()
            return
        }
        if narrator.currentFactID == fact.id, narrator.hasActiveSession {
            return
        }
        narrator.play(
            fact: fact,
            pageNumber: viewModel.currentIndex + 1,
            languageCode: settings.appLanguage.bcp47Code,
            voiceIdentifier: selectedVoiceIdentifier
        )
    }

    private func showBookmarkToast(isSaved: Bool) {
        bookmarkToastTask?.cancel()

        withAnimation(.spring(response: 0.24, dampingFraction: 0.95)) {
            bookmarkToast = BookmarkToastState(isSaved: isSaved)
        }

        bookmarkToastTask = Task {
            try? await Task.sleep(for: .milliseconds(980))
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.22)) {
                    bookmarkToast = nil
                }
            }
        }
    }

    private func forceHideNarrationPlayer() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.95)) {
            isNarrationPlayerExpanded = false
            isNarrationPlayerDismissed = false
            showNarrationPlayerChrome = false
        }
    }
    
    private func scheduleCategorySync() {
        hasPendingCategorySync = true
        categorySyncTask?.cancel()
        
        // Avoid heavy page regeneration while user is actively selecting categories.
        guard isSettingsPresented == false else { return }
        
        categorySyncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard Task.isCancelled == false else { return }
            hasPendingCategorySync = false
            await viewModel.applyCategoryChange(context: modelContext, settings: settings)
        }
    }

    private func startReload(preserveCurrentFact: Bool, restoreFromLastRead: Bool) {
        reloadTask?.cancel()
        reloadTask = Task {
            await viewModel.reload(
                context: modelContext,
                settings: settings,
                preserveCurrentFact: preserveCurrentFact,
                restoreFromLastRead: restoreFromLastRead
            )
            enforceDailyWindowIndexIfNeeded()
            settings.markPageViewed(viewModel.currentFact == nil ? nil : viewModel.currentIndex)
            syncNarrationWithCurrentFact()
        }
    }

    private func handleViewDisappear() {
        AppBrightnessManager.shared.restoreSystemBrightnessIfNeeded()
        reloadTask?.cancel()
        loadMoreTask?.cancel()
        reminderSyncTask?.cancel()
        categorySyncTask?.cancel()
        loadingWatchdogTask?.cancel()
        bookmarkToastTask?.cancel()
        chromeAutoHideTask?.cancel()
        suppressTextAnimationsTask?.cancel()
        splashDismissTask?.cancel()
    }

    private func enforceDailyWindowIndexIfNeeded() {
        guard viewModel.visiblePages.isEmpty == false else { return }
        let currentIndex = viewModel.currentIndex
        guard settings.canAccessPage(currentIndex) == false else { return }

        if let firstAccessible = viewModel.visiblePages.indices.first(where: { settings.canAccessPage($0) }) {
            viewModel.currentIndex = firstAccessible
            settings.lastReadFactID = viewModel.visiblePages[firstAccessible].sourceFactID
        }
    }

    private func syncRemindersIfNeeded() {
        reminderSyncTask?.cancel()
        guard settings.alertsEnabled else { return }
        reminderSyncTask = Task {
            _ = await FactReminderNotifications.shared.sync(enabled: true, language: settings.appLanguage)
        }
    }
    
    private func startLoadingWatchdog() {
        loadingWatchdogTask?.cancel()
        loadingWatchdogTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(14))
            guard Task.isCancelled == false else { return }
            guard isLoadingState else { return }
            viewModel.isInitialLoading = false
        }
    }
    
    private func stopLoadingWatchdog() {
        loadingWatchdogTask?.cancel()
        if isLoadingState == false {
            viewModel.isInitialLoading = false
        }
    }
    
    private func suppressTextAnimationsTemporarily() {
        suppressTextAnimationsTask?.cancel()
        suppressTextAnimations = true
        suppressTextAnimationsTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1100))
            guard Task.isCancelled == false else { return }
            suppressTextAnimations = false
            suppressTextAnimationsTask = nil
        }
    }

    private func showSplash() {
        splashDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            isSplashVisible = true
        }
        splashDismissTask = Task { @MainActor in
            // Keep a tiny branding beat, but avoid a long blank/blocked launch feel.
            try? await Task.sleep(for: .milliseconds(320))
            guard Task.isCancelled == false else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                isSplashVisible = false
            }
            splashDismissTask = nil
        }
    }

    private func hideSplashNow() {
        splashDismissTask?.cancel()
        splashDismissTask = nil
        withAnimation(.easeOut(duration: 0.15)) {
            isSplashVisible = false
        }
    }

    private func localized(_ text: String) -> String {
        text
    }

}

private struct ReaderTopGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

private extension View {
    @ViewBuilder
    func liquidGlassCircleMaterial() -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(in: Circle())
                .overlay(
                    Circle().stroke(.white.opacity(0.20), lineWidth: 0.6)
                )
        } else {
            self
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    @ViewBuilder
    func liquidGlassCapsuleMaterial() -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.20), lineWidth: 0.6)
                )
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        }
    }
}

private struct AppSplashOverlay: View {
    let palette: ReaderTheme.Palette
    let topSafeAreaInset: CGFloat
    @State private var animateIn = false
    @State private var pulseLogo = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    palette.pageGradientTop,
                    palette.pageBackground,
                    palette.pageGradientBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                splashLogo
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(palette.isDark ? 0.34 : 0.14), radius: 20, y: 10)
                    .scaleEffect(pulseLogo ? 1.03 : 0.97)

                Text("FACTREAD")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .tracking(2.3)
                    .foregroundStyle(palette.inkPrimary)

                Text("Smart facts, smooth reading.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.inkSecondary)
            }
            .padding(.top, topSafeAreaInset * 0.35)
            .scaleEffect(animateIn ? 1 : 0.94)
            .opacity(animateIn ? 1 : 0.16)
            .offset(y: animateIn ? 0 : 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            Rectangle()
                .fill(.white.opacity(palette.isDark ? 0.02 : 0.04))
                .blendMode(.softLight)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .allowsHitTesting(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.38)) {
                animateIn = true
            }
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                pulseLogo.toggle()
            }
        }
    }

    @ViewBuilder
    private var splashLogo: some View {
        if let image = UIImage(named: "LaunchIcon") {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(palette.markerTint.opacity(0.28))
                .overlay {
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(palette.inkPrimary)
                }
        }
    }
}

private struct InlineFactSkeletonOverlay: View {
    let palette: ReaderTheme.Palette
    let topSafeAreaInset: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.inkSecondary.opacity(0.26))
                .frame(width: 110, height: 12)
                .padding(.top, topSafeAreaInset + 22)

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.inkPrimary.opacity(0.22))
                    .frame(height: 34)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.inkPrimary.opacity(0.18))
                    .frame(width: 235, height: 34)
            }
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 11) {
                ForEach(0..<8, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.inkSecondary.opacity(idx < 2 ? 0.22 : 0.16))
                        .frame(width: lineWidth(at: idx), height: 15)
                }
            }
            .padding(.top, 22)
        }
        .shimmer(active: true)
    }

    private func lineWidth(at index: Int) -> CGFloat {
        switch index {
        case 0: return 330
        case 1: return 306
        case 2: return 320
        case 3: return 292
        case 4: return 312
        case 5: return 285
        case 6: return 324
        default: return 265
        }
    }
}

private struct BookmarkToastState: Equatable {
    let isSaved: Bool
}

private struct BookmarkToastPill: View {
    let isSaved: Bool
    let language: AppLanguage
    let isDark: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark.slash")
                .font(.system(size: 15, weight: .semibold))
            Text(toastText)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(2)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlassCard(cornerRadius: 999, isDark: isDark)
        .padding(.horizontal, 14)
    }

    private var toastText: String {
        isSaved ? "Saved to Bookmarks" : "Removed from Bookmarks"
    }
}

private struct NarrationPlayerCard: View {
    let title: String
    let category: String
    let isSpeaking: Bool
    let isPaused: Bool
    let progress: Double
    let elapsed: TimeInterval
    let duration: TimeInterval
    let isDark: Bool
    let language: AppLanguage
    let canGoPrevious: Bool
    let canGoNext: Bool
    @Binding var isExpanded: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onPlayPause: () -> Void
    let onStop: () -> Void
    let onSeek: (Double) -> Void
    let onExpand: () -> Void
    let onMinimize: () -> Void
    let onClose: () -> Void

    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @Namespace private var playerAnimation

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedContent
            } else {
                compactContent
            }
        }
        .padding(.horizontal, isExpanded ? 18 : 16)
        .padding(.vertical, isExpanded ? 14 : 10)
        .liquidGlassCard(cornerRadius: isExpanded ? 24 : 999, isDark: isDark)
        .padding(.horizontal, 14)
        .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.92, blendDuration: 0.08), value: isExpanded)
        .onAppear {
            scrubValue = progress
        }
        .onChange(of: progress) { _, newValue in
            if isScrubbing == false {
                withAnimation(.linear(duration: 0.18)) {
                    scrubValue = newValue
                }
            }
        }
    }

    private var compactContent: some View {
        HStack(spacing: 10) {
            Button(action: {
                withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.92, blendDuration: 0.08)) {
                    isExpanded = true
                }
                onExpand()
            }) {
                HStack(spacing: 10) {
                    artwork(size: 44, radius: 10)
                        .matchedGeometryEffect(id: "player.artwork", in: playerAnimation)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                            .matchedGeometryEffect(id: "player.title", in: playerAnimation)

                        Text("\(localizedCategory) • \(statusLabel)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    .matchedGeometryEffect(id: "player.category", in: playerAnimation)

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)
            iconButton(systemName: "backward.fill", size: 14, frame: 34, enabled: canGoPrevious, action: onPrevious)
            playButton(buttonSize: 36, iconSize: 16)
            iconButton(systemName: "forward.fill", size: 14, frame: 34, enabled: canGoNext, action: onNext)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(.primary.opacity(isDark ? 0.10 : 0.06))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
    }

    private var expandedContent: some View {
        VStack(spacing: 14) {
            Capsule(style: .continuous)
                .fill(.primary.opacity(isDark ? 0.34 : 0.22))
                .frame(width: 40, height: 4)
                .padding(.top, 1)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

            HStack(alignment: .top, spacing: 12) {
                artwork(size: 72, radius: 16)
                    .matchedGeometryEffect(id: "player.artwork", in: playerAnimation)
                    .shadow(color: categoryAccent.opacity(isDark ? 0.22 : 0.12), radius: 10, y: 4)

                VStack(alignment: .leading, spacing: 6) {
                    categoryPill
                        .matchedGeometryEffect(id: "player.category", in: playerAnimation)

                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .lineLimit(3)
                        .foregroundStyle(.primary)
                        .matchedGeometryEffect(id: "player.title", in: playerAnimation)

                    Text(statusLabel)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                Button(action: {
                    withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.92, blendDuration: 0.08)) {
                        isExpanded = false
                    }
                    onMinimize()
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(.primary.opacity(isDark ? 0.14 : 0.08))
                        )
                }
                .buttonStyle(.plain)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(.primary.opacity(isDark ? 0.12 : 0.07))
                        )
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { scrubValue },
                        set: { newValue in
                            scrubValue = newValue
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if editing {
                            HapticManager.shared.selection()
                        }
                        isScrubbing = editing
                        if editing == false {
                            onSeek(scrubValue)
                            HapticManager.shared.impact(.soft)
                        }
                    }
                )
                .tint(categoryAccent)
                .scaleEffect(isScrubbing ? 1.01 : 1.0)
                .animation(.easeOut(duration: 0.14), value: isScrubbing)

                HStack {
                    Text(timeString(displayElapsed))
                    Spacer()
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(stopLabel)
                    Text(timeString(displayRemaining))
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .transition(.move(edge: .bottom).combined(with: .opacity))

            HStack(spacing: 22) {
                iconButton(systemName: "backward.fill", size: 18, frame: 42, enabled: canGoPrevious, action: onPrevious)
                playButton(buttonSize: 52, iconSize: 20)
                iconButton(systemName: "forward.fill", size: 18, frame: 42, enabled: canGoNext, action: onNext)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .contentTransition(.interpolate)
    }

    private var localizedCategory: String {
        let raw = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.isEmpty == false else { return "Fact" }
        return Fact.localizedCategory(raw, language: language).uppercased()
    }

    private var categoryAccent: Color {
        CategoryStyle.accent(for: category, intensity: 0.88)
    }

    private var cardTintOpacity: Double {
        if isExpanded {
            return isDark ? 0.14 : 0.10
        }
        return isDark ? 0.08 : 0.06
    }

    private var isActivelyPlaying: Bool {
        isSpeaking && !isPaused
    }

    private var statusLabel: String {
        if isActivelyPlaying { return "Playing" }
        if isPaused { return "Paused" }
        return "Ready"
    }
    
    private var displayElapsed: TimeInterval {
        if isScrubbing {
            return max(0, min(duration, duration * scrubValue))
        }
        return elapsed
    }
    
    private var displayRemaining: TimeInterval {
        max(duration - displayElapsed, 0)
    }

    private var categoryPill: some View {
        Text(localizedCategory)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.2)
            .lineLimit(1)
            .foregroundStyle(categoryAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(categoryAccent.opacity(isDark ? 0.22 : 0.14))
            )
    }

    private func iconButton(
        systemName: String,
        size: CGFloat = 14,
        frame: CGFloat = 32,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .frame(width: frame, height: frame)
                .foregroundStyle(.primary)
                .background(
                    Circle()
                        .fill(.primary.opacity(isDark ? 0.10 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .disabled(enabled == false)
        .opacity(enabled ? 1 : 0.38)
        .scaleEffect(1.0)
    }

    private func playButton(buttonSize: CGFloat, iconSize: CGFloat) -> some View {
        Button(action: onPlayPause) {
            Image(systemName: isSpeaking && !isPaused ? "pause.fill" : "play.fill")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(categoryAccent.opacity(isDark ? 0.28 : 0.17))
                )
        }
        .buttonStyle(.plain)
    }

    private func timeString(_ time: TimeInterval) -> String {
        let total = max(Int(time.rounded()), 0)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var stopLabel: String {
        "Stop"
    }

    @ViewBuilder
    private func artwork(size: CGFloat, radius: CGFloat) -> some View {
        let trait = UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
        if let image = UIImage(named: "LaunchIcon", in: .main, compatibleWith: trait) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.secondary.opacity(0.25))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "waveform")
                        .font(.system(size: size * 0.30, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }
}

private struct ReaderAppearanceSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var brightnessProxy: Double = Double(AppBrightnessManager.shared.displayedBrightness)
    
    private enum ThemeSelection: String, CaseIterable, Identifiable {
        case matchDevice
        case light
        case dark
        
        var id: String { rawValue }
    }

    private var resolvedThemeMode: ReaderThemeMode {
        if settings.followsSystemTheme {
            return colorScheme == .dark ? .dark : .light
        }
        return settings.themeMode
    }

    private var palette: ReaderTheme.Palette {
        ReaderTheme.palette(for: resolvedThemeMode, typographyStyle: settings.readerTypographyStyle)
    }
    
    private var themeSelection: Binding<ThemeSelection> {
        Binding(
            get: {
                if settings.followsSystemTheme {
                    return .matchDevice
                }
                return settings.themeMode == .dark ? .dark : .light
            },
            set: { newValue in
                switch newValue {
                case .matchDevice:
                    settings.followsSystemTheme = true
                    settings.themeMode = colorScheme == .dark ? .dark : .light
                case .light:
                    if settings.followsSystemTheme || settings.themeMode != .light {
                        settings.followsSystemTheme = false
                        settings.themeMode = .light
                    }
                case .dark:
                    if settings.followsSystemTheme || settings.themeMode != .dark {
                        settings.followsSystemTheme = false
                        settings.themeMode = .dark
                    }
                }
            }
        )
    }

    private var presets: [ReaderPreset] {
        [
            .init(id: "original", title: "Original", subtitle: "Balanced", tint: 0.90, turn: .curl, lightBackgroundHex: "F9F9F7", lightForegroundHex: "171717", darkBackgroundHex: "0B0B0E", darkForegroundHex: "F2F2F2", typographyStyle: .original),
            .init(id: "quiet", title: "Quiet", subtitle: "Dim", tint: 0.70, turn: .curl, lightBackgroundHex: "585960", lightForegroundHex: "B4B7C0", darkBackgroundHex: "050507", darkForegroundHex: "9497A2", typographyStyle: .quiet),
            .init(id: "paper", title: "Paper", subtitle: "Soft", tint: 0.55, turn: .slide, lightBackgroundHex: "F1F1EE", lightForegroundHex: "22232A", darkBackgroundHex: "1B1C23", darkForegroundHex: "D3D5DD", typographyStyle: .paper),
            .init(id: "bold", title: "Bold", subtitle: "High Contrast", tint: 1.00, turn: .slide, lightBackgroundHex: "FFFFFF", lightForegroundHex: "101216", darkBackgroundHex: "121318", darkForegroundHex: "FDFEFF", typographyStyle: .bold),
            .init(id: "calm", title: "Calm", subtitle: "Easy Read", tint: 0.62, turn: .curl, lightBackgroundHex: "E6D8BE", lightForegroundHex: "4C402F", darkBackgroundHex: "534A3C", darkForegroundHex: "E9DFC9", typographyStyle: .calm),
            .init(id: "focus", title: "Focus", subtitle: "Tight", tint: 0.50, turn: .curl, lightBackgroundHex: "F3F2E7", lightForegroundHex: "201F14", darkBackgroundHex: "17160A", darkForegroundHex: "F0EBD1", typographyStyle: .focus)
        ]
    }

    private var activePreset: ReaderPreset? {
        presets.first { $0.matches(settings: settings) }
    }

    private var previewUsesDarkPalette: Bool {
        resolvedThemeMode == .dark
    }

    private var popupInkPrimary: Color { .primary }
    private var popupInkSecondary: Color { .secondary }
    private var popupPanelBorder: Color {
        popupInkPrimary.opacity(palette.isDark ? 0.20 : 0.10)
    }
    
    private var pageTurnSymbol: String {
        settings.pageTurnStyle == .slide ? "rectangle.3.group.fill" : "book.pages.fill"
    }

    private var presetColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    }

    private var themeSymbol: String {
        switch themeSelection.wrappedValue {
        case .matchDevice: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            headerRow
            topControls
            brightnessControls
            presetsGrid
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("Themes & Settings")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(popupInkPrimary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(popupInkPrimary.opacity(0.90))
            }
            .liquidGlassButtonStyle(fallbackShape: Circle())
        }
    }

    private var topControls: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.20)) {
                    settings.readerFontScale = max(0.85, settings.readerFontScale - 0.05)
                }
            } label: {
                Text("A")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(popupInkPrimary)
            }
            .liquidGlassButtonStyle(fallbackShape: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button {
                withAnimation(.easeInOut(duration: 0.20)) {
                    settings.readerFontScale = min(1.20, settings.readerFontScale + 0.05)
                }
            } label: {
                Text("A")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(popupInkPrimary)
            }
            .liquidGlassButtonStyle(fallbackShape: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Menu {
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.94)) {
                        settings.pageTurnStyle = .curl
                    }
                } label: {
                    Label("Curl", systemImage: "book.pages.fill")
                }
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.94)) {
                        settings.pageTurnStyle = .slide
                    }
                } label: {
                    Label("Slide", systemImage: "rectangle.3.group.fill")
                }
            } label: {
                Image(systemName: pageTurnSymbol)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(popupInkPrimary)
            }
            .menuStyle(.button)
            .liquidGlassButtonStyle(fallbackShape: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Menu {
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.94)) {
                        themeSelection.wrappedValue = .matchDevice
                    }
                } label: {
                    Label("Match Device", systemImage: "circle.lefthalf.filled")
                }
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.94)) {
                        themeSelection.wrappedValue = .light
                    }
                } label: {
                    Label("Light", systemImage: "sun.max.fill")
                }
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.94)) {
                        themeSelection.wrappedValue = .dark
                    }
                } label: {
                    Label("Dark", systemImage: "moon.fill")
                }
            } label: {
                Image(systemName: themeSymbol)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(popupInkPrimary)
            }
            .menuStyle(.button)
            .liquidGlassButtonStyle(fallbackShape: RoundedRectangle(cornerRadius: 16, style: .continuous))

        }
    }

    private var brightnessControls: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.min.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(popupInkSecondary)
            Slider(value: $brightnessProxy, in: 0.2...1.0)
                .tint(.primary)
                .onChange(of: brightnessProxy) { _, value in
                    AppBrightnessManager.shared.setPreferredBrightness(CGFloat(value))
                }
            Image(systemName: "sun.max.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(popupInkSecondary)
        }
        .padding(.horizontal, 2)
    }

    private var presetsGrid: some View {
        LazyVGrid(columns: presetColumns, spacing: 12) {
            ForEach(presets) { preset in
                ThemeOptionCard(
                    title: preset.title,
                    subtitle: preset.subtitle,
                    isSelected: preset.matches(settings: settings),
                    typographyStyle: preset.typographyStyle,
                    backgroundHex: previewUsesDarkPalette ? preset.darkBackgroundHex : preset.lightBackgroundHex,
                    foregroundHex: previewUsesDarkPalette ? preset.darkForegroundHex : preset.lightForegroundHex
                ) {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.94)) {
                        preset.apply(to: settings)
                    }
                }
            }
        }
    }
}

private struct ReaderPreset: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let tint: Double
    let turn: PageTurnStyle
    let lightBackgroundHex: String
    let lightForegroundHex: String
    let darkBackgroundHex: String
    let darkForegroundHex: String
    let typographyStyle: ReaderTypographyStyle

    func apply(to settings: AppSettings) {
        settings.readerFontScale = 1.0
        settings.categoryTintIntensity = tint
        settings.pageTurnStyle = turn
        settings.readerTypographyStyle = typographyStyle
    }

    func matches(settings: AppSettings) -> Bool {
        abs(settings.categoryTintIntensity - tint) < 0.07
            && settings.pageTurnStyle == turn
            && settings.readerTypographyStyle == typographyStyle
    }
}

private struct ThemeOptionCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let typographyStyle: ReaderTypographyStyle
    let backgroundHex: String
    let foregroundHex: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text("Aa")
                    .font(sampleFont(size: 34))
                    .lineLimit(1)
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                    .foregroundStyle(subtitleColor)
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, minHeight: 108)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? foregroundColor.opacity(0.70) : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        Color(hex: backgroundHex)
    }

    private var foregroundColor: Color {
        Color(hex: foregroundHex)
    }

    private var subtitleColor: Color {
        foregroundColor.opacity(0.84)
    }

    private func sampleFont(size: CGFloat) -> Font {
        switch typographyStyle {
        case .original:
            return .system(size: size, weight: .semibold, design: .serif)
        case .quiet:
            return Font.custom("PublicoText-Roman", size: size, relativeTo: .body)
        case .paper:
            return Font.custom("Charter", size: size, relativeTo: .body)
        case .bold:
            return .system(size: size, weight: .bold, design: .default)
        case .calm:
            return Font.custom("Canela-Regular", size: size, relativeTo: .body)
        case .focus:
            return Font.custom("ProximaNova-Regular", size: size, relativeTo: .body)
        }
    }
}
