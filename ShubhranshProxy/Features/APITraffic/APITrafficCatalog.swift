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
    var endpoints: [APIEndpointSummary]

    var id: String { baseURL }
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

    static func path(from urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        var value = url.path
        if value.isEmpty { value = "/" }
        if let query = url.query, !query.isEmpty {
            return "\(value)?\(query)"
        }
        return value
    }

    static func pathWithoutQuery(from urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        var value = url.path
        if value.isEmpty { value = "/" }
        return value
    }

    static func endpointKey(method: String, url: String) -> String {
        "\(method.uppercased()) \(pathWithoutQuery(from: url))"
    }

    static func buildBaseGroups(from sessions: [ProxySession]) -> [APIBaseGroup] {
        let visible = sessions.filter(SessionDisplayRules.shouldCapture)
        var endpointMap: [String: APIEndpointSummary] = [:]
        var baseCounts: [String: Int] = [:]

        for session in visible {
            let base = baseURL(from: session.url)
            let key = endpointKey(method: session.method, url: session.url)
            baseCounts[base, default: 0] += 1

            if var existing = endpointMap[key] {
                existing.count += 1
                if session.startedAt > existing.latestAt {
                    existing.latestAt = session.startedAt
                    existing.fullURL = session.url
                }
                endpointMap[key] = existing
            } else {
                endpointMap[key] = APIEndpointSummary(
                    endpointKey: key,
                    method: session.method.uppercased(),
                    path: pathWithoutQuery(from: session.url),
                    fullURL: session.url,
                    baseURL: base,
                    host: session.host,
                    count: 1,
                    latestAt: session.startedAt
                )
            }
        }

        var groups: [String: [APIEndpointSummary]] = [:]
        for endpoint in endpointMap.values {
            groups[endpoint.baseURL, default: []].append(endpoint)
        }

        return groups.map { base, endpoints in
            let sorted = endpoints.sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.latestAt > $1.latestAt
            }
            return APIBaseGroup(
                baseURL: base,
                host: sorted.first?.host ?? base,
                totalRequests: baseCounts[base, default: 0],
                endpoints: sorted
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
                    endpoints: group.endpoints.filter { isFavorite($0.fullURL) }
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
            mergedByHost[group.host.lowercased()] = group
        }

        for host in pinnedHosts {
            let hostKey = host.lowercased()
            if mergedByHost[hostKey] == nil {
                let baseURL = inferredBaseURL(forHost: host)
                mergedByHost[hostKey] = APIBaseGroup(
                    baseURL: baseURL,
                    host: host,
                    totalRequests: 0,
                    endpoints: []
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
                endpoints: []
            )

            if let live = liveEndpoints.first(where: { SessionDisplayRules.normalizedURLKey($0.fullURL) == normalized }) {
                if !group.endpoints.contains(where: { $0.endpointKey == live.endpointKey }) {
                    group.endpoints.append(live)
                    group.totalRequests += live.count
                }
                group.baseURL = live.baseURL
                group.host = live.host
            } else if !group.endpoints.contains(where: { SessionDisplayRules.normalizedURLKey($0.fullURL) == normalized }) {
                group.endpoints.append(
                    APIEndpointSummary(
                        endpointKey: endpointKey(method: "API", url: url),
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
}
