//
//  ExchangeSnapshotFactory.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//

import Foundation

enum ExchangeSnapshotFactory {
    static func httpExchange(
        id: UUID,
        startedAt: TimeInterval,
        request: ParsedInboundRequest,
        fullURL: String,
        host: String,
        responseStatus: Int?,
        responseHeaders: String?,
        responseBody: Data?,
        errorMessage: String?,
        wasMappedLocal: Bool,
        wasMappedRemote: Bool = false,
        responseByteCount: Int? = nil,
        wasDecryptedHTTPS: Bool = false,
        clientAppName: String? = nil,
        clientIPAddress: String? = nil
    ) -> HTTPExchangeSnapshot {
        let completedAt = Date().timeIntervalSince1970
        let durationMs = (completedAt - startedAt) * 1000
        let responseSize = responseByteCount ?? responseBody?.count
        return HTTPExchangeSnapshot(
            id: id,
            startedAt: startedAt,
            completedAt: completedAt,
            method: request.method,
            url: fullURL,
            host: host,
            responseStatus: responseStatus,
            durationMs: durationMs,
            requestSize: request.raw.count,
            responseSize: responseSize,
            mimeType: HTTPHeaderParsing.contentType(from: responseHeaders),
            requestHeaders: HTTPMessageHeaders.headerBlock(from: request.raw),
            requestBody: HTTPMessageHeaders.requestBody(from: request.raw),
            responseHeaders: responseHeaders,
            responseBody: responseBody,
            errorMessage: errorMessage,
            wasMappedLocal: wasMappedLocal,
            wasMappedRemote: wasMappedRemote,
            isCONNECT: false,
            wasDecryptedHTTPS: wasDecryptedHTTPS,
            clientAppName: clientAppName,
            clientIPAddress: clientIPAddress
        )
    }

    static func connect(
        authority: String,
        connected: Bool,
        error: String?,
        startedAt: TimeInterval = Date().timeIntervalSince1970,
        clientAppName: String? = nil,
        clientIPAddress: String? = nil,
        requestHeaders: String? = nil
    ) -> HTTPExchangeSnapshot {
        let host = authority.split(separator: ":").first.map(String.init) ?? authority
        let headers = requestHeaders ?? "CONNECT \(authority) HTTP/1.1"
        return HTTPExchangeSnapshot(
            id: UUID(),
            startedAt: startedAt,
            completedAt: Date().timeIntervalSince1970,
            method: "CONNECT",
            url: authority,
            host: host,
            responseStatus: connected ? 200 : nil,
            durationMs: nil,
            requestSize: 0,
            responseSize: nil,
            mimeType: nil,
            requestHeaders: headers,
            requestBody: Data(),
            responseHeaders: connected ? "HTTP/1.1 200 Connection Established" : nil,
            responseBody: nil,
            errorMessage: error,
            wasMappedLocal: false,
            isCONNECT: true,
            wasDecryptedHTTPS: false,
            clientAppName: clientAppName,
            clientIPAddress: clientIPAddress
        )
    }

    /// Synthetic row so mobile devices appear in the sidebar/table as soon as they connect.
    static func devicePresence(clientIPAddress: String) -> HTTPExchangeSnapshot {
        let ip = ClientAddressResolver.normalize(clientIPAddress) ?? clientIPAddress
        return HTTPExchangeSnapshot(
            id: UUID(),
            startedAt: Date().timeIntervalSince1970,
            completedAt: Date().timeIntervalSince1970,
            method: "DEVICE",
            url: "device://\(ip)/connected",
            host: ip,
            responseStatus: 200,
            durationMs: 0,
            requestSize: 0,
            responseSize: 0,
            mimeType: nil,
            requestHeaders: "X-ShubhranshProxy-Device: connected\nX-Client-IP: \(ip)",
            requestBody: Data(),
            responseHeaders: "X-ShubhranshProxy-Device: connected",
            responseBody: nil,
            errorMessage: nil,
            wasMappedLocal: false,
            isCONNECT: false,
            wasDecryptedHTTPS: false,
            clientAppName: nil,
            clientIPAddress: ip
        )
    }

    static func tlsFailure(
        host: String,
        clientIPAddress: String?,
        error: String,
        startedAt: TimeInterval = Date().timeIntervalSince1970
    ) -> HTTPExchangeSnapshot {
        let ip = ClientAddressResolver.normalize(clientIPAddress) ?? clientIPAddress
        return HTTPExchangeSnapshot(
            id: UUID(),
            startedAt: startedAt,
            completedAt: Date().timeIntervalSince1970,
            method: "TLS",
            url: "https://\(host)/",
            host: host,
            responseStatus: nil,
            durationMs: nil,
            requestSize: 0,
            responseSize: nil,
            mimeType: nil,
            requestHeaders: "TLS-Handshake: failed\nHost: \(host)",
            requestBody: Data(),
            responseHeaders: nil,
            responseBody: nil,
            errorMessage: error,
            wasMappedLocal: false,
            isCONNECT: false,
            wasDecryptedHTTPS: true,
            clientAppName: nil,
            clientIPAddress: ip
        )
    }
}
