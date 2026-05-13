import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english

    var id: String { rawValue }

    var bcp47Code: String { "en" }

    var title: String { "English" }

    var resolved: AppLanguage { .english }

    // Canonical app/storage code used across persistence, filtering and remote import.
    static func canonicalLanguageCode(_ rawCode: String) -> String {
        _ = rawCode
        return "en"
    }

    // Accepted aliases for querying legacy/imported records.
    static func languageCodeAliases(for canonicalCode: String) -> [String] {
        _ = canonicalCode
        return ["en", "en-US", "en-GB", "en-us", "en-gb"]
    }
}

enum PageTurnStyle: String, CaseIterable, Identifiable {
    case slide
    case curl

    var id: String { rawValue }
}

enum ReaderTypographyStyle: String, CaseIterable, Identifiable {
    case original
    case quiet
    case paper
    case bold
    case calm
    case focus

    var id: String { rawValue }
}

@Observable
@MainActor
final class AppSettings {
    private enum Keys {
        static let selectedCategories = "selectedCategories"
        static let hapticsEnabled = "hapticsEnabled"
        static let typingSoundEnabled = "typingSoundEnabled"
        static let themeMode = "themeMode"
        static let followsSystemTheme = "followsSystemTheme"
        static let appLanguage = "appLanguage"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let lastReadFactID = "lastReadFactID"
        static let alertsEnabled = "alertsEnabled"
        static let resumeFromLastRead = "resumeFromLastRead"
        static let hasSeenSwipeHint = "hasSeenSwipeHint"
        static let hasSeenBookmarkHint = "hasSeenBookmarkHint"
        static let dailyViewDayKey = "dailyViewDayKey"
        static let dailyViewedFactIDs = "dailyViewedFactIDs"
        static let dailyViewedPageIndices = "dailyViewedPageIndices"
        static let dailyWindowStartIndex = "dailyWindowStartIndex"
        static let lastRemoteFetchCount = "lastRemoteFetchCount"
        static let lastRemoteSyncError = "lastRemoteSyncError"
        static let categoryTintIntensity = "categoryTintIntensity"
        static let pageTextAnimationsEnabled = "pageTextAnimationsEnabled"
        static let narrationVoiceByLanguage = "narrationVoiceByLanguage"
        static let readingGoalMinutes = "readingGoalMinutes"
        static let readingDayKey = "readingDayKey"
        static let readingSecondsToday = "readingSecondsToday"
        static let readingGoalCelebratedDayKey = "readingGoalCelebratedDayKey"
        static let readerFontScale = "readerFontScale"
        static let pageTurnStyle = "pageTurnStyle"
        static let readerTypographyStyle = "readerTypographyStyle"
        static let serverCooldownUntil = "serverCooldownUntil"
        static let categoryAffinityScores = "categoryAffinityScores"
    }
    static let dailyFactLimit = 30

    var selectedCategories: Set<String> {
        didSet { persistCategories() }
    }

    var hapticsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hapticsEnabled, forKey: Keys.hapticsEnabled)
            HapticManager.shared.isEnabled = hapticsEnabled
        }
    }

    var typingSoundEnabled: Bool {
        didSet { UserDefaults.standard.set(typingSoundEnabled, forKey: Keys.typingSoundEnabled) }
    }

    var themeMode: ReaderThemeMode {
        didSet { UserDefaults.standard.set(themeMode.rawValue, forKey: Keys.themeMode) }
    }

    var followsSystemTheme: Bool {
        didSet { UserDefaults.standard.set(followsSystemTheme, forKey: Keys.followsSystemTheme) }
    }

    var appLanguage: AppLanguage {
        didSet {
            // Product decision: English-only build.
            if appLanguage != .english {
                appLanguage = .english
                return
            }
            UserDefaults.standard.set(appLanguage.rawValue, forKey: Keys.appLanguage)
        }
    }

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    var lastReadFactID: UUID? {
        didSet { UserDefaults.standard.set(lastReadFactID?.uuidString, forKey: Keys.lastReadFactID) }
    }

    var alertsEnabled: Bool {
        didSet { UserDefaults.standard.set(alertsEnabled, forKey: Keys.alertsEnabled) }
    }

    // UX defaults: start from the beginning unless user explicitly opts into resume.
    var resumeFromLastRead: Bool {
        didSet {
            if resumeFromLastRead == false {
                resumeFromLastRead = true
                return
            }
            UserDefaults.standard.set(true, forKey: Keys.resumeFromLastRead)
        }
    }

    // First-run UX hint. Keep it persistent so we don't annoy returning users.
    var hasSeenSwipeHint: Bool {
        didSet { UserDefaults.standard.set(hasSeenSwipeHint, forKey: Keys.hasSeenSwipeHint) }
    }

    var hasSeenBookmarkHint: Bool {
        didSet { UserDefaults.standard.set(hasSeenBookmarkHint, forKey: Keys.hasSeenBookmarkHint) }
    }

    private var dailyViewDayKey: String {
        didSet { UserDefaults.standard.set(dailyViewDayKey, forKey: Keys.dailyViewDayKey) }
    }

    private var dailyViewedFactIDs: Set<UUID> {
        didSet {
            UserDefaults.standard.set(dailyViewedFactIDs.map(\.uuidString), forKey: Keys.dailyViewedFactIDs)
        }
    }

    private var dailyViewedPageIndices: Set<Int> {
        didSet {
            UserDefaults.standard.set(Array(dailyViewedPageIndices).sorted(), forKey: Keys.dailyViewedPageIndices)
        }
    }

    private var dailyWindowStartIndex: Int {
        didSet { UserDefaults.standard.set(dailyWindowStartIndex, forKey: Keys.dailyWindowStartIndex) }
    }

    private var serverCooldownUntil: Date? {
        didSet { UserDefaults.standard.set(serverCooldownUntil, forKey: Keys.serverCooldownUntil) }
    }

    // Sync telemetry for empty and error states.
    var lastRemoteFetchCount: Int {
        didSet { UserDefaults.standard.set(lastRemoteFetchCount, forKey: Keys.lastRemoteFetchCount) }
    }

    var lastRemoteSyncError: String? {
        didSet { UserDefaults.standard.set(lastRemoteSyncError, forKey: Keys.lastRemoteSyncError) }
    }

    // 0...1, used as a subtle multiplier so category colors stay "glass-first".
    var categoryTintIntensity: Double {
        didSet {
            UserDefaults.standard.set(categoryTintIntensity, forKey: Keys.categoryTintIntensity)
        }
    }

    // Extra motion beyond iOS Reduce Motion / accessibility.
    var pageTextAnimationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(pageTextAnimationsEnabled, forKey: Keys.pageTextAnimationsEnabled)
        }
    }

    // Voice identifier persisted per language code (e.g. "en", "te").
    private var narrationVoiceByLanguage: [String: String] {
        didSet { persistNarrationVoiceMap() }
    }

    var readingGoalMinutes: Int {
        didSet {
            UserDefaults.standard.set(readingGoalMinutes, forKey: Keys.readingGoalMinutes)
        }
    }

    var readerFontScale: Double {
        didSet {
            let clamped = min(max(readerFontScale, 0.86), 1.24)
            if clamped != readerFontScale {
                readerFontScale = clamped
                return
            }
            UserDefaults.standard.set(readerFontScale, forKey: Keys.readerFontScale)
        }
    }

    var pageTurnStyle: PageTurnStyle {
        didSet {
            UserDefaults.standard.set(pageTurnStyle.rawValue, forKey: Keys.pageTurnStyle)
        }
    }

    var readerTypographyStyle: ReaderTypographyStyle {
        didSet {
            UserDefaults.standard.set(readerTypographyStyle.rawValue, forKey: Keys.readerTypographyStyle)
        }
    }

    private var readingDayKey: String {
        didSet { UserDefaults.standard.set(readingDayKey, forKey: Keys.readingDayKey) }
    }

    private var readingSecondsToday: Int {
        didSet { UserDefaults.standard.set(readingSecondsToday, forKey: Keys.readingSecondsToday) }
    }

    private var readingGoalCelebratedDayKey: String? {
        didSet { UserDefaults.standard.set(readingGoalCelebratedDayKey, forKey: Keys.readingGoalCelebratedDayKey) }
    }

    // On-device personalization score map (category -> score).
    private var categoryAffinityScores: [String: Double] {
        didSet { persistCategoryAffinityScores() }
    }

    init() {
        let storedHasCompletedOnboarding =
            UserDefaults.standard.object(forKey: Keys.hasCompletedOnboarding) as? Bool ?? false
        let storedCategories = UserDefaults.standard.array(forKey: Keys.selectedCategories) as? [String]
        let resolved = Set((storedCategories ?? []).filter { $0.isEmpty == false })
        selectedCategories = Self.normalizedCategories(resolved)

        let storedHaptics = UserDefaults.standard.object(forKey: Keys.hapticsEnabled) as? Bool ?? true
        hapticsEnabled = storedHaptics
        HapticManager.shared.isEnabled = storedHaptics
        typingSoundEnabled =
            UserDefaults.standard.object(forKey: Keys.typingSoundEnabled) as? Bool ?? true

        let storedTheme = UserDefaults.standard.string(forKey: Keys.themeMode)
        themeMode = ReaderThemeMode(rawValue: storedTheme ?? "light") ?? .light
        followsSystemTheme = UserDefaults.standard.object(forKey: Keys.followsSystemTheme) as? Bool ?? true

        appLanguage = .english

        hasCompletedOnboarding = storedHasCompletedOnboarding

        if let storedID = UserDefaults.standard.string(forKey: Keys.lastReadFactID) {
            lastReadFactID = UUID(uuidString: storedID)
        } else {
            lastReadFactID = nil
        }

        alertsEnabled = UserDefaults.standard.object(forKey: Keys.alertsEnabled) as? Bool ?? false

        resumeFromLastRead = true

        hasSeenSwipeHint = UserDefaults.standard.object(forKey: Keys.hasSeenSwipeHint) as? Bool ?? false
        hasSeenBookmarkHint = UserDefaults.standard.object(forKey: Keys.hasSeenBookmarkHint) as? Bool ?? false

        dailyViewDayKey = UserDefaults.standard.string(forKey: Keys.dailyViewDayKey) ?? Self.dayKey(for: Date())
        if let storedIDs = UserDefaults.standard.array(forKey: Keys.dailyViewedFactIDs) as? [String] {
            dailyViewedFactIDs = Set(storedIDs.compactMap(UUID.init(uuidString:)))
        } else {
            dailyViewedFactIDs = []
        }
        if let storedPageIndices = UserDefaults.standard.array(forKey: Keys.dailyViewedPageIndices) as? [Int] {
            dailyViewedPageIndices = Set(storedPageIndices.filter { $0 >= 0 })
        } else {
            dailyViewedPageIndices = []
        }
        let storedWindowStart = UserDefaults.standard.object(forKey: Keys.dailyWindowStartIndex) as? Int ?? 0
        dailyWindowStartIndex = Self.normalizedWindowStart(storedWindowStart)
        serverCooldownUntil = UserDefaults.standard.object(forKey: Keys.serverCooldownUntil) as? Date
        lastRemoteFetchCount = UserDefaults.standard.integer(forKey: Keys.lastRemoteFetchCount)
        lastRemoteSyncError = UserDefaults.standard.string(forKey: Keys.lastRemoteSyncError)

        let storedIntensity = UserDefaults.standard.object(forKey: Keys.categoryTintIntensity) as? Double
        categoryTintIntensity = storedIntensity ?? 0.9

        pageTextAnimationsEnabled =
            UserDefaults.standard.object(forKey: Keys.pageTextAnimationsEnabled) as? Bool ?? true

        if
            let raw = UserDefaults.standard.data(forKey: Keys.narrationVoiceByLanguage),
            let map = try? JSONDecoder().decode([String: String].self, from: raw)
        {
            narrationVoiceByLanguage = map
        } else {
            narrationVoiceByLanguage = [:]
        }

        let storedGoal = UserDefaults.standard.object(forKey: Keys.readingGoalMinutes) as? Int
        readingGoalMinutes = min(max(storedGoal ?? 20, 5), 180)
        let storedScale = UserDefaults.standard.object(forKey: Keys.readerFontScale) as? Double
        readerFontScale = min(max(storedScale ?? 1.0, 0.86), 1.24)
        let storedTurn = UserDefaults.standard.string(forKey: Keys.pageTurnStyle)
        pageTurnStyle = PageTurnStyle(rawValue: storedTurn ?? "curl") ?? .curl
        let storedTypography = UserDefaults.standard.string(forKey: Keys.readerTypographyStyle)
        readerTypographyStyle = ReaderTypographyStyle(rawValue: storedTypography ?? "original") ?? .original
        readingDayKey = UserDefaults.standard.string(forKey: Keys.readingDayKey) ?? Self.dayKey(for: Date())
        readingSecondsToday = UserDefaults.standard.integer(forKey: Keys.readingSecondsToday)
        readingGoalCelebratedDayKey = UserDefaults.standard.string(forKey: Keys.readingGoalCelebratedDayKey)
        if
            let raw = UserDefaults.standard.data(forKey: Keys.categoryAffinityScores),
            let map = try? JSONDecoder().decode([String: Double].self, from: raw)
        {
            categoryAffinityScores = map
        } else {
            categoryAffinityScores = [:]
        }

        refreshDailyBucketIfNeeded()
        refreshReadingBucketIfNeeded()
        normalizeServerCooldownStateIfNeeded()
    }

    func toggleCategory(_ category: String) {
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

    func applySelectedCategories(_ categories: Set<String>) {
        selectedCategories = Self.normalizedCategories(categories)
    }

    func trackCategoryRead(_ rawCategory: String, weight: Double = 1.0) {
        let category = Fact.canonicalCategory(rawCategory)
        guard Fact.allCategories.contains(category) else { return }
        let clampedWeight = min(max(weight, 0.2), 8.0)
        let current = categoryAffinityScores[category] ?? 0
        categoryAffinityScores[category] = current + clampedWeight
    }

    func personalizedCategories(limit: Int = 4, excluding selected: Set<String> = []) -> [String] {
        let sorted = Fact.allCategories.sorted { lhs, rhs in
            let l = categoryAffinityScores[lhs] ?? 0
            let r = categoryAffinityScores[rhs] ?? 0
            if l != r { return l > r }
            return lhs < rhs
        }
        let filtered = sorted.filter { selected.contains($0) == false && (categoryAffinityScores[$0] ?? 0) > 0 }
        return Array(filtered.prefix(max(1, limit)))
    }

    func applyPersonalizedCategoryMix(targetCount: Int = 4) {
        let desiredCount = min(max(targetCount, 2), Fact.allCategories.count)
        var picked: [String] = []
        let ranked = Fact.allCategories.sorted { lhs, rhs in
            let l = categoryAffinityScores[lhs] ?? 0
            let r = categoryAffinityScores[rhs] ?? 0
            if l != r { return l > r }
            return lhs < rhs
        }

        for category in ranked where picked.count < desiredCount {
            picked.append(category)
        }
        if picked.count < desiredCount {
            for category in Fact.allCategories where picked.contains(category) == false {
                picked.append(category)
                if picked.count == desiredCount { break }
            }
        }
        selectedCategories = Set(picked)
    }

    func clearReadingPosition() {
        lastReadFactID = nil
        UserDefaults.standard.removeObject(forKey: Keys.lastReadFactID)
    }

    func markFactViewed(_ id: UUID?) {
        refreshDailyBucketIfNeeded()
        guard let id else { return }
        dailyViewedFactIDs.insert(id)
    }

    func markPageViewed(_ pageIndex: Int?) {
        refreshDailyBucketIfNeeded()
        guard let pageIndex, pageIndex >= 0 else { return }
        guard canAccessPage(pageIndex) else { return }
        dailyViewedPageIndices.insert(pageIndex)
    }

    var isServerCoolingDown: Bool {
        normalizeServerCooldownStateIfNeeded()
        guard let serverCooldownUntil else { return false }
        return serverCooldownUntil > Date()
    }

    var serverCooldownResetDate: Date? {
        normalizeServerCooldownStateIfNeeded()
        return serverCooldownUntil
    }

    var hasReachedDailyFactLimit: Bool {
        false
    }

    func canAccessFact(_ id: UUID?) -> Bool {
        id != nil
    }

    func canAccessPage(_ pageIndex: Int?) -> Bool {
        guard let pageIndex else { return false }
        return pageIndex >= 0
    }

    func activateServerCooldown(until date: Date) {
        serverCooldownUntil = date
    }

    func clearServerCooldown() {
        serverCooldownUntil = nil
    }

    var dailyLimitModeMessage: String {
        "All facts are available offline."
    }

    var dailyLimitResetDate: Date {
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        return Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(60 * 60)
    }

    var effectiveDailyLimitResetDate: Date {
        dailyLimitResetDate
    }

    func narrationVoiceIdentifier(for languageCode: String) -> String? {
        let key = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.isEmpty == false else { return nil }
        return narrationVoiceByLanguage[key]
    }

    func setNarrationVoiceIdentifier(_ identifier: String?, for languageCode: String) {
        let key = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.isEmpty == false else { return }
        if let identifier, identifier.isEmpty == false {
            narrationVoiceByLanguage[key] = identifier
        } else {
            narrationVoiceByLanguage.removeValue(forKey: key)
        }
    }

    var readingGoalProgress: Double {
        refreshReadingBucketIfNeeded()
        let goalSeconds = max(1, readingGoalMinutes * 60)
        return min(1.0, Double(readingSecondsToday) / Double(goalSeconds))
    }

    var todayReadingSecondsValue: Int {
        refreshReadingBucketIfNeeded()
        return readingSecondsToday
    }

    var hasReachedReadingGoal: Bool {
        readingGoalProgress >= 1.0
    }

    func addReadingSeconds(_ seconds: Int) {
        guard seconds > 0 else { return }
        refreshReadingBucketIfNeeded()
        readingSecondsToday += seconds
    }

    func consumeReadingGoalCelebrationIfNeeded() -> Bool {
        refreshReadingBucketIfNeeded()
        guard hasReachedReadingGoal else { return false }
        let todayKey = Self.dayKey(for: Date())
        guard readingGoalCelebratedDayKey != todayKey else { return false }
        readingGoalCelebratedDayKey = todayKey
        return true
    }

    private func persistCategories() {
        UserDefaults.standard.set(Array(selectedCategories).sorted(), forKey: Keys.selectedCategories)
    }

    private func persistNarrationVoiceMap() {
        if let encoded = try? JSONEncoder().encode(narrationVoiceByLanguage) {
            UserDefaults.standard.set(encoded, forKey: Keys.narrationVoiceByLanguage)
        }
    }

    private func persistCategoryAffinityScores() {
        if let encoded = try? JSONEncoder().encode(categoryAffinityScores) {
            UserDefaults.standard.set(encoded, forKey: Keys.categoryAffinityScores)
        }
    }

    private static func normalizedCategories(_ source: Set<String>) -> Set<String> {
        var valid = source.filter { Fact.allCategories.contains($0) }
        if valid.count >= 2 { return valid }

        for fallback in Fact.allCategories where valid.contains(fallback) == false {
            valid.insert(fallback)
            if valid.count >= 2 { break }
        }
        return valid
    }

    private func refreshDailyBucketIfNeeded() {
        let todayKey = Self.dayKey(for: Date())
        guard dailyViewDayKey != todayKey else { return }
        if dailyWindowProgressCount >= Self.dailyFactLimit {
            dailyWindowStartIndex = Self.normalizedWindowStart(dailyWindowStartIndex) + Self.dailyFactLimit
        }
        dailyViewDayKey = todayKey
        dailyViewedFactIDs = []
        dailyViewedPageIndices = []
        // Offline-first build: no remote refresh trigger.
    }

    private func normalizeServerCooldownStateIfNeeded() {
        guard let serverCooldownUntil else { return }
        if serverCooldownUntil <= Date() {
            self.serverCooldownUntil = nil
        }
    }

    private func refreshReadingBucketIfNeeded() {
        let todayKey = Self.dayKey(for: Date())
        guard readingDayKey != todayKey else { return }
        readingDayKey = todayKey
        readingSecondsToday = 0
        readingGoalCelebratedDayKey = nil
    }

    private static func dayKey(for date: Date) -> String {
        let start = Calendar.current.startOfDay(for: date)
        return String(Int(start.timeIntervalSince1970))
    }

    private static func normalizedWindowStart(_ value: Int) -> Int {
        let clamped = max(0, value)
        return (clamped / dailyFactLimit) * dailyFactLimit
    }

    private var dailyWindowEndIndex: Int {
        dailyWindowStartIndex + max(0, Self.dailyFactLimit - 1)
    }

    private var dailyWindowProgressCount: Int {
        let visibleInWindow = dailyViewedPageIndices.filter { $0 >= dailyWindowStartIndex && $0 <= dailyWindowEndIndex }
        return visibleInWindow.count
    }
}
