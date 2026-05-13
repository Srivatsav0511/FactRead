import Foundation
import SwiftData
import SwiftUI

@Model
final class Fact {
    var id: UUID
    var languageCode: String
    var category: String
    var sortIndex: Int
    var title: String
    var body: String
    var highlightedPhrasesStorage: String
    var isBookmarked: Bool
    var collectionIDsStorage: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        languageCode: String = "en",
        category: String,
        sortIndex: Int = Int.max,
        title: String,
        body: String,
        highlightedPhrases: [String]? = nil,
        isBookmarked: Bool = false,
        collectionIDs: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.languageCode = languageCode
        self.category = category
        self.sortIndex = sortIndex
        self.title = title
        self.body = body
        self.highlightedPhrasesStorage = Self.encodeHighlights(highlightedPhrases)
        self.isBookmarked = isBookmarked
        self.collectionIDsStorage = Self.encodeCollectionIDs(collectionIDs)
        self.createdAt = createdAt
    }

    var highlightedPhrases: [String]? {
        get { Self.decodeHighlights(highlightedPhrasesStorage) }
        set { highlightedPhrasesStorage = Self.encodeHighlights(newValue) }
    }

    var collectionIDs: [UUID] {
        get { Self.decodeCollectionIDs(collectionIDsStorage) }
        set { collectionIDsStorage = Self.encodeCollectionIDs(newValue) }
    }

    func belongs(to collectionID: UUID) -> Bool {
        collectionIDs.contains(collectionID)
    }

    func addToCollection(_ collectionID: UUID) {
        var ids = Set(collectionIDs)
        ids.insert(collectionID)
        collectionIDs = Array(ids)
    }

    func removeFromCollection(_ collectionID: UUID) {
        let ids = collectionIDs.filter { $0 != collectionID }
        collectionIDs = ids
    }

    private static func encodeHighlights(_ value: [String]?) -> String {
        guard let value, value.isEmpty == false else { return "" }
        return value.joined(separator: "|||")
    }

    private static func decodeHighlights(_ value: String) -> [String]? {
        guard value.isEmpty == false else { return nil }
        return value.components(separatedBy: "|||").filter { $0.isEmpty == false }
    }

    private static func encodeCollectionIDs(_ ids: [UUID]) -> String {
        guard ids.isEmpty == false else { return "" }
        return ids.map(\.uuidString).joined(separator: ",")
    }

    private static func decodeCollectionIDs(_ storage: String) -> [UUID] {
        guard storage.isEmpty == false else { return [] }
        return storage
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
    }
}

extension Fact {
    static let allCategories: [String] = [
        "Science", "Space", "Nature", "Human Body", "History", "Technology", "Psychology", "Ocean", "Animals", "Movies"
    ]

    static func canonicalCategory(_ category: String) -> String {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return category }
        if allCategories.contains(trimmed) { return trimmed }

        let normalized = normalizeCategoryKey(trimmed)
        if let mapped = categoryAliases[normalized] {
            return mapped
        }
        return trimmed
    }

    static func tint(for category: String) -> Color {
        switch canonicalCategory(category) {
        case "Science": return Color(hex: "4A6785")
        case "Space": return Color(hex: "495A73")
        case "Nature": return Color(hex: "5E6B52")
        case "Human Body": return Color(hex: "6D5B5B")
        case "History": return Color(hex: "726350")
        case "Technology": return Color(hex: "505E6E")
        case "Psychology": return Color(hex: "6A5F74")
        case "Ocean": return Color(hex: "3F6470")
        case "Animals": return Color(hex: "695D4E")
        case "Movies": return Color(hex: "65566A")
        default: return .secondary
        }
    }

    static func localizedCategory(_ category: String, language: AppLanguage) -> String {
        _ = language
        return canonicalCategory(category)
    }

    private static func normalizeCategoryKey(_ value: String) -> String {
        value
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "&", with: "")
    }

    private static let categoryAliases: [String: String] = [
        "science": "Science",
        "space": "Space",
        "nature": "Nature",
        "humanbody": "Human Body",
        "history": "History",
        "technology": "Technology",
        "psychology": "Psychology",
        "ocean": "Ocean",
        "animal": "Animals",
        "animals": "Animals",
        "movie": "Movies",
        "movies": "Movies"
    ]
}
