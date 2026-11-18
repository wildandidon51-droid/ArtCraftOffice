import Foundation

func safeFileName(_ title: String) -> String {
    let sanitized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
        .replacingOccurrences(of: "\\", with: "-")
        .replacingOccurrences(of: "?", with: "-")
        .replacingOccurrences(of: "*", with: "-")
        .replacingOccurrences(of: "\"", with: "-")
        .replacingOccurrences(of: "<", with: "-")
        .replacingOccurrences(of: ">", with: "-")
        .replacingOccurrences(of: "|", with: "-")
    return sanitized.isEmpty ? "Untitled" : sanitized
}
