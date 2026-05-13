import SwiftData
import SwiftUI
import UserNotifications

private actor SeedGate {
    private var running = false

    func begin() -> Bool {
        guard running == false else { return false }
        running = true
        return true
    }

    func end() {
        running = false
    }
}

private struct BundledFactsPayload: Decodable {
    let facts: [BundledFact]
}

private struct BundledFact: Decodable {
    let category: String
    let title: String
    let body: String
    let order: Int
    let isActive: Bool?
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            await FactReminderNotifications.shared.clearDeliveredAndBadge()
        }
        completionHandler()
    }
}

@main
struct FactReadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var viewModel = FactViewModel()
    @State private var settings = AppSettings()
    @State private var didRunInitialSeed = false

    private let sharedModelContainer: ModelContainer = FactReadApp.makeModelContainer()
    private let seedGate = SeedGate()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .environment(settings)
                .task {
                    guard didRunInitialSeed == false else { return }
                    didRunInitialSeed = true
                    Task(priority: .utility) {
                        await seedFactsIfNeeded()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func seedFactsIfNeeded() async {
        guard await seedGate.begin() else { return }
        defer { Task { await seedGate.end() } }

        let context = ModelContext(sharedModelContainer)
        syncBundledFacts(context: context)
        await MainActor.run {
            settings.lastRemoteFetchCount = (try? context.fetchCount(FetchDescriptor<Fact>())) ?? 0
            settings.lastRemoteSyncError = nil
            settings.clearServerCooldown()
            NotificationCenter.default.post(name: .factLibraryDidChange, object: nil)
        }
    }

    private func syncBundledFacts(context: ModelContext) {
        guard let bundled = loadBundledFacts(), bundled.isEmpty == false else { return }

        let activeFacts = bundled.filter { $0.isActive ?? true }
        let curated = activeFacts.map {
            (
                id: UUID.stableHash("en|\($0.category)|\($0.order)"),
                category: Fact.canonicalCategory($0.category),
                sortIndex: max(0, $0.order),
                title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: $0.body.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }.filter {
            $0.title.isEmpty == false && $0.body.isEmpty == false
        }

        var curatedByID: [UUID: (id: UUID, category: String, sortIndex: Int, title: String, body: String)] = [:]
        for item in curated {
            if curatedByID[item.id] == nil {
                curatedByID[item.id] = item
            }
        }
        let curatedIDs = Set(curatedByID.keys)

        let descriptor = FetchDescriptor<Fact>()
        let existing = (try? context.fetch(descriptor)) ?? []
        var existingByID: [UUID: Fact] = [:]
        for item in existing where existingByID[item.id] == nil {
            existingByID[item.id] = item
        }

        var hasMutations = false

        for fact in existing where curatedIDs.contains(fact.id) == false {
            context.delete(fact)
            hasMutations = true
        }

        let orderedCurated = curated.sorted { lhs, rhs in
            if lhs.category == rhs.category { return lhs.sortIndex < rhs.sortIndex }
            return lhs.category < rhs.category
        }

        for (position, item) in orderedCurated.enumerated() {
            if let existingFact = existingByID[item.id] {
                var changed = false
                if existingFact.languageCode != "en" {
                    existingFact.languageCode = "en"
                    changed = true
                }
                if existingFact.category != item.category {
                    existingFact.category = item.category
                    changed = true
                }
                if existingFact.sortIndex != item.sortIndex {
                    existingFact.sortIndex = item.sortIndex
                    changed = true
                }
                if existingFact.title != item.title {
                    existingFact.title = item.title
                    changed = true
                }
                if existingFact.body != item.body {
                    existingFact.body = item.body
                    changed = true
                }
                if changed { hasMutations = true }
                continue
            }

            context.insert(
                Fact(
                    id: item.id,
                    languageCode: "en",
                    category: item.category,
                    sortIndex: item.sortIndex,
                    title: item.title,
                    body: item.body,
                    highlightedPhrases: nil,
                    isBookmarked: false,
                    createdAt: Date(timeIntervalSince1970: TimeInterval(1_680_100_000 + position))
                )
            )
            hasMutations = true
        }

        if hasMutations {
            try? context.save()
        }
    }

    private func loadBundledFacts() -> [BundledFact]? {
        let decoder = JSONDecoder()
        var candidates: [URL] = []
        candidates.append(contentsOf: Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Facts") ?? [])
        candidates.append(contentsOf: Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])

        // Keep deterministic order while avoiding duplicate decode work when files are discovered twice.
        var seenPaths = Set<String>()
        let categoryURLs = candidates
            .filter { seenPaths.insert($0.path).inserted }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard categoryURLs.isEmpty == false else { return nil }

        var merged: [BundledFact] = []
        for url in categoryURLs {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let payload = try? decoder.decode(BundledFactsPayload.self, from: data) else { continue }
            merged.append(contentsOf: payload.facts)
        }
        return merged.isEmpty ? nil : merged
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([Fact.self, BookmarkCollection.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let inMemoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            do {
                return try ModelContainer(for: schema, configurations: [inMemoryConfiguration])
            } catch {
                fatalError("Could not create ModelContainer (disk + in-memory both failed): \(error)")
            }
        }
    }
}
