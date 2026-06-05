//
//  RemoteClientTracker.swift
//  ShubhranshProxy — Features
//
//  Created by Shubhransh Gupta
//

import Foundation
import Observation

/// Tracks phones/tablets as soon as they open a TCP connection to the proxy listener.
@MainActor
@Observable
final class RemoteClientTracker {
    struct Client: Identifiable, Sendable, Equatable {
        var id: String { ip }
        var ip: String
        var lastSeen: Date
        var activeConnections: Int
    }

    private(set) var clients: [String: Client] = [:]

    func noteConnection(from ip: String) {
        guard let normalized = ClientAddressResolver.normalize(ip),
              !ClientAddressResolver.isLoopback(normalized) else { return }
        let now = Date()
        if var existing = clients[normalized] {
            existing.activeConnections += 1
            existing.lastSeen = now
            clients[normalized] = existing
        } else {
            clients[normalized] = Client(ip: normalized, lastSeen: now, activeConnections: 1)
        }
    }

    func noteDisconnection(from ip: String) {
        guard let normalized = ClientAddressResolver.normalize(ip),
              var existing = clients[normalized] else { return }
        existing.activeConnections = max(0, existing.activeConnections - 1)
        existing.lastSeen = Date()
        clients[normalized] = existing
    }

    var connectedIPs: [String] {
        clients.values
            .filter { $0.activeConnections > 0 || Date().timeIntervalSince($0.lastSeen) < 300 }
            .sorted { $0.lastSeen > $1.lastSeen }
            .map(\.ip)
    }

    func reset() {
        clients.removeAll()
    }
}
