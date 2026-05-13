import Foundation

enum FactStore {
    static func signature(title: String, body: String) -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalizedTitle)|#|\(normalizedBody)"
    }

    static func languageIndex(for languageCode: String) -> Int {
        let canonical = AppLanguage.canonicalLanguageCode(languageCode)
        return AppLanguage.allCases.firstIndex(where: { $0.bcp47Code == canonical }) ?? 0
    }
}
