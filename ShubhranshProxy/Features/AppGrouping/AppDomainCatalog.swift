//
//  AppDomainCatalog.swift
//  ShubhranshProxy — Features
//  Created by Shubhransh Gupta
//
//  Groups related hosts under app/service labels for the sidebar.
//

import Foundation

struct AppTrafficGroup: Identifiable, Sendable {
    var appName: String
    var systemImage: String
    var domains: [(host: String, count: Int)]
    var sessionCount: Int

    var id: String { appName }
}

enum AppDomainCatalog {
    private static let processLabels: [String: (name: String, icon: String)] = [
        "safari": ("Safari", "safari"),
        "com.apple.safari": ("Safari", "safari"),
        "google chrome": ("Google Chrome", "globe"),
        "chrome": ("Google Chrome", "globe"),
        "firefox": ("Firefox", "flame"),
        "slack": ("Slack", "number.square"),
        "slack helper": ("Slack", "number.square"),
        "cursor": ("Cursor", "chevron.left.forwardslash.chevron.right"),
        "proxyman": ("Proxyman", "network"),
        "charles": ("Charles", "network"),
        "xcode": ("Xcode", "hammer"),
        "postman": ("Postman", "paperplane"),
        "spotify": ("Spotify", "music.note"),
        "zoom.us": ("Zoom", "video"),
        "zoom": ("Zoom", "video"),
        "figma": ("Figma", "paintbrush"),
        "notion": ("Notion", "doc.text"),
    ]

    private static let domainRules: [(match: (String) -> Bool, app: String, icon: String)] = [
        ({ $0.contains("google") || $0.contains("gstatic") || $0.contains("googleusercontent") || $0.contains("gvt1") }, "Google", "globe"),
        ({ $0.contains("apple.com") || $0.contains("icloud.com") || $0.contains("mzstatic.com") }, "Apple", "apple.logo"),
        ({ $0.contains("slack") || $0.contains("slack-edge") }, "Slack", "number.square"),
        ({ $0.contains("microsoft") || $0.contains("office.com") || $0.contains("live.com") || $0.contains("azure") }, "Microsoft", "building.2"),
        ({ $0.contains("facebook") || $0.contains("fbcdn") || $0.contains("instagram") || $0.contains("whatsapp") }, "Meta", "person.2"),
        ({ $0.contains("github") || $0.contains("githubusercontent") }, "GitHub", "chevron.left.forwardslash.chevron.right"),
        ({ $0.contains("amazonaws") || $0.contains("cloudfront") }, "AWS", "cloud"),
        ({ $0.contains("lenskart") }, "Lenskart", "eyeglasses"),
    ]

    static func displayName(forProcessName processName: String?) -> String? {
        guard let processName, !processName.isEmpty else { return nil }
        if SessionDisplayRules.isSelfProcess(processName) { return nil }
        let key = processName.lowercased()
        if let hit = processLabels[key] { return hit.name }
        if let hit = processLabels.first(where: { key.contains($0.key) }) { return hit.value.name }
        return processName.replacingOccurrences(of: ".app", with: "").capitalized
    }

    static func systemImage(forAppName appName: String) -> String {
        let key = appName.lowercased()
        if let hit = processLabels.values.first(where: { $0.name.lowercased() == key }) {
            return hit.icon
        }
        if let hit = domainRules.first(where: { $0.app.lowercased() == key }) {
            return hit.icon
        }
        return "app"
    }

    static func inferredApp(for host: String) -> String {
        let normalized = host.lowercased()
        if let rule = domainRules.first(where: { $0.match(normalized) }) {
            return rule.app
        }
        return registrableDomainLabel(normalized)
    }

    static func effectiveAppName(clientAppName: String?, host: String) -> String {
        if let clientAppName, !clientAppName.isEmpty { return clientAppName }
        return inferredApp(for: host)
    }

    static func buildAppTree(from sessions: [ProxySession]) -> [AppTrafficGroup] {
        var appDomains: [String: [String: Int]] = [:]
        var appCounts: [String: Int] = [:]

        for session in sessions where SessionDisplayRules.shouldCapture(session) {
            let app = effectiveAppName(clientAppName: session.clientAppName, host: session.host)
            guard !SessionDisplayRules.isSelfProcess(app) else { continue }
            appCounts[app, default: 0] += 1
            appDomains[app, default: [:]][session.host, default: 0] += 1
        }

        return appCounts.keys.sorted { lhs, rhs in
            let lc = appCounts[lhs, default: 0]
            let rc = appCounts[rhs, default: 0]
            if lc != rc { return lc > rc }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }.map { app in
            let domains = appDomains[app, default: [:]]
                .map { ($0.key, $0.value) }
                .sorted { $0.1 > $1.1 }
            return AppTrafficGroup(
                appName: app,
                systemImage: systemImage(forAppName: app),
                domains: domains,
                sessionCount: appCounts[app, default: 0]
            )
        }
    }

    private static func registrableDomainLabel(_ host: String) -> String {
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return host }
        if parts.count >= 3, parts[parts.count - 2].count <= 3 {
            return parts.suffix(3).joined(separator: ".")
        }
        return parts.suffix(2).joined(separator: ".")
    }
}
