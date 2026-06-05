//
//  RewriteRuleEngine.swift — Phase 4
//
//  Created by Shubhransh Gupta

import Foundation

enum RewriteTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case requestHeader = "Request header"
    case requestBody = "Request body"
    case responseHeader = "Response header"
    case responseBody = "Response body"
    var id: String { rawValue }
}

struct RewriteRuleSnapshot: Sendable, Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var urlPattern: String
    var target: RewriteTarget
    var matchPattern: String
    var replaceWith: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        urlPattern: String = ".*",
        target: RewriteTarget = .requestBody,
        matchPattern: String = "",
        replaceWith: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.urlPattern = urlPattern
        self.target = target
        self.matchPattern = matchPattern
        self.replaceWith = replaceWith
        self.isEnabled = isEnabled
    }
}

enum RewriteRuleEngine {
    static func applyRequestRules(_ raw: Data, url: String, rules: [RewriteRuleSnapshot]) -> Data {
        var data = raw
        for rule in rules where rule.isEnabled && urlMatches(url, pattern: rule.urlPattern) {
            switch rule.target {
            case .requestHeader:
                if let s = String(data: data, encoding: .utf8),
                   let replaced = replace(in: s, rule: rule) {
                    data = Data(replaced.utf8)
                }
            case .requestBody:
                let headers = HTTPMessageHeaders.headerBlock(from: data)
                var body = HTTPMessageHeaders.requestBody(from: data)
                if let text = String(data: body, encoding: .utf8),
                   let replaced = replace(in: text, rule: rule) {
                    body = Data(replaced.utf8)
                    data = rebuildRequest(headers: headers, body: body)
                }
            default:
                break
            }
        }
        return data
    }

    static func applyResponseRules(_ raw: Data, url: String, rules: [RewriteRuleSnapshot]) -> Data {
        guard let text = String(data: raw, encoding: .utf8) else { return raw }
        var working = text
        for rule in rules where rule.isEnabled && urlMatches(url, pattern: rule.urlPattern) {
            switch rule.target {
            case .responseHeader, .responseBody:
                if let replaced = replace(in: working, rule: rule) {
                    working = replaced
                }
            default:
                break
            }
        }
        return Data(working.utf8)
    }

    private static func replace(in text: String, rule: RewriteRuleSnapshot) -> String? {
        guard !rule.matchPattern.isEmpty else { return nil }
        guard let regex = try? NSRegularExpression(pattern: rule.matchPattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let result = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: rule.replaceWith)
        return result == text ? nil : result
    }

    private static func urlMatches(_ url: String, pattern: String) -> Bool {
        guard !pattern.isEmpty else { return true }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        let range = NSRange(url.startIndex..<url.endIndex, in: url)
        return regex.firstMatch(in: url, options: [], range: range) != nil
    }

    private static func rebuildRequest(headers: String, body: Data) -> Data {
        var lines = headers.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        if lines.count > 1 {
            var found = false
            for i in 1..<lines.count {
                if lines[i].lowercased().hasPrefix("content-length:") {
                    lines[i] = "Content-Length: \(body.count)"
                    found = true
                    break
                }
                if lines[i].isEmpty { break }
            }
            if !found, lines.count > 1 {
                lines.insert("Content-Length: \(body.count)", at: 1)
            }
        }
        let headerData = lines.joined(separator: "\r\n")
        guard headerData.hasSuffix("\r\n\r\n") else {
            return Data((headerData + "\r\n\r\n").utf8) + body
        }
        return Data(headerData.utf8) + body
    }
}
