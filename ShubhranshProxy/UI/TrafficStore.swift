//
//  TrafficStore.swift
//  ShubhranshProxy
//  Created by Shubhransh Gupta
//
//  Charles-style session list, Map Local rules, and import/export.
//

import Foundation

private let maxStoredBodyBytes = 512 * 1024

@MainActor
@Observable
final class TrafficStore {
    var exchanges: [HTTPExchangeSnapshot] = []
    var mapLocalRules: [MapLocalRule] = []
    var filterHostSubstring: String = ""
    var filterMethod: String = ""
    var filterStatusCode: String = ""
    var selectedExchangeId: UUID?

    var filteredExchanges: [HTTPExchangeSnapshot] {
        exchanges.filter { ex in
            if !filterHostSubstring.isEmpty, !ex.url.localizedCaseInsensitiveContains(filterHostSubstring) {
                return false
            }
            if !filterMethod.isEmpty, ex.method.caseInsensitiveCompare(filterMethod) != .orderedSame {
                return false
            }
            if !filterStatusCode.isEmpty {
                let want = Int(filterStatusCode) ?? -1
                if ex.responseStatus != want { return false }
            }
            return true
        }
    }

    func clearSession() {
        exchanges.removeAll()
        selectedExchangeId = nil
    }

    func ingest(_ snapshot: HTTPExchangeSnapshot) {
        var s = snapshot
        s.requestBody = Self.cap(s.requestBody, maxStoredBodyBytes)
        if let b = s.responseBody {
            s.responseBody = Self.cap(b, maxStoredBodyBytes)
        }
        exchanges.insert(s, at: 0)
        if exchanges.count > 10_000 {
            exchanges.removeLast(exchanges.count - 10_000)
        }
    }

    func ingestCONNECT(
        authority: String,
        connected: Bool,
        error: String?,
        clientAppName: String? = nil,
        clientIPAddress: String? = nil
    ) {
        ingest(ExchangeSnapshotFactory.connect(
            authority: authority,
            connected: connected,
            error: error,
            clientAppName: clientAppName,
            clientIPAddress: clientIPAddress
        ))
    }

    func addMapRule() {
        mapLocalRules.append(MapLocalRule(pattern: "", isEnabled: false))
    }

    func removeMapRules(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            mapLocalRules.remove(at: index)
        }
    }

    func exportSessionJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        return try encoder.encode(exchanges)
    }

    func importSessionJSON(_ data: Data, merge: Bool) throws {
        let decoder = JSONDecoder()
        let loaded = try decoder.decode([HTTPExchangeSnapshot].self, from: data)
        if merge {
            exchanges.append(contentsOf: loaded)
            exchanges.sort { $0.startedAt > $1.startedAt }
        } else {
            exchanges = loaded
        }
    }

    func exportMapLocalJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(mapLocalRules)
    }

    func importMapLocalJSON(_ data: Data) throws {
        let decoder = JSONDecoder()
        mapLocalRules = try decoder.decode([MapLocalRule].self, from: data)
    }

    private static func cap(_ data: Data, _ max: Int) -> Data {
        if data.count <= max { return data }
        return data.prefix(max)
    }
}
