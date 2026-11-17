
import Foundation

struct WordDocument: Identifiable, Codable {
    var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var modifiedAt: Date

    init(
        title: String = "Untitled Document",
        content: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}
