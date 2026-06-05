//
//  HTTPProxyConfiguration.swift
//  ShubhranshProxy — ProxyCore
//  Created by Shubhransh Gupta
//
//  Tunables for the embedded HTTP(S) forward proxy listener.
//

import Foundation

/// Runtime settings for `HTTPProxyService`.
struct HTTPProxyConfiguration: Sendable, Equatable {
    /// Address to bind. Use `0.0.0.0` so iPhone/Android on the same Wi‑Fi can connect.
    var listenHost: String
    /// TCP port for HTTP proxy (browser “HTTP Proxy” setting).
    var listenPort: Int

    /// macOS system proxy always targets loopback — not the bind address.
    static let systemProxyHost = "127.0.0.1"

    static let `default` = HTTPProxyConfiguration(
        listenHost: "0.0.0.0",
        listenPort: 8888
    )

    static func acceptsRemoteDevices(listenHost: String) -> Bool {
        let host = listenHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return host == "0.0.0.0" || host == "::" || host == "*"
    }
}
