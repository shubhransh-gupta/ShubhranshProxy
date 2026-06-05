//
//  HARImporter.swift — Phase 3
//
//  Created by Shubhransh Gupta

import Foundation

enum HARImporter {
    enum ImportError: Error, LocalizedError {
        case invalidFormat
        case missingLog
        case noEntries

        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "File is not valid JSON."
            case .missingLog: return "HAR file is missing a log object."
            case .noEntries: return "HAR file contains no entries."
            }
        }
    }

    static func importSessions(from data: Data) throws -> [ProxySession] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.invalidFormat
        }
        guard let log = root["log"] as? [String: Any] else {
            throw ImportError.missingLog
        }
        guard let entries = log["entries"] as? [[String: Any]], !entries.isEmpty else {
            throw ImportError.noEntries
        }
        return entries.compactMap { session(from: $0) }
    }

    private static func session(from entry: [String: Any]) -> ProxySession? {
        guard let request = entry["request"] as? [String: Any],
              let method = request["method"] as? String,
              let url = request["url"] as? String else { return nil }

        let startedAt = parseDate(entry["startedDateTime"] as? String) ?? Date().timeIntervalSince1970
        let durationMs = (entry["time"] as? NSNumber)?.doubleValue
        let completedAt = durationMs.map { startedAt + ($0 / 1000) }

        let requestHeaders = headerBlock(from: request["headers"])
        let requestBody = bodyData(from: request["postData"])

        let response = entry["response"] as? [String: Any]
        let responseStatus = (response?["status"] as? NSNumber)?.intValue
        let responseHeaders = headerBlock(from: response?["headers"])
        let responseBodyRaw = bodyData(from: response?["content"])
        let responseBody = responseBodyRaw.isEmpty ? nil : responseBodyRaw
        let mimeType = (response?["content"] as? [String: Any])?["mimeType"] as? String
            ?? HTTPHeaderParsing.contentType(from: responseHeaders)

        let host = ProxySession.host(from: url)
        let snapshot = HTTPExchangeSnapshot(
            id: UUID(),
            startedAt: startedAt,
            completedAt: completedAt,
            method: method,
            url: url,
            host: host,
            responseStatus: responseStatus == 0 ? nil : responseStatus,
            durationMs: durationMs,
            requestSize: requestBody.count,
            responseSize: responseBody?.count,
            mimeType: mimeType,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            responseHeaders: responseHeaders.isEmpty ? nil : responseHeaders,
            responseBody: responseBody,
            errorMessage: nil,
            wasMappedLocal: false,
            isCONNECT: method.uppercased() == "CONNECT",
            wasDecryptedHTTPS: url.hasPrefix("https://")
        )
        return ProxySession(snapshot: snapshot)
    }

    private static func headerBlock(from value: Any?) -> String {
        guard let headers = value as? [[String: Any]], !headers.isEmpty else {
            return "HTTP/1.1\r\n"
        }
        var lines = ["HTTP/1.1"]
        for h in headers {
            guard let name = h["name"] as? String, let val = h["value"] as? String else { continue }
            lines.append("\(name): \(val)")
        }
        return lines.joined(separator: "\r\n")
    }

    private static func bodyData(from value: Any?) -> Data {
        guard let dict = value as? [String: Any] else { return Data() }
        if let encoding = dict["encoding"] as? String, encoding == "base64",
           let text = dict["text"] as? String,
           let data = Data(base64Encoded: text) {
            return data
        }
        if let text = dict["text"] as? String {
            return Data(text.utf8)
        }
        return Data()
    }

    private static func parseDate(_ string: String?) -> TimeInterval? {
        guard let string else { return nil }
        let formatters: [ISO8601DateFormatter] = {
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return [withFraction, plain]
        }()
        for f in formatters {
            if let date = f.date(from: string) { return date.timeIntervalSince1970 }
        }
        return nil
    }
}
