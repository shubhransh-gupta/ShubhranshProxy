//
//  SessionStore.swift
//  ShubhranshProxy — Core
//
//  Created by Shubhransh Gupta
//

import Foundation
import Observation

private let maxInMemorySessions = 20_000
private let maxStoredBodyBytes = 512 * 1024
private let mapLocalRulesKey = "ShubhranshProxy.mapLocalRules"
private let mapRemoteRulesKey = "ShubhranshProxy.mapRemoteRules"

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [ProxySession] = []
    var mapLocalRules: [MapLocalRule] = []
    var mapRemoteRules: [MapRemoteRule] = []
    var filterHostSubstring: String = ""
    var filterMethod: String = ""
    var filterStatusCode: String = ""
    var searchText: String = ""
    var selectedSessionId: UUID?
    var isRecording = true

    private var database: SessionDatabase?

    init() {
        database = try? SessionDatabase()
        loadPersistedRules()
    }

    func persistMappingRules() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(mapLocalRules) {
            UserDefaults.standard.set(data, forKey: mapLocalRulesKey)
        }
        if let data = try? encoder.encode(mapRemoteRules) {
            UserDefaults.standard.set(data, forKey: mapRemoteRulesKey)
        }
    }

    private func loadPersistedRules() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: mapLocalRulesKey),
           let rules = try? decoder.decode([MapLocalRule].self, from: data) {
            mapLocalRules = rules
        }
        if let data = UserDefaults.standard.data(forKey: mapRemoteRulesKey),
           let rules = try? decoder.decode([MapRemoteRule].self, from: data) {
            mapRemoteRules = rules
        }
    }

    var filteredSessions: [ProxySession] {
        sessions.filter { session in
            guard SessionDisplayRules.shouldCapture(session) else { return false }
            if !filterHostSubstring.isEmpty,
               !session.host.localizedCaseInsensitiveContains(filterHostSubstring),
               !session.url.localizedCaseInsensitiveContains(filterHostSubstring) {
                return false
            }
            if !filterMethod.isEmpty, session.method.caseInsensitiveCompare(filterMethod) != .orderedSame {
                return false
            }
            if !filterStatusCode.isEmpty {
                let want = Int(filterStatusCode) ?? -1
                if session.responseStatus != want { return false }
            }
            if !searchText.isEmpty, !session.url.localizedCaseInsensitiveContains(searchText) {
                return false
            }
            return true
        }
    }

    var domainTree: [(host: String, count: Int)] {
        let visible = sessions.filter(SessionDisplayRules.shouldCapture)
        let grouped = Dictionary(grouping: visible, by: \.host)
        return grouped.map { ($0.key, $0.value.count) }.sorted { $0.count > $1.count }
    }

    var urlTree: [URLTrafficRow] {
        var counts: [String: Int] = [:]
        var latest: [String: TimeInterval] = [:]
        for session in sessions where SessionDisplayRules.shouldCapture(session) {
            let key = SessionDisplayRules.normalizedURLKey(session.url)
            counts[key, default: 0] += 1
            latest[key] = max(latest[key] ?? 0, session.startedAt)
        }
        return counts.map { URLTrafficRow(url: $0.key, count: $0.value, latestAt: latest[$0.key] ?? 0) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.latestAt > $1.latestAt
            }
    }

    var appTree: [AppTrafficGroup] {
        AppDomainCatalog.buildAppTree(from: sessions.filter(SessionDisplayRules.shouldCapture))
    }

    func clearAll() {
        sessions.removeAll()
        selectedSessionId = nil
        try? database?.deleteAll()
    }

    func ingest(_ snapshot: HTTPExchangeSnapshot) {
        guard isRecording else { return }
        guard SessionDisplayRules.shouldCapture(snapshot) else { return }
        var snap = snapshot
        snap.requestBody = Self.cap(snap.requestBody)
        if var body = snap.responseBody {
            body = Self.cap(body)
            snap.responseBody = body
        }
        let session = ProxySession(snapshot: snap)
        sessions.insert(session, at: 0)
        if sessions.count > maxInMemorySessions {
            sessions.removeLast(sessions.count - maxInMemorySessions)
        }
        try? database?.insert(session)
    }

    func ingestCONNECT(
        authority: String,
        connected: Bool,
        error: String?,
        clientAppName: String? = nil,
        clientIPAddress: String? = nil,
        requestHeaders: String? = nil
    ) {
        guard isRecording else { return }
        let snapshot = ExchangeSnapshotFactory.connect(
            authority: authority,
            connected: connected,
            error: error,
            clientAppName: clientAppName,
            clientIPAddress: clientIPAddress,
            requestHeaders: requestHeaders
        )
        ingest(snapshot)
    }

    func session(id: UUID?) -> ProxySession? {
        guard let id else { return nil }
        return sessions.first { $0.id == id }
    }

    func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(sessions.map { $0.toSnapshot() })
    }

    func importJSON(_ data: Data, merge: Bool) throws {
        let loaded = try JSONDecoder().decode([HTTPExchangeSnapshot].self, from: data)
        importSnapshots(loaded, merge: merge)
    }

    func importSessions(_ imported: [ProxySession], merge: Bool) {
        importSnapshots(imported.map { $0.toSnapshot() }, merge: merge)
    }

    private func importSnapshots(_ loaded: [HTTPExchangeSnapshot], merge: Bool) {
        let mapped = loaded.map(ProxySession.init(snapshot:))
        if merge {
            sessions.append(contentsOf: mapped)
            sessions.sort { $0.startedAt > $1.startedAt }
        } else {
            sessions = mapped
            selectedSessionId = nil
            try? database?.deleteAll()
        }
        for session in mapped {
            try? database?.insert(session)
        }
    }

    func addMapRule() {
        mapLocalRules.append(MapLocalRule(pattern: "", isEnabled: false))
        persistMappingRules()
    }

    func removeMapRules(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            mapLocalRules.remove(at: index)
        }
        persistMappingRules()
    }

    func addMapRemoteRule() {
        mapRemoteRules.append(MapRemoteRule(isEnabled: false))
        persistMappingRules()
    }

    func addMapLocalRule(_ rule: MapLocalRule) {
        mapLocalRules.append(rule)
        persistMappingRules()
    }

    func addMapRemoteRule(_ rule: MapRemoteRule) {
        mapRemoteRules.append(rule)
        persistMappingRules()
    }

    func removeMapLocalRule(id: UUID) {
        mapLocalRules.removeAll { $0.id == id }
        persistMappingRules()
    }

    func removeMapRemoteRule(id: UUID) {
        mapRemoteRules.removeAll { $0.id == id }
        persistMappingRules()
    }

    func removeMapRemoteRules(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            mapRemoteRules.remove(at: index)
        }
        persistMappingRules()
    }

    func exportMapLocalJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(mapLocalRules)
    }

    func importMapLocalJSON(_ data: Data) throws {
        mapLocalRules = try JSONDecoder().decode([MapLocalRule].self, from: data)
        persistMappingRules()
    }

    private static func cap(_ data: Data) -> Data {
        if data.count <= maxStoredBodyBytes { return data }
        return data.prefix(maxStoredBodyBytes)
    }
}
