import Foundation
import Combine
import UIKit

struct WordDocument: Identifiable, Codable {
    var id: UUID
    var title: String
    var content: String
    var richText: Data?
    var paperSize: WordPaperSize
    var pageOrientation: WordPageOrientation
    var marginPreset: WordMarginPreset
    var createdAt: Date
    var modifiedAt: Date

    init(
        title: String = "Untitled Document",
        content: String = "",
        richText: Data? = nil,
        paperSize: WordPaperSize = .a4,
        pageOrientation: WordPageOrientation = .portrait,
        marginPreset: WordMarginPreset = .normal
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.richText = richText
        self.paperSize = paperSize
        self.pageOrientation = pageOrientation
        self.marginPreset = marginPreset
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, content, richText, paperSize, pageOrientation, marginPreset, createdAt, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Document"
        content = try values.decodeIfPresent(String.self, forKey: .content) ?? ""
        richText = try values.decodeIfPresent(Data.self, forKey: .richText)
        paperSize = try values.decodeIfPresent(WordPaperSize.self, forKey: .paperSize) ?? .a4
        pageOrientation = try values.decodeIfPresent(WordPageOrientation.self, forKey: .pageOrientation) ?? .portrait
        marginPreset = try values.decodeIfPresent(WordMarginPreset.self, forKey: .marginPreset) ?? .normal
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try values.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
    }

    var attributedContent: NSAttributedString {
        if let richText,
           let value = try? NSAttributedString(
            data: richText,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
           ) {
            return value
        }
        return NSAttributedString(string: content)
    }

    mutating func update(
        title: String,
        text: NSAttributedString,
        paperSize: WordPaperSize,
        pageOrientation: WordPageOrientation,
        marginPreset: WordMarginPreset
    ) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled Document" : title
        self.content = text.string
        self.richText = try? text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        self.paperSize = paperSize
        self.pageOrientation = pageOrientation
        self.marginPreset = marginPreset
        self.modifiedAt = Date()
    }
}

@MainActor
final class WordDocumentStore: ObservableObject {
    @Published private(set) var documents: [WordDocument] = []
    @Published private(set) var lastError: String?
    private let legacyKey = "artcraft.wordcraft.documents.v1"
    private let folderName = "WordCraft"

    init() { load() }

    func save(_ document: WordDocument) {
        var updated = document
        updated.modifiedAt = Date()
        if let index = documents.firstIndex(where: { $0.id == updated.id }) {
            documents[index] = updated
        } else {
            documents.insert(updated, at: 0)
        }
        documents.sort { $0.modifiedAt > $1.modifiedAt }
        persist(updated)
    }

    func delete(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            let removed = documents.remove(at: index)
            do { try FileManager.default.removeItem(at: fileURL(for: removed.id)) }
            catch { lastError = "Could not remove \(removed.title)." }
        }
    }

    func reportError(_ message: String) {
        lastError = message
    }

    private func load() {
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let files = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
            documents = files.compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(WordDocument.self, from: data)
            }.sorted { $0.modifiedAt > $1.modifiedAt }

            if documents.isEmpty,
               let legacyData = UserDefaults.standard.data(forKey: legacyKey),
               let legacyDocuments = try? JSONDecoder().decode([WordDocument].self, from: legacyData) {
                for document in legacyDocuments { persist(document) }
                documents = legacyDocuments.sorted { $0.modifiedAt > $1.modifiedAt }
                UserDefaults.standard.removeObject(forKey: legacyKey)
            }
        } catch {
            lastError = "Could not open saved documents."
        }
    }

    private var folderURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ArtCraftOffice", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private func fileURL(for id: UUID) -> URL {
        folderURL.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func persist(_ document: WordDocument) {
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(document)
            try data.write(to: fileURL(for: document.id), options: .atomic)
        } catch {
            lastError = "Could not save \(document.title)."
            return
        }
        lastError = nil
    }
}
