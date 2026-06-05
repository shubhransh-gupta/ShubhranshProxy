//
//  SessionDisplayRules.swift
//  ShubhranshProxy — Features
//  Created by Shubhransh Gupta
//

import Foundation

enum SessionDisplayRules {
    static func shouldCapture(_ snapshot: HTTPExchangeSnapshot) -> Bool {
        if snapshot.method == "DEVICE" {
            return snapshot.clientIPAddress.map { !ClientAddressResolver.isLoopback($0) } ?? false
        }
        if snapshot.method == "TLS" {
            return snapshot.clientIPAddress.map { !ClientAddressResolver.isLoopback($0) } ?? false
        }
        if snapshot.isCONNECT {
            return shouldCaptureConnect(from: snapshot.clientIPAddress, url: snapshot.url)
        }
        if isInternalURL(snapshot.url) { return false }
        if isSelfProcess(snapshot.clientAppName) { return false }
        return !snapshot.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func shouldCapture(_ session: ProxySession) -> Bool {
        if session.method == "DEVICE" {
            return session.clientIPAddress.map { !ClientAddressResolver.isLoopback($0) } ?? false
        }
        if session.method == "TLS" {
            return session.clientIPAddress.map { !ClientAddressResolver.isLoopback($0) } ?? false
        }
        if session.isCONNECT {
            return shouldCaptureConnect(from: session.clientIPAddress, url: session.url)
        }
        if isInternalURL(session.url) { return false }
        if isSelfProcess(session.clientAppName) { return false }
        return !session.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func shouldCaptureConnect(from clientIPAddress: String?, url: String) -> Bool {
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // Show HTTPS tunnels on Mac too — otherwise selective SSL looks like "no traffic".
        return true
    }

    static func isSelfProcess(_ name: String?) -> Bool {
        guard let name else { return false }
        let lowered = name.lowercased()
        return lowered.contains("shubhranshproxy") || lowered == "shubhranshproxy"
    }

    static func isInternalURL(_ url: String) -> Bool {
        let lowered = url.lowercased()
        if lowered.contains("shubhranshproxy") { return true }
        if lowered.hasPrefix("connect ") { return true }
        return false
    }

    static func normalizedURLKey(_ url: String) -> String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct URLTrafficRow: Identifiable, Sendable {
    var url: String
    var count: Int
    var latestAt: TimeInterval

    var id: String { url }
}
