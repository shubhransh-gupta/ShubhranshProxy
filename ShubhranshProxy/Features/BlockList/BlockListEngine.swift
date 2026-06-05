//
//  BlockListEngine.swift — Phase 4
//
//  Created by Shubhransh Gupta

import Foundation

struct BlockListSnapshot: Sendable, Equatable, Codable {
    var isEnabled = false
    var domainPatterns: [String] = []
    var pathPatterns: [String] = []
}

enum BlockListEngine {
    static func shouldBlock(url: String, host: String, settings: BlockListSnapshot) -> Bool {
        guard settings.isEnabled else { return false }
        let path = URL(string: url)?.path ?? url
        if matchesAny(host, patterns: settings.domainPatterns) { return true }
        if matchesAny(path, patterns: settings.pathPatterns) { return true }
        if matchesAny(url, patterns: settings.pathPatterns) { return true }
        return false
    }

    static func blockedResponseHTML(for url: String) -> Data {
        let body = """
        <html><head><title>Blocked</title></head><body>
        <h1>Blocked by ShubhranshProxy</h1>
        <p>\(url)</p>
        </body></html>
        """
        let payload =
            "HTTP/1.1 403 Forbidden\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        return Data(payload.utf8)
    }

    private static func matchesAny(_ text: String, patterns: [String]) -> Bool {
        for pattern in patterns where !pattern.isEmpty {
            if patternMatches(text, pattern: pattern) { return true }
        }
        return false
    }

    private static func patternMatches(_ text: String, pattern: String) -> Bool {
        if pattern.contains("*") || pattern.contains("?") {
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".")
            guard let regex = try? NSRegularExpression(pattern: "^\(escaped)$", options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
        return text.localizedCaseInsensitiveContains(pattern)
    }
}
