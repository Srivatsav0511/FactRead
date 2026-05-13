import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class FactViewModel {
    private struct PageAnchor {
        let category: String
        let sortIndex: Int?
        let ordinalInCategory: Int
    }

    struct PageSnapshot: Identifiable, Equatable {
        let id: UUID
        let sourceFactID: UUID
        let fact: Fact
        let lockedCategory: String
        let lockedTitle: String
        let lockedBody: String
        let lockedHighlights: [String]
        
        static func == (lhs: PageSnapshot, rhs: PageSnapshot) -> Bool {
            lhs.id == rhs.id
        }
    }

    var visiblePages: [PageSnapshot] = []
    var currentIndex: Int = 0
    // Start in loading state so launch never flashes a blank page.
    var isInitialLoading: Bool = true

    private var languageCode: String = "en"
    private var activeCategories: Set<String> = []
    private var categoryOrder: [String] = []
    private var categoryOffsets: [String: Int] = [:]
    private var categoryHasMore: [String: Bool] = [:]
    private var categoryLanguageFallback: [String: String] = [:]
    private var isLoading: Bool = false
    private var seenIDs: Set<UUID> = []
    private var sessionPageCache: [UUID: PageSnapshot] = [:]

    private let pageSizePerCategory: Int = 36
    private let prefetchThreshold: Int = 12

    var visibleFacts: [Fact] {
        visiblePages.map(\.fact)
    }

    var currentPage: PageSnapshot? {
        guard currentIndex >= 0, currentIndex < visiblePages.count else { return nil }
        return visiblePages[currentIndex]
    }

    var currentFact: Fact? {
        currentPage?.fact
    }

    func reload(
        context: ModelContext,
        settings: AppSettings,
        preserveCurrentFact: Bool = true,
        restoreFromLastRead: Bool = true
    ) async {
        isInitialLoading = true
        defer { isInitialLoading = false }
        let preservedID = preserveCurrentFact ? currentFact?.id : nil
        let preservedAnchor = preserveCurrentFact
            ? currentFact.flatMap { makePageAnchor(for: $0, context: context) }
            : nil

        languageCode = AppLanguage.canonicalLanguageCode(settings.appLanguage.bcp47Code)
        activeCategories = settings.selectedCategories
        categoryOrder = Array(settings.selectedCategories).sorted()
        categoryOffsets = Dictionary(uniqueKeysWithValues: categoryOrder.map { ($0, 0) })
        categoryHasMore = Dictionary(uniqueKeysWithValues: categoryOrder.map { ($0, true) })
        categoryLanguageFallback = [:]
        visiblePages.removeAll(keepingCapacity: true)
        seenIDs.removeAll(keepingCapacity: true)
        sessionPageCache.removeAll(keepingCapacity: true)

        // Initial load: pull chunks per category and interleave them for a mixed feed.
        await appendMixedPage(context: context, categories: categoryOrder)
        await ensureMinimumDailyPages(context: context)

        // Controlled fallback: only when selected language has no records for selected categories.
        if visiblePages.isEmpty, languageCode != "en" {
            let hasSelectedLanguageFacts = hasAnyFacts(
                for: activeCategories,
                languageCode: languageCode,
                context: context
            )
            if hasSelectedLanguageFacts == false {
                languageCode = "en"
                categoryOffsets = Dictionary(uniqueKeysWithValues: categoryOrder.map { ($0, 0) })
                categoryHasMore = Dictionary(uniqueKeysWithValues: categoryOrder.map { ($0, true) })
                categoryLanguageFallback = [:]
                seenIDs.removeAll(keepingCapacity: true)
                await appendMixedPage(context: context, categories: categoryOrder)
                await ensureMinimumDailyPages(context: context)
            }
        }
        
        restoreIndex(
            preferredID: preservedID,
            fallbackID: restoreFromLastRead ? settings.lastReadFactID : nil,
            preservedAnchor: preservedAnchor,
            context: context
        )
    }

    func applyCategoryChange(context: ModelContext, settings: AppSettings) async {
        let requestedLanguage = AppLanguage.canonicalLanguageCode(settings.appLanguage.bcp47Code)
        if visiblePages.isEmpty || requestedLanguage != languageCode {
            // If language changed or we have no session pages yet, perform a normal reload.
            await reload(context: context, settings: settings, preserveCurrentFact: true, restoreFromLastRead: false)
            return
        }

        // Real-book behavior:
        // Keep already-read pages immutable and apply category changes only to upcoming pages.
        let frozenCount = max(0, min(currentIndex + 1, visiblePages.count))
        let frozenPages = Array(visiblePages.prefix(frozenCount))
        visiblePages = frozenPages
        currentIndex = frozenPages.isEmpty ? 0 : (frozenPages.count - 1)
        seenIDs = Set(frozenPages.map(\.sourceFactID))

        activeCategories = settings.selectedCategories
        categoryOrder = Array(activeCategories).sorted()
        categoryLanguageFallback = [:]
        categoryOffsets = Dictionary(uniqueKeysWithValues: categoryOrder.map { ($0, 0) })
        categoryHasMore = Dictionary(uniqueKeysWithValues: categoryOrder.map { ($0, true) })

        for category in categoryOrder {
            // Offsets represent stable slot order per category, independent of translation availability.
            let consumed = frozenPages.filter { $0.fact.category == category }.count
            categoryOffsets[category] = consumed
        }

        await appendMixedPage(context: context, categories: categoryOrder)
        await ensureMinimumDailyPages(context: context)
    }

    func loadMoreIfNeeded(context: ModelContext, settings: AppSettings) async {
        guard languageCode == AppLanguage.canonicalLanguageCode(settings.appLanguage.bcp47Code) else { return }
        guard activeCategories == settings.selectedCategories else { return }
        guard isLoading == false else { return }
        guard visiblePages.isEmpty == false else { return }

        if currentIndex >= max(0, visiblePages.count - prefetchThreshold) {
            await appendMixedPage(context: context, categories: categoryOrder)
            await ensureMinimumDailyPages(context: context)
        }
    }

    func ensureFactVisible(_ fact: Fact, context: ModelContext, settings: AppSettings) async {
        if settings.selectedCategories.contains(fact.category) == false {
            settings.selectedCategories.insert(fact.category)
        }

        if AppLanguage.canonicalLanguageCode(settings.appLanguage.bcp47Code) != languageCode {
            await reload(context: context, settings: settings, preserveCurrentFact: false)
        } else {
            await applyCategoryChange(context: context, settings: settings)
        }

        if let idx = visiblePages.firstIndex(where: { $0.sourceFactID == fact.id }) {
            currentIndex = idx
            return
        }

        // Ensure we can jump to the exact fact even if it isn't in the initial chunk for its category.
        if visiblePages.contains(where: { $0.sourceFactID == fact.id }) == false {
            visiblePages.append(snapshot(for: fact))
            seenIDs.insert(fact.id)
            currentIndex = max(0, visiblePages.count - 1)
        }
    }

    private func appendMixedPage(context: ModelContext, categories: [String]) async {
        guard categories.isEmpty == false else { return }
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }

        var buckets: [String: [Fact]] = [:]
        var maxCount = 0
        for category in categories {
            let page = fetchNextPage(for: category, context: context)
            guard page.isEmpty == false else { continue }
            buckets[category] = page
            maxCount = max(maxCount, page.count)
        }

        guard maxCount > 0 else { return }

        var mixed: [Fact] = []
        mixed.reserveCapacity(buckets.values.reduce(0) { $0 + $1.count })
        for i in 0..<maxCount {
            for category in categories {
                if let bucket = buckets[category], bucket.indices.contains(i) {
                    let fact = bucket[i]
                    mixed.append(fact)
                }
            }
        }

        let unique = mixed.filter { seenIDs.insert($0.id).inserted }
        let snapshots = unique.map { snapshot(for: $0) }
        visiblePages.append(contentsOf: snapshots)
    }

    private func ensureMinimumDailyPages(context: ModelContext) async {
        guard visiblePages.count < AppSettings.dailyFactLimit else { return }
        guard categoryOrder.isEmpty == false else { return }

        var attempts = 0
        var stalledAttempts = 0
        let maxAttempts = max(12, categoryOrder.count * 8)

        while visiblePages.count < AppSettings.dailyFactLimit, attempts < maxAttempts {
            let hasRemainingCategoryData = categoryOrder.contains { categoryHasMore[$0, default: false] }
            if hasRemainingCategoryData == false { break }

            let before = visiblePages.count
            await appendMixedPage(context: context, categories: categoryOrder)
            attempts += 1

            if visiblePages.count == before {
                stalledAttempts += 1
            } else {
                stalledAttempts = 0
            }

            if stalledAttempts >= 2 { break }
        }

        // Final safety pass: deterministically backfill from selected categories so
        // we still reach a full 30-page daily window whenever enough source facts exist.
        if visiblePages.count < AppSettings.dailyFactLimit {
            appendDeterministicBackfill(context: context)
        }
    }

    private func fetchNextPage(for category: String, context: ModelContext) -> [Fact] {
        guard categoryHasMore[category] == true else { return [] }
        let preferredLang = AppLanguage.canonicalLanguageCode(languageCode)
        let lang = categoryLanguageFallback[category] ?? preferredLang
        let offset = categoryOffsets[category, default: 0]

        if lang == "en" {
            let englishPage = fetchPage(for: category, languageCode: "en", offset: offset, context: context)
            if englishPage.isEmpty == false {
                categoryOffsets[category, default: 0] += englishPage.count
                return englishPage
            }

            categoryHasMore[category] = false
            return []
        }

        // Keep stable slot order from English and only swap to selected language
        // when that exact slot (same sortIndex) exists.
        let englishBasePage = fetchPage(for: category, languageCode: "en", offset: offset, context: context)
        if englishBasePage.isEmpty == false {
            var mapped: [Fact] = []
            mapped.reserveCapacity(englishBasePage.count)
            var usedPageIDs: Set<UUID> = []

            for englishFact in englishBasePage {
                let resolved = resolvedFactForStableSlot(
                    englishFact: englishFact,
                    preferredLanguageCode: lang,
                    usedIDsInBatch: &usedPageIDs,
                    context: context
                )
                mapped.append(resolved)
            }
            categoryOffsets[category, default: 0] += englishBasePage.count
            return mapped
        }

        // If no English base exists for this category, use selected language as a fallback.
        // This keeps content available without changing the strict slot rule where English exists.
        let selectedPage = fetchPage(for: category, languageCode: lang, offset: offset, context: context)
        if selectedPage.isEmpty == false {
            categoryLanguageFallback[category] = lang
            categoryOffsets[category, default: 0] += selectedPage.count
            return selectedPage
        }

        categoryHasMore[category] = false
        return []
    }

    private func resolvedFactForStableSlot(
        englishFact: Fact,
        preferredLanguageCode: String,
        usedIDsInBatch: inout Set<UUID>,
        context: ModelContext
    ) -> Fact {
        let preferred = AppLanguage.canonicalLanguageCode(preferredLanguageCode)
        guard preferred != "en", englishFact.sortIndex != Int.max else {
            usedIDsInBatch.insert(englishFact.id)
            return englishFact
        }

        if let translated = fact(
            in: englishFact.category,
            languageCode: preferred,
            sortIndex: englishFact.sortIndex,
            context: context
        ) {
            // If slot mapping collapses to a duplicate translated ID (common when
            // upstream has repeated sortIndex values), fall back to the English slot
            // so pagination continues with unique pages.
            if usedIDsInBatch.contains(translated.id) == false,
               seenIDs.contains(translated.id) == false {
                usedIDsInBatch.insert(translated.id)
                return translated
            }
        }

        usedIDsInBatch.insert(englishFact.id)
        return englishFact
    }

    private func appendDeterministicBackfill(context: ModelContext) {
        guard visiblePages.count < AppSettings.dailyFactLimit else { return }
        guard categoryOrder.isEmpty == false else { return }

        let preferred = AppLanguage.canonicalLanguageCode(languageCode)
        var usedInBackfill: Set<UUID> = []

        for category in categoryOrder {
            let englishFacts = facts(in: category, languageCode: "en", context: context)
            guard englishFacts.isEmpty == false else { continue }

            for englishFact in englishFacts {
                let candidate = resolvedFactForStableSlot(
                    englishFact: englishFact,
                    preferredLanguageCode: preferred,
                    usedIDsInBatch: &usedInBackfill,
                    context: context
                )
                guard seenIDs.contains(candidate.id) == false else { continue }

                visiblePages.append(snapshot(for: candidate))
                seenIDs.insert(candidate.id)

                if visiblePages.count >= AppSettings.dailyFactLimit {
                    return
                }
            }
        }
    }

    private func fetchPage(for category: String, languageCode lang: String, offset: Int, context: ModelContext) -> [Fact] {
        let canonicalLang = AppLanguage.canonicalLanguageCode(lang)
        let acceptEmptyLanguageCodeAsEnglish = (canonicalLang == "en")

        var descriptor = FetchDescriptor<Fact>(
            predicate: #Predicate<Fact> { fact in
                fact.category == category
            },
            sortBy: [
                SortDescriptor(\Fact.sortIndex, order: .forward),
                SortDescriptor(\Fact.createdAt, order: .forward)
            ]
        )
        let facts = (try? context.fetch(descriptor)) ?? []
        let filtered = facts.filter { fact in
            let code = AppLanguage.canonicalLanguageCode(fact.languageCode)
            if code == canonicalLang { return true }
            return acceptEmptyLanguageCodeAsEnglish && fact.languageCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard offset < filtered.count else { return [] }
        let end = min(filtered.count, offset + pageSizePerCategory)
        return Array(filtered[offset..<end])
    }

    private func hasAnyFacts(for categories: Set<String>, languageCode lang: String, context: ModelContext) -> Bool {
        guard categories.isEmpty == false else { return false }
        let targetCode = AppLanguage.canonicalLanguageCode(lang)
        let allFacts = (try? context.fetch(FetchDescriptor<Fact>())) ?? []
        guard allFacts.isEmpty == false else { return false }

        return allFacts.contains { fact in
            guard categories.contains(fact.category) else { return false }
            let canonical = AppLanguage.canonicalLanguageCode(fact.languageCode)
            if canonical == targetCode { return true }
            return targetCode == "en" && fact.languageCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func restoreIndex(
        preferredID: UUID?,
        fallbackID: UUID?,
        preservedAnchor: PageAnchor?,
        context: ModelContext
    ) {
        if preferredID == nil && fallbackID == nil {
            if restoreUsingAnchor(preservedAnchor, context: context) {
                return
            }
            currentIndex = 0
            return
        }
        if let preferredID, let idx = visiblePages.firstIndex(where: { $0.sourceFactID == preferredID }) {
            currentIndex = idx
            return
        }
        if restoreUsingAnchor(preservedAnchor, context: context) {
            return
        }
        if let fallbackID, let idx = visiblePages.firstIndex(where: { $0.sourceFactID == fallbackID }) {
            currentIndex = idx
            return
        }
        currentIndex = min(currentIndex, max(visiblePages.count - 1, 0))
    }

    private func restoreUsingAnchor(_ anchor: PageAnchor?, context: ModelContext) -> Bool {
        guard let anchor else { return false }
        if let targetSortIndex = anchor.sortIndex {
            let selectedLanguageFact = fact(
                in: anchor.category,
                languageCode: languageCode,
                sortIndex: targetSortIndex,
                context: context
            )
            let englishFallbackFact = languageCode == "en" ? nil : fact(
                in: anchor.category,
                languageCode: "en",
                sortIndex: targetSortIndex,
                context: context
            )

            if let anchoredFact = selectedLanguageFact ?? englishFallbackFact {
                if let idx = visiblePages.firstIndex(where: { $0.sourceFactID == anchoredFact.id }) {
                    currentIndex = idx
                    return true
                }

                visiblePages.append(snapshot(for: anchoredFact))
                seenIDs.insert(anchoredFact.id)
                currentIndex = max(visiblePages.count - 1, 0)
                return true
            }
        }

        var orderedFacts = facts(
            in: anchor.category,
            languageCode: languageCode,
            context: context
        )

        // Strict fallback rule: if selected language misses this exact slot,
        // use the same slot from English instead of jumping to a different fact.
        if orderedFacts.indices.contains(anchor.ordinalInCategory) == false, languageCode != "en" {
            orderedFacts = facts(
                in: anchor.category,
                languageCode: "en",
                context: context
            )
        }
        guard orderedFacts.indices.contains(anchor.ordinalInCategory) else { return false }

        let anchoredFact = orderedFacts[anchor.ordinalInCategory]
        if let idx = visiblePages.firstIndex(where: { $0.sourceFactID == anchoredFact.id }) {
            currentIndex = idx
            return true
        }

        visiblePages.append(snapshot(for: anchoredFact))
        seenIDs.insert(anchoredFact.id)
        currentIndex = max(visiblePages.count - 1, 0)
        return true
    }

    private func makePageAnchor(for fact: Fact, context: ModelContext) -> PageAnchor? {
        let anchorLanguageCode = AppLanguage.canonicalLanguageCode(fact.languageCode)
        let orderedFacts = facts(
            in: fact.category,
            languageCode: anchorLanguageCode,
            context: context
        )
        guard let ordinal = orderedFacts.firstIndex(where: { $0.id == fact.id }) else { return nil }
        let sortIndex = fact.sortIndex == Int.max ? nil : fact.sortIndex
        return PageAnchor(category: fact.category, sortIndex: sortIndex, ordinalInCategory: ordinal)
    }

    private func facts(in category: String, languageCode: String, context: ModelContext) -> [Fact] {
        let aliases = Set(AppLanguage.languageCodeAliases(for: languageCode))
        let includeEmptyCodeAsEnglish = (languageCode == "en")
        let allFacts = (try? context.fetch(FetchDescriptor<Fact>())) ?? []

        return allFacts
            .filter { fact in
                guard fact.category == category else { return false }
                if aliases.contains(fact.languageCode) {
                    return true
                }
                return includeEmptyCodeAsEnglish && fact.languageCode.isEmpty
            }
            .sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex {
                    return lhs.sortIndex < rhs.sortIndex
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func fact(
        in category: String,
        languageCode: String,
        sortIndex: Int,
        context: ModelContext
    ) -> Fact? {
        facts(in: category, languageCode: languageCode, context: context)
            .first(where: { $0.sortIndex == sortIndex })
    }

    private func snapshot(for fact: Fact) -> PageSnapshot {
        if let cached = sessionPageCache[fact.id] {
            return cached
        }

        let snapshot = PageSnapshot(
            id: UUID(),
            sourceFactID: fact.id,
            fact: fact,
            lockedCategory: fact.category,
            lockedTitle: fact.title,
            lockedBody: fact.body,
            lockedHighlights: fact.highlightedPhrases ?? []
        )
        sessionPageCache[fact.id] = snapshot
        return snapshot
    }

}
