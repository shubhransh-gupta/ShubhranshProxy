//
//  TrafficDeviceCatalog.swift
//  ShubhranshProxy — Features
//
//  Created by Shubhransh Gupta
//

import Foundation

struct TrafficDeviceGroup: Identifiable, Sendable {
    var id: String
    var displayName: String
    var systemImage: String
    var sessionCount: Int
    var domainGroups: [APIBaseGroup]
}

enum TrafficDeviceCatalog {
    static let macDeviceKey = "mac"

    static func buildDeviceGroups(
        from sessions: [ProxySession],
        connectedRemoteIPs: [String] = []
    ) -> [TrafficDeviceGroup] {
        let visible = sessions.filter(SessionDisplayRules.shouldCapture)
        var grouped: [String: [ProxySession]] = [:]

        for session in visible {
            let key = deviceKey(for: session)
            grouped[key, default: []].append(session)
        }

        for ip in connectedRemoteIPs where !ClientAddressResolver.isLoopback(ip) {
            let key = deviceKey(forRemoteIP: ip, sessions: visible)
            if grouped[key] == nil {
                grouped[key] = []
            }
        }

        if grouped.isEmpty {
            return [
                TrafficDeviceGroup(
                    id: macDeviceKey,
                    displayName: "Mac",
                    systemImage: "desktopcomputer",
                    sessionCount: 0,
                    domainGroups: []
                )
            ]
        }

        return grouped.map { key, deviceSessions in
            TrafficDeviceGroup(
                id: key,
                displayName: displayName(forKey: key, sessions: deviceSessions),
                systemImage: systemImage(forKey: key, sessions: deviceSessions),
                sessionCount: deviceSessions.count,
                domainGroups: APITrafficCatalog.buildBaseGroups(from: deviceSessions)
            )
        }
        .sorted { lhs, rhs in
            if lhs.id == macDeviceKey { return true }
            if rhs.id == macDeviceKey { return false }
            if lhs.sessionCount != rhs.sessionCount { return lhs.sessionCount > rhs.sessionCount }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    static func deviceKey(forRemoteIP ip: String, sessions: [ProxySession]) -> String {
        let normalized = ClientAddressResolver.normalize(ip) ?? ip
        if let session = sessions.first(where: {
            ClientAddressResolver.normalize($0.clientIPAddress) == normalized
        }), let platform = platformPrefix(from: session.requestHeaders) {
            return "\(platform):\(normalized)"
        }
        return "device:\(normalized)"
    }

    static func deviceKey(for session: ProxySession) -> String {
        if let ip = ClientAddressResolver.normalize(session.clientIPAddress),
           !ClientAddressResolver.isLoopback(ip) {
            if let platform = platformPrefix(from: session.requestHeaders) {
                return "\(platform):\(ip)"
            }
            return "device:\(ip)"
        }
        return macDeviceKey
    }

    static func displayName(forKey key: String, sessions: [ProxySession]) -> String {
        if key == macDeviceKey { return "Mac" }
        if key.hasPrefix("ios:") {
            if sessions.contains(where: { userAgent(from: $0.requestHeaders)?.localizedCaseInsensitiveContains("ipad") == true }) {
                return "iPad"
            }
            return "iPhone"
        }
        if key.hasPrefix("android:") { return "Android" }
        if key.hasPrefix("device:") {
            let ip = String(key.dropFirst("device:".count))
            return "Mobile device (\(ip))"
        }
        return key
    }

    static func systemImage(forKey key: String, sessions: [ProxySession]) -> String {
        switch key {
        case macDeviceKey:
            return "desktopcomputer"
        case let key where key.hasPrefix("ios:"):
            if sessions.contains(where: { userAgent(from: $0.requestHeaders)?.localizedCaseInsensitiveContains("ipad") == true }) {
                return "ipad"
            }
            return "iphone"
        case let key where key.hasPrefix("android:"):
            return "smartphone"
        case let key where key.hasPrefix("device:"):
            return "iphone"
        default:
            return "network"
        }
    }

    private static func platformPrefix(from requestHeaders: String) -> String? {
        guard let ua = userAgent(from: requestHeaders)?.lowercased() else { return nil }
        if ua.contains("iphone") || ua.contains("ipad") || ua.contains("ios") {
            return "ios"
        }
        if ua.contains("android") {
            return "android"
        }
        return nil
    }

    static func userAgent(from requestHeaders: String) -> String? {
        for line in requestHeaders.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("user-agent:") else { continue }
            return trimmed.split(separator: ":", maxSplits: 1).dropFirst().joined(separator: ":")
                .trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    static func clientDisplayName(for session: ProxySession) -> String {
        if let app = session.clientAppName, !app.isEmpty {
            return app
        }
        if session.method == "DEVICE", let ip = ClientAddressResolver.normalize(session.clientIPAddress) {
            return "Mobile (\(ip))"
        }
        if session.method == "TLS", let ip = ClientAddressResolver.normalize(session.clientIPAddress) {
            return "Mobile (\(ip)) · TLS failed"
        }
        if let ip = ClientAddressResolver.normalize(session.clientIPAddress),
           !ClientAddressResolver.isLoopback(ip) {
            return displayName(forKey: deviceKey(for: session), sessions: [session])
        }
        return "Mac"
    }
}
