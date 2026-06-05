//
//  FavoritesStore.swift
//  ShubhranshProxy — Features (Phase 3)
//  Created by Shubhransh Gupta
//

import Foundation
import Observation

@MainActor
@Observable
final class FavoritesStore {
    private static let hostsKey = "ShubhranshProxy.favoriteHosts"
    private static let endpointsKey = "ShubhranshProxy.favoriteEndpoints"

    var favoriteHosts: Set<String> = [] {
        didSet { persist() }
    }

    var favoriteEndpoints: Set<String> = [] {
        didSet { persist() }
    }

    init() {
        load()
    }

    func toggle(_ host: String) {
        let key = host.lowercased()
        if favoriteHosts.contains(key) {
            favoriteHosts.remove(key)
        } else {
            favoriteHosts.insert(key)
        }
    }

    func isFavorite(_ host: String) -> Bool {
        favoriteHosts.contains(host.lowercased())
    }

    func toggleEndpoint(_ url: String) {
        let key = SessionDisplayRules.normalizedURLKey(url)
        if favoriteEndpoints.contains(key) {
            favoriteEndpoints.remove(key)
        } else {
            favoriteEndpoints.insert(key)
        }
    }

    func isFavoriteEndpoint(_ url: String) -> Bool {
        favoriteEndpoints.contains(SessionDisplayRules.normalizedURLKey(url))
    }

    var sortedFavorites: [String] {
        favoriteHosts.sorted()
    }

    private func persist() {
        UserDefaults.standard.set(Array(favoriteHosts), forKey: Self.hostsKey)
        UserDefaults.standard.set(Array(favoriteEndpoints), forKey: Self.endpointsKey)
    }

    private func load() {
        if let savedHosts = UserDefaults.standard.stringArray(forKey: Self.hostsKey) {
            favoriteHosts = Set(savedHosts.map { $0.lowercased() })
        }
        if let savedEndpoints = UserDefaults.standard.stringArray(forKey: Self.endpointsKey) {
            favoriteEndpoints = Set(savedEndpoints)
        }
    }
}
