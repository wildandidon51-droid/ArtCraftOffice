import Foundation
import ZIPFoundation

enum OfficeOpenXMLArchiveError: Error {
    case missingEntry(String)
    case entryTooLarge
}

enum OfficeOpenXMLArchive {
    static func create(entries: [String: Data]) throws -> Data {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent("ArtCraft-OOXML-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = fileManager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        defer {
            try? fileManager.removeItem(at: temporaryRoot)
            try? fileManager.removeItem(at: archiveURL)
        }

        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        for (path, data) in entries {
            let destination = temporaryRoot.appendingPathComponent(path)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
        try fileManager.zipItem(at: temporaryRoot, to: archiveURL, shouldKeepParent: false, compressionMethod: .deflate)
        return try Data(contentsOf: archiveURL)
    }

    static func read(_ path: String, from data: Data, maximumSize: UInt64) throws -> Data {
        let archive = try Archive(data: data, accessMode: .read)
        guard let entry = archive[path] else { throw OfficeOpenXMLArchiveError.missingEntry(path) }
        guard entry.uncompressedSize <= maximumSize else { throw OfficeOpenXMLArchiveError.entryTooLarge }
        var result = Data()
        result.reserveCapacity(Int(entry.uncompressedSize))
        try archive.extract(entry) { chunk in
            guard UInt64(result.count) <= maximumSize - UInt64(chunk.count) else {
                throw OfficeOpenXMLArchiveError.entryTooLarge
            }
            result.append(chunk)
        }
        return result
    }
}
