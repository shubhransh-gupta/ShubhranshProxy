//
//  HARExporter.swift — Phase 3 (full HAR 1.2)
//
//  Created by Shubhransh Gupta

import Foundation

enum HARExporter {
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func exportHAR(sessions: [ProxySession]) throws -> Data {
        let entries: [[String: Any]] = sessions.map { entry(for: $0) }
        let har: [String: Any] = [
            "log": [
                "version": "1.2",
                "creator": [
                    "name": "ShubhranshProxy",
                    "version": "1.0",
                ],
                "entries": entries,
            ],
        ]
        return try JSONSerialization.data(withJSONObject: har, options: [.prettyPrinted, .sortedKeys])
    }

    private static func entry(for session: ProxySession) -> [String: Any] {
        let started = iso8601.string(from: session.startedDate)
        let totalTime = session.durationMs ?? 0
        var result: [String: Any] = [
            "startedDateTime": started,
            "time": totalTime,
            "request": requestObject(session),
            "response": responseObject(session),
            "cache": [:] as [String: Any],
            "timings": timingsObject(durationMs: totalTime),
        ]
        if let completed = session.completedAt {
            result["endedDateTime"] = iso8601.string(from: Date(timeIntervalSince1970: completed))
        }
        return result
    }

    private static func requestObject(_ session: ProxySession) -> [String: Any] {
        let headers = harHeaders(from: session.requestHeaders)
        var req: [String: Any] = [
            "method": session.method,
            "url": session.url,
            "httpVersion": "HTTP/1.1",
            "headers": headers,
            "queryString": harQueryString(from: session.url),
            "headersSize": session.requestHeaders.utf8.count,
            "bodySize": session.requestSize,
        ]
        if !session.requestBody.isEmpty {
            req["postData"] = postData(body: session.requestBody, headers: headers)
        }
        return req
    }

    private static func responseObject(_ session: ProxySession) -> [String: Any] {
        let headers = harHeaders(from: session.responseHeaders)
        let status = session.responseStatus ?? 0
        let body = session.responseBody ?? Data()
        var resp: [String: Any] = [
            "status": status,
            "statusText": HTTPURLResponse.localizedString(forStatusCode: status),
            "httpVersion": "HTTP/1.1",
            "headers": headers,
            "headersSize": session.responseHeaders?.utf8.count ?? 0,
            "bodySize": session.responseSize ?? body.count,
            "content": contentObject(body: body, mimeType: session.mimeType),
        ]
        if session.errorMessage != nil {
            resp["status"] = status == 0 ? 0 : status
        }
        return resp
    }

    private static func harHeaders(from headerBlock: String?) -> [[String: String]] {
        guard let headerBlock, !headerBlock.isEmpty else { return [] }
        let lines = headerBlock.split(separator: "\r\n", omittingEmptySubsequences: false)
        var out: [[String: String]] = []
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            out.append(["name": name, "value": value])
        }
        return out
    }

    private static func harQueryString(from urlString: String) -> [[String: String]] {
        HTTPHeaderParsing.queryItems(from: urlString).map { ["name": $0.0, "value": $0.1] }
    }

    private static func postData(body: Data, headers: [[String: String]]) -> [String: Any] {
        let mime = headers.first { $0["name"]?.lowercased() == "content-type" }?["value"] ?? "application/octet-stream"
        var post: [String: Any] = [
            "mimeType": mime,
            "text": utf8OrBase64(body),
        ]
        if let text = String(data: body, encoding: .utf8) {
            post["text"] = text
        } else {
            post["text"] = body.base64EncodedString()
            post["encoding"] = "base64"
        }
        return post
    }

    private static func contentObject(body: Data, mimeType: String?) -> [String: Any] {
        var content: [String: Any] = [
            "size": body.count,
            "mimeType": mimeType ?? "application/octet-stream",
        ]
        if body.isEmpty {
            content["text"] = ""
        } else if let text = String(data: body, encoding: .utf8) {
            content["text"] = text
        } else {
            content["text"] = body.base64EncodedString()
            content["encoding"] = "base64"
        }
        return content
    }

    private static func timingsObject(durationMs: Double) -> [String: Any] {
        [
            "blocked": 0,
            "dns": 0,
            "connect": 0,
            "send": 0,
            "wait": max(0, durationMs),
            "receive": 0,
            "ssl": 0,
        ]
    }

    private static func utf8OrBase64(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? data.base64EncodedString()
    }

    static func exportCURL(session: ProxySession) -> String {
        var parts = ["curl", "-X", session.method, "'\(session.url.replacingOccurrences(of: "'", with: "'\\''"))'"]
        for line in session.requestHeaders.split(separator: "\r\n").dropFirst() {
            if line.isEmpty { break }
            let h = String(line).replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-H")
            parts.append("'\(h)'")
        }
        if !session.requestBody.isEmpty, let body = String(data: session.requestBody, encoding: .utf8) {
            parts.append("--data-raw")
            parts.append("'\(body.replacingOccurrences(of: "'", with: "'\\''"))'")
        }
        return parts.joined(separator: " ")
    }
}
