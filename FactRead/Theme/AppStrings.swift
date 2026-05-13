import Foundation

enum AppStringKey: String {
    case language
    case pagePrefix
}

enum AppStrings {
    static func text(_ key: AppStringKey, language: AppLanguage) -> String {
        _ = language
        return english[key] ?? ""
    }

    private static let english: [AppStringKey: String] = [
        .language: "Language",
        .pagePrefix: "Page"
    ]

}
