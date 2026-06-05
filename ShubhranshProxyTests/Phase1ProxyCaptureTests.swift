//
//  Phase1ProxyCaptureTests.swift
//  ShubhranshProxyTests
//  Created by Shubhransh Gupta
//

import Foundation
import Testing
@testable import ShubhranshProxy

struct Phase1ProxyCaptureTests {
    @Test func capturesPlainHTTPThroughForwardProxy() async throws {
        let port = 19876
        let captured = CapturedExchanges()

        let service = HTTPProxyService()
        let callbacks = ProxyRuntimeCallbacks(
            onHTTPExchange: { snap in
                Task { await captured.append(snap) }
            },
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

        try await service.start(
            configuration: HTTPProxyConfiguration(listenHost: "127.0.0.1", listenPort: port),
            callbacks: callbacks
        )

        try await Task.sleep(for: .milliseconds(150))

        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPPort as String: port,
        ]
        let session = URLSession(configuration: config)
        let (_, response) = try await session.data(from: URL(string: "http://example.com/")!)
        let status = (response as? HTTPURLResponse)?.statusCode
        #expect(status == 200)

        try await Task.sleep(for: .milliseconds(750))

        let snaps = await captured.all()
        await service.stop()

        #expect(!snaps.isEmpty)
        #expect(snaps.contains { $0.method == "GET" && $0.host == "example.com" })
        #expect(snaps.contains { ($0.responseStatus ?? 0) >= 200 })
    }

    @Test func logsCONNECTTunnelWithoutMITM() async throws {
        let port = 19877
        let captured = CapturedExchanges()

        let service = HTTPProxyService()
        let callbacks = ProxyRuntimeCallbacks(
            onHTTPExchange: { _ in },
            onCONNECT: { authority, ok, err, _, _, _ in
                Task { await captured.appendCONNECT(authority: authority, ok: ok, err: err) }
            },
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

        try await service.start(
            configuration: HTTPProxyConfiguration(listenHost: "127.0.0.1", listenPort: port),
            callbacks: callbacks
        )

        try await Task.sleep(for: .milliseconds(150))

        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPPort as String: port,
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPSPort as String: port,
        ]
        let session = URLSession(configuration: config)
        _ = try await session.data(from: URL(string: "https://example.com/")!)

        try await Task.sleep(for: .milliseconds(750))

        let connects = await captured.allCONNECT()
        await service.stop()

        #expect(!connects.isEmpty)
        #expect(connects.contains { $0.authority.contains("example.com") && $0.ok })
    }
}

private actor CapturedExchanges {
    private var http: [HTTPExchangeSnapshot] = []
    private var connect: [(authority: String, ok: Bool, err: String?)] = []

    func append(_ snap: HTTPExchangeSnapshot) {
        http.append(snap)
    }

    func appendCONNECT(authority: String, ok: Bool, err: String?) {
        connect.append((authority, ok, err))
    }

    func all() -> [HTTPExchangeSnapshot] { http }
    func allCONNECT() -> [(authority: String, ok: Bool, err: String?)] { connect }
}
