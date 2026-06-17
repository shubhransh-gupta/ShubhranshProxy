//
//  APITrafficCatalog.swift
//  ShubhranshProxy — Features
//
//  Created by Shubhransh Gupta
//

import Foundation

struct APIEndpointSummary: Identifiable, Hashable, Sendable {
    var endpointKey: String
    var method: String
    var path: String
    var fullURL: String
    var baseURL: String
    var host: String
    var count: Int
    var latestAt: TimeInterval

    var id: String { endpointKey }
    var displayTitle: String { "\(method) \(path)" }
}

struct APIBaseGroup: Identifiable, Sendable {
    var baseURL: String
    var host: String
    var totalRequests: Int
    /// Decrypted HTTP/API calls with a visible path.
    var endpoints: [APIEndpointSummary]
    /// CONNECT tunnels before HTTPS decryption (same host often collapses to one row).
    var tunnelRequestCount: Int = 0

    var id: String { host.lowercased() }

    var apiSummaryLabel: String {
        if endpoints.isEmpty, tunnelRequestCount > 0 {
            return "\(tunnelRequestCount) HTTPS tunnel\(tunnelRequestCount == 1 ? "" : "s")"
        }
        if tunnelRequestCount > 0 {
            return "\(endpoints.count) APIs · \(totalRequests) requests (\(tunnelRequestCount) tunnels)"
        }
        return "\(endpoints.count) APIs · \(totalRequests) requests"
    }
}

enum APITrafficCatalog {
    static func baseURL(from urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else {
            return urlString
        }
        let scheme = (url.scheme ?? "https").lowercased()
        if let port = url.port, !isDefaultPort(scheme: scheme, port: port) {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    static func path(from urlString: String, host: String? = nil) -> String {
        let resolved = host.map { canonicalURL(urlString, host: $0) } ?? urlString
        guard let url = URL(string: resolved) else { return resolved }
        var value = url.path
        if value.isEmpty { value = "/" }
        if let query = url.query, !query.isEmpty {
            return "\(value)?\(query)"
        }
        return value
    }

    static func pathWithoutQuery(from urlString: String, host: String? = nil) -> String {
        let resolved = host.map { canonicalURL(urlString, host: $0) } ?? urlString
        guard let url = URL(string: resolved) else { return resolved }
        var value = url.path
        if value.isEmpty { value = "/" }
        return value
    }

    /// Resolves origin-form paths and bare authorities into a full URL for stable endpoint identity.
    static func canonicalURL(_ urlString: String, host fallbackHost: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if var components = URLComponents(string: trimmed), let parsedHost = components.host, !parsedHost.isEmpty {
            components.fragment = nil
            return components.string ?? trimmed
        }

        let host = fallbackHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            var components = URLComponents(string: "https://\(host)\(trimmed)")
            components?.fragment = nil
            return components?.string ?? "https://\(host)\(trimmed)"
        }

        if trimmed.contains(":") && !trimmed.contains("/") && !trimmed.lowercased().hasPrefix("http") {
            var components = URLComponents(string: "https://\(trimmed)")
            components?.fragment = nil
            return components?.string ?? "https://\(trimmed)"
        }

        var components = URLComponents(string: "https://\(host)/\(trimmed)")
        components?.fragment = nil
        return components?.string ?? trimmed
    }

    static func endpointKey(
        method: String,
        url: String,
        host: String? = nil,
        isCONNECT: Bool = false
    ) -> String {
        let upperMethod = method.uppercased()
        let resolvedHost = normalizedHost(host ?? "", url: url)
        if isCONNECT || upperMethod == "CONNECT" {
            let authority = url
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
            return "\(resolvedHost)|CONNECT|\(authority)"
        }
        let canonical = canonicalURL(url, host: resolvedHost)
        let identity = endpointPathIdentity(from: canonical)
        return "\(resolvedHost)|\(upperMethod)|\(identity)"
    }

    /// Path + optional port + query — scheme-agnostic so http/https to the same API share one row.
    private static func endpointPathIdentity(from canonical: String) -> String {
        guard var components = URLComponents(string: canonical) else { return canonical.lowercased() }
        var parts: [String] = []
        if let port = components.port,
           !isDefaultPort(scheme: components.scheme ?? "https", port: port) {
            parts.append(":\(port)")
        }
        var path = components.path
        if path.isEmpty { path = "/" }
        parts.append(path)
        if let query = components.percentEncodedQuery, !query.isEmpty {
            parts.append("?\(query)")
        }
        return parts.joined().lowercased()
    }

    static func buildBaseGroups(from sessions: [ProxySession]) -> [APIBaseGroup] {
        let visible = sessions.filter(SessionDisplayRules.shouldCapture)
        var endpointMap: [String: APIEndpointSummary] = [:]
        var hostCounts: [String: Int] = [:]
        var tunnelCounts: [String: Int] = [:]
        var hostBaseURL: [String: String] = [:]

        for session in visible {
            let hostKey = normalizedHost(session.host, url: session.url)
            hostCounts[hostKey, default: 0] += 1
            let sessionBase = baseURL(from: session.url)
            if hostBaseURL[hostKey] == nil || sessionBase.hasPrefix("https://") {
                hostBaseURL[hostKey] = sessionBase
            }

            if session.isCONNECT || session.method.uppercased() == "CONNECT" {
                tunnelCounts[hostKey, default: 0] += 1
                let key = endpointKey(
                    method: session.method,
                    url: session.url,
                    host: session.host,
                    isCONNECT: true
                )
                if var existing = endpointMap[key] {
                    existing.count += 1
                    if session.startedAt > existing.latestAt {
                        existing.latestAt = session.startedAt
                    }
                    endpointMap[key] = existing
                } else {
                    endpointMap[key] = APIEndpointSummary(
                        endpointKey: key,
                        method: "CONNECT",
                        path: session.url,
                        fullURL: session.url,
                        baseURL: sessionBase,
                        host: session.host.isEmpty ? hostKey : session.host,
                        count: 1,
                        latestAt: session.startedAt
                    )
                }
                continue
            }

            if session.method == "TLS" || session.method == "DEVICE" {
                continue
            }

            let canonical = canonicalURL(session.url, host: hostKey)
            let key = endpointKey(method: session.method, url: session.url, host: session.host)
            if var existing = endpointMap[key] {
                existing.count += 1
                if session.startedAt > existing.latestAt {
                    existing.latestAt = session.startedAt
                    existing.fullURL = canonical
                    existing.baseURL = baseURL(from: canonical)
                    existing.path = path(from: canonical)
                }
                endpointMap[key] = existing
            } else {
                endpointMap[key] = APIEndpointSummary(
                    endpointKey: key,
                    method: session.method.uppercased(),
                    path: path(from: canonical),
                    fullURL: canonical,
                    baseURL: baseURL(from: canonical),
                    host: session.host.isEmpty ? hostKey : session.host,
                    count: 1,
                    latestAt: session.startedAt
                )
            }
        }

        var groups: [String: [APIEndpointSummary]] = [:]
        for endpoint in endpointMap.values {
            let hostKey = normalizedHost(endpoint.host, url: endpoint.fullURL)
            groups[hostKey, default: []].append(endpoint)
        }

        return groups.map { hostKey, endpoints in
            let sorted = endpoints.sorted {
                if $0.method == "CONNECT", $1.method != "CONNECT" { return false }
                if $1.method == "CONNECT", $0.method != "CONNECT" { return true }
                if $0.count != $1.count { return $0.count > $1.count }
                if $0.path != $1.path { return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
                return $0.latestAt > $1.latestAt
            }
            let displayHost = sorted.first(where: { $0.method != "CONNECT" })?.host
                ?? sorted.first?.host
                ?? hostKey
            return APIBaseGroup(
                baseURL: hostBaseURL[hostKey] ?? inferredBaseURL(forHost: displayHost),
                host: displayHost,
                totalRequests: hostCounts[hostKey, default: 0],
                endpoints: sorted,
                tunnelRequestCount: tunnelCounts[hostKey, default: 0]
            )
        }
        .sorted {
            if $0.totalRequests != $1.totalRequests { return $0.totalRequests > $1.totalRequests }
            return $0.baseURL < $1.baseURL
        }
    }

    static func favoriteEndpointGroups(
        from sessions: [ProxySession],
        isFavorite: (String) -> Bool
    ) -> [APIBaseGroup] {
        buildBaseGroups(from: sessions)
            .map { group in
                APIBaseGroup(
                    baseURL: group.baseURL,
                    host: group.host,
                    totalRequests: group.endpoints.filter { isFavorite($0.fullURL) }.reduce(0) { $0 + $1.count },
                    endpoints: group.endpoints.filter { isFavorite($0.fullURL) },
                    tunnelRequestCount: group.tunnelRequestCount
                )
            }
            .filter { !$0.endpoints.isEmpty }
    }

    /// Sidebar pinned section: pinned domains always visible, merged with captured traffic.
    static func buildSidebarPinnedGroups(
        pinnedHosts: [String],
        pinnedEndpointURLs: [String],
        sessionGroups: [APIBaseGroup]
    ) -> [APIBaseGroup] {
        var mergedByHost: [String: APIBaseGroup] = [:]

        for group in sessionGroups {
            let hostKey = group.host.lowercased()
            if var existing = mergedByHost[hostKey] {
                existing.totalRequests += group.totalRequests
                existing.tunnelRequestCount += group.tunnelRequestCount
                if group.baseURL.hasPrefix("https://") {
                    existing.baseURL = group.baseURL
                }
                for endpoint in group.endpoints where !existing.endpoints.contains(where: { $0.endpointKey == endpoint.endpointKey }) {
                    existing.endpoints.append(endpoint)
                }
                mergedByHost[hostKey] = existing
            } else {
                mergedByHost[hostKey] = group
            }
        }

        for host in pinnedHosts {
            let hostKey = host.lowercased()
            if mergedByHost[hostKey] == nil {
                let baseURL = inferredBaseURL(forHost: host)
                mergedByHost[hostKey] = APIBaseGroup(
                    baseURL: baseURL,
                    host: host,
                    totalRequests: 0,
                    endpoints: [],
                    tunnelRequestCount: 0
                )
            }
        }

        let liveEndpoints = sessionGroups.flatMap(\.endpoints)
        for url in pinnedEndpointURLs {
            let normalized = SessionDisplayRules.normalizedURLKey(url)
            let base = baseURL(from: url)
            let displayHost = URL(string: url)?.host ?? hostFromBaseURL(base)
            let hostKey = displayHost.lowercased()
            var group = mergedByHost[hostKey] ?? APIBaseGroup(
                baseURL: base,
                host: displayHost,
                totalRequests: 0,
                endpoints: [],
                tunnelRequestCount: 0
            )

            let matchingLive = liveEndpoints.filter {
                SessionDisplayRules.normalizedURLKey($0.fullURL) == normalized
            }
            if !matchingLive.isEmpty {
                for live in matchingLive where !group.endpoints.contains(where: { $0.endpointKey == live.endpointKey }) {
                    group.endpoints.append(live)
                    group.totalRequests += live.count
                }
                if let newest = matchingLive.max(by: { $0.latestAt < $1.latestAt }) {
                    group.baseURL = newest.baseURL
                    group.host = newest.host
                }
            } else if !group.endpoints.contains(where: { SessionDisplayRules.normalizedURLKey($0.fullURL) == normalized }) {
                group.endpoints.append(
                    APIEndpointSummary(
                        endpointKey: endpointKey(method: "API", url: url, host: displayHost),
                        method: "API",
                        path: pathWithoutQuery(from: url),
                        fullURL: url,
                        baseURL: base,
                        host: displayHost,
                        count: 0,
                        latestAt: 0
                    )
                )
            }
            mergedByHost[hostKey] = group
        }

        let pinnedHostSet = Set(pinnedHosts.map { $0.lowercased() })
        return mergedByHost.values
            .filter { group in
                pinnedHostSet.contains(group.host.lowercased())
                    || group.endpoints.contains {
                        pinnedEndpointURLs.contains(SessionDisplayRules.normalizedURLKey($0.fullURL))
                    }
            }
            .sorted {
                if $0.totalRequests != $1.totalRequests { return $0.totalRequests > $1.totalRequests }
                return $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending
            }
    }

    private static func hostFromBaseURL(_ baseURL: String) -> String {
        URL(string: baseURL)?.host ?? baseURL
    }

    static func inferredBaseURL(forHost host: String) -> String {
        "https://\(host)"
    }

    private static func isDefaultPort(scheme: String, port: Int) -> Bool {
        (scheme == "https" && port == 443) || (scheme == "http" && port == 80)
    }

    private static func normalizedHost(_ host: String, url: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed.lowercased()
        }
        if let parsed = URL(string: url), let parsedHost = parsed.host {
            return parsedHost.lowercased()
        }
        return url.lowercased()
    }
}
