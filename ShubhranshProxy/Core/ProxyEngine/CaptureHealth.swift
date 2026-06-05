//
//  CaptureHealth.swift
//  ShubhranshProxy — Core
//  Created by Shubhransh Gupta
//

import Foundation

struct CaptureHealth: Sendable, Equatable {
    var isListening: Bool
    var systemProxyRouted: Bool
    var enableSystemProxy: Bool
    var sslReady: Bool
    var sslEnabled: Bool
    var isRecording: Bool
    var listenAddress: String
    var listenPort: Int

    var canInterceptHTTP: Bool { isListening && isRecording }
    var canInterceptHTTPS: Bool { canInterceptHTTP && sslReady && sslEnabled }

    var routingHint: String? {
        guard isListening else { return "Press Start to begin capturing." }
        guard enableSystemProxy else { return nil }
        guard systemProxyRouted else {
            return """
            Mac Wi‑Fi/Ethernet proxy is not set to \(HTTPProxyConfiguration.systemProxyHost):\(listenPort). \
            Click “Retry routing” and approve the password prompt — otherwise Safari and Mac apps will not send traffic here.
            """
        }
        return nil
    }

    var deviceConnectionHint: String? {
        guard isListening else { return nil }
        guard !acceptsRemoteDevices else { return nil }
        return """
        iPhone/Android cannot connect while Listen Host is 127.0.0.1. \
        Set Listen Host to 0.0.0.0 in Proxy settings, restart capture, \
        then set the phone proxy to your Mac’s Wi‑Fi IP on port \(listenPort).
        """
    }

    var acceptsRemoteDevices: Bool {
        HTTPProxyConfiguration.acceptsRemoteDevices(listenHost: listenAddress)
    }

    var sslHint: String? {
        guard isListening else { return nil }
        guard sslEnabled else { return "SSL Proxying is off — only HTTP will be decrypted." }
        guard sslReady else { return "Install and trust the root CA (SSL tab) to decrypt HTTPS." }
        return nil
    }
}

enum CaptureHealthEvaluator {
    static func evaluate(
        isRunning: Bool,
        listenHost: String,
        listenPort: Int,
        systemProxyActive: Bool,
        enableSystemProxy: Bool,
        rootInstalled: Bool,
        rootTrusted: Bool,
        sslEnabled: Bool,
        isRecording: Bool
    ) -> CaptureHealth {
        let verification = SystemProxyManager.verifySystemProxy(
            host: HTTPProxyConfiguration.systemProxyHost,
            port: listenPort
        )
        let routed = !enableSystemProxy || verification.isCorrect || systemProxyActive
        return CaptureHealth(
            isListening: isRunning,
            systemProxyRouted: routed,
            enableSystemProxy: enableSystemProxy,
            sslReady: rootInstalled && rootTrusted,
            sslEnabled: sslEnabled,
            isRecording: isRecording,
            listenAddress: listenHost,
            listenPort: listenPort
        )
    }
}
