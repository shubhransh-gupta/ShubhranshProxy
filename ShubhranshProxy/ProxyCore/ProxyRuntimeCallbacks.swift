//
//  ProxyRuntimeCallbacks.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//
//  Thread-safe hooks from NIO worker threads into app services (traffic log, Map Local).
//

import Foundation

/// Completed HTTP exchange (plain HTTP or synthetic Map Local).
struct HTTPExchangeSnapshot: Sendable, Codable, Identifiable {
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
    /// macOS process that opened the proxy connection (Safari, Chrome, etc.).
    var clientAppName: String?
    /// IP address of the client that opened the proxy connection (loopback for Mac system proxy).
    var clientIPAddress: String?

    init(
        id: UUID,
        startedAt: TimeInterval,
        completedAt: TimeInterval? = nil,
        method: String,
        url: String,
        host: String = "",
        responseStatus: Int? = nil,
        durationMs: Double? = nil,
        requestSize: Int = 0,
        responseSize: Int? = nil,
        mimeType: String? = nil,
        requestHeaders: String,
        requestBody: Data,
        responseHeaders: String? = nil,
        responseBody: Data? = nil,
        errorMessage: String? = nil,
        wasMappedLocal: Bool = false,
        wasMappedRemote: Bool = false,
        isCONNECT: Bool = false,
        wasDecryptedHTTPS: Bool = false,
        clientAppName: String? = nil,
        clientIPAddress: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.method = method
        self.url = url
        self.host = host
        self.responseStatus = responseStatus
        self.durationMs = durationMs
        self.requestSize = requestSize
        self.responseSize = responseSize
        self.mimeType = mimeType
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.errorMessage = errorMessage
        self.wasMappedLocal = wasMappedLocal
        self.wasMappedRemote = wasMappedRemote
        self.isCONNECT = isCONNECT
        self.wasDecryptedHTTPS = wasDecryptedHTTPS
        self.clientAppName = clientAppName
        self.clientIPAddress = clientIPAddress
    }

    enum CodingKeys: String, CodingKey {
        case id, startedAt, completedAt, method, url, host
        case responseStatus, durationMs, requestSize, responseSize, mimeType
        case requestHeaders, requestBody, responseHeaders, responseBody
        case errorMessage, wasMappedLocal, wasMappedRemote, isCONNECT, wasDecryptedHTTPS, clientAppName, clientIPAddress
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        startedAt = try c.decode(TimeInterval.self, forKey: .startedAt)
        completedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .completedAt)
        method = try c.decode(String.self, forKey: .method)
        url = try c.decode(String.self, forKey: .url)
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        responseStatus = try c.decodeIfPresent(Int.self, forKey: .responseStatus)
        durationMs = try c.decodeIfPresent(Double.self, forKey: .durationMs)
        requestSize = try c.decodeIfPresent(Int.self, forKey: .requestSize) ?? 0
        responseSize = try c.decodeIfPresent(Int.self, forKey: .responseSize)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
        requestHeaders = try c.decode(String.self, forKey: .requestHeaders)
        requestBody = try c.decode(Data.self, forKey: .requestBody)
        responseHeaders = try c.decodeIfPresent(String.self, forKey: .responseHeaders)
        responseBody = try c.decodeIfPresent(Data.self, forKey: .responseBody)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        wasMappedLocal = try c.decodeIfPresent(Bool.self, forKey: .wasMappedLocal) ?? false
        wasMappedRemote = try c.decodeIfPresent(Bool.self, forKey: .wasMappedRemote) ?? false
        isCONNECT = try c.decodeIfPresent(Bool.self, forKey: .isCONNECT) ?? false
        wasDecryptedHTTPS = try c.decodeIfPresent(Bool.self, forKey: .wasDecryptedHTTPS) ?? false
        clientAppName = try c.decodeIfPresent(String.self, forKey: .clientAppName)
        clientIPAddress = try c.decodeIfPresent(String.self, forKey: .clientIPAddress)
    }
}

/// Configuration supplied when the listener starts (`Sendable` for NIO).
struct ProxyRuntimeCallbacks: Sendable {
    /// Invoked when a full HTTP response has been relayed (or synthesized).
    var onHTTPExchange: @Sendable (HTTPExchangeSnapshot) -> Void
    /// CONNECT result for the session list (HTTPS tunnel metadata for remote devices).
    var onCONNECT: @Sendable (
        _ authority: String,
        _ connected: Bool,
        _ errorMessage: String?,
        _ clientAppName: String?,
        _ clientIPAddress: String?,
        _ requestHeaders: String?
    ) -> Void
    /// Fired when a non-loopback client opens a TCP connection to the proxy.
    var onRemoteClientConnected: @Sendable (_ clientIPAddress: String) -> Void
    var onRemoteClientDisconnected: @Sendable (_ clientIPAddress: String) -> Void
    /// Latest Map Local rules (called from event loop; keep fast).
    var mapLocalRules: @Sendable () -> [MapLocalRuleSnapshot]
    /// Latest Map Remote rules (called from event loop; keep fast).
    var mapRemoteRules: @Sendable () -> [MapRemoteRuleSnapshot]
    /// SSL interception settings.
    var sslSettings: @Sendable () -> SSLProxySettings
    /// Dynamic leaf certificate for MITM (host without port).
    var leafCertificate: @Sendable (String) throws -> SSLCertificateMaterial
    /// Phase 4 — block list settings.
    var blockListSettings: @Sendable () -> BlockListSnapshot
    /// Phase 4 — rewrite rules.
    var rewriteRules: @Sendable () -> [RewriteRuleSnapshot]
    var rewriteEnabled: @Sendable () -> Bool
    /// Phase 4 — bandwidth throttling.
    var throttleSettings: @Sendable () -> ThrottleSnapshot
    /// Phase 4 — breakpoints.
    var shouldBreakRequest: @Sendable (String) -> Bool
    var shouldBreakResponse: @Sendable (String) -> Bool
    var awaitBreakpoint: @Sendable (PendingBreakpoint) -> BreakpointDecision

    static let noop = ProxyRuntimeCallbacks(
        onHTTPExchange: { _ in },
        onCONNECT: { _, _, _, _, _, _ in },
        onRemoteClientConnected: { _ in },
        onRemoteClientDisconnected: { _ in },
        mapLocalRules: { [] },
        mapRemoteRules: { [] },
        sslSettings: { SSLProxySettings() },
        leafCertificate: { _ in throw CertificateMailbox.CertificateMailboxError.providerNotConfigured },
        blockListSettings: { BlockListSnapshot() },
        rewriteRules: { [] },
        rewriteEnabled: { false },
        throttleSettings: { .off },
        shouldBreakRequest: { _ in false },
        shouldBreakResponse: { _ in false },
        awaitBreakpoint: { _ in BreakpointDecision(action: .forward, modifiedData: nil) }
    )
}
