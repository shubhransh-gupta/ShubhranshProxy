//
//  MapLocalEngine.swift
//  ShubhranshProxy — MappingEngine
//
//  Created by Shubhransh Gupta
//

import Foundation

enum MapLocalEngine {
    /// First matching enabled rule wins. Invalid regex patterns fall back to substring match.
    static func matchingRule(for fullURL: String, rules: [MapLocalRuleSnapshot]) -> MapLocalRuleSnapshot? {
        for rule in rules where rule.isEnabled {
            if matches(url: fullURL, pattern: rule.pattern) {
                return rule
            }
        }
        return nil
    }

    static func matches(url: String, pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if let regex = try? NSRegularExpression(pattern: trimmed, options: [.caseInsensitive]) {
            let range = NSRange(url.startIndex..<url.endIndex, in: url)
            if regex.firstMatch(in: url, options: [], range: range) != nil {
                return true
            }
        }

        return url.localizedCaseInsensitiveContains(trimmed)
    }

    static func loadMappedBody(from snapshot: MapLocalRuleSnapshot) throws -> (data: Data, contentType: String) {
        if snapshot.usesInlineBody, let inline = snapshot.inlineBody {
            guard let data = inline.data(using: .utf8) else {
                throw MapLocalError.invalidInlineBody
            }
            let mime = snapshot.contentType ?? "application/json; charset=utf-8"
            return (data, mime)
        }

        guard let path = snapshot.localFilePath, !path.isEmpty else {
            throw MapLocalError.missingResponseBody
        }

        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        let mime: String = switch ext {
        case "json": "application/json; charset=utf-8"
        case "html", "htm": "text/html; charset=utf-8"
        case "txt": "text/plain; charset=utf-8"
        case "xml": "application/xml; charset=utf-8"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "svg": "image/svg+xml"
        case "webp": "image/webp"
        case "js": "text/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        default: "application/octet-stream"
        }
        return (data, mime)
    }

    enum MapLocalError: Error, LocalizedError {
        case missingResponseBody
        case invalidInlineBody

        var errorDescription: String? {
            switch self {
            case .missingResponseBody:
                return "Map Local rule has no response body or file."
            case .invalidInlineBody:
                return "Map Local inline body is not valid UTF-8 text."
            }
        }
    }
}
