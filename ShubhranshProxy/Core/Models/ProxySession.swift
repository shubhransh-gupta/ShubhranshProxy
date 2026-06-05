//
//  ProxySession.swift
//  ShubhranshProxy
//  Created by Shubhransh Gupta
//
//  Canonical session model for UI, persistence, and export (Phase 1+).
//

import Foundation

struct ProxySession: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var startedAt: TimeInterval
    var completedAt: TimeInterval?
    var method: String
    var url: String
    var host: String
    var responseStatus: Int?
    var durationMs: Double?
    var requestSize: Int
    var responseSize: Int?
    var mimeType: String?
    var requestHeaders: String
    var requestBody: Data
    var responseHeaders: String?
    var responseBody: Data?
    var errorMessage: String?
    var wasMappedLocal: Bool
    var wasMappedRemote: Bool
    var isCONNECT: Bool
    var wasDecryptedHTTPS: Bool
    var clientAppName: String?
    var clientIPAddress: String?

    var startedDate: Date { Date(timeIntervalSince1970: startedAt) }

    var statusLabel: String {
        if method == "TLS" { return "TLS" }
        if method == "DEVICE" { return "OK" }
        if let code = responseStatus { return "\(code)" }
        if errorMessage != nil { return "ERR" }
        return "—"
    }

    init(snapshot: HTTPExchangeSnapshot) {
        id = snapshot.id
        startedAt = snapshot.startedAt
        completedAt = snapshot.completedAt
        method = snapshot.method
        url = snapshot.url
        host = snapshot.host.isEmpty ? Self.host(from: snapshot.url) : snapshot.host
        responseStatus = snapshot.responseStatus
        durationMs = snapshot.durationMs
        requestSize = snapshot.requestSize
        responseSize = snapshot.responseSize
        mimeType = snapshot.mimeType
        requestHeaders = snapshot.requestHeaders
        requestBody = snapshot.requestBody
        responseHeaders = snapshot.responseHeaders
        responseBody = snapshot.responseBody
        errorMessage = snapshot.errorMessage
        wasMappedLocal = snapshot.wasMappedLocal
        wasMappedRemote = snapshot.wasMappedRemote
        isCONNECT = snapshot.isCONNECT
        wasDecryptedHTTPS = snapshot.wasDecryptedHTTPS
        clientAppName = snapshot.clientAppName
        clientIPAddress = snapshot.clientIPAddress
    }

    func toSnapshot() -> HTTPExchangeSnapshot {
        HTTPExchangeSnapshot(
            id: id,
            startedAt: startedAt,
            completedAt: completedAt,
            method: method,
            url: url,
            host: host,
            responseStatus: responseStatus,
            durationMs: durationMs,
            requestSize: requestSize,
            responseSize: responseSize,
            mimeType: mimeType,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            responseHeaders: responseHeaders,
            responseBody: responseBody,
            errorMessage: errorMessage,
            wasMappedLocal: wasMappedLocal,
            wasMappedRemote: wasMappedRemote,
            isCONNECT: isCONNECT,
            wasDecryptedHTTPS: wasDecryptedHTTPS,
            clientAppName: clientAppName,
            clientIPAddress: clientIPAddress
        )
    }

    static func host(from url: String) -> String {
        if let u = URL(string: url), let h = u.host { return h }
        if url.hasPrefix("CONNECT ") { return url }
        return url
    }
}
