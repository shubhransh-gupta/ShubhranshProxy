//
//  SSLProxySettings.swift
//  ShubhranshProxy — Core (Phase 2)
//  Created by Shubhransh Gupta
//

import Foundation

/// Per-domain SSL interception settings (Proxyman-style).
struct SSLProxySettings: Sendable, Equatable, Codable {
    var isEnabled = false
    /// When true, decrypt all HTTPS hosts except `excludedHosts`.
    var interceptAllHosts = false
    /// When true, decrypt all HTTPS from iPhone/Android (non-loopback clients) even if not in `includedHosts`.
    var interceptRemoteDevices = true
    /// Used when `interceptAllHosts` is false — only these hosts are decrypted on Mac.
    var includedHosts: [String] = []
    /// Never decrypt these hosts (e.g. banking, Apple ID).
    var excludedHosts: [String] = []

    enum CodingKeys: String, CodingKey {
        case isEnabled, interceptAllHosts, interceptRemoteDevices, includedHosts, excludedHosts
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        interceptAllHosts = try container.decodeIfPresent(Bool.self, forKey: .interceptAllHosts) ?? false
        interceptRemoteDevices = try container.decodeIfPresent(Bool.self, forKey: .interceptRemoteDevices) ?? true
        includedHosts = try container.decodeIfPresent([String].self, forKey: .includedHosts) ?? []
        excludedHosts = try container.decodeIfPresent([String].self, forKey: .excludedHosts) ?? []
    }

    func shouldIntercept(host: String, clientIPAddress: String? = nil) -> Bool {
        guard isEnabled else { return false }
        let normalized = host.lowercased()
        if excludedHosts.contains(where: { matchesHost(normalized, pattern: $0) }) { return false }
        if interceptAllHosts { return true }
        if interceptRemoteDevices,
           let clientIPAddress,
           !ClientAddressResolver.isLoopback(clientIPAddress) {
            return true
        }
        return includedHosts.contains(where: { matchesHost(normalized, pattern: $0) })
    }

    private func matchesHost(_ host: String, pattern: String) -> Bool {
        let normalizedPattern = pattern.lowercased()
        guard !normalizedPattern.isEmpty else { return false }
        if host == normalizedPattern { return true }
        return host.hasSuffix(".\(normalizedPattern)")
    }
}
