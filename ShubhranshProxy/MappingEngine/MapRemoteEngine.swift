//
//  MapRemoteEngine.swift
//  ShubhranshProxy — MappingEngine
//  Created by Shubhransh Gupta
//
//  Rewrites matching requests to a different remote host/URL (Charles “Map Remote”).
//

import Foundation

enum MapRemoteEngine {
    struct MappedRequest: Sendable {
        var request: ParsedInboundRequest
        var fullURL: String
        var host: String
        var port: Int
    }

    static func matchingRule(for fullURL: String, rules: [MapRemoteRuleSnapshot]) -> MapRemoteRuleSnapshot? {
        for rule in rules where rule.isEnabled {
            if MapLocalEngine.matches(url: fullURL, pattern: rule.sourcePattern) {
                return rule
            }
        }
        return nil
    }

    static func apply(
        request: ParsedInboundRequest,
        fullURL: String,
        rule: MapRemoteRuleSnapshot
    ) -> MappedRequest? {
        guard let mappedURLString = mappedURL(fullURL: fullURL, rule: rule),
              let mappedURL = URL(string: mappedURLString),
              let host = mappedURL.host else {
            return nil
        }

        let port = mappedURL.port ?? (mappedURL.scheme?.lowercased() == "https" ? 443 : 80)
        let rewrittenRaw = RequestURLRewriter.rewrite(
            raw: request.raw,
            method: request.method,
            originalTarget: request.target,
            mappedURL: mappedURL
        )

        let rewritten = ParsedInboundRequest(
            raw: rewrittenRaw,
            method: request.method,
            target: requestTarget(for: request, mappedURL: mappedURL),
            isConnect: false
        )

        return MappedRequest(
            request: rewritten,
            fullURL: mappedURLString,
            host: host,
            port: port
        )
    }

    private static func mappedURL(fullURL: String, rule: MapRemoteRuleSnapshot) -> String? {
        let source = rule.sourcePattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = rule.destinationPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !destination.isEmpty else { return nil }

        if let regex = try? NSRegularExpression(pattern: source, options: [.caseInsensitive]) {
            let range = NSRange(fullURL.startIndex..<fullURL.endIndex, in: fullURL)
            if regex.firstMatch(in: fullURL, options: [], range: range) != nil {
                return regex.stringByReplacingMatches(
                    in: fullURL,
                    options: [],
                    range: range,
                    withTemplate: destination
                )
            }
        }

        guard let range = fullURL.range(of: source, options: .caseInsensitive) else { return nil }
        return fullURL.replacingCharacters(in: range, with: destination)
    }

    private static func requestTarget(for request: ParsedInboundRequest, mappedURL: URL) -> String {
        if request.target.hasPrefix("http://") || request.target.hasPrefix("https://") {
            return mappedURL.absoluteString
        }
        var path = mappedURL.path
        if path.isEmpty { path = "/" }
        if let query = mappedURL.query { path += "?\(query)" }
        return path
    }
}

enum RequestURLRewriter {
    static func rewrite(
        raw: Data,
        method: String,
        originalTarget: String,
        mappedURL: URL
    ) -> Data {
        guard let headerEnd = raw.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else { return raw }

        let headerData = raw.subdata(in: raw.startIndex..<headerEnd.upperBound)
        let body = raw.subdata(in: headerEnd.upperBound..<raw.endIndex)
        var lines = String(decoding: headerData, as: UTF8.self)
            .split(separator: "\r\n", omittingEmptySubsequences: false)
            .map(String.init)

        let newTarget: String
        if originalTarget.hasPrefix("http://") || originalTarget.hasPrefix("https://") {
            newTarget = mappedURL.absoluteString
        } else {
            var path = mappedURL.path
            if path.isEmpty { path = "/" }
            if let query = mappedURL.query { path += "?\(query)" }
            newTarget = path
        }

        if !lines.isEmpty {
            let parts = lines[0].split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            if parts.count == 3 {
                lines[0] = "\(parts[0]) \(newTarget) \(parts[2])"
            }
        }

        let hostValue = hostHeaderValue(for: mappedURL)
        var hostReplaced = false
        for index in 1..<lines.count {
            let name = lines[index].split(separator: ":", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespaces).lowercased()
            if name == "host" {
                lines[index] = "Host: \(hostValue)"
                hostReplaced = true
                break
            }
        }
        if !hostReplaced {
            lines.insert("Host: \(hostValue)", at: min(1, lines.count))
        }

        let newHeader = lines.joined(separator: "\r\n")
        if !newHeader.hasSuffix("\r\n\r\n") {
            return Data((newHeader + "\r\n\r\n").utf8) + body
        }
        return Data(newHeader.utf8) + body
    }

    private static func hostHeaderValue(for url: URL) -> String {
        guard let host = url.host else { return "" }
        let defaultPort = url.scheme?.lowercased() == "https" ? 443 : 80
        if let port = url.port, port != defaultPort {
            return host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
        }
        return host
    }
}
