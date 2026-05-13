import SwiftData
import SwiftUI

struct BookmarksView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<Fact> { $0.isBookmarked }, sort: [SortDescriptor(\Fact.createdAt)]) private var bookmarks: [Fact]
    @Query(sort: [SortDescriptor(\BookmarkCollection.createdAt)]) private var collections: [BookmarkCollection]

    let onOpenFact: (Fact) -> Void
    let palette: ReaderTheme.Palette

    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var selectedCollectionID: UUID? = nil
    @State private var showNewCollectionAlert = false
    @State private var newCollectionName = ""

    private var sortedBookmarks: [Fact] {
        bookmarks.sorted { $0.createdAt > $1.createdAt }
    }

    private var collectionScopedBookmarks: [Fact] {
        guard let selectedCollectionID else { return sortedBookmarks }
        return sortedBookmarks.filter { $0.belongs(to: selectedCollectionID) }
    }

    private var filteredBookmarks: [Fact] {
        let base = collectionScopedBookmarks.filter { fact in
            if let selectedCategory, fact.category != selectedCategory { return false }
            return true
        }

        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return base
        }

        let query = searchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return base.filter { fact in
            let title = fact.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            let body = fact.body.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            let category = Fact.localizedCategory(fact.category, language: settings.appLanguage.resolved)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return title.contains(query) || body.contains(query) || category.contains(query)
        }
    }

    private var groupedBookmarks: [(category: String, facts: [Fact])] {
        Dictionary(grouping: filteredBookmarks, by: \.category)
            .map { (category: $0.key, facts: $0.value) }
            .sorted { lhs, rhs in
                if lhs.category == rhs.category { return false }
                return lhs.category.localizedCaseInsensitiveCompare(rhs.category) == .orderedAscending
            }
    }

    private var categoriesWithCounts: [(category: String, count: Int)] {
        Fact.allCategories.compactMap { category in
            let count = collectionScopedBookmarks.filter { $0.category == category }.count
            return count > 0 ? (category, count) : nil
        }
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            if bookmarks.isEmpty {
                ContentUnavailableView {
                    Label(emptyText, systemImage: "bookmark")
                }
            } else {
                List {
                    collectionStrip
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 4, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    folderStrip
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 8, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    if groupedBookmarks.isEmpty {
                        Text(noResultsText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(groupedBookmarks, id: \.category) { group in
                            Section {
                                ForEach(group.facts) { fact in
                                    Button {
                                        onOpenFact(fact)
                                        dismiss()
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(fact.title)
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(2)

                                            Text(fact.body)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .padding(.vertical, 6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .liquidGlassButtonStyle(
                                        fallbackShape: RoundedRectangle(cornerRadius: 14, style: .continuous),
                                        isDark: palette.isDark
                                    )
                                    .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                                    .contextMenu {
                                        if collections.isEmpty == false {
                                            ForEach(collections, id: \.id) { collection in
                                                Button {
                                                    toggleFact(fact, in: collection)
                                                } label: {
                                                    Label(
                                                        collection.name,
                                                        systemImage: fact.belongs(to: collection.id) ? "checkmark.circle.fill" : "circle"
                                                    )
                                                }
                                            }
                                            Divider()
                                        }
                                        Button {
                                            showNewCollectionAlert = true
                                        } label: {
                                            Label("New Collection", systemImage: "plus.circle")
                                        }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            fact.isBookmarked = false
                                            fact.collectionIDs = []
                                            try? modelContext.save()
                                            HapticManager.shared.impact(.rigid)
                                        } label: {
                                            Label(removeText, systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                HStack(spacing: 8) {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(CategoryStyle.accent(for: group.category, intensity: settings.categoryTintIntensity))
                                    Text(Fact.localizedCategory(group.category, language: settings.appLanguage.resolved))
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(group.facts.count)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .background(Color(uiColor: .systemGroupedBackground))
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: searchPrompt)
            }
        }
        .navigationTitle(bookmarksTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewCollectionAlert = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
        }
        .alert("New Collection", isPresented: $showNewCollectionAlert) {
            TextField("Collection name", text: $newCollectionName)
            Button("Create") {
                createCollection()
            }
            Button("Cancel", role: .cancel) {
                newCollectionName = ""
            }
        } message: {
            Text("Create custom folders to organize your saved facts.")
        }
    }

    private var collectionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                folderChip(
                    title: "All Saves",
                    count: sortedBookmarks.count,
                    color: palette.inkSecondary,
                    isSelected: selectedCollectionID == nil
                ) {
                    selectedCollectionID = nil
                }

                ForEach(collections, id: \.id) { collection in
                    let count = sortedBookmarks.filter { $0.belongs(to: collection.id) }.count
                    if count > 0 {
                        folderChip(
                            title: collection.name,
                            count: count,
                            color: Color(hex: collection.accentHex),
                            isSelected: selectedCollectionID == collection.id
                        ) {
                            selectedCollectionID = collection.id
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteCollection(collection)
                            } label: {
                                Label("Delete Collection", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private var folderStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                folderChip(
                    title: allFoldersTitle,
                    count: sortedBookmarks.count,
                    color: palette.inkSecondary,
                    isSelected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }

                ForEach(categoriesWithCounts, id: \.category) { item in
                    folderChip(
                        title: Fact.localizedCategory(item.category, language: settings.appLanguage.resolved),
                        count: item.count,
                        color: CategoryStyle.accent(for: item.category, intensity: settings.categoryTintIntensity),
                        isSelected: selectedCategory == item.category
                    ) {
                        selectedCategory = item.category
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func folderChip(
        title: String,
        count: Int,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)

                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                Text("\(count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? color.opacity(0.45) : .white.opacity(palette.isDark ? 0.14 : 0.30), lineWidth: isSelected ? 1.2 : 0.7)
            }
        }
        .buttonStyle(.plain)
        .liquidGlassButtonStyle(
            fallbackShape: RoundedRectangle(cornerRadius: 16, style: .continuous),
            isDark: palette.isDark
        )
        .accessibilityLabel("\(title), \(count)")
    }

    private func createCollection() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        let exists = collections.contains { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }
        guard exists == false else {
            newCollectionName = ""
            return
        }
        let paletteHexes = ["5E6B52", "495A73", "6A5F74", "3F6470", "726350", "65566A"]
        let nextHex = paletteHexes[collections.count % paletteHexes.count]
        modelContext.insert(BookmarkCollection(name: trimmed, accentHex: nextHex))
        try? modelContext.save()
        HapticManager.shared.notification(.success)
        newCollectionName = ""
    }

    private func deleteCollection(_ collection: BookmarkCollection) {
        for fact in bookmarks where fact.belongs(to: collection.id) {
            fact.removeFromCollection(collection.id)
        }
        if selectedCollectionID == collection.id {
            selectedCollectionID = nil
        }
        modelContext.delete(collection)
        try? modelContext.save()
        HapticManager.shared.impact(.rigid)
    }

    private func toggleFact(_ fact: Fact, in collection: BookmarkCollection) {
        if fact.belongs(to: collection.id) {
            fact.removeFromCollection(collection.id)
        } else {
            fact.addToCollection(collection.id)
        }
        try? modelContext.save()
        HapticManager.shared.selection()
    }

    private var allFoldersTitle: String {
        "All"
    }

    private var searchPrompt: String {
        "Search bookmarks"
    }

    private var noResultsText: String {
        "No matches found"
    }

    private var bookmarksTitle: String {
        "Bookmarks"
    }

    private var removeText: String {
        "Remove"
    }

    private var emptyText: String {
        "No saved facts yet"
    }
}
