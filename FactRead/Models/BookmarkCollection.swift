import Foundation
import SwiftData

@Model
final class BookmarkCollection {
    var id: UUID
    var name: String
    var accentHex: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        accentHex: String = "5E6B52",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.accentHex = accentHex
        self.createdAt = createdAt
    }
}

