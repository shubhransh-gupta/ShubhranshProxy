//
//  ProxyViewModel.swift
//  ShubhranshProxy
//  Created by Shubhransh Gupta
//
//  Bridges SwiftUI to `HTTPProxyService`, traffic store, and Map Local mailbox.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class ProxyViewModel {
    var isRunning = false
    var listenHost = HTTPProxyConfiguration.default.listenHost
    var listenPort = HTTPProxyConfiguration.default.listenPort
    var lastError: String?

    var traffic = TrafficStore()
    private let rulesMailbox = MapLocalRulesMailbox()
    private let service = HTTPProxyService()

    init() {
        syncMapLocalMailbox()
    }

    /// Call after any edit to `traffic.mapLocalRules` so the proxy sees fresh rules.
    func syncMapLocalMailbox() {
        rulesMailbox.replace(traffic.mapLocalRules.map(\.snapshot))
    }

    func start() async {
        lastError = nil
        syncMapLocalMailbox()
        let trafficRef = traffic
        let mailbox = rulesMailbox
        let callbacks = ProxyRuntimeCallbacks(
            onHTTPExchange: { snap in
                Task { @MainActor in
                    trafficRef.ingest(snap)
                }
            },
            onCONNECT: { authority, ok, err, clientApp, clientIP, _ in
                Task { @MainActor in
                    trafficRef.ingestCONNECT(
                        authority: authority,
                        connected: ok,
                        error: err,
                        clientAppName: clientApp,
                        clientIPAddress: clientIP
                    )
                }
            },
            onRemoteClientConnected: { _ in },
            onRemoteClientDisconnected: { _ in },
            mapLocalRules: {
                mailbox.current()
            },
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
        let config = HTTPProxyConfiguration(listenHost: listenHost, listenPort: listenPort)
        do {
            try await service.start(configuration: config, callbacks: callbacks)
            isRunning = true
        } catch {
            lastError = error.localizedDescription
            isRunning = false
        }
    }

    func stop() async {
        await service.stop()
        isRunning = false
    }

    func exportSession() {
        do {
            let data = try traffic.exportSessionJSON()
            ExportHelpers.saveJSON(data, defaultName: "ShubhranshProxy-session.json")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func importSession(replace: Bool) {
        ExportHelpers.pickJSON { data in
            guard let data else { return }
            Task { @MainActor in
                do {
                    try self.traffic.importSessionJSON(data, merge: !replace)
                } catch {
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    func exportMapLocal() {
        do {
            let data = try traffic.exportMapLocalJSON()
            ExportHelpers.saveJSON(data, defaultName: "ShubhranshProxy-maplocal.json")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func importMapLocal() {
        ExportHelpers.pickJSON { data in
            guard let data else { return }
            Task { @MainActor in
                do {
                    try self.traffic.importMapLocalJSON(data)
                    self.syncMapLocalMailbox()
                } catch {
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    var statusLine: String {
        if let lastError {
            return "Error: \(lastError)"
        }
        if isRunning {
            return "Listening on \(listenHost):\(listenPort)"
        }
        return "Stopped"
    }
}
