//
//  ComposerExecutor.swift — Phase 4
//
//  Created by Shubhransh Gupta

import Foundation

enum ComposerExecutor {
    enum ComposerError: Error, LocalizedError {
        case invalidURL
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Enter a valid URL."
            case .transport(let message): return message
            }
        }
    }

    @MainActor
    static func send(
        method: String,
        urlString: String,
        headersBlock: String,
        bodyText: String,
        viaProxyHost: String,
        viaProxyPort: Int,
        ingest: @MainActor (HTTPExchangeSnapshot) -> Void
    ) async throws {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ComposerError.invalidURL
        }

        let startedAt = Date().timeIntervalSince1970
        let exchangeID = UUID()
        var request = URLRequest(url: url)
        request.httpMethod = method.uppercased()
        request.httpBody = bodyText.isEmpty ? nil : Data(bodyText.utf8)

        for line in headersBlock.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            request.setValue(parts[1], forHTTPHeaderField: parts[0])
        }

        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: viaProxyHost,
            kCFNetworkProxiesHTTPPort as String: viaProxyPort,
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: viaProxyHost,
            kCFNetworkProxiesHTTPSPort as String: viaProxyPort,
        ]
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(for: request)
            let completedAt = Date().timeIntervalSince1970
            let http = response as? HTTPURLResponse
            let status = http?.statusCode
            var responseHeaders = "HTTP/1.1 \(status ?? 0)\r\n"
            http?.allHeaderFields.forEach { key, value in
                responseHeaders += "\(key): \(value)\r\n"
            }
            responseHeaders += "\r\n"

            let requestHeaders = buildRequestHeaders(method: method, url: url, headersBlock: headersBlock)
            let host = url.host ?? url.absoluteString
            let snapshot = HTTPExchangeSnapshot(
                id: exchangeID,
                startedAt: startedAt,
                completedAt: completedAt,
                method: method.uppercased(),
                url: url.absoluteString,
                host: host,
                responseStatus: status,
                durationMs: (completedAt - startedAt) * 1000,
                requestSize: (request.httpBody?.count ?? 0) + requestHeaders.utf8.count,
                responseSize: data.count,
                mimeType: http?.value(forHTTPHeaderField: "Content-Type"),
                requestHeaders: requestHeaders,
                requestBody: request.httpBody ?? Data(),
                responseHeaders: responseHeaders,
                responseBody: data,
                errorMessage: nil,
                wasMappedLocal: false,
                isCONNECT: false,
                wasDecryptedHTTPS: url.scheme?.lowercased() == "https"
            )
            ingest(snapshot)
        } catch {
            throw ComposerError.transport(error.localizedDescription)
        }
    }

    private static func buildRequestHeaders(method: String, url: URL, headersBlock: String) -> String {
        var lines = ["\(method.uppercased()) \(url.path.isEmpty ? "/" : url.path) HTTP/1.1"]
        lines.append("Host: \(url.host ?? "")")
        for line in headersBlock.split(separator: "\n", omittingEmptySubsequences: true) {
            lines.append(String(line))
        }
        return lines.joined(separator: "\r\n") + "\r\n\r\n"
    }
}
